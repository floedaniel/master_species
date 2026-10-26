# Master species

Shiny app for the master species list: browse, add and edit species and their
assessments. The data lives in a PostgreSQL database on [Neon](https://neon.tech)
(the old Excel file on SharePoint is no longer the source of truth).

## Getting started

1. Open `master_species.Rproj` and run `renv::restore()` once.
2. Create a file `.Renviron` in the project folder (it is git-ignored, never commit it):
   ```
   DATABASE_URL=postgresql://...      # Neon branch "main": the live data
   TEST_DATABASE_URL=postgresql://... # Neon branch "test": wiped by the tests
   ```
   Copy the strings from the Neon console (*Connect*). Restart R afterwards.
3. Run the app with `shiny::runApp()`. Edits go straight to the live data.

### Which database is used

| `DATABASE_URL` | Database |
|---|---|
| set | PostgreSQL at that URL (`sql/schema_postgres.sql`) |
| not set | local SQLite file `data/master_species.sqlite` (`sql/schema.sql`), imported from `data/master_species.xlsx` on first start |

The live data was copied from the local SQLite file once with
`Rscript scripts/migrate_to_neon.R` (it refuses to run if the target already has species).

## Using the app

- **Filter** with the boxes above each column; empty values show as a grey `–`.
- **Add species** opens an empty form. EPPO code is required and must be unique.
- **Edit selected**: click a row, then edit. The *History* tab lists every change.
- **Download xlsx** saves a copy: an `overview` sheet like the table, plus one sheet per database table.

## Data model

Tidy tables, one per kind of thing (see `sql/schema.sql`; keep `sql/schema_postgres.sql` in step):

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
They never use `DATABASE_URL`. By default they run on temporary SQLite files;
with `TEST_DATABASE_URL` set, the database tests run on that PostgreSQL database
instead and **drop and rebuild its tables**, so only ever point it at a test branch.
Browser tests always run the app on a temporary SQLite copy.

| Path | Contents |
|---|---|
| `app.R` | UI layout and wiring |
| `R/db.R` | database: schema, import, reading and saving |
| `R/import.R` | splits the legacy workbook into tidy tables |
| `R/export.R` | xlsx download |
| `R/mod_species_table.R`, `R/mod_species_form.R` | Shiny modules |
| `sql/` | database schema for SQLite and PostgreSQL |
| `scripts/migrate_to_neon.R` | one-time copy of the local database to Neon |

## Backups

Neon keeps a restore history for the live database (point-in-time restore; the
window depends on your Neon plan). Keep a regular **Download xlsx** copy as well.
