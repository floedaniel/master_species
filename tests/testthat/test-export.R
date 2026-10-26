test_that("the xlsx export has an overview and one sheet per table", {
  con <- local_test_db()
  path <- withr::local_tempfile(fileext = ".xlsx")
  save_species(con, values_from_view(species_view(con) |> slice(1)) |> modifyList(list(status = "completed")), 1L)

  write_master_xlsx(con, path)

  expect_equal(
    excel_sheets(path),
    c("overview", "species", "assessments", "eppo_list_events", "change_log", "assessors", "statuses")
  )
  overview <- read_excel(path, sheet = "overview")
  expect_equal(nrow(overview), 318)
  expect_equal(names(overview)[1:4], c("eppocode", "fullname", "assessor", "status"))
  expect_false(any(c("species_id", "assessment_id") %in% names(overview)))
  expect_equal(overview$status[1], "completed")
  expect_equal(nrow(read_excel(path, sheet = "change_log")), 1)
})
