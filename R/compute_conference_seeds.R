#' Compute NFL Playoff Seedings using Game Results and Divisional Rankings
#'
#' @inheritParams compute_division_ranks
#' @param teams The division standings data frame as computed by
#'  \code{\link{compute_division_ranks}}
#' @param playoff_seeds Number of playoff teams per conference (increased
#'  in 2020 from 6 to 7).
#'
#' @returns A data frame of division standings including playoff seeds and the
#'   week in which the season ended for the respective team (\code{exit}).
#' @returns A list of two data frames:
#'  \describe{
#'  \item{standings}{Division standings including playoff seeds.}
#'  \item{h2h}{A data frame that is used for head-to-head tiebreakers across the
#'  tie-breaking functions.}
#'  }
#' @seealso The examples [on the package website](https://nflseedr.com/articles/articles/nflseedR.html)
#' @export
#' @examples
#' \donttest{
#' # Change some options for better output
#' old <- options(list(digits = 3, tibble.print_min = 64))
#' library(dplyr, warn.conflicts = FALSE)
#'
#' try({#to avoid CRAN test problems
#' s <- nflseedR::load_sharpe_games() |>
#'   dplyr::filter(season %in% 2019:2020) |>
#'   dplyr::select(sim = season, game_type, week, away_team, home_team, result) |>
#'   nflseedR::compute_division_ranks()
#'   nflseedR::compute_conference_seeds(s, h2h = s$h2h) |>
#'   purrr::pluck("standings")
#' })
#'
#' # Restore old options
#' options(old)
#' }
compute_conference_seeds <- function(teams,
                                     h2h = NULL,
                                     tiebreaker_depth = 3,
                                     .debug = FALSE,
                                     playoff_seeds = 7) {
  # catch invalid input
  if (!isTRUE(tiebreaker_depth %in% 1:3)) {
    cli::cli_abort(
      "The argument {.arg tiebreaker_depth} has to be \\
      a single value in the range of 1-3!"
    )
  }

  if (!is_tibble(teams)) teams <- teams$standings

  if (!any((names(teams) %in% "div_rank")) | !is.data.frame(teams)) {
    cli::cli_abort(
      "The argument {.arg teams} has to be a data frame including \\
      the variable {.val div_rank} as computed by {.fn compute_division_ranks}!"
    )
  }

  if(is.null(h2h) & tiebreaker_depth > TIEBREAKERS_NONE){
    cli::cli_abort(
      "You asked for tiebreakers but the argument {.arg h2h} is {.val NULL}. \\
       Did you forget to pass the {.val h2h} data frame? It is computed with \\
       the function {.fn compute_division_ranks}."
    )
  }

  teams <- teams |>
    mutate(conf_rank = NA_real_)

  # seed loop
  for (seed_num in seq_len(playoff_seeds))
  {
    report("Calculating seed #{seed_num}")

    # find teams at this seed
    update <- teams |>
      filter(is.na(conf_rank)) |>
      mutate(div_winner = (div_rank == 1)) |>
      group_by(sim, conf) |>
      filter(div_winner == max(div_winner)) |>
      filter(win_pct == max(win_pct)) |>
      mutate(conf_rank = ifelse(n() == 1, as.numeric(seed_num), conf_rank)) |>
      ungroup() |>
      group_by(sim, conf, division) |>
      mutate(div_best_left = (div_rank == min(div_rank))) |>
      ungroup() |>
      break_conference_ties(seed_num, h2h = h2h, tb_depth = tiebreaker_depth, .debug = .debug)

    # store updates
    teams <- teams |>
      left_join(update, by = c("sim", "team")) |>
      mutate(conf_rank = ifelse(!is.na(new_rank), new_rank, conf_rank)) |>
      select(-new_rank)
  } # end conference rank loop

  # rename conference rank to seed
  teams <- teams |>
    rename(seed = conf_rank) |>
    mutate(exit = ifelse(is.na(seed), max_reg_week, NA_real_)) |>
    select(-max_reg_week)

  list(
    "standings" = tibble::as_tibble(teams),
    "h2h" = tibble::as_tibble(h2h)
  )
}
