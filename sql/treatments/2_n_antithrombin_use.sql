-- n = 555
SELECT 
  distinct icu_stay_id
FROM `medicu-production.research_tte_anticoagulant_2026.33_extract_windows_up_to_28days`
where antithrombin_use = 1
