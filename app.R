# A minimal Shiny app: public configuration plus one reactive calculation.
library(shiny)

create_ui <- function(greeting = Sys.getenv(
  "GREETING_TEXT", unset = "Hello from the Shiny container!"
)) {
  fluidPage(
    titlePanel("Docker Shiny demo"),
    # Passing text to p() escapes HTML. Do not wrap configuration in HTML().
    p(greeting, id = "greeting"),
    sliderInput("number", "Choose a number", min = 1, max = 10, value = 4, step = 1),
    textOutput("result")
  )
}

app_server <- function(input, output, session) {
  output$result <- renderText({
    value <- input$number
    req(value)
    # Validate on the server too: a browser can send values outside the widget.
    validate(need(
      is.numeric(value) && length(value) == 1 && is.finite(value) &&
        value >= 1 && value <= 10,
      "Choose a number from 1 to 10."
    ))
    sprintf("%g squared is %g", value, value^2)
  })
}

# Shiny Server loads the returned app object; no development server is started here.
shinyApp(ui = create_ui(), server = app_server)
