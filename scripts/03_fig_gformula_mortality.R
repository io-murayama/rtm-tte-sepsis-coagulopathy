### g-formula mortality curves ###
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tidyr", quietly = TRUE)) install.packages("tidyr")
library(tidyr)
if (!requireNamespace("ggplot2", quietly = TRUE)) install.packages("ggplot2")
library(ggplot2)

# Usage:
#   Rscript scripts/03_fig_gformula_mortality.R --sg all --date 260827
#   Rscript scripts/03_fig_gformula_mortality.R --sg all --date 260827 --stages first,second,combined
#   Rscript scripts/03_fig_gformula_mortality.R --sg all --date 260827 --tw 24
#   Rscript scripts/03_fig_gformula_mortality.R --sg all --date 260827 --cov-inv
output_dir <- "./output/"
ylim <- 0.40
y_breaks_by <- 0.10
dpi_out <- 600
tw_hr <- 24L

args <- commandArgs(trailingOnly = TRUE)
flag_value <- function(args, flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 0L || length(args) < idx[1] + 1L) return(default)
  args[idx[1] + 1L]
}
parse_csv <- function(x, default) {
  if (is.null(x) || !nzchar(x)) return(default)
  vals <- trimws(unlist(strsplit(x, ",", fixed = TRUE)))
  vals[nzchar(vals)]
}

date <- flag_value(args, "--date", "260827")
if (!grepl("^[0-9]{6}$", date)) stop("--date must use YYMMDD format.")
sg <- flag_value(args, "--sg", "all")
outdir <- flag_value(args, "--outdir", output_dir)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
stages <- parse_csv(flag_value(args, "--stages", NULL), c("first", "second", "combined"))
unknown_stages <- setdiff(stages, c("first", "second", "combined"))
if (length(unknown_stages)) {
  stop(
    "Unknown --stages: ", paste(unknown_stages, collapse = ", "),
    ". Allowed: first, second, combined"
  )
}
tw_hr <- suppressWarnings(as.integer(flag_value(args, "--tw", as.character(tw_hr))))
if (is.na(tw_hr) || tw_hr < 1L) stop("--tw must be a positive integer.")
cov_order_label <- if ("--cov-inv" %in% args) "inv" else "fwd"

strategy_colors <- c(
  TM_day1_surv_mean = "#084594",
  TM_day2_surv_mean = "#4292C6",
  no_TM_surv_mean   = "#7A7A7A"
)

stage_titles <- c(
  first = "First stage (in-ICU mortality)",
  second = "Second stage (post-ICU mortality)",
  combined = "Combined (overall mortality)"
)

tm_strategy_labels <- c(
  `1` = "rTM initiated within 24 hours",
  `2` = "rTM initiated at 24-48 hours"
)

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

if (exists("int_descript")) {
  tm_days <- paste0(int_descript[grepl("^TM_day", int_descript)], "_surv_mean")
} else {
  tm_days <- paste0("TM_day", 1:2, "_surv_mean")
}
no_tm_col <- "no_TM_surv_mean"

label_for_tm_col <- function(col) {
  day <- sub("^TM_day(\\d+)_surv_mean$", "\\1", col)
  lab <- unname(tm_strategy_labels[day])
  if (is.na(lab)) paste0("rTM day ", day) else lab
}

build_surv_plot <- function(dfc, stage) {
  if (is.null(dfc)) {
    stop(
      "Result not found for stage '", stage, "' / subgroup '", sg, "'. ",
      "Available keys: ", paste(names(results), collapse = ", ")
    )
  }

  surv_cols <- c(tm_days, no_tm_col)
  missing_cols <- setdiff(surv_cols, names(dfc))
  if (length(missing_cols)) {
    stop(
      "Missing survival columns in stage '", stage, "': ",
      paste(missing_cols, collapse = ", ")
    )
  }

  strategy_labels <- c(
    stats::setNames(vapply(tm_days, label_for_tm_col, character(1)), tm_days),
    stats::setNames("no rTM", no_tm_col)
  )
  strategy_labels <- strategy_labels[surv_cols]

  pal_col <- c(
    stats::setNames(strategy_colors[tm_days], tm_days),
    no_TM_surv_mean = "#7A7A7A"
  )

  df_long <- dfc %>%
    dplyr::select(time_points, all_of(surv_cols)) %>%
    tidyr::pivot_longer(
      cols = -time_points,
      names_to = "strategy",
      values_to = "survival"
    ) %>%
    dplyr::mutate(
      mortality = 1 - survival,
      strategy = factor(strategy, levels = surv_cols)
    )

  ggplot(df_long, aes(x = time_points, y = mortality, colour = strategy)) +
    geom_step(linewidth = 0.8) +
    scale_x_continuous(
      limits = c(0, followup_length),
      breaks = seq(0, followup_length, by = 7)
    ) +
    scale_y_continuous(
      limits = c(0, 1 - ylim),
      breaks = seq(0, 1 - ylim, by = y_breaks_by)
    ) +
    scale_colour_manual(values = pal_col, labels = strategy_labels) +
    labs(
      title  = paste0(stage_titles[[stage]], " (", sg, ")"),
      x      = "Days Since Time 0",
      y      = "Mortality",
      colour = "Treatment Strategy"
    ) +
    theme_classic() +
    theme(
      text            = element_text(family = font_family),
      axis.text       = element_text(size = 16),
      axis.title      = element_text(size = 16),
      legend.text     = element_text(size = 12),
      legend.title    = element_text(size = 14),
      legend.position = "right",
      plot.title      = element_text(size = 18)
    )
}

for (stage in stages) {
  dfc <- results[[paste0(stage, "_", sg)]]
  p <- build_surv_plot(dfc, stage)
  tryCatch(print(p), error = function(e) {
    message("[03] skip interactive print for stage=", stage, ": ", conditionMessage(e))
  })

  out_file <- file.path(
    outdir,
    sprintf("%s_g_surv_%s_%shr_%s_%s.png", date, stage, time_window_width, cov_order_label, sg)
  )
  ggsave(
    filename = out_file,
    plot     = p,
    width    = 8,
    height   = 6,
    dpi      = dpi_out
  )
  message("[03] wrote ", out_file)
}
