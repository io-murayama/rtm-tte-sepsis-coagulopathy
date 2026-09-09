### tableone ###
# load packages
if (!require("tableone")) install.packages("tableone")
library(tableone)
if (!require("dplyr")) install.packages("dplyr")
library(dplyr)

#========================================#
# Configurations                         #
#========================================#
date       <- '260827'
data_dir   <- './data/'
output_dir <- './output/'

# load
load(paste0(data_dir, "df_", date, "_all.RData"))

# rTM使用の有無でグループ化
rtm_group <- df %>%
  group_by(icu_stay_id) %>%
  summarise(
    rtm_ever_use = as.integer(any(thrombomodulin_use == 1, na.rm = TRUE)),
    .groups = "drop"
  )

df_baseline <- df %>%
  filter(time_window_index == 0) %>%
  left_join(rtm_group, by = "icu_stay_id") %>%
  mutate(
    rtm_ever_use = factor(
      rtm_ever_use,
      levels = c(0, 1),
      labels = c("No rTM use", "rTM use")
    )
  )

myVars <- c(
  # demographics
  "age", "female", "icu_admission_year",
  # infection sites
  "respiratory_infection", "abdominal_infection", "urinary_infection",
  "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
  # comorbidity
  "charlson_comorbidity_index",
  # vitals / labs
  "bt", "hr", "rr", "mbp", "spo2", "lactate", "pt_inr", "platelet",
  # treatments
  "noradrenaline_equivalent_dose",
  "mechanical_ventilation_use", "renal_replacement_therapy_use",
  # severity scores
  "sofa_score", "apache2_score",
  # treatments
  "heparin_use", "rbc_use", "ffp_use", "pc_use",
  "thrombomodulin_use", "antithrombin_use"
)

catVars <- c(
  "female", "icu_admission_year",
  "respiratory_infection", "abdominal_infection", "urinary_infection",
  "soft_tissue_infection", "central_nervous_infection", "cardiovascular_infection",
  "mechanical_ventilation_use", "renal_replacement_therapy_use",
  "heparin_use", "rbc_use", "ffp_use", "pc_use",
  "thrombomodulin_use", "antithrombin_use"
)

tab1 <- CreateTableOne(
  vars       = myVars,
  data       = df_baseline,
  factorVars = catVars
)
print(tab1)

tab1_stratified <- CreateTableOne(
  vars       = myVars,
  strata     = "rtm_ever_use",
  data       = df_baseline,
  factorVars = catVars
)
print(tab1_stratified)

# 結果を CSV で保存
tab1_mat <- print(
  tab1, 
  quote = FALSE, 
  noSpaces = TRUE, 
  printToggle = FALSE,
  smd = TRUE
)
write.csv(
  tab1_mat,
  file = paste0(output_dir, date, "_tableone_baseline.csv")
)

tab1_stratified_mat <- print(
  tab1_stratified,
  quote = FALSE,
  noSpaces = TRUE,
  printToggle = FALSE,
  smd = TRUE
)

write.csv(
  tab1_stratified_mat,
  file = paste0(output_dir, date, "_tableone_baseline_stratified_by_rtm_ever_use.csv")
)
