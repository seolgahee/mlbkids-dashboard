/* section5_adult_cross_top5_sm.sql
   키즈광고(I_) 유입이 만든 성인(3*) 매출 기준 source/medium TOP5 + inbound sessions
*/

WITH purchase_adult AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    COALESCE(
      it.value:item_revenue::NUMBER,
      (COALESCE(it.value:price::NUMBER,0) * COALESCE(it.value:quantity::NUMBER,1)),
      0
    ) AS revenue
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='purchase'
    AND it.value:item_id::STRING LIKE '3%%'
  GROUP BY e.USER_PSEUDO_ID, e.EVENT_TIMESTAMP,
           it.value:item_revenue::NUMBER, it.value:price::NUMBER, it.value:quantity::NUMBER
  HAVING session_id IS NOT NULL
),

session_start_dim AS (
  SELECT
    e.USER_PSEUDO_ID,
    MAX(IFF(ep.value:key::STRING='ga_session_id', ep.value:value:int_value::NUMBER, NULL)) AS session_id,
    COALESCE(
      NULLIF(GET(e.COLLECTED_TRAFFIC_SOURCE[0],'manual_campaign_name')::STRING,''),
      NULLIF(GET(e.TRAFFIC_SOURCE[0],'name')::STRING,'')
    ) AS campaign,
    COALESCE(GET(e.TRAFFIC_SOURCE[0],'source')::STRING,'(not set)') AS source,
    COALESCE(GET(e.TRAFFIC_SOURCE[0],'medium')::STRING,'(not set)') AS medium
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.EVENT_PARAMS) ep
  WHERE e.P_BRAND='M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME='session_start'
  GROUP BY e.USER_PSEUDO_ID, campaign, source, medium
  HAVING session_id IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY e.USER_PSEUDO_ID, session_id
    ORDER BY e.USER_PSEUDO_ID
  ) = 1
),

inbound AS (
  SELECT
    source,
    medium,
    COUNT(DISTINCT USER_PSEUDO_ID || '-' || session_id) AS inbound_sessions
  FROM session_start_dim
  WHERE LEFT(UPPER(TRIM(campaign)),2)='I_'
  GROUP BY 1,2
),

rev AS (
  SELECT
    d.source,
    d.medium,
    SUM(p.revenue) AS revenue
  FROM purchase_adult p
  JOIN session_start_dim d
    ON p.USER_PSEUDO_ID = d.USER_PSEUDO_ID
   AND p.session_id     = d.session_id
  WHERE LEFT(UPPER(TRIM(d.campaign)),2)='I_'
  GROUP BY 1,2
)

SELECT
  r.source AS SOURCE,
  r.medium AS MEDIUM,
  r.revenue AS REVENUE,
  COALESCE(i.inbound_sessions, 0) AS INFLOW_SESSIONS
FROM rev r
LEFT JOIN inbound i
  ON r.source=i.source AND r.medium=i.medium
ORDER BY r.revenue DESC
LIMIT 5;
