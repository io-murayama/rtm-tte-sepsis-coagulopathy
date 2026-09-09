with
    respiratory_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'J153', 'J128', 'J152', 'J869', 'J852', 'J205', 'J210',
                'J121', 'J209', 'J028', 'J120', 'B085', 'A065', 'B441',
                'B371', 'B49', 'J029', 'J068', 'J392', 'J060', 'J390',
                'A360', 'A010', 'J391', 'J111', 'J201', 'J042', 'J14',
                'J110', 'J208', 'J129', 'J207', 'J850', 'J156', 'M0091',
                'B390', 'B392', 'B391', 'K768', 'B488', 'J180', 'A202',
                'J860', 'J039', 'J041', 'J050', 'J219', 'J189', 'B450',
                'B380', 'B400', 'T812', 'M8698', 'B029', 'L022', 'B001',
                'L033', 'J188', 'M8940', 'J160', 'B378', 'J203', 'J158',
                'J159', 'B250', 'A022', 'B012', 'A698', 'J155', 'J181',
                'J182', 'I269', 'B59', 'J150', 'J851', 'M0019', 'J202',
                'J13', 'B382', 'B420', 'A221', 'B583', 'A430', 'B410',
                'A310', 'B402', 'A420', 'B460', 'A212', 'J204', 'J122',
                'A318', 'J211', 'J123', 'A482', 'A361', 'J398', 'B002',
                'J157', 'B052', 'B381', 'B401', 'J206', 'J151', 'A241',
                'A481', 'J154', 'A691', 'A192', 'A199', 'A240', 'A242',
                'A244', 'A319', 'A362', 'A370', 'A379', 'B018', 'J010',
                'J011', 'J014', 'J019', 'J030', 'J038', 'J040', 'J051',
                'J069', 'J09', 'J101', 'J22', 'J36', 'U071', 'J690',
                'A162', 'J849', 'J40'
            )
    ),

    abdominal_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'K650', 'T857', 'B270', 'K830', 'A048', 'A099', 'K633',
                'K573', 'K572', 'K631', 'K632', 'K358', 'K36', 'A082',
                'A064', 'A068', 'A062', 'K768', 'A222', 'B462', 'J118',
                'A084', 'A052', 'A046', 'K635', 'K571', 'K570', 'A090',
                'K750', 'K759', 'K838', 'K658', 'K831', 'A045', 'B678',
                'N733', 'K353', 'K37', 'A047', 'K659', 'B338', 'N735',
                'A049', 'B251', 'B252', 'B258', 'A020', 'K613', 'K638',
                'K754', 'A368', 'K764', 'B675', 'K832', 'K810', 'K758',
                'B670', 'A498', 'A044', 'A421', 'K762', 'T814', 'K352',
                'M8695', 'L022', 'K639', 'A010', 'A078', 'K630', 'K612',
                'K611', 'B581', 'T812', 'K753', 'T838', 'T816', 'B268',
                'B263', 'K751', 'K766', 'K811', 'K819', 'K833', 'A079',
                'B008', 'N734', 'A061', 'B378', 'A282', 'A043', 'A042',
                'A041', 'K579', 'K578', 'A073', 'A081', 'K752', 'A040', 
                'A060', 'A053', 'K634', 'A063', 'K610', 'K614', 'A080', 
                'A085A','A213', 'K550', 'K803', 'K859', 'K265', 'K559', 
                'K255', 'K800', 'K562', 'K223'
            )
    ),

    urinary_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'N308', 'N390', 'T835', 'N301', 'B374', 'N300', 'N309',
                'A590', 'T814', 'N399', 'T832', 'N304', 'N303', 'N302',
                'A022', 'B268', 'N10', 'N150', 'N151', 'N159', 'N410',
                'N412', 'N419', 'N450', 'N459', 'N12', 'N201', 'N209'
            )
    ),

    soft_tissue_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'A010', 'A014', 'A022', 'A067', 'A199', 'A201', 'A220',
                'A260', 'A311', 'A318', 'A320', 'A363', 'A398', 'A431',
                'A480', 'A690', 'A691', 'A692', 'B000', 'B001', 'B268',
                'B331', 'B349', 'B372', 'B378', 'B403', 'B421', 'B428',
                'B432', 'B452', 'B463', 'B488', 'B551', 'B552', 'B679',
                'H050', 'H605', 'J012', 'J013', 'J36', 'L020', 'L021',
                'L022', 'L023', 'L024', 'L028', 'L029', 'L030', 'L031',
                'L032', 'L033', 'L038', 'L039', 'L040', 'L042', 'L043',
                'L049', 'L059', 'L080', 'L081', 'L089', 'M0001', 'M0002',
                'M0005', 'M0006', 'M0009', 'M0025', 'M0029', 'M0089',
                'M0091', 'M0092', 'M0093', 'M0094', 'M0095', 'M0096',
                'M0097', 'M0099', 'M0219', 'M0239', 'M8616', 'M8619',
                'M8605', 'M8606', 'M8609', 'M8630', 'M8655', 'M8656',
                'M8659', 'M8662', 'M8665', 'M8666', 'M8669', 'M8689',
                'M8691', 'M8692', 'M8693', 'M8694', 'M8695', 'M8696',
                'M8697', 'M8698', 'M8699', 'M8900', 'M8909', 'M8950',
                'M8987', 'M8989', 'M1339', 'M4654', 'M4659', 'M7227',
                'M7249', 'M7260', 'M7263', 'M7265', 'M7266', 'M7267',
                'M7269', 'T845', 'T847', 'T857'
            )
    ),

    central_nervous_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'A010', 'A022', 'A066', 'A081', 'A170', 'A203', 'A228',
                'A279', 'A321', 'A390', 'A392', 'A393', 'A398', 'A399',
                'A804', 'A809', 'A810', 'A811', 'A812', 'A818', 'A819',
                'A830', 'A831', 'A832', 'A833', 'A834', 'A835', 'A836',
                'A840', 'A841', 'A848', 'A850', 'A851', 'A852', 'A858',
                'A870', 'A872', 'A879', 'B003', 'B004', 'B010', 'B011',
                'B020', 'B021', 'B022', 'B050', 'B051', 'B060', 'B258',
                'B261', 'B262', 'B279', 'B375', 'B384', 'B451', 'B500',
                'B582', 'B602', 'G000', 'G001', 'G002', 'G003', 'G008',
                'G009', 'G030', 'G031', 'G032', 'G039', 'G040', 'G042',
                'G048', 'G049', 'G060', 'G061', 'G062', 'G14', 'J118',
                'T812', 'T814', 'M7227', 'M7249', 'M7260', 'M7263',
                'M7265', 'M7266', 'M7267', 'M7269'
            )
    ),

    cardiovascular_infection as (
        select distinct icu_stay_id
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where
            icd10 in (
                'A395', 'A010', 'T856', 'T857', 'I330', 'I339', 'T827',
                'J118', 'B332', 'I400', 'T814', 'B376', 'I409', 'I38',
                'I408', 'I401', 'A022', 'A38', 'A368', 'A759', 'B588',
                'G08', 'B268', 'A328', 'I301'
            )
    ),

    diagnosis as (
        select
            icu_stay_id,
            diagnosis as primary_diagnosis,
            icd10 as primary_icd10
        from `medicu-beta.latest_one_icu.icu_diagnoses`
        where primary
    ),

    apache2_variable as (
        select icu_stay_id, apache2_score
        from `medicu-beta.latest_one_icu_derived.apache2`
    ),

    apache3_variable as (
        select icu_stay_id, apache3_score
        from `medicu-beta.latest_one_icu_derived.apache3`
    ),

    baseline as (
        select
            s.icu_stay_id,
            i.female,
            i.age,
            i.body_weight_imputed as body_weight,
            i.type_of_hospital,
            i.hospital_length_of_stay,
            i.icu_length_of_stay,
            i.icu_admission_year,
            i.icu_admission_type,
            i.hospital_id,
            i.date_of_death,
            i.in_time,
            i.out_time,
            s.primary_diagnosis,
            s.primary_icd10,
            case when re.icu_stay_id is not null then 1 else 0 end as respiratory_infection,
            case when ab.icu_stay_id is not null then 1 else 0 end as abdominal_infection,
            case when ur.icu_stay_id is not null then 1 else 0 end as urinary_infection,
            case when so.icu_stay_id is not null then 1 else 0 end as soft_tissue_infection,
            case when ce.icu_stay_id is not null then 1 else 0 end as central_nervous_infection,
            case when ca.icu_stay_id is not null then 1 else 0 end as cardiovascular_infection,
            c.charlson_comorbidity_index,
            c.myocardial_infarct,
            c.congestive_heart_failure,
            c.cerebrovascular_disease,
            c.chronic_pulmonary_disease,
            c.mild_liver_disease,
            c.severe_liver_disease,
            c.diabetes_without_cc,
            c.diabetes_with_cc,
            c.renal_disease,
            c.malignant_cancer,
            c.metastatic_solid_tumor,
            c.aids,
            a2.apache2_score,
            a3.apache3_score,
            -- in-hospital mortality解析用のICU退室後生存日数
            case
                when i.mortality in ('icu', 'er')
                then 0  -- ICU, ER死亡の場合はICU退室後生存日数は0とする
                when i.date_of_death = 'survival_at_last_hospital_discharge'
                then 100 * 365  -- 生存退院の場合は100年後を死亡時刻とする（解析する範囲より十分長い生存時間を仮に設定）
                when i.date_of_death in ('mortality_unknown', 'expired_date_unknown')
                then null  -- 死亡不明、死亡日不明の場合はnull（exclusion criteriaで除外するため、nullになるようなケースはない）
                else cast(date_diff(cast(i.date_of_death as date), cast(i.out_time as date), day) as int64)
            end as survival_after_icu_discharge
        from diagnosis as s
        left join
            `medicu-beta.latest_one_icu_derived.extended_icu_stays` as i
            using (icu_stay_id)
        left join respiratory_infection as re using (icu_stay_id)
        left join abdominal_infection as ab using (icu_stay_id)
        left join urinary_infection as ur using (icu_stay_id)
        left join soft_tissue_infection as so using (icu_stay_id)
        left join central_nervous_infection as ce using (icu_stay_id)
        left join cardiovascular_infection as ca using (icu_stay_id)
        left join
            `medicu-beta.latest_one_icu_derived.charlson` as c
            using (icu_stay_id)
        left join apache2_variable as a2 using (icu_stay_id)
        left join apache3_variable as a3 using (icu_stay_id)
    )

select *
from baseline
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria`
    using (icu_stay_id)
