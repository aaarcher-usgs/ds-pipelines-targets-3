
library(targets)
library(tarchetypes)
library(tibble)
library(retry)
suppressPackageStartupMessages(library(tidyverse))

options(tidyverse.quiet = TRUE)
tar_option_set(packages = c("tidyverse", "dataRetrieval", "urbnmapr",
                            "rnaturalearth", "cowplot", "lubridate",
                            "readr", "leafpop", "htmlwidgets", "leaflet"))

# Load functions needed by targets below
source("1_fetch/src/find_oldest_sites.R")
source("1_fetch/src/get_site_data.R")
source("2_process/src/tally_site_obs.R")
source("2_process/src/summarize_targets.R")
source("3_visualize/src/map_sites.R")
source("3_visualize/src/plot_site_data.R")
source("3_visualize/src/plot_data_coverage.R")
source("3_visualize/src/map_timeseries.R")

# Configuration
states <- c('AL','AZ','AR','CA','CO','CT','DE','DC','FL','GA','ID','IL','IN','IA',
            'KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH',
            'NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX',
            'UT','VT','VA','WA','WV','WI','WY','AK','HI','GU','PR')
parameter <- c('00060')

mapped_by_state_targets <- tar_map(
  values = tibble(state_abb = states,
                  state_plot_files = sprintf("3_visualize/out/timeseries_%s.png",state_abb)),
  names = state_abb,
  unlist = FALSE,
  tar_target(nwis_inventory,
             oldest_active_sites %>% filter(state_cd == state_abb)),
  tar_target(
    nwis_data,
    retry(get_site_data(site_info = nwis_inventory,
                  state = state_abb,
                  parameter = parameter),
          when = "Ugh, the internet data transfer failed!",
          max_tries = 30)
  ),
  tar_target(
    tally,
    tally_site_obs(site_data = nwis_data)
  ),
  tar_target(
    timeseries_png,
    plot_site_data(out_file = state_plot_files,
                   site_data = nwis_data,
                   parameter = parameter),
    format = "file"
  )
)

# Targets
fetch_targets <- list(
  # Identify oldest sites
  tar_target(oldest_active_sites,
             find_oldest_sites(states, parameter)
             )
)

combine_targets <- list(
  # Combine the tallies by site and year
  tar_combine(
    obs_tallies,
    mapped_by_state_targets$tally,
    command = combine_obs_tallies(!!!.x)
  ),

  # Create log of individual pngs
  tar_combine(
    summary_state_timeseries_csv,
    mapped_by_state_targets$timeseries_png,
    command = summarize_targets(ind_file = '3_visualize/log/summary_state_timeseries.csv',
                                !!!.x),
    format="file"
  ),

  # create coverage map of tallies
  tar_target(
    data_coverage_png,
    plot_data_coverage(oldest_site_tallies = obs_tallies,
                       out_file = "3_visualize/out/data_coverage.png",
                       parameter = parameter),
    format = "file"
  )
)

site_map <- list(
  # Map oldest sites
  tar_target(
    site_map_png,
    map_sites("3_visualize/out/site_map.png", oldest_active_sites),
    format = "file"
  )
)

leaflet <- tar_target(
  map_timeseries_html,
  map_timeseries(site_info = oldest_active_sites,
                 plot_info_csv = summary_state_timeseries_csv,
                 out_file = "3_visualize/out/timeseries_map.html")
)

list(fetch_targets, mapped_by_state_targets, combine_targets, site_map, leaflet)
