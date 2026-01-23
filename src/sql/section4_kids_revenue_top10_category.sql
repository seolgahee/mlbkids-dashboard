WITH purchase_items AS (
  SELECT
    it.value:item_id::STRING AS item_id,
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
    AND it.value:item_id::STRING LIKE '7%%'
),

cat_agg AS (
  SELECT
    SUBSTR(item_id, 3, 2) AS category_code,   -- ✅ 3번째부터 2글자 (7ABKB... -> BK)
    SUM(qty) AS quantity,
    SUM(revenue) AS revenue
  FROM purchase_items
  GROUP BY 1
)

SELECT
  ROW_NUMBER() OVER (ORDER BY revenue DESC, quantity DESC) AS rank,
  category_code AS category,
  quantity,
  revenue
FROM cat_agg
ORDER BY revenue DESC, quantity DESC
LIMIT 10;