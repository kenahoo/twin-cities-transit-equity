# Build a census BLOCK-GROUP table for the seven-county Twin Cities metro that
# pairs transit SUPPLY (weekday departures within a short walk of where people
# actually live) with transit NEED (share of households with no vehicle), plus
# income and population.
#
# Why block groups, and why population-weighted centroids?
#   Earlier this analysis buffered whole census tracts by 400 m and counted the
#   stops inside. But tracts span several km, so a single stop on a tract's edge
#   got credited to residents living kilometers away: "within 1/4 mile of the
#   tract" is not "within 1/4 mile of a person." Here we instead (a) drop to
#   block groups (~10x smaller) and (b) measure access at each block group's
#   POPULATION-WEIGHTED center (Census CenPop2020), i.e. where residents really
#   are, not the polygon's shape.
#
# Run after 00_setup.R, with a CENSUS_API_KEY set. Writes data/analysis.rds.

import::from(sf, st_as_sf, st_transform, st_buffer, st_join, st_drop_geometry,
             st_within)
import::from(tidycensus, get_acs)
import::from(tigris, area_water)
import::from(tidytransit, read_gtfs, filter_feed_by_date,
             get_stop_frequency, stops_as_sf)
import::from(dplyr, inner_join, left_join, mutate, group_by, summarise,
             coalesce, filter)

# tigris is used implicitly by get_acs(geometry = TRUE); no import required
options(tigris_use_cache = TRUE)

# ---- Parameters -------------------------------------------------------------
metro_counties <- c("Anoka", "Carver", "Dakota", "Hennepin",
                    "Ramsey", "Scott", "Washington")  # Met Council jurisdiction
acs_year     <- 2023                       # latest ACS 5-year release
service_date <- as.Date("2026-06-17")      # a Wednesday
walk_m       <- 800                        # ~1/2 mile walk to a stop (meters);
                                           # the standard BRT/rail catchment, and
                                           # apt for Metro Transit's growing BRT network
metric_crs   <- 26915                      # UTM 15N: meters, for distance ops
gtfs_url     <- "https://svc.metrotransit.org/mtgtfs/gtfs.zip"  # Metro Transit / Met Council
# Population-weighted block-group centers, 2020 Census, Minnesota (FIPS 27):
centroid_url <- "https://www2.census.gov/geo/docs/reference/cenpop2020/blkgrp/CenPop2020_Mean_BG27.txt"

dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)

# ---- 1. Transit supply: weekday departures per stop (GTFS) ------------------
gtfs_zip <- "data/raw/metro_gtfs.zip"
if (!file.exists(gtfs_zip)) download.file(gtfs_url, gtfs_zip, mode = "wb")

gtfs <-
  read_gtfs(gtfs_zip) |>
  filter_feed_by_date(service_date)   # keep only that weekday's service

# departures at each stop during the service day (6am-10pm)
stop_freq <- get_stop_frequency(gtfs, start_time = "06:00:00",
                                end_time = "22:00:00", by_route = FALSE)

stops_sf <- stops_as_sf(gtfs$stops) |>
  inner_join(stop_freq, by = "stop_id") |>   # adds n_departures
  st_transform(metric_crs)

# ---- 2. Transit need + boundaries: ACS by block group -----------------------
# B25044 = Tenure by Vehicles Available (the no-vehicle counts, owner + renter,
# available at block-group resolution; B08201 is tract-only).
vars <- c(
  hh_total     = "B25044_001",  # occupied housing units (households)
  own_no_veh   = "B25044_003",  # owner-occupied, no vehicle available
  rent_no_veh  = "B25044_010",  # renter-occupied, no vehicle available
  med_income   = "B19013_001",  # median household income
  population   = "B01003_001"   # total population
)

bg <- get_acs(
  geography = "block group",
  variables = vars,
  state     = "MN",
  county    = metro_counties,
  year      = acs_year,
  survey    = "acs5",
  geometry  = TRUE,
  output    = "wide"            # gives <name>E (estimate) / <name>M (margin) cols
) |>
  st_transform(metric_crs) |>
  mutate(
    hh_novehicle   = own_no_vehE + rent_no_vehE,
    pct_no_vehicle = 100 * hh_novehicle / hh_totalE
  )

# ---- 3. Population-weighted centers: where residents actually live ----------
centroid_csv <- "data/raw/cenpop2020_bg_mn.csv"
if (!file.exists(centroid_csv)) download.file(centroid_url, centroid_csv)

centroids <- read.csv(centroid_csv, colClasses = c(
  STATEFP = "character", COUNTYFP = "character",
  TRACTCE = "character", BLKGRPCE = "character"))
centroids$GEOID <- paste0(centroids$STATEFP, centroids$COUNTYFP,
                          centroids$TRACTCE, centroids$BLKGRPCE)

centroids <- centroids |>
  filter(GEOID %in% bg$GEOID) |>                         # seven-county metro only
  st_as_sf(coords = c("LONGITUDE", "LATITUDE"), crs = 4326) |>
  st_transform(metric_crs)

# ---- 4. Combine: departures reachable within walk_m of the population center -
# A stop within walk_m of a block group's population-weighted center counts
# toward that block group's accessible service.
centroid_buffer <- st_buffer(centroids, walk_m)

service_by_bg <- st_join(stops_sf, centroid_buffer, join = st_within) |>
  st_drop_geometry() |>
  group_by(GEOID) |>
  summarise(departures = sum(n_departures, na.rm = TRUE), .groups = "drop")

analysis <- bg |>
  left_join(service_by_bg, by = "GEOID") |>
  mutate(departures = coalesce(departures, 0)) |>
  # keep only residential block groups (drops airport/parks/industrial)
  filter(hh_totalE > 0, populationE > 0)

saveRDS(analysis, "data/analysis.rds")

# ---- 5. Larger lakes & rivers (map orientation) -----------------------------
# TIGER/Line area-water polygons, one county at a time, then keep the big ones.
water <- do.call(rbind, lapply(metro_counties, function(co)
  area_water("MN", co, year = acs_year))) |>
  st_transform(metric_crs)

lakes <- filter(water, AWATER > 1e6)   # keep water bodies larger than 1 sq km
saveRDS(lakes, "data/lakes.rds")

# ---- Quick look (so we can decide how to visualize) -------------------------
cat("\nBlock groups (residential):", nrow(analysis), "\n")
cat("\n% households with no vehicle:\n")
print(summary(analysis$pct_no_vehicle))
cat("\nWeekday departures reachable within 1/2 mile of the population center:\n")
print(summary(analysis$departures))
cat("\nCorrelation (need vs. supply):",
    round(cor(analysis$pct_no_vehicle, analysis$departures), 3), "\n")
