
WITH year_region_trends AS (
    SELECT
        DATE_TRUNC('year', a.order_date::DATE)::DATE AS year,
        a.region,
        COUNT(*) AS total_orders,
        SUM(a.total_price) AS total_loss
    FROM order_loss_summary o
    JOIN amazon_sales a ON o.customer_id = a.customer_id
    GROUP BY year, a.region
),
loss_by_status AS (
    SELECT
        order_status,
        COUNT(*) AS num_orders,
        SUM(total_value_lost) AS total_loss
    FROM order_loss_summary
    GROUP BY order_status
),
loss_by_salesperson AS (
    SELECT
        a.salesperson,
        COUNT(*) AS num_loss_orders,
        SUM(o.total_value_lost) AS total_loss
    FROM order_loss_summary o
    JOIN amazon_sales a ON o.customer_id = a.customer_id
    GROUP BY a.salesperson
),
loss_by_category AS (
    SELECT
        a.product_category,
        COUNT(*) AS num_loss_orders,
        SUM(o.total_value_lost) AS total_loss
    FROM order_loss_summary o
    JOIN amazon_sales a ON o.customer_id = a.customer_id
    GROUP BY a.product_category
),
loss_by_payment AS (
    SELECT
        payment_method,
        COUNT(*) AS num_orders,
        SUM(total_value_lost) AS total_loss
    FROM order_loss_summary
    GROUP BY payment_method
)
-- Final combined summary
SELECT
    'Yearly & Regional Trends' AS analysis_type,
    NULL::TEXT AS order_status,
    region,
    year::TEXT AS dimension_value,
    total_orders AS metric_count,
    total_loss
FROM year_region_trends

UNION ALL

SELECT
    'Top Loss Reasons (order_status)' AS analysis_type,
    order_status,
    NULL::TEXT AS region,
    NULL::TEXT AS dimension_value,
    num_orders,
    total_loss
FROM loss_by_status

UNION ALL

SELECT
    'Salespeople with Most Revenue Leakage' AS analysis_type,
    NULL::TEXT AS order_status,
    NULL::TEXT AS region,
    salesperson AS dimension_value,
    num_loss_orders,
    total_loss
FROM loss_by_salesperson

UNION ALL

SELECT
    'Product Categories Most Affected' AS analysis_type,
    NULL::TEXT AS order_status,
    NULL::TEXT AS region,
    product_category AS dimension_value,
    num_loss_orders,
    total_loss
FROM loss_by_category

UNION ALL

SELECT
    'Payment Method Losses' AS analysis_type,
    payment_method AS order_status,
    NULL::TEXT AS region,
    NULL::TEXT AS dimension_value,
    num_orders,
    total_loss
FROM loss_by_payment;


