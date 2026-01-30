WITH purchase_items AS (
  -- 1) 구매 이벤트에서 "키즈 상품(7%)"만 먼저 필터링 + 매출 계산
  SELECT
    e.USER_PSEUDO_ID,

    MAX(
      IFF(ep.value:key::STRING = 'ga_session_id',
          ep.value:value:int_value::NUMBER, NULL)
    ) AS session_id,

    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        (COALESCE(it.value:price::NUMBER, 0) * COALESCE(it.value:quantity::NUMBER, 1)),
        0
      )
    ) AS revenue

  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME = 'purchase'
    AND it.value:item_id::STRING LIKE '7%%'   -- ✅ 키즈 상품만
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

purchase_session AS (
  -- 2) 세션 단위로 매출 확정(중복/뭉침 방지)
  SELECT
    USER_PSEUDO_ID,
    session_id,
    SUM(revenue) AS revenue
  FROM purchase_items
  GROUP BY 1,2
),

pv AS (
  -- 3) 세션 이벤트에서 캠페인 가져오기
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    e.EVENT_PARAMS,
    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0], 'manual_campaign_name')::STRING, ''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0], 'name')::STRING, '')
    ) AS campaign
  FROM FNF.STRG_GA.EVENTS e
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME IN ('page_view','session_start')
),

pv_with_session AS (
  SELECT
    USER_PSEUDO_ID,
    COALESCE(NULLIF(campaign,''),'(not set)') AS campaign,

    MAX(
      IFF(ep.value:key::STRING = 'ga_session_id',
          ep.value:value:int_value::NUMBER, NULL)
    ) AS session_id,

    MIN(EVENT_TIMESTAMP) AS first_ts

  FROM pv,
       LATERAL FLATTEN(input => EVENT_PARAMS) ep
  GROUP BY 1,2
),

session_dim AS (
  -- 4) 세션당 1개 캠페인 확정
  SELECT
    USER_PSEUDO_ID,
    session_id,
    campaign
  FROM pv_with_session
  WHERE session_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY USER_PSEUDO_ID, session_id
    ORDER BY first_ts ASC
  ) = 1
)

-- 5) 키즈 상품 매출 세션에 캠페인을 붙여서 I_ vs 그 외로 분리
SELECT
  CASE
    WHEN LEFT(UPPER(TRIM(d.campaign)), 2) = 'I_' THEN '키즈 광고'
    ELSE '키즈 광고가 아닌것'
  END AS bucket,
  SUM(p.revenue) AS revenue
FROM purchase_session p
JOIN session_dim d
  ON p.USER_PSEUDO_ID = d.USER_PSEUDO_ID
 AND p.session_id     = d.session_id
GROUP BY 1
ORDER BY revenue DESC;