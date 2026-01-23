WITH purchase_kids AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(
      IFF(
        ep.value:key::STRING = 'ga_session_id',
        ep.value:value:int_value::NUMBER,
        NULL
      )
    ) AS session_id,

    -- 키즈 상품 매출
    SUM(
      COALESCE(
        it.value:item_revenue::NUMBER,
        COALESCE(it.value:price::NUMBER, 0)
        * COALESCE(it.value:quantity::NUMBER, 1)
      )
    ) AS revenue

  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME = 'purchase'
    AND it.value:item_id::STRING LIKE '7%%'   -- ✅ 키즈 상품
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

session_touch AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(
      IFF(
        ep.value:key::STRING = 'ga_session_id',
        ep.value:value:int_value::NUMBER,
        NULL
      )
    ) AS session_id,
    e.EVENT_TIMESTAMP,

    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0], 'manual_source')::STRING, ''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0], 'source')::STRING, '')
    ) AS source,

    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0], 'manual_medium')::STRING, ''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0], 'medium')::STRING, '')
    ) AS medium,

    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0], 'manual_campaign_name')::STRING, ''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0], 'name')::STRING, '')
    ) AS campaign

  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME IN ('session_start', 'page_view')
  GROUP BY
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    e.COLLECTED_TRAFFIC_SOURCE,
    e.TRAFFIC_SOURCE
  HAVING session_id IS NOT NULL
),

session_dim AS (
  SELECT
    USER_PSEUDO_ID,
    session_id,
    COALESCE(NULLIF(source, ''), '(direct)')  AS source,
    COALESCE(NULLIF(medium, ''), '(none)')    AS medium,
    COALESCE(NULLIF(campaign, ''), '')        AS campaign
  FROM session_touch
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY USER_PSEUDO_ID, session_id
    ORDER BY EVENT_TIMESTAMP ASC
  ) = 1
)

SELECT
  '#' || ROW_NUMBER() OVER (ORDER BY SUM(p.revenue) DESC) AS 순위,

  d.source || ' / ' || d.medium AS "소스 / 매체",

  CASE
    WHEN LEFT(UPPER(TRIM(d.campaign)), 2) IN ('I_', 'M_')
      THEN '광고'
    WHEN LOWER(d.source) = '(direct)' AND LOWER(d.medium) = '(none)'
      THEN '직접'
    ELSE '자연'
  END AS "유입 유형",

  COUNT(DISTINCT d.session_id) AS "세션 수",

  SUM(p.revenue) AS "매출"

FROM purchase_kids p
JOIN session_dim d
  ON p.USER_PSEUDO_ID = d.USER_PSEUDO_ID
 AND p.session_id     = d.session_id

GROUP BY
  d.source,
  d.medium,
  d.campaign

ORDER BY 매출 DESC
LIMIT 10;
