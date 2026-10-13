# Test public configuration, HTML escaping and reactive server behavior.
# Run from the repository root with testthat installed in the test environment.
source("app.R")

Sys.unsetenv("GREETING_TEXT")
default_page <- as.character(create_ui())
stopifnot(grepl("Hello from the Shiny container!", default_page, fixed = TRUE))
cat("PASS: default greeting\n")

Sys.setenv(GREETING_TEXT = "Hello from an environment variable!")
environment_page <- as.character(create_ui())
stopifnot(grepl("Hello from an environment variable!", environment_page, fixed = TRUE))
Sys.unsetenv("GREETING_TEXT")
cat("PASS: environment greeting\n")

escaped_page <- as.character(create_ui("<script>alert('example')</script>"))
stopifnot(!grepl("<script>alert", escaped_page, fixed = TRUE))
stopifnot(grepl("&lt;script&gt;", escaped_page, fixed = TRUE))
cat("PASS: greeting HTML escaping\n")

shiny::testServer(app_server, {
  session$setInputs(number = 4)
  stopifnot(output$result == "4 squared is 16")
  session$setInputs(number = 7)
  stopifnot(output$result == "7 squared is 49")
  session$setInputs(number = 10)
  stopifnot(output$result == "10 squared is 100")
})
cat("PASS: slider changes trigger new results\n")
