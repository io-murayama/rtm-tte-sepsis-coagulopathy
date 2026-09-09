### preprocessing ###
# load packages
if (!require("dplyr")) install.packages("dplyr")
library(dplyr)

# config
date <- '260827'
data_dir <- './data/'
export_dir <-'./data/'

# load
file_name <- paste0(date, "_df_all.csv")
df <- read.csv(paste0(data_dir, file_name), stringsAsFactors = FALSE)

# データ型の確認
sapply(df, class)

# hospital_idはモデルに入れる前に、患者数が少ない病院を "other" にまとめる
df$hospital_id <- as.character(df$hospital_id)

hospital_summary <- df %>%
  group_by(icu_stay_id) %>%
  summarise(
    hospital_id = first(hospital_id),
    discharged_alive_ever = as.integer(any(icu_discharge_alive == 1, na.rm = TRUE)),
    .groups = "drop"
  ) %>%
  group_by(hospital_id) %>%
  summarise(
    n_patients = n(),
    n_discharged_alive = sum(discharged_alive_ever),
    .groups = "drop"
  )

print(hospital_summary %>% arrange(n_patients))

hospital_keep <- hospital_summary %>%
  filter(n_patients >= 100) %>%
  pull(hospital_id)

df <- df %>%
  mutate(
    hospital_id_model = ifelse(
      hospital_id %in% hospital_keep,
      hospital_id,
      "other"
    ),
    hospital_id_model = factor(hospital_id_model)
  )

print(df %>%
        group_by(icu_stay_id) %>%
        summarise(hospital_id_model = first(hospital_id_model), .groups = "drop") %>%
        count(hospital_id_model))

# icu admission year をカテゴリ変数として持つ
df$icu_admission_year <- as.integer(df$icu_admission_year)

df <- df %>%
  mutate(
    icu_admission_year = case_when(
      icu_admission_year <= 2016 ~ "~2016",
      icu_admission_year >= 2017 & icu_admission_year <= 2019 ~ "2017-2019",
      icu_admission_year >= 2020 & icu_admission_year <= 2022 ~ "2020-2022",
      icu_admission_year >= 2023 ~ "2023~"
    ),
    icu_admission_year = factor(
      icu_admission_year,
      levels = c("~2016", "2017-2019", "2020-2022", "2023~")
    )
  )

print(df %>%
        group_by(icu_stay_id) %>%
        summarise(icu_admission_year = first(icu_admission_year), .groups = "drop") %>%
        count(icu_admission_year))

# 型を明示
df$female      <- as.integer(df$female)
df$age         <- as.integer(df$age)
df$respiratory_infection      <- as.integer(df$respiratory_infection)
df$abdominal_infection        <- as.integer(df$abdominal_infection)
df$urinary_infection          <- as.integer(df$urinary_infection)
df$soft_tissue_infection      <- as.integer(df$soft_tissue_infection)
df$central_nervous_infection  <- as.integer(df$central_nervous_infection)
df$cardiovascular_infection   <- as.integer(df$cardiovascular_infection)
df$charlson_comorbidity_index <- as.integer(df$charlson_comorbidity_index)

df$mechanical_ventilation_use <- as.integer(df$mechanical_ventilation_use)
df$renal_replacement_therapy_use <- as.integer(df$renal_replacement_therapy_use)
df$sofa_score                 <- as.integer(df$sofa_score)
df$apache2_score              <- as.integer(df$apache2_score)
df$lactate                    <- as.numeric(df$lactate)
df$heparin_use                <- as.integer(df$heparin_use)
df$rbc_use                    <- as.integer(df$rbc_use)
df$ffp_use                    <- as.integer(df$ffp_use)
df$pc_use                     <- as.integer(df$pc_use)

df$thrombomodulin_use         <- as.integer(df$thrombomodulin_use)
df$antithrombin_use           <- as.integer(df$antithrombin_use)

df$time_window_index            <- as.integer(df$time_window_index)
df$icu_death                    <- as.integer(df$icu_death)
df$icu_discharge_alive          <- as.integer(df$icu_discharge_alive)
df$survival_after_icu_discharge <- as.integer(df$survival_after_icu_discharge)

df$intracranial_bleeding <- as.integer(df$intracranial_bleeding)

# adverse_event列を定義
# intracranial bleeding or
# transfusion of >= 1440mL of RBCs over a period of two consecutive days
rbc_6_units_ml <- 1440

df <- df %>%
  arrange(icu_stay_id, time_window_index) %>%
  group_by(icu_stay_id) %>%
  mutate(
    rbc_amount_ml_2days = lag(rbc_amount_ml, default = 0) + rbc_amount_ml,
    rbc_6_units_over_2days = ifelse(rbc_amount_ml_2days >= rbc_6_units_ml, 1, 0),
    adverse_event = ifelse(
      intracranial_bleeding == 1 | rbc_6_units_over_2days == 1,
      1,
      0
    )
  ) %>%
  ungroup()

# 解析に必要な列だけ残す
columns_to_use <- c(
  "icu_stay_id", "time_window_index", "female", "age", "hospital_id_model",
  "icu_admission_year", "respiratory_infection", "abdominal_infection", "urinary_infection",
  "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
  "charlson_comorbidity_index", "bt", "hr", "rr", "mbp", "spo2", "lactate",
  "pt_inr", "platelet",
  "noradrenaline_equivalent_dose", "mechanical_ventilation_use", 
  "renal_replacement_therapy_use", "sofa_score", "apache2_score",
  "heparin_use", "rbc_use", "ffp_use", "pc_use", "thrombomodulin_use", "antithrombin_use",
  "icu_death", "icu_discharge_alive", "survival_after_icu_discharge", "adverse_event"
)

df <- df %>%
  select(all_of(columns_to_use))

print(paste0("Number of unique icu_stay_id: ", length(unique(df$icu_stay_id))))

# Winsorize vital signs only at mean ± k*SD (clinical / identity scale).
# Labs (lactate, pt_inr, platelet), norad, and sofa_score are not winsorized here.
cap_mean_sd <- function(x, transform = "identity", k = 3, var = NULL) {
  x <- as.numeric(x)
  ok <- is.finite(x)
  n_ok <- sum(ok)
  empty <- list(
    x = x,
    transform = transform,
    n_ok = n_ok,
    n_capped_lo = 0L,
    n_capped_hi = 0L,
    lo_t = NA_real_,
    hi_t = NA_real_,
    lo_clinical = NA_real_,
    hi_clinical = NA_real_
  )
  if (n_ok == 0L) {
    return(empty)
  }

  if (identical(transform, "identity")) {
    x_t <- x
  } else if (identical(transform, "log")) {
    if (any(x[ok] <= 0)) {
      stop(sprintf(
        "[cap_mean_sd] %s requires strictly positive values for log; found min=%s",
        if (is.null(var)) "<unknown>" else var,
        format(min(x[ok], na.rm = TRUE), digits = 6)
      ))
    }
    x_t <- log(x)
  } else if (identical(transform, "log1p")) {
    if (any(x[ok] < 0)) {
      stop(sprintf(
        "[cap_mean_sd] %s requires non-negative values for log1p; found min=%s",
        if (is.null(var)) "<unknown>" else var,
        format(min(x[ok], na.rm = TRUE), digits = 6)
      ))
    }
    x_t <- log1p(x)
  } else {
    stop("[cap_mean_sd] Unsupported transform: ", transform)
  }

  mu <- mean(x_t[ok])
  s <- sd(x_t[ok])
  if (!is.finite(s) || s <= 0) {
    return(empty)
  }

  lo_t <- mu - k * s
  hi_t <- mu + k * s
  n_capped_lo <- sum(ok & x_t < lo_t, na.rm = TRUE)
  n_capped_hi <- sum(ok & x_t > hi_t, na.rm = TRUE)
  x_t_capped <- pmin(pmax(x_t, lo_t), hi_t)

  if (identical(transform, "identity")) {
    x_out <- x_t_capped
    lo_clinical <- lo_t
    hi_clinical <- hi_t
  } else if (identical(transform, "log")) {
    x_out <- exp(x_t_capped)
    lo_clinical <- exp(lo_t)
    hi_clinical <- exp(hi_t)
  } else {
    # log1p
    x_out <- pmax(expm1(x_t_capped), 0)
    lo_clinical <- pmax(expm1(lo_t), 0)
    hi_clinical <- pmax(expm1(hi_t), 0)
  }
  x_out[!ok] <- x[!ok]

  list(
    x = x_out,
    transform = transform,
    n_ok = n_ok,
    n_capped_lo = as.integer(n_capped_lo),
    n_capped_hi = as.integer(n_capped_hi),
    lo_t = lo_t,
    hi_t = hi_t,
    lo_clinical = lo_clinical,
    hi_clinical = hi_clinical
  )
}

cap_specs <- c(
  bt = "identity",
  hr = "identity",
  rr = "identity",
  mbp = "identity",
  spo2 = "identity"
)

cap_rows <- list()
for (v in names(cap_specs)) {
  res <- cap_mean_sd(df[[v]], transform = cap_specs[[v]], k = 3, var = v)
  df[[v]] <- res$x
  cap_rows[[v]] <- data.frame(
    variable = v,
    transform = res$transform,
    n_ok = res$n_ok,
    n_capped_lo = res$n_capped_lo,
    n_capped_hi = res$n_capped_hi,
    pct_capped = 100 * (res$n_capped_lo + res$n_capped_hi) / max(res$n_ok, 1L),
    lo_clinical = res$lo_clinical,
    hi_clinical = res$hi_clinical,
    stringsAsFactors = FALSE
  )
}
cap_summary <- do.call(rbind, cap_rows)
rownames(cap_summary) <- NULL
message("[01_preprocess] mean±3SD winsorize (vitals only; stored clinical):")
print(cap_summary)

# RDataで保存（臨床単位のまま）
save(df, file = paste0(export_dir,"df_",date,"_all.RData"))
