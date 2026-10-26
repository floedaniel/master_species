suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(dplyr)
  library(dbplyr, warn.conflicts = FALSE)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(readr)
  library(readxl)
  library(janitor, warn.conflicts = FALSE)
})

walk(list.files(test_path("../../R"), full.names = TRUE), source)

xlsx_fixture <- test_path("../../data/master_species.xlsx")
schema_fixture <- test_path("../../sql/schema.sql")

# Fresh database imported from the workbook, removed when the calling test ends
local_test_db <- function(env = parent.frame()) {
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")
  path <- withr::local_tempfile(fileext = ".sqlite", .local_envir = env)
  con <- init_db(path, xlsx_fixture, schema_fixture)
  withr::defer(dbDisconnect(con), envir = env)
  con
}

# Flat list of values for save_species(), taken from one species_view() row
values_from_view <- function(row) {
  fields <- c(species_fields, assessment_fields, event_fields)
  map(set_names(fields), \(f) row[[f]])
}
