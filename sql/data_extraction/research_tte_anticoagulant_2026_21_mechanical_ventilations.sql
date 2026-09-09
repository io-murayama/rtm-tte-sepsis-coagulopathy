with
    mv_records as (
        select
            icu_stay_id,
            start_time,
            end_time,
            1 as mechanical_ventilation_use
        from `medicu-beta.latest_one_icu.mechanical_ventilations`
    ),

    match_mv_in_time_window as (
        select
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            mechanical_ventilation_use
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as time_windows
        left join
            mv_records
            on time_windows.icu_stay_id = mv_records.icu_stay_id
            and time_windows.end_time > mv_records.start_time
            and (time_windows.start_time <= mv_records.end_time or mv_records.end_time is null)
    ),

    aggregate_per_time_window as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            coalesce(
                max(mechanical_ventilation_use), 0
            ) as mechanical_ventilation_use
        from match_mv_in_time_window
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from aggregate_per_time_window
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
