suppressPackageStartupMessages({
  library(shiny)
})

project_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
setwd(project_root)

if (file.exists(file.path("renv", "activate.R"))) {
  source(file.path("renv", "activate.R"))
}

source(file.path("R", "data_fetch.R"))
source(file.path("R", "data_process.R"))
source(file.path("R", "gemini_api.R"))

message("Running live data pipeline...")

raw_data <- fetch_all_runtime_data(start_year = 2000, end_year = 2025)
analysis_dataset <- build_analysis_dataset(
  owid_cases = raw_data$owid_cases,
  owid_mcv1 = raw_data$owid_mcv1,
  who_data = raw_data$who_data,
  population = raw_data$population
) |>
  dplyr::filter(year >= 2000, year <= 2025)

options(
  glhlth562.preloaded_dataset = analysis_dataset,
  glhlth562.preloaded_at = Sys.time()
)

message("Pipeline complete: ", nrow(analysis_dataset), " rows loaded.")
message("Launching Shiny app...")

shiny::runApp(
  appDir = project_root,
  launch.browser = interactive()
)
