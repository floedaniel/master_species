db_path <- "data/master_species.sqlite"
xlsx_path <- "data/master_species.xlsx"
schema_dir <- "sql"

species_fields <- c(
  "eppocode", "fullname", "authdesc", "kingdom", "phylum", "class", "order",
  "family", "genus", "eppo_list", "eppo_status", "date_flagged"
)
assessment_fields <- c("assessor", "status", "hours", "batch", "ai", "endnote", "comment")
event_fields <- c(added = "eppo_year_added", deleted = "eppo_year_deleted", transient = "eppo_year_transient")
default_status <- "not started"
# Fields that are not text; PostgreSQL needs each value in its column's type
field_types <- c(
  hours = "double", batch = "integer", ai = "logical",
  eppo_year_added = "integer", eppo_year_deleted = "integer", eppo_year_transient = "integer"
)

# Connection ----------------------------------------------------------------

# PostgreSQL (Neon) when `url` is set, otherwise the local SQLite file
db_connect <- function(path = db_path, url = Sys.getenv("DATABASE_URL")) {
  if (nzchar(url)) {
    return(do.call(dbConnect, c(list(RPostgres::Postgres()), parse_pg_url(url))))
  }
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

# Split postgresql://user:password@host:port/dbname?key=value into dbConnect()
# arguments; RPostgres does not parse connection URIs itself
parse_pg_url <- function(url) {
  parts <- str_match(url, "^postgres(?:ql)?://([^:@]+)(?::([^@]*))?@([^:/?]+)(?::(\\d+))?/([^?]+)(?:\\?(.*))?$")
  if (is.na(parts[1])) {
    stop("DATABASE_URL is not a postgresql://user:password@host/dbname URL")
  }
  query <- if (is.na(parts[7])) character() else str_split_1(parts[7], "&")
  options <- set_names(str_remove(query, "^[^=]*="), str_extract(query, "^[^=]*"))
  list(
    user = URLdecode(parts[2]), password = URLdecode(parts[3]),
    host = parts[4], port = parts[5], dbname = parts[6]
  ) |>
    discard(is.na) |>
    c(as.list(options))
}

is_postgres <- function(con) inherits(con, "PqConnection")

create_schema <- function(con, dir = schema_dir) {
  file <- if (is_postgres(con)) "schema_postgres.sql" else "schema.sql"
  # Drop comment lines first so a ";" inside a comment can't split a statement
  read_lines(file.path(dir, file)) |>
    discard(\(line) str_detect(line, "^\\s*--")) |>
    paste(collapse = "\n") |>
    str_split_1(";") |>
    str_trim() |>
    discard(\(sql) sql == "") |>
    walk(\(sql) dbExecute(con, sql))
}

write_tables <- function(con, tables) {
  table_order <- c("assessors", "statuses", "species", "assessments", "eppo_list_events", "change_log")
  dbWithTransaction(con, {
    walk(intersect(table_order, names(tables)), \(name) dbAppendTable(con, name, tables[[name]]))
    reset_ids(con)
  })
}

# Rows were written with explicit ids, so move PostgreSQL's id counters past them
reset_ids <- function(con) {
  if (!is_postgres(con)) {
    return(invisible())
  }
  ids <- c(species = "species_id", assessments = "assessment_id", change_log = "change_id")
  sql <- "SELECT setval(pg_get_serial_sequence('%1$s', '%2$s'), COALESCE(MAX(%2$s), 0) + 1, false) FROM %1$s"
  iwalk(ids, \(id, table) dbExecute(con, sprintf(sql, table, id)))
}

# Copy every table of `from` into the empty database `to` (e.g. local SQLite to Neon)
copy_database <- function(from, to) {
  if (tbl(to, "species") |> count() |> pull(n) > 0) {
    stop("The target database already has species; nothing copied.")
  }
  tables <- c("assessors", "statuses", "species", "assessments", "eppo_list_events", "change_log")
  data <- map(set_names(tables), \(t) tbl(from, t) |> collect())
  data$assessments <- data$assessments |> mutate(ai = as.logical(ai))
  write_tables(to, data)
  invisible(map_int(data, nrow))
}

# Create the database on first run, importing the Excel file. A database from
# the first app version (single wide species table) is converted in place; the
# old table is kept as species_legacy and its lookup tables are reused.
init_db <- function(path = db_path, xlsx = xlsx_path, schema = schema_dir, url = Sys.getenv("DATABASE_URL")) {
  con <- db_connect(path, url)
  tables <- dbListTables(con)
  fresh <- !"species" %in% tables

  legacy <- !fresh && !"assessments" %in% tables
  if (legacy) {
    dbExecute(con, "ALTER TABLE species RENAME TO species_legacy")
  }

  create_schema(con, schema)

  if (fresh) {
    write_tables(con, read_master_xlsx(xlsx))
  }
  if (legacy) {
    old <- tbl(con, "species_legacy") |>
      arrange(id) |>
      collect() |>
      select(-id, -added_at, -any_of("updated_at"))
    new_statuses <- tibble(name = setdiff(default_status, get_lookup(con, "statuses")))
    write_tables(con, c(tidy_master(old), list(statuses = new_statuses)))
    dbExecute(con, "DROP TABLE IF EXISTS ai_values")
  }
  ensure_status(con)
  con
}

# Give every species an assessment with a status, so "not started" is a real
# value rather than a missing one. Does nothing once the data is complete.
ensure_status <- function(con) {
  if (!default_status %in% get_lookup(con, "statuses")) {
    dbAppendTable(con, "statuses", tibble(name = default_status))
  }
  unassessed <- tbl(con, "species") |>
    anti_join(tbl(con, "assessments"), by = "species_id") |>
    transmute(species_id, status = !!default_status)
  blank <- tbl(con, "assessments") |>
    filter(is.na(status)) |>
    transmute(assessment_id, status = !!default_status)

  dbWithTransaction(con, {
    rows_append(tbl(con, "assessments"), unassessed, in_place = TRUE)
    rows_update(tbl(con, "assessments"), blank, by = "assessment_id", unmatched = "ignore", in_place = TRUE)
  })
  invisible()
}

# Reading -------------------------------------------------------------------

get_lookup <- function(con, table) {
  tbl(con, table) |> pull(name)
}

# One row per species, with its latest assessment and EPPO list years
species_view <- function(con) {
  latest <- tbl(con, "assessments") |>
    group_by(species_id) |>
    filter(assessment_id == max(assessment_id, na.rm = TRUE)) |>
    ungroup() |>
    select(-added_at, -updated_at)

  years <- tbl(con, "eppo_list_events") |>
    collect() |>
    mutate(event = factor(event, levels = names(event_fields))) |>
    pivot_wider(
      names_from = event, values_from = year,
      names_prefix = "eppo_year_", names_expand = TRUE
    )

  tbl(con, "species") |>
    left_join(latest, by = "species_id") |>
    arrange(species_id) |>
    collect() |>
    left_join(years, by = "species_id") |>
    mutate(ai = as.logical(ai))
}

# Assessment columns first, internal ids and timestamps dropped
display_columns <- function(view) {
  first <- c("eppocode", "fullname", "assessor", "status", "hours", "batch", "ai", "endnote", "comment")
  hidden <- c("species_id", "assessment_id", "added_at", "updated_at")
  view |> select(any_of(first), everything(), -any_of(hidden))
}

# Writing -------------------------------------------------------------------

# Returns an error message, or NULL when `values` can be saved
validate_species <- function(con, values, species_id = NULL) {
  if (is.na(values$eppocode)) {
    return("EPPO code is required.")
  }
  exclude <- c(species_id, -1L)
  taken <- tbl(con, "species") |>
    filter(eppocode == !!values$eppocode, !species_id %in% !!exclude) |>
    count() |>
    pull(n)
  if (taken > 0) {
    return(sprintf("EPPO code %s already exists.", values$eppocode))
  }
  NULL
}

# Add (species_id = NULL) or update a species from a flat named list of values.
# Updates write one change_log row per changed field. Returns the species_id.
save_species <- function(con, values, species_id = NULL, changed_by = NA_character_) {
  fields <- c(species_fields, assessment_fields, event_fields)
  values <- map(set_names(fields), \(f) values[[f]]) |>
    map(\(v) if (length(v) == 0 || identical(v, "")) NA else v) |>
    imap(\(v, f) as.vector(v, mode = coalesce(field_types[f], "character")))
  values$status <- coalesce(values$status, default_status)
  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC")

  dbWithTransaction(con, {
    if (is.null(species_id)) {
      dbAppendTable(con, "species", as_tibble(values[species_fields]))
      species_id <- tbl(con, "species") |>
        filter(eppocode == !!values$eppocode) |>
        pull(species_id)
      old <- NULL
    } else {
      old <- species_view(con) |> filter(species_id == !!species_id)
      update_rows(con, "species", tibble(species_id, !!!values[species_fields], updated_at = now), "species_id")
    }

    if (!is.null(old) && !is.na(old$assessment_id)) {
      row <- tibble(assessment_id = old$assessment_id, !!!values[assessment_fields], updated_at = now)
      update_rows(con, "assessments", row, "assessment_id")
    } else {
      dbAppendTable(con, "assessments", tibble(species_id, !!!values[assessment_fields]))
    }

    events <- tibble(species_id, event = names(event_fields), year = as.integer(unlist(values[event_fields]))) |>
      filter(!is.na(year))
    rows_delete(
      tbl(con, "eppo_list_events"), tibble(species_id),
      by = "species_id", unmatched = "ignore", in_place = TRUE, copy = "inline"
    )
    dbAppendTable(con, "eppo_list_events", events)

    if (!is.null(old)) {
      changes <- diff_values(old, values) |> mutate(species_id, changed_at = now, changed_by)
      dbAppendTable(con, "change_log", changes)
    }
  })
  species_id
}

# Update the rows of `table` matching `data` on `by`
update_rows <- function(con, table, data, by) {
  rows_update(tbl(con, table), data, by = by, unmatched = "ignore", in_place = TRUE, copy = "inline")
}

# Long tibble of the fields whose value differs between `old` (one-row view) and `new` (list)
diff_values <- function(old, new) {
  fields <- c(species_fields, assessment_fields, event_fields)
  as_text <- \(v) if (length(v) == 0 || is.na(v)) NA_character_ else as.character(v)
  tibble(
    field = unname(fields),
    old_value = map_chr(fields, \(f) as_text(old[[f]])),
    new_value = map_chr(fields, \(f) as_text(new[[f]]))
  ) |>
    filter(!map2_lgl(old_value, new_value, identical))
}

get_change_log <- function(con, species_id) {
  tbl(con, "change_log") |>
    filter(species_id == !!species_id) |>
    arrange(desc(change_id)) |>
    select(changed_at, changed_by, field, old_value, new_value) |>
    collect()
}
