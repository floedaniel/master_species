# Read the legacy Excel workbook into a list of tidy tibbles, one per table
read_master_xlsx <- function(path) {
  raw <- read_excel(path, sheet = "Master species")
  codes <- read_excel(path, sheet = "codes")

  tidy_master(raw) |>
    c(list(
      assessors = tibble(name = unique(na.omit(codes$assessor))),
      statuses = tibble(name = unique(c(default_status, na.omit(codes$status))))
    ))
}

# Split the wide legacy layout (one row per species, everything in it) into
# species, assessments and eppo_list_events. Works on the Excel sheet and on
# the species table of the first app version, which had the same columns.
tidy_master <- function(raw) {
  raw <- raw |>
    clean_names() |>
    mutate(species_id = row_number())

  species <- raw |>
    transmute(
      species_id, eppocode, fullname, authdesc,
      kingdom, phylum, class, order, family, genus,
      eppo_list = str_remove(eppo_qlist_label, " \\(formerly\\)$"),
      eppo_status,
      date_flagged = format(as.Date(date_flagged))
    )

  # Every species gets an assessment; one without a status has not been started
  assessments <- raw |>
    transmute(
      species_id, assessor,
      status = coalesce(completed, default_status),
      hours = suppressWarnings(as.numeric(hours)),
      batch = as.integer(batch),
      ai = ai == "YES",
      endnote = str_to_sentence(end_note),
      comment
    )

  eppo_list_events <- raw |>
    select(species_id, added = eppo_year_add, deleted = eppo_year_del, transient = eppo_year_transient) |>
    pivot_longer(-species_id, names_to = "event", values_to = "year", values_drop_na = TRUE) |>
    mutate(year = as.integer(year))

  list(species = species, assessments = assessments, eppo_list_events = eppo_list_events)
}
