/* 1) 키즈 상품을 본 세션(=GA 아이템 필터 세션수에 가장 근접) */
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
    AND e.EVENT_NAME = 'view_item'
    AND it.value:item_id::STRING LIKE '7%%'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),
kids_sessions AS (
  SELECT USER_PSEUDO_ID, session_id, MIN(first_ts) AS first_ts
  FROM kids_view_sessions
  GROUP BY 1,2
),

/* 2) 세션 유입정보: session_start 우선, 없으면 page_view fallback (GA에 근접) */
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

/* 3) 키즈 상품 매출: purchase 중 item_id 7%만 */
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
  d.source || ' / ' || d.medium AS source_medium,
  COUNT(DISTINCT k.USER_PSEUDO_ID || '-' || k.session_id) AS sessions,
  COALESCE(SUM(r.revenue), 0) AS revenue
FROM kids_sessions k
LEFT JOIN session_dim_one d
  ON k.USER_PSEUDO_ID=d.USER_PSEUDO_ID AND k.session_id=d.session_id
LEFT JOIN kids_revenue_sess r
  ON k.USER_PSEUDO_ID=r.USER_PSEUDO_ID AND k.session_id=r.session_id
GROUP BY 1
ORDER BY sessions DESC, revenue DESC;
