with
    transfusion_records as (
        select
            icu_stay_id,
            start_time,
            end_time,
            active_ingredient_name,
            ml_per_hour,
            case
                when active_ingredient_name = 'rbc'
                then 'rbc'
                when active_ingredient_name = 'ffp'
                then 'ffp'
                when active_ingredient_name = 'pc'
                then 'pc'
            end as transfusion_type,
            1 as transfusion_use
        from `medicu-beta.latest_one_icu.blood_transfusions`
        left join
            `medicu-beta.latest_one_icu.blood_transfusion_components` using (
                blood_transfusion_id
            )
        left join
            `medicu-beta.latest_one_icu_standard.blood_product_active_ingredients`
            using (blood_product_name)
        where active_ingredient_name in ('rbc', 'ffp', 'pc')
    ),

    match_transfusion_in_time_window as (
        select
            time_windows.icu_stay_id,
            time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            transfusion_type,
            transfusion_use,
            case
                when transfusion_type = 'rbc'
                then
                    ml_per_hour
                    * timestamp_diff(
                        least(
                            time_windows.end_time, transfusion_records.end_time
                        ),
                        greatest(
                            time_windows.start_time,
                            transfusion_records.start_time
                        ),
                        minute
                    )
                    / 60
            end as rbc_amount_ml
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as time_windows
        left join
            transfusion_records
            on time_windows.icu_stay_id = transfusion_records.icu_stay_id
            and time_windows.end_time > transfusion_records.start_time
            and time_windows.start_time <= transfusion_records.end_time
    ),

    rbc_amount as (
        select
            icu_stay_id,
            time_window_index,
            coalesce(sum(rbc_amount_ml), 0) as rbc_amount_ml
        from match_transfusion_in_time_window
        group by icu_stay_id, time_window_index
    ),

    pivot_transfusions as (
        select *
        from
            (
                select
                    icu_stay_id,
                    time_window_index,
                    start_time,
                    end_time,
                    transfusion_type,
                    transfusion_use
                from match_transfusion_in_time_window
            )
            pivot (max(transfusion_use) for transfusion_type in ('rbc', 'ffp', 'pc'))
    ),

    coalesce_columns as (
        select
            pivot_transfusions.icu_stay_id,
            pivot_transfusions.time_window_index,
            pivot_transfusions.start_time,
            pivot_transfusions.end_time,
            coalesce(rbc, 0) as rbc_use,
            rbc_amount.rbc_amount_ml,
            coalesce(ffp, 0) as ffp_use,
            coalesce(pc, 0) as pc_use
        from pivot_transfusions
        left join rbc_amount using (icu_stay_id, time_window_index)
    )

select *
from coalesce_columns
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
