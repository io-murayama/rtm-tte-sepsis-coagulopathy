### rTM treatment patterns ###
#========================================#
# 0. Packages
#========================================#
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(ggplot2)
if (!requireNamespace("tibble", quietly = TRUE)) install.packages("tibble")
library(tibble)

#========================================#
# 1. Configurations
#========================================#
date <- "260827"
data_dir <- "./data/"
output_dir <- "./output/"

time_window_width <- 24
followup_days <- 28
x_max_days <- 28
x_break_days <- 7

patient_height_scale <- 1.5

treatment_col <- "thrombomodulin_use"
id_col        <- "icu_stay_id"
time_col      <- "time_window_index"
death_col     <- "icu_death"
discharge_col <- "icu_discharge_alive"
required_cols <- c(id_col, time_col, treatment_col, death_col, discharge_col)

#========================================#
# 2. Load data
#========================================#
load(paste0(data_dir, "df_", date, "_all.RData"))

#========================================#
# 3. Prepare plot data
#========================================#
plot_df <- df %>%
  select(all_of(required_cols)) %>%
  arrange(.data[[id_col]], .data[[time_col]])

patient_summary <- plot_df %>%
  group_by(.data[[id_col]]) %>%
  summarise(
    ever_rtm = any(.data[[treatment_col]] == 1L, na.rm = TRUE),
    first_rtm_index = {
      rtm_indices <- .data[[time_col]][.data[[treatment_col]] == 1L]
      if (length(rtm_indices) > 0) min(rtm_indices, na.rm = TRUE) else NA_integer_
    },
    total_rtm_windows = sum(.data[[treatment_col]] == 1L, na.rm = TRUE),
    last_observed_index = max(.data[[time_col]], na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(ever_rtm) %>%
  mutate(
    first_rtm_day  = first_rtm_index * time_window_width / 24,
    total_rtm_days = total_rtm_windows * time_window_width / 24
  ) %>%
  arrange(first_rtm_day, desc(total_rtm_days), .data[[id_col]]) %>%
  mutate(
    patient_rank = row_number(),
    y_position   = patient_rank
  )

n_rtm_patients <- nrow(patient_summary)

#========================================#
# 4. Create rTM treatment segments
#========================================#
tm_segments <- plot_df %>%
  semi_join(patient_summary, by = id_col) %>%
  filter(.data[[treatment_col]] == 1L) %>%
  arrange(.data[[id_col]], .data[[time_col]]) %>%
  group_by(.data[[id_col]]) %>%
  mutate(
    previous_index = lag(.data[[time_col]], default = first(.data[[time_col]]) - 1L),
    new_segment    = is.na(previous_index) | .data[[time_col]] != previous_index + 1L,
    segment_id     = cumsum(new_segment)
  ) %>%
  group_by(.data[[id_col]], segment_id) %>%
  summarise(
    start_index = min(.data[[time_col]], na.rm = TRUE),
    end_index   = max(.data[[time_col]], na.rm = TRUE),
    .groups     = "drop"
  ) %>%
  mutate(
    x_start = start_index * time_window_width / 24,
    x_end   = (end_index + 1L) * time_window_width / 24
  ) %>%
  left_join(patient_summary, by = id_col) %>%
  filter(x_start <= x_max_days) %>%
  mutate(x_end = pmin(x_end, x_max_days))

#========================================#
# 5. Create follow-up background lines
#========================================#
followup_segments <- patient_summary %>%
  transmute(
    patient_rank = patient_rank,
    y_position   = y_position,
    x_start      = 0,
    x_end        = pmin((last_observed_index + 1L) * time_window_width / 24, x_max_days)
  )

#========================================#
# 6. Create ICU discharge/death markers
#========================================#
event_df <- plot_df %>%
  semi_join(patient_summary, by = id_col) %>%
  filter(.data[[death_col]] == 1L | .data[[discharge_col]] == 1L) %>%
  mutate(
    event_status = if_else(
      .data[[death_col]] == 1L,
      "ICU death",
      "Discharged alive from ICU"
    ),
    x_event = (.data[[time_col]] + 1L) * time_window_width / 24
  ) %>%
  left_join(patient_summary, by = id_col) %>%
  filter(x_event <= x_max_days)

#========================================#
# 7. Check descriptive statistics
#========================================#
rtm_summary_stats <- patient_summary %>%
  summarise(
    n_patients        = n(),
    median_start_day  = median(first_rtm_day, na.rm = TRUE),
    q1_start_day      = quantile(first_rtm_day, 0.25, na.rm = TRUE),
    q3_start_day      = quantile(first_rtm_day, 0.75, na.rm = TRUE),
    median_total_days = median(total_rtm_days, na.rm = TRUE),
    q1_total_days     = quantile(total_rtm_days, 0.25, na.rm = TRUE),
    q3_total_days     = quantile(total_rtm_days, 0.75, na.rm = TRUE)
  )

print(rtm_summary_stats)

#========================================#
# 8. Plot Observed rTM administration
#========================================#
p_s2 <- ggplot() +
  geom_segment(
    data = followup_segments,
    aes(x = x_start, xend = x_end, y = y_position, yend = y_position),
    color = "grey88",
    linewidth = 0.35 * patient_height_scale,
    lineend = "butt"
  ) +
  geom_segment(
    data = tm_segments,
    aes(x = x_start, xend = x_end, y = y_position, yend = y_position),
    color = "#084594",
    linewidth = 0.85 * patient_height_scale,
    lineend = "butt"
  ) +
  geom_point(
    data = event_df,
    aes(x = x_event, y = y_position, shape = event_status, fill = event_status),
    size = 1.25 * patient_height_scale,
    color = "black",
    stroke = 0.20
  ) +
  scale_x_continuous(
    name = "Days since time zero",
    limits = c(0, x_max_days),
    breaks = seq(0, x_max_days, by = x_break_days),
    expand = expansion(mult = c(0, 0.01))
  ) +
  scale_y_reverse(
    name = "Patients who received rTM during ICU stay",
    breaks = seq(0, ceiling(n_rtm_patients / 100) * 100, by = 100),
    limits = c(n_rtm_patients + 1, 0),
    expand = expansion(mult = c(0.005, 0.005))
  ) +
  scale_shape_manual(
    name = NULL,
    values = c("Discharged alive from ICU" = 22, "ICU death" = 21)
  ) +
  scale_fill_manual(
    name = NULL,
    values = c("Discharged alive from ICU" = "grey55", "ICU death" = "#D55E00")
  ) +
  theme_classic(base_size = 8.5) +
  theme(
    axis.title = element_text(size = 16),
    axis.text = element_text(size = 16),
    legend.position = "bottom",
    legend.text = element_text(size = 12)
  )

print(p_s2)

#========================================#
# 9. Save figure
#========================================#
ggsave(
  filename = paste0(output_dir, "Supplementary_Figure_S2_rTM_treatment_history_", date, ".png"),
  plot = p_s2,
  width = 8.2,
  height = 8.5 * patient_height_scale,
  units = "in",
  dpi = 600
)