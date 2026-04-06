# Shinyapps.io deployment script
# Update these values if your shinyapps.io account or desired app name changes.
# You can keep the credentials inline here, or replace them with Sys.getenv(...)
# calls if you prefer to read them from environment variables.

account_name <- "laurenlloyd"
account_token <- "E5CE58520D7E4401C02ECE8E148DA586"
account_secret <- "eZCSwdsWBupQEt3ajpWarQiavvPZ/+iK3vG6DDL8"

# By default this uses the current folder name as the shinyapps.io app name.
# Change this string if you want the deployed app to use a different public URL.
app_name <- basename(normalizePath(getwd()))

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  install.packages("rsconnect", repos = "https://cloud.r-project.org")
}

library(rsconnect)

rsconnect::setAccountInfo(
  name = account_name,
  token = account_token,
  secret = account_secret
)

deployment <- rsconnect::deployApp(
  appDir = getwd(),
  appName = app_name,
  launch.browser = FALSE
)

public_url <- paste0("https://", account_name, ".shinyapps.io/", app_name, "/")

cat("\nDeployment complete.\n")

if (!is.null(deployment$url) && nzchar(deployment$url)) {
  cat("Public URL:", deployment$url, "\n")
} else {
  cat("Public URL:", public_url, "\n")
}

