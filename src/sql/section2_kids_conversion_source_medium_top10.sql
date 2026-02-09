/* ==========================================================
   section2_kids_conversion_source_medium_top10.sql
   ✅ GA4 유사 정합 (FIX)
   - users/sessions: view_item(7%) 세션 기준
   - revenue: purchase items(7%) 매출 기준
   - source/medium: session_start 우선, 없으면 page_view로 보강
   - 과집계 방지: (user, session) 단위로 먼저 dedup 후 join
   ========================================================== */

WITH
/* 1) 키즈 상품(7%) view_item 발생 세션 (GA4의 사용자/세션 분모에 가깝게) */
kids_view_sessions_raw AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input=>e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='view_item'
    AND it.value:item_id::STRING LIKE '7%%'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

kids_view_sess AS (
  SELECT USER_PSEUDO_ID, session_id
  FROM kids_view_sessions_raw
  GROUP BY 1,2
),

/* 2) 키즈 상품(7%) purchase 매출(아이템 기준) */
kids_purchase_event_rev AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    SUM(
      CASE
        WHEN it.value:item_id::STRING LIKE '7%%' THEN
          COALESCE(
            it.value:item_revenue::NUMBER,
            COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1),
            0
          )
        ELSE 0
      END
    ) AS revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
),

/* 3) purchase 이벤트에서 session_id 추출 (EVENT_PARAMS에서) */
purchase_event_sess AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    MAX(IFF(ep.value:key::STRING='ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

/* 4) purchase 이벤트 단위로 결합 후, 세션 단위로 매출 집계 (user,session 1행) */
kids_revenue_sess AS (
  SELECT
    ps.USER_PSEUDO_ID,
    ps.session_id,
    SUM(COALESCE(pr.revenue,0)) AS revenue
  FROM purchase_event_sess ps
  JOIN kids_purchase_event_rev pr
    ON ps.USER_PSEUDO_ID  = pr.USER_PSEUDO_ID
   AND ps.EVENT_TIMESTAMP = pr.EVENT_TIMESTAMP
  WHERE COALESCE(pr.revenue,0) > 0  -- 7% 상품이 실제로 팔린 이벤트만
  GROUP BY 1,2
),

/* 5) session_start 기반 소스/매체 (없으면 page_view로 보강) */
session_start_dim AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_source')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'source')::STRING,''), '(not set)') AS source,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_medium')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'medium')::STRING,''), '(not set)') AS medium,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_campaign_name')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'name')::STRING,''), '(not set)') AS campaign,

    MIN(e.EVENT_TIMESTAMP) AS ts
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN TO_CHAR(DATEADD(day,-1,TO_DATE(%(start_date)s,'YYYYMMDD')),'YYYYMMDD')
                     AND %(end_date)s
    AND e.EVENT_NAME='session_start'
  GROUP BY e.USER_PSEUDO_ID, e.COLLECTED_TRAFFIC_SOURCE, e.TRAFFIC_SOURCE
  HAVING session_id IS NOT NULL
),

page_view_dim AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_source')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'source')::STRING,''), '(not set)') AS source,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_medium')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'medium')::STRING,''), '(not set)') AS medium,

    COALESCE(NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_campaign_name')::STRING,''),
             NULLIF(GET(e.TRAFFIC_SOURCE[0],'name')::STRING,''), '(not set)') AS campaign,

    MIN(e.EVENT_TIMESTAMP) AS ts
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN TO_CHAR(DATEADD(day,-1,TO_DATE(%(start_date)s,'YYYYMMDD')),'YYYYMMDD')
                     AND %(end_date)s
    AND e.EVENT_NAME='page_view'
  GROUP BY e.USER_PSEUDO_ID, e.COLLECTED_TRAFFIC_SOURCE, e.TRAFFIC_SOURCE
  HAVING session_id IS NOT NULL
),

session_dim AS (
  SELECT * FROM session_start_dim
  UNION ALL
  SELECT p.*
  FROM page_view_dim p
  LEFT JOIN session_start_dim s
    ON p.USER_PSEUDO_ID=s.USER_PSEUDO_ID AND p.session_id=s.session_id
  WHERE s.session_id IS NULL
),

session_dim_one AS (
  SELECT USER_PSEUDO_ID, session_id, source, medium, campaign
  FROM session_dim
  QUALIFY ROW_NUMBER() OVER (PARTITION BY USER_PSEUDO_ID, session_id ORDER BY ts ASC)=1
)

/* 6) 최종: users/sessions는 view 기준, revenue는 purchase(7%) 기준 */
SELECT
  COALESCE(d.source,'(not set)') || ' / ' || COALESCE(d.medium,'(not set)') AS source_medium,

  CASE
    WHEN LOWER(COALESCE(d.source,'')) = 'datarize'
     AND LOWER(COALESCE(d.medium,'')) = 'brandmessage' THEN '광고'
    WHEN LOWER(COALESCE(d.source,'')) = 'kakaofriend'
     AND LOWER(COALESCE(d.medium,'')) = 'message' THEN '광고'
    WHEN LEFT(UPPER(TRIM(COALESCE(d.campaign,''))), 2) IN ('I_', 'M_') THEN '광고'
    WHEN LOWER(COALESCE(d.source,'(not set)')) = '(direct)'
     AND LOWER(COALESCE(d.medium,'(not set)')) = '(none)' THEN '직접'
    ELSE '자연'
  END AS inflow_type,

  COUNT(DISTINCT v.USER_PSEUDO_ID) AS users,
  COUNT(DISTINCT v.USER_PSEUDO_ID || '-' || v.session_id) AS sessions,

  /* ✅ (user,session) 1행인 r를 (user,session) 1행인 v에 붙이므로 과집계 없음 */
  COALESCE(SUM(r.revenue),0) AS revenue

FROM kids_view_sess v
LEFT JOIN session_dim_one d
  ON v.USER_PSEUDO_ID=d.USER_PSEUDO_ID
 AND v.session_id=d.session_id
LEFT JOIN kids_revenue_sess r
  ON v.USER_PSEUDO_ID=r.USER_PSEUDO_ID
 AND v.session_id=r.session_id

GROUP BY 1,2
ORDER BY revenue DESC, sessions DESC
LIMIT 10;
