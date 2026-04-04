# Global Measles Incidence and Vaccination Shiny App

This project is a reproducible R Shiny data product for exploring global measles burden and vaccination coverage. It pulls live data at runtime, merges multiple public APIs, and optionally uses the Gemini API to generate short narrative summaries for a selected country and year range.

Code scaffolding and pipeline development were assisted using Codex as a software engineering agent.

## Session Documentation Notes

Changes made during this session should also be reflected in this `README.md`.

- Add the API URL before describing how each external request is built.
- Include a short section on how to inspect available parameters or fields before constructing a request.
- When parsing JSON in project code, use `jsonlite::fromJSON(..., simplifyVector = TRUE)` and add `flatten = TRUE` when the response has nested record structures that should be flattened into tabular columns.

## Project Structure

```text
project/
├── glhlth562-final.Rproj
├── run-all.R
├── app.R
├── _site/                 # generated locally by run-all.R
├── R/
│   ├── data_fetch.R
│   ├── data_process.R
│   ├── gemini_api.R
├── README.md
├── .gitignore
└── .Renviron.example
```

## API Reference and Parameter Discovery

Before building any request in this project, confirm the endpoint shape, path parameters, query parameters, and returned fields from the source itself.

### Our World in Data Grapher CSVs

- Measles cases CSV: <https://ourworldindata.org/grapher/reported-cases-of-measles.csv>
- MCV1 coverage CSV: <https://ourworldindata.org/grapher/share-of-children-vaccinated-against-measles.csv>
- How to inspect available fields before requesting:
  - Open the CSV URL directly and review the header row.
  - Confirm the exact measure column names used by the app before selecting or renaming columns in `R/data_fetch.R`.

### WHO Global Health Observatory API

- API base pattern: <https://ghoapi.azureedge.net/api/{INDICATOR_CODE}>
- Indicators used by this project:
  - `WHS8_110` for MCV1 coverage
  - `MCV2` for MCV2 coverage
  - `WHS3_62` for reported measles cases
- How to inspect available parameters and fields before requesting:
  - Open an indicator endpoint directly to inspect the JSON schema and available columns in `value`.
  - Review pagination fields such as `@odata.nextLink` before implementing loops.
  - Validate filterable fields like `SpatialDim`, `SpatialDimType`, `TimeDim`, and `TimeDimType` before adding request logic.

### World Bank API

- Population indicator endpoint: <https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL>
- Query parameters used by this project:
  - `format=json`
  - `per_page=20000`
  - `page=<page_number>`
- How to inspect available parameters and fields before requesting:
  - Start with the indicator endpoint and inspect the metadata object returned in the first array element.
  - Confirm pagination fields such as `page`, `pages`, `per_page`, and `total`.
  - Confirm the data fields used downstream, including `country.value`, `countryiso3code`, `date`, and `value`.

### Gemini API

- Request base URL: <https://generativelanguage.googleapis.com/v1beta>
- Request path appended by the app: `models/gemini-2.5-flash:generateContent`
- Environment variables used by this project:
  - `GEMINI_API_KEY`
- Request body sections used by this project:
  - `contents`
- How to inspect available parameters before requesting:
  - Confirm the `generateContent` path and model before building the request.
  - Review the request body structure in `R/gemini_api.R` before adding fields.
  - Check the response shape for `candidates`, `content`, and `parts` before extracting text.
- Prompt template used by the app:
  - `You are a public health analyst. Based on the following data for [country] from [start year] to [end year], summarize the relationship between measles cases and vaccination coverage. Highlight any notable increases in cases and explain whether they may be associated with declines in vaccination. Keep the explanation in 200 words and accessible to a general audience.`

## Data Sources

- Our World in Data grapher CSVs
  - Reported measles cases
  - MCV1 vaccination coverage
- WHO Global Health Observatory API
  - `WHS8_110` for MCV1 coverage
  - `MCV2` for MCV2 coverage
  - `WHS3_62` for reported measles cases
- World Bank API
  - `SP.POP.TOTL` for annual population, used to compute incidence per 100,000
- Gemini API
  - Generates a concise country summary from a summarized analytic payload, not the raw joined dataset

## Pipeline Overview

1. `R/data_fetch.R`
   - Downloads live OWID CSVs with `httr2`
   - Pulls WHO GHO indicator tables with `httr2` and `jsonlite`
   - Parses JSON with `simplifyVector = TRUE` and `flatten = TRUE`
   - Pulls World Bank population data for incidence calculation
2. `R/data_process.R`
   - Standardizes countries to ISO3
   - Aligns datasets by `iso3 + year`
   - Uses `full_join()` to merge sources
   - Creates:
     - `measles_incidence_per_100k`
     - `vaccination_gap`
     - `cases_yoy_pct_change`
3. `R/gemini_api.R`
   - Summarizes the selected subset
   - Calls Gemini with `request("https://generativelanguage.googleapis.com/v1beta")`, `req_url_path_append()`, and `req_url_query(key = GEMINI_API_KEY)`
   - Sends Gemini both selected countries when a comparison country is chosen, along with per-country trend summaries and yearly metrics for time-based interpretation
   - Falls back to a deterministic local summary when `GEMINI_API_KEY` is not set or the Gemini request fails
   - Parses Gemini JSON responses with `simplifyVector = TRUE`
4. `app.R`
   - Builds the UI and server logic
   - Supports single-country analysis with optional comparison country
   - Generates the AI summary from the same selected-country subset used by the plots, so the text can compare countries when a comparison is selected
   - Uses `isolate()` inside the startup `session$onFlushed()` callback so the initial data load does not read a reactive value outside a reactive consumer
   - Renders plotly versions of ggplot time-series and scatter plots

## Setup

Install required packages:

```r
install.packages(c(
  "shiny", "httr2", "jsonlite", "readr", "dplyr", "tidyr",
  "ggplot2", "plotly", "countrycode", "scales", "purrr", "renv"
))
```

Create `.Renviron` from `.Renviron.example` and add your Gemini key:

```text
GEMINI_API_KEY=your-api-key-here
```

Then restart R and run:

```r
shiny::runApp()
```

Or run the full pipeline plus app startup from the project root:

```bash
Rscript run-all.R
```

The project now includes [_site/index.html](/Users/lindseycobb/Desktop/562final/_site/index.html) as the local shell page for the app. `run-all.R` overwrites that file at startup so it points at the active localhost Shiny URL. Keep the `Rscript run-all.R` process running, then open or refresh `_site/index.html` in your browser.

If you use RStudio, open `glhlth562-final.Rproj` to load the project with the repository root as the working directory.

## Reproducibility

- API keys are read from `.Renviron`
- `.gitignore` excludes `.Renviron`, `.Rhistory`, and `.RData`
- `renv` can be initialized with:

```r
renv::init()
renv::snapshot()
```

## GitHub Setup

Initialize the repository locally:

```bash
git init
git add .
git commit -m "Initial commit: Shiny measles + vaccine hesitancy app"
git branch -M main
```

Connect to your shared remote and push:

```bash
git remote add origin https://github.com/<USERNAME>/<REPO_NAME>.git
git push -u origin main
```

## Notes

- The original OWID URL in the prompt (`https://ourworldindata.org/measles.csv`) no longer resolves. The app uses the live OWID grapher CSV endpoints instead.
- WHO data are used when available and are merged with OWID by `iso3` and `year`.
- If Gemini is not configured, the app still runs and shows a built-in summary in the summary panel.
