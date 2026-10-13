# Runtime dependencies. Shiny is already supplied by the selected Rocker image.
# Add your own required packages here; install them during the image build.
packages <- c("shiny")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
stopifnot(all(vapply(packages, requireNamespace, logical(1), quietly = TRUE)))
# This list is not a package-version lock. Use a reviewed renv workflow if needed.
