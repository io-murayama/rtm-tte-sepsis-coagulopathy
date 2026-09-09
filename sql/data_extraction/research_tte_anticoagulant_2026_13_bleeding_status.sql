with
    bleeding_categories as (
        select
            i.icu_stay_id,
            hd.disease_start_date,
            -- =========================
            -- 1) Intracranial bleeding
            -- Non-traumatic: I60-I62
            -- Traumatic intracranial: S064-S066
            -- =========================
            case
                when hd.icd10 like 'I60%'
                or hd.icd10 like 'I61%'
                or hd.icd10 like 'I62%'
                or hd.icd10 like 'S064%'
                or hd.icd10 like 'S065%'
                or hd.icd10 like 'S066%'
                then 1
                else 0
            end as intracranial_bleeding,
            -- =========================
            -- 2) Gastrointestinal bleeding
            -- I850, I864
            -- K250,K252,K254,K256
            -- K260,K262,K264,K266
            -- K270,K272,K274,K276
            -- K280,K282,K284,K286
            -- K625
            -- K920-K922
            -- =========================
            case
                when hd.icd10 in (
                    'I850','I864',
                    'K250','K252','K254','K256',
                    'K260','K262','K264','K266',
                    'K270','K272','K274','K276',
                    'K280','K282','K284','K286',
                    'K625',
                    'K920','K921','K922'
                    )
                then 1
                else 0
            end as gastrointestinal_bleeding,
            -- =========================
            -- 3) Other major bleeding
            -- Respiratory: J942, R04
            -- Renal/urinary: R31
            -- Ophthalmic: H313, H356, H431, H450
            -- Retroperitoneal: K661
            -- Pericardial: I312
            -- Anemia due to blood loss: D500, D62
            -- =========================
            case
                when hd.icd10 in (
                    'J942','R04',
                    'R31',
                    'H313','H356','H431','H450',
                    'K661',
                    'I312',
                    'D500','D62'
                    )
                then 1
                else 0
            end as another_major_bleeding
        from `medicu-beta.latest_one_icu.hospital_admission_diagnoses` as hd
        inner join
            `medicu-beta.latest_one_icu.icu_stays` as i
            using (hospital_admission_id)
    ),

    bleeding_records as (
        select
            icu_stay_id,
            disease_start_date,
            intracranial_bleeding,
            gastrointestinal_bleeding,
            another_major_bleeding,
            1 as any_bleeding
        from bleeding_categories
        where
            intracranial_bleeding = 1
            or gastrointestinal_bleeding = 1
            or another_major_bleeding = 1
    ),

    match_bleeding_in_time_window as (
        select
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            r.intracranial_bleeding,
            r.gastrointestinal_bleeding,
            r.another_major_bleeding,
            r.any_bleeding
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as tw
        left join
            bleeding_records as r
            on tw.icu_stay_id = r.icu_stay_id
            and r.disease_start_date >= tw.start_time
            and r.disease_start_date < tw.end_time
    ),

    aggregate_per_time_window as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            coalesce(max(intracranial_bleeding), 0) as intracranial_bleeding,
            coalesce(
                max(gastrointestinal_bleeding), 0
            ) as gastrointestinal_bleeding,
            coalesce(max(another_major_bleeding), 0) as another_major_bleeding,
            coalesce(max(any_bleeding), 0) as any_bleeding
        from match_bleeding_in_time_window
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from aggregate_per_time_window
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
