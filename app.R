library(shiny)
library(bslib)
library(DT)
library(DBI)
library(RSQLite)
library(dplyr)
library(dbplyr, warn.conflicts = FALSE)
library(tidyr)
library(purrr)
library(stringr)
library(readr)
library(readxl)
library(janitor, warn.conflicts = FALSE)

# Files in R/ are sourced automatically by shiny

con <- init_db()
onStop(\() dbDisconnect(con))

ui <- page_fillable(
  title = "Master species",
  theme = bs_theme(version = 5),
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      span("Master species", textOutput("n_rows", inline = TRUE)),
      div(
        downloadButton("download", "Download xlsx", class = "btn-outline-secondary btn-sm"),
        actionButton("edit", "Edit selected", class = "btn-outline-primary btn-sm"),
        actionButton("add", "Add species", class = "btn-primary btn-sm")
      )
    ),
    mod_species_table_ui("table")
  )
)

server <- function(input, output, session) {
  refresh <- reactiveVal(0)
  species <- reactive({
    refresh()
    species_view(con)
  })

  output$n_rows <- renderText(sprintf("(%d species)", nrow(species())))

  selected <- mod_species_table_server("table", species)
  form <- mod_species_form_server(
    "form", con, species,
    on_saved = \() refresh(refresh() + 1),
    changed_by = session$user %||% Sys.info()[["user"]]
  )

  output$download <- downloadHandler(
    filename = \() sprintf("master_species_%s.xlsx", Sys.Date()),
    content = \(file) write_master_xlsx(con, file)
  )

  observeEvent(input$add, form$open())
  observeEvent(input$edit, {
    if (is.null(selected())) {
      showNotification("Click a row in the table first.", type = "warning")
      return()
    }
    form$open(selected())
  })
}

shinyApp(ui, server)
