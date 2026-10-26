test_that("workbook splits into tidy tables", {
  skip_if_not(file.exists(xlsx_fixture))
  tables <- read_master_xlsx(xlsx_fixture)

  expect_named(tables, c("species", "assessments", "eppo_list_events", "assessors", "statuses"), ignore.order = TRUE)
  expect_equal(nrow(tables$species), 318)
  expect_false(anyDuplicated(tables$species$eppocode) > 0)
  expect_setequal(unique(na.omit(tables$species$eppo_list)), c("A1 list", "A2 list", "Alert list"))
})

test_that("every species gets an assessment, unassessed ones 'not started'", {
  skip_if_not(file.exists(xlsx_fixture))
  tables <- read_master_xlsx(xlsx_fixture)

  expect_equal(nrow(tables$assessments), nrow(tables$species))
  expect_false(anyNA(tables$assessments$status))
  expect_gt(sum(tables$assessments$status == "not started"), 0)
  expect_true("not started" %in% tables$statuses$name)
  expect_type(tables$assessments$ai, "logical")
  expect_setequal(unique(na.omit(tables$assessments$endnote)), "Updated")
})

test_that("EPPO list years become one row per event", {
  skip_if_not(file.exists(xlsx_fixture))
  events <- read_master_xlsx(xlsx_fixture)$eppo_list_events

  expect_setequal(unique(events$event), c("added", "deleted", "transient"))
  expect_false(anyNA(events$year))
  expect_equal(anyDuplicated(events[c("species_id", "event")]), 0)
})
