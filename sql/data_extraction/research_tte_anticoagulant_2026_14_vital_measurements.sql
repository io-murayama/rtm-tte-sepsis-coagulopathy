with
    get_vital_measurements as (
        select
            icu_stay_id,
            time,
            coalesce(bt_core, bt_surface) as bt,
            hr,
            if(rr >= 6, rr, null) as rr,
            coalesce(invasive_mbp, non_invasive_mbp) as mbp,
            spo2
        from `medicu-beta.latest_one_icu.vital_measurements`
    ),

    join_vital_measurements as (
        select distinct
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            percentile_cont(vs.bt, 0.5) over daily_window as bt,
            percentile_cont(vs.hr, 0.5) over daily_window as hr,
            percentile_cont(vs.rr, 0.5) over daily_window as rr,
            percentile_cont(vs.mbp, 0.5) over daily_window as mbp,
            percentile_cont(vs.spo2, 0.5) over daily_window as spo2
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as tw
        left join
            get_vital_measurements as vs
            on tw.icu_stay_id = vs.icu_stay_id
            and tw.start_time <= vs.time
            and vs.time < tw.end_time
        window daily_window as (partition by tw.icu_stay_id, tw.time_window_index)
    )

select *
from join_vital_measurements
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
