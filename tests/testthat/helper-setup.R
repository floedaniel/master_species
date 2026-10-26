suppressPackageStartupMessages({
  library(DBI)
  library(DT)
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

# Tests must never reach the live database, including apps they start
withr::local_envvar(DATABASE_URL = NA, .local_envir = teardown_env())

xlsx_fixture <- test_path("../../data/master_species.xlsx")
schema_fixture <- test_path("../../sql")

# Set TEST_DATABASE_URL to a throwaway PostgreSQL database (e.g. a Neon test
# branch) to run the database tests on PostgreSQL instead of SQLite.
# Its tables are dropped and rebuilt for every test.
test_pg_url <- Sys.getenv("TEST_DATABASE_URL")
on_postgres <- nzchar(test_pg_url)

drop_all_tables <- function(con) {
  tables <- c("change_log", "eppo_list_events", "assessments", "species", "statuses", "assessors")
  walk(tables, \(t) dbExecute(con, paste("DROP TABLE IF EXISTS", t, "CASCADE")))
}

# Fresh database imported from the workbook, cleaned up when the calling test ends
local_test_db <- function(env = parent.frame()) {
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")
  if (on_postgres) {
    con <- db_connect(url = test_pg_url)
    drop_all_tables(con)
    dbDisconnect(con)
    con <- init_db(xlsx = xlsx_fixture, schema = schema_fixture, url = test_pg_url)
  } else {
    path <- withr::local_tempfile(fileext = ".sqlite", .local_envir = env)
    con <- init_db(path, xlsx_fixture, schema_fixture, url = "")
  }
  withr::defer(dbDisconnect(con), envir = env)
  con
}

# Flat list of values for save_species(), taken from one species_view() row
values_from_view <- function(row) {
  fields <- c(species_fields, assessment_fields, event_fields)
  map(set_names(fields), \(f) row[[f]])
}
