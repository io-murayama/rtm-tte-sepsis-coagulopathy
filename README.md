# rtm-sepsis-coagulopathy-target-trial-emulation

This repository contains the full set of R scripts, SQL queries, and environment configuration files used in a study evaluating recombinant human soluble thrombomodulin (rTM) treatment strategies in patients with sepsis-associated coagulopathy. Using multicenter ICU observational data from Japan, the analyses emulate a target trial and estimate the effects of initiating rTM within 24 hours, between 24 and 48 hours, or not at all, on 28-day all-cause mortality.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Requirements](#requirements)
- [Usage](#usage)
- [Contact](#contact)
- [License](#license)

---

## Overview

This project evaluates the effects of clinically relevant rTM treatment strategies on short-term mortality in ICU patients with sepsis-associated coagulopathy, using a target trial emulation framework.

Statistical analyses were conducted in R, and data extraction used SQL. This repository provides:

- SQL queries used for cohort definition, data extraction, patient flow, treatment summaries, and ICU length-of-stay summaries
- R scripts used for data processing, modeling, and visualization
- Files required to reproduce the R computational environment (`renv`, Docker)

---

## Repository Structure

```
rtm-sepsis-coagulopathy-target-trial-emulation
├── README.md
├── LICENSE
├── .Rprofile
├── .Rbuildignore
├── renv.lock
├── renv/
│   ├── activate.R
│   └── settings.json
├── rocker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── up.sh
├── sql/
│   ├── data_extraction/
│   │   ├── research_tte_anticoagulant_2026_01_eligibility_criteria.sql
│   │   ├── research_tte_anticoagulant_2026_02_daily_time_windows.sql
│   │   ├── research_tte_anticoagulant_2026_03_labeling_treatment.sql
│   │   ├── research_tte_anticoagulant_2026_04_labeling_icu_death_and_discharge_alive.sql
│   │   ├── research_tte_anticoagulant_2026_05_static_variables.sql
│   │   ├── research_tte_anticoagulant_2026_11_blood_gas.sql
│   │   ├── research_tte_anticoagulant_2026_12_laboratory_tests.sql
│   │   ├── research_tte_anticoagulant_2026_13_bleeding_status.sql
│   │   ├── research_tte_anticoagulant_2026_14_vital_measurements.sql
│   │   ├── research_tte_anticoagulant_2026_21_mechanical_ventilations.sql
│   │   ├── research_tte_anticoagulant_2026_22_renal_replacement_therapy.sql
│   │   ├── research_tte_anticoagulant_2026_23_scoring.sql
│   │   ├── research_tte_anticoagulant_2026_24_noradrenaline_equivalent_dose.sql
│   │   ├── research_tte_anticoagulant_2026_25_heparin_use.sql
│   │   ├── research_tte_anticoagulant_2026_26_transfusions.sql
│   │   ├── research_tte_anticoagulant_2026_31_join_all_features.sql
│   │   ├── research_tte_anticoagulant_2026_32_forward_filling.sql
│   │   └── research_tte_anticoagulant_2026_33_extract_windows_up_to_28days.sql
│   ├── icu_length_of_stay/
│   │   ├── 1_overall_icu_length_of_stay.sql
│   │   ├── 2_rTM_use_icu_length_of_stay.sql
│   │   └── 3_no_rTM_use_icu_length_of_stay.sql
│   ├── patient_flow_diagram/
│   │   ├── 1_distinct_hospital_id.sql
│   │   ├── 2_database_n_icu_stay_id.sql
│   │   ├── 3_sepsis_associated_coagulopathy.sql
│   │   ├── 4_exclusion_liver_disease.sql
│   │   ├── 5_exclusion_cardiac_arrest_or_ie_diagnosis.sql
│   │   ├── 6_exclusion_no_recorded_gender_age_mortality.sql
│   │   ├── 7_exclusion_antithrombin.sql
│   │   ├── 8_exclusion_younger.sql
│   │   ├── 9_exclusion_rTM.sql
│   │   ├── 10_exclusion_vital_missing.sql
│   │   └── 11_exclusion_er_death.sql
│   └── treatments/
│       ├── 1_n_thrombomodulin_use.sql
│       ├── 2_n_antithrombin_use.sql
│       ├── 3_rTM_start_time.sql
│       └── 4_rTM_treatment_days.sql
├── data/
├── output/
└── scripts/
    ├── 01_preprocess.R
    ├── 02_gformula.R
    ├── 03_fig_gformula_mortality.R
    ├── 04_fig_risk_difference.R
    ├── 05_table1_baseline.R
    ├── 06_fig_crude_mortality.R
    ├── 07_fig_rtm_treatment_history.R
    ├── 08_table_missingness.R
    ├── 09_fig_natural_course_vs_crude_mortality.R
    ├── 10_fig_subgroup_forest.R
    └── run_analysis.sh
```

- renv
  - Contains files required to reproduce the exact R package environment used in the analysis.
- rocker
  - Contains a Dockerfile for building a containerized R environment consistent with the analysis setup.
- `.Rprofile` / `.Rbuildignore`
  - Project settings for renv activation.
- sql
  - Contains SQL queries used in the study:
    - `data_extraction/`: analysis dataset pipeline in order—cohort and labels (`01`–`05`), time-varying features (`11`–`26`), then join, forward-filling, and final extraction up to 28 days (`31`–`33`)
    - `patient_flow_diagram/`: cohort counts for the patient flow diagram
    - `treatments/`: rTM and antithrombin use summaries
    - `icu_length_of_stay/`: ICU length-of-stay summaries overall and by rTM use
- data / output
  - Local input data and generated analysis outputs. Contents are gitignored; only empty directory placeholders are tracked.
- scripts
  - Contains R scripts for preprocessing, parametric g-formula estimation, and figures/tables, plus `run_analysis.sh` to run the main analysis pipeline.

---

## Requirements

### R Environment

- R version: 4.5.1 (R Foundation for Statistical Computing); the exact package versions are recorded in `renv.lock`
- R packages: fully specified in `renv.lock`

---

## Usage

### Start the analysis environment (Docker)

From the project root directory, run:

```
cd rocker
bash up.sh
```

Then open RStudio Server at [http://localhost:8787](http://localhost:8787) (password: `password`). The repository is mounted at `/home/rstudio/repository`.

### Prepare the analysis dataset

Place the extracted CSV under `data/` (for example `data/260827_df_all.csv`), then from the project root run:

```
Rscript scripts/01_preprocess.R
```

This writes `data/df_260827_all.RData` used by the downstream scripts. Adjust the `date` setting inside each script if your file prefix differs.

### Run the main analysis (g-formula)

The main pipeline estimates per-protocol effects with bootstrap confidence intervals, a full-cohort point estimate (natural course), and builds the primary figures:

```
bash scripts/run_analysis.sh
```

Optional environment variables:

```
DATE=260827 N_ITER=1000 SG=all bash scripts/run_analysis.sh
DATE=260827 N_ITER=25 SGS=all,sofa_10_or_higher bash scripts/run_analysis.sh
VISUALIZE=0 DATE=260827 N_ITER=25 SG=all bash scripts/run_analysis.sh
COV_INV=1 DATE=260827 N_ITER=25 SG=all bash scripts/run_analysis.sh
```

- `DATE`: YYMMDD prefix matching the preprocessed data (default: `260827`)
- `N_ITER`: number of bootstrap iterations (default: `1000`)
- `SG` / `SGS`: subgroup name, or comma-separated list (default: `all`)
- `VISUALIZE`: set to `0` to skip figure scripts `03`, `04`, and `09` (default: `1`)
- `COV_INV`: set to `1` to reverse the within-time **covariate (L)** modeling order while keeping TM/AT last (`--cov-inv`; default: forward)

You can also call the scripts directly, for example:

```
Rscript scripts/02_gformula.R --sg all --date 260827 --n-iter 1000
Rscript scripts/03_fig_gformula_mortality.R --date 260827 --sg all
Rscript scripts/04_fig_risk_difference.R --date 260827 --sg all
Rscript scripts/02_gformula.R --sg all --single --date 260827
Rscript scripts/09_fig_natural_course_vs_crude_mortality.R --date 260827
# Sensitivity: reverse L covariate order (TM/AT remain last)
Rscript scripts/02_gformula.R --sg all --date 260827 --n-iter 1000 --cov-inv
Rscript scripts/02_gformula.R --sg all --single --date 260827 --cov-inv
```

Results are written to `output/` (logs under `output/logs/`). Filenames include `fwd` or `inv` for the covariate order (for example `260827_gformula_ci_24hr_fwd_all.RData`).

After subgroup CI files are available, build the combined subgroup forest plot (day-28 risk differences for both rTM strategies vs no rTM):

```
Rscript scripts/10_fig_subgroup_forest.R --date 260827
Rscript scripts/10_fig_subgroup_forest.R --date 260827 --cov-inv
```

### Natural course vs observed mortality (point estimate)

`run_analysis.sh` already runs the full-cohort `--single` point estimate and, when `VISUALIZE=1`, script `09`. To run that step alone:

```
Rscript scripts/02_gformula.R --sg all --single --date 260827
Rscript scripts/09_fig_natural_course_vs_crude_mortality.R --date 260827
```

This writes `output/<date>_natural_course_vs_observed_mortality_24hr_fwd_all.png` (and a CSV of the plotted curves). No confidence band is drawn. Script `09` is for the full cohort only (no `--sg`).

### Descriptive tables and figures

After preprocessing, run from the project root as needed:

```
Rscript scripts/05_table1_baseline.R
Rscript scripts/06_fig_crude_mortality.R
Rscript scripts/07_fig_rtm_treatment_history.R
Rscript scripts/08_table_missingness.R
```

---

## Contact

For questions or collaboration inquiries, please reach out to us by email:

- [MeDiCU, Inc.](mailto:info@medicu.co.jp)

---

## License

This project is licensed under the GNU General Public License (GPL) - see the [LICENSE](https://github.com/io-murayama/rtm-sepsis-coagulopathy-target-trial-emulation/blob/main/LICENSE) file for details.

---

**Disclaimer:**
The code in this repository is provided for academic research and educational purposes. Individual patient data are not provided.
