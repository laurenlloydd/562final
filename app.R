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

ui <- fluidPage(
  titlePanel("Global Measles Incidence and Vaccination Dashboard"),
  sidebarLayout(
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
        )
      )
    )
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

    plot <- ggplot(
      plot_data,
      aes(
        x = year,
        y = value,
        color = location,
        linetype = series,
        text = paste0(
          "Country: ", location,
          "<br>Year: ", year,
          "<br>Series: ", series,
          "<br>Value: ", comma(round(value, 2))
        )
      )
    )

    plot <- plot +
      geom_smooth(
        aes(
          x = year,
          y = value,
          group = interaction(location, series),
          color = location
        ),
        method = "lm",
        se = FALSE,
        linewidth = 0.8,
        linetype = "dashed",
        alpha = 0.7,
        inherit.aes = FALSE,
        na.rm = TRUE
      ) +
      geom_line(linewidth = 0.9, na.rm = TRUE) +
      geom_point(size = 1.4, na.rm = TRUE) +
      facet_wrap(~metric, ncol = 1, scales = "free_y") +
      scale_x_continuous(breaks = pretty_breaks()) +
      labs(
        x = "Year",
        y = NULL,
        color = "Country",
        linetype = "Series",
        title = "Reported measles cases and vaccination coverage over time"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")

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
