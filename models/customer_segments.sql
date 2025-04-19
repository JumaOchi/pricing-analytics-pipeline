-- Active: 1744934238838@@127.0.0.1@5432@analytics@public

WITH customer_base AS (
    SELECT
        customer_id,
        MAX(order_date::date) AS last_order_date,
        SUM(total_price) AS monetary_value
    FROM amazon_sales
    GROUP BY customer_id
),
rm AS (
    SELECT
        customer_id,
        (CURRENT_DATE - last_order_date)::int AS recency_days,
        monetary_value
    FROM customer_base
)
SELECT
    customer_id,
    recency_days,
    monetary_value,
    CASE
        WHEN recency_days <= 365 AND monetary_value >= 2000 THEN 'Recent Big Spender'
        WHEN recency_days <= 365 AND monetary_value BETWEEN 1000 AND 1999 THEN 'Recent Moderate Spender'
        WHEN recency_days <= 365 THEN 'Recent Low Spender'

        WHEN recency_days BETWEEN 366 AND 1095 AND monetary_value >= 2000 THEN 'Mid-Term Big Spender'
        WHEN recency_days BETWEEN 366 AND 1095 THEN 'Mid-Term Spender'

        WHEN recency_days > 1095 AND monetary_value >= 2000 THEN 'Dormant Big Spender'
        WHEN recency_days > 1095 THEN 'Dormant Low Spender'

        ELSE 'Unclassified'
    END AS segment
FROM rm;


