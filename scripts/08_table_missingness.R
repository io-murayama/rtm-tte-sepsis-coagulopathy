### Missing Rate ###
if (!requireNamespace("dplyr", quietly = TRUE)) install.packages("dplyr")
library(dplyr)
if (!requireNamespace("tibble", quietly = TRUE)) install.packages("tibble")
library(tibble)

#========================================#
# Configurations                         #
#========================================#
date <- "260827"
data_dir <- "./data/"
output_dir <- "./output/"

#========================================#
# 1. Load data                           #
#========================================#
load(paste0(data_dir, "df_", date, "_all.RData"))

#========================================#
# 2. Define variables                    #
#========================================#
# Amelia single-imputation targets in scripts/02_gformula.R (single_imputation)
covariates <- c(
  bt         = "Body temperature",
  hr         = "Heart rate",
  rr         = "Respiratory rate",
  mbp        = "Mean arterial pressure",
  spo2       = "Oxygen saturation",
  lactate    = "Lactate",
  pt_inr     = "PT-INR",
  platelet   = "Platelet count",
  sofa_score = "SOFA score"
)

missing_vars <- setdiff(names(covariates), names(df))

if (length(missing_vars) > 0) {
  stop(
    paste0(
      "The following variables are not found in df: ",
      paste(missing_vars, collapse = ", ")
    )
  )
}

#========================================#
# 3. Summarize missingness               #
#========================================#
supp_table_s2 <- lapply(names(covariates), function(var) {
  
  dat_var <- df %>%
    select(icu_stay_id, time_window_index, all_of(var))
  
  total_records <- nrow(dat_var)
  missing_records <- sum(is.na(dat_var[[var]]))
  missing_record_percent <- 100 * missing_records / total_records
  
  patient_missing_summary <- dat_var %>%
    group_by(icu_stay_id) %>%
    summarise(
      n_missing_records = sum(is.na(.data[[var]])),
      has_missing = n_missing_records > 0,
      .groups = "drop"
    )
  
  total_patients <- nrow(patient_missing_summary)
  patients_with_missing <- sum(patient_missing_summary$has_missing)
  patient_missing_percent <- 100 * patients_with_missing / total_patients
  
  affected_missing_counts <- patient_missing_summary %>%
    filter(has_missing) %>%
    pull(n_missing_records)
  
  if (length(affected_missing_counts) == 0) {
    median_iqr <- "0 (0–0)"
  } else {
    median_iqr <- paste0(
      median(affected_missing_counts),
      " (",
      quantile(affected_missing_counts, 0.25),
      "–",
      quantile(affected_missing_counts, 0.75),
      ")"
    )
  }
  
  tibble(
    Variable = covariates[[var]],
    `Total records, n` = total_records,
    `Missing records, n (%)` = sprintf(
      "%d (%.1f)",
      missing_records,
      missing_record_percent
    ),
    `Patients with ≥1 missing record, n/N (%)` = sprintf(
      "%d/%d (%.1f)",
      patients_with_missing,
      total_patients,
      patient_missing_percent
    ),
    `Median missing records per affected patient (IQR)` = median_iqr
  )
  
}) %>%
  bind_rows()

#========================================#
# 4. Export table                        #
#========================================#
print(supp_table_s2)

write.csv(
  supp_table_s2,
  paste0(output_dir, date, "_supplementary_table_s2_missing_values.csv"),
  row.names = FALSE
)