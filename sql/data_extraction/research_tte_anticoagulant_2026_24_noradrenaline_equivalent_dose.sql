-- Noradrenaline Equivalent Dose (NED) の計算
-- NED = noradrenaline + adrenaline + phenylephrine/10 + dopamine/100 + vasopressin*2.5
-- 各time windowにおけるNEDのtime weighted averageを共変量として取得する
--
-- 区間再構成のアプローチ（derived_infusion_injection_active_ingredient_rate_smoothed.sql 参考）:
-- 各薬剤のNED寄与分をstart/endイベントに分解し（start: +NED, end: -NED）、
-- 累積和で任意の時点でのNED合計値を算出、区間時系列データとして再構成する
with
    -- 1. infusion_injection_active_ingredient_rate_smoothedから対象薬剤を抽出
    -- injection（ボラス）は除外し、持続投与（infusion）のみを対象とする
    vasopressor_infusions as (
        select
            icu_stay_id,
            start_time,
            end_time,
            active_ingredient_name,
            unit_per_hour_active_ingredient,
            unit_active_ingredient
        from
            `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate_smoothed`
        where
            active_ingredient_name in (
                'noradrenaline',
                'adrenaline',
                'phenylephrine',
                'dopamine',
                'vasopressin'
            )
            and source = 'infusions'
    ),

    -- 体重・ICU退室時刻の取得
    icu_stay_info as (
        select icu_stay_id, body_weight_imputed, out_time
        from `medicu-beta.latest_one_icu_derived.extended_icu_stays`
    ),

    -- 2. 単位変換し、NED寄与分を計算
    -- noradrenaline, adrenaline, phenylephrine, dopamine: mg/hour -> mcg/kg/min
    --   = unit_per_hour_active_ingredient * 1000 / 60 / body_weight_imputed
    -- vasopressin: unit/hour -> unit/min
    --   = unit_per_hour_active_ingredient / 60
    -- NED寄与分:
    --   noradrenaline: gamma * 1
    --   adrenaline: gamma * 1
    --   phenylephrine: gamma / 10
    --   dopamine: gamma / 100
    --   vasopressin: (unit/min) * 2.5
    ned_contributions as (
        select
            v.icu_stay_id,
            v.start_time,
            v.end_time,
            v.active_ingredient_name,
            case
                when v.active_ingredient_name = 'noradrenaline'
                then
                    v.unit_per_hour_active_ingredient
                    * 1000
                    / 60
                    / s.body_weight_imputed
                when v.active_ingredient_name = 'adrenaline'
                then
                    v.unit_per_hour_active_ingredient
                    * 1000
                    / 60
                    / s.body_weight_imputed
                when v.active_ingredient_name = 'phenylephrine'
                then
                    v.unit_per_hour_active_ingredient
                    * 1000
                    / 60
                    / s.body_weight_imputed
                    / 10
                when v.active_ingredient_name = 'dopamine'
                then
                    v.unit_per_hour_active_ingredient
                    * 1000
                    / 60
                    / s.body_weight_imputed
                    / 100
                when v.active_ingredient_name = 'vasopressin'
                then v.unit_per_hour_active_ingredient / 60 * 2.5
            end as ned_contribution
        from vasopressor_infusions as v
        inner join icu_stay_info as s using (icu_stay_id)
    ),

    -- 3. start/endイベントに分解
    -- startイベント: +ned_contribution（NEDが増加）
    -- endイベント: -ned_contribution（NEDが減少）
    split_time_events as (
        select
            icu_stay_id,
            start_time as time,
            '1_start' as time_type,
            round(cast(ned_contribution as numeric), 5) as score_change
        from ned_contributions
        union all
        select
            icu_stay_id,
            end_time as time,
            '2_end' as time_type,
            round(cast(-ned_contribution as numeric), 5) as score_change
        from ned_contributions
    ),

    -- 4. 同一timeのイベントのNEDを合計しておく（timeでの一意性を担保）
    aggregate_by_time as (
        select 
            icu_stay_id,
            time,
            sum(score_change) as score_change
        from split_time_events
        group by icu_stay_id, time
    ),

    -- 5. scoreに変更のあったtime pointだけを抽出
    extract_ned_change_time_points as (
        select *
        from aggregate_by_time
        where score_change != 0
    ),

    -- 6. 各timeにおける累積和でNED合計値を算出
    -- 最後の区間は次の変化イベントがないため、ICU退室時刻まで値を維持する
    cumulative_ned as (
        select
            n.icu_stay_id,
            n.time as start_time,
            coalesce(
                lead(n.time) over (
                    partition by n.icu_stay_id
                    order by n.time
                ),
                s.out_time
            ) as end_time,
            n.score_change,
            sum(n.score_change) over (
                partition by n.icu_stay_id
                order by n.time
            ) as cumulative_ned_value
        from extract_ned_change_time_points as n
        inner join icu_stay_info as s using (icu_stay_id)
    ),

    -- 7. time windowと区間の重なりを使い、各time windowのNED time weighted averageを取得
    -- 各区間ではcumulative_ned_valueが一定なので、
    -- value * 重なり時間 を合計し、time windowの長さで割る
    time_weighted_average_ned_per_time_window as (
        select
            time_windows.icu_stay_id,
            time_windows.time_window_index,
            time_windows.start_time,
            time_windows.end_time,
            coalesce(
                sum(
                    cumulative_ned.cumulative_ned_value
                    * timestamp_diff(
                        least(
                            cumulative_ned.end_time, time_windows.end_time
                        ),
                        greatest(
                            cumulative_ned.start_time, time_windows.start_time
                        ),
                        minute
                    )
                )
                / nullif(
                    timestamp_diff(
                        time_windows.end_time, time_windows.start_time, minute
                    ),
                    0
                ),
                0
            ) as noradrenaline_equivalent_dose
        from
            `medicu-production.research_tte_anticoagulant_2026.02_daily_time_windows`
            as time_windows
        left join
            cumulative_ned
            on time_windows.icu_stay_id = cumulative_ned.icu_stay_id
            and time_windows.end_time > cumulative_ned.start_time
            and time_windows.start_time < cumulative_ned.end_time
        group by
            time_windows.icu_stay_id,
            time_windows.time_window_index,
            time_windows.start_time,
            time_windows.end_time
    )

select *
from time_weighted_average_ned_per_time_window
inner join
    `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria` using (
        icu_stay_id
    )
