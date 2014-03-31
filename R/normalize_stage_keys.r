#' Normalize a reference to stage keys 
#'
#' For example, \code{list('data/one', 2)} would be converted to
#' \code{list('data', list('one')), 2)}.
#'
#' @param keys a list. The keys to normalize.
#' @param stages a list. The stages we're normalizing with respect to.
#' @param parent_key character. A helper for sane recursive error handling.
#'    For example, if we try to reference key \code{foo/bar}, but a recursive
#'    call to \code{normalize_stage_keys} errors when \code{bar} isn't found,
#'    we would still like the error to display the full name (\code{foo/bar}).
#' @param to an indexing parameter. If \code{keys} refers to a single stage,
#'   attempt to find all stages from that stage to this stage (or, if this one comes first,
#'   this stage to that stage). For example, if we have
#'      \code{stages = list(a = list(b = 1, c = 2), d = 3, e = list(f = 4, g = 5))}
#'   where the numbers are some functions, and we call \code{normalize_stage_keys} with
#'   \code{keys = 'a/c'} and \code{to = 'e/f'}, then we would obtain a nested list
#'   of logicals referencing \code{"a/c", "d", "e/f"}.
#' @return a list. The format is nested logicals. For example, if \code{stages}
#'   is
#' \code{list(one = stageRunner$new(new.env(), list(subone = function(cx) 1)),
#'            two = function(cx) 1)} then
#' \code{normalize_stage_keys('one/subone')} would return
#' \code{list(one = list(subone = TRUE), two = FALSE)}.
#' @seealso stageRunner__run
#' @examples
#' \dontrun{
#'    # TODO: Fill in
#' }
normalize_stage_keys <- function(keys, stages, parent_key = "", to = NULL) {
  if (!is.null(to)) {
    stage_key <- normalize_stage_keys(keys, stages)
    to_key <- normalize_stage_keys(to, stages)
    if (!compare_stage_keys(stage_key, to_key)) {
      # stage_key occurs after to_key
      tmp <- stage_key; stage_key <- to_key; to_key <- tmp
    }
    # to go from the first key to the last, populate all the entries
    # after the first TRUE w/ TRUE in stage_key, and all the entries
    # before the first TRUE w/ TRUE in to_key, and then intersect.
    return(special_and_lists(
      boolean_fill(stage_key, forward = TRUE),
      boolean_fill(to_key, forward = FALSE)
    ))
  }

  if (is.null(keys) || length(keys) == 0 || identical(keys, "")) {
    return(if (!is.list(stages) || length(stages) == 1) TRUE
           else rep(list(TRUE), length(stages)))
  }
  if (is.stagerunner(stages)) stages <- stages$stages

  all_logical <- function(x) length(x) > 0 && all(vapply(x,
    function(y) if (is.atomic(y)) is.logical(y) else all_logical(y), logical(1)))
  if (all_logical(keys)) return(keys) # Already normalized

  normalized_keys <- rep(list(FALSE), if (is.list(stages)) length(stages) else 1)
  if (is.numeric(keys) && any(keys < 0)) { # Allow negative indexing
    normalized_keys[keys] <- rep(list(TRUE), length(normalized_keys[keys]))
  } else {
    seqs <- seq_along(if (is.list(stages)) stages else 1)
    lapply(seq_along(keys), function(key_index) {
      key <- keys[[key_index]]
      if (length(key) == 0) stop("Invalid stage key (cannot be of length 0)")
      rest_keys <- key[-1]
      key <- key[[1]]
      if (is.logical(key)) {
        normalized_keys[[key_index]] <<- key
      } else if (is.numeric(key) && key %in% seqs) {
        # Recursively process any potential extra keys
        normalized_keys[[as.integer(key)]] <<-
          if (length(rest_keys) == 0) TRUE
          else normalize_stage_keys(rest_keys, stages[[as.integer(key)]],
                                    parent_key = paste0(parent_key, key, '/'))
      } else if (is.character(key)) {
        # The hard part! Allow things like one/subone/subsubone/etc
        # to reference arbitrarily nested stages.
        if (length(key) == 0) stop("Stage key of length zero")
        key <- strsplit(key, '/')[[1]]
        finds <- grepl(key[[1]], names(stages), ignore.case = TRUE)
        if (length(finds) == 0 || sum(finds) == 0) {
          # if we have a key like foo/3/bar, process the 3 as a numeric index
          if (is.finite(suppressWarnings(tmp <- as.numeric(key[[1]]))) &&
              tmp > 0 && tmp <= length(stages)) finds <- tmp
          else stop("No stage with key '", paste0(parent_key, key[[1]]), "' found")
        } else if (sum(finds) > 1) {
          stop("Multiple stages with key '", paste0(parent_key, key[[1]]),
                 "', found: ", paste0(parent_key, names(stages)[finds], collapse = ', '))
        } else finds <- which(finds) # now an integer of length 1
        normalized_keys[[finds]] <<- special_or_lists(
          normalized_keys[[finds]],
          normalize_stage_keys(append(paste0(key[-1], collapse = '/'), rest_keys), 
            stages[[finds]], paste0(parent_key, key[[1]], '/')))
      } else stop("Invalid stage key")
    })
  }

  normalized_keys
}

