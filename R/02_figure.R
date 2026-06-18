# Create output/transit-equity.pdf: a two-panel figure showing
# - how transit supply relates to need across census tracts
# - where the high-need, under-served neighborhoods are
#
# Run after 01_get_data.R (reads data/analysis.rds).

import::from(sf, st_drop_geometry)
import::from(dplyr, mutate, arrange, if_else, group_by, summarise)
import::from(ggplot2, ggplot, aes, geom_point, geom_smooth, geom_sf,
             scale_color_manual, scale_fill_manual, scale_y_continuous,
             labs, theme_minimal, theme, element_text, element_blank,
             coord_sf, ggsave)
import::from(patchwork, wrap_plots, plot_annotation)
import::from(scales, label_comma)

analysis <- readRDS("data/analysis.rds")
lakes    <- readRDS("data/lakes.rds")

# ---- Classify the equity gap: high need AND low supply ----------------------
need_cut   <- quantile(analysis$pct_no_vehicle, 0.75, na.rm = TRUE)
supply_cut <- median(analysis$departures, na.rm = TRUE)

analysis <- analysis |>
  mutate(
    gap   = pct_no_vehicle >= need_cut & departures < supply_cut,
    group = factor(if_else(gap, "High need, low service", "Other tracts"),
                   levels = c("High need, low service", "Other tracts"))
  ) |>
  arrange(gap)   # draw the highlighted tracts last (on top)

# palette: orange for the gap tracts, neutral grey otherwise
pal <- c("High need, low service" = "#E8702A", "Other tracts" = "#C9C9C9")

# ---- Panel A: the relationship (scatter) ------------------------------------
pA <- ggplot(st_drop_geometry(analysis),
             aes(pct_no_vehicle, departures, color = group)) +
  geom_smooth(aes(group = 1), method = "lm", se = FALSE,
              color = "grey35", linewidth = 0.6, linetype = "dashed") +
  geom_point(size = 1.6, alpha = 0.75) +
  scale_color_manual(values = pal, name = NULL) +
  scale_y_continuous(labels = label_comma()) +
  labs(
    title = "Service rises with need, but loosely",
    x = "Households without a vehicle (%)",
    y = "Weekday departures within a 1/4-mile walk"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top",
        plot.title = element_text(face = "bold"))

# county outlines: union the tracts (GEOID = state+county+tract) by county
counties <- analysis |>
  mutate(county_fips = substr(GEOID, 1, 5)) |>
  group_by(county_fips) |>
  summarise(.groups = "drop")

# ---- Panel B: the geography (map) -------------------------------------------
pB <- ggplot() +
  geom_sf(data = analysis, aes(fill = group), color = "white", linewidth = 0.04) +
  geom_sf(data = lakes, fill = "#5bf", color = NA) +
  geom_sf(data = counties, fill = NA, color = "grey30", linewidth = 0.1) +
  scale_fill_manual(values = pal, name = NULL) +
  labs(title = "High-need, under-served tracts") +
  coord_sf(datum = NA) +
  theme_minimal(base_size = 11) +
  theme(axis.text = element_blank(),
        panel.grid = element_blank(),
        legend.position = "none",
        plot.title = element_text(face = "bold"))

# ---- Compose + caption ------------------------------------------------------
fig <- wrap_plots(pA, pB, nrow = 1) +
  plot_annotation(
    title = "Does Twin Cities transit reach the households that depend on it?",
    caption = paste0(
      "Sources: Metro Transit / Metropolitan Council GTFS (weekday service); ",
      "U.S. Census Bureau ACS 5-year (2019–2023). Seven-county metro, census-tract level.\n",
      '"Need" = share of households with no vehicle; ',
      '"service" = weekday departures reachable within a 1/4-mile walk.'
    ),
    theme = theme(
      plot.title   = element_text(face = "bold", size = 14),
      plot.caption = element_text(color = "grey40", hjust = 0)
    )
  )

ggsave("output/transit-equity.pdf", fig, width = 10, height = 5.4)
cat("Wrote output/transit-equity.pdf\n")

# Assumptions:
#  - "Frequency of service" is our measure of transportation access.  This assumes that once
#    you get on a bus/train, you can get anywhere you need to go, efficiently.  There are likely places
#    where this isn't the case.
#
# Questions:
#  - What does "within a 1/4−mile walk" mean for an entire census tract?  They are way bigger than 1/4 mile typically.
#
# Conclusions:
#  - The under-served tracts are very spread out, and none are in the city centers.  Solving this need
#    might be difficult
