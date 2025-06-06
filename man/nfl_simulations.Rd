% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/simulations.R
\name{nfl_simulations}
\alias{nfl_simulations}
\title{Simulate an NFL Season}
\usage{
nfl_simulations(
  games,
  compute_results = nflseedR_compute_results,
  ...,
  playoff_seeds = 7L,
  simulations = 10000L,
  chunks = 8L,
  byes_per_conf = 1L,
  tiebreaker_depth = c("SOS", "PRE-SOV", "RANDOM"),
  sim_include = c("DRAFT", "REG", "POST"),
  verbosity = c("MIN", "MAX", "NONE")
)
}
\arguments{
\item{games}{A data frame containing real or simulated game scores. Outside
of simulations, this is simply the output of \link[nflreadr:load_schedules]{nflreadr::load_schedules}.
The following variables are required as a minimum:
\describe{
\item{sim or season}{A season or simulation ID. Normally 1 - n simulated seasons.}
\item{game_type}{One of 'REG', 'WC', 'DIV', 'CON', 'SB' indicating if a
game was a regular season game or one of the playoff rounds.}
\item{week}{The week of the corresponding NFL season.}
\item{away_team}{Team abbreviation of the away team (please see
\code{\link{divisions}} for valid team abbreviations).}
\item{home_team}{Team abbreviation of the home team (please see
\code{\link{divisions}} for valid team abbreviations).}
\item{result}{Equals home score - away score.}
}
If tiebreakers beyond SOS are to be used, then the actual scores of the
home (\code{home_score}) and away (\code{away_score}) teams must also be available.}

\item{compute_results}{Defaults to the nflseedR function \code{nflseedR_compute_results}.
A function to compute results of games. Uses team, schedule, and week number
as arguments. Please see \link{simulations_verify_fct} for further information.}

\item{...}{Additional parameters passed on to the function \code{compute_results}.}

\item{playoff_seeds}{If \code{NULL} (the default), will compute all 16 conference
ranks. This means, the function applies conference tiebreakers to all
conference ranks. For better performance, it is possible to set this to a
value < 16 to make the function skip tiebreakers of those conference ranks.}

\item{simulations}{Equals the number of times the given NFL season shall be simulated}

\item{chunks}{The number of chunks \code{simulations} should be split into
and potentially be processed parallel. This parameter controls the number
of simulations per chunk. There is no obvious way to determine the ideal
number of chunks in advance because there are too many dependencies on the
hardware. Too many chunks can be just as slow as too few. It is therefore
up to the user to determine the optimum number themselves.}

\item{byes_per_conf}{The number of teams with a playoff bye week per conference.
This number influences the number of wildcard games that are simulated.}

\item{tiebreaker_depth}{One of \code{"SOS"}, \code{"PRE-SOV"}, \code{"POINTS"} or \code{"RANDOM"}.
Controls which tiebreakers are to be applied. The implemented tiebreakers
are documented here \url{https://nflseedr.com/articles/tiebreaker.html}.
The values mean:
\itemize{
\item \code{"SOS"} (default): Apply all tiebreakers through Strength of Schedule. If there are
still remaining ties, break them through coin toss.
\item \code{"PRE-SOV"}: Apply all tiebreakers before Strength of Victory. If there are
still remaining ties, break them through coin toss. Why Pre SOV? It's the
first tiebreaker that requires knowledge of how OTHER teams played.
\item \code{"POINTS"}: Apply all tiebreakers through point differential. If there are
still remaining ties, break them through coin toss. This will go beyond SOS
and requires knowledge of points scored and points allowed. As this is not
usually part of season simulations, caution is advised in this case.
These tiebreakers should only be used if the scores are real or are
deliberately simulated.
\item \code{"RANDOM"}: Breaks all tiebreakers with a coin toss. I don't really know,
why I allow this...
}}

\item{sim_include}{One of \code{"REG"}, \code{"POST"}, \code{"DRAFT"} (the default).
Simulation will behave as follows:
\itemize{
\item \code{"REG"}: Simulate the regular season and compute standings, division ranks, and playoff seeds
\item \code{"POST"}: Do \code{"REG"} + simulate the postseason
\item \code{"DRAFT"} (default): Do \code{"POST"} + compute draft order
}}

\item{verbosity}{One of \code{"MIN"}, \code{"MAX"}, or \code{"NONE"} allowing the user
to set the grade of verbosity of status reports. They mean:
\itemize{
\item \code{"MIN"} (default): Prints main steps of the process.
\item \code{"MAX"}: Prints all steps of the complete tiebreaking process.
\item \code{"NONE"}: No status reports at all. Do this to maximize the performance.
}}
}
\value{
An \code{nflseedR_simulation} object containing a list of 6
data frames with the results of all simulated games,
the final standings in each simulated season,
summary statistics across all simulated seasons, and the simulation parameters. For a full list,
please see \href{https://nflseedr.com/articles/articles/nflsim2.html#simulation-output}{the package website}.
}
\description{
Simulate NFL games based on a user provided games/schedule object that
holds matchups with and without results. Missing results are computed using
the argument \code{compute_results} and possible further arguments to
\code{compute_results} in \code{...} (please see \link{simulations_verify_fct} for
further information.).

It is possible to let the function calculate playoff participants
and simulate the post-season.
The code is also developed for maximum performance and allows parallel
computation by splitting the number of simulations into chunks and calling the
appropriate \link[future:plan]{future::plan}.
Progress updates can be activated by calling \link[progressr:handlers]{progressr::handlers}
before the start of the simulations.
Please see the below given section "Details" for further information.
}
\details{
\subsection{More Speed Using Parallel Processing}{

We recommend choosing a default parallel processing method and saving it
as an environment variable in the R user profile to make sure all futures
will be resolved with the chosen method by default.
This can be done by following the below given steps.

First, run the below line and the user profile should be opened automatically.
If you haven't saved any environment variables yet, this will be an empty file.

\if{html}{\out{<div class="sourceCode">}}\preformatted{usethis::edit_r_environ()
}\if{html}{\out{</div>}}

In the opened file add the next line, then save the file and restart your R session.
Please note that this example sets "multisession" as default. For most users
this should be the appropriate plan but please make sure it truly is.

\if{html}{\out{<div class="sourceCode">}}\preformatted{R_FUTURE_PLAN="multisession"
}\if{html}{\out{</div>}}

After the session is freshly restarted please check if the above method worked
by running the next line. If the output is \code{FALSE} you successfully set up a
default non-sequential \code{\link[future:plan]{future::plan()}}. If the output is \code{TRUE} all functions
will behave like they were called with \code{\link[purrr:map]{purrr::map()}} and \strong{NOT} in multisession.

\if{html}{\out{<div class="sourceCode">}}\preformatted{inherits(future::plan(), "sequential")
}\if{html}{\out{</div>}}

For more information on possible plans please see
\href{https://github.com/futureverse/future/blob/develop/README.md}{the future package Readme}.
}

\subsection{Get Progress Updates while Functions are Running}{

nflseedR is able to show progress updates
using \code{\link[progressr:progressor]{progressr::progressor()}} if they are turned on before the function is
called. There are at least two basic ways to do this by either activating
progress updates globally (for the current session) with

\if{html}{\out{<div class="sourceCode">}}\preformatted{progressr::handlers(global = TRUE)
}\if{html}{\out{</div>}}

or by piping the function call into \code{\link[progressr:with_progress]{progressr::with_progress()}}:

\if{html}{\out{<div class="sourceCode">}}\preformatted{nflseedR::nfl_simulations(
  games = nflseedR::sims_games_example,
  simulations = 4,
  chunks = 2
) |>
  progressr::with_progress()
}\if{html}{\out{</div>}}

For more information how to work with progress handlers please see
\link[progressr:progressr]{progressr::progressr}.
}

\subsection{Reproducible Random Number Generation (RNG)}{

It is to be expected that some form of random number generation is required
in the function in argument \code{compute_results}.
For better performance, nflseedR uses the furrr package to parallelize chunks.
furrr functions are guaranteed to generate the exact same sequence of random
numbers given the same initial seed if, and only if, the initial seed is of
the type "L'Ecuyer-CMRG".
So if you want a consistent seed to be used across all chunks, you must ensure
that the correct type is specified in \code{set.seed}, e.g. with the following code

\if{html}{\out{<div class="sourceCode">}}\preformatted{set.seed(5, "L'Ecuyer-CMRG")
}\if{html}{\out{</div>}}

It is sufficient to set the seed before nfl_simulations is called.
To check that the type has been set correctly, you can use the following code.

\if{html}{\out{<div class="sourceCode">}}\preformatted{RNGkind()
"L'Ecuyer-CMRG" "Inversion"     "Rejection"

# Should be a integer vector of length 7
.Random.seed
10407  1157214768 -1674567567 -1532971138 -1249749529  1302496508  -253670963
}\if{html}{\out{</div>}}

For more information, please see the section "Reproducible random number
generation (RNG)" in \link[furrr:furrr_options]{furrr::furrr_options}.
}
}
\examples{
\donttest{
library(nflseedR)

# Activate progress updates
# progressr::handlers(global = TRUE)

# Parallel processing can be activated via the following line
# future::plan("multisession")

sim <- nflseedR::nfl_simulations(
  games = nflseedR::sims_games_example,
  simulations = 4,
  chunks = 2
)

# Overview output
str(sim, max.level = 3)
}
}
\seealso{
The examples \href{https://nflseedr.com/articles/articles/nflsim2.html}{on the package website}

The method \code{\link[=summary.nflseedR_simulation]{summary.nflseedR_simulation()}} that creates a pretty html summary table.
}
