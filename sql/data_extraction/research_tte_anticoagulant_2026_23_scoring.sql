with
    sofa_joined as (
        select
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            sofa.sofa_24hours as sofa_score
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as tw
        left join
            `medicu-beta.latest_one_icu_derived.sofa_hourly` as sofa
            on tw.icu_stay_id = sofa.icu_stay_id
            and sofa.start_time <= tw.start_time
            and tw.start_time < sofa.end_time
    ),

    dic_joined as (
        select
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            dic.sic_score,
            dic.jaam_dic_score,
            dic.jaam_dic_2_score
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as tw
        left join
            `medicu-beta.latest_one_icu_derived.dic_hourly` as dic
            on tw.icu_stay_id = dic.icu_stay_id
            and dic.start_time <= tw.start_time
            and tw.start_time < dic.end_time
    )

select
    sofa_joined.*,
    dic_joined.* except (icu_stay_id, time_window_index, start_time, end_time)
from sofa_joined
left join dic_joined using (icu_stay_id, time_window_index)
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
