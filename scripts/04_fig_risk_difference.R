### g-formula risk difference ###
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(ggplot2)
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tibble", quietly = TRUE)) install.packages("tibble")
library(tibble)

# Usage:
#   Rscript scripts/04_fig_risk_difference.R --sg all --date 260827
#   Rscript scripts/04_fig_risk_difference.R --sg all --date 260827 --day 28
#   Rscript scripts/04_fig_risk_difference.R --sg all --date 260827 --cov-inv
output_dir <- "./output/"
plot_day <- 28L
dpi_out <- 600
tw_hr <- 24L

args <- commandArgs(trailingOnly = TRUE)
flag_value <- function(args, flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 0L || length(args) < idx[1] + 1L) return(default)
  args[idx[1] + 1L]
}
date <- flag_value(args, "--date", "260827")
if (!grepl("^[0-9]{6}$", date)) stop("--date must use YYMMDD format.")
sg <- flag_value(args, "--sg", "all")
outdir <- flag_value(args, "--outdir", output_dir)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
plot_day <- suppressWarnings(as.integer(flag_value(args, "--day", as.character(plot_day))))
if (is.na(plot_day)) stop("--day must be an integer.")
tw_hr <- suppressWarnings(as.integer(flag_value(args, "--tw", as.character(tw_hr))))
if (is.na(tw_hr) || tw_hr < 1L) stop("--tw must be a positive integer.")
cov_order_label <- if ("--cov-inv" %in% args) "inv" else "fwd"

font_family <- "sans"
if (requireNamespace("systemfonts", quietly = TRUE)) {
  fonts <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character())
  if ("Arial" %in% fonts) font_family <- "Arial"
}

rdata_file <- file.path(
  output_dir,
  paste0(date, "_gformula_ci_", tw_hr, "hr_", cov_order_label, "_", sg, ".RData")
)
if (!file.exists(rdata_file)) {
  stop("RData file not found: ", rdata_file)
}
load(rdata_file)

dfc <- results[[paste0("combined_", sg)]]
if (is.null(dfc)) {
  stop(
    "Result not found for subgroup '", sg, "'. ",
    "Available keys: ", paste(names(results), collapse = ", ")
  )
}
if (!"time_points" %in% names(dfc)) {
  stop("Column 'time_points' not found in combined results.")
}
if (!plot_day %in% dfc$time_points) {
  stop(
    "--day=", plot_day, " not found in time_points. ",
    "Available: ", paste(sort(unique(dfc$time_points)), collapse = ", ")
  )
}

tm_start_days <- if (exists("tm_start_days")) tm_start_days else 1:2
strategy_labels <- c(
  `1` = "rTM initiated\nwithin 24 hours",
  `2` = "rTM initiated\nat 24-48 hours"
)

risk_diff_df <- tibble(
  tm_day = tm_start_days,
  strategy = paste0("TM_day", tm_start_days)
) %>%
  mutate(
    mean_col = paste0(strategy, "_risk_diff_mean"),
    ul_col   = paste0("ul_risk_diff_", strategy),
    ll_col   = paste0("ll_risk_diff_", strategy),
    strategy_label = unname(strategy_labels[as.character(tm_day)])
  )
if (anyNA(risk_diff_df$strategy_label)) {
  stop("Missing strategy labels for tm_start_days: ", paste(tm_start_days, collapse = ", "))
}

missing_cols <- setdiff(
  c(risk_diff_df$mean_col, risk_diff_df$ul_col, risk_diff_df$ll_col),
  names(dfc)
)
if (length(missing_cols) > 0L) {
  stop("Missing risk-difference columns: ", paste(missing_cols, collapse = ", "))
}

df_day <- dfc %>% filter(time_points == plot_day)
if (nrow(df_day) != 1L) {
  stop("Expected 1 row for day ", plot_day, ", found ", nrow(df_day), ".")
}

risk_diff_plot_df <- risk_diff_df %>%
  mutate(
    risk_diff = vapply(mean_col, function(col) df_day[[col]][[1]], numeric(1)),
    ul = vapply(ul_col, function(col) df_day[[col]][[1]], numeric(1)),
    ll = vapply(ll_col, function(col) df_day[[col]][[1]], numeric(1))
  )

if (all(is.na(risk_diff_plot_df$ll) & is.na(risk_diff_plot_df$ul))) {
  message("[04] CI bounds are NA (point estimate only); plotting means without error bars.")
}

p_risk_diff <- ggplot(
  risk_diff_plot_df,
  aes(
    x = risk_diff,
    y = factor(strategy_label, levels = rev(strategy_label))
  )
) +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.5) +
  geom_errorbarh(
    aes(xmin = ll, xmax = ul),
    height = 0.2,
    linewidth = 0.7,
    na.rm = TRUE
  ) +
  geom_point(size = 2.5) +
  labs(
    x = "Risk Difference (vs no rTM)",
    y = NULL,
    title = paste0("Risk Difference at Day ", plot_day, " (", sg, ")")
  ) +
  theme_classic() +
  theme(
    text       = element_text(family = font_family),
    axis.text  = element_text(size = 16),
    axis.text.y = element_text(lineheight = 0.95),
    axis.title = element_text(size = 16),
    plot.title = element_text(size = 18),
    plot.margin = margin(10, 10, 10, 10)
  )

tryCatch(print(p_risk_diff), error = function(e) {
  message("[04] skip interactive print: ", conditionMessage(e))
})

f_risk_diff <- file.path(
  outdir,
  sprintf("%s_g_risk_diff_%shr_%s_%s.png", date, time_window_width, cov_order_label, sg)
)

ggsave(
  filename = f_risk_diff,
  plot     = p_risk_diff,
  width    = 8,
  height   = 6,
  dpi      = dpi_out
)
message("[04] wrote ", f_risk_diff)
