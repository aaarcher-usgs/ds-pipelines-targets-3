
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
            'UT','VA','WA','WV','WI','WY','AK','HI','PR')
parameter <- c('00010')



# Targets
fetch_targets <- list(
  # Identify oldest sites
  tar_target(oldest_active_sites,
             find_oldest_sites(states, parameter)
             ),

  tar_target(nwis_inventory,
             oldest_active_sites %>% group_by(state_cd) %>% tar_group(),
             iteration = "group"),

  tar_target(
    nwis_data,
    retry(get_site_data(site_info = nwis_inventory,
                        state = nwis_inventory$state_cd,
                        parameter = parameter),
          when = "Ugh, the internet data transfer failed!",
          max_tries = 30),
    pattern =  map(nwis_inventory)
  ),

  tar_target(
    tally,
    tally_site_obs(site_data = nwis_data),
    pattern = map(nwis_data)
  )
)

combine_targets <- list(

  tar_target(
    timeseries_png,
    plot_site_data(out_file = sprintf("3_visualize/out/timeseries_%s.png", unique(nwis_data$State)),
                   site_data = nwis_data,
                   parameter = parameter),
    format = "file",
    pattern = map(nwis_data)
  ),

  # Create log of individual pngs
  tar_target(
    summary_state_timeseries_csv,
    command = summarize_targets(ind_file = '3_visualize/log/summary_state_timeseries.csv',
                                input = names(timeseries_png)),
    format="file"
  ),

  # create coverage map of tallies
  tar_target(
    data_coverage_png,
    plot_data_coverage(oldest_site_tallies = tally,
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

list(fetch_targets, combine_targets, site_map, leaflet)
