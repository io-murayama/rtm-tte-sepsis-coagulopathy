with
    join_labeling_treatment as (
        select
            daily_time_windows.*,
            labeling_treatment.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as daily_time_windows
        left join
            `medicu-production.research_tte_anticoagulant_2026.03_labeling_treatment`
            as labeling_treatment
            using (icu_stay_id, time_window_index)
    ),

    join_death_and_censor as (
        select
            join_labeling_treatment.*,
            death_and_censor.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_labeling_treatment
        left join
            `medicu-production.research_tte_anticoagulant_2026.04_labeling_icu_death_and_discharge_alive`
            as death_and_censor
            using (icu_stay_id, time_window_index)
    ),

    join_static as (
        select
            join_death_and_censor.*,
            static_variables.* except (icu_stay_id, out_time, time0)
        from join_death_and_censor
        left join
            `medicu-production.research_tte_anticoagulant_2026.05_static_variables`
            as static_variables
            using (icu_stay_id)
    ),

    join_blood_gas as (
        select
            join_static.*,
            blood_gas.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_static
        left join
            `medicu-production.research_tte_anticoagulant_2026.11_blood_gas`
            as blood_gas
            using (icu_stay_id, time_window_index)
    ),

    join_laboratory_tests as (
        select
            join_blood_gas.*,
            laboratory_tests.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_blood_gas
        left join
            `medicu-production.research_tte_anticoagulant_2026.12_laboratory_tests`
            as laboratory_tests
            using (icu_stay_id, time_window_index)
    ),

    join_bleeding_status as (
        select
            join_laboratory_tests.*,
            bleeding_status.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_laboratory_tests
        left join
            `medicu-production.research_tte_anticoagulant_2026.13_bleeding_status`
            as bleeding_status
            using (icu_stay_id, time_window_index)
    ),

    join_vital_measurements as (
        select
            join_bleeding_status.*,
            vital_measurements.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_bleeding_status
        left join
            `medicu-production.research_tte_anticoagulant_2026.14_vital_measurements`
            as vital_measurements
            using (icu_stay_id, time_window_index)
    ),

    join_mechanical_ventilations as (
        select
            join_vital_measurements.*,
            mechanical_ventilations.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_vital_measurements
        left join
            `medicu-production.research_tte_anticoagulant_2026.21_mechanical_ventilations`
            as mechanical_ventilations
            using (icu_stay_id, time_window_index)
    ),

    join_renal_replacement_therapy as (
        select
            join_mechanical_ventilations.*,
            renal_replacement_therapy.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_mechanical_ventilations
        left join
            `medicu-production.research_tte_anticoagulant_2026.22_renal_replacement_therapy`
            as renal_replacement_therapy
            using (icu_stay_id, time_window_index)
    ),

    join_scoring as (
        select
            join_renal_replacement_therapy.*,
            scoring.* except (icu_stay_id, time_window_index, start_time, end_time)
        from join_renal_replacement_therapy
        left join
            `medicu-production.research_tte_anticoagulant_2026.23_scoring`
            as scoring
            using (icu_stay_id, time_window_index)
    ),

    join_noradrenaline_equivalent_dose as (
        select
            join_scoring.*,
            noradrenaline_equivalent_dose.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_scoring
        left join
            `medicu-production.research_tte_anticoagulant_2026.24_noradrenaline_equivalent_dose`
            as noradrenaline_equivalent_dose
            using (icu_stay_id, time_window_index)
    ),

    join_heparin_use as (
        select
            join_noradrenaline_equivalent_dose.*,
            heparin_use.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_noradrenaline_equivalent_dose
        left join
            `medicu-production.research_tte_anticoagulant_2026.25_heparin_use`
            as heparin_use
            using (icu_stay_id, time_window_index)
    ),

    join_transfusions as (
        select
            join_heparin_use.*,
            transfusions.* except (
                icu_stay_id, time_window_index, start_time, end_time, time0,
                organ_dysfunction_time, first_coagulopathy_time,
                coagulopathy_plt_criterion
            )
        from join_heparin_use
        left join
            `medicu-production.research_tte_anticoagulant_2026.26_transfusions`
            as transfusions
            using (icu_stay_id, time_window_index)
    )

select *
from join_transfusions
