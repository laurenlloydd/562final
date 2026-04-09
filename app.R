required <- c(
  "shiny",
  "dplyr",
  "ggplot2",
  "plotly",
  "leaflet",
  "sf",
  "rnaturalearth",
  "rnaturalearthdata",
  "scales",
  "countrycode",
  "httr2",
  "jsonlite",
  "readr",
  "tibble",
  "tidyr"
)
missing <- required[!sapply(required, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  warning(paste("Missing packages:", paste(missing, collapse = ", ")))
}

library(shiny)
library(dplyr)
library(ggplot2)
library(plotly)
library(leaflet)
library(sf)
library(rnaturalearth)
library(rnaturalearthdata)
library(scales)
library(countrycode)
library(httr2)
library(jsonlite)
library(readr)
library(tibble)
library(tidyr)

source(file.path("R", "data_fetch.R"))
source(file.path("R", "data_process.R"))
source(file.path("R", "gemini_api.R"))

world_geometry <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") |>
  dplyr::transmute(
    iso3 = as.character(iso_a3),
    country_name = as.character(admin),
    geometry
  )

landing_page_ui <- tagList(
  div(
    class = "landing-shell",
    div(
      class = "landing-hero",
      fluidRow(
        column(
          width = 8,
          tags$span(class = "hero-kicker", "WHO measles overview"),
          h1("Global Measles Incidence and Vaccination Dashboard"),
          tags$p(
            class = "hero-lead",
            "Measles is a highly contagious airborne viral disease that spreads easily when an infected person breathes, coughs, or sneezes. WHO notes that it can cause severe disease, complications, and death, especially in children, and that complications are most common in children under 5 years, adults over 30 years, and people who are malnourished or immunocompromised."
          ),
          tags$p(
            class = "hero-lead secondary",
            "The vaccine is safe and cost-effective, and WHO reports that measles vaccination averted nearly 59 million deaths between 2000 and 2024. But global protection is still below the level needed to stop outbreaks: in 2024, first-dose coverage was 84%, second-dose coverage was 76%, and WHO guidance indicates that at least 95% coverage with two doses is needed to prevent transmission and protect communities."
          ),
          div(
            class = "hero-actions",
            actionButton("enter_dashboard", "Open the interactive dashboard", class = "primary-cta"),
            tags$span(class = "hero-note", "Or use the Dashboard tab above.")
          ),
          tags$p(
            class = "hero-citation",
            "Source: WHO Measles Fact Sheet (who.int)"
          )
        ),
        column(
          width = 4,
          div(
            class = "hero-side-panel",
            div(
              class = "mini-chart-card",
              h3("Global measles vaccine coverage"),
              tags$p(
                class = "mini-chart-caption",
                "WHO reported 84% first-dose coverage and 76% second-dose coverage in 2024."
              ),
              div(
                class = "coverage-bars",
                div(
                  class = "coverage-row",
                  tags$div(class = "coverage-label-wrap",
                    tags$span(class = "coverage-label", "MCV1"),
                    tags$span(class = "coverage-value", "84%")
                  ),
                  div(class = "coverage-track", div(class = "coverage-fill fill-mcv1", style = "width: 84%;"))
                ),
                div(
                  class = "coverage-row",
                  tags$div(class = "coverage-label-wrap",
                    tags$span(class = "coverage-label", "MCV2"),
                    tags$span(class = "coverage-value", "76%")
                  ),
                  div(class = "coverage-track", div(class = "coverage-fill fill-mcv2", style = "width: 76%;"))
                ),
                div(
                  class = "coverage-row threshold-row",
                  tags$div(class = "coverage-label-wrap",
                    tags$span(class = "coverage-label", "Threshold"),
                    tags$span(class = "coverage-value", "95%")
                  ),
                  div(class = "coverage-track threshold-track", div(class = "coverage-fill fill-threshold", style = "width: 95%;"))
                )
              )
            ),
            div(
              class = "stat-grid",
              div(
                class = "stat-card",
                tags$span(class = "stat-value", "95,000"),
                tags$span(class = "stat-label", "Estimated measles deaths globally in 2024")
              ),
              div(
                class = "stat-card",
                tags$span(class = "stat-value", "59M"),
                tags$span(class = "stat-label", "Deaths averted by measles vaccination, 2000-2024")
              ),
              div(
                class = "stat-card",
                tags$span(class = "stat-value", "97%"),
                tags$span(class = "stat-label", "Protection WHO reports after two doses")
              )
            )
          )
        )
      )
    ),
    div(
      class = "fast-facts-strip",
      div(
        class = "fact-column",
        tags$span(class = "fact-tag", "What measles is"),
        tags$p(
          "WHO describes measles as a serious airborne viral disease that infects the respiratory tract and then spreads throughout the body. Symptoms include high fever, cough, runny nose, red watery eyes, and a rash."
        ),
        tags$p(
          "It spreads easily when an infected person breathes, coughs, or sneezes."
        )
      ),
      div(
        class = "fact-column",
        tags$span(class = "fact-tag", "MCV1 and MCV2"),
        tags$p(
          "WHO recommends two doses of measles-containing vaccine. The fact sheet notes that two doses are needed to ensure immunity because not all children develop immunity from the first dose."
        ),
        tags$p(
          "WHO also reports that two doses provide 97% protection from infection and its serious consequences for most people."
        )
      ),
      div(
        class = "fact-column",
        tags$span(class = "fact-tag", "Why this app matters"),
        tags$p(
          "Coverage gaps leave populations susceptible, and the dashboard helps users see where those gaps overlap with higher reported incidence, case burden, and shifting trends over time."
        ),
        tags$p(
          "That makes the app useful for comparison, risk communication, and country-level surveillance review."
        )
      )
    ),
    div(
      class = "callout-box",
      tags$span(class = "callout-tag", "Why incidence and coverage together?"),
      h3("Coverage tells you where protection is thin. Incidence shows where outbreaks are already breaking through."),
      tags$p(
        "WHO states that at least 95% coverage with two doses is needed to prevent outbreaks and protect communities. When coverage falls below that threshold, immunity gaps can open. Reading measles incidence side by side with MCV1 and MCV2 coverage makes it easier to spot where vulnerability and burden may be moving together."
      )
    ),
    div(
      class = "tools-section",
      div(
        class = "section-heading",
        tags$span(class = "section-kicker", "Explore the interface"),
        h2("Tools available in the app")
      ),
      div(
        class = "tool-grid",
        div(
          class = "tool-card",
          tags$span(class = "tool-tag", "Mapping"),
          h3("World Map"),
          tags$p(
            "Compare country-level measles incidence or MCV1 coverage for a selected year and see how selected countries stand out against the global background."
          )
        ),
        div(
          class = "tool-card",
          tags$span(class = "tool-tag", "Trend view"),
          h3("Time Series"),
          tags$p(
            "Track reported measles cases, MCV1 coverage, and MCV2 coverage over time for one country or an optional comparison country."
          )
        ),
        div(
          class = "tool-card",
          tags$span(class = "tool-tag", "Relationship"),
          h3("Scatterplot"),
          tags$p(
            "Inspect how vaccination coverage and measles incidence move together across years, with point size reflecting reported case counts."
          )
        ),
        div(
          class = "tool-card",
          tags$span(class = "tool-tag", "Context"),
          h3("Summary Table and Narrative"),
          tags$p(
            "Review the latest country metrics, refresh live data, and read a short narrative summary of the selected country or comparison."
          )
        )
      )
    ),
    div(
      class = "data-sources-section",
      tags$details(
        class = "data-sources-details",
        tags$summary("Data sources used in this app"),
        tags$div(
          class = "data-source-item",
          strong("Our World in Data"),
          tags$p(
            "Reported cases, MCV1 coverage, child measles prevalence, vaccine attitudes, and region labels."
          ),
          tags$ul(
            tags$li("reported-cases-of-measles.csv"),
            tags$li("share-of-children-vaccinated-against-measles.csv"),
            tags$li("API indicator endpoints used for child measles prevalence, vaccine attitudes, and region labels")
          )
        ),
        tags$div(
          class = "data-source-item",
          strong("WHO Global Health Observatory"),
          tags$p(
            "MCV1 (WHS8_110), MCV2, and measles cases (WHS3_62) via ghoapi.azureedge.net."
          )
        ),
        tags$div(
          class = "data-source-item",
          strong("World Bank"),
          tags$p(
            "Annual population (SP.POP.TOTL), used to calculate measles incidence per 100,000."
          )
        )
      )
    )
  )
)

dashboard_ui <- sidebarLayout(
  sidebarPanel(
    width = 3,
    actionButton("refresh_data", "Refresh Live Data"),
    br(),
    br(),
    selectInput("country", "Country", choices = character(0)),
    selectInput(
      "compare_country",
      "Comparison Country (Optional)",
      choices = c("None" = "")
    ),
    uiOutput("year_slider_ui"),
    uiOutput("map_year_ui"),
    selectInput(
      "map_metric",
      "Map Metric",
      choices = c(
        "Measles incidence (per 100k)" = "measles_incidence_per_100k",
        "MCV1 coverage (%)" = "mcv1"
      ),
      selected = "measles_incidence_per_100k"
    ),
    tags$hr(),
    strong("Data Status"),
    textOutput("data_status")
  ),
  mainPanel(
    width = 9,
    tabsetPanel(
      tabPanel("World Map", leafletOutput("world_map", height = "620px")),
      tabPanel("Time Series", plotlyOutput("trend_plot", height = "620px")),
      tabPanel("Scatterplot", plotlyOutput("scatter_plot", height = "520px")),
      tabPanel("Summary Table", tableOutput("summary_table"))
    ),
    fluidRow(
      column(
        width = 12,
        h3("Summary"),
        tags$p(
          style = "font-size: 16px; line-height: 1.5; color: #444;",
          HTML("<strong>Vaccine terms:</strong> MCV1 is the first routine measles vaccine dose. MCV2 is the second dose, which strengthens protection and helps close immunity gaps.")
        ),
        uiOutput("summary_text")
      ),
    )
  )
)

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body {
        background: #fff9f4;
        color: #2b211d;
      }
      .nav-tabs {
        font-size: 16px;
        font-weight: 600;
      }
      .landing-shell {
        padding: 20px 8px 34px;
      }
      .landing-hero {
        background: #FDF3EB;
        border: 1px solid #F0D5BC;
        border-radius: 28px;
        padding: 34px 32px;
        margin-bottom: 22px;
        box-shadow: 0 20px 46px rgba(153, 60, 29, 0.08);
      }
      .hero-kicker {
        display: inline-block;
        margin-bottom: 12px;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        font-size: 12px;
        font-weight: 700;
        color: #993C1D;
      }
      .landing-hero h1 {
        margin-top: 0;
        margin-bottom: 16px;
        font-size: 42px;
        line-height: 1.04;
      }
      .hero-lead {
        font-size: 18px;
        line-height: 1.75;
        max-width: 780px;
        margin-bottom: 16px;
      }
      .hero-lead.secondary {
        color: #5c463c;
      }
      .hero-actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 14px;
        margin-top: 24px;
      }
      .primary-cta,
      .primary-cta:hover,
      .primary-cta:focus {
        background: #993C1D !important;
        border-color: #993C1D !important;
        color: #ffffff !important;
        font-weight: 700;
        padding: 11px 18px;
        border-radius: 999px;
        box-shadow: 0 10px 22px rgba(153, 60, 29, 0.18);
      }
      .hero-note {
        color: #7b6155;
        font-size: 15px;
      }
      .hero-citation {
        margin-top: 18px;
        margin-bottom: 0;
        font-size: 13px;
        color: #7b6155;
      }
      .hero-side-panel {
        display: grid;
        gap: 16px;
      }
      .mini-chart-card,
      .stat-card,
      .fact-column,
      .callout-box,
      .tool-card,
      .data-sources-details {
        background: #fffdfb;
        border: 1px solid #F0D5BC;
        border-radius: 22px;
        box-shadow: 0 12px 30px rgba(153, 60, 29, 0.06);
      }
      .mini-chart-card {
        padding: 20px 20px 18px;
      }
      .mini-chart-card h3,
      .fact-column h3,
      .callout-box h3,
      .tool-card h3,
      .tools-section h2,
      .section-heading h2 {
        margin-top: 0;
        color: #2f211c;
      }
      .mini-chart-caption {
        color: #6d554b;
        line-height: 1.5;
        margin-bottom: 16px;
      }
      .coverage-bars {
        display: grid;
        gap: 12px;
      }
      .coverage-row {
        display: grid;
        gap: 7px;
      }
      .coverage-label-wrap {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        font-size: 13px;
        font-weight: 700;
        color: #5c463c;
      }
      .coverage-track {
        height: 12px;
        border-radius: 999px;
        background: #f8e7d9;
        overflow: hidden;
      }
      .coverage-fill {
        height: 100%;
        border-radius: 999px;
      }
      .fill-mcv1 {
        background: linear-gradient(90deg, #c86335 0%, #993C1D 100%);
      }
      .fill-mcv2 {
        background: linear-gradient(90deg, #d48655 0%, #b7512d 100%);
      }
      .fill-threshold {
        background: linear-gradient(90deg, #7a8f66 0%, #56734c 100%);
      }
      .threshold-track {
        background: #e8efdf;
      }
      .stat-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 12px;
      }
      .stat-card {
        padding: 18px 16px;
        min-height: 132px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
      }
      .stat-value {
        font-size: 33px;
        line-height: 1;
        font-weight: 800;
        color: #993C1D;
      }
      .stat-label {
        font-size: 14px;
        line-height: 1.5;
        color: #5b483f;
      }
      .fast-facts-strip {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 16px;
        margin-bottom: 18px;
      }
      .fact-column {
        padding: 22px;
      }
      .fact-tag,
      .callout-tag,
      .tool-tag,
      .section-kicker {
        display: inline-block;
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        color: #993C1D;
        background: #f9e3d3;
        border-radius: 999px;
        padding: 6px 10px;
        margin-bottom: 12px;
      }
      .fact-column p,
      .callout-box p,
      .tool-card p,
      .data-source-item p,
      .data-source-item li {
        color: #5b483f;
        line-height: 1.7;
      }
      .callout-box {
        padding: 24px 24px 22px;
        margin-bottom: 20px;
      }
      .callout-box h3 {
        margin-bottom: 10px;
        font-size: 26px;
        line-height: 1.25;
      }
      .tools-section {
        margin-top: 8px;
      }
      .section-heading {
        margin-bottom: 14px;
      }
      .section-heading h2 {
        margin-bottom: 0;
      }
      .tool-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 16px;
      }
      .tool-card {
        padding: 22px;
        min-height: 210px;
      }
      .data-sources-section {
        margin-top: 20px;
      }
      .data-sources-details {
        padding: 16px 18px;
      }
      .data-sources-details summary {
        cursor: pointer;
        font-size: 16px;
        font-weight: 700;
        color: #2f211c;
      }
      .data-source-item {
        margin-top: 16px;
      }
      .data-source-item ul {
        padding-left: 20px;
        margin-bottom: 0;
      }
      @media (max-width: 767px) {
        .landing-hero {
          padding: 24px 20px;
        }
        .landing-hero h1 {
          font-size: 32px;
        }
        .hero-lead {
          font-size: 17px;
        }
        .stat-grid,
        .fast-facts-strip,
        .tool-grid {
          grid-template-columns: 1fr;
        }
      }
      @media (min-width: 768px) and (max-width: 991px) {
        .stat-grid {
          grid-template-columns: 1fr;
        }
      }
    "))
  ),
  titlePanel("Global Measles Incidence and Vaccination Dashboard"),
  tabsetPanel(
    id = "main_view",
    selected = "Overview",
    tabPanel("Overview", landing_page_ui),
    tabPanel("Dashboard", dashboard_ui)
  )
)

server <- function(input, output, session) {
  preloaded_dataset <- getOption("glhlth562.preloaded_dataset", default = NULL)
  preloaded_at <- getOption("glhlth562.preloaded_at", default = NULL)

  dataset_state <- reactiveValues(
    data = preloaded_dataset,
    status = if (!is.null(preloaded_dataset)) {
      paste(
        "Loaded",
        nrow(preloaded_dataset),
        "rows at",
        format(preloaded_at %||% Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
    } else {
      "Loading live data..."
    },
    loaded_at = preloaded_at
  )

  initialize_inputs_from_dataset <- function(dataset) {
    choices <- as.character(available_country_choices(dataset))
    default_country <- if ("United States" %in% choices) "United States" else choices[[1]] %||% ""

    updateSelectInput(session, "country", choices = choices, selected = default_country)
    updateSelectInput(
      session,
      "compare_country",
      choices = c("None" = "", choices),
      selected = ""
    )
  }

  load_dataset <- function() {
    dataset_state$status <- "Fetching OWID, WHO, and World Bank data..."

    tryCatch(
      {
        raw_data <- fetch_all_runtime_data(start_year = 2000, end_year = 2025)
        dataset <- build_analysis_dataset(
          owid_cases = raw_data$owid_cases,
          owid_mcv1 = raw_data$owid_mcv1,
          who_data = raw_data$who_data,
          population = raw_data$population
        ) |>
          dplyr::filter(year >= 2000, year <= 2025)

        loaded_at <- Sys.time()
        dataset_state$data <- dataset
        dataset_state$loaded_at <- loaded_at
        dataset_state$status <- paste(
          "Loaded",
          nrow(dataset),
          "rows at",
          format(loaded_at, "%Y-%m-%d %H:%M:%S")
        )

        initialize_inputs_from_dataset(dataset)
      },
      error = function(error) {
        dataset_state$status <- paste("Data load failed:", conditionMessage(error))
      }
    )
  }

  observeEvent(input$refresh_data, {
    load_dataset()
  })

  observe({
    req(dataset_state$data)
    initialize_inputs_from_dataset(dataset_state$data)
  })

  session$onFlushed(function() {
    if (is.null(isolate(dataset_state$data))) {
      load_dataset()
    }
  }, once = TRUE)

  observeEvent(input$enter_dashboard, {
    updateTabsetPanel(session, "main_view", selected = "Dashboard")
  })

  output$year_slider_ui <- renderUI({
    data <- dataset_state$data

    if (is.null(data) || nrow(data) == 0) {
      return(sliderInput("year_range", "Year Range", min = 2000, max = 2025, value = c(2000, 2025), sep = ""))
    }

    sliderInput(
      "year_range",
      "Year Range",
      min = min(data$year, na.rm = TRUE),
      max = max(data$year, na.rm = TRUE),
      value = c(2000, min(max(data$year, na.rm = TRUE), 2025)),
      sep = ""
    )
  })

  output$map_year_ui <- renderUI({
    data <- dataset_state$data

    if (is.null(data) || nrow(data) == 0) {
      return(selectInput("map_year", "Map Year", choices = 2025, selected = 2025))
    }

    years <- sort(unique(data$year))
    selectInput("map_year", "Map Year", choices = years, selected = max(years, na.rm = TRUE))
  })

  selected_data <- reactive({
    req(dataset_state$data, input$country, input$year_range)

    countries <- as.character(c(input$country, input$compare_country))
    subset <- filter_country_data(dataset_state$data, countries, input$year_range)
    validation_message <- validate_country_subset(subset)

    shiny::validate(shiny::need(is.null(validation_message), validation_message))
    subset
  })

  comparison_country <- reactive({
    input$comparison_country %||% input$compare_country %||% ""
  })

  summary_text <- reactive({
    generate_summary(selected_data())
  })

  summary_table_data <- reactive({
    summarise_country_metrics(selected_data())
  })

  output$data_status <- renderText({
    dataset_state$status
  })

  output$summary_text <- renderUI({
    paragraphs <- strsplit(summary_text(), "\n\\s*\n")[[1]]
    paragraphs <- trimws(paragraphs)
    paragraphs <- paragraphs[nzchar(paragraphs)]

    tags$div(
      style = "font-size: 18px; line-height: 1.7;",
      lapply(paragraphs, function(paragraph) {
        tags$p(style = "margin-bottom: 14px;", paragraph)
      })
    )
  })

  map_data <- reactive({
    req(dataset_state$data, input$map_year)

    create_map_data(dataset_state$data, input$map_year)
  })

  map_geometry <- reactive({
    summary_map <- summary_table_data() |>
      dplyr::rename(location = `Country`)

    joined <- dplyr::left_join(world_geometry, map_data(), by = "iso3") |>
      dplyr::left_join(summary_map, by = "location")
    joined$value <- joined[[input$map_metric]]
    joined$border_color <- dplyr::case_when(
      !is.na(joined$location) & joined$location == input$country ~ "#d62728",
      nzchar(comparison_country()) &
        !is.na(joined$location) &
        joined$location == comparison_country() ~ "#1f77b4",
      TRUE ~ "#ffffff"
    )
    joined$border_weight <- dplyr::case_when(
      !is.na(joined$location) & joined$location == input$country ~ 2.5,
      nzchar(comparison_country()) &
        !is.na(joined$location) &
        joined$location == comparison_country() ~ 2.5,
      TRUE ~ 0.7
    )
    joined$label <- vapply(
      seq_len(nrow(joined)),
      FUN.VALUE = character(1),
      FUN = function(i) {
        location <- joined$location[[i]]

        if (is.na(location) || !(location %in% c(input$country, comparison_country()))) {
          return("")
        }

        paste0(
          "<div style='font-family:-apple-system,BlinkMacSystemFont,\"Segoe UI\",Roboto,Helvetica,Arial,sans-serif;'>",
          "<div style='font-weight:700;font-size:14px;margin-bottom:6px;'>", location, "</div>",
          "<table style='border-collapse:collapse;font-size:12px;line-height:1.35;'>",
          "<tr><td style='color:#6b7280;padding:2px 10px 2px 0;'>Latest Year</td><td style='font-weight:700;padding:2px 0;'>", as.character(joined$`Latest Year`[[i]]), "</td></tr>",
          "<tr><td style='color:#6b7280;padding:2px 10px 2px 0;'>Latest Reported Measles Cases</td><td style='font-weight:700;padding:2px 0;'>", as.character(joined$`Latest Reported Measles Cases`[[i]]), "</td></tr>",
          "<tr><td style='color:#6b7280;padding:2px 10px 2px 0;'>MCV1 Coverage (%)</td><td style='font-weight:700;padding:2px 0;'>", as.character(joined$`Latest MCV1 Coverage (%)`[[i]]), "</td></tr>",
          "<tr><td style='color:#6b7280;padding:2px 10px 2px 0;'>MCV2 Coverage (%)</td><td style='font-weight:700;padding:2px 0;'>", as.character(joined$`Latest MCV2 Coverage (%)`[[i]]), "</td></tr>",
          "<tr><td style='color:#6b7280;padding:2px 10px 2px 0;'>Measles Incidence (per 100k)</td><td style='font-weight:700;padding:2px 0;'>", as.character(joined$`Latest Measles Incidence (per 100k)`[[i]]), "</td></tr>",
          "</table></div>"
        )
      }
    )

    joined
  })

  output$world_map <- renderLeaflet({
    leaflet(world_geometry) |>
      addProviderTiles(providers$CartoDB.Positron) |>
      setView(lng = 10, lat = 20, zoom = 1.4)
  })

  observe({
    req(input$map_metric, input$map_year)

    map_sf <- map_geometry()
    dataset_values <- map_data()[[input$map_metric]]
    finite_values <- dataset_values[is.finite(dataset_values)]
    has_data <- length(finite_values) > 0
    pal <- leaflet::colorNumeric(
      palette = if (identical(input$map_metric, "mcv1")) "Blues" else "YlOrRd",
      domain = if (has_data) finite_values else c(0, 1),
      na.color = "lightgray"
    )
    labels <- lapply(
      map_sf$label,
      function(label) {
        htmltools::HTML(label)
      }
    )
    legend_title <- if (identical(input$map_metric, "mcv1")) {
      "MCV1 coverage (%)"
    } else {
      "Measles incidence (per 100k)"
    }

    proxy <- leafletProxy("world_map", data = map_sf) |>
      clearShapes() |>
      clearControls() |>
      addPolygons(
        fillColor = ~pal(value),
        fillOpacity = 0.85,
        color = ~border_color,
        weight = ~border_weight,
        smoothFactor = 0.2,
        label = labels,
        labelOptions = labelOptions(
          direction = "auto",
          textsize = "13px",
          textOnly = FALSE
        ),
        highlightOptions = highlightOptions(
          weight = 1.5,
          color = "#333333",
          bringToFront = TRUE
        )
      )

    if (has_data) {
      proxy <- proxy |>
        addLegend(
          "bottomright",
          pal = pal,
          values = finite_values,
          title = legend_title,
          opacity = 0.85
        )
    }
  })

  output$trend_plot <- renderPlotly({
    plot_data <- create_trend_plot_data(selected_data())

    country_levels <- unique(plot_data$location)
    measure_levels <- c("Cases", "MCV1", "MCV2")
    plot_data <- plot_data |>
      dplyr::mutate(
        location = factor(location, levels = country_levels),
        series = factor(series, levels = measure_levels)
      )

    plot <- ggplot(
      plot_data,
      aes(
        x = year,
        y = value,
        color = location,
        linetype = series,
        group = interaction(location, series),
        text = paste0(
          "Country: ", location,
          "<br>Year: ", year,
          "<br>Measure: ", series,
          "<br>Value: ", comma(round(value, 2))
        )
      )
    )

    plot <- plot +
      geom_smooth(
        method = "lm",
        se = FALSE,
        linewidth = 0.8,
        alpha = 0.35,
        show.legend = FALSE,
        na.rm = TRUE
      ) +
      geom_line(linewidth = 1, alpha = 0.8, na.rm = TRUE) +
      geom_point(size = 2.6, alpha = 0.7, na.rm = TRUE) +
      facet_wrap(~metric, ncol = 1, scales = "free_y") +
      scale_x_continuous(breaks = pretty_breaks()) +
      scale_linetype_manual(
        values = c("Cases" = "solid", "MCV1" = "longdash", "MCV2" = "dotdash"),
        breaks = measure_levels
      ) +
      labs(
        x = "Year",
        y = NULL,
        color = "Country",
        linetype = "Measure",
        title = "Reported measles cases and vaccination coverage over time"
      ) +
      theme_minimal(base_size = 12) +
      guides(
        color = guide_legend(
          order = 1,
          override.aes = list(
            linetype = rep("solid", length(country_levels)),
            shape = 16,
            alpha = 1,
            linewidth = 1
          )
        ),
        linetype = guide_legend(
          order = 2,
          override.aes = list(
            color = "gray35",
            shape = NA,
            alpha = 1,
            linewidth = 1.1
          )
        )
      ) +
      theme(
        legend.position = "bottom",
        legend.box = "vertical"
      )

    ggplotly(plot, tooltip = "text")
  })

  output$scatter_plot <- renderPlotly({
    plot_data <- create_scatter_plot_data(selected_data())

    shiny::validate(
      shiny::need(nrow(plot_data) > 0, "Not enough non-missing rows for the vaccination/incidence scatterplot.")
    )

    plot <- ggplot(
      plot_data,
      aes(
        x = mcv1,
        y = plot_incidence,
        color = location,
        text = paste0(
          "Country: ", location,
          "<br>Year: ", year,
          "<br>MCV1: ", round(mcv1, 1), "%",
          "<br>Incidence per 100k: ", round(measles_incidence_per_100k, 2),
          "<br>Cases: ", comma(round(measles_cases, 0))
        )
      )
    ) +
      geom_smooth(
        method = "lm",
        se = FALSE,
        linewidth = 0.8,
        linetype = "dashed",
        alpha = 0.7,
        na.rm = TRUE
      ) +
      geom_point(aes(size = pmax(measles_cases, 1)), alpha = 0.75, na.rm = TRUE) +
      scale_y_log10(labels = label_number(accuracy = 0.1)) +
      scale_size_continuous(labels = comma) +
      labs(
        x = "MCV1 coverage (%)",
        y = "Measles incidence per 100k (log scale)",
        color = "Country",
        size = "Reported cases",
        title = "Vaccination coverage versus measles incidence"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")

    ggplotly(plot, tooltip = "text")
  })

  output$summary_table <- renderTable({
    summary_table_data()
  }, striped = TRUE, bordered = TRUE, digits = 2)
}

shinyApp(ui = ui, server = server)
