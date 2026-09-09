### Subgroup forest plot (day-28 mortality risk differences) ###
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tidyr", quietly = TRUE)) install.packages("tidyr")
library(tidyr)
if (!requireNamespace("tibble", quietly = TRUE)) install.packages("tibble")
library(tibble)
if (!requireNamespace("purrr", quietly = TRUE)) install.packages("purrr")
library(purrr)
if (!requireNamespace("forestplot", quietly = TRUE)) install.packages("forestplot")
library(forestplot)
if (!requireNamespace("grid", quietly = TRUE)) install.packages("grid")
library(grid)

# Usage:
#   Rscript scripts/10_fig_subgroup_forest.R --date 260827
#   Rscript scripts/10_fig_subgroup_forest.R --date 260827 --day 28
#   Rscript scripts/10_fig_subgroup_forest.R --date 260827 --cov-inv
data_dir <- "./data/"
output_dir <- "./output/"
plot_day <- 28L
tw_hr <- 24L
dpi_out <- 200
png_width <- 1550
png_height <- 580

args <- commandArgs(trailingOnly = TRUE)
flag_value <- function(args, flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 0L || length(args) < idx[1] + 1L) return(default)
  args[idx[1] + 1L]
}

date <- flag_value(args, "--date", "260827")
if (!grepl("^[0-9]{6}$", date)) stop("--date must use YYMMDD format.")
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

sg_keys <- c(
  "all",
  "sofa_less_than_10",
  "sofa_10_or_higher",
  "apache2_less_than_25",
  "apache2_25_or_higher"
)

rows_spec <- tibble(
  sg_key = c(
    "all",
    "sofa_header",
    "sofa_less_than_10",
    "sofa_10_or_higher",
    "apache_header",
    "apache2_less_than_25",
    "apache2_25_or_higher"
  ),
  label = c(
    "All patients",
    "SOFA",
    "  <10",
    "  ≥10",
    "APACHE II",
    "  <25",
    "  ≥25"
  ),
  row_type = c(
    "data",
    "header",
    "data",
    "data",
    "header",
    "data",
    "data"
  ),
  row_order = seq_len(7)
)

extract_one_sg <- function(sg, output_dir, date, tw_hr, cov_order_label, plot_day) {
  load_path <- file.path(
    output_dir,
    paste0(date, "_gformula_ci_", tw_hr, "hr_", cov_order_label, "_", sg, ".RData")
  )
  if (!file.exists(load_path)) {
    stop("RData file not found: ", load_path)
  }
  e <- new.env(parent = emptyenv())
  load(load_path, envir = e)
  combined_df <- e$results[[paste0("combined_", sg)]]
  if (is.null(combined_df)) {
    stop("combined_", sg, " not found in ", load_path)
  }
  if (!plot_day %in% combined_df$time_points) {
    stop(
      "day=", plot_day, " not found for sg=", sg, ". Available: ",
      paste(sort(unique(combined_df$time_points)), collapse = ", ")
    )
  }

  day_row <- combined_df %>% filter(time_points == !!plot_day)
  if (nrow(day_row) != 1L) {
    stop("Expected 1 row for day ", plot_day, " / sg=", sg, ", found ", nrow(day_row), ".")
  }

  tibble(
    sg_key = sg,
    day = as.integer(plot_day),
    mort_no_tm = 1 - day_row$no_TM_surv_mean[[1]],
    mort_tm1 = 1 - day_row$TM_day1_surv_mean[[1]],
    mort_tm2 = 1 - day_row$TM_day2_surv_mean[[1]],
    rd_tm1 = day_row$TM_day1_risk_diff_mean[[1]],
    rd_lcl_tm1 = day_row$ll_risk_diff_TM_day1[[1]],
    rd_ucl_tm1 = day_row$ul_risk_diff_TM_day1[[1]],
    rd_tm2 = day_row$TM_day2_risk_diff_mean[[1]],
    rd_lcl_tm2 = day_row$ll_risk_diff_TM_day2[[1]],
    rd_ucl_tm2 = day_row$ul_risk_diff_TM_day2[[1]]
  )
}

sg_data <- map_dfr(
  sg_keys,
  ~ extract_one_sg(.x, output_dir, date, tw_hr, cov_order_label, plot_day)
)

data_path <- file.path(data_dir, paste0("df_", date, "_all.RData"))
if (!file.exists(data_path)) {
  stop("Analysis data not found: ", data_path)
}
load(data_path)
if (!exists("df")) stop("Object 'df' not found in ", data_path)

df_base <- df %>%
  filter(time_window_index == 0)

n_table <- tibble(
  sg_key = sg_keys,
  n_patients = c(
    nrow(df_base),
    nrow(filter(df_base, sofa_score < 10)),
    nrow(filter(df_base, sofa_score >= 10)),
    nrow(filter(df_base, apache2_score < 25)),
    nrow(filter(df_base, apache2_score >= 25))
  )
)

forestplot_input <- rows_spec %>%
  left_join(n_table, by = "sg_key") %>%
  left_join(sg_data, by = "sg_key") %>%
  mutate(
    across(
      c(
        mort_no_tm, mort_tm1, mort_tm2,
        rd_tm1, rd_lcl_tm1, rd_ucl_tm1,
        rd_tm2, rd_lcl_tm2, rd_ucl_tm2
      ),
      ~ ifelse(row_type == "data", .x, NA_real_)
    )
  ) %>%
  arrange(row_order)

xlim <- c(-16, 6)
xticks <- seq(-16, 6, by = 4)

df2 <- forestplot_input %>%
  mutate(
    n_txt = ifelse(
      is.na(n_patients),
      "",
      paste0("  ", format(n_patients, big.mark = ","), "  ")
    ),
    mort_no_txt = ifelse(is.na(mort_no_tm), "", sprintf("  %.1f  ", 100 * mort_no_tm)),
    mort_tm1_txt = ifelse(is.na(mort_tm1), "", sprintf("  %.1f  ", 100 * mort_tm1)),
    mort_tm2_txt = ifelse(is.na(mort_tm2), "", sprintf("  %.1f  ", 100 * mort_tm2)),
    rd_tm1_txt = ifelse(
      is.na(rd_tm1),
      "",
      sprintf(
        "%.1f (%.1f, %.1f)",
        100 * rd_tm1,
        100 * rd_lcl_tm1,
        100 * rd_ucl_tm1
      )
    ),
    rd_tm2_txt = ifelse(
      is.na(rd_tm2),
      "",
      sprintf(
        "%.1f (%.1f, %.1f)",
        100 * rd_tm2,
        100 * rd_lcl_tm2,
        100 * rd_ucl_tm2
      )
    )
  )

tabletext_header <- rbind(
  c(
    "Subgroup",
    "  N  ",
    "No rTM (%)",
    "Within 24 h (%)",
    "24–48 h (%)",
    "RD Within 24 h (pp)",
    "RD 24–48 h (pp)"
  )
)

tabletext_body <- df2 %>%
  select(
    label, n_txt, mort_no_txt, mort_tm1_txt, mort_tm2_txt,
    rd_tm1_txt, rd_tm2_txt
  ) %>%
  as.matrix()

tabletext <- rbind(tabletext_header, tabletext_body)

mean_mat_data <- cbind(
  ifelse(df2$row_type == "data", 100 * df2$rd_tm1, NA_real_),
  ifelse(df2$row_type == "data", 100 * df2$rd_tm2, NA_real_)
)
lower_mat_data <- cbind(
  ifelse(df2$row_type == "data", 100 * df2$rd_lcl_tm1, NA_real_),
  ifelse(df2$row_type == "data", 100 * df2$rd_lcl_tm2, NA_real_)
)
upper_mat_data <- cbind(
  ifelse(df2$row_type == "data", 100 * df2$rd_ucl_tm1, NA_real_),
  ifelse(df2$row_type == "data", 100 * df2$rd_ucl_tm2, NA_real_)
)

clip_to_xlim <- function(x) {
  pmin(pmax(x, xlim[1], na.rm = FALSE), xlim[2], na.rm = FALSE)
}

mean_mat_data_plot <- clip_to_xlim(mean_mat_data)
lower_mat_data_plot <- pmax(lower_mat_data, xlim[1], na.rm = FALSE)
upper_mat_data_plot <- pmin(upper_mat_data, xlim[2], na.rm = FALSE)

na_header <- matrix(NA_real_, nrow = 1L, ncol = 2L)
mean_mat <- rbind(na_header, mean_mat_data_plot)
lower_mat <- rbind(na_header, lower_mat_data_plot)
upper_mat <- rbind(na_header, upper_mat_data_plot)

is_summary_vec <- c(TRUE, df2$row_type == "header")

out_path <- file.path(
  outdir,
  sprintf(
    "%s_forest_subgroup_day%d_%shr_%s.png",
    date, plot_day, tw_hr, cov_order_label
  )
)

png(out_path, width = png_width, height = png_height, res = dpi_out)

fp <- forestplot(
  labeltext = tabletext,
  mean = mean_mat,
  lower = lower_mat,
  upper = upper_mat,
  is.summary = is_summary_vec,
  zero = 0,
  xlog = FALSE,
  xticks = xticks,
  xlim = xlim,
  graph.pos = 6,
  graphwidth = unit(48, "mm"),
  colgap = unit(1.5, "mm"),
  mar = unit(c(1, 1, 1, 1), "mm"),
  align = c("l", "c", "c", "c", "c", "c", "c"),
  boxsize = 0.20,
  line.margin = 0.28,
  xlab = "Risk difference (percentage points)",
  title = paste0(
    "Subgroup analysis of ",
    plot_day,
    "-day mortality: risk difference vs no rTM (95% CI)"
  ),
  legend = c("Within 24 h", "24–48 h"),
  legend_args = fpLegend(
    pos = "top",
    title = "rTM"
  ),
  fn.ci_norm = c(fpDrawNormalCI, fpDrawCircleCI),
  col = fpColors(
    box = c("black", "black"),
    lines = c("black", "black"),
    summary = "black"
  ),
  hrzl_lines = list("2" = gpar(lwd = 1)),
  txt_gp = fpTxtGp(
    title = gpar(fontface = "bold", fontfamily = font_family, cex = 0.78),
    label = gpar(fontfamily = font_family, cex = 0.62),
    ticks = gpar(fontfamily = font_family, cex = 0.60),
    xlab = gpar(fontfamily = font_family, cex = 0.62),
    legend = gpar(fontfamily = font_family, cex = 0.56)
  )
)
fp <- fp_set_zebra_style(fp, "#F5F5F5", ignore_subheaders = TRUE)

print(fp)
dev.off()

message("[10] wrote ", out_path)
