/* ==========================================================
   sectionX_kids_source_medium_ga4_align.sql
   ✅ GA4 정합용: "상품단(아이템ID 7*) + 세션 소스/매체" 기준 TOP10
   - 모집단: purchase 이벤트에서 item_id LIKE '7%'
   - 매출: purchase.items 중 item_id '7%'만 합산
   - users: 구매 발생 사용자수 (distinct user_pseudo_id)
   - sessions: 구매 발생 세션수 (distinct user_pseudo_id + session_id)
   - source/medium: session_start 우선, 없으면 page_view로 보강(첫 ts)
   ========================================================== */

WITH
/* 1) purchase에서 세션ID 추출 (이벤트 단위) */
purchase_sess AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    MAX(IFF(ep.value:key::STRING='ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

/* 2) purchase 아이템에서 "키즈(7%) 매출"만 합산 (이벤트 단위) */
purchase_kids_rev AS (
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
    ) AS kids_revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
),

/* 3) purchase 이벤트 단위로 결합 + kids_revenue>0만 남김(= 실제로 7% 구매된 이벤트만) */
kids_purchase_events AS (
  SELECT
    ps.USER_PSEUDO_ID,
    ps.session_id,
    ps.EVENT_TIMESTAMP,
    pr.kids_revenue
  FROM purchase_sess ps
  JOIN purchase_kids_rev pr
    ON ps.USER_PSEUDO_ID = pr.USER_PSEUDO_ID
   AND ps.EVENT_TIMESTAMP = pr.EVENT_TIMESTAMP
  WHERE COALESCE(pr.kids_revenue,0) > 0
),

/* 4) 구매 세션(사용자+세션) 단위로 매출 합산 */
kids_purchase_sessions AS (
  SELECT
    USER_PSEUDO_ID,
    session_id,
    SUM(kids_revenue) AS kids_revenue
  FROM kids_purchase_events
  GROUP BY 1,2
),

/* 5) 세션 시작 시점의 source/medium/campaign 확보
   - GA4 세션 소스/매체는 보통 session_start 기준이 맞음
   - 누락 시 page_view로 보강 */
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
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    /* 세션 시작이 start_date 전날에 찍힐 수 있어 버퍼 */
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
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
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

SELECT
  /* 소스/매체 */
  COALESCE(d.source,'(not set)') || ' / ' || COALESCE(d.medium,'(not set)') AS source_medium,

  /* 유입유형: GA4 정합용(원하면 GA default channel group로도 확장 가능) */
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

  /* ✅ GA4 상품단 기준: 구매 사용자/세션 */
  COUNT(DISTINCT k.USER_PSEUDO_ID) AS users,
  COUNT(DISTINCT k.USER_PSEUDO_ID || '-' || k.session_id) AS sessions,

  /* ✅ GA4 상품단 기준: item_id 7% 구매 매출 */
  SUM(k.kids_revenue) AS revenue

FROM kids_purchase_sessions k
LEFT JOIN session_dim_one d
  ON k.USER_PSEUDO_ID=d.USER_PSEUDO_ID
 AND k.session_id=d.session_id

GROUP BY 1,2
ORDER BY revenue DESC, sessions DESC
LIMIT 10;
