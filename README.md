# Master species

Shiny app for the master species list: browse, add and edit species and their
assessments. The data lives in a local SQLite database instead of Excel.

## Getting started

1. Copy `master_species.xlsx` into `data/` (it is not in the repo).
2. Open `master_species.Rproj` and run `renv::restore()` once.
3. Run the app with `shiny::runApp()`.

On first start the app imports the workbook into `data/master_species.sqlite`.
From then on the database is the source of truth and the workbook is not read again.

## Using the app

- **Filter** with the boxes above each column; empty values show as a grey `–`.
- **Add species** opens an empty form. EPPO code is required and must be unique.
- **Edit selected**: click a row, then edit. The *History* tab lists every change.
- **Download xlsx** saves a copy: an `overview` sheet like the table, plus one sheet per database table.

## Data model

Tidy tables, one per kind of thing (see `sql/schema.sql`):

| Table | One row per |
|---|---|
| `species` | species: EPPO code, names, taxonomy, EPPO list and status |
| `assessments` | assessment of a species (the app shows and edits the latest) |
| `eppo_list_events` | EPPO list event (`added` / `deleted` / `transient`) and its year |
| `change_log` | changed field: old and new value, when, by whom |
| `assessors`, `statuses` | allowed dropdown values |

Missing values are stored as `NULL`/`NA`, never as placeholder text. A species
whose work hasn't begun has status `not started`.

## Development

```r
Sys.setenv(NOT_CRAN = "true")       # also run the browser tests
testthat::test_dir("tests/testthat")
lintr::lint_dir(".")
styler::style_dir(".", exclude_dirs = "renv")
```

The tests use `data/master_species.xlsx` and are skipped when it is missing.
Browser tests run the app on a temporary copy, never on the live database.

| Path | Contents |
|---|---|
| `app.R` | UI layout and wiring |
| `R/db.R` | database: schema, import, reading and saving |
| `R/import.R` | splits the legacy workbook into tidy tables |
| `R/export.R` | xlsx download |
| `R/mod_species_table.R`, `R/mod_species_form.R` | Shiny modules |

## Backups

`data/master_species.sqlite` is not in git. Back it up separately, for example by
copying it to a shared drive, or keep a regular **Download xlsx** copy.
