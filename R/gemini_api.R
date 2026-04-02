safe_mean <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }

  mean(x, na.rm = TRUE)
}

build_gemini_summary_payload <- function(data_subset) {
  clean_data <- data_subset |>
    dplyr::arrange(year)

  start_row <- clean_data |>
    dplyr::filter(!is.na(measles_cases) | !is.na(mcv1)) |>
    dplyr::slice_head(n = 1)

  end_row <- clean_data |>
    dplyr::filter(!is.na(measles_cases) | !is.na(mcv1)) |>
    dplyr::slice_tail(n = 1)

  peak_cases <- clean_data |>
    dplyr::filter(!is.na(measles_cases)) |>
    dplyr::slice_max(order_by = measles_cases, n = 1, with_ties = FALSE)

  largest_jump <- clean_data |>
    dplyr::filter(!is.na(cases_yoy_pct_change)) |>
    dplyr::slice_max(order_by = cases_yoy_pct_change, n = 1, with_ties = FALSE)

  list(
    country = unique(clean_data$location)[1],
    start_year = min(clean_data$year, na.rm = TRUE),
    end_year = max(clean_data$year, na.rm = TRUE),
    observations = nrow(clean_data),
    measles_cases_start = start_row$measles_cases %||% NA_real_,
    measles_cases_end = end_row$measles_cases %||% NA_real_,
    mcv1_start = start_row$mcv1 %||% NA_real_,
    mcv1_end = end_row$mcv1 %||% NA_real_,
    average_mcv1 = safe_mean(clean_data$mcv1),
    average_cases = safe_mean(clean_data$measles_cases),
    peak_cases_year = peak_cases$year %||% NA_integer_,
    peak_cases_value = peak_cases$measles_cases %||% NA_real_,
    largest_yoy_jump_year = largest_jump$year %||% NA_integer_,
    largest_yoy_jump_pct = largest_jump$cases_yoy_pct_change %||% NA_real_,
    missing_case_years = sum(is.na(clean_data$measles_cases)),
    missing_vaccine_years = sum(is.na(clean_data$mcv1))
  )
}

extract_gemini_text <- function(response_body) {
  find_first_text <- function(x) {
    if (is.null(x)) {
      return(NULL)
    }

    if (is.character(x)) {
      non_empty <- trimws(x[nzchar(trimws(x))])
      return(non_empty[1] %||% NULL)
    }

    if (is.data.frame(x)) {
      if ("text" %in% names(x)) {
        non_empty <- trimws(x$text[nzchar(trimws(x$text))])
        return(non_empty[1] %||% NULL)
      }

      for (column_name in names(x)) {
        text_value <- find_first_text(x[[column_name]])
        if (!is.null(text_value)) {
          return(text_value)
        }
      }
    }

    if (is.list(x)) {
      if (!is.null(x$text) && is.character(x$text)) {
        non_empty <- trimws(x$text[nzchar(trimws(x$text))])
        return(non_empty[1] %||% NULL)
      }

      for (item in x) {
        text_value <- find_first_text(item)
        if (!is.null(text_value)) {
          return(text_value)
        }
      }
    }

    NULL
  }

  find_first_text(response_body$candidates)
}

generate_summary <- function(data_subset) {
  validation_message <- validate_country_subset(data_subset)

  if (!is.null(validation_message)) {
    return(validation_message)
  }

  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (!nzchar(api_key)) {
    return("Gemini summary unavailable. Add GEMINI_API_KEY to .Renviron and restart the app.")
  }

  payload <- build_gemini_summary_payload(data_subset)
  prompt <- paste0(
    "You are a public health analyst. Based on the following data for ",
    payload$country,
    " from ",
    payload$start_year,
    " to ",
    payload$end_year,
    ", summarize the relationship between measles cases and vaccination coverage. ",
    "Highlight any notable increases in cases and explain whether they may be associated ",
    "with declines in vaccination. Keep the explanation in 200 words and accessible ",
    "to a general audience.\n\n",
    "Use only the summarized dataset below. If data are sparse, say so briefly.\n",
    jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE)
  )

  response_text <- tryCatch(
    {
      response <- httr2::request("https://generativelanguage.googleapis.com/v1beta") |>
        httr2::req_url_path_append("models/gemini-2.5-flash:generateContent") |>
        httr2::req_url_query(key = api_key) |>
        httr2::req_body_json(
          list(
            contents = list(
              list(
                parts = list(
                  list(text = prompt)
                )
              )
            )
          ),
          auto_unbox = TRUE
        ) |>
        httr2::req_timeout(45) |>
        httr2::req_perform()

      parsed <- jsonlite::fromJSON(
        httr2::resp_body_string(response),
        simplifyVector = TRUE,
        flatten = TRUE
      )
      extract_gemini_text(parsed)
    },
    error = function(error) {
      paste("Gemini summary request failed:", conditionMessage(error))
    }
  )

  response_text %||% "Gemini returned no summary text for this selection."
}
