with
    pivot_laboratory_tests as (
        select *
        from
            (
                select icu_stay_id, time, field_name, value
                from `medicu-beta.latest_one_icu.laboratory_tests_blood`
                where
                    field_name in (
                        'wbc',
                        'hemoglobin',
                        'platelet',
                        'crp',
                        'albumin',
                        'brain_natriuretic_peptide',
                        'creatine_kinase',
                        'd_dimer',
                        'fdp',
                        'international_normalized_ratio_of_prothrombin_time',
                        'creatinine',
                        'total_bilirubin',
                        'potassium',
                        'sodium'
                    )
            ) pivot (
                max(value) for field_name in (
                    'wbc',
                    'hemoglobin',
                    'platelet',
                    'crp',
                    'albumin',
                    'brain_natriuretic_peptide',
                    'creatine_kinase',
                    'd_dimer',
                    'fdp',
                    'international_normalized_ratio_of_prothrombin_time',
                    'creatinine',
                    'total_bilirubin',
                    'potassium',
                    'sodium'
                )
            )
    ),

    treatment_time_windows as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            coalesce(
                least(thrombomodulin_start_time, antithrombin_start_time),
                thrombomodulin_start_time,
                antithrombin_start_time
            ) as treatment_start_time
        from
            `medicu-production.research_tte_anticoagulant_2026.03_labeling_treatment`
    ),

    join_laboratory_tests as (
        select
            tw.icu_stay_id,
            tw.time_window_index,
            tw.start_time,
            tw.end_time,
            tw.treatment_start_time,
            lab.time,
            lab.wbc,
            lab.hemoglobin,
            lab.platelet,
            lab.crp,
            lab.albumin,
            lab.brain_natriuretic_peptide,
            lab.creatine_kinase,
            lab.d_dimer,
            lab.fdp,
            lab.international_normalized_ratio_of_prothrombin_time,
            lab.creatinine,
            lab.total_bilirubin,
            lab.potassium,
            lab.sodium
        from treatment_time_windows as tw
        left join
            pivot_laboratory_tests as lab
            on tw.icu_stay_id = lab.icu_stay_id
            and tw.start_time <= lab.time
            and lab.time < tw.end_time
    ),

    mark_before_treatment as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            time,
            wbc,
            hemoglobin,
            platelet,
            crp,
            albumin,
            brain_natriuretic_peptide,
            creatine_kinase,
            d_dimer,
            fdp,
            international_normalized_ratio_of_prothrombin_time,
            creatinine,
            total_bilirubin,
            potassium,
            sodium,
            if(treatment_start_time < time, null, wbc) as wbc_before_treatment,
            if(
                treatment_start_time < time, null, hemoglobin
            ) as hemoglobin_before_treatment,
            if(
                treatment_start_time < time, null, platelet
            ) as platelet_before_treatment,
            if(treatment_start_time < time, null, crp) as crp_before_treatment,
            if(
                treatment_start_time < time, null, albumin
            ) as albumin_before_treatment,
            if(
                treatment_start_time < time, null, brain_natriuretic_peptide
            ) as brain_natriuretic_peptide_before_treatment,
            if(
                treatment_start_time < time, null, creatine_kinase
            ) as creatine_kinase_before_treatment,
            if(
                treatment_start_time < time, null, d_dimer
            ) as d_dimer_before_treatment,
            if(treatment_start_time < time, null, fdp) as fdp_before_treatment,
            if(
                treatment_start_time < time,
                null,
                international_normalized_ratio_of_prothrombin_time
            ) as pt_inr_before_treatment,
            if(
                treatment_start_time < time, null, creatinine
            ) as creatinine_before_treatment,
            if(
                treatment_start_time < time, null, total_bilirubin
            ) as total_bilirubin_before_treatment,
            if(
                treatment_start_time < time, null, potassium
            ) as potassium_before_treatment,
            if(treatment_start_time < time, null, sodium) as sodium_before_treatment
        from join_laboratory_tests
    ),

    aggregate_laboratory_tests as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            {{ min_by_ignore_nulls("wbc", "time") }} as wbc,
            {{ min_by_ignore_nulls("hemoglobin", "time") }} as hemoglobin,
            {{ min_by_ignore_nulls("platelet", "time") }} as platelet,
            {{ min_by_ignore_nulls("crp", "time") }} as crp,
            {{ min_by_ignore_nulls("albumin", "time") }} as albumin,
            {{ min_by_ignore_nulls("brain_natriuretic_peptide", "time") }} as brain_natriuretic_peptide,
            {{ min_by_ignore_nulls("creatine_kinase", "time") }} as creatine_kinase,
            {{ min_by_ignore_nulls("d_dimer", "time") }} as d_dimer,
            {{ min_by_ignore_nulls("fdp", "time") }} as fdp,
            {{ min_by_ignore_nulls("international_normalized_ratio_of_prothrombin_time", "time") }} as pt_inr,
            {{ min_by_ignore_nulls("creatinine", "time") }} as creatinine,
            {{ min_by_ignore_nulls("total_bilirubin", "time") }} as total_bilirubin,
            {{ min_by_ignore_nulls("potassium", "time") }} as potassium,
            {{ min_by_ignore_nulls("sodium", "time") }} as sodium,
            {{ min_by_ignore_nulls("wbc_before_treatment", "time") }} as wbc_before_treatment,
            {{ min_by_ignore_nulls("hemoglobin_before_treatment", "time") }} as hemoglobin_before_treatment,
            {{ min_by_ignore_nulls("platelet_before_treatment", "time") }} as platelet_before_treatment,
            {{ min_by_ignore_nulls("crp_before_treatment", "time") }} as crp_before_treatment,
            {{ min_by_ignore_nulls("albumin_before_treatment", "time") }} as albumin_before_treatment,
            {{ min_by_ignore_nulls("brain_natriuretic_peptide_before_treatment", "time") }} as brain_natriuretic_peptide_before_treatment,
            {{ min_by_ignore_nulls("creatine_kinase_before_treatment", "time") }} as creatine_kinase_before_treatment,
            {{ min_by_ignore_nulls("d_dimer_before_treatment", "time") }} as d_dimer_before_treatment,
            {{ min_by_ignore_nulls("fdp_before_treatment", "time") }} as fdp_before_treatment,
            {{ min_by_ignore_nulls("pt_inr_before_treatment", "time") }} as pt_inr_before_treatment,
            {{ min_by_ignore_nulls("creatinine_before_treatment", "time") }} as creatinine_before_treatment,
            {{ min_by_ignore_nulls("total_bilirubin_before_treatment", "time") }} as total_bilirubin_before_treatment,
            {{ min_by_ignore_nulls("potassium_before_treatment", "time") }} as potassium_before_treatment,
            {{ min_by_ignore_nulls("sodium_before_treatment", "time") }} as sodium_before_treatment
        from mark_before_treatment
        group by icu_stay_id, time_window_index, start_time, end_time
    )

select *
from aggregate_laboratory_tests
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
