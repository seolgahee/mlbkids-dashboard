WITH purchase_items AS (
  SELECT
    it.value:item_id::STRING AS item_id,
    it.value:item_name::STRING AS item_name,

    COALESCE(it.value:quantity::NUMBER, 1) AS qty,

    COALESCE(
      it.value:item_revenue::NUMBER,
      (COALESCE(it.value:price::NUMBER, 0) * COALESCE(it.value:quantity::NUMBER, 1)),
      0
    ) AS revenue

  FROM FNF.STRG_GA.EVENTS e,
       LATERAL FLATTEN(input => e.ITEMS) it
  WHERE e.P_BRAND = 'M'
    AND e.P_DATE BETWEEN %(start_date)s AND %(end_date)s
    AND e.EVENT_NAME = 'purchase'
    AND it.value:item_id::STRING LIKE '7%%'   -- ✅ 키즈 상품만
)

SELECT
  ROW_NUMBER() OVER (ORDER BY SUM(revenue) DESC, SUM(qty) DESC) AS rank,
  item_id,
  item_name,
  SUM(qty) AS quantity,
  SUM(revenue) AS revenue
FROM purchase_items
GROUP BY item_id, item_name
ORDER BY revenue DESC, quantity DESC
LIMIT 10;