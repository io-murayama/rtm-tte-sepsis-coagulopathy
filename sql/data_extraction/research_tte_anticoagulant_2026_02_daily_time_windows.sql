with
    define_time_window_parameters as (
        select
            e.icu_stay_id,
            s.in_time,
            s.out_time,
            e.time0 as first_time_window_start_time
        from
            `medicu-production.research_tte_anticoagulant_2026.01_eligibility_criteria`
            as e
        inner join
            `medicu-beta.latest_one_icu_derived.extended_icu_stays` as s
            using (icu_stay_id)
    ),

    generate_time_window_indices as (
        select
            icu_stay_id,
            in_time,
            out_time,
            first_time_window_start_time,
            generate_array(
                0,
                cast(
                    floor(
                        timestamp_diff(
                            out_time, first_time_window_start_time, hour
                        )
                        / 24
                    ) as int64
                )
            ) as time_window_indices
        from define_time_window_parameters
    ),

    generate_time_windows as (
        select
            icu_stay_id,
            time_window_index,
            timestamp_add(
                first_time_window_start_time,
                interval time_window_index * 24 hour
            ) as start_time,
            least(
                timestamp_add(
                    first_time_window_start_time,
                    interval (time_window_index + 1) * 24 hour
                ),
                out_time
            ) as end_time,
            out_time
        from generate_time_window_indices as twi
        cross join unnest(twi.time_window_indices) as time_window_index
    )

select *
from generate_time_windows
where start_time < end_time
