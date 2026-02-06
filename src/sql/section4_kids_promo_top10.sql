/* =========================
   section4_kids_promo_top10.sql
   ✅ promo_url(절대 URL) 컬럼 추가
   ✅ event 경로(url_key) 오류 수정
   ✅ promo_key 중복 방지(promo_map_dedup)
   ✅ GA4 스타일: 기획전 랜딩 세션 기준 유입/상품조회/구매/CVR/매출
   ✅ 구매 매출: item_id '7' 필터 제거
   ✅ 과집계 방지: purchase에서 EVENT_PARAMS x ITEMS 곱 제거(CTE 분리 후 JOIN)
   ========================= */

WITH promo_map AS (
  SELECT '1441' AS promo_key, 'collection' AS promo_type, '베이비 선물하기' AS promo_name, '/display/promotions/collection/1441' AS url_key
  UNION ALL SELECT '1387', 'collection', '트랙러너', '/display/promotions/collection/1387'
  UNION ALL SELECT '1407', 'collection', '루키 백팩&슈즈', '/display/promotions/collection/1407'
  UNION ALL SELECT '1410', 'collection', '걸스크루', '/display/promotions/collection/1410'
  UNION ALL SELECT '1440', 'collection', '패밀리 슈즈', '/display/promotions/collection/1440'
  UNION ALL SELECT '1449', 'collection', 'FW 셋업', '/display/promotions/collection/1449'
  UNION ALL SELECT '1464', 'collection', '바시티', '/display/promotions/collection/1464'
  UNION ALL SELECT '1465', 'collection', '신학기 볼캡', '/display/promotions/collection/1465'
  UNION ALL SELECT '1470', 'collection', '고학년 맨투맨&티셔츠', '/display/promotions/collection/1470'
  UNION ALL SELECT '1450', 'event', '경량패딩 테스트', '/display/promotions/event/1450'
  UNION ALL SELECT '1498', 'collection', '토들러 나들이룩', '/display/promotions/collection/1498'
  UNION ALL SELECT '1494', 'collection', '에어데일리 부츠', '/display/promotions/collection/1494'
  UNION ALL SELECT '1503', 'collection', '숏패딩', '/display/promotions/collection/1503'
  UNION ALL SELECT '1516', 'event', '이현이도', '/display/promotions/event/1516'
  UNION ALL SELECT '1542', 'collection', '바운서워머 부츠', '/display/promotions/collection/1542'
  UNION ALL SELECT '1526', 'collection', 'AI 겨울 레이어링', '/display/promotions/collection/1526'
  UNION ALL SELECT '1543', 'collection', '프리즘 걸스다운', '/display/promotions/collection/1543'
  UNION ALL SELECT '1553', 'collection', 'LIVE 사전알림 기획전(해리포터)', '/display/promotions/collection/1553'
  UNION ALL SELECT '1568', 'collection', '베이비 바디수트', '/display/promotions/collection/1568'
  UNION ALL SELECT '1571', 'collection', '저학년&고학년 책가방', '/display/promotions/collection/1571'
  UNION ALL SELECT '1572', 'collection', '고학년 책가방', '/display/promotions/collection/1572'
  UNION ALL SELECT '1585', 'collection', '딥윈터 페스타', '/display/promotions/collection/1585'
  UNION ALL SELECT '1579', 'event', '기프트 이벤트', '/display/promotions/event/1579'
  UNION ALL SELECT '1589', 'collection', '헤비다운', '/display/promotions/collection/1589'
  UNION ALL SELECT '1590', 'collection', '방한모&방한화', '/display/promotions/collection/1590'
  UNION ALL SELECT '1606', 'collection', '베이비 슈즈', '/display/promotions/collection/1606'
  UNION ALL SELECT '1617', 'collection', '키즈 패딩 15% 시즌오프', '/display/promotions/collection/1617'
  UNION ALL SELECT '1601', 'event', '소히조이 사전알림', '/display/promotions/event/1601'
  UNION ALL SELECT '1600', 'collection', '바시티 에프터 스쿨', '/display/promotions/collection/1600'
  UNION ALL SELECT '1607', 'collection', '바시티 아우터', '/display/promotions/collection/1607'
  UNION ALL SELECT '1628', 'collection', '메가베어 프렌즈 런칭', '/display/promotions/collection/1628'
  UNION ALL SELECT '1642', 'event', '설선물 기획전', '/display/promotions/event/1642'
),

promo_map_dedup AS (
  SELECT
    promo_key,
    ANY_VALUE(promo_type) AS promo_type,
    ANY_VALUE(promo_name) AS promo_name,
    ANY_VALUE(url_key)    AS url_key
  FROM promo_map
  GROUP BY promo_key
),

/* page_view / view_item에서 session_id + page_location 확보 */
events_with_location AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    e.EVENT_NAME,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    MAX(IFF(ep.value:key::STRING='page_location', ep.value:value:string_value::STRING, NULL)) AS page_location
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME IN ('page_view','view_item')
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP, e.EVENT_NAME
  HAVING session_id IS NOT NULL
),

/* 기획전 랜딩 세션(모집단) */
promo_sessions AS (
  SELECT
    ev.USER_PSEUDO_ID,
    ev.session_id,
    pm.promo_key,
    pm.promo_name,
    pm.url_key
  FROM events_with_location ev
  JOIN promo_map_dedup pm
    ON ev.EVENT_NAME='page_view'
   AND POSITION(pm.url_key IN ev.page_location) > 0
  GROUP BY ev.USER_PSEUDO_ID, ev.session_id, pm.promo_key, pm.promo_name, pm.url_key
),

/* 유입(세션) */
session_metrics AS (
  SELECT
    promo_key,
    COUNT(DISTINCT USER_PSEUDO_ID || '-' || session_id) AS promo_sessions
  FROM promo_sessions
  GROUP BY promo_key
),

/* 상품조회(세션) */
view_sessions AS (
  SELECT
    ps.promo_key,
    COUNT(DISTINCT ps.USER_PSEUDO_ID || '-' || ps.session_id) AS view_sessions
  FROM promo_sessions ps
  JOIN events_with_location ev
    ON ps.USER_PSEUDO_ID = ev.USER_PSEUDO_ID
   AND ps.session_id     = ev.session_id
   AND ev.EVENT_NAME     = 'view_item'
  GROUP BY ps.promo_key
),

/* ✅ purchase: session_id 추출(이벤트 단위) */
purchase_session AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

/* ✅ purchase: 매출 합산(이벤트 단위, item_id 7 필터 제거) */
purchase_revenue AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1),
        0
      )
    ) AS event_revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
),

/* ✅ purchase 이벤트 단위로 결합(카티전 곱 방지 완료) */
purchase_event_base AS (
  SELECT
    ps.USER_PSEUDO_ID,
    ps.EVENT_TIMESTAMP,
    ps.session_id,
    COALESCE(pr.event_revenue, 0) AS event_revenue
  FROM purchase_session ps
  LEFT JOIN purchase_revenue pr
    ON ps.USER_PSEUDO_ID = pr.USER_PSEUDO_ID
   AND ps.EVENT_TIMESTAMP = pr.EVENT_TIMESTAMP
),

/* 기획전 랜딩 세션 내 구매(세션) + 매출 */
promo_purchase AS (
  SELECT
    s.promo_key,
    COUNT(DISTINCT s.USER_PSEUDO_ID || '-' || s.session_id) AS purchase_sessions,
    SUM(peb.event_revenue) AS revenue
  FROM promo_sessions s
  JOIN purchase_event_base peb
    ON s.USER_PSEUDO_ID = peb.USER_PSEUDO_ID
   AND s.session_id     = peb.session_id
  GROUP BY s.promo_key
)

SELECT
  ROW_NUMBER() OVER (
    ORDER BY COALESCE(pp.revenue,0) DESC,
             COALESCE(vs.view_sessions,0) DESC,
             sm.promo_sessions DESC
  ) AS rank,
  sm.promo_key AS promo_no,
  pm.promo_name,
  'https://www.mlb-korea.com' || pm.url_key AS promo_url,

  sm.promo_sessions                  AS promo_sessions,      -- 유입(세션)
  COALESCE(vs.view_sessions, 0)      AS view_sessions,       -- 상품조회(세션)
  COALESCE(pp.purchase_sessions, 0)  AS purchase_sessions,   -- 구매(세션)

  /* CVR = 구매세션 / 유입세션 (GA4 스타일) */
  CASE
    WHEN sm.promo_sessions = 0 THEN 0
    ELSE ROUND((COALESCE(pp.purchase_sessions,0)::FLOAT / sm.promo_sessions::FLOAT) * 100, 2)
  END AS purchase_cvr_pct,

  COALESCE(pp.revenue, 0) AS revenue

FROM session_metrics sm
JOIN promo_map_dedup pm
  ON sm.promo_key = pm.promo_key
LEFT JOIN view_sessions vs
  ON sm.promo_key = vs.promo_key
LEFT JOIN promo_purchase pp
  ON sm.promo_key = pp.promo_key

ORDER BY revenue DESC, view_sessions DESC, promo_sessions DESC
LIMIT 10;
