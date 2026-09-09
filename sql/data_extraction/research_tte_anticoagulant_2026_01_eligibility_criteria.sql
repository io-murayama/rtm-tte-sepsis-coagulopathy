-- inclusion criteria:
-- 1. 感染症の診断（ICD-10コードに基づくスクリーニング）
-- 2. Day 1 SOFA >= 2（敗血症の定義）
-- 3. 臓器障害: Vasopressor（noradrenaline, adrenaline, dopamine, vasopressin, phenylephrine）または Mechanical Ventilation の使用
-- 4. 凝固障害: (PLT 30-150 x10^3/mcL または 24時間以内にPLTが30%超の減少) かつ PT-INR > 1.4 の同時期間が存在
-- time0の定義: 臓器障害と凝固障害の両方が起こった後の時点（遅い方）
--
-- exclusion criteria:
-- 1. Time 0以前のantithrombin（antithrombin_gamma, freeze_dried_concentrated_human_antithrombin）の使用
-- 2. Time 0以前のthrombomodulin_alfaの使用
-- 3. 18歳未満
-- 4. 性別・年齢・死亡情報が記録されていない症例
-- 5. CCI（charlson）でのmild_liver_diseaseまたはsevere_liver_diseaseに該当する症例
-- 6. mortality = 'er' の症例（ER死亡）
-- 7. ICU diagnosis に CPA (I469), PCAS (I460), 心臓急死 (I461), IE (I330, I339) のいずれかが含まれる症例（Primaryに限定しない）
-- 8. バイタル測定記録がない症例（体温, 心拍数, 呼吸数, SpO2, 血圧のいずれかが欠損）
with 
  infect_pts as (
    select 
      distinct icu_stay_id
    from `medicu-beta.latest_one_icu.icu_diagnoses`
    where 
      -- icd10に基づく感染症コードのスクリーニング。非感染症も一部含まれる
        (
          icd10 like 'A%' or icd10 like 'B%'
        or
          --インフルエンザ、その他ウイルスによる気道感染およびウイルス性と細菌性肺炎
          icd10 like 'J1%'
        or
          -- 各種気管支炎
          icd10 like 'J2%'
        or
          -- 胸郭の膿瘍性疾患（膿胸、肺化膿症、縦隔膿瘍など）
          icd10 like 'J85%'
        or
          -- 胸郭の膿瘍性疾患つづき
          icd10 like 'J86%'
        or
          --　虫垂炎関連 K35-K37
          icd10 like 'K35%'
        or
          icd10 like 'K36%'
        or
          icd10 like 'K37%'
        or
          --陰部の膿瘍性疾患
          icd10 like 'K61%'
        or
          --腹膜炎および腹腔内膿瘍性疾患
          icd10 like 'K65%'
        or
          --胆嚢炎
          icd10 like 'K81%'
        or
          --膿痂疹
          icd10 like 'L01%'
        or
          --全身体表のせつ、よう、膿瘍
          icd10 like 'L02%'
        or
          --全身体表の蜂窩織炎
          icd10 like 'L03%'
        or
          --全身のリンパ節炎
          icd10 like 'L04%'
        or
          --感染性関節炎
          icd10 like 'M00%'
        or
          --脊椎の感染症
          icd10 like 'M46%'
        or
          --腱および腱周囲の感染症
          icd10 like 'M650%'
        or
          --滑液包膿瘍
          icd10 like 'M710%'
        or
          --壊死性筋膜炎
          icd10 like 'M726%'
        or
        --骨髄炎
          icd10 like 'M86%'
        or
        --尿道感染
          icd10 like 'N34%'
        or
        --前立腺感染
          icd10 like 'N41%'
        or
        --精巣感染
          icd10 like 'N45%'
        or
        --陰嚢感染
          icd10 like 'N49%'
        or
        --付属器感染
          icd10 like 'N70%'
        or
        --子宮感染
          icd10 like 'N71%'
        or
        --女性の外陰感染　非感染病名あり
          icd10 like 'N76%'
        or
        --妊娠中の感染　非感染病名あり
          icd10 like 'O23%'
        or
        --産褥の感染
          icd10 like 'O85%' or icd10 like 'O86%'
        or
        --妊娠から産褥にかけての乳腺感染
          icd10 like 'O91%' --非感染病名あり
        or
        --新生児の先天性肺炎
          icd10 like 'P23%' 
        or
        --新生児の先天性ウイルス
          icd10 like 'P35%' 
        or
        --新生児の敗血症
          icd10 like 'P36%' 
        or
        --その他の先天性感染
          icd10 like 'P37%' 
        or
        --新生児の感染症
          icd10 like 'P39%' 
        or
        --COVID-19
          icd10 like 'U07%' 
        or
          icd10 in (
          "D71", -- 敗血症性肉芽腫症　非感染病名も含まれる
          "E060", -- 急性化膿性甲状腺炎
          "E321", -- 胸腺膿瘍
          "E328", -- 胸腺炎　非感染病名も含まれる
          "G000", --　インフルエンザ菌髄膜炎
          "G001", -- 肺炎球菌性髄膜炎
          "G002", -- 連鎖球菌性髄膜炎
          "G003", -- MRSA髄膜炎、ブドウ球菌性髄膜炎
          "G008", -- クレブシエラ、フリードレンダー桿菌、大腸菌、緑膿菌　髄膜炎
          "G009", -- 細菌性髄膜炎、原因菌不明髄膜炎
          "G030", -- 無菌性髄膜炎
          "G031", -- 慢性髄膜炎
          "G039", -- 髄膜炎、視神経髄膜炎、硬膜炎、くも膜炎など
          "G042", -- 化膿性脳脊髄炎
          "G049", -- 脳炎、脊髄炎
          "G060", -- 脳膿瘍　非感染病名も含まれる
          "G061", -- 脊髄、脊髄硬膜外膿瘍
          "G062", -- 硬膜外、硬膜下膿瘍 
          "H000", -- 眼瞼の感染
          "H001", -- 霰粒腫
          "H050", -- 眼窩の各種感染症病名、眼窩の非感染病名を含む
          "H100", -- 感染性の結膜炎
          "H109", -- MRSA結膜炎
          "H162", -- MRSA角結膜炎、フリクテン性角膜炎、フリクテン性結膜炎、ビランなどの非感染病名あり
          "H208", -- 化膿性ぶどう膜炎、化膿性虹彩炎、非感染病名あり
          "H440", -- 眼内炎
          -- 外耳道の感染
          "H600", -- 外耳道膿瘍
          "H601", -- 外耳道蜂窩織炎
          "H602", -- 外耳道炎
          "H603", -- 外耳道炎つづき
          -- 中耳炎
          "H660", 
          "H661",
          "H662",
          "H663",
          "H664",
          "H700", -- 乳様突起感染
          "H830", -- 内耳の感染
          "I301", -- 感染性心膜炎
          "I309", -- 急性心膜炎
          "I330", -- IE
          "I339", -- IE
          "I400", -- 感染性心筋炎
          "I409", -- 感染性心筋炎
          "I776", -- 感染性大動脈炎
          "I809", -- 化膿性静脈炎
          "I881", -- 腸間膜リンパ節炎
          "J00", -- 鼻咽頭炎
          --副鼻腔炎
          "J010",
          "J011",
          "J012",
          "J013",
          "J014",
          "J019",
          --咽頭炎
          "J020", -- 溶連菌
          "J028", -- その他の細菌およびウイルス
          "J029", -- 化膿性など
          -- 扁桃炎
          "J030", -- 連鎖球菌性
          "J038", -- その他の細菌およびウイルス
          "J039", -- 化膿性など
          -- 喉頭炎
          "J040",
          "J041", 
          "J042",
          "J050", 
          --喉頭蓋炎
          "J051",
          --咽頭喉頭炎
          "J060",
          --咽頭返答、咽頭気管支、鼻咽頭
          "J068",
          "J069",
          "J311", -- 鼻咽頭炎
          -- 副鼻腔炎
          "J320",
          "J321",
          "J322",
          "J323",
          "J324",
          "J329",
          --鼻の感染
          "J340", 
          -- 扁桃周囲炎および扁桃周囲膿瘍
          "J36",
          --声帯膿瘍
          "J383", -- 非感染病名あり
          --喉頭蓋膿瘍
          "J387", -- 非感染病名あり
          --咽後、鼻咽頭膿瘍
          "J390",
          "J391",
          --気管支炎
          "J40",
          "J410",
          "J42",
          -- 誤嚥性肺炎
          "J690",
          "J698",
          --胸膜炎
          "J90", --非感染病名あり
          --気管切開由来の敗血症
          "J950", -- 非感染病名あり
          -- 術後肺炎
          "J958", --非感染病名あり
          -- 歯髄炎
          "K040", --非感染病名あり
          -- 化膿性歯周炎
          "K044",
          "K045",
          -- 歯槽、根尖膿瘍
          "K047",
          -- 歯周囲膿瘍、炎症
          "K052",
          "K053",
          --顎骨炎、膿瘍、骨髄炎
          "K102", -- 非感染病名を含む
          --歯槽炎
          "K103",
          --耳下腺炎
          "K112",
          --耳下腺膿瘍
          "K113",
          --口蓋炎、膿瘍
          "K122",
          -- 食道炎
          "K20",
          -- 胃炎
          "K291",
          -- 十二指腸炎
          "K298",
          --虫垂憩室炎
          "K382",
          --消化管壊死を伴うヘルニア
          "K404",
          "K414",
          "K421",
          "K431",
          "K434",
          "K437",
          "K441",
          "K451",
          -- 中毒性腸管炎
          "K521", --非感染病名あり
          --小腸炎
          "K529", --非感染病名あり
          "K630",
          --盲腸炎
          "K529", --非感染病名あり
          --腸管壊死
          "K550",
          -- 小腸穿孔
          "K570",
          -- 憩室炎
          "K571",
          --大腸穿孔
          "K572",
          --大腸憩室炎
          "K573", --非感染病名あり
          --消化管穿孔
          "K631",
          --腸管気腫
          "K638", --非感染病名あり
          --肝膿瘍
          "K750",
          --胆嚢炎
          "K800",
          "K801",
          --胆嚢,胆管穿孔
          "K822",
          "K832",
          --胆管炎
          "K803",
          "K804",
          "K830",
          --感染性膵壊死、感染性膵炎
          "K858", --非感染病名あり
          "K859", --非感染病名あり
          --敗血症性皮膚炎
          "L080", --非感染病名あり
          --筋膜膿瘍
          "M7289",
          --腎盂腎炎
          "N10",
          "N111",
          "N118",
          "N12",
          "N209", --非感染病名あり
          --腎膿瘍
          "N136",
          "N151",
          --尿管感染
          "N288", --非感染病名あり
          --膀胱炎
          "N300",
          "N308",
          "N309",
          "N323", --非感染病名あり
          --尿路感染全般
          "N390", --非感染病名あり
          -- 陰茎の感染
          "N482",
          -- 乳腺の感染
          "N61",
          --子宮頸部、骨盤内、バルトリン腺、膣の感染症
          "N72",
          "N730",
          "N731",
          "N732",
          "N733",
          "N734",
          "N735",
          "N736",
          "N739",
          --流産後感染
          "O080",
          --妊娠中の感染
          "O290",
          "O353",
          -- 胎盤、羊水などの感染
          "O411",
          --分娩中の敗血症
          "O753",
          "O883",
        --新生児の腸管壊死、穿孔
          'P780',
          'P781',
          'P788',
        -- デバイス感染、術後感染
          "T814",
          "T826",
          "T827",
          "T835",
          "T845",
          "T846",
          "T847",
          "T857",
        -- 予防接種後感染
          "T880"
        )
        )
        -- 非感染症病名を文字列から除外する
        and
        (
          -- 明らかに除外すべき病名
          diagnosis != '急性腎障害'
          -- 感染性でないことが自明な原因を説明する文字列がある
          and diagnosis not like '%薬剤性%' 
          and diagnosis not like '%放射線性%' 
          and diagnosis not like '%アレルギー性%' 
          and diagnosis not like '%好酸球性%' 
          and diagnosis not like '%非感染性%' 
          and diagnosis not like '%非化膿性%' 
          and diagnosis not like '%化学性%' 
          and diagnosis not like '%ERCP%' 
          -- 感染性でないことが自明な接尾語がある
          and diagnosis not like '%出血' 
          and diagnosis not like '%憩室' 
          and diagnosis not like '%腫大' 
          and diagnosis not like '%腫瘤' 
          and diagnosis not like '%尿' 
          and diagnosis not like '%痛' 
          and diagnosis not like '%びらん' 
          and diagnosis not like '%炎症性疾患' 
          and diagnosis not like '%潰瘍' 
          and diagnosis not like '%癒着' 
          and diagnosis not like '%狭窄' 
          and diagnosis not like '%機能障害' 
          and diagnosis not like '%瘻' 
          and diagnosis not like '%閉塞' 
          and diagnosis not like '%貯留' 
          and diagnosis not like '%のう胞' 
          and diagnosis not like '%腐骨' 
          and diagnosis not like '%疣贅' 
          and diagnosis not like '%胸水' 
        )
  ),

  day1_sofa as (
    select 
      icu_stay_id, 
      max(sofa_24hours) as max_sofa 
    from `medicu-beta.latest_one_icu_derived.sofa_hourly`
    where time_window_index >= 0 and time_window_index < 24
    group by icu_stay_id
  ),

  -- 敗血症
  sepsis as (
    select distinct
      i.icu_stay_id,
      s.max_sofa
    from infect_pts as i
    inner join day1_sofa as s using (icu_stay_id)
    where s.max_sofa >= 2
  ),

  -- Vasopressor(noradrenaline, adrenaline, dopamine, vasopressin, phenylephrine)の使用
  vaso as (
    select
      icu_stay_id,
      min(start_time) as vaso_start
    from `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate`
    where active_ingredient_name in ('noradrenaline', 'adrenaline', 'dopamine', 'vasopressin', 'phenylephrine')
    group by icu_stay_id
  ),

  -- mechanical ventilation の使用
  mv as (
    select
      icu_stay_id,
      min(start_time) as mv_start
    from `medicu-beta.latest_one_icu.mechanical_ventilations`
    group by icu_stay_id
  ),

  organ_dysfunction as (
    select
      coalesce(n.icu_stay_id, m.icu_stay_id) as icu_stay_id,
      n.vaso_start,
      m.mv_start,
      -- vaso_start / mv_start のうち早い方を organ_dysfunction_time とする
      case
        when n.vaso_start is not null and m.mv_start is not null then least(n.vaso_start, m.mv_start)
        when n.vaso_start is not null then n.vaso_start
        when m.mv_start  is not null then m.mv_start
        else null
      end as organ_dysfunction_time
    from vaso n
    full outer join mv m using (icu_stay_id)
  ),

  first_coagulopathy as (
    with
      platelet_measurements as (
        select
          icu_stay_id,
          time as start_time,
          coalesce(lead(time) over (partition by icu_stay_id order by time), out_time) as end_time,
          value
        from `medicu-beta.latest_one_icu.laboratory_tests_blood`
        inner join `medicu-beta.latest_one_icu.icu_stays` using (icu_stay_id)
        where field_name = 'platelet' and value is not null and value > 0 and time < out_time
      ),

      -- 24時間以内に30%超のPLT減少を検出
      plt_decrease_intervals as (
        select distinct
          p_later.icu_stay_id,
          p_later.start_time,
          p_later.end_time
        from platelet_measurements as p_later
        inner join platelet_measurements as p_earlier
          on p_earlier.icu_stay_id = p_later.icu_stay_id
          and p_earlier.start_time < p_later.start_time
          and p_later.start_time <= timestamp_add(p_earlier.start_time, interval 24 hour)
          and p_later.value < 0.7 * p_earlier.value  -- >30% decrease
      ),

      coagulopathy_plt_intervals as (
        select icu_stay_id, start_time, end_time, 'plt_range' as source
        from platelet_measurements
        where value >= 30 and value <= 150  -- 30x10^3/mcL 以上, 150x10^3/mcL 以下
        union distinct
        select icu_stay_id, start_time, end_time, 'plt_decrease' as source
        from plt_decrease_intervals
      ),

      inr_measurements as (
        select
          icu_stay_id,
          time as start_time,
          coalesce(lead(time) over (partition by icu_stay_id order by time), out_time) as end_time,
          value
        from `medicu-beta.latest_one_icu.laboratory_tests_blood`
        inner join `medicu-beta.latest_one_icu.icu_stays` using (icu_stay_id)
        where
          field_name = 'international_normalized_ratio_of_prothrombin_time'
          and value is not null
          and value > 0 and time < out_time
      ),

      coagulopathy_ptinr_intervals as (
        select icu_stay_id, start_time, end_time
        from inr_measurements
        where value > 1.4
      ),

      -- 区間時系列データ（半開区間[start, end))同士の重なり条件でjoin
      -- greatest, leastで重なっている部分だけを取り出す
      overlaps as (
        select
          c1.icu_stay_id,
          greatest(c1.start_time, c2.start_time) as start_time,
          least(c1.end_time, c2.end_time) as end_time,
          c1.source
        from coagulopathy_plt_intervals as c1
        inner join coagulopathy_ptinr_intervals as c2
          on c1.icu_stay_id = c2.icu_stay_id
          and c1.start_time < c2.end_time
          and c2.start_time < c1.end_time
      ),

      get_first_coagulopathy_time as (
        select
          icu_stay_id,
          min(start_time) as first_coagulopathy_time
        from overlaps
        group by icu_stay_id
      ),

      coagulopathy_label as (
        select
          g.icu_stay_id,
          g.first_coagulopathy_time,
          case
            when logical_or(o.source = 'plt_range') and logical_or(o.source = 'plt_decrease') then 'both'
            when logical_or(o.source = 'plt_range') then 'plt_range'
            when logical_or(o.source = 'plt_decrease') then 'plt_decrease'
          end as coagulopathy_plt_criterion
        from get_first_coagulopathy_time as g
        inner join overlaps as o
          on g.icu_stay_id = o.icu_stay_id
          and o.start_time = g.first_coagulopathy_time
        group by g.icu_stay_id, g.first_coagulopathy_time
      )
    
    select * from coagulopathy_label
  ),

  --敗血症＋臓器障害＋凝固障害
  sepsis_org_coag as (
    select
      s.icu_stay_id,
      s.max_sofa,
      od.vaso_start,
      od.mv_start,
      od.organ_dysfunction_time,
      c.first_coagulopathy_time,
      c.coagulopathy_plt_criterion,
      -- 両方のイベントが起こった後の時点（遅い方）を time0 と定義
      greatest(od.organ_dysfunction_time, c.first_coagulopathy_time) as time0
    from sepsis s
    inner join organ_dysfunction od using (icu_stay_id)
    inner join first_coagulopathy c using (icu_stay_id)
  ),

  exclusion_criteria as (
      with
          -- Exclusion Criteria
          -- time 0以前のantithrombinの使用
          antithrombin_before as (
              select
                  distinct s.icu_stay_id
              from sepsis_org_coag as s
              left join `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate` t using (icu_stay_id)
              where active_ingredient_name in ('antithrombin_gamma', 'freeze_dried_concentrated_human_antithrombin') and t.start_time < s.time0
          ),

          -- time 0以前のtheombomodulin_alfaの使用
          thrombomoduline_before as (
              select
                  distinct s.icu_stay_id
              from sepsis_org_coag as s
              left join `medicu-beta.latest_one_icu_derived.infusion_injection_active_ingredient_rate` t using (icu_stay_id)
              where active_ingredient_name = 'thrombomodulin_alfa' and t.start_time < s.time0
          ),

          -- 18歳未満
          younger as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                icu_stay_id not in (
                  select icu_stay_id
                  from `medicu-beta.latest_one_icu_derived.extended_icu_stays`
                  where age >= 18
                )
          ),

          -- 性別・年齢・死亡情報が記録されていない症例
          no_recorded_gender_age_mortality as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                  icu_stay_id not in (
                      select distinct icu_stay_id
                      from `medicu-beta.latest_one_icu_derived.extended_icu_stays`
                      where
                          age is not null
                          and female is not null
                          and mortality is not null
                          -- ICU退室後のmortalityも追跡できる必要があるので、mortality_unknown, expired_date_unknownは除外
                          and date_of_death not in ('mortality_unknown', 'expired_date_unknown')
                  )
          ),

          -- CCI（charlson）でのmild_liver_diseaseまたはsevere_liver_diseaseに該当する症例
          liver_disease as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                icu_stay_id in (
                  select icu_stay_id
                  from `medicu-beta.latest_one_icu_derived.charlson`
                  where mild_liver_disease = 1 or severe_liver_disease = 1
                )
          ),

          -- mortality = 'er' の症例（ER死亡）
          mortality_er as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                icu_stay_id in (
                  select icu_stay_id
                  from `medicu-beta.latest_one_icu_derived.extended_icu_stays`
                  where mortality = 'er'
                )
          ),

          -- ICU diagnosis に CPA (I469), PCAS (I460), 心臓急死 (I461), IE (I330, I339) のいずれかが含まれる症例
          -- I46% で CPA / PCAS / 心臓急死 をまとめてカバーする。Primary には限定しない。
          cardiac_arrest_or_ie_diagnosis as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                icu_stay_id in (
                  select icu_stay_id
                  from `medicu-beta.latest_one_icu.icu_diagnoses`
                  where icd10 like 'I46%' or icd10 in ('I330', 'I339')
                )
          ),

          -- バイタル測定記録がない症例
          no_recorded_vital_measurement as (
              select distinct icu_stay_id
              from sepsis_org_coag
              where
                  icu_stay_id not in (
                      select distinct icu_stay_id
                      from
                          `medicu-beta.latest_one_icu_derived.aggregated_vital_measurements`
                      where
                          (bt_core_count + bt_surface_count) > 0
                          and hr_count > 0
                          and rr_count > 0
                          and spo2_count > 0
                          and (invasive_mbp_count + non_invasive_mbp_count) > 0
                  )
          )

      select icu_stay_id from antithrombin_before
      union all
      select icu_stay_id from thrombomoduline_before
      union all
      select icu_stay_id from younger
      union all
      select icu_stay_id from no_recorded_gender_age_mortality
      union all
      select icu_stay_id from liver_disease
      union all
      select icu_stay_id from mortality_er
      union all
      select icu_stay_id from cardiac_arrest_or_ie_diagnosis
      union all
      select icu_stay_id from no_recorded_vital_measurement
  )

select icu_stay_id, time0, organ_dysfunction_time, first_coagulopathy_time, coagulopathy_plt_criterion
from sepsis_org_coag
where icu_stay_id not in (select distinct icu_stay_id from exclusion_criteria)
