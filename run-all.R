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

create_site_shell <- function(site_dir, app_url) {
  dir.create(site_dir, recursive = TRUE, showWarnings = FALSE)

  index_path <- file.path(site_dir, "index.html")
  html <- sprintf(
    paste(
      "<!doctype html>",
      "<html lang=\"en\">",
      "<head>",
      "  <meta charset=\"utf-8\">",
      "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      "  <title>Global Measles Dashboard</title>",
      "  <style>",
      "    :root { color-scheme: light; }",
      "    body { margin: 0; font-family: Georgia, 'Times New Roman', serif; background: linear-gradient(180deg, #f5efe2 0%%, #ece6dc 100%%); color: #1f2933; }",
      "    .page { min-height: 100vh; display: grid; grid-template-rows: auto 1fr; }",
      "    .header { padding: 24px 32px 16px; background: rgba(255, 255, 255, 0.78); backdrop-filter: blur(10px); border-bottom: 1px solid rgba(31, 41, 51, 0.12); }",
      "    h1 { margin: 0 0 8px; font-size: clamp(2rem, 3vw, 3.2rem); font-weight: 600; }",
      "    p { margin: 0; max-width: 70ch; line-height: 1.5; }",
      "    .actions { margin-top: 14px; display: flex; gap: 12px; flex-wrap: wrap; }",
      "    a { color: #7c2d12; text-decoration: none; font-weight: 600; }",
      "    a:hover { text-decoration: underline; }",
      "    .frame-wrap { padding: 20px; height: calc(100vh - 160px); }",
      "    iframe { width: 100%%; height: 100%%; border: 1px solid rgba(31, 41, 51, 0.12); border-radius: 18px; background: white; box-shadow: 0 20px 45px rgba(31, 41, 51, 0.08); }",
      "    code { background: rgba(124, 45, 18, 0.08); padding: 2px 6px; border-radius: 6px; }",
      "  </style>",
      "</head>",
      "<body>",
      "  <div class=\"page\">",
      "    <div class=\"header\">",
      "      <h1>Global Measles Dashboard</h1>",
      "      <p>This local page embeds the running Shiny app. Keep <code>run-all.R</code> running, then open or refresh this file in your browser.</p>",
      "      <div class=\"actions\">",
      "        <a href=\"%1$s\" target=\"_blank\" rel=\"noreferrer\">Open the app directly</a>",
      "        <a href=\"./index.html\">Refresh this shell page</a>",
      "      </div>",
      "    </div>",
      "    <div class=\"frame-wrap\">",
      "      <iframe src=\"%1$s\" title=\"Global Measles Dashboard\"></iframe>",
      "    </div>",
      "  </div>",
      "</body>",
      "</html>",
      sep = "\n"
    ),
    app_url
  )

  writeLines(html, index_path, useBytes = TRUE)
  index_path
}

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

port <- getOption("glhlth562.shiny_port", httpuv::randomPort())
app_url <- sprintf("http://127.0.0.1:%s", port)
site_dir <- file.path(project_root, "_site")
index_path <- create_site_shell(site_dir, app_url)

message("Pipeline complete: ", nrow(analysis_dataset), " rows loaded.")
message("Generated local site shell: ", normalizePath(index_path, winslash = "/", mustWork = TRUE))
message("Shiny app URL: ", app_url)
message("Launching Shiny app...")

shiny::runApp(
  appDir = project_root,
  host = "127.0.0.1",
  port = port,
  launch.browser = FALSE
)

