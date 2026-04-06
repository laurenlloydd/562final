safe_mean <- function(x) {
  if (all(is.na(x))) {
    return(NA_real_)
  }

  mean(x, na.rm = TRUE)
}

safe_cor <- function(x, y) {
  complete <- stats::complete.cases(x, y)

  if (sum(complete) < 3) {
    return(NA_real_)
  }

  stats::cor(x[complete], y[complete])
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

  aligned_data <- clean_data |>
    dplyr::filter(!is.na(mcv1), !is.na(measles_incidence_per_100k))

  year_to_year_changes <- clean_data |>
    dplyr::arrange(year) |>
    dplyr::transmute(
      mcv1,
      next_mcv1 = dplyr::lead(mcv1),
      measles_cases,
      next_cases = dplyr::lead(measles_cases),
      measles_incidence_per_100k,
      next_incidence = dplyr::lead(measles_incidence_per_100k)
    )

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
    incidence_start = start_row$measles_incidence_per_100k %||% NA_real_,
    incidence_end = end_row$measles_incidence_per_100k %||% NA_real_,
    average_incidence = safe_mean(clean_data$measles_incidence_per_100k),
    coverage_incidence_correlation = safe_cor(clean_data$mcv1, clean_data$measles_incidence_per_100k),
    stable_high_coverage_low_incidence =
      !is.na(safe_mean(clean_data$mcv1)) &&
      !is.na(safe_mean(clean_data$measles_incidence_per_100k)) &&
      safe_mean(clean_data$mcv1) >= 90 &&
      safe_mean(clean_data$measles_incidence_per_100k) <= 5,
    coverage_drop_followed_by_case_spike = any(
      !is.na(year_to_year_changes$mcv1) &
        !is.na(year_to_year_changes$next_mcv1) &
        !is.na(year_to_year_changes$next_cases) &
        !is.na(year_to_year_changes$measles_cases) &
        year_to_year_changes$next_mcv1 <= year_to_year_changes$mcv1 - 2 &
        year_to_year_changes$next_cases >
          pmax(year_to_year_changes$measles_cases * 1.5, year_to_year_changes$measles_cases + 5),
      na.rm = TRUE
    ) || any(
      !is.na(year_to_year_changes$mcv1) &
        !is.na(year_to_year_changes$next_mcv1) &
        !is.na(year_to_year_changes$next_incidence) &
        !is.na(year_to_year_changes$measles_incidence_per_100k) &
        year_to_year_changes$next_mcv1 <= year_to_year_changes$mcv1 - 2 &
        year_to_year_changes$next_incidence >
          pmax(year_to_year_changes$measles_incidence_per_100k * 1.5, year_to_year_changes$measles_incidence_per_100k + 0.5),
      na.rm = TRUE
    ),
    aligned_years = nrow(aligned_data),
    peak_cases_year = peak_cases$year %||% NA_integer_,
    peak_cases_value = peak_cases$measles_cases %||% NA_real_,
    largest_yoy_jump_year = largest_jump$year %||% NA_integer_,
    largest_yoy_jump_pct = largest_jump$cases_yoy_pct_change %||% NA_real_,
    missing_case_years = sum(is.na(clean_data$measles_cases)),
    missing_vaccine_years = sum(is.na(clean_data$mcv1))
  )
}

generate_country_local_summary <- function(country_summary) {
  descriptive_sentence <- dplyr::case_when(
    !is.na(country_summary$average_mcv1) &&
      !is.na(country_summary$average_incidence) &&
      !is.na(country_summary$peak_cases_year) ~ paste0(
      country_summary$country,
      " maintains average MCV1 coverage of about ",
      format_metric(country_summary$average_mcv1, 1, "%"),
      ", with measles incidence averaging ",
      format_metric(country_summary$average_incidence, 1),
      " per 100,000 and the clearest case surge occurring around ",
      country_summary$peak_cases_year,
      "."
    ),
    !is.na(country_summary$average_mcv1) &&
      !is.na(country_summary$average_incidence) ~ paste0(
      country_summary$country,
      " maintains average MCV1 coverage of about ",
      format_metric(country_summary$average_mcv1, 1, "%"),
      ", while measles incidence averages ",
      format_metric(country_summary$average_incidence, 1),
      " per 100,000."
    ),
    TRUE ~ paste0(
      country_summary$country,
      " shows enough overlap between vaccination and case reporting to support a cautious read of the outbreak pattern."
    )
  )

  relationship_sentence <- dplyr::case_when(
    isTRUE(country_summary$stable_high_coverage_low_incidence) ~ paste0(
      "Taken together, the time series and scatterplot suggest routine vaccination is helping suppress sustained outbreaks."
    ),
    !is.na(country_summary$coverage_incidence_correlation) &&
      country_summary$coverage_incidence_correlation <= -0.35 ~ paste0(
      "Taken together, the plots suggest higher MCV1 coverage generally aligns with lower measles incidence, which is consistent with stronger routine protection."
    ),
    !is.na(country_summary$coverage_incidence_correlation) &&
      country_summary$coverage_incidence_correlation >= 0.35 ~ paste0(
      "The relationship is less straightforward, which may indicate that outbreak risk is being shaped by factors beyond routine MCV1 coverage alone."
    ),
    !is.na(country_summary$mcv1_start) &&
      !is.na(country_summary$mcv1_end) &&
      !is.na(country_summary$incidence_start) &&
      !is.na(country_summary$incidence_end) &&
      country_summary$mcv1_end > country_summary$mcv1_start &&
      country_summary$incidence_end < country_summary$incidence_start ~ paste0(
      "Rising MCV1 coverage is paired with lower measles incidence, which suggests protection improved over time."
    ),
    TRUE ~ paste0(
      "The relationship between MCV1 coverage and measles incidence is mixed, so the pattern should be interpreted cautiously."
    )
  )

  qualifier_sentence <- dplyr::case_when(
    isTRUE(country_summary$coverage_drop_followed_by_case_spike) ~
      "Short drops in coverage are followed by increases in cases or incidence, which may indicate that even modest immunity gaps can raise outbreak risk.",
    isTRUE(country_summary$stable_high_coverage_low_incidence) ~
      "Cases remain low despite stable coverage, which is consistent with herd protection limiting transmission.",
    !is.na(country_summary$peak_cases_year) &&
      !is.na(country_summary$average_cases) &&
      !is.na(country_summary$peak_cases_value) &&
      country_summary$peak_cases_value > country_summary$average_cases * 1.5 ~ paste0(
      "The sharpest increase appears around ",
      country_summary$peak_cases_year,
      ", suggesting periodic outbreaks rather than steady transmission."
    ),
    TRUE ~
      "The pattern looks more like intermittent flare-ups than a steady shift in measles burden."
  )

  caution_sentence <- if (is.na(country_summary$coverage_incidence_correlation) || country_summary$aligned_years < 4) {
    "The overlap between coverage and incidence data is limited, so this interpretation should be treated as tentative."
  } else {
    NULL
  }

  paste(c(descriptive_sentence, relationship_sentence, qualifier_sentence, caution_sentence), collapse = " ")
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
      average_incidence = vapply(payload$country_summaries, `[[`, numeric(1), "average_incidence")
    )

    highest_coverage <- comparison_df |>
      dplyr::filter(!is.na(average_mcv1)) |>
      dplyr::slice_max(order_by = average_mcv1, n = 1, with_ties = FALSE)

    lowest_incidence <- comparison_df |>
      dplyr::filter(!is.na(average_incidence)) |>
      dplyr::slice_min(order_by = average_incidence, n = 1, with_ties = FALSE)

    if (nrow(highest_coverage) > 0 && nrow(lowest_incidence) > 0) {
      if (identical(highest_coverage$country[[1]], lowest_incidence$country[[1]])) {
        comparison_sentence <- paste0(
          highest_coverage$country[[1]],
          " combines the highest average MCV1 coverage with the lowest average measles incidence in this comparison, which is consistent with stronger outbreak control."
        )
      } else {
        comparison_sentence <- paste0(
          highest_coverage$country[[1]],
          " maintains the higher average MCV1 coverage, while ",
          lowest_incidence$country[[1]],
          " has the lower average measles incidence, suggesting the relationship is directionally protective but not explained by coverage alone."
        )
      }
    }
  }

  paste(
    paste(country_sentences, collapse = " "),
    comparison_sentence,
    sep = "\n\n"
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
    " Write 4 to 6 sentences in plain language for a public health audience. ",
    "Blend a brief descriptive setup with a more elaborate interpretation. ",
    "Use one short descriptive sentence to orient the reader, then spend most of the summary interpreting what the patterns may mean. ",
    "Do not restate obvious details such as the number of years, missing-data counts, exact stable percentages, or what is directly visible in the charts. ",
    "Interpret the relationship between MCV1 coverage and measles incidence. ",
    "State whether higher vaccination coverage appears to align with lower measles burden, whether declines in coverage seem to be followed by spikes in cases, and whether low cases under stable coverage suggest effective herd immunity. ",
    "Include concise descriptive context such as overall coverage/incidence level or whether outbreaks appear intermittent, but keep the emphasis on interpretation. ",
    "Use cautious language when the evidence is mixed or limited, but do not overemphasize missingness. ",
    "Use insight-driven phrasing such as 'this suggests' or 'this may indicate' when appropriate. ",
    "Make clear conclusions about what the time-series and scatter plots imply. ",
    "Do not begin with a 'Selected countries' label or list. ",
    "Avoid bullet points, avoid mentioning JSON, and do not invent facts not present in the structured data.\n\n",
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
