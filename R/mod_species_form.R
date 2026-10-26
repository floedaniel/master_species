text_fields <- c("fullname", "authdesc", "kingdom", "phylum", "class", "order", "family", "genus", "endnote")
number_fields <- c("hours", "batch", unname(event_fields))

# Add/edit modal for one species. `species` is a reactive species_view();
# `on_saved` is called after a successful save. Returns list(open = function(species_id)),
# where species_id = NULL opens an empty form for a new species.
mod_species_form_server <- function(id, con, species, on_saved, changed_by = NA_character_) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    editing_id <- reactiveVal(NULL)

    form <- function(s) {
      val <- \(f) if (nrow(s) && !is.na(s[[f]])) s[[f]] else NA
      txt <- \(f) if (is.na(val(f))) "" else as.character(val(f))
      # Keep a stored value selectable even if it is missing from the lookup list
      choices <- \(options, f) unique(c("", options, na.omit(val(f))))
      choose <- \(f, label, options) selectInput(ns(f), label, choices(options, f), txt(f))
      number <- \(f, label, step = 1) numericInput(ns(f), label, val(f), min = 0, step = step)

      title <- if (nrow(s)) paste("Edit", s$eppocode) else "Add species"
      modalDialog(
        title = title, size = "l", easyClose = FALSE,
        navset_underline(
          nav_panel(
            "Assessment",
            layout_columns(
              col_widths = c(4, 4, 4),
              textInput(ns("eppocode"), "EPPO code *", txt("eppocode")),
              choose("assessor", "Assessor", get_lookup(con, "assessors")),
              choose("status", "Status", get_lookup(con, "statuses")),
              number("hours", "Hours", step = 0.5),
              number("batch", "Batch"),
              selectInput(ns("ai"), "AI", c("", Yes = "TRUE", No = "FALSE"), txt("ai"))
            ),
            textAreaInput(ns("comment"), "Comment", txt("comment"), width = "100%")
          ),
          nav_panel(
            "Species",
            map(text_fields, \(f) textInput(ns(f), f, txt(f))) |>
              c(list(col_widths = c(6, 6))) |>
              do.call(what = layout_columns)
          ),
          nav_panel(
            "EPPO",
            layout_columns(
              col_widths = c(4, 4, 4),
              choose("eppo_list", "EPPO list", c("A1 list", "A2 list", "Alert list")),
              choose("eppo_status", "EPPO status", c("active", "removed_from_list")),
              # value = "" renders an empty date box; shiny warns but it works
              suppressWarnings(dateInput(ns("date_flagged"), "Date flagged", value = txt("date_flagged"))),
              number("eppo_year_added", "Year added"),
              number("eppo_year_deleted", "Year deleted"),
              number("eppo_year_transient", "Year transient")
            )
          ),
          if (nrow(s)) nav_panel("History", tableOutput(ns("history")))
        ),
        footer = tagList(modalButton("Cancel"), actionButton(ns("save"), "Save", class = "btn-primary"))
      )
    }

    output$history <- renderTable({
      req(editing_id())
      input$save
      get_change_log(con, editing_id())
    })

    form_values <- function() {
      fields <- c(species_fields, assessment_fields, event_fields)
      values <- map(set_names(fields), \(f) input[[f]])
      values <- modify_at(values, number_fields, \(v) if (is.null(v)) NA else v)
      values$eppocode <- str_to_upper(str_trim(values$eppocode))
      values[text_fields] <- map(values[text_fields], str_trim)
      values$ai <- as.logical(values$ai)
      values$batch <- as.integer(values$batch)
      values$date_flagged <- if (length(values$date_flagged)) format(values$date_flagged) else NA
      map(values, \(v) if (length(v) == 0 || identical(v, "")) NA else v)
    }

    observeEvent(input$save, {
      values <- form_values()
      problem <- validate_species(con, values, editing_id())
      if (!is.null(problem)) {
        showNotification(problem, type = "error")
        return()
      }
      tryCatch(
        {
          save_species(con, values, editing_id(), changed_by)
          removeModal()
          on_saved()
          verb <- if (is.null(editing_id())) "Added" else "Saved changes to"
          showNotification(paste(verb, values$eppocode), type = "message")
        },
        error = \(e) showNotification(conditionMessage(e), type = "error")
      )
    })

    list(open = function(species_id = NULL) {
      editing_id(species_id)
      s <- species() |> filter(species_id %in% !!species_id)
      showModal(form(s))
    })
  })
}
