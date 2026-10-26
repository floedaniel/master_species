# Browser test: the add/edit form must bind its inputs. A JS error while
# binding (e.g. a selectize plugin clash with DT's column filters) leaves
# every field unbound and Save silently does nothing.
test_that("the species form binds its inputs in the browser", {
  skip_on_cran()
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")

  # Run the app on a throwaway copy so the live database is never touched
  app_dir <- withr::local_tempdir()
  file.copy(test_path("../../app.R"), app_dir)
  file.copy(test_path("../../R"), app_dir, recursive = TRUE)
  file.copy(test_path("../../sql"), app_dir, recursive = TRUE)
  dir.create(file.path(app_dir, "data"))
  file.copy(xlsx_fixture, file.path(app_dir, "data"))

  app <- shinytest2::AppDriver$new(app_dir, load_timeout = 60000)
  withr::defer(app$stop())

  app$click("add", wait_ = FALSE)
  app$wait_for_js("$('#form-save').length > 0")
  app$wait_for_idle()

  expect_true(app$get_js("$('#form-save').hasClass('shiny-bound-input')"))
  expect_true(app$get_js("$('#form-status').hasClass('shiny-bound-input')"))
})

test_that("the download button returns the xlsx export", {
  skip_on_cran()
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")

  app_dir <- withr::local_tempdir()
  file.copy(test_path("../../app.R"), app_dir)
  file.copy(test_path("../../R"), app_dir, recursive = TRUE)
  file.copy(test_path("../../sql"), app_dir, recursive = TRUE)
  dir.create(file.path(app_dir, "data"))
  file.copy(xlsx_fixture, file.path(app_dir, "data"))

  app <- shinytest2::AppDriver$new(app_dir, load_timeout = 60000)
  withr::defer(app$stop())

  path <- app$get_download("download")

  expect_match(basename(path), "^master_species_[0-9]{4}-[0-9]{2}-[0-9]{2}[.]xlsx$")
  expect_equal(nrow(read_excel(path, sheet = "overview")), 318)
})

test_that("empty table cells show a grey dash", {
  skip_on_cran()
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")

  app_dir <- withr::local_tempdir()
  file.copy(test_path("../../app.R"), app_dir)
  file.copy(test_path("../../R"), app_dir, recursive = TRUE)
  file.copy(test_path("../../sql"), app_dir, recursive = TRUE)
  dir.create(file.path(app_dir, "data"))
  file.copy(xlsx_fixture, file.path(app_dir, "data"))

  app <- shinytest2::AppDriver$new(app_dir, load_timeout = 60000)
  withr::defer(app$stop())
  app$wait_for_js("$('#table-table tbody tr').length > 0")

  # Row 1 (XANTGA) has no hours in the workbook
  hours_col <- app$get_js("$('#table-table thead tr:first th').map((i, e) => $(e).text()).get().indexOf('hours')")
  cell <- sprintf("$('#table-table tbody tr:first td').eq(%d)", hours_col)
  expect_equal(app$get_js(paste0(cell, ".text()")), "–")
  expect_true(app$get_js(paste0(cell, ".find('.text-muted').length == 1")))
})

test_that("saving an edit from the browser updates the database", {
  skip_on_cran()
  skip_if_not(file.exists(xlsx_fixture), "master_species.xlsx not available")

  app_dir <- withr::local_tempdir()
  file.copy(test_path("../../app.R"), app_dir)
  file.copy(test_path("../../R"), app_dir, recursive = TRUE)
  file.copy(test_path("../../sql"), app_dir, recursive = TRUE)
  dir.create(file.path(app_dir, "data"))
  file.copy(xlsx_fixture, file.path(app_dir, "data"))

  app <- shinytest2::AppDriver$new(app_dir, load_timeout = 60000)
  withr::defer(app$stop())

  app$set_inputs(`table-table_rows_selected` = 1, allow_no_input_binding_ = TRUE)
  app$click("edit", wait_ = FALSE)
  app$wait_for_js("$('#form-save').hasClass('shiny-bound-input')")
  expect_equal(app$get_js("$('#form-ai option:selected').text()"), "— not set —")
  expect_equal(app$get_js("$('#form-status option:selected').text()"), "not started")
  expect_equal(app$get_js("$('#form-hours').attr('placeholder')"), "not set")
  app$set_inputs(`form-status` = "completed", `form-ai` = "TRUE")
  app$click("form-save")
  app$wait_for_js("$('.modal').length == 0")

  con <- dbConnect(SQLite(), file.path(app_dir, "data", "master_species.sqlite"))
  withr::defer(dbDisconnect(con))
  saved <- species_view(con) |> slice(1)
  expect_equal(saved$status, "completed")
  expect_true(saved$ai)
  expect_setequal(get_change_log(con, saved$species_id)$field, c("status", "ai"))
})
