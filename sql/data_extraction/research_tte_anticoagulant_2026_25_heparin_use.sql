with
    infusion_injection_records as (
        select icu_stay_id, start_time, end_time, unit_per_hour
        from
            `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate`
        where active_ingredient_name in ('heparin_calcium', 'heparin_sodium')
    ),

    dose_per_time_window as (
        select
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            coalesce(
                sum(
                    infusion_injection_records.unit_per_hour
                    * timestamp_diff(
                        least(
                            infusion_injection_records.end_time,
                            time_windows.end_time
                        ),
                        greatest(
                            infusion_injection_records.start_time,
                            time_windows.start_time
                        ),
                        minute
                    )
                    / 60.0
                ),
                0
            ) as heparin_daily_dose
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as time_windows
        left join
            infusion_injection_records
            on time_windows.icu_stay_id = infusion_injection_records.icu_stay_id
            and time_windows.end_time > infusion_injection_records.start_time
            and time_windows.start_time <= infusion_injection_records.end_time
        group by
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time
    ),

    aggregate_per_time_window as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            case when heparin_daily_dose >= 5000 then 1 else 0 end as heparin_use
        from dose_per_time_window
    )

select *
from aggregate_per_time_window
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
