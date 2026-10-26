test_that("init_db imports every species once", {
  con <- local_test_db()
  view <- species_view(con)

  expect_equal(nrow(view), 318)
  expect_true(all(c("eppo_year_added", "eppo_year_deleted", "eppo_year_transient") %in% names(view)))
})

test_that("save_species adds a new species with assessment and events", {
  con <- local_test_db()
  values <- list(
    eppocode = "NEWSPP", fullname = "Novus testus", status = "in progress",
    ai = TRUE, eppo_year_added = 2026L
  )

  id <- save_species(con, values)
  row <- species_view(con) |> filter(species_id == !!id)

  expect_equal(row$fullname, "Novus testus")
  expect_equal(row$status, "in progress")
  expect_true(row$ai)
  expect_equal(row$eppo_year_added, 2026L)
})

test_that("save_species updates and logs only the changed fields", {
  con <- local_test_db()
  old <- species_view(con) |> slice(1)
  values <- values_from_view(old)
  values$status <- "on hold"
  values$hours <- 7

  save_species(con, values, old$species_id, changed_by = "tester")
  new <- species_view(con) |> filter(species_id == !!old$species_id)
  log <- get_change_log(con, old$species_id)

  expect_equal(new$status, "on hold")
  expect_equal(new$hours, 7)
  expect_equal(new$fullname, old$fullname)
  expect_false(is.na(new$updated_at))
  expect_setequal(log$field, c("status", "hours"))
  expect_equal(unique(log$changed_by), "tester")
})

test_that("clearing a year removes the event", {
  con <- local_test_db()
  old <- species_view(con) |>
    filter(!is.na(eppo_year_added)) |>
    slice(1)
  values <- values_from_view(old)
  values$eppo_year_added <- NA

  save_species(con, values, old$species_id)

  expect_true(is.na(species_view(con) |> filter(species_id == !!old$species_id) |> pull(eppo_year_added)))
})

test_that("validate_species rejects missing and duplicate EPPO codes", {
  con <- local_test_db()
  first <- species_view(con) |> slice(1)
  second <- species_view(con) |> slice(2)

  expect_match(validate_species(con, list(eppocode = NA)), "required")
  expect_match(validate_species(con, list(eppocode = second$eppocode), first$species_id), "already exists")
  expect_null(validate_species(con, list(eppocode = first$eppocode), first$species_id))
  expect_null(validate_species(con, list(eppocode = "UNUSED")))
})

test_that("the database rejects values outside the lookup lists", {
  con <- local_test_db()

  expect_error(save_species(con, list(eppocode = "BADSPP", status = "not a status")))
  expect_equal(nrow(filter(species_view(con), eppocode == "BADSPP")), 0)
})

test_that("a first-version database is converted to the tidy layout", {
  skip_if_not(file.exists(xlsx_fixture))
  path <- withr::local_tempfile(fileext = ".sqlite")
  legacy <- dbConnect(SQLite(), path)
  raw <- read_excel(xlsx_fixture, sheet = "Master species") |>
    mutate(id = row_number(), added_at = "2026-10-26 10:00:00", date_flagged = format(as.Date(date_flagged)))
  dbWriteTable(legacy, "species", raw)
  # Lookup tables as the first version created them
  walk(c("assessors", "statuses", "ai_values"), \(t) {
    dbExecute(legacy, paste("CREATE TABLE", t, "(name TEXT PRIMARY KEY)"))
  })
  dbAppendTable(legacy, "assessors", tibble(name = unique(na.omit(raw$assessor))))
  dbAppendTable(legacy, "statuses", tibble(name = unique(na.omit(raw$completed))))
  dbDisconnect(legacy)

  con <- init_db(path, xlsx_fixture, schema_fixture)
  withr::defer(dbDisconnect(con))

  expect_equal(nrow(species_view(con)), 318)
  expect_true("species_legacy" %in% dbListTables(con))
  expect_false("ai_values" %in% dbListTables(con))
  expect_false(anyNA(species_view(con)$status))
})

test_that("a new species without a status is 'not started'", {
  con <- local_test_db()

  id <- save_species(con, list(eppocode = "NOSTAT"))

  expect_equal(species_view(con) |> filter(species_id == !!id) |> pull(status), "not started")
})

test_that("ensure_status fills in missing assessments and statuses once", {
  con <- local_test_db()
  dbExecute(con, "DELETE FROM assessments WHERE species_id <= 3")
  dbExecute(con, "UPDATE assessments SET status = NULL WHERE species_id BETWEEN 4 AND 6")

  ensure_status(con)
  ensure_status(con)
  first_six <- species_view(con) |> filter(species_id <= 6)

  expect_equal(first_six$status, rep("not started", 6))
  expect_equal(tbl(con, "assessments") |> count() |> pull(n), 318)
})
