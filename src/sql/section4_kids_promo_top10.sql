/* =========================
   section4_kids_promo_top10.sql
   ✅ promo_url(절대 URL) 컬럼 추가
   ✅ event 경로(url_key) 오류 수정
   ========================= */

WITH promo_map AS (
  /* promo_key(숫자), promo_type(collection/event), promo_name, url_key(상대경로) */
  SELECT '1441' AS promo_key, 'collection' AS promo_type, '베이비 선물하기' AS promo_name, '/display/promotions/collection/1441' AS url_key
  UNION ALL SELECT '1387', 'collection', '트랙러너', '/display/promotions/collection/1387'
  UNION ALL SELECT '1407', 'collection', '루키 백팩&슈즈', '/display/promotions/collection/1407'
  UNION ALL SELECT '1410', 'collection', '걸스크루', '/display/promotions/collection/1410'
  UNION ALL SELECT '1440', 'collection', '패밀리 슈즈', '/display/promotions/collection/1440'
  UNION ALL SELECT '1449', 'collection', 'FW 셋업', '/display/promotions/collection/1449'
  UNION ALL SELECT '1464', 'collection', '바시티', '/display/promotions/collection/1464'
  UNION ALL SELECT '1465', 'collection', '신학기 볼캡', '/display/promotions/collection/1465'
  UNION ALL SELECT '1470', 'collection', '고학년 맨투맨&티셔츠', '/display/promotions/collection/1470'

  /* ✅ event는 event 경로 */
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

/* 기획전 유입 세션(모집단) */
promo_sessions AS (
  SELECT
    ev.USER_PSEUDO_ID,
    ev.session_id,
    pm.promo_key,
    pm.promo_name,
    pm.url_key
  FROM events_with_location ev
  JOIN promo_map pm
    ON ev.EVENT_NAME='page_view'
   AND POSITION(pm.url_key IN ev.page_location) > 0
  GROUP BY ev.USER_PSEUDO_ID, ev.session_id, pm.promo_key, pm.promo_name, pm.url_key
),

/* 분모: 기획전 유입 세션 내 view_item 이벤트 수 */
view_item_events AS (
  SELECT
    ps.promo_key,
    COUNT(*) AS view_item_events
  FROM promo_sessions ps
  JOIN events_with_location ev
    ON ps.USER_PSEUDO_ID = ev.USER_PSEUDO_ID
   AND ps.session_id     = ev.session_id
   AND ev.EVENT_NAME     = 'view_item'
  GROUP BY ps.promo_key
),

/* purchase 이벤트: 이벤트 단위 매출(키즈 item만) */
purchase_event_base AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1),
        0
      )
    ) AS event_revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
    AND LEFT(it.value:item_id::STRING, 1) = '7'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

/* 분자: 기획전 유입 세션 내 purchase 이벤트 수 + 매출 */
promo_purchase_events AS (
  SELECT
    ps.promo_key,
    COUNT(DISTINCT peb.USER_PSEUDO_ID || '-' || peb.session_id || '-' || peb.EVENT_TIMESTAMP) AS purchase_events,
    SUM(peb.event_revenue) AS revenue
  FROM promo_sessions ps
  JOIN purchase_event_base peb
    ON ps.USER_PSEUDO_ID = peb.USER_PSEUDO_ID
   AND ps.session_id     = peb.session_id
  GROUP BY ps.promo_key
),

/* 세션 지표 */
session_metrics AS (
  SELECT
    ps.promo_key,
    COUNT(DISTINCT ps.USER_PSEUDO_ID || '-' || ps.session_id) AS promo_sessions,
    COUNT(DISTINCT CASE WHEN ev.EVENT_NAME='view_item' THEN ps.USER_PSEUDO_ID || '-' || ps.session_id END) AS view_sessions
  FROM promo_sessions ps
  LEFT JOIN events_with_location ev
    ON ps.USER_PSEUDO_ID = ev.USER_PSEUDO_ID
   AND ps.session_id     = ev.session_id
   AND ev.EVENT_NAME     = 'view_item'
  GROUP BY ps.promo_key
),

purchase_sessions AS (
  SELECT
    ps.promo_key,
    COUNT(DISTINCT ps.USER_PSEUDO_ID || '-' || ps.session_id) AS purchase_sessions
  FROM promo_sessions ps
  JOIN purchase_event_base peb
    ON ps.USER_PSEUDO_ID = peb.USER_PSEUDO_ID
   AND ps.session_id     = peb.session_id
  GROUP BY ps.promo_key
)

SELECT
  ROW_NUMBER() OVER (ORDER BY COALESCE(ppe.revenue,0) DESC, COALESCE(sm.view_sessions,0) DESC) AS rank,
  sm.promo_key AS promo_no,
  pm.promo_name,

  /* ✅ 절대 URL(행별 링크) */
  'https://www.mlb-korea.com' || pm.url_key AS promo_url,

  sm.promo_sessions,
  sm.view_sessions,
  COALESCE(pss.purchase_sessions, 0) AS purchase_sessions,
  CASE
    WHEN COALESCE(vie.view_item_events, 0) = 0 THEN 0
    ELSE ROUND((COALESCE(ppe.purchase_events, 0)::FLOAT / vie.view_item_events::FLOAT) * 100, 2)
  END AS purchase_cvr_pct,
  COALESCE(ppe.revenue, 0) AS revenue
FROM session_metrics sm
JOIN promo_map pm
  ON sm.promo_key = pm.promo_key
LEFT JOIN view_item_events vie
  ON sm.promo_key = vie.promo_key
LEFT JOIN promo_purchase_events ppe
  ON sm.promo_key = ppe.promo_key
LEFT JOIN purchase_sessions pss
  ON sm.promo_key = pss.promo_key
ORDER BY revenue DESC, view_sessions DESC
LIMIT 10;
