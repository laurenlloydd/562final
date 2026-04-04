library(shiny)
library(dplyr)
library(ggplot2)
library(plotly)
library(scales)

source(file.path("R", "data_fetch.R"))
source(file.path("R", "data_process.R"))
source(file.path("R", "gemini_api.R"))

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
      tags$hr(),
      strong("Data Status"),
      textOutput("data_status"),
    ),
    mainPanel(
      width = 9,
      fluidRow(
        column(
          width = 12,
          h3("Summary"),
          uiOutput("summary_text")
        )
      ),
      tabsetPanel(
        tabPanel("Time Series", plotlyOutput("trend_plot", height = "620px")),
        tabPanel("Scatterplot", plotlyOutput("scatter_plot", height = "520px")),
        tabPanel("Summary Table", tableOutput("summary_table"))
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
    choices <- available_country_choices(dataset)
    selected_country <- if ("United States" %in% choices) {
      "United States"
    } else {
      choices[[1]] %||% ""
    }

    updateSelectInput(session, "country", choices = choices, selected = selected_country)
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

  selected_data <- reactive({
    req(dataset_state$data, input$country, input$year_range)

    countries <- c(input$country, input$compare_country)
    subset <- filter_country_data(dataset_state$data, countries, input$year_range)
    validation_message <- validate_country_subset(subset)

    validate(need(is.null(validation_message), validation_message))
    subset
  })

  summary_text <- reactive({
    generate_summary(selected_data())
  })

  output$data_status <- renderText({
    dataset_state$status
  })

  output$summary_text <- renderUI({
    tags$div(style = "white-space: pre-wrap;", summary_text())
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

    validate(
      need(nrow(plot_data) > 0, "Not enough non-missing rows for the vaccination/incidence scatterplot.")
    )

    plot <- ggplot(
      plot_data,
      aes(
        x = mcv1,
        y = plot_incidence,
        color = location,
        size = pmax(measles_cases, 1),
        text = paste0(
          "Country: ", location,
          "<br>Year: ", year,
          "<br>MCV1: ", round(mcv1, 1), "%",
          "<br>Incidence per 100k: ", round(measles_incidence_per_100k, 2),
          "<br>Cases: ", comma(round(measles_cases, 0))
        )
      )
    ) +
      geom_point(alpha = 0.75) +
      geom_smooth(method = "lm", se = FALSE, linewidth = 0.8) +
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
    summarise_country_metrics(selected_data())
  }, striped = TRUE, bordered = TRUE, digits = 2)
}

shinyApp(ui = ui, server = server)
