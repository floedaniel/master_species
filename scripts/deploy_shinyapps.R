# Deploy the app to shinyapps.io: Rscript --vanilla scripts/deploy_shinyapps.R
# shinyapps.io can't receive environment variables from rsconnect, so the app
# is staged in a temporary folder with a .Renviron holding only DATABASE_URL
# (read from this project's .Renviron). Nothing is written into the project.

stage <- file.path(tempdir(), "master-species")
unlink(stage, recursive = TRUE)
dir.create(stage)
file.copy(c("app.R", "R", "sql", "renv.lock"), stage, recursive = TRUE)

readRenviron(".Renviron")
url <- Sys.getenv("DATABASE_URL")
if (!nzchar(url)) stop("DATABASE_URL is not set in .Renviron")
writeLines(paste0("DATABASE_URL=", url), file.path(stage, ".Renviron"))

rsconnect::deployApp(
  appDir = stage,
  appFiles = list.files(stage, recursive = TRUE, all.files = TRUE),
  appName = "master-species",
  appTitle = "Master species",
  account = "danielapp",
  server = "shinyapps.io",
  launch.browser = FALSE,
  forceUpdate = TRUE
)
unlink(stage, recursive = TRUE)
