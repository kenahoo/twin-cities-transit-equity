# Build a census-tract table for the seven-county Twin Cities metro that pairs
# transit SUPPLY (weekday departures within a short walk) with transit NEED
# (share of households with no vehicle), plus income and population data
#
# Run after 00_setup.R, with a CENSUS_API_KEY set. Writes data/analysis.rds.

import::from(sf, st_transform, st_buffer, st_join, st_drop_geometry, st_within)
import::from(tidycensus, get_acs)
import::from(tigris, area_water)
import::from(tidytransit, read_gtfs, filter_feed_by_date,
             get_stop_frequency, stops_as_sf)
import::from(dplyr, inner_join, left_join, mutate, group_by, summarise, coalesce, filter)

# tigris is used implicitly by get_acs(geometry = TRUE); no import required
options(tigris_use_cache = TRUE)

# ---- Parameters -------------------------------------------------------------
metro_counties <- c("Anoka", "Carver", "Dakota", "Hennepin",
                    "Ramsey", "Scott", "Washington")  # Met Council jurisdiction
acs_year     <- 2023                       # latest ACS 5-year release
service_date <- as.Date("2026-06-17")      # a Wednesday
walk_m       <- 400                        # ~1/4 mile walk to a stop (meters)
metric_crs   <- 26915                      # UTM 15N: meters, for distance ops
gtfs_url     <- "https://svc.metrotransit.org/mtgtfs/gtfs.zip"  # Metro Transit / Met Council

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

# ---- 2. Transit need + boundaries: ACS by tract -----------------------------
vars <- c(
  hh_total     = "B08201_001",  # total households
  hh_novehicle = "B08201_002",  # households with no vehicle available
  med_income   = "B19013_001",  # median household income
  population   = "B01003_001"   # total population
)

acs <- get_acs(
  geography = "tract",
  variables = vars,
  state     = "MN",
  county    = metro_counties,
  year      = acs_year,
  survey    = "acs5",
  geometry  = TRUE,
  output    = "wide"            # gives <name>E (estimate) / <name>M (margin) cols
) |>
  st_transform(metric_crs) |>
  mutate(pct_no_vehicle = 100 * hh_novehicleE / hh_totalE)

# ---- 3. Combine: departures reachable within walk_m of each tract -----------
# A stop within walk_m of a tract counts toward that tract's accessible service.
tract_buffer <- st_buffer(acs, walk_m)

service_by_tract <- st_join(stops_sf, tract_buffer, join = st_within) |>
  st_drop_geometry() |>
  group_by(GEOID) |>
  summarise(departures = sum(n_departures, na.rm = TRUE), .groups = "drop")

analysis <- acs |>
  left_join(service_by_tract, by = "GEOID") |>
  mutate(departures = coalesce(departures, 0)) |>
  # keep only residential tracts (drops airport/parks/industrial with no people)
  filter(hh_totalE > 0, populationE > 0)

saveRDS(analysis, "data/analysis.rds")

# ---- 4. Larger lakes & rivers (map orientation) -----------------------------
# TIGER/Line area-water polygons, one county at a time, then keep the big ones.
water <- do.call(rbind, lapply(metro_counties, function(co)
  area_water("MN", co, year = acs_year))) |>
  st_transform(metric_crs)

lakes <- filter(water, AWATER > 1e6)   # keep water bodies larger than 1 sq km
saveRDS(lakes, "data/lakes.rds")

# ---- Quick look (so we can decide how to visualize) -------------------------
cat("\nTracts (residential):", nrow(analysis), "\n")
cat("\n% households with no vehicle:\n")
print(summary(analysis$pct_no_vehicle))
cat("\nWeekday departures reachable within 1/4 mile:\n")
print(summary(analysis$departures))
cat("\nCorrelation (need vs. supply):",
    round(cor(analysis$pct_no_vehicle, analysis$departures), 3), "\n")

