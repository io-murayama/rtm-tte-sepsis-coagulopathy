-- n = 523
-- q1_days = 2.0, median_days = 4.0, q3_days = 6.0
with patient_level as (
  select
    icu_stay_id,
    countif(thrombomodulin_use = 1) as thrombomodulin_use_days
  from `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
  group by icu_stay_id
  having max(thrombomodulin_use) = 1
)

select
  count(*) over() as n,
  percentile_cont(thrombomodulin_use_days, 0.25) over() as q1_days,
  percentile_cont(thrombomodulin_use_days, 0.50) over() as median_days,
  percentile_cont(thrombomodulin_use_days, 0.75) over() as q3_days
from patient_level
qualify row_number() over(order by thrombomodulin_use_days) = 1
