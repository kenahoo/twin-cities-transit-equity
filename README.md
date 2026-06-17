# Data Analysis Sample

A small, reproducible analysis of how Metro Transit service in the
seven-county Twin Cities region lines up with the communities most likely to
depend on it.

"Supply" is measured from Metro Transit's published
schedule (how much service is within walking distance of each neighborhood);
"need" is measured from Census demographics (households without a vehicle,
income, and related indicators).

## Data sources (all public)

- **Metro Transit GTFS** — published transit schedule (stops, routes, trip
  frequency). https://www.metrotransit.org/
- **American Community Survey (ACS)** 5-year estimates, census-tract level, via
  the U.S. Census Bureau API (`tidycensus` package).
- **Tract boundaries** for the seven-county metro, via `tigris`.

## Reproducing

Requires R (≥ 4.5) and a free [Census API
key](https://api.census.gov/data/key_signup.html).

```r
# from the project root
source("R/00_setup.R")     # installs/loads packages
source("R/01_get_data.R")  # downloads GTFS + ACS, builds the analysis table
source("R/02_figure.R")    # renders output/transit-equity.pdf
```

## Output

`output/transit-equity.pdf` — presents a simple analysis in graphical form
