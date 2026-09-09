-- n = 523
-- q1_hour = 3.0, median_hour = 9.0, q3_hour = 31.5
with target_icu_stays as (
  select distinct
    icu_stay_id
  from `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
  where thrombomodulin_use = 1
),

first_thrombomodulin as (
  select
    icu_stay_id,
    min(thrombomodulin_start_time) as first_thrombomodulin_start_time
  from `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
  where icu_stay_id in (select icu_stay_id from target_icu_stays)
    and thrombomodulin_start_time is not null
  group by icu_stay_id
),

baseline_time as (
  select
    icu_stay_id,
    start_time as baseline_start_time
  from `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
  where time_window_index = 0
    and icu_stay_id in (select icu_stay_id from target_icu_stays)
),

diff_hours as (
  select
    f.icu_stay_id,
    timestamp_diff(
      f.first_thrombomodulin_start_time,
      b.baseline_start_time,
      hour
    ) as thrombomodulin_start_hour_from_baseline
  from first_thrombomodulin as f
  inner join baseline_time as b
    on f.icu_stay_id = b.icu_stay_id
)

select
  count(*) over() as n,
  percentile_cont(thrombomodulin_start_hour_from_baseline, 0.25) over() as q1_hour,
  percentile_cont(thrombomodulin_start_hour_from_baseline, 0.50) over() as median_hour,
  percentile_cont(thrombomodulin_start_hour_from_baseline, 0.75) over() as q3_hour
from diff_hours
qualify row_number() over() = 1
