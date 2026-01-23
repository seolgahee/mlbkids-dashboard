WITH purchase_kids AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING = 'ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id,

    /* 키즈 전환 매출 */
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
    AND it.value:item_id::STRING LIKE '7%%'     -- ✅ 키즈 상품만
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP
  HAVING session_id IS NOT NULL
),

session_touch AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING = 'ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id,
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
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP, e.COLLECTED_TRAFFIC_SOURCE, e.TRAFFIC_SOURCE
  HAVING session_id IS NOT NULL
),

session_dim AS (
  SELECT
    USER_PSEUDO_ID,
    session_id,
    COALESCE(NULLIF(source,''), '(not set)')   AS source,
    COALESCE(NULLIF(medium,''), '(not set)')   AS medium,
    COALESCE(NULLIF(campaign,''), '(not set)') AS campaign
  FROM session_touch
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY USER_PSEUDO_ID, session_id
    ORDER BY EVENT_TIMESTAMP ASC
  ) = 1
)

SELECT
  d.source || ' / ' || d.medium AS source_medium,

  CASE
    WHEN LEFT(UPPER(TRIM(d.campaign)), 2) IN ('I_', 'M_') THEN '광고'
    WHEN LOWER(d.source) = '(direct)' AND LOWER(d.medium) = '(none)' THEN '직접'
    ELSE '자연'
  END AS inflow_type,

  COUNT(DISTINCT p.USER_PSEUDO_ID || '-' || p.session_id) AS sessions,
  SUM(p.revenue) AS revenue

FROM purchase_kids p
JOIN session_dim d
  ON p.USER_PSEUDO_ID = d.USER_PSEUDO_ID
 AND p.session_id     = d.session_id

GROUP BY 1,2
ORDER BY revenue DESC, sessions DESC
LIMIT 10;