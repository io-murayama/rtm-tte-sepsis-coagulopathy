with
    infusion_injection_records as (
        select
            icu_stay_id,
            start_time,
            end_time,
            active_ingredient_name,
            1 as active_ingredient_use
        from `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate`
        where
            active_ingredient_name in (
                'thrombomodulin_alfa',
                'antithrombin_gamma',
                'freeze_dried_concentrated_human_antithrombin'
            )
    ),

    match_infusion_injection_in_time_window as (
        select
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            active_ingredient_name,
            active_ingredient_use,
            infusion_injection_records.start_time as infusion_start_time
        from `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows` time_windows
        left join infusion_injection_records
            on time_windows.icu_stay_id = infusion_injection_records.icu_stay_id
            and time_windows.end_time > infusion_injection_records.start_time
            and time_windows.start_time <= infusion_injection_records.end_time
    ),

    classify_active_ingredients as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            case
                when active_ingredient_name = 'thrombomodulin_alfa'
                then active_ingredient_use
            end as thrombomodulin_use,
            case
                when active_ingredient_name in ('antithrombin_gamma', 'freeze_dried_concentrated_human_antithrombin')
                then active_ingredient_use
            end as antithrombin_use,
            case
                when active_ingredient_name = 'thrombomodulin_alfa'
                    and infusion_start_time >= start_time
                    and infusion_start_time < end_time
                then infusion_start_time
            end as thrombomodulin_start_time,
            case
                when active_ingredient_name in ('antithrombin_gamma', 'freeze_dried_concentrated_human_antithrombin')
                    and infusion_start_time >= start_time
                    and infusion_start_time < end_time
                then infusion_start_time
            end as antithrombin_start_time
        from match_infusion_injection_in_time_window
    ),

    aggregate_per_time_window as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            coalesce(max(thrombomodulin_use), 0) as thrombomodulin_use,
            coalesce(max(antithrombin_use), 0) as antithrombin_use,
            min(thrombomodulin_start_time) as thrombomodulin_start_time,
            min(antithrombin_start_time) as antithrombin_start_time
        from classify_active_ingredients
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from aggregate_per_time_window
inner join `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (icu_stay_id)
