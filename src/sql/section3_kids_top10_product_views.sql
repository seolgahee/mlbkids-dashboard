WITH product_views AS (
  SELECT
    it.value:item_id::STRING AS item_id,
    it.value:item_name::STRING AS item_name
  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME = 'view_item'
    AND it.value:item_id::STRING LIKE '7%%'   -- ✅ 키즈 상품만
)

SELECT
  ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rank,
  item_id,
  item_name,
  COUNT(*) AS view_count
FROM product_views
GROUP BY item_id, item_name
ORDER BY view_count DESC
LIMIT 10;
