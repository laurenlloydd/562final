`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0 || all(is.na(x))) {
    return(y)
  }

  x
}

fetch_text_response <- function(url, query = list()) {
  request <- httr2::request(url) |>
    httr2::req_user_agent("glhlth562-final-shiny/1.0")

  if (length(query) > 0) {
    request <- do.call(httr2::req_url_query, c(list(request), query))
  }

  response <- request |>
    httr2::req_timeout(60) |>
    httr2::req_perform()

  httr2::resp_body_string(response)
}

fetch_json_response <- function(url, query = list()) {
  jsonlite::fromJSON(
    fetch_text_response(url, query = query),
    simplifyVector = TRUE,
    flatten = TRUE
  )
}

fetch_csv_response <- function(url) {
  readr::read_csv(
    I(fetch_text_response(url)),
    show_col_types = FALSE,
    progress = FALSE
  )
}

fetch_owid_indicator_response <- function(indicator_id, suffix = "data") {
  fetch_json_response(
    sprintf("https://api.ourworldindata.org/v1/indicators/%s.%s.json", indicator_id, suffix)
  )
}

fetch_owid_indicator_data <- function(indicator_id, value_name, value_transform = as.numeric) {
  data_payload <- fetch_owid_indicator_response(indicator_id, suffix = "data")
  metadata_payload <- fetch_owid_indicator_response(indicator_id, suffix = "metadata")

  entity_lookup <- tibble::as_tibble(metadata_payload$dimensions$entities$values) |>
    dplyr::transmute(
      entity_id = as.integer(id),
      location = name,
      iso3 = code
    )

  tibble::tibble(
    entity_id = as.integer(data_payload$entities),
    year = as.integer(data_payload$years),
    raw_value = data_payload$values
  ) |>
    dplyr::left_join(entity_lookup, by = "entity_id") |>
    dplyr::transmute(
      location,
      iso3,
      year,
      !!value_name := value_transform(raw_value)
    ) |>
    dplyr::filter(!is.na(iso3), nchar(iso3) == 3, !is.na(year)) |>
    dplyr::distinct()
}

fetch_owid_measles_cases <- function(
  url = "https://ourworldindata.org/grapher/reported-cases-of-measles.csv"
) {
  fetch_csv_response(url) |>
    dplyr::transmute(
      location = Entity,
      iso3 = Code,
      year = as.integer(Year),
      measles_cases_owid = as.numeric(`Measles - number of reported cases`)
    ) |>
    dplyr::filter(!is.na(iso3), nchar(iso3) == 3, !is.na(year)) |>
    dplyr::distinct()
}

fetch_owid_mcv1 <- function(
  url = "https://ourworldindata.org/grapher/share-of-children-vaccinated-against-measles.csv"
) {
  fetch_csv_response(url) |>
    dplyr::transmute(
      location = Entity,
      iso3 = Code,
      year = as.integer(Year),
      mcv1_owid = as.numeric(`Measles, first dose (MCV1)`)
    ) |>
    dplyr::filter(!is.na(iso3), nchar(iso3) == 3, !is.na(year)) |>
    dplyr::distinct()
}

fetch_owid_measles_prevalence_children <- function(indicator_id = 1182306) {
  fetch_owid_indicator_data(indicator_id, "measles_prevalence_children")
}

fetch_owid_vaccine_attitudes <- function(indicator_id = 1075290) {
  fetch_owid_indicator_data(indicator_id, "vaccine_attitudes_disagree_effective")
}

fetch_owid_regions <- function(indicator_id = 900801) {
  fetch_owid_indicator_data(
    indicator_id,
    "owid_region",
    value_transform = as.character
  ) |>
    dplyr::arrange(iso3, dplyr::desc(year)) |>
    dplyr::group_by(iso3) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::select(location, iso3, owid_region)
}

fetch_who_indicator <- function(indicator_code, value_name) {
  base_url <- paste0("https://ghoapi.azureedge.net/api/", indicator_code)
  next_url <- base_url
  pages <- list()

  while (!is.null(next_url) && nzchar(next_url)) {
    payload <- jsonlite::fromJSON(
      fetch_text_response(next_url),
      simplifyVector = TRUE,
      flatten = TRUE
    )
    pages[[length(pages) + 1]] <- tibble::as_tibble(payload$value %||% data.frame())
    next_url <- payload[["@odata.nextLink"]] %||% NULL
  }

  dplyr::bind_rows(pages) |>
    dplyr::filter(
      SpatialDimType == "COUNTRY",
      TimeDimType == "YEAR",
      !is.na(SpatialDim),
      !is.na(TimeDim)
    ) |>
    dplyr::transmute(
      iso3 = SpatialDim,
      year = as.integer(TimeDim),
      !!value_name := as.numeric(NumericValue)
    ) |>
    dplyr::filter(!is.na(iso3), nchar(iso3) == 3, !is.na(year)) |>
    dplyr::distinct()
}

fetch_who_measles_data <- function() {
  list(
    mcv1 = fetch_who_indicator("WHS8_110", "mcv1_who"),
    mcv2 = fetch_who_indicator("MCV2", "mcv2_who"),
    measles_cases = fetch_who_indicator("WHS3_62", "measles_cases_who")
  )
}

fetch_world_bank_population_page <- function(page, per_page = 20000) {
  payload <- fetch_json_response(
    "https://api.worldbank.org/v2/country/all/indicator/SP.POP.TOTL",
    query = list(format = "json", per_page = per_page, page = page)
  )

  list(
    meta = payload[[1]],
    data = tibble::as_tibble(payload[[2]])
  )
}

fetch_world_bank_population <- function(start_year = 2000, end_year = 2025) {
  first_page <- fetch_world_bank_population_page(1)
  total_pages <- as.integer(first_page$meta$pages %||% 1)
  records <- list(first_page$data)

  if (total_pages > 1) {
    for (page in seq.int(2, total_pages)) {
      records[[length(records) + 1]] <- fetch_world_bank_population_page(page)$data
    }
  }

  dplyr::bind_rows(records) |>
    dplyr::transmute(
      location = country.value,
      iso3 = countryiso3code,
      year = as.integer(date),
      population = as.numeric(value)
    ) |>
    dplyr::filter(
      !is.na(iso3),
      nchar(iso3) == 3,
      !is.na(year),
      year >= start_year,
      year <= end_year
    ) |>
    dplyr::distinct()
}

fetch_all_runtime_data <- function(start_year = 2000, end_year = 2025) {
  owid_cases <- fetch_owid_measles_cases()
  owid_mcv1 <- fetch_owid_mcv1()
  owid_measles_prevalence <- fetch_owid_measles_prevalence_children()
  owid_vaccine_attitudes <- fetch_owid_vaccine_attitudes()
  owid_regions <- fetch_owid_regions()
  who_data <- fetch_who_measles_data()
  population <- fetch_world_bank_population(start_year = start_year, end_year = end_year)

  list(
    owid_cases = owid_cases,
    owid_mcv1 = owid_mcv1,
    owid_measles_prevalence = owid_measles_prevalence,
    owid_vaccine_attitudes = owid_vaccine_attitudes,
    owid_regions = owid_regions,
    who_data = who_data,
    population = population
  )
}

