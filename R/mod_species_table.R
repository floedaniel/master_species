# Show missing values as a grey dash; the data itself stays NA
# R/ is sourced before app.R attaches packages, hence DT::
na_render <- DT::JS(
  "function(data, type) {",
  "  if (type === 'display' && (data === null || data === '')) return '<span class=\"text-muted\">–</span>';",
  "  return data;",
  "}"
)

mod_species_table_ui <- function(id) {
  DTOutput(NS(id, "table"))
}

# `species` is a reactive species_view(). Returns a reactive with the
# species_id of the selected row (NULL when nothing is selected).
mod_species_table_server <- function(id, species) {
  moduleServer(id, function(input, output, session) {
    table_data <- reactive({
      display_columns(species())
    })

    # Rendered once; later changes go through the proxy so paging and filters stay put
    output$table <- renderDT({
      datatable(
        isolate(table_data()),
        rownames = FALSE, filter = "top", selection = "single",
        extensions = "FixedHeader",
        options = list(
          pageLength = 25, scrollX = TRUE, fixedHeader = TRUE,
          columnDefs = list(list(targets = "_all", render = na_render))
        )
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
