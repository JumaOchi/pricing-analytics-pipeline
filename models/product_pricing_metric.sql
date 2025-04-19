-- models/product_pricing_metric.sql

WITH base_sales AS (
    SELECT
        EXTRACT(YEAR FROM CAST(order_date AS DATE)) AS order_year,
        order_id,
        region,
        product_category,
        quantity_sold,
        unit_price,
        discounted_price,
        total_price,
        profit,
        (unit_price - discounted_price) / NULLIF(unit_price, 0) AS discount_rate
    FROM amazon_sales
),
-- Tag each row into 'High Discount' or 'Low Discount' bands
discount_band AS (
    SELECT *,
        CASE
            WHEN discount_rate >= 0.20 THEN 'High Discount'
            ELSE 'Low Discount'
        END AS discount_group
    FROM base_sales
),
-- Estimate price sensitivity: avg quantity per discount band
price_sensitivity_estimate AS (
    SELECT
        order_year,
        product_category,
        discount_group,
        AVG(quantity_sold) AS avg_quantity_sold
    FROM discount_band
    GROUP BY order_year, product_category, discount_group
),
-- Pivot the above to compute sensitivity score
price_sensitivity_summary AS (
    SELECT
        pse.order_year,
        pse.product_category,
        MAX(CASE WHEN discount_group = 'High Discount' THEN avg_quantity_sold ELSE NULL END) AS avg_qty_high_discount,
        MAX(CASE WHEN discount_group = 'Low Discount' THEN avg_quantity_sold ELSE NULL END) AS avg_qty_low_discount,
        CASE 
            WHEN MAX(CASE WHEN discount_group = 'Low Discount' THEN avg_quantity_sold ELSE NULL END) = 0 THEN NULL
            ELSE ROUND((
                MAX(CASE WHEN discount_group = 'High Discount' THEN avg_quantity_sold ELSE 0 END) 
                / NULLIF(MAX(CASE WHEN discount_group = 'Low Discount' THEN avg_quantity_sold ELSE 0 END), 0)
            ) - 1, 2)
        END AS sensitivity_score -- % increase from Low to High discount band
    FROM price_sensitivity_estimate pse
    GROUP BY pse.order_year, pse.product_category
),
-- Core pricing metrics
product_year_metrics AS (
    SELECT
        order_year,
        product_category,
        COUNT(DISTINCT order_id) AS num_orders,
        SUM(quantity_sold) AS total_units_sold,
        SUM(unit_price * quantity_sold) AS gross_revenue,
        SUM(total_price) AS net_revenue,
        SUM(profit) AS total_profit,
        AVG(unit_price) AS avg_unit_price,
        AVG(discounted_price) AS avg_discounted_price,
        AVG(unit_price - discounted_price) AS avg_discount_amount,
        AVG(1 - (discounted_price / NULLIF(unit_price, 0))) AS avg_discount_rate,
        (SUM(unit_price * quantity_sold) - SUM(total_price)) AS total_discount_impact
    FROM base_sales
    GROUP BY order_year, product_category
),
-- Combine metrics with sensitivity
final_product_pricing AS (
    SELECT
        pym.*,
        pss.avg_qty_high_discount,
        pss.avg_qty_low_discount,
        pss.sensitivity_score,
        CASE 
            WHEN pss.sensitivity_score > 0.2 THEN 'High Sensitivity'
            WHEN pss.sensitivity_score BETWEEN 0.05 AND 0.2 THEN 'Moderate Sensitivity'
            ELSE 'Low Sensitivity'
        END AS price_sensitivity_flag
    FROM product_year_metrics pym
    LEFT JOIN price_sensitivity_summary pss
    ON pym.order_year = pss.order_year AND pym.product_category = pss.product_category
)
SELECT * FROM final_product_pricing
ORDER BY order_year, product_category;


