# Global Measles Incidence and Vaccination Dashboard

This repository contains an R Shiny data product that ingests live public health data at runtime, builds a country-year analysis dataset, and serves a two-stage web experience: a public-facing landing page followed by an interactive dashboard for exploring measles burden and vaccination coverage. The app can also generate a short narrative summary for the selected country or country comparison using the Gemini API, with a deterministic local fallback when no API key is available.

This README is the technical handoff document for the pipeline. It is written for the next person who needs to run, maintain, or redeploy the project.

## What This Project Produces

The main output is a Shiny app with:

- A landing page that explains what measles is, why vaccination coverage matters, why the interface is useful, and how to enter the dashboard
- A dashboard with four interactive views

- A world choropleth map for either measles incidence per 100,000 or MCV1 coverage
- A time-series view of reported measles cases, MCV1 coverage, and MCV2 coverage
- A scatterplot of MCV1 coverage versus measles incidence
- A summary table of the latest available country metrics

The app also produces:

- A narrative summary for the selected country or country pair
- A local HTML shell at `_site/index.html` when `run-all.R` is used
- An optional shinyapps.io deployment via `deploy_shinyapps.R`, where the root app URL opens on the landing page first

## Repository Structure

```text
project/
├── app.R
├── run-all.R
├── deploy_shinyapps.R
├── README.md
├── renv.lock
├── R/
│   ├── data_fetch.R
│   ├── data_process.R
│   └── gemini_api.R
└── _site/
```

## Pipeline Summary

The runtime pipeline is:

1. `R/data_fetch.R` pulls live data from OWID, WHO, and the World Bank.
2. `R/data_process.R` standardizes, joins, and derives analysis fields.
3. `R/gemini_api.R` builds the summary payload and either calls Gemini or falls back to a local summary generator.
4. `app.R` loads the dataset into Shiny, renders a landing page at first load, exposes filtering controls in the dashboard view, and renders the dashboard outputs.
5. `run-all.R` optionally preloads the dataset before app startup and creates a local shell page in `_site/`.

## 1. Where The Data Comes From

This project does not read from a local database. It builds its analytic dataset from live remote sources each time the app is started or refreshed.

### Our World in Data

Used for:

- Reported measles cases
- MCV1 vaccination coverage
- Child measles prevalence
- Vaccine attitudes
- Region lookup data

Endpoints used by the code:

- CSV: `https://ourworldindata.org/grapher/reported-cases-of-measles.csv`
- CSV: `https://ourworldindata.org/grapher/share-of-children-vaccinated-against-measles.csv`
- JSON API pattern: `https://api.ourworldindata.org/v1/indicators/{indicator_id}.{suffix}.json`

Indicator IDs currently used:

- `1182306` for child measles prevalence
- `1075290` for vaccine attitudes
- `900801` for OWID region labels

### WHO Global Health Observatory API

Used for:

- MCV1 coverage
- MCV2 coverage
- Reported measles cases

Endpoint pattern:

- `https://ghoapi.azureedge.net/api/{INDICATOR_CODE}`

Indicator codes currently used:

- `WHS8_110` for MCV1 coverage
- `MCV2` for MCV2 coverage
- `WHS3_62` for reported measles cases

### World Bank API

Used for:

- Annual population by country

Endpoint used:

- `https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL`

Population is used to calculate measles incidence per 100,000.

### User Input

The dashboard accepts user selections at runtime:

- Primary country
- Optional comparison country
- Year range
- Map year
- Map metric
- Manual refresh trigger for live data reload

These inputs do not create new source data, but they determine which subset of the processed data is rendered and summarized.

### Gemini API

Used for:

- Optional narrative summary generation from the processed selected-country subset

Endpoint pattern used by the app:

- Base URL: `https://generativelanguage.googleapis.com/v1beta`
- Path appended at runtime: `models/gemini-2.5-flash:generateContent`

Gemini is not required for the dashboard to run. If `GEMINI_API_KEY` is missing or the request fails, the app falls back to a local rule-based summary.

## 2. How The Data Is Ingested

### Packages Used For Ingestion

The ingestion layer uses:

- `httr2` for HTTP requests
- `jsonlite` for JSON parsing
- `readr` for CSV parsing
- `tibble` and `dplyr` for shaping returned records

### Request Construction

All runtime fetch helpers live in `R/data_fetch.R`.

- `fetch_text_response()` builds the base `httr2` request, applies a user agent, optional query parameters, and a 60-second timeout.
- `fetch_json_response()` parses JSON with `jsonlite::fromJSON(..., simplifyVector = TRUE, flatten = TRUE)`.
- `fetch_csv_response()` reads CSV text via `readr::read_csv()`.

Development decision carried into this project: before building any external request, inspect the endpoint directly first. In practice that means verifying the URL, the returned field names, the pagination structure, and the exact columns needed downstream before changing the code.

### Authentication

Authentication requirements differ by source:

- OWID: no API key required
- WHO GHO: no API key required
- World Bank: no API key required
- Gemini: requires `GEMINI_API_KEY` in the environment

The app reads the Gemini key with `Sys.getenv("GEMINI_API_KEY")`.

### Formats Returned

The pipeline ingests two main formats:

- CSV from OWID grapher endpoints
- JSON from OWID indicator endpoints, WHO GHO, World Bank, and Gemini

WHO responses may be paginated. The code follows `@odata.nextLink` until all pages are collected.

World Bank responses are paginated arrays. The code reads page 1 metadata, determines the total number of pages, and fetches the remaining pages.

### Ingestion Functions

Primary fetch functions:

- `fetch_owid_measles_cases()`
- `fetch_owid_mcv1()`
- `fetch_owid_measles_prevalence_children()`
- `fetch_owid_vaccine_attitudes()`
- `fetch_owid_regions()`
- `fetch_who_indicator()`
- `fetch_who_measles_data()`
- `fetch_world_bank_population()`
- `fetch_all_runtime_data()`

`fetch_all_runtime_data()` is the top-level runtime entry point and returns a list of source tables.

## 3. How The Data Is Processed

All core processing lives in `R/data_process.R`.

### Standardization

The pipeline standardizes data to a country-year grain using:

- `iso3` country codes
- `year`
- standardized `location` values

If a country name is missing after joins, the code backfills it from ISO3 using `countrycode`.

### Joining Strategy

`build_analysis_dataset()` performs the main joins:

1. OWID cases and OWID MCV1 are joined by `location`, `iso3`, and `year`.
2. WHO measles cases, WHO MCV1, and WHO MCV2 are joined by `iso3` and `year`.
3. OWID data and WHO data are joined by `iso3` and `year`.
4. Population data are joined by `iso3` and `year`.

The project prefers WHO values when both WHO and OWID contain the same metric:

- `measles_cases = coalesce(measles_cases_who, measles_cases_owid)`
- `mcv1 = coalesce(mcv1_who, mcv1_owid)`

### Derived Fields

The processed dataset includes the following derived fields:

- `measles_incidence_per_100k`
- `vaccination_gap`
- `cases_yoy_pct_change`

These are computed as:

- Incidence: `(measles_cases / population) * 100000`
- Vaccination gap: `100 - mcv1`
- Year-over-year percent change in cases using lagged case counts within country

### Filtering And Validation

The app uses additional processing helpers to make the dashboard stable:

- `available_country_choices()` restricts selectable countries to those with enough non-missing coverage and case data
- `filter_country_data()` subsets the processed data by selected countries and year range
- `validate_country_subset()` blocks views when the selected subset has too little usable data
- `summarise_country_metrics()` builds the table shown in the dashboard
- `create_trend_plot_data()`, `create_scatter_plot_data()`, and `create_map_data()` create view-specific analytic slices

### Summary Generation

`R/gemini_api.R` does not send raw API payloads from the source systems to Gemini. It first builds a structured summary payload from the processed selected-country subset:

- Country-level trend summaries
- Start and end years
- Average coverage, cases, and incidence
- Peak-case year
- Largest year-over-year jump
- Coverage-versus-incidence relationship signals
- Yearly metrics for the selected countries

If Gemini is available, the app sends that structured payload to `gemini-2.5-flash` and extracts the first text response. If Gemini is unavailable, the app uses `generate_local_summary()` to produce a deterministic narrative from the same processed subset.

## 4. What The Output Is

### Dashboard

`app.R` serves a Shiny app titled `Global Measles Incidence and Vaccination Dashboard`.

### Landing Page

The app now opens on an `Overview` tab that acts as the landing page for the shinyapps.io URL and local runs. That page includes:

- A short explanation of what measles is
- A short explanation of vaccination coverage and why it matters
- Context for why comparing measles burden against vaccine coverage is useful
- A brief summary of the available dashboard tools
- A direct `Open the interactive dashboard` button that switches the user into the existing app interface

The navigation tabs remain visible, so users can also click `Dashboard` directly.

Tabs rendered by the app:

- `Overview`
- `World Map`
- `Time Series`
- `Scatterplot`
- `Summary Table`

The world map uses `leaflet` and `rnaturalearth` geometry. The time series and scatterplot use `ggplot2` rendered through `plotly`.

### Summary Text

The summary panel underneath the tabs displays:

- A short explanatory note about MCV1 and MCV2
- A Gemini-generated summary when `GEMINI_API_KEY` is configured and the request succeeds
- A local fallback summary otherwise

### Local Browser Shell

When `run-all.R` is used, the project creates `_site/index.html`, which embeds the running app in an iframe and links to the direct local Shiny URL. This is a convenience output for demoing the app locally.

### Dashboard Entry

The original analytic interface is preserved under the `Dashboard` tab. No analytic controls or outputs were removed; the landing page is an additional first-load layer in front of the existing dashboard.

### Deployment Output

`deploy_shinyapps.R` deploys the app to shinyapps.io and prints the public URL after deployment. When the deployed URL is opened, users land on the `Overview` tab first and can enter the analytic interface through the button on that page or by clicking the `Dashboard` tab.

## 5. How Someone Else Could Run It

### Environment Requirements

- R 4.5.1 is the version recorded in `renv.lock`
- Internet access is required because the app fetches live remote data at runtime
- A Gemini API key is optional

### Files To Know

- `app.R`: main Shiny app
- `run-all.R`: preload data, create local shell page, then launch the app
- `deploy_shinyapps.R`: deploy to shinyapps.io
- `R/data_fetch.R`: all runtime data ingestion
- `R/data_process.R`: joins and derived fields
- `R/gemini_api.R`: narrative summary logic
- `renv.lock`: reproducible package snapshot

### Dependency Setup

Preferred setup:

```r
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::restore()
```

If you do not want to use `renv`, install the packages required by the app and deployment script:

```r
install.packages(c(
  "shiny", "dplyr", "ggplot2", "plotly", "leaflet", "sf",
  "rnaturalearth", "rnaturalearthdata", "scales", "countrycode",
  "httr2", "jsonlite", "readr", "tibble", "tidyr", "rsconnect", "renv"
))
```

### Environment Variables

Create a `.Renviron` file in the project root. `.gitignore` already excludes it.

Example:

```text
GEMINI_API_KEY=your-api-key-here
```

If this variable is absent, the dashboard still runs and summary text falls back to the local generator.

### Running Locally

Option 1: run the app directly from R:

```r
shiny::runApp()
```

Option 2: run the full startup script from the project root:

```bash
Rscript run-all.R
```

`run-all.R` will:

1. Activate `renv` if `renv/activate.R` exists.
2. Fetch live data.
3. Build the processed dataset.
4. Store the dataset in R options for preloading.
5. Create `_site/index.html`.
6. Launch the app on a random local port.

When the app opens in a browser, the first visible page is the `Overview` landing page. Users can then move into the existing interactive dashboard from that page.

### Refreshing Data

The dashboard fetches live data at startup. Users can also click `Refresh Live Data` in the sidebar to rerun the ingestion and processing pipeline during the session.

### Deployment To shinyapps.io

From the project root:

```bash
Rscript deploy_shinyapps.R
```

The deployment script:

1. Detects the project directory.
2. Creates a local `.Rlibs` directory if needed.
3. Installs `rsconnect` locally if it is missing.
4. Deploys `app.R`, `R/`, and `renv.lock`.
5. Prints the public shinyapps.io URL.

Note on `rsconnect/`: this repository does not currently store a committed `rsconnect/` metadata folder. The landing page behavior is implemented directly in `app.R`, so the shinyapps.io URL itself opens on the landing page after deployment without requiring committed deployment metadata.

Maintenance note: the current deployment script stores shinyapps.io credentials directly in `deploy_shinyapps.R`. That works for deployment, but it is not a good long-term secret-management pattern. Move those credentials into environment variables or Posit-managed account configuration before sharing or reusing this code outside the course setting.

## Maintenance Notes From Development

These are implementation decisions already reflected in the code and should be kept in mind when modifying the pipeline:

- Keep the README focused on the technical pipeline, not a narrative methods section.
- Document the source URL before describing how a request is assembled.
- Inspect source fields and pagination behavior before adding or changing request logic.
- Parse JSON responses with `jsonlite::fromJSON(..., simplifyVector = TRUE)`, and use `flatten = TRUE` when nested records should become tabular columns.
- Keep the app functional without Gemini by preserving the local summary fallback.
- Keep the runtime data flow live unless there is a deliberate decision to switch to cached or stored source files.

## Operational Caveats

- The pipeline depends on external services being available at runtime.
- WHO and World Bank pagination behavior could change and would need corresponding updates in `R/data_fetch.R`.
- The map currently visualizes incidence per 100,000 or MCV1 coverage only, even though the pipeline also fetches MCV2, vaccine attitudes, regions, and child measles prevalence.
- `build_analysis_dataset()` currently uses OWID child prevalence, vaccine attitudes, and region data only as fetched inputs, not as dashboard-facing fields. They are available for future expansion but are not part of the current rendered outputs.
