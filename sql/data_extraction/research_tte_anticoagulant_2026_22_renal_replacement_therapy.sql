with
    rrt_records as (
        select icu_stay_id, start_time, end_time, 1 as renal_replacement_therapy_use
        from `medicu-beta.latest_one_icu.renal_replacement_therapy`
    ),

    match_rrt_in_time_window as (
        select
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            renal_replacement_therapy_use
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as time_windows
        left join
            rrt_records
            on time_windows.icu_stay_id = rrt_records.icu_stay_id
            and time_windows.end_time > rrt_records.start_time
            and (time_windows.start_time <= rrt_records.end_time or rrt_records.end_time is null)
    ),

    aggregate_per_time_window as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            coalesce(
                max(renal_replacement_therapy_use), 0
            ) as renal_replacement_therapy_use
        from match_rrt_in_time_window
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from aggregate_per_time_window
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
