# Shinyapps.io deployment script
# Specify your shinyapps.io credentials in the three variables below.
# Replace these values if your shinyapps.io name, token, or secret ever change.

account_name <- "laurenlloyd"
account_token <- "E5CE58520D7E4401C02ECE8E148DA586"
account_secret <- "eZCSwdsWBupQEt3ajpWarQiavvPZ/+iK3vG6DDL8"

# By default the app name matches the current folder name.
# Change app_name if you want a different shinyapps.io URL slug.
app_name <- basename(normalizePath(getwd()))
local_library <- file.path(getwd(), ".Rlibs")
app_files <- c("app.R", "R")

.libPaths(c(local_library, .libPaths()))

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  if (!dir.exists(local_library)) {
    dir.create(local_library, recursive = TRUE)
  }
  install.packages(
    "rsconnect",
    lib = local_library,
    repos = "https://cloud.r-project.org"
  )
}

library(rsconnect)

rsconnect::setAccountInfo(
  name = account_name,
  token = account_token,
  secret = account_secret
)

deployment <- rsconnect::deployApp(
  appDir = getwd(),
  appFiles = app_files,
  appName = app_name,
  launch.browser = FALSE
)

if (is.list(deployment) && !is.null(deployment$appName) && nzchar(deployment$appName)) {
  app_name <- deployment$appName
}

deployed_apps <- tryCatch(
  rsconnect::applications(account = account_name, server = "shinyapps.io"),
  error = function(e) NULL
)

public_url <- NULL

if (!is.null(deployed_apps) && nrow(deployed_apps) > 0) {
  matched_app <- deployed_apps[deployed_apps$name == app_name, , drop = FALSE]

  if (nrow(matched_app) > 0 && "url" %in% names(matched_app)) {
    public_url <- matched_app$url[[1]]
  }
}

if (is.null(public_url) || !nzchar(public_url)) {
  if (is.character(deployment) && length(deployment) >= 1 && nzchar(deployment[[1]])) {
    public_url <- deployment[[1]]
  }
}

if (is.null(public_url) || !nzchar(public_url)) {
  public_url <- sprintf("https://%s.shinyapps.io/%s/", account_name, app_name)
}

cat("\nDeployment complete.\n")
cat("Public URL:", public_url, "\n")
