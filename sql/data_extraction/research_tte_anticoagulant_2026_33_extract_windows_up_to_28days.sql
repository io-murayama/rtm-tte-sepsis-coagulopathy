-- primary outcome: in-ICU 28-day all-cause mortality
-- time_window_index は 0 始まりのため、28日分は time_window_index <= 27 に相当する
select *
from `medicu-production.research_tte_anticoagulant_2026.32_forward_filling`
where time_window_index <= 28 - 1
