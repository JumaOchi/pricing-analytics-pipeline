-- models/discount_impact_analysis.sql
WITH base_completed AS (
  SELECT
    order_id::text,
    customer_id::text,
    region::text,
    product_category::text,
    total_price::double precision,
    profit::double precision,
    ((unit_price - discounted_price) / NULLIF(unit_price,0)) * 100.0 AS discount_pct,
    'Completed'::text AS order_status
  FROM amazon_sales
),
base_lost AS (
  SELECT
    NULL::text                        AS order_id,
    customer_id::text                 AS customer_id,
    region::text                      AS region,
    NULL::text                        AS product_category,
    total_value_lost::double precision AS total_price,
    NULL::double precision            AS profit,
    avg_discount_applied::double precision AS discount_pct,
    order_status::text                AS order_status
  FROM order_loss_summary
),
unified_orders AS (
  SELECT * FROM base_completed
  UNION ALL
  SELECT * FROM base_lost
),
banded_orders AS (
  SELECT
    *,
    CASE
      WHEN discount_pct <= 10  THEN 'Low'
      WHEN discount_pct <= 25  THEN 'Medium'
      ELSE 'High'
    END AS discount_band
  FROM unified_orders
),
discount_summary AS (
  SELECT
    discount_band,
    order_status,
    COUNT(*)                   AS num_orders,
    SUM(total_price)           AS total_value,
    SUM(profit)                AS total_profit,
    AVG(discount_pct)          AS avg_discount
  FROM banded_orders
  GROUP BY discount_band, order_status
),
discount_band_share AS (
  SELECT
    discount_band,
    SUM(CASE WHEN order_status = 'Completed' THEN num_orders ELSE 0 END) AS completed_orders,
    SUM(CASE WHEN order_status <> 'Completed' THEN num_orders ELSE 0 END) AS lost_orders,
    SUM(num_orders)                                       AS total_orders
  FROM discount_summary
  GROUP BY discount_band
)
SELECT 
  s.discount_band,
  s.order_status,
  s.num_orders,
  s.total_value,
  s.total_profit,
  s.avg_discount,
  b.completed_orders,
  b.lost_orders,
  b.total_orders,
  ROUND((s.num_orders::numeric / b.total_orders) * 100, 2) AS pct_of_band
FROM discount_summary s
JOIN discount_band_share b USING (discount_band)
ORDER BY discount_band, order_status;

