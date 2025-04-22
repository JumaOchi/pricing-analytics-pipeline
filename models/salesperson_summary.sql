-- Active: 1744934238838@@127.0.0.1@5432@analytics@publicCREATE OR REPLACE VIEW salesperson_summary 
WITH base_salesperson_data AS (
    SELECT
        DATE_PART('year', order_date::date) AS year,
        salesperson,
        COUNT(DISTINCT order_id) AS num_completed_orders,
        SUM(total_price) AS total_sales,
        SUM(profit) AS total_profit,
        AVG(total_price)::numeric AS avg_order_value,
        AVG(profit)::numeric AS avg_profit_per_order,
        SUM(discounted_price * quantity_sold) AS total_discounted_revenue,
        SUM((unit_price - discounted_price) * quantity_sold) AS total_discount_given
    FROM amazon_sales
    GROUP BY DATE_PART('year', order_date::date), salesperson
),
loss_with_years AS (
    SELECT
        DATE_PART('year', order_date::date) AS year,
        salesperson,
        SUM(total_value_lost) AS total_revenue_lost,
        SUM(units_affected) AS units_lost,
        COUNT(DISTINCT customer_id) AS customers_lost
    FROM order_loss_summary
    GROUP BY DATE_PART('year', order_date::date), salesperson
)
SELECT
    s.year,
    s.salesperson,
    s.num_completed_orders,
    s.total_sales,
    s.total_profit,
    ROUND(s.avg_order_value, 2) AS avg_order_value,
    ROUND(s.avg_profit_per_order, 2) AS avg_profit_per_order,
    s.total_discounted_revenue,
    s.total_discount_given,
    COALESCE(l.total_revenue_lost, 0) AS total_revenue_lost,
    COALESCE(l.units_lost, 0) AS units_lost,
    COALESCE(l.customers_lost, 0) AS customers_lost
FROM base_salesperson_data s
LEFT JOIN loss_with_years l
  ON s.salesperson = l.salesperson AND s.year = l.year
ORDER BY s.year, s.salesperson;




