hidden_cols <- c("species_id", "assessment_id", "added_at", "updated_at")
first_cols <- c("eppocode", "fullname", "assessor", "status", "hours", "batch", "ai", "endnote", "comment")

mod_species_table_ui <- function(id) {
  DTOutput(NS(id, "table"))
}

# `species` is a reactive species_view(). Returns a reactive with the
# species_id of the selected row (NULL when nothing is selected).
mod_species_table_server <- function(id, species) {
  moduleServer(id, function(input, output, session) {
    table_data <- reactive({
      species() |>
        select(any_of(first_cols), everything(), -any_of(hidden_cols))
    })

    # Rendered once; later changes go through the proxy so paging and filters stay put
    output$table <- renderDT({
      datatable(
        isolate(table_data()),
        rownames = FALSE, filter = "top", selection = "single",
        extensions = "FixedHeader",
        options = list(pageLength = 25, scrollX = TRUE, fixedHeader = TRUE)
      )
    })

    proxy <- dataTableProxy("table")
    observeEvent(table_data(),
      {
        replaceData(proxy, table_data(), rownames = FALSE, resetPaging = FALSE, clearSelection = "none")
      },
      ignoreInit = TRUE
    )

    reactive({
      sel <- input$table_rows_selected
      if (length(sel)) species()$species_id[sel] else NULL
    })
  })
}
