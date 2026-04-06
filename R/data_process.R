standardize_location_from_iso3 <- function(iso3) {
  suppressWarnings(countrycode::countrycode(iso3, "iso3c", "country.name"))
}

last_non_missing <- function(x) {
  values <- x[!is.na(x)]

  if (length(values) == 0) {
    return(NA_real_)
  }

  values[[length(values)]]
}

build_analysis_dataset <- function(
  owid_cases,
  owid_mcv1,
  who_data,
  population
) {
  owid_joined <- owid_cases |>
    dplyr::full_join(owid_mcv1, by = c("location", "iso3", "year"))

  who_joined <- who_data$measles_cases |>
    dplyr::full_join(who_data$mcv1, by = c("iso3", "year")) |>
    dplyr::full_join(who_data$mcv2, by = c("iso3", "year"))

  owid_joined |>
    dplyr::full_join(who_joined, by = c("iso3", "year")) |>
    dplyr::full_join(population, by = c("iso3", "year"), suffix = c("", "_wb")) |>
    dplyr::mutate(
      location = dplyr::coalesce(location, location_wb, standardize_location_from_iso3(iso3)),
      measles_cases = dplyr::coalesce(measles_cases_who, measles_cases_owid),
      mcv1 = dplyr::coalesce(mcv1_who, mcv1_owid),
      measles_incidence_per_100k = dplyr::if_else(
        !is.na(population) & population > 0 & !is.na(measles_cases),
        (measles_cases / population) * 100000,
        NA_real_
      ),
      vaccination_gap = dplyr::if_else(!is.na(mcv1), 100 - mcv1, NA_real_)
    ) |>
    dplyr::arrange(location, year) |>
    dplyr::group_by(iso3) |>
    dplyr::mutate(
      cases_yoy_pct_change = dplyr::if_else(
        !is.na(dplyr::lag(measles_cases)) & dplyr::lag(measles_cases) > 0,
        ((measles_cases - dplyr::lag(measles_cases)) / dplyr::lag(measles_cases)) * 100,
        NA_real_
      )
    ) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(location), !is.na(year)) |>
    dplyr::distinct()
}

available_country_choices <- function(data) {
  data |>
    dplyr::filter(!is.na(location)) |>
    dplyr::distinct(location) |>
    dplyr::arrange(location) |>
    dplyr::pull(location)
}

filter_country_data <- function(data, countries, year_range) {
  countries <- countries[!is.na(countries) & nzchar(countries)]

  data |>
    dplyr::filter(
      location %in% countries,
      year >= year_range[1],
      year <= year_range[2]
    ) |>
    dplyr::arrange(location, year)
}

validate_country_subset <- function(data) {
  if (nrow(data) == 0) {
    return("No rows match the selected country and year range.")
  }

  coverage_rows <- sum(!is.na(data$mcv1))
  case_rows <- sum(!is.na(data$measles_cases))

  if (coverage_rows < 2 || case_rows < 2) {
    return("Insufficient data for the selected view. Try a wider year range or another country.")
  }

  NULL
}

summarise_country_metrics <- function(data) {
  data |>
    dplyr::group_by(location) |>
    dplyr::summarise(
      years_covered = dplyr::n_distinct(year),
      latest_year = max(year, na.rm = TRUE),
      latest_measles_cases = last_non_missing(measles_cases),
      latest_mcv1 = last_non_missing(mcv1),
      latest_mcv2 = last_non_missing(mcv2_who),
      latest_incidence_per_100k = last_non_missing(measles_incidence_per_100k),
      .groups = "drop"
    ) |>
    dplyr::rename(
      "Country" = location,
      "Years Covered" = years_covered,
      "Latest Year" = latest_year,
      "Latest Reported Measles Cases" = latest_measles_cases,
      "Latest MCV1 Coverage (%)" = latest_mcv1,
      "Latest MCV2 Coverage (%)" = latest_mcv2,
      "Latest Measles Incidence (per 100k)" = latest_incidence_per_100k
    )
}

create_trend_plot_data <- function(data) {
  cases_long <- data |>
    dplyr::transmute(
      location,
      year,
      metric = "Reported measles cases",
      value = measles_cases
    )

  vaccine_long <- data |>
    dplyr::select(location, year, mcv1, mcv2_who) |>
    tidyr::pivot_longer(
      cols = c(mcv1, mcv2_who),
      names_to = "series",
      values_to = "value"
    ) |>
    dplyr::mutate(
      metric = dplyr::case_when(
        series == "mcv1" ~ "Vaccination coverage (%)",
        series == "mcv2_who" ~ "Vaccination coverage (%)",
        TRUE ~ "Vaccination coverage (%)"
      ),
      series = dplyr::case_when(
        series == "mcv1" ~ "MCV1",
        series == "mcv2_who" ~ "MCV2",
        TRUE ~ series
      )
    )

  dplyr::bind_rows(
    cases_long |> dplyr::mutate(series = "Cases"),
    vaccine_long
  ) |>
    dplyr::filter(!is.na(value))
}

create_scatter_plot_data <- function(data) {
  data |>
    dplyr::filter(!is.na(mcv1), !is.na(measles_incidence_per_100k)) |>
    dplyr::arrange(location, year) |>
    dplyr::mutate(plot_incidence = pmax(measles_incidence_per_100k, 0.01))
}

