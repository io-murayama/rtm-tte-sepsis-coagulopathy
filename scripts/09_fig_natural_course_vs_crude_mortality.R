### Natural course (point estimate) vs observed crude mortality ###
### Full cohort (all) only — g-formula calibration check (no CI ribbon).
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tidyr", quietly = TRUE)) install.packages("tidyr")
library(tidyr)
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(ggplot2)

# Usage:
#   Rscript scripts/02_gformula.R --sg all --single --date 260827
#   Rscript scripts/09_fig_natural_course_vs_crude_mortality.R --date 260827
#   Rscript scripts/09_fig_natural_course_vs_crude_mortality.R --date 260827 --cov-inv
#
# Optional:
#   --stage combined|first|second   (default: combined)
#   --tw 24
#   --outdir ./output
#   --allow-ci   fall back to _gformula_ci_*.RData if point-estimate file is missing
#   --cov-inv    use inverted covariate modeling order results
data_dir   <- "./data"
output_dir <- "./output"
sg         <- "all"
ylim       <- 0.50
y_breaks_by <- 0.10
dpi_out    <- 600
followup_length_default   <- 28L
time_window_width_default <- 24L

args <- commandArgs(trailingOnly = TRUE)
flag_value <- function(args, flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 0L || length(args) < idx[1] + 1L) return(default)
  args[idx[1] + 1L]
}

if ("--sg" %in% args) {
  stop(
    "[09] This figure is for the full cohort only; do not pass --sg. ",
    "Use: Rscript scripts/09_fig_natural_course_vs_crude_mortality.R --date YYMMDD"
  )
}

date <- flag_value(args, "--date", "260827")
if (!grepl("^[0-9]{6}$", date)) stop("--date must use YYMMDD format.")

stage <- flag_value(args, "--stage", "combined")
if (!stage %in% c("first", "second", "combined")) {
  stop("--stage must be one of: first, second, combined")
}
outdir <- flag_value(args, "--outdir", output_dir)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
tw_hr <- suppressWarnings(as.integer(flag_value(
  args, "--tw", as.character(time_window_width_default)
)))
if (is.na(tw_hr) || tw_hr < 1L) stop("--tw must be a positive integer.")
allow_ci <- "--allow-ci" %in% args
cov_order_label <- if ("--cov-inv" %in% args) "inv" else "fwd"

font_family <- "sans"
if (requireNamespace("systemfonts", quietly = TRUE)) {
  fonts <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character())
  if ("Arial" %in% fonts) font_family <- "Arial"
}

#========================================#
# 1. Load Natural course from g-formula  #
#========================================#
pe_file <- file.path(
  output_dir,
  paste0(date, "_gformula_pe_", tw_hr, "hr_", cov_order_label, "_", sg, ".RData")
)
ci_file <- file.path(
  output_dir,
  paste0(date, "_gformula_ci_", tw_hr, "hr_", cov_order_label, "_", sg, ".RData")
)

rdata_file <- pe_file
source_label <- "point estimate (--single)"
if (!file.exists(pe_file)) {
  if (isTRUE(allow_ci) && file.exists(ci_file)) {
    rdata_file <- ci_file
    source_label <- "bootstrap CI mean (fallback via --allow-ci)"
    message("[09] Point-estimate RData not found; using CI file: ", ci_file)
  } else {
    stop(
      "Point-estimate RData not found: ", pe_file, "\n",
      "Run first:\n",
      "  Rscript scripts/02_gformula.R --sg all --single --date ", date,
      if (identical(cov_order_label, "inv")) " --cov-inv" else "", "\n",
      "Or pass --allow-ci to fall back to ", ci_file
    )
  }
} else {
  message("[09] Using ", source_label, ": ", pe_file)
}

load(rdata_file)

followup_length <- if (exists("followup_length")) {
  as.integer(followup_length)
} else {
  followup_length_default
}
time_window_width <- if (exists("time_window_width")) {
  as.integer(time_window_width)
} else {
  tw_hr
}

dfc <- results[[paste0(stage, "_", sg)]]
if (is.null(dfc)) {
  stop(
    "Result not found for stage '", stage, "' / subgroup '", sg, "'. ",
    "Available keys: ", paste(names(results), collapse = ", ")
  )
}

nc_risk_col <- "Natural_course_risk_mean"
nc_surv_col <- "Natural_course_surv_mean"
if (nc_risk_col %in% names(dfc)) {
  nc_mort <- as.numeric(dfc[[nc_risk_col]])
} else if (nc_surv_col %in% names(dfc)) {
  nc_mort <- 1 - as.numeric(dfc[[nc_surv_col]])
} else {
  stop(
    "Natural course columns not found in results. Expected ",
    nc_risk_col, " or ", nc_surv_col, "."
  )
}
if (!"time_points" %in% names(dfc)) {
  stop("Column 'time_points' not found in g-formula results.")
}

df_nc <- tibble::tibble(
  time_points = as.numeric(dfc$time_points),
  mortality = nc_mort,
  curve = "Natural course"
)

#========================================#
# 2. Observed crude all-cause mortality  #
#========================================#
data_file <- file.path(data_dir, paste0("df_", date, "_all.RData"))
if (!file.exists(data_file)) {
  stop("Analysis data not found: ", data_file)
}
load(data_file)
if (!exists("df")) stop("Object 'df' not found in ", data_file)

sg_ids <- df %>%
  filter(time_window_index == 0) %>%
  distinct(icu_stay_id) %>%
  pull(icu_stay_id)

df_last <- df %>%
  filter(icu_stay_id %in% sg_ids) %>%
  filter(time_window_index <= followup_length * (24 / time_window_width) - 1) %>%
  group_by(icu_stay_id) %>%
  arrange(time_window_index, .by_group = TRUE) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  mutate(
    icu_length_of_stay_days = (time_window_index + 1) * time_window_width / 24,
    death_time = dplyr::case_when(
      icu_death == 1 ~ icu_length_of_stay_days,
      icu_discharge_alive == 1 ~
        # Same coding as 02/06: death on discharge day recorded as survival_after=0
        icu_length_of_stay_days + survival_after_icu_discharge + 1,
      TRUE ~ 100 * 365
    ),
    death_time = dplyr::if_else(death_time <= followup_length, death_time, 100 * 365)
  )

time_grid <- seq(0, followup_length, by = time_window_width / 24)
df_crude <- tibble::tibble(
  time_points = time_grid,
  mortality = vapply(
    time_grid,
    function(t) mean(df_last$death_time <= t, na.rm = TRUE),
    numeric(1)
  ),
  curve = "Observed mortality"
)

message(sprintf(
  "[09] Crude cohort n=%d | NC source=%s | stage=%s",
  dplyr::n_distinct(df_last$icu_stay_id),
  source_label,
  stage
))

#========================================#
# 3. Combine and plot                    #
#========================================#
df_plot <- dplyr::bind_rows(df_nc, df_crude) %>%
  dplyr::mutate(
    curve = factor(curve, levels = c("Natural course", "Observed mortality"))
  )

pal_col <- c(
  "Natural course" = "#000000",
  "Observed mortality" = "#084594"
)

p <- ggplot2::ggplot(
  df_plot,
  ggplot2::aes(x = time_points, y = mortality, colour = curve)
) +
  ggplot2::geom_step(linewidth = 0.8) +
  ggplot2::scale_x_continuous(
    limits = c(0, followup_length),
    breaks = seq(0, followup_length, by = 7)
  ) +
  ggplot2::scale_y_continuous(
    limits = c(0, 1 - ylim),
    breaks = seq(0, 1 - ylim, by = y_breaks_by)
  ) +
  ggplot2::scale_colour_manual(values = pal_col) +
  ggplot2::labs(
    title = "Natural Course vs Observed Mortality",
    x = "Days Since Time 0",
    y = "Mortality",
    colour = NULL
  ) +
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = 1, byrow = TRUE)) +
  ggplot2::theme_classic() +
  ggplot2::theme(
    text = ggplot2::element_text(family = font_family),
    axis.text = ggplot2::element_text(size = 16),
    axis.title = ggplot2::element_text(size = 16),
    legend.text = ggplot2::element_text(size = 12),
    legend.position = "bottom",
    legend.direction = "horizontal",
    plot.title = ggplot2::element_text(size = 18)
  )

f_plot <- file.path(
  outdir,
  sprintf(
    "%s_natural_course_vs_observed_mortality_%shr_%s_%s.png",
    date, time_window_width, cov_order_label, sg
  )
)
f_csv <- file.path(
  outdir,
  sprintf(
    "%s_natural_course_vs_observed_mortality_%shr_%s_%s.csv",
    date, time_window_width, cov_order_label, sg
  )
)

ggplot2::ggsave(f_plot, p, width = 8, height = 6, dpi = dpi_out)
utils::write.csv(df_plot, f_csv, row.names = FALSE)

tryCatch(print(p), error = function(e) {
  message("[09] skip interactive print: ", conditionMessage(e))
})
if (file.exists("Rplots.pdf")) {
  unlink("Rplots.pdf")
}

message("[09] wrote ", f_plot)
message("[09] wrote ", f_csv)
