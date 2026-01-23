WITH purchase_kids AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING = 'ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    COALESCE(
      it.value:item_revenue::NUMBER,
      (COALESCE(it.value:price::NUMBER, 0) * COALESCE(it.value:quantity::NUMBER, 1)),
      0
    ) AS revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %s AND %s
    AND e.EVENT_NAME = 'purchase'
    AND it.value:item_id::STRING LIKE '7%%'
  GROUP BY
    e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP,
    it.value:item_revenue::NUMBER, it.value:price::NUMBER, it.value:quantity::NUMBER
  HAVING session_id IS NOT NULL
),

pv AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_PARAMS,
    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0], 'manual_campaign_name')::STRING, ''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0], 'name')::STRING, '')
    ) AS campaign
  FROM FNF.STRG_GA.EVENTS e
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %s AND %s
    AND e.EVENT_NAME IN ('page_view','session_start')
),

pv_with_session AS (
  SELECT
    USER_PSEUDO_ID,
    COALESCE(NULLIF(campaign,''),'(not set)') AS campaign,
    MAX(IFF(ep.value:key::STRING = 'ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id
  FROM pv,
       LATERAL FLATTEN(input => EVENT_PARAMS) ep
  GROUP BY 1,2
),

session_dim AS (
  SELECT
    USER_PSEUDO_ID,
    session_id,
    campaign
  FROM pv_with_session
  WHERE session_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY USER_PSEUDO_ID, session_id
    ORDER BY USER_PSEUDO_ID
  ) = 1
),

joined AS (
  SELECT
    p.revenue,
    d.campaign
  FROM purchase_kids p
  JOIN session_dim d
    ON p.USER_PSEUDO_ID = d.USER_PSEUDO_ID
   AND p.session_id     = d.session_id
),

agg AS (
  SELECT
    CASE
      WHEN LEFT(UPPER(TRIM(campaign)), 2) = 'I_' THEN '키즈 광고'
      WHEN LEFT(UPPER(TRIM(campaign)), 2) = 'M_' THEN '성인 광고'
      ELSE NULL
    END AS ad_type,
    SUM(revenue) AS revenue
  FROM joined
  GROUP BY 1
),

tot AS (
  SELECT SUM(revenue) AS total_revenue
  FROM agg
  WHERE ad_type IS NOT NULL
)

SELECT
  '키즈 매출' AS area,
  ad_type,
  revenue,
  ROUND( (revenue / NULLIF(total_revenue, 0)) * 100, 0 ) AS pct
FROM agg
CROSS JOIN tot
WHERE ad_type IS NOT NULL
ORDER BY revenue DESC;
