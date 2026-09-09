with
    forward_filling as (
        select
            icu_stay_id,
            time_window_index,
            start_time,
            end_time,
            out_time,

            thrombomodulin_use,
            antithrombin_use,
            thrombomodulin_start_time,
            antithrombin_start_time,

            icu_death,
            icu_discharge_alive,

            female,
            age,
            body_weight,
            type_of_hospital,
            hospital_length_of_stay,
            icu_length_of_stay,
            icu_admission_year,
            icu_admission_type,
            hospital_id,
            date_of_death,
            in_time,
            primary_diagnosis,
            primary_icd10,
            respiratory_infection,
            abdominal_infection,
            urinary_infection,
            soft_tissue_infection,
            central_nervous_infection,
            cardiovascular_infection,
            charlson_comorbidity_index,
            myocardial_infarct,
            congestive_heart_failure,
            cerebrovascular_disease,
            chronic_pulmonary_disease,
            mild_liver_disease,
            severe_liver_disease,
            diabetes_without_cc,
            diabetes_with_cc,
            renal_disease,
            malignant_cancer,
            metastatic_solid_tumor,
            aids,
            apache2_score,
            apache3_score,
            survival_after_icu_discharge,

            organ_dysfunction_time,
            first_coagulopathy_time,

            -- blood_gas
            -- unbounded precedingでforward filling
            last_value(ph ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as ph,
            last_value(base_excess ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as base_excess,
            last_value(bicarbonate ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as bicarbonate,
            last_value(po2 ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as po2,
            last_value(pco2 ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as pco2,
            last_value(lactate ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as lactate,

            -- laboratory_tests
            -- unbounded precedingでforward filling
            -- 治療開始時刻より前の記録があればそれを使用、なければ、forward fillingにより直近の記録を取得する
            coalesce(
                wbc_before_treatment,
                last_value(wbc ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as wbc,
            coalesce(
                hemoglobin_before_treatment,
                last_value(hemoglobin ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as hemoglobin,
            coalesce(
                platelet_before_treatment,
                last_value(platelet ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as platelet,
            coalesce(
                crp_before_treatment,
                last_value(crp ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as crp,
            coalesce(
                albumin_before_treatment,
                last_value(albumin ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as albumin,
            coalesce(
                brain_natriuretic_peptide_before_treatment,
                last_value(brain_natriuretic_peptide ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as brain_natriuretic_peptide,
            coalesce(
                creatine_kinase_before_treatment,
                last_value(creatine_kinase ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as creatine_kinase,
            coalesce(
                d_dimer_before_treatment,
                last_value(d_dimer ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as d_dimer,
            coalesce(
                fdp_before_treatment,
                last_value(fdp ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as fdp,
            coalesce(
                pt_inr_before_treatment,
                last_value(pt_inr ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as pt_inr,
            coalesce(
                creatinine_before_treatment,
                last_value(creatinine ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as creatinine,
            coalesce(
                total_bilirubin_before_treatment,
                last_value(total_bilirubin ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as total_bilirubin,
            coalesce(
                potassium_before_treatment,
                last_value(potassium ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as potassium,
            coalesce(
                sodium_before_treatment,
                last_value(sodium ignore nulls) over (
                    partition by icu_stay_id
                    order by time_window_index
                    rows between unbounded preceding and 1 preceding
                )
            ) as sodium,

            -- vital_measurements
            -- unbounded precedingでforward filling
            last_value(bt ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as bt,
            last_value(hr ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as hr,
            last_value(rr ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as rr,
            last_value(mbp ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as mbp,
            last_value(spo2 ignore nulls) over (
                partition by icu_stay_id
                order by time_window_index
                rows between unbounded preceding and current row
            ) as spo2,

            -- bleeding_status
            intracranial_bleeding,
            gastrointestinal_bleeding,
            another_major_bleeding,
            any_bleeding,

            -- mechanical_ventilations
            mechanical_ventilation_use,

            -- renal_replacement_therapy
            renal_replacement_therapy_use,

            -- scoring
            sofa_score,
            sic_score,
            jaam_dic_score,
            jaam_dic_2_score,

            -- noradrenaline equivalent dose
            noradrenaline_equivalent_dose,

            -- heparin
            heparin_use,

            -- transfusions
            rbc_use,
            rbc_amount_ml,
            ffp_use,
            pc_use
        from `medicu-production.research_tte_anticoagulant_2026.31_join_all_features`
    )

select *
from forward_filling
