# Setup: install the project's declared dependencies (see DESCRIPTION) into the
# project renv library, then pin exact versions in renv.lock.
#
# renv is activated automatically by the project .Rprofile, so everything
# installs into renv/library/.

# Treat DESCRIPTION as the single source of truth for dependencies.
renv::settings$snapshot.type("explicit")

renv::install()                 # install/upgrade deps from DESCRIPTION
renv::snapshot(prompt = FALSE)  # record exact versions in renv.lock

# A free Census API key is required for tidycensus:
#   https://api.census.gov/data/key_signup.html
# Set it once with: tidycensus::census_api_key("YOUR_KEY", install = TRUE)
if (Sys.getenv("CENSUS_API_KEY") == "")
  warning("CENSUS_API_KEY is not set; 01_get_data.R will fail until it is.")

message("Setup complete.")
