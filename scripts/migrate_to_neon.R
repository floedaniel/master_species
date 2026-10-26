# One-time copy of the local SQLite database to the PostgreSQL database in
# DATABASE_URL (Neon). Run from the project root:
#   Rscript scripts/migrate_to_neon.R
# Refuses to run if the target already has species.

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
walk(c("R/db.R", "R/import.R"), source)

if (!nzchar(Sys.getenv("DATABASE_URL"))) stop("Set DATABASE_URL first (see README).")
if (!file.exists(db_path)) stop("No local database at ", db_path)

local <- init_db(url = "")
remote <- db_connect()
create_schema(remote)

counts <- copy_database(local, remote)
ensure_status(remote)

message("Copied to Neon:")
iwalk(counts, \(n, table) message(sprintf("  %-17s %4d rows", table, n)))
stopifnot(identical(nrow(species_view(remote)), nrow(species_view(local))))
message("Check passed: same number of species in both databases.")

dbDisconnect(local)
dbDisconnect(remote)
