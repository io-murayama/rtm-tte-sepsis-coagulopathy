-- outcome: icu内死亡（icu, er）
with
    labeling_death_and_censoring as (
        select
            icu_stay_id,
            out_time as time,
            case when mortality in ('icu', 'er') then 1 else 0 end as icu_death,
            case
                when mortality in ('survival', 'in_hospital') then 1 else 0
            end as icu_discharge_alive
        from `medicu-beta.latest_one_icu_derived.extended_icu_stays`
    ),

    join_death_and_censor as (
        select
            daily_time_windows.icu_stay_id,
            daily_time_windows.time_window_index,
            daily_time_windows.start_time,
            daily_time_windows.end_time,
            max(coalesce(icu_death, 0)) as icu_death,
            max(coalesce(icu_discharge_alive, 0)) as icu_discharge_alive
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as daily_time_windows
        left join
            labeling_death_and_censoring as d_c_label
            on daily_time_windows.icu_stay_id = d_c_label.icu_stay_id
            -- 02_daily_time_windows のクエリで、out_time を含む time window の end_time は
            -- out_time と一致するようになっている。そのため、下のように等号で join することで
            -- out_time を含む time window に対して labeling を行うことができる
            and d_c_label.time = daily_time_windows.end_time
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from join_death_and_censor
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
