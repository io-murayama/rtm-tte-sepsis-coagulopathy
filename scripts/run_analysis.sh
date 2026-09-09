#!/usr/bin/env bash
# Paper analysis: gformula bootstrap CI + point estimate + main figures
#   - 02 gformula (bootstrap CI per subgroup)
#   - 03 mortality curves
#   - 04 risk difference at day 28
#   - 02 gformula (--single, full cohort) + 09 natural course vs observed mortality
#
# Usage:
#   bash scripts/run_analysis.sh
#   DATE=260827 N_ITER=25 SG=all bash scripts/run_analysis.sh
#   DATE=260827 N_ITER=25 SGS=all,sofa_10_or_higher bash scripts/run_analysis.sh
#   VISUALIZE=0 DATE=260827 N_ITER=25 SG=all bash scripts/run_analysis.sh
#   COV_INV=1 DATE=260827 N_ITER=25 SG=all bash scripts/run_analysis.sh
#
# Output:
#   output/${DATE}_gformula_ci_24hr_${COV}_${sg}.RData
#   output/${DATE}_gformula_pe_24hr_${COV}_all.RData
#   (+ PNGs when VISUALIZE=1)
#   COV is "fwd" (default) or "inv" when COV_INV=1

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p output/logs

DATE="${DATE:-260827}"
N_ITER="${N_ITER:-1000}"
SGS="${SGS:-${SG:-all}}"
VISUALIZE="${VISUALIZE:-1}"
COV_INV="${COV_INV:-0}"

COV_LABEL="fwd"
COV_FLAG=""
if [[ "${COV_INV}" == "1" ]]; then
  COV_LABEL="inv"
  COV_FLAG="--cov-inv"
fi

run_02() {
  # usage: run_02 <extra args...>
  if [[ -n "${COV_FLAG}" ]]; then
    Rscript scripts/02_gformula.R "$@" "${COV_FLAG}"
  else
    Rscript scripts/02_gformula.R "$@"
  fi
}

run_fig() {
  # usage: run_fig <script> <extra args...>
  local script="$1"
  shift
  if [[ -n "${COV_FLAG}" ]]; then
    Rscript "${script}" "$@" "${COV_FLAG}"
  else
    Rscript "${script}" "$@"
  fi
}

IFS=',' read -r -a SG_ARR <<< "${SGS}"
for sg in "${SG_ARR[@]}"; do
  sg="$(echo "${sg}" | xargs)"
  [[ -z "${sg}" ]] && continue
  echo "[run_analysis] date=${DATE} n_iter=${N_ITER} sg=${sg} cov=${COV_LABEL}"
  run_02 \
    --sg "${sg}" \
    --date "${DATE}" \
    --n-iter "${N_ITER}" \
    2>&1 | tee "output/logs/gformula_ci_${DATE}_boot${N_ITER}_${COV_LABEL}_${sg}.log"

  if [[ "${VISUALIZE}" == "1" ]]; then
    rdata="output/${DATE}_gformula_ci_24hr_${COV_LABEL}_${sg}.RData"
    if [[ ! -f "${rdata}" ]]; then
      echo "[run_analysis] ERROR: missing ${rdata}" >&2
      exit 1
    fi
    echo "[run_analysis] visualize date=${DATE} sg=${sg} cov=${COV_LABEL}"
    run_fig scripts/03_fig_gformula_mortality.R \
      --date "${DATE}" --sg "${sg}" \
      2>&1 | tee "output/logs/viz_surv_${DATE}_${COV_LABEL}_${sg}.log"
    run_fig scripts/04_fig_risk_difference.R \
      --date "${DATE}" --sg "${sg}" \
      2>&1 | tee "output/logs/viz_rd_${DATE}_${COV_LABEL}_${sg}.log"
  fi
done

# Full-cohort point estimate + natural course vs crude mortality figure
echo "[run_analysis] point estimate date=${DATE} sg=all cov=${COV_LABEL}"
run_02 \
  --sg all \
  --date "${DATE}" \
  --single \
  2>&1 | tee "output/logs/gformula_pe_${DATE}_${COV_LABEL}_all.log"

pe_rdata="output/${DATE}_gformula_pe_24hr_${COV_LABEL}_all.RData"
if [[ ! -f "${pe_rdata}" ]]; then
  echo "[run_analysis] ERROR: missing ${pe_rdata}" >&2
  exit 1
fi

if [[ "${VISUALIZE}" == "1" ]]; then
  echo "[run_analysis] natural course vs observed mortality date=${DATE} cov=${COV_LABEL}"
  run_fig scripts/09_fig_natural_course_vs_crude_mortality.R \
    --date "${DATE}" \
    2>&1 | tee "output/logs/viz_nc_vs_crude_${DATE}_${COV_LABEL}_all.log"

  forest_needed=(
    "all"
    "sofa_less_than_10"
    "sofa_10_or_higher"
    "apache2_less_than_25"
    "apache2_25_or_higher"
  )
  forest_ok=1
  for sg in "${forest_needed[@]}"; do
    if [[ ! -f "output/${DATE}_gformula_ci_24hr_${COV_LABEL}_${sg}.RData" ]]; then
      forest_ok=0
      break
    fi
  done
  if [[ "${forest_ok}" == "1" ]]; then
    echo "[run_analysis] subgroup forest date=${DATE} cov=${COV_LABEL}"
    run_fig scripts/10_fig_subgroup_forest.R \
      --date "${DATE}" \
      2>&1 | tee "output/logs/viz_forest_${DATE}_${COV_LABEL}.log"
  else
    echo "[run_analysis] skip subgroup forest (not all subgroup CI files present)"
  fi
fi

echo "[run_analysis] Done."
