# Shiny Server starts R with a reduced environment (HOME, LANG and PATH).
# This user profile restores only the demo's public greeting, saved at startup.
# RDS preserves quotes, dollar signs and newlines without generating R code.
local({
  path <- "/tmp/shiny-server/greeting.rds"
  if (file.exists(path)) {
    greeting <- readRDS(path)
    stopifnot(is.character(greeting), length(greeting) == 1L)
    if (!is.na(greeting)) {
      Sys.setenv(GREETING_TEXT = greeting)
    }
  }
})
