# Check the actual Shiny page using R already installed in the application image.
# Usage: Rscript probe.R URL [expected public greeting]
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 1, length(args) <= 2)
options(timeout = 10)

probe <- function() {
  connection <- url(args[[1]], open = "r", method = "libcurl")
  on.exit(close(connection))
  page <- paste(readLines(connection, warn = FALSE), collapse = "\n")
  stopifnot(grepl("Docker Shiny demo", page, fixed = TRUE))
  stopifnot(grepl('id="number"', page, fixed = TRUE))
  if (length(args) == 2) {
    # Compare the escaped text, matching how the app inserts its greeting.
    expected <- as.character(htmltools::htmlEscape(args[[2]]))
    stopifnot(grepl(expected, page, fixed = TRUE))
  }
}
probe()
cat("Shiny HTTP probe passed.\n")
# HTTP availability is not an end-to-end browser/session test.
