with
    blood_gas_pivot as (
        select *
        from
            (
                select icu_stay_id, time, field_name, value
                from `medicu-beta.latest_one_icu.blood_gas`
                where
                    field_name in (
                        'ph',
                        'base_excess',
                        'bicarbonate',
                        'po2',
                        'pco2',
                        'lactate',
                        'hemoglobin'
                    )
                    and (sample_type like '%blood_gas%' or sample_type is null)
            ) pivot (
                max(value) for field_name in (
                    'ph',
                    'base_excess',
                    'bicarbonate',
                    'po2',
                    'pco2',
                    'lactate',
                    'hemoglobin'
                )
            )
    ),

    filter_blood_gas as (select * from blood_gas_pivot where hemoglobin >= 1),

    join_blood_gas as (
        select
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            {{ min_by_ignore_nulls("bg.ph", "bg.time") }} as ph,
            {{ min_by_ignore_nulls("bg.base_excess", "bg.time") }} as base_excess,
            {{ min_by_ignore_nulls("bg.bicarbonate", "bg.time") }} as bicarbonate,
            {{ min_by_ignore_nulls("bg.po2", "bg.time") }} as po2,
            {{ min_by_ignore_nulls("bg.pco2", "bg.time") }} as pco2,
            {{ min_by_ignore_nulls("bg.lactate", "bg.time") }} as lactate
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as tw
        left join
            filter_blood_gas as bg
            on tw.icu_stay_id = bg.icu_stay_id
            and tw.start_time <= bg.time
            and bg.time < tw.end_time
        group by tw.icu_stay_id, tw.time_window_index, tw.start_time, tw.end_time
    )

select *
from join_blood_gas
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
