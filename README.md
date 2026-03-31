# Global Measles Incidence and Vaccination Shiny App

This project is a reproducible R Shiny data product for exploring global measles burden and vaccination coverage. It pulls live data at runtime, merges multiple public APIs, and optionally uses the Gemini API to generate short narrative summaries for a selected country and year range.

Code scaffolding and pipeline development were assisted using Codex as a software engineering agent.

## Project Structure

```text
project/
├── app.R
├── R/
│   ├── data_fetch.R
│   ├── data_process.R
│   ├── gemini_api.R
├── README.md
├── .gitignore
└── .Renviron.example
```

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
   - Sends a compact prompt to Gemini via HTTP
4. `app.R`
   - Builds the UI and server logic
   - Supports single-country analysis with optional comparison country
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
GEMINI_MODEL=gemini-2.5-flash
```

Then restart R and run:

```r
shiny::runApp()
```

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
- If Gemini is not configured, the app still runs and shows a configuration message in the summary panel.
