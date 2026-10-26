# Excel copy of the database: an overview sheet laid out like the app's table,
# followed by one sheet per database table
write_master_xlsx <- function(con, path) {
  tables <- c("species", "assessments", "eppo_list_events", "change_log", "assessors", "statuses")
  sheets <- map(set_names(tables), \(t) tbl(con, t) |> collect())
  sheets$assessments <- sheets$assessments |> mutate(ai = as.logical(ai))

  c(list(overview = display_columns(species_view(con))), sheets) |>
    writexl::write_xlsx(path)
  invisible(path)
}
