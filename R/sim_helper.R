simulate_round <- function(sim_round,
                           sim_rounds,
                           sims_per_round,
                           schedule,
                           simulations,
                           weeks_to_sim,
                           process_games,
                           ...,
                           tiebreaker_depth,
                           test_week,
                           .debug,
                           playoff_seeds,
                           p,
                           sim_include) {

  # iteration sims
  iter_sims <- sims_per_round * (sim_round - 1) + seq_len(sims_per_round)
  iter_sims <- iter_sims[iter_sims <= simulations]
  iter_sims_num <- length(iter_sims)

  # games have copies per sim
  sched_rows <- nrow(schedule)
  games <- schedule[rep(seq_len(sched_rows), each = iter_sims_num), ] |>
    mutate(sim = rep(iter_sims, sched_rows)) |>
    select(sim, everything())

  # teams starts as divisions data
  teams <- nflseedR::divisions |>
    filter(team %in% schedule$away_team | team %in% schedule$home_team)
  teams <- teams[rep(seq_len(nrow(teams)), iter_sims_num), ] |>
    mutate(sim = rep(iter_sims, each = nrow(teams))) |>
    select(sim, everything())

  # playoff seeds bounds checking
  max_seeds <- teams |>
    group_by(sim, conf) |>
    summarize(count=n()) |>
    ungroup() |>
    pull(count) |>
    min()
  if (playoff_seeds < 1 || playoff_seeds > max_seeds) {
    stop("`playoff_seeds` must be between 1 and ",max_seeds)
  }

  # function to simulate a week
  simulate_week <- function(teams, games, week_num, test_week, ...) {

    # recall old data for comparison
    old_teams <- teams
    old_games <- games |>
      rename(.old_result = result)

    # estimate and simulate games
    return_value <- process_games(teams, games, week_num, ...)

    # testing?
    if (!is.null(test_week) && week_num == test_week) {
      return(return_value)
    }

    # did we get the right data back?
    problems <- c()
    if (typeof(return_value) != "list") {
      problems[length(problems) + 1] <- "the returned value was not a list"
    } else {
      if (!("teams" %in% names(return_value))) {
        problems[length(problems) + 1] <- "`teams` was not in the returned list"
      } else {
        teams <- return_value$teams
        if (!is_tibble(teams)) {
          problems[length(problems) + 1] <- "`teams` was not a tibble"
        } else {
          if (nrow(teams) != nrow(old_teams)) {
            problems[length(problems) + 1] <- paste(
              "`teams` changed from", nrow(old_teams), "to",
              nrow(teams), "rows",
              collapse = " "
            )
          }
          for (cname in colnames(old_teams)) {
            if (!(cname %in% colnames(teams))) {
              problems[length(problems) + 1] <- paste(
                "`teams` column `", cname, "` was removed"
              )
            }
          }
        }
      }
      if (!("games" %in% names(return_value))) {
        problems[length(problems) + 1] <- "`games` was not in the returned list"
      } else {
        games <- return_value$games
        if (!is_tibble(games)) {
          problems[length(problems) + 1] <- "`games` was not a tibble"
        } else {
          if (nrow(games) != nrow(old_games)) {
            problems[length(problems) + 1] <- paste(
              "`games` changed from", nrow(old_games), "to",
              nrow(games), "rows",
              collapse = " "
            )
          }
          for (cname in colnames(old_games)) {
            if (!(cname %in% colnames(games)) && cname != ".old_result") {
              problems[length(problems) + 1] <- paste(
                "`teams` column `", cname, "` was removed"
              )
            }
          }
        }
      }
    }

    # report data structure problems
    problems <- paste(problems, collapse = ", ")
    if (problems != "") {
      stop(
        "During Week ", week_num, ", your `process_games()` function had the ",
        "following issues: ", problems, ". "
      )
    }

    # identify improper results values
    problems <- old_games |>
      inner_join(games, by = intersect(colnames(old_games), colnames(games))) |>
      mutate(problem = case_when(
        week == week_num & is.na(result) ~
        "a result from the current week is missing",
        week != week_num & !is.na(.old_result) & is.na(result) ~
        "a known result outside the current week was blanked out",
        week != week_num & is.na(.old_result) & !is.na(result) ~
        "a result outside the current week was entered",
        week != week_num & .old_result != result ~
        "a known result outside the current week was updated",
        !is.na(.old_result) & is.na(result) ~
        "a known result was blanked out",
        !is.na(result) & result == 0 & game_type != "REG" ~
        "a playoff game resulted in a tie (had result == 0)",
        TRUE ~ NA_character_
      )) |>
      filter(!is.na(problem)) |>
      pull(problem) |>
      unique() |>
      paste(collapse = ", ")

    # report result value problems
    if (problems != "") {
      stop(
        "During Week ", week_num, ", your `process_games()` function had the",
        "following issues: ", problems, ". Make sure you only change results ",
        "when week == week_num & is.na(result)"
      )
    }

    return(list(teams = teams, games = games))
  }

  # simulate remaining regular season games
  for (week_num in weeks_to_sim)
  {
    return_value <-
      simulate_week(teams, games, week_num, test_week, ...)
    if (!is.null(test_week) && week_num == test_week) {
      return(return_value)
    }
    list[teams, games] <- return_value
  }

  #### FIND DIVISIONAL STANDINGS AND PLAYOFF SEEDINGS ####

  standings_and_h2h <- games |>
    compute_division_ranks(
      tiebreaker_depth = tiebreaker_depth,
      .debug = .debug
    )
  standings_and_h2h <- standings_and_h2h |>
    compute_conference_seeds(
      h2h = standings_and_h2h$h2h,
      tiebreaker_depth = tiebreaker_depth,
      .debug = .debug,
      playoff_seeds = playoff_seeds
    )

  teams <- teams |>
    inner_join(standings_and_h2h$standings,
      by = intersect(colnames(teams), colnames(standings_and_h2h$standings))
    )
  h2h_df <- standings_and_h2h$h2h

  #### PLAYOFFS ####
  if (sim_include != "REG"){# sim_include allows us to skip playoff simulation

    # week tracker
    week_num <- games |>
      filter(game_type == "REG") |>
      pull(week) |>
      max()

    # identify playoff teams
    playoff_teams <- teams |>
      filter(!is.na(seed)) |>
      select(sim, conf, seed, team) |>
      arrange(sim, conf, seed)

    # num teams tracker
    num_teams <- playoff_teams |>
      group_by(sim, conf) |>
      summarize(count = n()) |>
      pull(count) |>
      max()

    # bye count (per conference)
    num_byes <- 2^ceiling(log(num_teams, 2)) - num_teams

    # first playoff week
    first_playoff_week <- week_num + 1

    # final week of season (Super Bowl week)
    week_max <- week_num +
      ceiling(log(num_teams * length(unique(playoff_teams$conf)), 2))

    # playoff weeks
    for (week_num in first_playoff_week:week_max) {
      report(paste("Processing Playoffs Week", week_num))

      # seed_numeate games if they don't already exist
      if (!any(games$week == week_num)) {
        # teams playing this round
        add_teams <- playoff_teams |>
          group_by(sim, conf) |>
          slice((2^ceiling(log(num_teams, 2)) - num_teams + 1):num_teams) |>
          mutate(round_rank = row_number()) |>
          ungroup()

        # games to seed_numeate
        add_games <- add_teams |>
          inner_join(add_teams, by = c("sim", "conf")) |>
          filter(round_rank.x > round_rank.y) |>
          filter(round_rank.x + round_rank.y == max(round_rank.x) + 1) |>
          rename(away_team = team.x, home_team = team.y) |>
          mutate(
            week = week_num,
            game_type = case_when(
              week_max - week_num == 3 ~ "WC",
              week_max - week_num == 2 ~ "DIV",
              week_max - week_num == 1 ~ "CON",
              week_max - week_num == 0 ~ "SB",
              TRUE ~ "POST"
            ),
            away_rest = case_when(
              conf == "SB" ~ 14,
              week_num == first_playoff_week + 1 & seed.x <= num_byes ~ 14,
              TRUE ~ 7
            ),
            home_rest = case_when(
              conf == "SB" ~ 14,
              week_num == first_playoff_week + 1 & seed.y <= num_byes ~ 14,
              TRUE ~ 7
            ),
            location = ifelse(conf == "SB", "Neutral", "Home")
          ) |>
          select(-conf, -seed.x, -seed.y, -round_rank.x, -round_rank.y)

        # add to games
        games <- bind_rows(games, add_games)
      }

      # process any new games
      return_value <-
        simulate_week(teams, games, week_num, test_week, ...)
      if (!is.null(test_week) && week_num == test_week) {
        return(return_value)
      }
      list[teams, games] <- return_value

      # record losers
      teams <- games |>
        filter(week == week_num) |>
        double_games() |>
        filter(outcome == 0) |>
        select(sim, team, outcome) |>
        right_join(teams, by = c("sim", "team")) |>
        mutate(exit = ifelse(!is.na(outcome), week_num, exit)) |>
        select(-outcome)

      # if super bowl, record winner
      if (any(playoff_teams$conf == "SB")) {
        # super bowl winner exit is +1 to SB week
        teams <- games |>
          filter(week == week_num) |>
          double_games() |>
          filter(outcome == 1) |>
          select(sim, team, outcome) |>
          right_join(teams, by = c("sim", "team")) |>
          mutate(exit = ifelse(!is.na(outcome), week_num + 1, exit)) |>
          select(-outcome)
      }

      # filter to winners or byes
      playoff_teams <- games |>
        filter(week == week_num) |>
        double_games() |>
        right_join(playoff_teams, by = c("sim", "team")) |>
        filter(is.na(result) | result > 0) |>
        select(sim, conf, seed, team) |>
        arrange(sim, conf, seed)

      # update number of teams
      num_teams <- playoff_teams |>
        group_by(sim, conf) |>
        summarize(count = n()) |>
        pull(count) |>
        max()

      # if at one team per conf, loop once more for the super bowl
      if (num_teams == 1 && !any(playoff_teams$conf == "SB")) {
        playoff_teams <- playoff_teams |>
          mutate(conf = "SB", seed = 1)
        num_teams <- 2
      }
    } # end playoff loop
  }

  #### DRAFT ORDER ####
  if (sim_include == "DRAFT"){
    teams <- standings_and_h2h |>
      compute_draft_order(
        games = games,
        h2h = h2h_df,
        tiebreaker_depth = tiebreaker_depth,
        .debug = .debug
      )
  } else {
    if (!is_tibble(teams)) teams <- teams$standings
    teams$draft_order <- NA_real_
    teams <- teams |>
      dplyr::select(
        dplyr::any_of(c(
          "sim", "team", "conf", "division", "games",
          "wins", "true_wins", "losses", "ties", "win_pct", "div_pct",
          "conf_pct", "sov", "sos", "div_rank", "seed", "exit", "draft_order"
        ))
      )
  }

  p(sprintf("finished sim round %g", sim_round))

  list("teams" = teams, "games" = games)
}
