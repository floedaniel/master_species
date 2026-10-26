db_path <- "data/master_species.sqlite"
xlsx_path <- "data/master_species.xlsx"
schema_path <- "sql/schema.sql"

species_fields <- c(
  "eppocode", "fullname", "authdesc", "kingdom", "phylum", "class", "order",
  "family", "genus", "eppo_list", "eppo_status", "date_flagged"
)
assessment_fields <- c("assessor", "status", "hours", "batch", "ai", "endnote", "comment")
event_fields <- c(added = "eppo_year_added", deleted = "eppo_year_deleted", transient = "eppo_year_transient")
default_status <- "not started"

# Connection ----------------------------------------------------------------

db_connect <- function(path = db_path) {
  con <- dbConnect(SQLite(), path)
  dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

create_schema <- function(con, schema = schema_path) {
  read_file(schema) |>
    str_split_1(";") |>
    str_trim() |>
    discard(\(sql) sql == "" || str_detect(sql, "^(--[^\n]*\n?)*$")) |>
    walk(\(sql) dbExecute(con, sql))
}

write_tables <- function(con, tables) {
  table_order <- c("assessors", "statuses", "species", "assessments", "eppo_list_events")
  dbWithTransaction(con, {
    walk(intersect(table_order, names(tables)), \(name) dbAppendTable(con, name, tables[[name]]))
  })
}

# Create the database on first run, importing the Excel file. A database from
# the first app version (single wide species table) is converted in place; the
# old table is kept as species_legacy and its lookup tables are reused.
init_db <- function(path = db_path, xlsx = xlsx_path, schema = schema_path) {
  fresh <- !file.exists(path)
  con <- db_connect(path)

  legacy <- !fresh && "species" %in% dbListTables(con) && !"assessments" %in% dbListTables(con)
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
    map(\(v) if (length(v) == 0 || identical(v, "")) NA else v)
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
    dbExecute(con, "DELETE FROM eppo_list_events WHERE species_id = ?", params = list(species_id))
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
