-- n = 4,417
-- q1_days = 3.0, q2_days = 8.0, q3_days = 17.0
with patient_level as (
  select
    icu_stay_id,
    count(*) as icu_length_of_stay_days
  from `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
  group by icu_stay_id
)

select
  count(*) over() as n,
  percentile_cont(icu_length_of_stay_days, 0.25) over() as q1_days,
  percentile_cont(icu_length_of_stay_days, 0.50) over() as median_days,
  percentile_cont(icu_length_of_stay_days, 0.75) over() as q3_days
from patient_level
qualify row_number() over(order by icu_length_of_stay_days) = 1
