# Setup script: ensure the project-local (renv) library has everything this analysis
# needs, record exact versions in renv.lock, and load the packages.
#
# renv is activated automatically by the project .Rprofile, so packages install
# into renv/library/ , not global/user library.

required <- c(
  "import",      # import::from() for explicit, scoped symbol imports
  "sf",          # spatial data frames + geometric operations
  "tidycensus",  # ACS data via the Census API
  "tigris",      # TIGER/Line tract boundaries
  "tidytransit", # read GTFS feeds
  "ggplot2",     # plotting
  "patchwork",   # compose multi-panel figures
  "scales",      # axis label formatting
  "dplyr"        # data wrangling
)

# Install whatever is missing into the project library, then pin versions.
missing <- setdiff(required, rownames(installed.packages()))
if (length(missing)) {
  message("Installing into project library: ", paste(missing, collapse = ", "))
  renv::install(missing)
  renv::snapshot(prompt = FALSE)
}

# Verify each package loads, without attaching it (the analysis scripts use
# import::from() to pull in only the symbols they need).
ok <- vapply(required, requireNamespace, logical(1), quietly = TRUE)
if (!all(ok)) stop("These packages failed to load: ",
                   paste(required[!ok], collapse = ", "))

# A free Census API key is required for tidycensus:
#   https://api.census.gov/data/key_signup.html
# Set it once with: tidycensus::census_api_key("YOUR_KEY", install = TRUE)
if (Sys.getenv("CENSUS_API_KEY") == "") {
  warning("CENSUS_API_KEY is not set; 01_get_data.R will fail until it is.")
}

message("Setup complete. Library paths:\n  ",
        paste(.libPaths(), collapse = "\n  "))
