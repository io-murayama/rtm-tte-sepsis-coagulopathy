### gformula simulations ###
if (!require("Amelia")) install.packages("Amelia")
library(Amelia)
if (!require("tidyverse")) install.packages("tidyverse")
library(tidyverse)
if (!require("gfoRmula")) install.packages("gfoRmula")
library(gfoRmula)
if (!require("dplyr")) install.packages("dplyr")
library(dplyr)
if (!require("data.table")) install.packages("data.table")
library(data.table)
if (!require("dtplyr")) install.packages("dtplyr")
library(dtplyr)
if (!require("future.apply")) install.packages("future.apply")
library(future.apply)
if (!require("parallel")) install.packages("parallel")
library(parallel) 
if (!require("progressr")) install.packages("progressr")
library(progressr)
if (!require("RhpcBLASctl")) install.packages("RhpcBLASctl")
library(RhpcBLASctl)
if (!require("truncnorm")) install.packages("truncnorm")
library(truncnorm)

#========================================#
# Configurations                         #
#========================================#
handlers(handler_txtprogressbar)
handlers(global = TRUE)
options(
  progressr.enable = TRUE,
  progressr.clear = FALSE
)

data_dir   <- './data/'
output_dir <- './output/'

set.seed(813)
followup_length   <- 28        # followup期間（日）
time_window_width <- 24        # time windowの幅（時間）
n_simul_min       <- 10000     # Monte Carlo simulationの最低症例数（gfoRmulaで使用）
size              <- NULL      # bootstrapサンプルサイズ（NULLなら元の症例数を使う）

total_ram     <- 90 * 1024^3  # 利用可能RAMに合わせて調整
max_workers   <- detectCores() - 1 
print(sprintf("Detected %d CPU cores, using up to %d workers", detectCores(), max_workers))
ram_use_frac  <- 0.7          # 利用するRAMの割合
expand_factor <- 80           # 処理中に膨らむ分（中間オブジェクトなど）を見込む係数

subgroup_filters <- rlang::quos(
  all                    = (TRUE),
  sofa_10_or_higher      = (sofa_score >= 10),
  sofa_less_than_10      = (sofa_score < 10),
  apache2_25_or_higher   = (apache2_score >= 25),
  apache2_less_than_25   = (apache2_score < 25)
)

# Usage:
#   Rscript scripts/02_gformula.R --sg all --date 260827 --n-iter 25
#   Rscript scripts/02_gformula.R --sg all --single
#   Rscript scripts/02_gformula.R --sg all --single --cov-inv   # reverse L order; TM/AT stay last
args          <- commandArgs(trailingOnly = TRUE)
flag_value <- function(args, flag, default = NULL) {
  idx <- which(args == flag)
  if (length(idx) == 0L || length(args) < idx[1] + 1L) return(default)
  args[idx[1] + 1L]
}
sg_idx        <- which(args == "--sg")
run_single    <- "--single" %in% args || "--no-bootstrap" %in% args
use_cov_inv   <- "--cov-inv" %in% args
cov_order_label <- if (use_cov_inv) "inv" else "fwd"

date <- flag_value(args, "--date", "260827")
if (!grepl("^[0-9]{6}$", date)) stop("--date must use YYMMDD format.")

n_iter <- suppressWarnings(as.integer(flag_value(args, "--n-iter", "1000")))
if (is.na(n_iter) || n_iter < 1L) stop("--n-iter must be a positive integer.")

if (length(sg_idx) == 0) {
  chosen_sg   <- "all" # 指定がない場合は all（全症例）を選択
} else if (length(sg_idx) > 1) {
  stop("Error: --sg must be specified only once.")
} else if (length(args) < sg_idx + 1) {
  stop("Error: --sg must be followed by a subgroup name.")
} else {
  chosen_sg <- args[sg_idx + 1]
}

# gformula.source_only=TRUE のときは他スクリプトから source される想定
if (!isTRUE(getOption("gformula.source_only", FALSE))) {
  if (!chosen_sg %in% names(subgroup_filters)) {
    stop(
      "Error: unknown subgroup '", chosen_sg, "'. ",
      "Available: ", paste(names(subgroup_filters), collapse = ", ")
    )
  }
} else if (!chosen_sg %in% names(subgroup_filters)) {
  chosen_sg <- "all"
}

# 介入: day1/day2 から6日間 rTM（有害事象で中止）+ no_TM
tm_start_days <- c(1:2)

message(sprintf(
  "[CLI] date=%s | subgroup=%s | mode=%s | n_iter=%s | cov=%s",
  date,
  chosen_sg,
  if (run_single) "single (no bootstrap)" else "bootstrap",
  if (run_single) "NA" else as.character(n_iter),
  cov_order_label
))

gformula_rdata_stem <- function(kind, date, time_window_width, cov_order_label, sg) {
  # kind: "ci" or "pe"
  paste0(date, "_gformula_", kind, "_", time_window_width, "hr_", cov_order_label, "_", sg)
}

#========================================#
# 0. parallel planning                   #
#    subgroupごとに適切な並列数を推定    #
#========================================#
estimate_bytes_per_row <- function(df_filtered, sample_n = 50000L) {
  n <- nrow(df_filtered)
  s <- df_filtered[sample.int(n, min(sample_n, n)), ]
  return(as.numeric(object.size(s)) / nrow(s))
}

workers_for_sg <- function(n_rows_sg,
                           bytes_per_row,
                           n_iter,
                           total_ram,
                           max_workers,
                           ram_use_frac,
                           expand_factor) {
  budget         <- total_ram * ram_use_frac                   # 予算メモリ
  bytes_per_iter <- n_rows_sg * bytes_per_row * expand_factor  # 1回のsimulationに必要なメモリ
  w              <- floor(budget / bytes_per_iter)             # 同時に動かせるワーカー数
  return(max(1L, min(max_workers, w, n_iter)))
}


#========================================#
# 1. Bootstrap, Imputation               #
#    icu_stay_id単位でリサンプリング     #
#    単一代入法により欠損を処理          #
#========================================#
bootstrap_by_icu <- function(df) {
  orig_ids <- df %>% distinct(icu_stay_id)
  id_map   <- orig_ids %>%
    slice_sample(n = nrow(orig_ids), replace = TRUE) %>%
    mutate(new_id = row_number())
  df_boot  <- id_map %>%
    left_join(df, by = "icu_stay_id", relationship = "many-to-many") %>% 
    mutate(icu_stay_id = as.integer(new_id)) %>%
    select(-new_id) %>%
    arrange(icu_stay_id, time_window_index)
  
  return(df_boot)
}

single_imputation <- function(df) {
  target_cols <- c(
    "bt", "hr", "rr", "mbp", "spo2", "lactate", "pt_inr", "platelet",
    "sofa_score"
  )

  other_cols <- setdiff(names(df), target_cols)
  if (any(sapply(df[other_cols], function(x) any(is.na(x))))) {
    stop("Error in single_imputation: target_cols 以外に欠損値が含まれています。")
  }

  # Amelia bounds: sofa は定義域 [0,24]、他は標本の観測 min/max
  fixed_bounds <- list(
    sofa_score = c(0, 24)
  )
  observed_bound_cols <- setdiff(target_cols, names(fixed_bounds))
  observed_bounds <- setNames(
    lapply(observed_bound_cols, function(v) {
      rng <- suppressWarnings(range(df[[v]], na.rm = TRUE))
      if (!all(is.finite(rng))) {
        stop("Error in single_imputation: no finite values to bound column: ", v)
      }
      rng
    }),
    observed_bound_cols
  )
  bound_specs <- c(fixed_bounds, observed_bounds)
  bounds <- do.call(rbind, lapply(names(bound_specs), function(v) {
    j <- match(v, names(df))
    if (is.na(j)) {
      stop("Error in single_imputation: bound column missing: ", v)
    }
    c(j, bound_specs[[v]])
  }))
  
  amel <- amelia(
    x = df,
    m = 1,
    cs = "icu_stay_id",
    ts = "time_window_index",
    polytime = 2,
    noms = c("hospital_id_model", "icu_admission_year"),
    idvars = NULL,
    empri = 0.005 * nrow(df),
    p2s = 2,
    parallel = 'no',
    bounds = bounds,
    max.resample = 1000
  )
  
  df_imputed <- amel$imputations[[1]]
  
  return(df_imputed)
}


#========================================#
# 2. G-formula survival model            #
#    ICU退室後のモデルを作成             #
#========================================#
create_cumulatives <- function(df, df_last) {
  counts <- df %>%
    group_by(icu_stay_id) %>%
    summarise(
      mean_ned               = mean(noradrenaline_equivalent_dose, na.rm = TRUE),
      num_heparin_use        = sum(heparin_use == 1, na.rm = TRUE),
      num_rbc_use            = sum(rbc_use == 1, na.rm = TRUE),
      num_ffp_use            = sum(ffp_use == 1, na.rm = TRUE),
      num_pc_use             = sum(pc_use == 1, na.rm = TRUE),
      num_thrombomodulin_use = sum(thrombomodulin_use == 1, na.rm = TRUE),
      num_antithrombin_use   = sum(antithrombin_use == 1, na.rm = TRUE),
      count_mv               = sum(mechanical_ventilation_use == 1, na.rm = TRUE),
      count_vasopressor      = sum(noradrenaline_equivalent_dose > 0, na.rm = TRUE),
      adverse_event_ever     = as.integer(any(adverse_event == 1, na.rm = TRUE)),
      .groups = "drop"
    )
  
  df_last_with_cum <- df_last %>%
    left_join(counts, by = "icu_stay_id")
  
  return(df_last_with_cum)
}

extract_last_time_window <- function(df, cum = FALSE) {
  df_last <- df %>%
    group_by(icu_stay_id) %>%
    slice_max(time_window_index, n=1) %>%
    ungroup()
  if (cum) df_last <- create_cumulatives(df, df_last)
  
  return(df_last)
}

get_gformula_pooled_model <- function(df, followup_length, time_window_width){
  df_last_with_cum <- extract_last_time_window(df, cum = TRUE)
  
  df_surv_g <- df_last_with_cum %>% 
    # ICUを退室した症例のみを抽出
    # = follow_up_lengthまでICUに残り続けた人と途中でICU内死亡した人を除外
    filter(icu_discharge_alive == 1) %>% 
    # 退室後モデルの作成に使用するデータの範囲をICU内でtime0から
    # follow_up_length日後までに限定するための変数を作成
    mutate(
      icu_length_of_stay = floor((time_window_index + 1) * time_window_width / 24),
      followup_after_icu_discharge = pmin(
        # 退室時~1日目までの死亡はsurvival_after_icu_discharge = 0 と記録されている
        survival_after_icu_discharge + 1, 
        pmax(followup_length - icu_length_of_stay, 0))
    ) %>%
    uncount(weights = followup_after_icu_discharge, .remove = FALSE) %>% 
    group_by(icu_stay_id) %>%
    mutate(
      time = row_number() - 1,
      event = as.integer(time == survival_after_icu_discharge)
    ) %>%
    ungroup()
  
  # 説明変数
  static_vars <- c(
    "age", "I(age^2)", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index",
    "apache2_score"
  )
  time_varying_vars <- c(
    "sofa_score", "I(sofa_score^2)",
    "bt", "hr", "rr", "mbp", "spo2",
    "lactate", "I(lactate^2)",
    "pt_inr", "I(pt_inr^2)", "platelet", "I(platelet^2)",
    "noradrenaline_equivalent_dose", "I(noradrenaline_equivalent_dose^2)",
    "mechanical_ventilation_use", "renal_replacement_therapy_use",
    "rbc_use", "ffp_use", "pc_use"
  )
  cum_vars <- c(
    "mean_ned",
    "num_heparin_use",
    "num_rbc_use",
    "num_ffp_use",
    "num_pc_use",
    "num_thrombomodulin_use",
    "num_antithrombin_use"
  )
  time_vars <- c(
    "time", "I(time^2)",
    "time_window_index", "I(time_window_index^2)",
    "time_window_index:time"
  )
  
  all_vars <- c(static_vars, time_varying_vars, cum_vars, time_vars)
  
  formula      <- as.formula(paste("event ~", paste(all_vars, collapse = " + ")))
  g_pool_model <- glm(
    formula,
    data = df_surv_g,
    family = binomial()
  )
  
  message("[get_gformula_pooled_model] g-formula pooled logistic modelを構築")
  return(g_pool_model)
}


#========================================#
# 3. g‐formula simulation                #
#    ICU内シミュレーション               #
#========================================#
history_ever_days_since <- function(pool, histvars, time_name, t, id_name) {
  if (!data.table::is.data.table(pool)) {
    stop("history_ever_days_since expects a data.table pool")
  }
  histvars <- as.character(histvars)
  if (!length(histvars)) return(invisible(NULL))

  for (histvar in histvars) {
    if (!histvar %in% names(pool)) {
      stop("history_ever_days_since: missing column ", histvar)
    }
    ever_name <- paste0("ever_", histvar)
    days_name <- paste0("days_since_first_", histvar)

    ids_t <- unique(pool[pool[[time_name]] == t][[id_name]])
    if (!length(ids_t)) next

    hist <- pool[
      pool[[time_name]] <= t & pool[[id_name]] %in% ids_t,
      c(id_name, time_name, histvar),
      with = FALSE
    ]
    data.table::setnames(hist, c(id_name, time_name, histvar), c(".id", ".tt", ".A"))
    summ <- hist[, {
      w <- which(.A > 0)
      .(.sumA = sum(.A, na.rm = TRUE),
        .first = if (length(w)) as.integer(min(.tt[w])) else NA_integer_)
    }, by = .id]
    summ[, `:=`(
      .ever = as.integer(.sumA > 0),
      .days = data.table::fifelse(
        is.na(.first),
        0L,
        as.integer(t - .first)
      )
    )]

    idx <- pool[[time_name]] == t & pool[[id_name]] %in% ids_t
    id_map <- match(pool[[id_name]][idx], summ$.id)
    pool[idx, (ever_name) := summ$.ever[id_map]]
    pool[idx, (days_name) := summ$.days[id_map]]
  }
  invisible(NULL)
}

e6_thrombomodulin_use <- paste0(
  "I(",
  paste(sprintf("lag%d_thrombomodulin_use", 1:6), collapse = " + "),
  ")"
)
ever_thrombomodulin_use <- "ever_thrombomodulin_use"
days_since_first_thrombomodulin_use <- "days_since_first_thrombomodulin_use"
ever_days_interaction <- paste0(
  ever_thrombomodulin_use, ":", days_since_first_thrombomodulin_use
)

# Control
no_tm_no_at <- function(newdf, pool, intvar, intvals, time_name, t) {
  newdf[, thrombomodulin_use := 0L]
  newdf[, antithrombin_use := 0L]
}

make_tm_6days_from_day_x_stop_if_ae <- function(start_day, time_window_width) {
  force(start_day)
  force(time_window_width)
  
  function(newdf, pool, intvar, intvals, time_name, t) {
    windows_per_day <- 24 / time_window_width
    
    start_treat_index <- (start_day - 1) * windows_per_day
    end_treat_index   <- (start_day - 1 + 6) * windows_per_day
    
    current_ids <- newdf$id
    past_pool   <- pool[id %in% current_ids & get(time_name) <= t]
    ae_by_id    <- past_pool[, .(ae_occurred = as.integer(any(adverse_event == 1, na.rm = TRUE))), by = id]
    
    newdf[, ae_occurred := ae_by_id$ae_occurred[match(id, ae_by_id$id)]]
    newdf[is.na(ae_occurred), ae_occurred := 0L]
    newdf[, antithrombin_use := 0L]
    newdf[, thrombomodulin_use := fifelse(
                    start_treat_index <= t &
                    t < end_treat_index &
                    ae_occurred == 0L,
                    1L,
                    0L
                    )]
    newdf[, ae_occurred := NULL]
  }
}

tm_intervention_functions <- lapply(
  tm_start_days,
  function(day) {
    make_tm_6days_from_day_x_stop_if_ae(
      start_day = day,
      time_window_width = time_window_width
    )
  }
)

interventions <- c(lapply(
    tm_intervention_functions,
    function(f) {list(c(f))}
  ),
  list(
    list(c(no_tm_no_at))
  )
)

int_descript <- c(
  paste0("TM_day", tm_start_days),
  "no_TM"
)

# natural course の名称（gfoRmula返却名 → 下流で使う名前）
NATURAL_COURSE_GFORMULA <- "Natural course"
NATURAL_COURSE_NAME     <- "Natural_course"
all_strategies          <- c(NATURAL_COURSE_NAME, int_descript)

GFORMULA_COVNAMES <- c(
  "bt", "hr", "rr", "mbp", "spo2", "lactate", "pt_inr", "platelet",
  "sofa_score",
  "noradrenaline_equivalent_dose", "mechanical_ventilation_use",
  "renal_replacement_therapy_use",
  "heparin_use", "rbc_use", "ffp_use", "pc_use",
  "adverse_event", "thrombomodulin_use", "antithrombin_use"
)
# sofa は定義域 [0,24] の truncnorm（subgroup の観測範囲に依存させない）
GFORMULA_CUSTOM_TRUNC_COVNAMES <- c("sofa_score")
GFORMULA_CUSTOM_TRUNC_BOUNDS <- list(
  sofa_score = c(a = 0, b = 24)
)
stopifnot(setequal(GFORMULA_CUSTOM_TRUNC_COVNAMES, names(GFORMULA_CUSTOM_TRUNC_BOUNDS)))
GFORMULA_COVTYPES <- c(
  "normal",               # bt
  "normal",               # hr
  "normal",               # rr
  "normal",               # mbp
  "normal",               # spo2 (log_comp_101)
  "normal",               # lactate (log1p)
  "normal",               # pt_inr (log)
  "normal",               # platelet (sqrt)
  "custom",               # sofa_score
  "zero-inflated normal", # noradrenaline_equivalent_dose (log1p)
  "binary",               # mechanical_ventilation_use
  "binary",               # renal_replacement_therapy_use
  "binary", "binary", "binary", "binary", # heparin, rbc, ffp, pc
  "binary", "binary", "binary"            # AE, TM, AT
)
stopifnot(length(GFORMULA_COVNAMES) == length(GFORMULA_COVTYPES))
names(GFORMULA_COVTYPES) <- GFORMULA_COVNAMES

# モデル用変換（fit/sim 後に clinical scale へ戻す）
GFORMULA_COV_TRANSFORMS <- c(
  bt = "identity",
  hr = "identity",
  rr = "identity",
  mbp = "identity",
  spo2 = "log_comp_101",
  lactate = "log1p",
  pt_inr = "log",
  platelet = "sqrt",
  sofa_score = "identity",
  noradrenaline_equivalent_dose = "log1p",
  mechanical_ventilation_use = "identity",
  renal_replacement_therapy_use = "identity",
  heparin_use = "identity",
  rbc_use = "identity",
  ffp_use = "identity",
  pc_use = "identity",
  adverse_event = "identity",
  thrombomodulin_use = "identity",
  antithrombin_use = "identity"
)
stopifnot(all(GFORMULA_COVNAMES %in% names(GFORMULA_COV_TRANSFORMS)))

# truncnorm fit（modeling scale）
fit_cov_truncnorm_2sided <- function(covparams, covname, obs_data, j) {
  fit <- stats::glm(
    stats::as.formula(paste(covparams$covmodels[j])),
    family = stats::gaussian(),
    data = obs_data,
    y = TRUE
  )
  fit$rmse <- sqrt(mean((fit$y - stats::fitted(fit))^2))
  fixed <- GFORMULA_CUSTOM_TRUNC_BOUNDS[[covname]]
  if (is.null(fixed)) {
    stop("[fit_cov_truncnorm_2sided] Missing fixed bounds for ", covname)
  }
  fit$trunc_a <- unname(fixed[["a"]])
  fit$trunc_b <- unname(fixed[["b"]])
  fit
}

# truncnorm からの予測 draw（gfoRmula custom predict 用）
predict_cov_truncnorm_2sided <- function(obs_data, newdf, fit, time_name, t,
                                         condition, covname, ...) {
  mu <- as.numeric(stats::predict(fit, newdata = newdf, type = "response"))
  a <- fit$trunc_a
  b <- fit$trunc_b
  if (is.null(a) || is.null(b) || !is.finite(a) || !is.finite(b)) {
    fixed <- GFORMULA_CUSTOM_TRUNC_BOUNDS[[covname]]
    if (is.null(fixed)) {
      stop("[predict_cov_truncnorm_2sided] Missing fixed bounds for ", covname)
    }
    a <- unname(fixed[["a"]])
    b <- unname(fixed[["b"]])
  }
  sd <- fit$rmse
  if (is.null(sd) || !is.finite(sd) || sd <= 0) {
    sd <- stats::sd(stats::residuals(fit), na.rm = TRUE)
  }
  truncnorm::rtruncnorm(n = length(mu), mean = mu, sd = sd, a = a, b = b)
}

build_gformula_custom_cov_args <- function(covnames,
                                           custom_vars = GFORMULA_CUSTOM_TRUNC_COVNAMES) {
  fits <- vector("list", length(covnames))
  preds <- vector("list", length(covnames))
  for (i in seq_along(covnames)) {
    v <- covnames[[i]]
    if (v %in% custom_vars) {
      fits[[i]] <- fit_cov_truncnorm_2sided
      preds[[i]] <- predict_cov_truncnorm_2sided
    } else {
      fits[[i]] <- NA
      preds[[i]] <- NA
    }
  }
  # restrictions=NA だと condition が未定義になるため、常に真の条件を渡す
  restrictions <- lapply(custom_vars, function(v) {
    c(v, "time_window_index >= 0", simple_restriction, 0)
  })
  list(
    covfits_custom = fits,
    covpredict_custom = preds,
    restrictions = restrictions
  )
}

transform_cov_vector <- function(x, transform, var = NULL, direction = c("forward", "inverse")) {
  direction <- match.arg(direction)
  if (identical(transform, "identity") || is.null(transform) || !nzchar(transform)) {
    return(x)
  }
  if (identical(direction, "forward")) {
    if (identical(transform, "log1p")) {
      x2 <- as.numeric(x)
      if (any(x2 < 0, na.rm = TRUE)) {
        stop(sprintf(
          "[transform_cov_vector] %s requires non-negative values for log1p; found min=%s",
          if (is.null(var)) "<unknown>" else var,
          format(min(x2, na.rm = TRUE), digits = 6)
        ))
      }
      return(log1p(x2))
    }
    if (identical(transform, "log")) {
      x2 <- as.numeric(x)
      if (any(x2 <= 0, na.rm = TRUE)) {
        stop(sprintf(
          "[transform_cov_vector] %s requires strictly positive values for log; found min=%s",
          if (is.null(var)) "<unknown>" else var,
          format(min(x2, na.rm = TRUE), digits = 6)
        ))
      }
      return(log(x2))
    }
    # spo2: log(101 - s)
    if (identical(transform, "log_comp_101")) {
      x2 <- as.numeric(x)
      x2 <- pmin(pmax(x2, 0), 100)
      return(log(101 - x2))
    }
    if (identical(transform, "sqrt")) {
      x2 <- as.numeric(x)
      if (any(x2 < 0, na.rm = TRUE)) {
        stop(sprintf(
          "[transform_cov_vector] %s requires non-negative values for sqrt; found min=%s",
          if (is.null(var)) "<unknown>" else var,
          format(min(x2, na.rm = TRUE), digits = 6)
        ))
      }
      return(sqrt(x2))
    }
    stop("Unsupported transform: ", transform)
  }
  if (identical(transform, "log1p")) {
    return(pmax(expm1(as.numeric(x)), 0))
  }
  if (identical(transform, "log")) {
    return(exp(as.numeric(x)))
  }
  if (identical(transform, "log_comp_101")) {
    spo2 <- 101 - exp(as.numeric(x))
    return(pmin(pmax(spo2, 0), 100))
  }
  if (identical(transform, "sqrt")) {
    return(pmax(as.numeric(x), 0)^2)
  }
  stop("Unsupported transform: ", transform)
}

apply_gformula_cov_transforms <- function(dt, direction = c("forward", "inverse"),
                                          transforms = GFORMULA_COV_TRANSFORMS) {
  direction <- match.arg(direction)
  if (!data.table::is.data.table(dt)) dt <- data.table::as.data.table(dt)
  for (v in names(transforms)) {
    tr <- transforms[[v]]
    if (identical(tr, "identity") || !v %in% names(dt)) next
    data.table::set(
      dt, j = v,
      value = transform_cov_vector(dt[[v]], tr, var = v, direction = direction)
    )
  }
  dt
}

intvars <- replicate(
  length(interventions),
  c("thrombomodulin_use", "antithrombin_use"),
  simplify = FALSE
)

run_gformula_simulation <- function(df_boot, interventions, n_simul_min,
                                    followup_length, time_window_width,
                                    keep_model_fits = FALSE, seed = 813L) {
  dt     <- as.data.table(df_boot)
  dt[, source_icu_stay_id := icu_stay_id]
  rm(df_boot); gc()

  n_unique <- length(unique(dt$icu_stay_id))
  n_simul  <- max(n_simul_min, n_unique)

  columns_to_use <- c(
    "icu_stay_id", "source_icu_stay_id", "time_window_index", "icu_death", "icu_discharge_alive",
    "age", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index", "apache2_score", "sofa_score", "bt", "hr", "rr", "mbp", "spo2",
    "lactate", "pt_inr", "platelet",
    "noradrenaline_equivalent_dose", "mechanical_ventilation_use", "renal_replacement_therapy_use",
    "heparin_use", "rbc_use", "ffp_use", "pc_use",
    "adverse_event", "thrombomodulin_use", "antithrombin_use"
  )
  dt <- dt[, ..columns_to_use]

  dt <- apply_gformula_cov_transforms(dt, direction = "forward")
  tr_msg <- GFORMULA_COV_TRANSFORMS[GFORMULA_COV_TRANSFORMS != "identity"]
  message(sprintf(
    "[run_gformula_simulation] cov transforms: %s",
    paste(sprintf("%s=%s", names(tr_msg), tr_msg), collapse = ", ")
  ))
  message(sprintf(
    "[run_gformula_simulation] covtypes: %s",
    paste(sprintf("%s=%s", GFORMULA_COVNAMES, GFORMULA_COVTYPES), collapse = " | ")
  ))

  basecovs <- c(
    "source_icu_stay_id", "age", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index", "apache2_score"
  )
  
  covnames_fwd <- GFORMULA_COVNAMES
  treatment_covs <- c("thrombomodulin_use", "antithrombin_use")
  l_covnames_fwd <- setdiff(covnames_fwd, treatment_covs)
  # --cov-inv: reverse L only; keep A (TM/AT) last
  covnames <- if (isTRUE(use_cov_inv)) {
    c(rev(l_covnames_fwd), treatment_covs)
  } else {
    covnames_fwd
  }
  covtypes <- unname(GFORMULA_COVTYPES[covnames])
  message(sprintf(
    "[run_gformula_simulation] cov order (%s): %s",
    cov_order_label,
    paste(covnames, collapse = " -> ")
  ))
  
  # Y model
  y_static_vars <- c(
    "age", "I(age^2)", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index",
    "apache2_score"
  )

  y_time_varying_vars <- c(
    "sofa_score", "I(sofa_score^2)",
    "bt", "hr", "rr", "mbp", "spo2",
    "lactate", "I(lactate^2)",
    "pt_inr", "I(pt_inr^2)", "platelet", "I(platelet^2)",
    "noradrenaline_equivalent_dose", "I(noradrenaline_equivalent_dose^2)",
    "mechanical_ventilation_use", "renal_replacement_therapy_use",
    "heparin_use", "rbc_use", "ffp_use", "pc_use",
    "adverse_event", "thrombomodulin_use", "antithrombin_use",
    ever_thrombomodulin_use,
    ever_days_interaction
  )
  y_time_vars <- c("time_window_index", "I(time_window_index^2)", "I(time_window_index^3)")

  y_all_vars <- c(y_static_vars, y_time_varying_vars, y_time_vars)
  y_formula  <- as.formula(paste("icu_death ~", paste(y_all_vars, collapse = " + ")))

  # L / A models
  l_static_vars <- c(
    "age", "I(age^2)", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index",
    "apache2_score"
  )

  l_cov_lagged_vars <- c(
    "lag1_bt",
    "lag1_hr",
    "lag1_rr",
    "lag1_mbp",
    "lag1_spo2",
    "lag1_lactate", "I(lag1_lactate^2)",
    "lag1_pt_inr", "I(lag1_pt_inr^2)",
    "lag1_platelet", "I(lag1_platelet^2)",
    "lag1_sofa_score", "I(lag1_sofa_score^2)",
    "lag1_noradrenaline_equivalent_dose", "I(lag1_noradrenaline_equivalent_dose^2)",
    "lag1_mechanical_ventilation_use",
    "lag1_renal_replacement_therapy_use",
    "lag1_heparin_use", "lag1_rbc_use", "lag1_ffp_use", "lag1_pc_use",
    "lag1_adverse_event",
    "lag1_antithrombin_use"
  )
  l_time_vars <- c("time_window_index", "I(time_window_index^2)")
  l_base_vars <- c(l_static_vars, l_cov_lagged_vars, l_time_vars)

  # L の rTM: lag1、凝固系/SOFA は E6（+線形交互作用）
  l_other_rtm <- "lag1_thrombomodulin_use"
  l_e6_coag_platelet <- c(
    e6_thrombomodulin_use,
    paste0(e6_thrombomodulin_use, ":lag1_platelet")
  )
  l_e6_coag_pt_inr <- c(
    e6_thrombomodulin_use,
    paste0(e6_thrombomodulin_use, ":lag1_pt_inr")
  )
  l_e6_sofa <- e6_thrombomodulin_use

  a_static_vars       <- l_static_vars
  a_time_varying_vars <- c(
    "sofa_score", "I(sofa_score^2)",
    "bt", "hr", "rr", "mbp", "spo2",
    "lactate", "I(lactate^2)",
    "pt_inr", "I(pt_inr^2)", "platelet", "I(platelet^2)",
    "noradrenaline_equivalent_dose", "I(noradrenaline_equivalent_dose^2)",
    "mechanical_ventilation_use", "renal_replacement_therapy_use",
    "heparin_use", "rbc_use", "ffp_use", "pc_use",
    "adverse_event"
  )
  a_hist_vars <- c(
    "lag1_thrombomodulin_use", "lag2_thrombomodulin_use",
    "lag1_antithrombin_use", "lag2_antithrombin_use"
  )
  a_time_vars <- l_time_vars
  a_all_vars  <- c(a_static_vars, a_time_varying_vars, a_hist_vars, a_time_vars)

  l_other <- c(l_base_vars, l_other_rtm)

  # Contemporaneous predictors follow simulation order (fwd or inv).
  build_cov_formula_vars <- function(ord) {
    out <- list()
    seen <- character(0)
    for (v in ord) {
      if (v %in% treatment_covs) {
        out[[v]] <- a_all_vars
      } else if (identical(v, "pt_inr")) {
        out[[v]] <- c(l_base_vars, l_e6_coag_pt_inr, seen)
      } else if (identical(v, "platelet")) {
        out[[v]] <- c(l_base_vars, l_e6_coag_platelet, seen)
      } else if (identical(v, "sofa_score")) {
        out[[v]] <- c(l_base_vars, l_e6_sofa, seen)
      } else {
        out[[v]] <- c(l_other, seen)
      }
      seen <- c(seen, v)
    }
    out
  }
  cov_formula_vars <- build_cov_formula_vars(covnames)

  cov_formulas <- lapply(names(cov_formula_vars), function(var){
    rhs <- paste(cov_formula_vars[[var]], collapse = " + ")
    as.formula(paste(var, "~", rhs))
  })
  names(cov_formulas) <- names(cov_formula_vars)

  covmodels_ordered <- lapply(covnames, function(v) cov_formulas[[v]])
  custom_args <- build_gformula_custom_cov_args(covnames)

  res <- gformula(
    seed          = seed,
    obs_data      = dt,
    id            = "icu_stay_id",
    time_name     = "time_window_index",
    time_points   = followup_length*(24/time_window_width),
    outcome_name  = "icu_death",
    outcome_type  = "survival",
    ymodel        = y_formula,
    basecovs      = basecovs,
    covnames      = covnames,
    covtypes      = covtypes,
    histories = c(lagged, history_ever_days_since),
    histvars  = list(
      covnames,
      c("thrombomodulin_use")
    ),
    covparams     = list(covmodels = covmodels_ordered),
    covfits_custom = custom_args$covfits_custom,
    covpredict_custom = custom_args$covpredict_custom,
    restrictions = custom_args$restrictions,
    intvars       = intvars,
    interventions = interventions,
    int_descript  = int_descript,
    ref_int       = 1,
    nsamples      = 0,
    nsimul        = n_simul,
    model_fits    = keep_model_fits,
    sim_data_b    = TRUE,
    parallel      = FALSE,
    threads       = 1,
    # 連続共変量は観測 min/max で clip（sofa は custom truncnorm）
    sim_trunc     = TRUE
  )
  message("[run_gformula_simulation] g-formula 実行完了")
  
  columns_to_keep <- c(columns_to_use, c("Py", "id"))
  columns_to_keep <- setdiff(columns_to_keep, c("icu_stay_id", "icu_death", "icu_discharge_alive"))
  
  process_sim_dt <- function(x_dt) {
    x_dt <- x_dt[, ..columns_to_keep]
    x_dt <- apply_gformula_cov_transforms(x_dt, direction = "inverse")
    
    x_dt[, sim_icu_stay_id := id]
    x_dt[, icu_stay_id := sim_icu_stay_id]
    x_dt[, id := NULL]
    
    return(x_dt[])
  }
  
  sim_names   <- names(res$sim_data)
  sims_merged <- lapply(res$sim_data, process_sim_dt)
  names(sims_merged) <- ifelse(
    sim_names == NATURAL_COURSE_GFORMULA,
    NATURAL_COURSE_NAME,
    sim_names
  )
  
  return(list(
    sims = sims_merged,
    model_fits = if (keep_model_fits) res else NULL
  ))
}

get_discharge_model <- function(df) {
  c_static_vars <- c(
    "age", "I(age^2)", "female", "icu_admission_year", "hospital_id_model",
    "respiratory_infection", "abdominal_infection", "urinary_infection",
    "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
    "charlson_comorbidity_index",
    "apache2_score"
  )
  c_time_varying_vars <- c(
    "sofa_score", "I(sofa_score^2)",
    "bt", "hr", "rr", "mbp", "spo2",
    "lactate", "I(lactate^2)",
    "pt_inr", "I(pt_inr^2)", "platelet", "I(platelet^2)",
    "noradrenaline_equivalent_dose", "I(noradrenaline_equivalent_dose^2)",
    "mechanical_ventilation_use", "renal_replacement_therapy_use",
    "heparin_use", "rbc_use", "ffp_use", "pc_use",
    "thrombomodulin_use", "antithrombin_use",
    "adverse_event"
  )
  c_time_vars <- c("time_window_index", "I(time_window_index^2)", "I(time_window_index^3)")
  
  c_all_vars <- c(c_static_vars, c_time_varying_vars, c_time_vars)
  discharge_formula <- as.formula(paste("icu_discharge_alive ~", paste(c_all_vars, collapse = " + ")))
  
  # 同一time windowで死亡していない症例に条件づけ（P(discharge | not death in window)）
  df_at_risk <- df %>% filter(icu_death == 0)
  
  discharge_model <- glm(
    formula = discharge_formula,
    data = df_at_risk,
    family = binomial()
  )
  
  return(discharge_model)
}

process_first_simulation <- function(g_results, discharge_model) {
  sim_icu_death_and_icu_discharge <- list()
  sim_icu_death_only              <- list() # ICU内simulationだけのsurvival curveを得るための処理
  
  for (nm in names(g_results$sims)) {
    dt_sim <- g_results$sims[[nm]] %>% 
      as_tibble() %>% # data.table → data.frame
      mutate(
        icu_discharge_alive_prob = predict(
          discharge_model,
          newdata = .,
          type    = "response"
        ),
        icu_discharge_alive = rbinom(nrow(.), 1, icu_discharge_alive_prob),
        icu_death           = rbinom(nrow(.), 1, Py)
      ) %>% 
      select(-starts_with("lag")) # simulation結果として帰ってくるこれ以降不要な列を削除
    
    # icu_discharge_alive, icu_death以降の行を削除
    dt_sim_icu_death_and_icu_discharge <- dt_sim %>% 
      group_by(icu_stay_id) %>% 
      arrange(time_window_index, .by_group = TRUE) %>% 
      mutate(event_flag = (icu_discharge_alive == 1 | icu_death == 1)) %>%
      slice(
        # 最初に event_flag が TRUE になる行までを取得
        seq_len(if (any(event_flag)) which(event_flag)[1] else n())
      ) %>%
      mutate(
        # 最初のイベント行で両方 TRUE の場合 icu_discharge_alive を 0 に変える
        icu_discharge_alive = if_else(row_number() == replace_na(which(event_flag)[1], -1) & icu_death == 1, 0, icu_discharge_alive)
      ) %>%
      ungroup() %>% 
      select(-event_flag) 
    
    # icu_death以降の行を削除
    dt_sim_icu_death_only <- dt_sim %>%
      group_by(icu_stay_id) %>% 
      arrange(time_window_index, .by_group = TRUE) %>% 
      mutate(event_flag = (icu_death == 1)) %>%
      slice(
        # 最初に event_flag が TRUE になる行までを取得
        seq_len(if (any(event_flag)) which(event_flag)[1] else n())
      ) %>%
      ungroup() %>% 
      select(-event_flag)
    
    rm(dt_sim); gc()
    
    # secondary endpoint解析に必要な累積変数を残して最後のtime windowだけ取り出す
    dt_sim_icu_death_and_icu_discharge <- extract_last_time_window(dt_sim_icu_death_and_icu_discharge, cum = TRUE)
    dt_sim_icu_death_only              <- extract_last_time_window(dt_sim_icu_death_only, cum = TRUE)
    
    sim_icu_death_and_icu_discharge[[nm]] <- dt_sim_icu_death_and_icu_discharge
    sim_icu_death_only[[nm]]              <- dt_sim_icu_death_only 
  }
  
  message("[process_first_simulation] ICU内simulationを実行")
  return(list(
    sim_icu_death_and_icu_discharge = sim_icu_death_and_icu_discharge,
    sim_icu_death_only              = sim_icu_death_only
  ))
}


#======================================================#
# 4. g‐formula survival prediction with simulated data #
#    ICU退室後シミュレーション                         #
#======================================================#
build_second_stage_individuals <- function(sims1, g_pool_model, followup_length){
  
  process_second_simulation <- function(sim_data, g_pool_model, followup_length){
    surv_results <- sim_data %>%  
      # ICUを退室した症例のみを抽出
      # = 最後のtime windowでもICUに残り続けた人、ICU内死亡した人を除外
      filter(icu_discharge_alive == 1) %>% 
      # 実際に生存関数の描画に使うのはfollowup_length - icu_length_of_stay分だけだが
      # 多くestimateする分には結果に影響しないので一律followup_length分展開する
      uncount(weights = followup_length, .remove = F) %>% 
      group_by(icu_stay_id) %>%
      mutate(time = row_number() - 1) %>%
      ungroup()
    
    # g_pool_modelの予測値をbernoulli分布に基づいてhazardを0,1に変換（simulation）
    surv_results[["hazard"]] <- predict(g_pool_model, newdata = surv_results, type = "response")
    surv_results[["death_after_discharge"]] <- rbinom(nrow(surv_results), 1, surv_results[["hazard"]])
    
    # 必要最小限の列への圧縮
    out <- surv_results %>%
      mutate(time_updated = time + 1) %>% 
      select(icu_stay_id, time_window_index, time_updated, 
             hazard, death_after_discharge, count_mv, 
             count_vasopressor, adverse_event_ever) %>%
      arrange(icu_stay_id, time_window_index)
    
    return(out)
  }
  
  out_list <- lapply(
    sims1,
    process_second_simulation,
    g_pool_model = g_pool_model,
    followup_length = followup_length
  )
  
  return(out_list) 
}


#======================================================#
# 5. summarize simulation results                      #
#    生存曲線/secondary endpointの計算                 #
#======================================================#
# 5-0. 共通関数
calc_survival <- function(df, time_points) {
  sapply(time_points, function(t) {
    1 - mean(df$time_since_baseline <= t, na.rm = TRUE)
  })
}

convert_to_surv_data <- function(sim_results, followup_length, time_window_width) {
  time_points <- seq(0, followup_length, by = time_window_width / 24)
  
  surv_list <- lapply(sim_results, function(df) {
    calc_survival(df, time_points)
  })
  
  result <- tibble(time_points = time_points)
  
  for (nm in names(surv_list)) {
    result[[nm]] <- surv_list[[nm]]
  }
  return(result)
}

# 5-1. ICU内シミュレーションのみの結果（生存曲線）を得るための処理（combinedには不要）
get_first_stage_surv_data <- function(sim_icu_death_only, time_window_width) {
  out_list <- list()
  
  for (nm in names(sim_icu_death_only)) {
    # ICU内で死亡した症例
    sim_1_death <- sim_icu_death_only[[nm]] %>% 
      filter(icu_death == 1) %>% 
      mutate(time_since_baseline = (time_window_index + 1) * time_window_width / 24) %>% 
      select(icu_stay_id, time_since_baseline)
    
    # ICU内で生存したままだった症例
    sim_1_survive <- sim_icu_death_only[[nm]] %>% 
      filter(icu_death == 0) %>% 
      mutate(time_since_baseline = 100 * 365) %>% # 解析に影響しない十分長い時間（100年）を代入
      select(icu_stay_id, time_since_baseline)
    
    # sim_1_death, sim_1_surviveを縦方向に結合
    sim_all <- bind_rows(sim_1_death, sim_1_survive)
    if (!all(unique(sim_all$icu_stay_id) %in% unique(sim_icu_death_only[[nm]]$icu_stay_id))) {
      stop(sprintf("Error: icu_stay_id mismatch in %s", nm))
    }
    
    out_list[[nm]] <- sim_all
  }
  
  return(out_list)
}

# 5-2. ICU退室後シミュレーションのみの結果（生存曲線）を得るための処理
get_second_stage_surv_data <- function(sim_list_2){
  
  calculate_second_stage_surv_func <- function(sim_data, group_name) {
    sim_data %>% 
      arrange(icu_stay_id, time_updated) %>%
      group_by(icu_stay_id) %>% 
      mutate(surv_indv = cumprod(1 - hazard)) %>% 
      ungroup() %>% 
      group_by(time_updated) %>%
      summarise(survival = mean(surv_indv), .groups = "drop") %>%
      mutate(group = group_name)
  }
  
  surv_list <- lapply(names(sim_list_2), function(nm) {
    calculate_second_stage_surv_func(sim_list_2[[nm]], nm)
  })
  
  g_surv_long <- bind_rows(surv_list)
  
  baseline_row <- tibble(
    time_updated = 0,
    survival = 1,
    group = names(sim_list_2)
  )
  
  g_surv_long <- bind_rows(baseline_row, g_surv_long) %>%
    arrange(group, time_updated)
  
  g_surv_data <- g_surv_long %>%
    tidyr::pivot_wider(
      names_from = group,
      values_from = survival
    ) %>%
    arrange(time_updated)
  
  return(g_surv_data)
}

# 5-3. ICU内・退室後シミュレーションを組み合わせた結果（生存曲線）を得るための処理
combine_simulation_results <- function(sim_list_1, sim_list_2, time_window_width, followup_length) {
  out_list <- list()
  
  for (nm in names(sim_list_2)) {
    # ICU内で死亡した症例
    sim_1_death <- sim_list_1[[nm]] %>% 
      filter(icu_death == 1) %>% 
      mutate(time_since_baseline = (time_window_index + 1) * time_window_width / 24,
             icu_free_days = 0,
             mv_free_days  = 0,
             vasopressor_free_days = 0) %>% 
      select(icu_stay_id, time_since_baseline, 
             icu_free_days, mv_free_days, vasopressor_free_days, adverse_event_ever)
    
    # ICU内で生存したまま退室もしなかった症例
    sim_1_survive <- sim_list_1[[nm]] %>% 
      filter(icu_death == 0 & icu_discharge_alive == 0) %>% 
      mutate(time_since_baseline = 100 * 365, # 解析に影響しない十分長い時間（100年）を代入
             icu_free_days = 0,
             mv_free_days  = icu_free_days + ((time_window_index + 1) - count_mv) * time_window_width / 24,
             vasopressor_free_days = 
                icu_free_days + ((time_window_index + 1) - count_vasopressor) * time_window_width / 24) %>% 
      select(icu_stay_id, time_since_baseline, 
             icu_free_days, mv_free_days, vasopressor_free_days, adverse_event_ever)
    
    # ICUを退室した症例
    sim_2 <- sim_list_2[[nm]] %>% 
      group_by(icu_stay_id) %>% 
      arrange(time_updated, .by_group = TRUE) %>% 
      slice(
        seq_len(
          if (any(death_after_discharge == 1)) 
            which(death_after_discharge == 1)[1] 
          else n())
      ) %>%
      filter(time_updated == max(time_updated)) %>% 
      ungroup() %>% 
      mutate(
        # death_after_discharge = 1なら ICU在室時間 + 退院後時間, 
        # death_after_discharge = 0なら解析に影響しない十分長い時間（100年）を代入
        time_since_baseline = if_else(
          death_after_discharge == 1, 
          (time_window_index + 1) * time_window_width / 24 + time_updated, 
          100 * 365 # 解析に影響しない十分長い時間（100年）を代入
        ),
        icu_free_days           = if_else(
          time_since_baseline <= followup_length, 
          0,  # followup期間内に死亡した場合は0日
          pmax(followup_length - (time_window_index + 1) * time_window_width / 24, 0)  # followup期間 - ICU滞在期間
        ),
        mv_free_days            = if_else(
          time_since_baseline <= followup_length, 
          0,  # followup期間内に死亡した場合は0日
          pmax(icu_free_days + ((time_window_index + 1) - count_mv) * time_window_width / 24, 0)
        ),
        vasopressor_free_days   = if_else(
          time_since_baseline <= followup_length, 
          0,  # followup期間内に死亡した場合は0日
          pmax(icu_free_days + ((time_window_index + 1) - count_vasopressor) * time_window_width / 24, 0)
        )
      ) %>%
      select(icu_stay_id, time_since_baseline, 
             icu_free_days, mv_free_days, vasopressor_free_days, adverse_event_ever)
    
    # sim_1_death, sim_1_survive, sim_2を縦方向に結合
    sim_all <- bind_rows(sim_1_death, sim_1_survive, sim_2)
    if (!all(unique(sim_all$icu_stay_id) %in% unique(sim_list_1[[nm]]$icu_stay_id))) {
      stop(sprintf("Error: icu_stay_id mismatch in %s", nm))
    }
    
    out_list[[nm]] <- sim_all
  }
  
  return(out_list)
}

# 5-4. secondary endpointの集計
summarize_secondary_endpoints <- function(sim_results) {
  summary_df <- purrr::imap_dfr(sim_results, function(dat, nm) {
    tibble::tibble(
      strategy = nm,
      icu_free_days = mean(dat$icu_free_days, na.rm = TRUE),
      mv_free_days  = mean(dat$mv_free_days, na.rm = TRUE),
      vasopressor_free_days = mean(dat$vasopressor_free_days, na.rm = TRUE),
      adverse_event_prop    = mean(dat$adverse_event_ever == 1, na.rm = TRUE)
    )
  }) 
  return(summary_df)
}


#==================#
# 6. bootstrap     #
#==================#
run_one_iter_for_one_sg <- function(df_filtered, sg_ids, i,
                                    interventions, followup_length, 
                                    time_window_width, n_simul_min,
                                    use_bootstrap = TRUE){
  # worker内での処理を1スレッドに制限
  try({
    RhpcBLASctl::blas_set_num_threads(1)
    RhpcBLASctl::omp_set_num_threads(1)
    data.table::setDTthreads(1)
  }, silent = TRUE)
  
  # 1. bootstrap集団を作成し、single imputationを実行
  #    --single 時は元データそのものに single imputation のみ
  if (isTRUE(use_bootstrap)) {
    df_boot <- bootstrap_by_icu(df_filtered)
  } else {
    df_boot <- df_filtered
  }
  df_boot      <- single_imputation(df_boot)
  
  # 2. ICU退室後死亡のpooled logistic modelを作成
  g_pool_model <- get_gformula_pooled_model(df_boot, followup_length, time_window_width)
  
  # 3. ICU内シミュレーション
  g_results       <- run_gformula_simulation(
    df_boot, interventions, n_simul_min,
    followup_length, time_window_width,
    seed = 813L + as.integer(i)
  )
  discharge_model <- get_discharge_model(df_boot)
  sims1           <- process_first_simulation(g_results, discharge_model)
  
  # 4. ICU退室後シミュレーション
  sims2           <- build_second_stage_individuals(sims1$sim_icu_death_and_icu_discharge, 
                                                    g_pool_model, followup_length)
  
  # 5. 生存曲線/secondary endpointの計算
  # 5-1. ICU内シミュレーションのみの結果（生存曲線）を得るための処理（combinedには不要）
  first_sg   <- get_first_stage_surv_data(sims1$sim_icu_death_only, time_window_width)
  surv_first <- convert_to_surv_data(
    sim_results       = first_sg, 
    followup_length   = followup_length, 
    time_window_width = time_window_width)
  
  # 5-2. ICU退室後シミュレーションのみの結果（生存曲線）を得るための処理（combinedには不要）
  surv_second <- get_second_stage_surv_data(sims2) %>% rename(time_points = time_updated)
  
  # 5-3. ICU内・退室後シミュレーションを組み合わせた結果（生存曲線）を得るための処理
  sim_comb <- combine_simulation_results(
    sim_list_1        = sims1$sim_icu_death_and_icu_discharge,
    sim_list_2        = sims2,
    time_window_width = time_window_width,
    followup_length   = followup_length
  )
  surv_comb    <- convert_to_surv_data(
    sim_results       = sim_comb, 
    followup_length   = followup_length, 
    time_window_width = time_window_width)
  
  # 5-4. secondary endpointの計算
  secondary_endpoints <- summarize_secondary_endpoints(sim_comb)
  
  # 中間オブジェクトの掃除（ピークメモリ削減）
  rm(g_pool_model, g_results, sims1, sims2); gc()
  
  list(
    first = surv_first,
    second = surv_second,
    combined = surv_comb,
    secondary_endpoints = secondary_endpoints
  )
}

format_point_estimate_survival <- function(
    surv_df,
    strategies,
    control_strategy = "no_TM",
    exclude_from_contrast = NATURAL_COURSE_NAME
) {
  # 1回のpoint estimateを、bootstrap CI結果と同じ *_surv_mean 列名に揃える
  out <- surv_df %>%
    select(time_points, all_of(strategies)) %>%
    mutate(across(all_of(strategies), as.numeric))

  for (strategy in strategies) {
    out[[paste0(strategy, "_surv_mean")]] <- out[[strategy]]
    out[[paste0(strategy, "_risk_mean")]] <- 1 - out[[strategy]]
    out[[paste0("ll_surv_", strategy)]] <- NA_real_
    out[[paste0("ul_surv_", strategy)]] <- NA_real_
    out[[paste0("ll_risk_", strategy)]] <- NA_real_
    out[[paste0("ul_risk_", strategy)]] <- NA_real_
  }

  intervention_strategies <- setdiff(strategies, c(control_strategy, exclude_from_contrast))
  for (strategy in intervention_strategies) {
    out[[paste0(strategy, "_risk_diff_mean")]] <-
      (1 - out[[strategy]]) - (1 - out[[control_strategy]])
    out[[paste0(strategy, "_risk_ratio_mean")]] <-
      (1 - out[[strategy]]) / (1 - out[[control_strategy]])
    out[[paste0("ll_risk_diff_", strategy)]] <- NA_real_
    out[[paste0("ul_risk_diff_", strategy)]] <- NA_real_
    out[[paste0("ll_risk_ratio_", strategy)]] <- NA_real_
    out[[paste0("ul_risk_ratio_", strategy)]] <- NA_real_
  }

  out %>% select(-all_of(strategies))
}

calculate_confidence_intervals_survival <- function(
    surv_df,
    strategies,
    control_strategy = "no_TM",
    exclude_from_contrast = NATURAL_COURSE_NAME
) {
  z <- qnorm(0.975)
  
  strategy_cols <- strategies
  
  surv_summary <- surv_df %>%
    group_by(time_points) %>%
    summarise(
      across(
        all_of(strategy_cols),
        list(
          surv_mean = ~ mean(.x, na.rm = TRUE),
          surv_sd   = ~ sd(.x, na.rm = TRUE),
          risk_mean = ~ mean(1 - .x, na.rm = TRUE),
          risk_sd   = ~ sd(1 - .x, na.rm = TRUE)
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
  
  for (strategy in strategy_cols) {
    surv_mean_col <- paste0(strategy, "_surv_mean")
    surv_sd_col   <- paste0(strategy, "_surv_sd")
    risk_mean_col <- paste0(strategy, "_risk_mean")
    risk_sd_col   <- paste0(strategy, "_risk_sd")
    
    surv_summary[[paste0("ul_surv_", strategy)]] <- surv_summary[[surv_mean_col]] + z * surv_summary[[surv_sd_col]]
    surv_summary[[paste0("ll_surv_", strategy)]] <- surv_summary[[surv_mean_col]] - z * surv_summary[[surv_sd_col]]
    surv_summary[[paste0("ul_risk_", strategy)]] <- surv_summary[[risk_mean_col]] + z * surv_summary[[risk_sd_col]]
    surv_summary[[paste0("ll_risk_", strategy)]] <- surv_summary[[risk_mean_col]] - z * surv_summary[[risk_sd_col]]
  }
  
  intervention_strategies <- setdiff(strategy_cols, c(control_strategy, exclude_from_contrast))
  
  contrast_summary <- surv_df %>%
    group_by(time_points) %>%
    summarise(
      across(
        all_of(intervention_strategies),
        list(
          risk_diff_mean = ~ mean((1 - .x) - (1 - .data[[control_strategy]]), na.rm = TRUE),
          risk_diff_sd   = ~ sd((1 - .x) - (1 - .data[[control_strategy]]), na.rm = TRUE),
          risk_ratio_mean = ~ {
            rr <- (1 - .x) / (1 - .data[[control_strategy]])
            rr <- rr[is.finite(rr) & rr > 0]
            if (length(rr) == 0L) NA_real_ else exp(mean(log(rr)))
          },
          risk_ratio_log_sd = ~ {
            rr <- (1 - .x) / (1 - .data[[control_strategy]])
            rr <- rr[is.finite(rr) & rr > 0]
            if (length(rr) < 2L) NA_real_ else sd(log(rr))
          }
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
  
  out <- left_join(surv_summary, contrast_summary, by = "time_points")
  
  for (strategy in intervention_strategies) {
    rd_mean_col <- paste0(strategy, "_risk_diff_mean")
    rd_sd_col   <- paste0(strategy, "_risk_diff_sd")
    rr_mean_col <- paste0(strategy, "_risk_ratio_mean")
    rr_log_sd_col <- paste0(strategy, "_risk_ratio_log_sd")
    
    out[[paste0("ul_risk_diff_", strategy)]] <- out[[rd_mean_col]] + z * out[[rd_sd_col]]
    out[[paste0("ll_risk_diff_", strategy)]] <- out[[rd_mean_col]] - z * out[[rd_sd_col]]
    out[[paste0("ul_risk_ratio_", strategy)]] <-
      exp(log(out[[rr_mean_col]]) + z * out[[rr_log_sd_col]])
    out[[paste0("ll_risk_ratio_", strategy)]] <-
      exp(log(out[[rr_mean_col]]) - z * out[[rr_log_sd_col]])
  }
  
  return(out)
}

calculate_confidence_intervals_secondary_endpoints <- function(
    sec_df,
    control_strategy = "no_TM",
    exclude_from_contrast = NATURAL_COURSE_NAME
) {
  z <- qnorm(0.975)
  
  endpoint_cols <- c(
    "icu_free_days",
    "mv_free_days",
    "vasopressor_free_days",
    "adverse_event_prop"
  )
  
  sec_summary <- sec_df %>%
    group_by(strategy) %>%
    summarise(
      across(
        all_of(endpoint_cols),
        list(
          mean = ~ mean(.x, na.rm = TRUE),
          sd   = ~ sd(.x, na.rm = TRUE)
        ),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
  
  for (endpoint in endpoint_cols) {
    mean_col <- paste0(endpoint, "_mean")
    sd_col   <- paste0(endpoint, "_sd")
    
    sec_summary[[paste0("ul_", endpoint)]] <- sec_summary[[mean_col]] + z * sec_summary[[sd_col]]
    sec_summary[[paste0("ll_", endpoint)]] <- sec_summary[[mean_col]] - z * sec_summary[[sd_col]]
  }
  
  sec_wide <- sec_df %>%
    select(boot_iter, strategy, all_of(endpoint_cols)) %>%
    pivot_wider(
      names_from = strategy,
      values_from = all_of(endpoint_cols)
    )
  
  intervention_strategies <- setdiff(
    unique(sec_df$strategy),
    c(control_strategy, exclude_from_contrast)
  )
  
  diff_summary <- purrr::map_dfr(intervention_strategies, function(strategy_name) {
    purrr::map_dfr(endpoint_cols, function(endpoint) {
      strategy_col <- paste0(endpoint, "_", strategy_name)
      control_col  <- paste0(endpoint, "_", control_strategy)
      
      diffs <- sec_wide[[strategy_col]] - sec_wide[[control_col]]
      
      tibble(
        strategy = strategy_name,
        endpoint = endpoint,
        diff_mean = mean(diffs, na.rm = TRUE),
        diff_sd = sd(diffs, na.rm = TRUE),
        ll_diff = mean(diffs, na.rm = TRUE) - z * sd(diffs, na.rm = TRUE),
        ul_diff = mean(diffs, na.rm = TRUE) + z * sd(diffs, na.rm = TRUE)
      )
    })
  })
  
  return(
    list(
      summary_by_strategy = sec_summary,
      diff_vs_control = diff_summary
    )
  )
}

get_gformula_ci_single_sg <- function(
    df_filtered, interventions, int_descript,
    followup_length, time_window_width, n_simul_min,
    n_iter, size,
    total_ram, max_workers, ram_use_frac, expand_factor
) {
  
  # 指定された症例数にランダムサンプリング
  # 実験用に使うだけで、本解析ではsize = NULLとする
  if (!is.null(size)) {
    sampled_ids <- df_filtered %>%
      distinct(icu_stay_id) %>%
      slice_sample(n = size, replace = FALSE) %>%
      pull(icu_stay_id)
    df_filtered <- df_filtered %>%
      filter(icu_stay_id %in% sampled_ids)
  }
  
  # 最適なworker数を決定
  bytes_per_row <- estimate_bytes_per_row(df_filtered)
  ids           <- df_filtered %>%                                    
    distinct(icu_stay_id) %>%                               
    pull(icu_stay_id)                                       
  n_rows_sg     <- nrow(df_filtered)
  n_workers     <- workers_for_sg(
    n_rows_sg     = n_rows_sg, 
    bytes_per_row = bytes_per_row, 
    n_iter        = n_iter, 
    total_ram     = total_ram, 
    max_workers   = max_workers, 
    ram_use_frac  = ram_use_frac, 
    expand_factor = expand_factor
  )
  future::plan(future::multisession, workers = n_workers) 
  message(sprintf(                                          
    "[scheduler] sg=%s, ids=%d, rows≈%d, data≈%.3f GB -> workers=%d",
    chosen_sg, length(ids), n_rows_sg, (bytes_per_row * n_rows_sg) / 1024^3, n_workers
  ))
  
  # bootstrap処理を並列実行
  pieces <- with_progress({
    p <- progressor(steps = n_iter)
    future_lapply(seq_len(n_iter), function(i) {
      p(sprintf("sg=%s iter=%d/%d", chosen_sg, i, n_iter))
      out <- tryCatch(
        {
          run_one_iter_for_one_sg(
            df_filtered = df_filtered, 
            sg_ids = ids, 
            i = i,
            interventions = interventions, 
            followup_length = followup_length,
            time_window_width = time_window_width,
            n_simul_min = n_simul_min
          )
        },
        error = function(e) {
          message(sprintf("[bootstrap] sg=%s iter=%d FAILED: %s",
                          chosen_sg, i, e$message))
          return(NULL)
        }
      )
      return(out)
    }, 
    future.seed = TRUE
    )
  })
  
  pieces_valid <- Filter(Negate(is.null), pieces)
  n_success    <- length(pieces_valid)
  if (n_success == 0L) {
    stop("[get_gformula_ci_single_sg] All bootstrap iterations failed (n_success = 0).")
  }
  message(sprintf("[get_gformula_ci_single_sg] Successful iterations: %d / %d",
                  n_success, n_iter))
  
  # 結果を集計
  surv_results_1    <- bind_rows(lapply(pieces_valid, `[[`, "first"))
  surv_results_2    <- bind_rows(lapply(pieces_valid, `[[`, "second"))
  surv_results_c    <- bind_rows(lapply(pieces_valid, `[[`, "combined"))
  surv_results_se   <- bind_rows(
      lapply(seq_along(pieces_valid), function(i) {
        pieces_valid[[i]][["secondary_endpoints"]] %>%
          mutate(boot_iter = i)
      })
    )
  rm(pieces, pieces_valid); gc()
  
  g_surv_data_1     <- calculate_confidence_intervals_survival(
                            surv_df = surv_results_1,
                            strategies = all_strategies,
                            control_strategy = "no_TM")
  g_surv_data_2     <- calculate_confidence_intervals_survival(
                            surv_df = surv_results_2,
                            strategies = all_strategies,
                            control_strategy = "no_TM")
  g_surv_data_c     <- calculate_confidence_intervals_survival(
                            surv_df = surv_results_c,
                            strategies = all_strategies,
                            control_strategy = "no_TM")
  g_surv_data_se    <- calculate_confidence_intervals_secondary_endpoints(surv_results_se)
  
  results           <- list()
  results[[paste0("first_", chosen_sg)]]               <- tibble(g_surv_data_1)
  results[[paste0("second_", chosen_sg)]]              <- tibble(g_surv_data_2)
  results[[paste0("combined_", chosen_sg)]]            <- tibble(g_surv_data_c)
  results[[paste0("secondary_endpoints_", chosen_sg)]] <- g_surv_data_se$summary_by_strategy
  results[[paste0("secondary_endpoint_diffs_", chosen_sg)]] <- g_surv_data_se$diff_vs_control
  results[["n_success"]]                               <- n_success   
  
  # 結果をRDataで保存
  rdata_file <- file.path(
    output_dir,
    paste0(gformula_rdata_stem("ci", date, time_window_width, cov_order_label, chosen_sg), ".RData")
  )
  save(
    list     = c("results", "followup_length",
                 "time_window_width", "n_iter", "n_success", "size", "chosen_sg",
                 "int_descript", "all_strategies", "NATURAL_COURSE_NAME",
                 "GFORMULA_COVNAMES", "GFORMULA_COVTYPES", "GFORMULA_COV_TRANSFORMS",
                 "cov_order_label", "use_cov_inv"),
    file     = rdata_file
  )
  message("[get_gformula_ci_single_sg] Results saved for subgroup: ",
          chosen_sg, " -> ", rdata_file)
  
  return(results)
}

get_gformula_point_estimate_single_sg <- function(
    df_filtered, interventions, int_descript,
    followup_length, time_window_width,
    n_simul_min, size = NULL
) {
  if (!is.null(size)) {
    sampled_ids <- df_filtered %>%
      distinct(icu_stay_id) %>%
      slice_sample(n = size, replace = FALSE) %>%
      pull(icu_stay_id)
    df_filtered <- df_filtered %>%
      filter(icu_stay_id %in% sampled_ids)
  }

  message(sprintf(
    "[get_gformula_point_estimate_single_sg] sg=%s | cov=%s | single run (no bootstrap)",
    chosen_sg, cov_order_label
  ))

  piece <- run_one_iter_for_one_sg(
    df_filtered = df_filtered,
    sg_ids = df_filtered %>% distinct(icu_stay_id) %>% pull(icu_stay_id),
    i = 1L,
    interventions = interventions,
    followup_length = followup_length,
    time_window_width = time_window_width,
    n_simul_min = n_simul_min,
    use_bootstrap = FALSE
  )

  g_surv_data_1 <- format_point_estimate_survival(piece$first, all_strategies)
  g_surv_data_2 <- format_point_estimate_survival(piece$second, all_strategies)
  g_surv_data_c <- format_point_estimate_survival(piece$combined, all_strategies)

  results <- list()
  results[[paste0("first_", chosen_sg)]] <- tibble(g_surv_data_1)
  results[[paste0("second_", chosen_sg)]] <- tibble(g_surv_data_2)
  results[[paste0("combined_", chosen_sg)]] <- tibble(g_surv_data_c)
  results[[paste0("secondary_endpoints_", chosen_sg)]] <- piece$secondary_endpoints
  results[["n_success"]] <- 1L
  results[["estimation_mode"]] <- "point_estimate"

  n_iter <- 0L
  n_success <- 1L
  rdata_file <- file.path(
    output_dir,
    paste0(gformula_rdata_stem("pe", date, time_window_width, cov_order_label, chosen_sg), ".RData")
  )
  save(
    list = c(
      "results", "followup_length", "time_window_width", "n_iter", "n_success",
      "size", "chosen_sg", "int_descript", "all_strategies", "NATURAL_COURSE_NAME",
      "GFORMULA_COVNAMES", "GFORMULA_COVTYPES", "GFORMULA_COV_TRANSFORMS",
      "cov_order_label", "use_cov_inv"
    ),
    file = rdata_file
  )
  message(
    "[get_gformula_point_estimate_single_sg] Results saved for subgroup: ",
    chosen_sg, " -> ", rdata_file
  )

  return(results)
}



#==================#
# 7. main flow     #
#==================#
if (!isTRUE(getOption("gformula.source_only", FALSE))) {
  # データの読み込み
  load(paste0(data_dir, "df_", date, "_all.RData"))
  if (any(is.na(df$survival_after_icu_discharge))) {
    stop("Error: survival_after_icu_discharge contains NA values.")
  }
  sg_ids <- df %>%
    filter(time_window_index == 0) %>%
    filter(!!subgroup_filters[[chosen_sg]]) %>%
    distinct(icu_stay_id) %>%
    pull(icu_stay_id)
  df_filtered   <- df %>%
    filter(icu_stay_id %in% sg_ids) %>%
    filter(time_window_index <= followup_length*(24/time_window_width) - 1) # フォローアップ期間に合わせてデータを抽出
  rm(df); gc()

  if (isTRUE(run_single)) {
    get_gformula_point_estimate_single_sg(
      df_filtered       = df_filtered,
      interventions     = interventions,
      int_descript      = int_descript,
      followup_length   = followup_length,
      time_window_width = time_window_width,
      n_simul_min       = n_simul_min,
      size              = size
    )
  } else {
    # bootstrap CI
    get_gformula_ci_single_sg(
      df_filtered       = df_filtered,
      interventions     = interventions,
      int_descript      = int_descript,
      followup_length   = followup_length,
      time_window_width = time_window_width,
      n_simul_min       = n_simul_min,
      n_iter            = n_iter,
      size              = size,
      total_ram         = total_ram,
      max_workers       = max_workers,
      ram_use_frac      = ram_use_frac,
      expand_factor     = expand_factor
    )
  }
}
