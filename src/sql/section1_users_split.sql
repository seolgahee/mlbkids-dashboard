WITH pv AS (
  SELECT
    e.USER_PSEUDO_ID,
    e.EVENT_TIMESTAMP,
    e.EVENT_PARAMS,

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

  FROM FNF.STRG_GA.EVENTS e
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME IN ('page_view','session_start')
),

pv_with_session AS (
  SELECT
    USER_PSEUDO_ID,
    COALESCE(NULLIF(source,''),'(not set)') AS source,
    COALESCE(NULLIF(medium,''),'(not set)') AS medium,
    COALESCE(NULLIF(campaign,''),'(not set)') AS campaign,

    MAX(IFF(ep.value:key::STRING = 'ga_session_id',
            ep.value:value:int_value::NUMBER, NULL)) AS session_id

  FROM pv,
       LATERAL FLATTEN(input => EVENT_PARAMS) ep
  GROUP BY 1,2,3,4
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
)

SELECT
  CASE
  WHEN LEFT(UPPER(TRIM(campaign)), 2) = 'I_' THEN '키즈 광고'
  WHEN LEFT(UPPER(TRIM(campaign)), 2) = 'M_' THEN '성인 광고'
  ELSE 'Non-paid'
END
 AS bucket,
  COUNT(DISTINCT USER_PSEUDO_ID) AS users
FROM session_dim
GROUP BY 1
ORDER BY users DESC;
