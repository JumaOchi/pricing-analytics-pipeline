WITH regional_sales AS (
    SELECT
        DATE_PART('year', CAST(order_date AS DATE)) AS year,
        region,
        COUNT(DISTINCT order_id) AS num_completed_orders,
        COUNT(DISTINCT customer_id) AS unique_customers,
        SUM(total_price) AS total_sales,
        SUM(profit) AS total_profit,
        AVG(total_price) AS avg_order_value,
        AVG((unit_price - discounted_price) / NULLIF(unit_price, 0)) * 100 AS avg_discount_percentage
    FROM amazon_sales
    GROUP BY year, region
),
regional_losses AS (
    SELECT
        region,
        DATE_PART('year', CURRENT_DATE) AS year, -- assuming loss records are recent, or you can extract from order_date if it exists
        COUNT(*) AS num_loss_cases,
        SUM(total_value_lost) AS total_value_lost,
        AVG(avg_discount_applied) AS avg_discount_on_losses,
        SUM(units_affected) AS units_lost
    FROM order_loss_summary
    GROUP BY region
)
SELECT
    rs.year,
    rs.region,
    rs.num_completed_orders,
    rs.unique_customers,
    rs.total_sales,
    rs.total_profit,
    rs.avg_order_value,
    rs.avg_discount_percentage,
    COALESCE(rl.num_loss_cases, 0) AS num_loss_cases,
    COALESCE(rl.total_value_lost, 0) AS total_value_lost,
    COALESCE(rl.avg_discount_on_losses, 0) AS avg_discount_on_losses,
    COALESCE(rl.units_lost, 0) AS units_lost
FROM regional_sales rs
LEFT JOIN regional_losses rl
  ON rs.region = rl.region
ORDER BY rs.year, rs.region;
