WITH promo_map AS (
  SELECT '1441' AS promo_key, '베이비 선물하기' AS promo_name, '/display/promotions/collection/1441' AS url_key
  UNION ALL SELECT '1387', '트랙러너', '/display/promotions/collection/1387'
  UNION ALL SELECT '1407', '루키 백팩&슈즈', '/display/promotions/collection/1407'
  UNION ALL SELECT '1410', '걸스크루', '/display/promotions/collection/1410'
  UNION ALL SELECT '1440', '패밀리 슈즈', '/display/promotions/collection/1440'
  UNION ALL SELECT '1449', 'FW 셋업', '/display/promotions/collection/1449'
  UNION ALL SELECT '1464', '바시티', '/display/promotions/collection/1464'
  UNION ALL SELECT '1465', '신학기 볼캡', '/display/promotions/collection/1465'
  UNION ALL SELECT '1470', '고학년 맨투맨&티셔츠', '/display/promotions/collection/1470'
  UNION ALL SELECT 'event/1450', '경량패딩 테스트', '/display/promotions/collection/event/1450'
  UNION ALL SELECT '1498', '토들러 나들이룩', '/display/promotions/collection/1498'
  UNION ALL SELECT '1494', '에어데일리 부츠', '/display/promotions/collection/1494'
  UNION ALL SELECT '1503', '숏패딩', '/display/promotions/collection/1503'
  UNION ALL SELECT 'event/1516', '이현이도', '/display/promotions/collection/event/1516'
  UNION ALL SELECT '1542', '바운서워머 부츠', '/display/promotions/collection/1542'
  UNION ALL SELECT '1526', 'AI 겨울 레이어링', '/display/promotions/collection/1526'
  UNION ALL SELECT '1543', '프리즘 걸스다운', '/display/promotions/collection/1543'
  UNION ALL SELECT '1553', 'LIVE 사전알림 기획전(해리포터)', '/display/promotions/collection/1553'
  UNION ALL SELECT '1568', '베이비 바디수트', '/display/promotions/collection/1568'
  UNION ALL SELECT '1571', '저학년&고학년 책가방', '/display/promotions/collection/1571'
  UNION ALL SELECT '1572', '고학년 책가방', '/display/promotions/collection/1572'
  UNION ALL SELECT '1585', '딥윈터 페스타', '/display/promotions/collection/1585'
  UNION ALL SELECT 'event/1579', '기프트 이벤트', '/display/promotions/collection/event/1579'
  UNION ALL SELECT '1589', '헤비다운', '/display/promotions/collection/1589'
  UNION ALL SELECT '1590', '방한모&방한화', '/display/promotions/collection/1590'
  UNION ALL SELECT '1606', '베이비 슈즈', '/display/promotions/collection/1606'
  UNION ALL SELECT '1617', '키즈 패딩 15% 시즌오프', '/display/promotions/collection/1617'
  UNION ALL SELECT '1600', '바시티 기획전', '/display/promotions/collection/1600'
  UNION ALL SELECT 'event/1601', '소히조이 사전알림', '/display/promotions/event/1601'
),

-- page_location + session_id (page_view / view_item)
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

-- 기획전 유입 세션(모집단)
promo_pageviews AS (
  SELECT
    ev.USER_PSEUDO_ID,
    ev.session_id,
    pm.promo_key,
    pm.promo_name
  FROM events_with_location ev
  JOIN promo_map pm
    ON ev.EVENT_NAME='page_view'
   AND POSITION(pm.url_key IN ev.page_location) > 0
  GROUP BY ev.USER_PSEUDO_ID, ev.session_id, pm.promo_key, pm.promo_name
),

-- ✅ (세션) 상품조회 여부
promo_view_session AS (
  SELECT
    ev.USER_PSEUDO_ID,
    ev.session_id,
    1 AS has_view_item
  FROM events_with_location ev
  WHERE ev.EVENT_NAME='view_item'
  GROUP BY ev.USER_PSEUDO_ID, ev.session_id
),

-- ✅ (세션) 구매 여부 + 매출 (키즈)
promo_purchase_session AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    1 AS has_purchase,
    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1),
        0
      )
    ) AS revenue
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

/* =========================
   ✅ B안: 이벤트 기준 CVR
   - 분모: 기획전 유입 세션 내 view_item 이벤트 수
   - 분자: 기획전 유입 세션 내 purchase 이벤트 수 (키즈 상품 구매 이벤트)
   ========================= */

-- ✅ 분모: view_item 이벤트 수 (기획전 유입 세션 내)
promo_view_item_events AS (
  SELECT
    ppg.promo_key,
    ppg.promo_name,
    COUNT(*) AS view_item_events
  FROM promo_pageviews ppg
  JOIN events_with_location ev
    ON ppg.USER_PSEUDO_ID = ev.USER_PSEUDO_ID
   AND ppg.session_id     = ev.session_id
   AND ev.EVENT_NAME      = 'view_item'
  GROUP BY ppg.promo_key, ppg.promo_name
),

-- ✅ 분자: purchase 이벤트 수 + 매출 (기획전 유입 세션 내, 키즈 상품만)
promo_purchase_events AS (
  SELECT
    ppg.promo_key,
    ppg.promo_name,

    COUNT(DISTINCT e.USER_PSEUDO_ID || '-' ||
      MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) || '-' ||
      e.EVENT_TIMESTAMP
    ) AS purchase_events,

    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1),
        0
      )
    ) AS revenue
  FROM promo_pageviews ppg
  JOIN FNF.STRG_GA.EVENTS e
    ON ppg.USER_PSEUDO_ID = e.USER_PSEUDO_ID
  , LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  , LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
    AND LEFT(it.value:item_id::STRING, 1) = '7'
    -- 구매 이벤트가 "해당 기획전 유입 세션"에서 발생한 것만
    AND MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) = ppg.session_id
  GROUP BY ppg.promo_key, ppg.promo_name
),

-- ✅ 기획전 단위 집계
promo_agg AS (
  SELECT
    ppg.promo_key AS promo_no,
    ppg.promo_name,

    -- 세션 기반 지표(기존 유지)
    COUNT(DISTINCT ppg.USER_PSEUDO_ID || '-' || ppg.session_id) AS promo_sessions,

    COUNT(DISTINCT
      CASE WHEN pvs.has_view_item = 1
           THEN ppg.USER_PSEUDO_ID || '-' || ppg.session_id
      END
    ) AS view_sessions,

    COUNT(DISTINCT
      CASE WHEN pps.has_purchase = 1
           THEN ppg.USER_PSEUDO_ID || '-' || ppg.session_id
      END
    ) AS purchase_sessions,

    -- 이벤트 기반 지표(B안)
    COALESCE(pvie.view_item_events, 0) AS view_item_events,
    COALESCE(ppe.purchase_events, 0)   AS purchase_events,

    -- ✅ B안 CVR (소수점 2자리)
    CASE
      WHEN COALESCE(pvie.view_item_events, 0) = 0 THEN 0
      ELSE ROUND(
        (COALESCE(ppe.purchase_events, 0)::FLOAT / pvie.view_item_events::FLOAT) * 100
      , 2)
    END AS purchase_cvr_pct,

    -- 매출은 purchase 이벤트 기반 집계 값 사용 (세션 구매 매출과 거의 동일하지만 이벤트 기준이 더 일관됨)
    COALESCE(ppe.revenue, 0) AS revenue

  FROM promo_pageviews ppg
  LEFT JOIN promo_view_session pvs
    ON ppg.USER_PSEUDO_ID = pvs.USER_PSEUDO_ID
   AND ppg.session_id     = pvs.session_id

  LEFT JOIN promo_purchase_session pps
    ON ppg.USER_PSEUDO_ID = pps.USER_PSEUDO_ID
   AND ppg.session_id     = pps.session_id

  LEFT JOIN promo_view_item_events pvie
    ON ppg.promo_key = pvie.promo_key

  LEFT JOIN promo_purchase_events ppe
    ON ppg.promo_key = ppe.promo_key

  GROUP BY
    ppg.promo_key, ppg.promo_name,
    pvie.view_item_events,
    ppe.purchase_events,
    ppe.revenue
)

SELECT
  ROW_NUMBER() OVER (ORDER BY revenue DESC, view_sessions DESC) AS rank,
  promo_no,
  promo_name,
  promo_sessions,
  view_sessions,
  purchase_sessions,
  purchase_cvr_pct,
  revenue
FROM promo_agg
ORDER BY revenue DESC, view_sessions DESC
LIMIT 10;
