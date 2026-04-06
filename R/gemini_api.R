safe_mean <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }

  mean(x, na.rm = TRUE)
}

format_metric <- function(value, digits = 1, suffix = "") {
  if (is.null(value) || length(value) == 0 || is.na(value)) {
    return("no reported value")
  }

  paste0(format(round(value, digits), big.mark = ","), suffix)
}

build_country_trend_summary <- function(country_data) {
  clean_data <- country_data |>
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

generate_country_local_summary <- function(country_summary) {
  coverage_direction <- dplyr::case_when(
    is.na(country_summary$mcv1_start) || is.na(country_summary$mcv1_end) ~ "had limited vaccination coverage data",
    country_summary$mcv1_end > country_summary$mcv1_start + 1 ~ paste0(
      "rose from ",
      format_metric(country_summary$mcv1_start, 1, "%"),
      " to ",
      format_metric(country_summary$mcv1_end, 1, "%")
    ),
    country_summary$mcv1_end < country_summary$mcv1_start - 1 ~ paste0(
      "fell from ",
      format_metric(country_summary$mcv1_start, 1, "%"),
      " to ",
      format_metric(country_summary$mcv1_end, 1, "%")
    ),
    TRUE ~ paste0(
      "stayed fairly stable around ",
      format_metric(country_summary$average_mcv1, 1, "%")
    )
  )

  case_direction <- dplyr::case_when(
    is.na(country_summary$measles_cases_start) || is.na(country_summary$measles_cases_end) ~ "Case data were incomplete across the selected period.",
    country_summary$measles_cases_end > country_summary$measles_cases_start * 1.1 ~ paste0(
      "Reported measles cases increased from ",
      format_metric(country_summary$measles_cases_start, 0),
      " to ",
      format_metric(country_summary$measles_cases_end, 0),
      "."
    ),
    country_summary$measles_cases_end < country_summary$measles_cases_start * 0.9 ~ paste0(
      "Reported measles cases decreased from ",
      format_metric(country_summary$measles_cases_start, 0),
      " to ",
      format_metric(country_summary$measles_cases_end, 0),
      "."
    ),
    TRUE ~ paste0(
      "Reported measles cases were relatively stable, moving from ",
      format_metric(country_summary$measles_cases_start, 0),
      " to ",
      format_metric(country_summary$measles_cases_end, 0),
      "."
    )
  )

  peak_sentence <- if (!is.na(country_summary$peak_cases_year) && !is.na(country_summary$peak_cases_value)) {
    paste0(
      "The highest reported case count was ",
      format_metric(country_summary$peak_cases_value, 0),
      " in ",
      country_summary$peak_cases_year,
      "."
    )
  } else {
    "No clear peak year could be identified from the available case data."
  }

  association_sentence <- dplyr::case_when(
    is.na(country_summary$mcv1_start) || is.na(country_summary$mcv1_end) ||
      is.na(country_summary$measles_cases_start) || is.na(country_summary$measles_cases_end) ~
      "Because one of the two series is incomplete, any relationship between vaccination coverage and measles incidence should be interpreted cautiously.",
    country_summary$mcv1_end < country_summary$mcv1_start && country_summary$measles_cases_end > country_summary$measles_cases_start ~
      "Over this window, lower vaccination coverage coincided with higher case counts, which is consistent with increased outbreak risk.",
    country_summary$mcv1_end > country_summary$mcv1_start && country_summary$measles_cases_end < country_summary$measles_cases_start ~
      "Over this window, higher vaccination coverage coincided with lower case counts, which is consistent with stronger population protection.",
    TRUE ~
      "The relationship between vaccination coverage and cases was not perfectly one-directional, so the pattern should be read as descriptive rather than causal."
  )

  missing_sentence <- if (country_summary$missing_case_years > 0 || country_summary$missing_vaccine_years > 0) {
    paste0(
      "The selection includes ",
      country_summary$missing_case_years,
      " year(s) with missing case data and ",
      country_summary$missing_vaccine_years,
      " year(s) with missing vaccination data."
    )
  } else {
    "The selected window has complete case and vaccination coverage values."
  }

  paste(
    paste0(
      country_summary$country,
      " covers ",
      country_summary$start_year,
      " to ",
      country_summary$end_year,
      " across ",
      country_summary$observations,
      " yearly observations."
    ),
    paste("MCV1 coverage", coverage_direction, "."),
    case_direction,
    peak_sentence,
    association_sentence,
    missing_sentence
  )
}

build_gemini_summary_payload <- function(data_subset) {
  clean_data <- data_subset |>
    dplyr::arrange(location, year)

  country_summaries <- clean_data |>
    dplyr::group_split(location, .keep = TRUE) |>
    lapply(build_country_trend_summary)

  yearly_metrics <- clean_data |>
    dplyr::transmute(
      country = location,
      year,
      measles_cases = round(measles_cases, 2),
      mcv1 = round(mcv1, 2),
      mcv2 = round(mcv2_who, 2),
      measles_incidence_per_100k = round(measles_incidence_per_100k, 4)
    )

  list(
    selected_countries = unique(clean_data$location),
    start_year = min(clean_data$year, na.rm = TRUE),
    end_year = max(clean_data$year, na.rm = TRUE),
    observations = nrow(clean_data),
    country_summaries = country_summaries,
    yearly_metrics = yearly_metrics
  )
}

generate_local_summary <- function(payload) {
  country_sentences <- vapply(
    payload$country_summaries,
    generate_country_local_summary,
    character(1)
  )

  comparison_sentence <- ""

  if (length(payload$country_summaries) > 1) {
    comparison_df <- tibble::tibble(
      country = vapply(payload$country_summaries, `[[`, character(1), "country"),
      average_mcv1 = vapply(payload$country_summaries, `[[`, numeric(1), "average_mcv1"),
      average_cases = vapply(payload$country_summaries, `[[`, numeric(1), "average_cases")
    )

    highest_coverage <- comparison_df |>
      dplyr::filter(!is.na(average_mcv1)) |>
      dplyr::slice_max(order_by = average_mcv1, n = 1, with_ties = FALSE)

    highest_cases <- comparison_df |>
      dplyr::filter(!is.na(average_cases)) |>
      dplyr::slice_max(order_by = average_cases, n = 1, with_ties = FALSE)

    comparison_parts <- c()

    if (nrow(highest_coverage) > 0) {
      comparison_parts <- c(
        comparison_parts,
        paste0(
          highest_coverage$country[[1]],
          " had the highest average MCV1 coverage at ",
          format_metric(highest_coverage$average_mcv1[[1]], 1, "%"),
          "."
        )
      )
    }

    if (nrow(highest_cases) > 0) {
      comparison_parts <- c(
        comparison_parts,
        paste0(
          highest_cases$country[[1]],
          " had the highest average reported measles cases at ",
          format_metric(highest_cases$average_cases[[1]], 0),
          "."
        )
      )
    }

    comparison_sentence <- paste(comparison_parts, collapse = " ")
  }

  paste(
    paste0(
      "Selected countries: ",
      paste(payload$selected_countries, collapse = ", "),
      "."
    ),
    paste(country_sentences, collapse = " "),
    comparison_sentence
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

  payload <- build_gemini_summary_payload(data_subset)
  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (!nzchar(api_key)) {
    return(generate_local_summary(payload))
  }

  selected_country_text <- paste(payload$selected_countries, collapse = ", ")
  comparison_instruction <- if (length(payload$selected_countries) > 1) {
    paste0(
      "Compare the countries directly. Explain which country kept higher vaccination coverage, ",
      "which country experienced larger or sharper increases in measles cases, and whether case spikes ",
      "appear alongside declines or stagnation in MCV1 coverage."
    )
  } else {
    "Interpret how measles cases and MCV1 coverage changed over time for the selected country."
  }

  prompt <- paste0(
    "You are a public health analyst writing a short dashboard summary for ",
    selected_country_text,
    ". The selected time window runs from ",
    payload$start_year,
    " to ",
    payload$end_year,
    ". ",
    comparison_instruction,
    " Focus on interpretation over time, not just description. ",
    "State whether higher vaccination coverage generally aligns with lower measles burden, ",
    "call out notable peaks or reversals, and mention if the evidence is mixed or incomplete. ",
    "Use plain language for a general audience, avoid jargon, avoid bullet points, avoid mentioning JSON, ",
    "and do not invent facts not present in the structured data. Keep the answer between 140 and 220 words.\n\n",
    "Use only the structured data below:\n",
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
      NULL
    }
  )

  response_text %||% generate_local_summary(payload)
}

