/* 키즈 상품(view_item) 포함 세션 기준: 소스/매체 TOP 10
   + 유입유형(자연/광고/직접) + 매출 기준 정렬
   ✅ B안 확장: 특정 소스/매체는 무조건 '광고'로 고정 (datarize/brandmessage, kakaofriend/message 등) */

WITH kids_view_sessions AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    MIN(e.EVENT_TIMESTAMP) AS first_ts
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

kids_sessions AS (
  SELECT USER_PSEUDO_ID, session_id, MIN(first_ts) AS first_ts
  FROM kids_view_sessions
  GROUP BY 1,2
),

session_start_dim AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,

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
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,

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
),

kids_revenue AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER,0)*COALESCE(it.value:quantity::NUMBER,1),
        0
      )
    ) AS revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input=>e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input=>e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
    AND it.value:item_id::STRING LIKE '7%%'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

kids_revenue_sess AS (
  SELECT USER_PSEUDO_ID, session_id, SUM(revenue) AS revenue
  FROM kids_revenue
  GROUP BY 1,2
)

SELECT
  /* 소스/매체 */
  COALESCE(d.source,'(not set)') || ' / ' || COALESCE(d.medium,'(not set)') AS source_medium,

  /* ✅ 유입유형 (B안 확장) */
  CASE
    /* 1) 무조건 광고로 고정할 소스/매체 */
    WHEN LOWER(COALESCE(d.source,'')) = 'datarize'
     AND LOWER(COALESCE(d.medium,'')) = 'brandmessage' THEN '광고'

    WHEN LOWER(COALESCE(d.source,'')) = 'kakaofriend'
     AND LOWER(COALESCE(d.medium,'')) = 'message' THEN '광고'

    /* 필요하면 여기 계속 추가 (예: kakaofriend/smart_chat도 광고로 고정하고 싶으면 아래 주석 해제)
    WHEN LOWER(COALESCE(d.source,'')) = 'kakaofriend'
     AND LOWER(COALESCE(d.medium,'')) = 'smart_chat' THEN '광고'
    */

    /* 2) 캠페인 네이밍 규칙(I_/M_)이면 광고 */
    WHEN LEFT(UPPER(TRIM(COALESCE(d.campaign,''))), 2) IN ('I_', 'M_') THEN '광고'

    /* 3) direct/none이면 직접 */
    WHEN LOWER(COALESCE(d.source,'(not set)')) = '(direct)'
     AND LOWER(COALESCE(d.medium,'(not set)')) = '(none)' THEN '직접'

    /* 4) 그 외 자연 */
    ELSE '자연'
  END AS inflow_type,

  /* 세션수 */
  COUNT(DISTINCT k.USER_PSEUDO_ID || '-' || k.session_id) AS sessions,

  /* 키즈 매출 */
  COALESCE(SUM(r.revenue), 0) AS revenue

FROM kids_sessions k
LEFT JOIN session_dim_one d
  ON k.USER_PSEUDO_ID=d.USER_PSEUDO_ID AND k.session_id=d.session_id
LEFT JOIN kids_revenue_sess r
  ON k.USER_PSEUDO_ID=r.USER_PSEUDO_ID AND k.session_id=r.session_id

GROUP BY 1,2
ORDER BY revenue DESC, sessions DESC
LIMIT 10;
