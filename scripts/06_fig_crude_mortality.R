### visualization: crude mortality curves stratified by rTM ever use ###
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(ggplot2)
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tidyr", quietly = TRUE)) install.packages("tidyr")
library(tidyr)

#========================================#
# Configurations                         #
#========================================#
date <- "260827"
data_dir <- "./data/"
output_dir <- "./output/"
followup_length <- 28
time_window_width <- 24
ylim <- 0.50
y_breaks_by <- 0.10
dpi_out <- 600

font_family <- "sans"
if (requireNamespace("systemfonts", quietly = TRUE)) {
  fonts <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character())
  if ("Arial" %in% fonts) font_family <- "Arial"
}

#========================================#
# 1. Load data                           #
#========================================#
load(paste0(data_dir, "df_", date, "_all.RData"))

#========================================#
# 2. Define rTM ever-use group           #
#========================================#
rtm_group <- df %>%
  group_by(icu_stay_id) %>%
  summarise(
    rtm_ever_use = as.integer(any(thrombomodulin_use == 1, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  mutate(
    rtm_ever_use = factor(
      rtm_ever_use,
      levels = c(1, 0),
      labels = c("rTM use", "No rTM use")
    )
  )

#========================================#
# 3. Define observed death time          #
#========================================#
df_last <- df %>%
  group_by(icu_stay_id) %>%
  arrange(time_window_index, .by_group = TRUE) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  left_join(rtm_group, by = "icu_stay_id") %>%
  mutate(
    icu_length_of_stay_days = (time_window_index + 1) * time_window_width / 24,
    death_time = case_when(
      icu_death == 1 ~ icu_length_of_stay_days,
      icu_discharge_alive == 1 ~
        # 退室時~1日目までの死亡はsurvival_after_icu_discharge = 0 と記録されている
        icu_length_of_stay_days + survival_after_icu_discharge + 1,
      # 28日以内死亡が確認されない場合は十分遠い日付を入れる
      TRUE ~ 100 * 365
    ),
    death_time = if_else(death_time <= followup_length, death_time, 100 * 365)
  )

#========================================#
# 4. Calculate crude mortality           #
#========================================#
time_points <- seq(0, followup_length, by = time_window_width / 24)

df_surv <- tidyr::expand_grid(
  rtm_ever_use = levels(df_last$rtm_ever_use),
  time_points = time_points
) %>%
  left_join(
    df_last %>% select(icu_stay_id, rtm_ever_use, death_time),
    by = "rtm_ever_use",
    relationship = "many-to-many"
  ) %>%
  group_by(rtm_ever_use, time_points) %>%
  summarise(
    n = n_distinct(icu_stay_id),
    survival = 1 - mean(death_time <= time_points, na.rm = TRUE),
    mortality = 1 - survival,
    .groups = "drop"
  )

#========================================#
# 5. Visualization                       #
#========================================#
pal_col <- c(
  "rTM use" = "#084594",
  "No rTM use" = "#7A7A7A"
)

p_crude_mortality <- ggplot(df_surv, aes(x = time_points, y = mortality, colour = rtm_ever_use)) +
  geom_step(linewidth = 0.8) +
  scale_x_continuous(
    limits = c(0, followup_length),
    breaks = seq(0, followup_length, by = 7)
  ) +
  scale_y_continuous(
    limits = c(0, 1 - ylim),
    breaks = seq(0, 1 - ylim, by = y_breaks_by)
  ) +
  scale_colour_manual(values = pal_col) +
  labs(
    x = "Days Since Time 0",
    y = "Mortality",
    colour = "Observed rTM Use"
  ) +
  guides(
    colour = guide_legend(
      nrow = 1,
      byrow = TRUE
    )
  ) +
  theme_classic() +
  theme(
    text = element_text(family = font_family),
    axis.text = element_text(size = 16),
    axis.title = element_text(size = 16),
    legend.text = element_text(size = 12),
    legend.title = element_text(size = 14),
    legend.position = "bottom",
    legend.direction = "horizontal",
    plot.title = element_text(size = 18)
  )

#========================================#
# 6. Save outputs                        #
#========================================#
f_crude_mortality <- file.path(
  output_dir,
  sprintf("%s_crude_mortality_by_rtm_ever_use_%shr.png", date, time_window_width)
)

ggsave(
  filename = f_crude_mortality,
  plot = p_crude_mortality,
  width = 8,
  height = 6,
  dpi = dpi_out
)

write.csv(
  df_surv,
  file = file.path(output_dir, sprintf("%s_crude_mortality_by_rtm_ever_use.csv", date)),
  row.names = FALSE
)