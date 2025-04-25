--
-- PostgreSQL database dump
--

-- Dumped from database version 16.8 (Ubuntu 16.8-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.8 (Ubuntu 16.8-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: amazon_sales; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.amazon_sales (
    order_id text,
    order_date text,
    customer_id text,
    region text,
    product_category text,
    quantity_sold bigint,
    unit_price double precision,
    discounted_price double precision,
    total_price double precision,
    profit double precision,
    salesperson text,
    num_orders bigint,
    total_spent double precision,
    recency_days bigint,
    avg_order_value double precision,
    num_orders_by_sp bigint,
    total_sales_by_sp double precision,
    avg_profit_per_order_by_sp double precision
);


ALTER TABLE public.amazon_sales OWNER TO juma;

--
-- Name: archetype_growth; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.archetype_growth (
    total_sales_yoy double precision,
    total_profit_yoy double precision,
    avg_order_value_yoy double precision,
    avg_profit_per_order_yoy double precision,
    growth_score double precision
);


ALTER TABLE public.archetype_growth OWNER TO juma;

--
-- Name: customer_segments; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.customer_segments AS
 WITH customer_base AS (
         SELECT amazon_sales.customer_id,
            max((amazon_sales.order_date)::date) AS last_order_date,
            sum(amazon_sales.total_price) AS monetary_value
           FROM public.amazon_sales
          GROUP BY amazon_sales.customer_id
        ), rm AS (
         SELECT customer_base.customer_id,
            (CURRENT_DATE - customer_base.last_order_date) AS recency_days,
            customer_base.monetary_value
           FROM customer_base
        )
 SELECT customer_id,
    recency_days,
    monetary_value,
        CASE
            WHEN ((recency_days <= 365) AND (monetary_value >= (2000)::double precision)) THEN 'Recent Big Spender'::text
            WHEN ((recency_days <= 365) AND ((monetary_value >= (1000)::double precision) AND (monetary_value <= (1999)::double precision))) THEN 'Recent Moderate Spender'::text
            WHEN (recency_days <= 365) THEN 'Recent Low Spender'::text
            WHEN (((recency_days >= 366) AND (recency_days <= 1095)) AND (monetary_value >= (2000)::double precision)) THEN 'Mid-Term Big Spender'::text
            WHEN ((recency_days >= 366) AND (recency_days <= 1095)) THEN 'Mid-Term Spender'::text
            WHEN ((recency_days > 1095) AND (monetary_value >= (2000)::double precision)) THEN 'Dormant Big Spender'::text
            WHEN (recency_days > 1095) THEN 'Dormant Low Spender'::text
            ELSE 'Unclassified'::text
        END AS segment
   FROM rm;


ALTER VIEW public.customer_segments OWNER TO juma;

--
-- Name: order_loss_summary; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.order_loss_summary (
    customer_id text,
    order_status text,
    payment_method text,
    region text,
    salesperson text,
    order_date text,
    num_orders bigint,
    num_customers bigint,
    total_value_lost double precision,
    avg_discount_applied double precision,
    units_affected bigint,
    avg_order_value_lost double precision
);


ALTER TABLE public.order_loss_summary OWNER TO juma;

--
-- Name: discount_impact_analysis; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.discount_impact_analysis AS
 WITH base_completed AS (
         SELECT amazon_sales.order_id,
            amazon_sales.customer_id,
            amazon_sales.region,
            amazon_sales.product_category,
            amazon_sales.total_price,
            amazon_sales.profit,
            (((amazon_sales.unit_price - amazon_sales.discounted_price) / NULLIF(amazon_sales.unit_price, (0)::double precision)) * (100.0)::double precision) AS discount_pct,
            'Completed'::text AS order_status
           FROM public.amazon_sales
        ), base_lost AS (
         SELECT NULL::text AS order_id,
            order_loss_summary.customer_id,
            order_loss_summary.region,
            NULL::text AS product_category,
            order_loss_summary.total_value_lost AS total_price,
            NULL::double precision AS profit,
            order_loss_summary.avg_discount_applied AS discount_pct,
            order_loss_summary.order_status
           FROM public.order_loss_summary
        ), unified_orders AS (
         SELECT base_completed.order_id,
            base_completed.customer_id,
            base_completed.region,
            base_completed.product_category,
            base_completed.total_price,
            base_completed.profit,
            base_completed.discount_pct,
            base_completed.order_status
           FROM base_completed
        UNION ALL
         SELECT base_lost.order_id,
            base_lost.customer_id,
            base_lost.region,
            base_lost.product_category,
            base_lost.total_price,
            base_lost.profit,
            base_lost.discount_pct,
            base_lost.order_status
           FROM base_lost
        ), banded_orders AS (
         SELECT unified_orders.order_id,
            unified_orders.customer_id,
            unified_orders.region,
            unified_orders.product_category,
            unified_orders.total_price,
            unified_orders.profit,
            unified_orders.discount_pct,
            unified_orders.order_status,
                CASE
                    WHEN (unified_orders.discount_pct <= (10)::double precision) THEN 'Low'::text
                    WHEN (unified_orders.discount_pct <= (25)::double precision) THEN 'Medium'::text
                    ELSE 'High'::text
                END AS discount_band
           FROM unified_orders
        ), discount_summary AS (
         SELECT banded_orders.discount_band,
            banded_orders.order_status,
            count(*) AS num_orders,
            sum(banded_orders.total_price) AS total_value,
            sum(banded_orders.profit) AS total_profit,
            avg(banded_orders.discount_pct) AS avg_discount
           FROM banded_orders
          GROUP BY banded_orders.discount_band, banded_orders.order_status
        ), discount_band_share AS (
         SELECT discount_summary.discount_band,
            sum(
                CASE
                    WHEN (discount_summary.order_status = 'Completed'::text) THEN discount_summary.num_orders
                    ELSE (0)::bigint
                END) AS completed_orders,
            sum(
                CASE
                    WHEN (discount_summary.order_status <> 'Completed'::text) THEN discount_summary.num_orders
                    ELSE (0)::bigint
                END) AS lost_orders,
            sum(discount_summary.num_orders) AS total_orders
           FROM discount_summary
          GROUP BY discount_summary.discount_band
        )
 SELECT s.discount_band,
    s.order_status,
    s.num_orders,
    s.total_value,
    s.total_profit,
    s.avg_discount,
    b.completed_orders,
    b.lost_orders,
    b.total_orders,
    round((((s.num_orders)::numeric / b.total_orders) * (100)::numeric), 2) AS pct_of_band
   FROM (discount_summary s
     JOIN discount_band_share b USING (discount_band))
  ORDER BY s.discount_band, s.order_status;


ALTER VIEW public.discount_impact_analysis OWNER TO juma;

--
-- Name: discount_impact_analysis_summary; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.discount_impact_analysis_summary (
    discount_band text,
    avg_discount double precision,
    num_orders bigint,
    avg_profit_per_order double precision,
    avg_order_value double precision,
    profit_margin double precision,
    total_revenue double precision,
    total_profit double precision,
    order_uplift_vs_low double precision,
    revenue_uplift_vs_low double precision,
    profit_uplift_vs_low double precision,
    profit_per_discount_pct double precision
);


ALTER TABLE public.discount_impact_analysis_summary OWNER TO juma;

--
-- Name: discount_simulation_results; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.discount_simulation_results (
    region text,
    scenario text,
    predicted_profit double precision
);


ALTER TABLE public.discount_simulation_results OWNER TO juma;

--
-- Name: order_loss_analysis; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.order_loss_analysis AS
 WITH year_region_trends AS (
         SELECT (date_trunc('year'::text, ((a.order_date)::date)::timestamp with time zone))::date AS year,
            a.region,
            count(*) AS total_orders,
            sum(a.total_price) AS total_loss
           FROM (public.order_loss_summary o
             JOIN public.amazon_sales a ON ((o.customer_id = a.customer_id)))
          GROUP BY ((date_trunc('year'::text, ((a.order_date)::date)::timestamp with time zone))::date), a.region
        ), loss_by_status AS (
         SELECT order_loss_summary.order_status,
            count(*) AS num_orders,
            sum(order_loss_summary.total_value_lost) AS total_loss
           FROM public.order_loss_summary
          GROUP BY order_loss_summary.order_status
        ), loss_by_salesperson AS (
         SELECT a.salesperson,
            count(*) AS num_loss_orders,
            sum(o.total_value_lost) AS total_loss
           FROM (public.order_loss_summary o
             JOIN public.amazon_sales a ON ((o.customer_id = a.customer_id)))
          GROUP BY a.salesperson
        ), loss_by_category AS (
         SELECT a.product_category,
            count(*) AS num_loss_orders,
            sum(o.total_value_lost) AS total_loss
           FROM (public.order_loss_summary o
             JOIN public.amazon_sales a ON ((o.customer_id = a.customer_id)))
          GROUP BY a.product_category
        ), loss_by_payment AS (
         SELECT order_loss_summary.payment_method,
            count(*) AS num_orders,
            sum(order_loss_summary.total_value_lost) AS total_loss
           FROM public.order_loss_summary
          GROUP BY order_loss_summary.payment_method
        )
 SELECT 'Yearly & Regional Trends'::text AS analysis_type,
    NULL::text AS order_status,
    year_region_trends.region,
    (year_region_trends.year)::text AS dimension_value,
    year_region_trends.total_orders AS metric_count,
    year_region_trends.total_loss
   FROM year_region_trends
UNION ALL
 SELECT 'Top Loss Reasons (order_status)'::text AS analysis_type,
    loss_by_status.order_status,
    NULL::text AS region,
    NULL::text AS dimension_value,
    loss_by_status.num_orders AS metric_count,
    loss_by_status.total_loss
   FROM loss_by_status
UNION ALL
 SELECT 'Salespeople with Most Revenue Leakage'::text AS analysis_type,
    NULL::text AS order_status,
    NULL::text AS region,
    loss_by_salesperson.salesperson AS dimension_value,
    loss_by_salesperson.num_loss_orders AS metric_count,
    loss_by_salesperson.total_loss
   FROM loss_by_salesperson
UNION ALL
 SELECT 'Product Categories Most Affected'::text AS analysis_type,
    NULL::text AS order_status,
    NULL::text AS region,
    loss_by_category.product_category AS dimension_value,
    loss_by_category.num_loss_orders AS metric_count,
    loss_by_category.total_loss
   FROM loss_by_category
UNION ALL
 SELECT 'Payment Method Losses'::text AS analysis_type,
    loss_by_payment.payment_method AS order_status,
    NULL::text AS region,
    NULL::text AS dimension_value,
    loss_by_payment.num_orders AS metric_count,
    loss_by_payment.total_loss
   FROM loss_by_payment;


ALTER VIEW public.order_loss_analysis OWNER TO juma;

--
-- Name: product_pricing_metric; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.product_pricing_metric AS
 WITH base_sales AS (
         SELECT EXTRACT(year FROM (amazon_sales.order_date)::date) AS order_year,
            amazon_sales.order_id,
            amazon_sales.region,
            amazon_sales.product_category,
            amazon_sales.quantity_sold,
            amazon_sales.unit_price,
            amazon_sales.discounted_price,
            amazon_sales.total_price,
            amazon_sales.profit,
            ((amazon_sales.unit_price - amazon_sales.discounted_price) / NULLIF(amazon_sales.unit_price, (0)::double precision)) AS discount_rate
           FROM public.amazon_sales
        ), discount_band AS (
         SELECT base_sales.order_year,
            base_sales.order_id,
            base_sales.region,
            base_sales.product_category,
            base_sales.quantity_sold,
            base_sales.unit_price,
            base_sales.discounted_price,
            base_sales.total_price,
            base_sales.profit,
            base_sales.discount_rate,
                CASE
                    WHEN (base_sales.discount_rate >= (0.20)::double precision) THEN 'High Discount'::text
                    ELSE 'Low Discount'::text
                END AS discount_group
           FROM base_sales
        ), price_sensitivity_estimate AS (
         SELECT discount_band.order_year,
            discount_band.product_category,
            discount_band.discount_group,
            avg(discount_band.quantity_sold) AS avg_quantity_sold
           FROM discount_band
          GROUP BY discount_band.order_year, discount_band.product_category, discount_band.discount_group
        ), price_sensitivity_summary AS (
         SELECT pse.order_year,
            pse.product_category,
            max(
                CASE
                    WHEN (pse.discount_group = 'High Discount'::text) THEN pse.avg_quantity_sold
                    ELSE NULL::numeric
                END) AS avg_qty_high_discount,
            max(
                CASE
                    WHEN (pse.discount_group = 'Low Discount'::text) THEN pse.avg_quantity_sold
                    ELSE NULL::numeric
                END) AS avg_qty_low_discount,
                CASE
                    WHEN (max(
                    CASE
                        WHEN (pse.discount_group = 'Low Discount'::text) THEN pse.avg_quantity_sold
                        ELSE NULL::numeric
                    END) = (0)::numeric) THEN NULL::numeric
                    ELSE round(((max(
                    CASE
                        WHEN (pse.discount_group = 'High Discount'::text) THEN pse.avg_quantity_sold
                        ELSE (0)::numeric
                    END) / NULLIF(max(
                    CASE
                        WHEN (pse.discount_group = 'Low Discount'::text) THEN pse.avg_quantity_sold
                        ELSE (0)::numeric
                    END), (0)::numeric)) - (1)::numeric), 2)
                END AS sensitivity_score
           FROM price_sensitivity_estimate pse
          GROUP BY pse.order_year, pse.product_category
        ), product_year_metrics AS (
         SELECT base_sales.order_year,
            base_sales.product_category,
            count(DISTINCT base_sales.order_id) AS num_orders,
            sum(base_sales.quantity_sold) AS total_units_sold,
            sum((base_sales.unit_price * (base_sales.quantity_sold)::double precision)) AS gross_revenue,
            sum(base_sales.total_price) AS net_revenue,
            sum(base_sales.profit) AS total_profit,
            avg(base_sales.unit_price) AS avg_unit_price,
            avg(base_sales.discounted_price) AS avg_discounted_price,
            avg((base_sales.unit_price - base_sales.discounted_price)) AS avg_discount_amount,
            avg(((1)::double precision - (base_sales.discounted_price / NULLIF(base_sales.unit_price, (0)::double precision)))) AS avg_discount_rate,
            (sum((base_sales.unit_price * (base_sales.quantity_sold)::double precision)) - sum(base_sales.total_price)) AS total_discount_impact
           FROM base_sales
          GROUP BY base_sales.order_year, base_sales.product_category
        ), final_product_pricing AS (
         SELECT pym.order_year,
            pym.product_category,
            pym.num_orders,
            pym.total_units_sold,
            pym.gross_revenue,
            pym.net_revenue,
            pym.total_profit,
            pym.avg_unit_price,
            pym.avg_discounted_price,
            pym.avg_discount_amount,
            pym.avg_discount_rate,
            pym.total_discount_impact,
            pss.avg_qty_high_discount,
            pss.avg_qty_low_discount,
            pss.sensitivity_score,
                CASE
                    WHEN (pss.sensitivity_score > 0.2) THEN 'High Sensitivity'::text
                    WHEN ((pss.sensitivity_score >= 0.05) AND (pss.sensitivity_score <= 0.2)) THEN 'Moderate Sensitivity'::text
                    ELSE 'Low Sensitivity'::text
                END AS price_sensitivity_flag
           FROM (product_year_metrics pym
             LEFT JOIN price_sensitivity_summary pss ON (((pym.order_year = pss.order_year) AND (pym.product_category = pss.product_category))))
        )
 SELECT order_year,
    product_category,
    num_orders,
    total_units_sold,
    gross_revenue,
    net_revenue,
    total_profit,
    avg_unit_price,
    avg_discounted_price,
    avg_discount_amount,
    avg_discount_rate,
    total_discount_impact,
    avg_qty_high_discount,
    avg_qty_low_discount,
    sensitivity_score,
    price_sensitivity_flag
   FROM final_product_pricing
  ORDER BY order_year, product_category;


ALTER VIEW public.product_pricing_metric OWNER TO juma;

--
-- Name: region_behaviour_matrix; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.region_behaviour_matrix AS
 WITH regional_sales AS (
         SELECT date_part('year'::text, (amazon_sales.order_date)::date) AS year,
            amazon_sales.region,
            count(DISTINCT amazon_sales.order_id) AS num_completed_orders,
            count(DISTINCT amazon_sales.customer_id) AS unique_customers,
            sum(amazon_sales.total_price) AS total_sales,
            sum(amazon_sales.profit) AS total_profit,
            avg(amazon_sales.total_price) AS avg_order_value,
            (avg(((amazon_sales.unit_price - amazon_sales.discounted_price) / NULLIF(amazon_sales.unit_price, (0)::double precision))) * (100)::double precision) AS avg_discount_percentage
           FROM public.amazon_sales
          GROUP BY (date_part('year'::text, (amazon_sales.order_date)::date)), amazon_sales.region
        ), regional_losses AS (
         SELECT order_loss_summary.region,
            date_part('year'::text, CURRENT_DATE) AS year,
            count(*) AS num_loss_cases,
            sum(order_loss_summary.total_value_lost) AS total_value_lost,
            avg(order_loss_summary.avg_discount_applied) AS avg_discount_on_losses,
            sum(order_loss_summary.units_affected) AS units_lost
           FROM public.order_loss_summary
          GROUP BY order_loss_summary.region
        )
 SELECT rs.year,
    rs.region,
    rs.num_completed_orders,
    rs.unique_customers,
    rs.total_sales,
    rs.total_profit,
    rs.avg_order_value,
    rs.avg_discount_percentage,
    COALESCE(rl.num_loss_cases, (0)::bigint) AS num_loss_cases,
    COALESCE(rl.total_value_lost, (0)::double precision) AS total_value_lost,
    COALESCE(rl.avg_discount_on_losses, (0)::double precision) AS avg_discount_on_losses,
    COALESCE(rl.units_lost, (0)::numeric) AS units_lost
   FROM (regional_sales rs
     LEFT JOIN regional_losses rl ON ((rs.region = rl.region)))
  ORDER BY rs.year, rs.region;


ALTER VIEW public.region_behaviour_matrix OWNER TO juma;

--
-- Name: salesperson_cluster_summary; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.salesperson_cluster_summary (
    avg_order_value double precision,
    avg_profit_per_order double precision,
    discount_rate double precision,
    profit_margin double precision,
    num_completed_orders double precision,
    loss_rate double precision
);


ALTER TABLE public.salesperson_cluster_summary OWNER TO juma;

--
-- Name: salesperson_growth_yoy; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.salesperson_growth_yoy (
    year bigint,
    salesperson text,
    num_completed_orders bigint,
    total_sales double precision,
    total_profit double precision,
    avg_order_value double precision,
    avg_profit_per_order double precision,
    total_discounted_revenue double precision,
    total_discount_given double precision,
    total_revenue_lost double precision,
    units_lost double precision,
    customers_lost bigint,
    discount_rate double precision,
    loss_rate double precision,
    profit_margin double precision,
    cluster integer,
    total_sales_yoy double precision,
    total_profit_yoy double precision,
    avg_order_value_yoy double precision,
    avg_profit_per_order_yoy double precision,
    num_completed_orders_yoy double precision
);


ALTER TABLE public.salesperson_growth_yoy OWNER TO juma;

--
-- Name: salesperson_summary; Type: VIEW; Schema: public; Owner: juma
--

CREATE VIEW public.salesperson_summary AS
 WITH base_salesperson_data AS (
         SELECT date_part('year'::text, (amazon_sales.order_date)::date) AS year,
            amazon_sales.salesperson,
            count(DISTINCT amazon_sales.order_id) AS num_completed_orders,
            sum(amazon_sales.total_price) AS total_sales,
            sum(amazon_sales.profit) AS total_profit,
            (avg(amazon_sales.total_price))::numeric AS avg_order_value,
            (avg(amazon_sales.profit))::numeric AS avg_profit_per_order,
            sum((amazon_sales.discounted_price * (amazon_sales.quantity_sold)::double precision)) AS total_discounted_revenue,
            sum(((amazon_sales.unit_price - amazon_sales.discounted_price) * (amazon_sales.quantity_sold)::double precision)) AS total_discount_given
           FROM public.amazon_sales
          GROUP BY (date_part('year'::text, (amazon_sales.order_date)::date)), amazon_sales.salesperson
        ), loss_with_years AS (
         SELECT date_part('year'::text, (order_loss_summary.order_date)::date) AS year,
            order_loss_summary.salesperson,
            sum(order_loss_summary.total_value_lost) AS total_revenue_lost,
            sum(order_loss_summary.units_affected) AS units_lost,
            count(DISTINCT order_loss_summary.customer_id) AS customers_lost
           FROM public.order_loss_summary
          GROUP BY (date_part('year'::text, (order_loss_summary.order_date)::date)), order_loss_summary.salesperson
        )
 SELECT s.year,
    s.salesperson,
    s.num_completed_orders,
    s.total_sales,
    s.total_profit,
    round(s.avg_order_value, 2) AS avg_order_value,
    round(s.avg_profit_per_order, 2) AS avg_profit_per_order,
    s.total_discounted_revenue,
    s.total_discount_given,
    COALESCE(l.total_revenue_lost, (0)::double precision) AS total_revenue_lost,
    COALESCE(l.units_lost, (0)::numeric) AS units_lost,
    COALESCE(l.customers_lost, (0)::bigint) AS customers_lost
   FROM (base_salesperson_data s
     LEFT JOIN loss_with_years l ON (((s.salesperson = l.salesperson) AND (s.year = l.year))))
  ORDER BY s.year, s.salesperson;


ALTER VIEW public.salesperson_summary OWNER TO juma;

--
-- Name: sensitivity_ranked; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.sensitivity_ranked (
    product_category text,
    region text,
    sensitivity_coef double precision,
    sensitivity_tier text
);


ALTER TABLE public.sensitivity_ranked OWNER TO juma;

--
-- Name: sensitivity_with_volatility; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.sensitivity_with_volatility (
    product_category text,
    region text,
    sensitivity_coef double precision,
    sensitivity_tier text,
    volatility_score double precision,
    total_units bigint
);


ALTER TABLE public.sensitivity_with_volatility OWNER TO juma;

--
-- Name: what_if_simulation_value_results; Type: TABLE; Schema: public; Owner: juma
--

CREATE TABLE public.what_if_simulation_value_results (
    region text,
    scenario text,
    predicted_profit double precision
);


ALTER TABLE public.what_if_simulation_value_results OWNER TO juma;

--
-- Data for Name: amazon_sales; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.amazon_sales (order_id, order_date, customer_id, region, product_category, quantity_sold, unit_price, discounted_price, total_price, profit, salesperson, num_orders, total_spent, recency_days, avg_order_value, num_orders_by_sp, total_sales_by_sp, avg_profit_per_order_by_sp) FROM stdin;
b2852522-fbaa-43fa-b165-bd10e0035591	2019-01-02	6ac41f61-acf6-4e46-8b70-ad00ce01c9d0	North America	Sports	6	185.34	182.430162	1094.580972	866.9511063426361	Johnny Marshall	1	1094.580972	2188	1094.580972	61	67804.798966	913.3835523608234
f14eae78-235f-4283-a2cc-6433fd861c14	2019-01-04	04bb6a6a-a62a-4e79-a038-68758f215ccc	Asia	Home & Kitchen	5	40.98	39.25474199999999	196.27371	79.64544331748766	Roger Brown	1	196.27371	2186	196.27371	54	68595.667163	1076.1212096324236
f5bbf818-b635-477e-8770-1decbf291623	2019-01-05	d2019210-5707-4c36-a4ca-98f10f130f64	Europe	Beauty	4	424.33	387.83762	1551.35048	1308.8761942857143	Sandra Luna	1	1551.35048	2185	1551.35048	56	72688.198308	1090.9576938669472
4e0d446a-1f42-4e52-9a96-c1b5d55b9db3	2019-01-09	215bad3f-a307-4a9c-be98-f5c2482c9d50	South America	Sports	6	323.25	232.67535	1396.0521	1157.7203429664028	Christina Thompson	1	1396.0521	2181	1396.0521	53	64491.182614000005	1021.7261378833904
309c6d54-7d7f-4b0d-8810-d307d21a2261	2019-01-13	60823426-df1d-4db7-acec-2ab59d60a3f7	North America	Books	6	155.51	155.494449	932.966694	713.2538395149188	Christina Thompson	1	932.966694	2177	932.966694	53	64491.182614000005	1021.7261378833904
60978bd9-93ce-4bba-87b4-f3923f7b5528	2019-01-14	4f1ae849-cf84-4ab2-a0ec-9e67de881f0d	Australia	Clothing	8	222.88	177.055872	1416.446976	1177.529360374051	Caitlyn Boyd	1	1416.446976	2176	1416.446976	58	71709.8323	1035.5858485437743
15db83a2-9ae9-4797-8f8c-f7f4c2eb95be	2019-01-14	1dc94815-f0f6-4d41-b59c-8d9d8da78ae0	North America	Clothing	5	445.69	342.379058	1711.89529	1465.8131104870197	Caitlyn Boyd	1	1711.89529	2176	1711.89529	58	71709.8323	1035.5858485437743
4df01473-1e30-4061-aae9-fe1a097ca22f	2019-01-15	e5e091c9-93f5-482b-81b1-56b6bc7e93de	Europe	Clothing	2	163.89	159.514137	319.028274	167.83720533026872	Caleb Camacho	1	319.028274	2175	319.028274	66	91544.242731	1177.604080808591
41b2ec45-1058-4c30-9ea6-fd324ae8fd2e	2019-01-21	8050d664-2709-4144-946c-03ca835103d4	Asia	Books	6	351.13	272.12575	1632.7545	1388.374074327965	Charles Smith	1	1632.7545	2169	1632.7545	70	95387.089343	1149.437576059358
febc8ee1-a99a-433d-9801-3122a9aa16e0	2019-01-21	6c741970-a178-4b03-b450-620c8525599c	North America	Toys	6	336.37	255.203919	1531.223514	1289.243787076376	Joseph Brooks	1	1531.223514	2169	1531.223514	60	60657.854394	824.8550359343124
cac09295-c995-4df1-86a1-8c8fd40bbf07	2019-01-24	b1ba495a-a1f6-4da4-bd7f-31868357cc05	Australia	Books	10	325.4	229.99272	2299.9272	2044.4563745809592	Caleb Camacho	1	2299.9272	2166	2299.9272	66	91544.242731	1177.604080808591
406ed6b4-9544-4583-8ea5-cf797fba06cf	2019-01-24	9cb907bd-b4b3-40d8-9350-1ec8ad157b75	North America	Electronics	5	338.23	325.546375	1627.731875	1383.4670598794985	Mary Scott	1	1627.731875	2166	1627.731875	63	77562.23517100001	1033.152899764227
e111a06d-ffe5-436f-a673-736efdee7cca	2019-01-27	e66b2f35-60ef-47a7-bd75-567cab47be72	Europe	Books	4	377.89	293.204851	1172.819404	941.9903374960344	Steven Coleman	1	1172.819404	2163	1172.819404	59	68355.922945	964.8650638967956
1f948715-fef2-4845-8da8-3538f61eb8d3	2019-01-28	c071ccec-cb2e-4d4c-aef6-24575e7858f3	Europe	Toys	10	181.15	130.50046	1305.0046	1069.4782139185677	Caleb Camacho	1	1305.0046	2162	1305.0046	66	91544.242731	1177.604080808591
5c6efbbb-71ed-41ca-b59e-45fb7249bffc	2019-01-28	050b46f5-49e5-4842-bbfa-f1517abe87c2	Australia	Home & Kitchen	9	425.2	404.11008	3636.99072	3370.6440275554187	Adam Smith	1	3636.99072	2162	3636.99072	55	62372.113224	936.3944649146875
440d0143-fe58-4db8-be38-73ada9adbae2	2019-01-29	682742ce-afca-4719-b72b-7d85ae985747	North America	Beauty	9	450.3	361.05054	3249.4548600000003	2985.413218929355	Michelle Andersen	1	3249.4548600000003	2161	3249.4548600000003	60	66978.268402	921.082547231716
1dc458df-3cb1-460b-a48e-111052a0b4f9	2019-01-29	ce865928-8e42-4d61-82a2-21695d01dce0	Europe	Books	4	94.92	92.376144	369.504576	207.84531362961016	Kristen Ramos	1	369.504576	2161	369.504576	62	73461.618973	988.8412277570784
5036293f-1e1c-4935-9a94-3a9ba20c8eb2	2019-01-30	5c808cb6-9117-4a12-835b-2fae74aabb57	Australia	Electronics	3	496.29	470.929581	1412.788743	1173.976602328251	Bradley Howe	1	1412.788743	2160	1412.788743	56	64186.396558	951.6581100155678
c7ff529a-d00b-4d37-8c9a-2b97c7bedae0	2019-02-02	15a06880-4f6d-400b-8ae7-a5cb4b01edc4	Asia	Sports	7	289.09	250.669939	1754.689573	1507.7414943285482	Christina Thompson	1	1754.689573	2157	1754.689573	53	64491.182614000005	1021.7261378833904
7e05c96d-15ee-498c-b355-925852978cac	2019-02-02	e62791d2-0252-4ac8-b442-d151f330bc24	Asia	Home & Kitchen	3	383.32	310.335872	931.007616	711.4044514758816	Michelle Garza	1	931.007616	2157	931.007616	65	76798.491008	980.44596940906
48383d7a-8a01-455c-9175-0e86a2dedcc8	2019-02-03	1851cd68-8bf3-47be-823c-79dfea0dadc0	South America	Home & Kitchen	10	145.26	138.563514	1385.63514	1147.610757549043	Kristen Ramos	1	1385.63514	2156	1385.63514	62	73461.618973	988.8412277570784
ff9a82b6-8d6d-40eb-b248-ba7d82b4c102	2019-02-05	b21f780b-daee-4bc4-b7b6-afe978365876	Australia	Sports	2	264.17	225.548346	451.096692	275.54536416687426	Christina Thompson	1	451.096692	2154	451.096692	53	64491.182614000005	1021.7261378833904
fa7211cc-74cb-410d-bc86-c6cc60083016	2019-02-05	08de2fe8-4a51-431a-a4ad-fea34b1c4964	North America	Home & Kitchen	1	5.38	5.100239999999999	5.100239999999999	0.0887041839441877	Susan Edwards	1	5.100239999999999	2154	5.100239999999999	68	86058.98736700001	1063.159646603474
baa5d9a3-fea8-43da-9a1c-be8233714089	2019-02-06	ea97f7cf-4f40-4439-9fbe-228a401d52b6	Australia	Beauty	2	104.7	76.5357	153.0714	53.19445885423464	Diane Andrews	1	153.0714	2153	153.0714	58	66389.094387	950.0340815608216
5f51f8c1-19e4-41cc-9dd5-4f3775ef9646	2019-02-10	f75acfbb-efaa-4393-aea0-cbc7dbfd742a	Europe	Clothing	4	153.79	138.457137	553.828548	364.6212957708312	Crystal Williams	1	553.828548	2149	553.828548	65	72555.900913	927.0834787540324
7580eaba-2bca-4108-b77a-abaf592c0f74	2019-02-13	daea6508-0399-4cf6-8144-9eaf3f81faa0	Australia	Clothing	4	45.21	32.650662	130.602648	40.80434766996699	Roger Brown	1	130.602648	2146	130.602648	54	68595.667163	1076.1212096324236
bb03de1e-71be-479b-b8f6-8a4b95d5e115	2019-02-16	66f80761-a058-4b25-863f-1b82e21d0534	North America	Clothing	3	363.7	307.98116	923.94348	704.7346067171225	Michelle Andersen	1	923.94348	2143	923.94348	60	66978.268402	921.082547231716
26ccda59-a3ea-4f16-b603-9690ae2dbc38	2019-02-19	501e8b7e-943a-4508-80a0-3c6c13f432a8	Asia	Toys	1	244.71	225.549207	225.549207	99.17694848363963	Michelle Andersen	1	225.549207	2140	225.549207	60	66978.268402	921.082547231716
a80ce54f-2cde-46cd-8e75-0cb2b4047dc4	2019-02-19	7e6b36fb-d1a8-4e79-a5e6-dd208859caeb	South America	Clothing	9	62.1	47.40714	426.66426	254.9407391113258	Jason Nelson	1	426.66426	2140	426.66426	70	87933.283392	1049.1629849529377
36efe66d-b180-41ab-9ab5-7d8e59f9309b	2019-02-20	c45830c0-c897-417c-b946-6008ef62f0eb	Europe	Clothing	9	343.26	336.841038	3031.569342	2769.061713996363	Michelle Garza	1	3031.569342	2139	3031.569342	65	76798.491008	980.44596940906
a1ae0dd7-9ed6-4075-b6f5-ab449bc2d5e6	2019-02-23	abd48472-2f24-4d42-9ace-29a7b5f35911	South America	Sports	2	221.7	210.41547	420.83094	250.05995432455464	Sandra Luna	1	420.83094	2136	420.83094	56	72688.198308	1090.9576938669472
d411259d-5da1-4981-9f11-89f8d48c5786	2019-02-24	faecb7d3-188d-4bfb-9925-9bfdf622dbc0	North America	Clothing	9	133.12	129.618944	1166.570496	935.9819533738412	Christina Thompson	1	1166.570496	2135	1166.570496	53	64491.182614000005	1021.7261378833904
a8fa5458-cf5c-4310-9665-9cdfa33ea57b	2019-02-25	1e92cbae-c20a-412e-a580-b1c1e860f438	Asia	Beauty	4	140.6	122.33606	489.34424	308.2866901424501	Mary Scott	1	489.34424	2134	489.34424	63	77562.23517100001	1033.152899764227
7ab6a441-46a0-4601-9b6c-1244c19fdea1	2019-02-26	ff9cab1c-49d2-4e02-9ca6-db64c2160088	Asia	Books	3	425.92	367.14304	1101.42912	873.5079363476461	Caitlyn Boyd	1	1101.42912	2133	1101.42912	58	71709.8323	1035.5858485437743
1eca3102-7cba-4477-9842-34c9231d8b4f	2019-02-26	12941393-2ff3-4eda-81c7-ea2428cc4b8f	Australia	Electronics	10	494.53	373.86468	3738.6468	3471.768352167209	Jason Nelson	1	3738.6468	2133	3738.6468	70	87933.283392	1049.1629849529377
d0431dc8-d1c0-47f3-800e-a602c5e6a73c	2019-02-27	ffbc7ca5-d04b-4b2e-a307-69e316eea9e6	Asia	Home & Kitchen	1	370.83	283.981614	283.981614	141.14090478014182	Charles Smith	1	283.981614	2132	283.981614	70	95387.089343	1149.437576059358
9b44afa1-946c-4f41-aa88-297944a50f41	2019-03-03	e6a10eb1-3adc-48f1-97b3-0eea0e324181	North America	Clothing	10	121.69	95.027721	950.27721	729.6160675409265	Susan Edwards	1	950.27721	2128	950.27721	68	86058.98736700001	1063.159646603474
239b3a2d-13b8-4a50-9a65-6d4b8acb60bd	2019-03-04	f4b0746c-ac30-4307-8771-9e3f98ad7989	Asia	Electronics	7	49.25	39.907275	279.350925	137.69224092292086	Adam Smith	1	279.350925	2127	279.350925	55	62372.113224	936.3944649146875
6c067873-5181-4524-ab94-1896b1e54a9d	2019-03-05	0ed272d9-ecba-4e3a-a484-471588856e67	Europe	Books	6	323.67	288.972576	1733.835456	1487.3068827026873	Caleb Camacho	1	1733.835456	2126	1733.835456	66	91544.242731	1177.604080808591
b687a8a1-1cc5-4ad7-9cd4-277aeb4dd625	2019-03-07	fe82139b-fa71-4388-b8f9-2c6fffc23fd4	Australia	Clothing	6	67.78	55.776162	334.656972	180.04529632432434	Adam Smith	1	334.656972	2124	334.656972	55	62372.113224	936.3944649146875
b5f0d003-04ce-47dd-ad70-8885f335f6ed	2019-03-07	b9aaf52e-8004-4e9f-a063-e82b9531ecc7	Europe	Toys	6	112.73	94.603016	567.618096	376.8285104398508	Mary Scott	1	567.618096	2124	567.618096	63	77562.23517100001	1033.152899764227
58dd5101-e613-4d85-878f-c943ee3d3209	2019-03-15	57faa818-b21f-4e18-a664-c87a3309ba47	Asia	Toys	8	493.29	414.018297	3312.146376	3047.699328861522	Susan Edwards	1	3312.146376	2116	3312.146376	68	86058.98736700001	1063.159646603474
407880c1-2136-4d43-a839-b85a8a5c8d69	2019-03-15	de3a3ffb-2251-42fa-a6f1-d28689bcbf53	South America	Clothing	7	460.2	332.67858	2328.7500600000003	2072.9277970097774	Emily Matthews	1	2328.7500600000003	2116	2328.7500600000003	72	80570.187359	919.786031455556
81393008-4143-474f-8c86-ca4fafba17a7	2019-03-22	81edbf39-bb2f-4d44-ba9a-be465309689b	Asia	Clothing	7	317.83	245.015147	1715.1060289999998	1468.9586038442835	Jason Nelson	1	1715.1060289999998	2109	1715.1060289999998	70	87933.283392	1049.1629849529377
84ca7cd9-de10-4168-82a4-b79cdc197b9c	2019-03-23	28b28ef2-456a-434e-8fc2-0fb7ce5eaa7d	South America	Toys	7	497.41	463.03896900000007	3241.2727830000003	2977.28464289689	Steven Coleman	1	3241.2727830000003	2108	3241.2727830000003	59	68355.922945	964.8650638967956
2600becf-048f-4dbb-afce-6ba83a727b89	2019-03-25	749d6397-1373-4d37-b85a-a23a989de09b	South America	Sports	10	307.34	216.275158	2162.75158	1909.0682830285969	Michelle Andersen	1	2162.75158	2106	2162.75158	60	66978.268402	921.082547231716
7aae6b19-4bf0-4b23-9c69-5a2c6d4ca291	2019-03-25	e4303474-9466-44b7-b1dc-6b36c40bb86c	South America	Books	1	318.15	288.021195	288.021195	144.1688350958945	Bradley Howe	1	288.021195	2106	288.021195	56	64186.396558	951.6581100155678
9a9d8949-ea3c-433f-bb95-21473b873f66	2019-03-29	d255b6fa-2339-4be1-b94f-f17edaed4b98	Asia	Books	4	10.18	8.560362	34.241448	3.64413944848539	Steven Coleman	1	34.241448	2102	34.241448	59	68355.922945	964.8650638967956
4b10c6da-7fa0-40b8-975f-3049bb1c7bdd	2019-03-30	81fc152a-2946-45cc-b5d2-a405bd45e505	Europe	Beauty	1	293.87	233.009523	233.009523	104.33185401391648	Crystal Williams	1	233.009523	2101	233.009523	65	72555.900913	927.0834787540324
84a85b73-26af-4712-8e46-237b39159a0c	2019-03-31	e162e2c5-9336-4c81-a615-bb8f656285e9	North America	Beauty	4	161.29	121.12879	484.51516	304.1230530712238	Michelle Garza	1	484.51516	2100	484.51516	65	76798.491008	980.44596940906
5fe58f8a-4d65-450c-8bb1-a8879edc5638	2019-04-01	3b876e0e-fe43-4657-8a89-3ee1c6cc44ac	Europe	Books	7	261.34	218.08823	1526.6176099999998	1284.7542075379836	Sandra Luna	1	1526.6176099999998	2099	1526.6176099999998	56	72688.198308	1090.9576938669472
161312b4-3c42-494e-8e7b-f38dd6794eeb	2019-04-06	a3a5f553-e94e-493a-814c-27eef6cebab7	Europe	Electronics	8	158.11	147.311087	1178.488696	947.4396633371762	Susan Edwards	1	1178.488696	2094	1178.488696	68	86058.98736700001	1063.159646603474
969a6eb9-72ab-4a9c-b31e-3d3aaf90ae1c	2019-04-08	ebad781c-cd78-4454-9271-5e9119f62409	Australia	Books	6	107.45	78.76085	472.5651	293.8542502477027	Caleb Camacho	1	472.5651	2092	472.5651	66	91544.242731	1177.604080808591
59bbe935-d32d-42e9-b111-9fadcc446165	2019-04-08	233e7b39-aac2-493f-95d1-2b3ea7fd2ce8	Europe	Books	7	447.56	320.587228	2244.110596	1989.34410953806	Crystal Williams	1	2244.110596	2092	2244.110596	65	72555.900913	927.0834787540324
c2912be1-6dc8-440d-adfc-a9051652f40b	2019-04-13	fce199dc-3bad-4b3b-95de-151e2d1e176f	Asia	Electronics	8	242.29	229.69092	1837.52736	1589.004630145257	Bradley Howe	1	1837.52736	2087	1837.52736	56	64186.396558	951.6581100155678
05c4ee34-0c61-4c60-99d2-9942fa4cc255	2019-04-14	bd1a0c76-3449-478b-96a7-d5d31a36e0c5	Australia	Sports	9	201.33	181.257399	1631.3165910000002	1386.9721800238608	Charles Smith	1	1631.3165910000002	2086	1631.3165910000002	70	95387.089343	1149.437576059358
be799183-b725-4c34-808f-3ac947397a94	2019-04-15	99c3bb4a-09e0-48c8-86c1-15d10f5e99e7	North America	Sports	2	54.22	51.134882000000005	102.269764	26.84402168862012	Caitlyn Boyd	1	102.269764	2085	102.269764	58	71709.8323	1035.5858485437743
8b98db71-ef11-4f0c-aa8d-bad4fe587298	2019-04-15	a26df309-efb0-46a2-8a46-92b45a158eae	Europe	Home & Kitchen	5	36.45	32.597235000000005	162.98617500000003	58.98121360634293	Kristen Ramos	1	162.98617500000003	2085	162.98617500000003	62	73461.618973	988.8412277570784
e54af86a-1420-417b-bada-0a0378a707d5	2019-04-19	3227e64c-e483-4435-b6fb-d665d8854fdf	South America	Home & Kitchen	8	493.36	463.067696	3704.541568	3437.837831669808	Jason Nelson	1	3704.541568	2081	3704.541568	70	87933.283392	1049.1629849529377
6f1e2478-2468-4e53-a829-ca0e20dcdd2d	2019-04-19	33343b51-2c7c-4a8b-8676-24ac7871f4bb	Europe	Clothing	5	131.69	119.074098	595.37049	401.5397535759865	Emily Matthews	1	595.37049	2081	595.37049	72	80570.187359	919.786031455556
e6666c81-342e-4ced-9956-fd77b31d2cdf	2019-04-20	0677a155-eb18-4dc0-804a-b75b0e2da190	North America	Clothing	1	129.43	122.065433	122.065433	36.38744254586932	Joseph Brooks	1	122.065433	2080	122.065433	60	60657.854394	824.8550359343124
ca17f1b4-89f7-42c1-9f54-7b6f6d5f242c	2019-04-23	37516753-abe1-4502-9c08-91174b59cec4	Asia	Beauty	4	428.02	388.470952	1553.8838079999998	1311.3471581904223	Caleb Camacho	1	1553.8838079999998	2077	1553.8838079999998	66	91544.242731	1177.604080808591
2007b196-9703-4032-98d0-b91e4434a66c	2019-04-23	54579c18-6979-430f-b1b1-f4d2e7ab46b6	Europe	Toys	5	369.88	289.505076	1447.5253799999998	1207.737850389451	Kristen Ramos	1	1447.5253799999998	2077	1447.5253799999998	62	73461.618973	988.8412277570784
36c1308d-ae1e-4448-8afb-49ac72e05159	2019-04-24	92bfe5c1-4762-4cdc-9842-cc6d73c7b88e	Australia	Beauty	10	309.19	257.740784	2577.4078400000003	2318.8448256142538	Kristen Ramos	1	2577.4078400000003	2076	2577.4078400000003	62	73461.618973	988.8412277570784
cedf186c-2024-4408-b26f-8237d638b3fb	2019-04-24	11b97e72-28f9-4c88-9dfc-58aae863acce	Asia	Beauty	5	48.13	43.644284000000006	218.22142	94.18264321377822	Steven Coleman	1	218.22142	2076	218.22142	59	68355.922945	964.8650638967956
7028ca3d-7f8c-49f7-8e60-5987a2b94767	2019-04-25	c7e83433-dd72-464b-b7e9-092489449f1a	South America	Books	8	351.69	305.196582	2441.572656	2184.445917721218	Emily Matthews	1	2441.572656	2075	2441.572656	72	80570.187359	919.786031455556
001fe900-aab6-4ad0-8138-e919bdce97d0	2019-04-26	ab8e674e-77db-4680-8135-cbcc9e1604af	Asia	Home & Kitchen	2	415.96	333.47513200000003	666.9502640000001	466.1039773736864	Bradley Howe	1	666.9502640000001	2074	666.9502640000001	56	64186.396558	951.6581100155678
ca37d76b-9029-4f5e-ad54-66b4a695dce9	2019-04-27	ced29de6-ed76-4643-813c-ae167092624f	Europe	Home & Kitchen	7	195.37	149.809716	1048.668012	823.0946479784036	Sandra Luna	1	1048.668012	2073	1048.668012	56	72688.198308	1090.9576938669472
ed83cbd4-15c8-43a0-8c11-45266d52550a	2019-04-30	0af3185d-28b1-4fb1-9553-06c1d747b5a8	South America	Home & Kitchen	4	473.28	451.698432	1806.793728	1558.839382059395	Charles Smith	1	1806.793728	2070	1806.793728	70	95387.089343	1149.437576059358
011258f2-20e7-4611-b69e-761f073f30a1	2019-05-01	3756b317-2ef2-433a-adba-dfec948e30f9	North America	Books	9	359.46	347.84944199999995	3130.644978	2867.415151040056	Bradley Howe	1	3130.644978	2069	3130.644978	56	64186.396558	951.6581100155678
ec5147b5-680b-45e0-a679-d066de59f28f	2019-05-02	e01addbd-e452-47f7-bf48-43a49731e8ea	Australia	Books	9	422.16	360.018048	3240.162432	2976.183025272121	Caleb Camacho	1	3240.162432	2068	3240.162432	66	91544.242731	1177.604080808591
c6df5380-0e08-4624-8b4b-094f569c10a3	2019-05-06	9b1600dd-0bb2-41f2-98de-7aaffbfd1c1e	Asia	Home & Kitchen	2	245.41	183.689385	367.37877	206.12749931571784	Michelle Andersen	1	367.37877	2064	367.37877	60	66978.268402	921.082547231716
0ddb74fc-8c6b-4833-bd30-48c07a302181	2019-05-06	49252d36-e251-4b2d-9277-d3ce587aeefc	Europe	Electronics	8	35.96	33.55068	268.40544	129.6157197455918	Mary Scott	1	268.40544	2064	268.40544	63	77562.23517100001	1033.152899764227
172ca2e9-c2c1-4f4d-bf71-48372ff452cd	2019-05-13	0c88a0af-b435-4be2-b1e3-819b7fa821b3	Asia	Clothing	1	383.81	270.816336	270.816336	131.3855910069505	Susan Edwards	1	270.816336	2057	270.816336	68	86058.98736700001	1063.159646603474
34473f11-f1c7-4f64-aa9b-b874b967df98	2019-05-13	bbe85219-b390-4c2f-a797-3bfba26c6888	North America	Books	4	437.06	360.312264	1441.249056	1201.635919289498	Jason Nelson	1	1441.249056	2057	1441.249056	70	87933.283392	1049.1629849529377
7c2b3eac-49d6-464a-b358-d3bee9d65b32	2019-05-16	03a30dcb-c39a-47f2-a36b-3c9e3572fcda	Australia	Home & Kitchen	6	83.96	77.008112	462.048672	284.86238830172186	Michelle Garza	1	462.048672	2054	462.048672	65	76798.491008	980.44596940906
9619b13c-79db-4964-887e-a2743fe6f625	2019-05-19	0bbef808-5771-4b2d-8c49-c3b2b7d53cf9	Australia	Electronics	4	17.67	14.432856	57.731424	9.657959098675995	Mary Scott	1	57.731424	2051	57.731424	63	77562.23517100001	1033.152899764227
312200de-5b2a-431c-955a-b37cf57cb356	2019-05-23	7380de74-830c-4b8c-ad7d-e934c9b6fa3f	Europe	Electronics	3	64.06	57.122302	171.366906	64.01433693403496	Mary Scott	1	171.366906	2047	171.366906	63	77562.23517100001	1033.152899764227
1437a9c3-4a5f-49f2-a941-724d6145661c	2019-05-24	a52b2530-435e-485f-9a93-de8def11a971	Europe	Books	1	473.78	460.27727	460.27727	283.3564251353014	Caitlyn Boyd	1	460.27727	2046	460.27727	58	71709.8323	1035.5858485437743
d4e62769-6f3b-43bf-a938-b76f859eafb0	2019-05-24	09b1d742-9d7c-4fe5-917e-92438864253a	Asia	Electronics	6	84.7	79.33849000000001	476.03094	296.8294116157205	Jason Nelson	1	476.03094	2046	476.03094	70	87933.283392	1049.1629849529377
b50b70e1-c186-42ee-815d-ed1af34d424a	2019-05-29	62ef12b2-48a3-439a-a60c-6254418aa956	South America	Beauty	4	406.07	370.092198	1480.368792	1239.697552851894	Mary Scott	1	1480.368792	2041	1480.368792	63	77562.23517100001	1033.152899764227
4b6677df-c760-4789-88b5-067ebbb7fff1	2019-05-31	a686adbe-3da2-428b-a4e7-35565cb9167c	Europe	Sports	5	31.81	25.183977	125.919885	38.35998999965231	Bradley Howe	1	125.919885	2039	125.919885	56	64186.396558	951.6581100155678
5342f147-8c2e-4032-96b1-bc1ab9d95917	2019-05-31	20f3a542-1753-44bb-a8db-dcf804e8155d	Asia	Sports	7	330.22	294.457174	2061.200218	1808.9730743387177	Roger Brown	1	2061.200218	2039	2061.200218	54	68595.667163	1076.1212096324236
f3b5ca0e-ade9-47a7-a9a2-3218530d542d	2019-06-04	2df26b6f-6c5b-49fe-81d4-9af09457174b	Asia	Electronics	5	388.08	307.980288	1539.90144	1297.7100273360384	Johnny Marshall	1	1539.90144	2035	1539.90144	61	67804.798966	913.3835523608234
d6069cdd-3d7e-470b-9939-1567ed937721	2019-06-05	998dfeb1-e32b-4ede-8d7b-417b93f0ffe9	Australia	Books	3	180.32	168.400848	505.202544	322.0187650377461	Charles Smith	1	505.202544	2034	505.202544	70	95387.089343	1149.437576059358
2d4c515b-6511-452e-9660-971096c027ef	2019-06-05	45559666-b64b-4178-ba04-1c0e2c1b6339	Asia	Home & Kitchen	1	393.33	281.938944	281.938944	139.6174174982332	Caleb Camacho	1	281.938944	2034	281.938944	66	91544.242731	1177.604080808591
6d7387dc-3a6e-40c9-a623-1719153e56a9	2019-06-07	058003d7-9cdf-4c40-bc69-8b4f270dc4ab	North America	Sports	4	30.49	25.724413	102.897652	27.12618513696613	Crystal Williams	1	102.897652	2032	102.897652	65	72555.900913	927.0834787540324
2767981b-311e-4ee7-9057-95ca3dfd74b9	2019-06-08	e15d0e6d-46f8-42e8-96c9-f2519a5f2278	Europe	Beauty	8	15.26	12.691742	101.533936	26.507012184142468	Sandra Luna	1	101.533936	2031	101.533936	56	72688.198308	1090.9576938669472
b916adae-b107-424f-be50-b7f7e31619a9	2019-06-10	c979fc36-f5b3-4376-bcaf-bd16799ba01f	Asia	Books	1	257.08	215.407332	215.407332	92.28224940497284	Johnny Marshall	1	215.407332	2029	215.407332	61	67804.798966	913.3835523608234
331d1c01-ca01-44bc-90d8-9f2aa33fc445	2019-06-11	89735550-9eb0-41eb-af30-b44aa4dca31c	Europe	Sports	2	64.91	51.551522	103.103044	27.219446443512183	Steven Coleman	1	103.103044	2028	103.103044	59	68355.922945	964.8650638967956
546e45b2-ec48-4644-a752-350cf57e09f5	2019-06-13	ef4b4c6f-ae8d-48cb-8923-ecad594a19bc	South America	Toys	8	398.6	392.70072	3141.60576	2878.3000490188915	Mary Scott	1	3141.60576	2026	3141.60576	63	77562.23517100001	1033.152899764227
ae756bba-c22d-4f7e-be8f-58e130175828	2019-06-15	e493b67d-047d-4370-a3be-1d17c3b6f461	Europe	Books	4	432.94	338.212728	1352.850912	1115.8122226022112	Michelle Garza	1	1352.850912	2024	1352.850912	65	76798.491008	980.44596940906
cce9c24f-1f7e-4a48-83e0-87dee36283de	2019-06-17	6a3f5d5f-3cf6-492c-9d02-f528d999a8d5	South America	Toys	8	248.97	182.519907	1460.159256	1220.029130192116	Johnny Marshall	1	1460.159256	2022	1460.159256	61	67804.798966	913.3835523608234
e6c1f011-09b2-471d-9b0a-56a117c46553	2019-06-18	cd48fdd7-df9f-48cb-8ad2-adbf3292c963	Asia	Books	8	75.37	58.56249	468.49992	290.3766137875447	Kristen Ramos	1	468.49992	2021	468.49992	62	73461.618973	988.8412277570784
081bacb1-8e18-4f60-ada7-d0f71deba09f	2019-06-19	41f4a2d8-6289-4385-ba85-ef1f5824ed3c	Europe	Books	3	60.91	51.353221	154.059663	53.76693270900333	Diane Andrews	1	154.059663	2020	154.059663	58	66389.094387	950.0340815608216
0a83bb6e-8d4f-4ce1-ad04-3ef959a0e67c	2019-06-20	8025bdeb-5525-4780-b667-e8e06973d5e2	Australia	Sports	1	238.04	176.93513199999998	176.93513199999998	67.42524031218666	Crystal Williams	1	176.93513199999998	2019	176.93513199999998	65	72555.900913	927.0834787540324
aaae2d78-ea68-4e6d-b861-f1c3504ad80f	2019-06-22	e551075c-5584-49ae-827e-ada3757b3fc2	North America	Electronics	6	413.52	326.47404	1958.84424	1708.2212484059417	Charles Smith	1	1958.84424	2017	1958.84424	70	95387.089343	1149.437576059358
b3b59f75-8dcd-4c8d-b09a-0cb608c2fae5	2019-06-22	acb8ff03-93e8-4d47-90d4-187256fe86a5	Asia	Books	6	289.09	240.985424	1445.912544	1206.1697866257234	Crystal Williams	1	1445.912544	2017	1445.912544	65	72555.900913	927.0834787540324
bbf2710d-066c-4169-b3c6-c3ed2dbbe530	2019-06-28	5bcb02f9-e248-4011-b87c-430eb19b73a7	North America	Toys	2	53.01	47.894535	95.78907	23.94547141003524	Steven Coleman	1	95.78907	2011	95.78907	59	68355.922945	964.8650638967956
4a463ed4-ed64-43dc-b005-e24ec0fad600	2019-06-29	1675dd06-4c4c-414d-8afd-0b1134a9e581	South America	Books	5	282.15	276.365925	1381.829625	1143.9153974557084	Michelle Andersen	1	1381.829625	2010	1381.829625	60	66978.268402	921.082547231716
0074ab4a-96aa-403a-ae7d-cc426be042da	2019-06-30	fd618575-0754-4149-bd91-508af61b95ea	Europe	Toys	9	380.32	294.101456	2646.913104	2387.6659831381	Sandra Luna	1	2646.913104	2009	2646.913104	56	72688.198308	1090.9576938669472
4c52a007-f140-458f-a2fe-90c34fd9f03e	2019-07-02	f79ccc31-a40a-44fd-809c-0a3bda431437	Europe	Clothing	10	285.72	216.918624	2169.18624	1915.4149491415333	Caleb Camacho	1	2169.18624	2007	2169.18624	66	91544.242731	1177.604080808591
da17c60c-8f8e-4481-b455-37dcdf79ead6	2019-07-06	311547c4-0973-49c4-b255-98e924931592	North America	Sports	7	194.42	180.207898	1261.455286	1027.3886565676062	Jason Nelson	1	1261.455286	2003	1261.455286	70	87933.283392	1049.1629849529377
aa56d7d6-8ed0-4e2f-ba8a-773304db6bd6	2019-07-06	d8fd326a-a5d3-41d0-95d0-77346a90aafd	North America	Books	3	326.48	269.80307200000004	809.4092160000001	597.3221140190757	Crystal Williams	1	809.4092160000001	2003	809.4092160000001	65	72555.900913	927.0834787540324
d45ec934-b44d-4209-9806-4a2d3491828a	2019-07-07	86ecaa61-7cfb-403e-9c09-79a429f2d962	Asia	Beauty	3	465.68	344.6032	1033.8096	808.9315002871314	Emily Matthews	1	1033.8096	2002	1033.8096	72	80570.187359	919.786031455556
ede2ede3-4877-4022-8e58-0fdc2aa94aa6	2019-07-08	586ced57-6da4-4528-acf7-5a1d571d0ae7	North America	Clothing	4	93.08	90.65992	362.63968	202.3073429233354	Christina Thompson	1	362.63968	2001	362.63968	53	64491.182614000005	1021.7261378833904
15b13e5d-0be9-4ce1-8dd6-37269acf9765	2019-07-10	edbfafad-8e03-4402-941a-419c1dd64015	Europe	Clothing	7	256.16	243.99240000000003	1707.9468000000002	1461.947750611416	Emily Matthews	1	1707.9468000000002	1999	1707.9468000000002	72	80570.187359	919.786031455556
15d35392-c1e9-454a-bf1d-fba097a7217c	2019-07-12	7885c74b-bed8-4edd-aaa2-f0aa816768ce	South America	Beauty	5	491.1	426.02925	2130.14625	1876.9191636947216	Susan Edwards	1	2130.14625	1997	2130.14625	68	86058.98736700001	1063.159646603474
1a22bcd0-fbb6-4347-85c8-b4f8d5d5ceb2	2019-07-14	7a5a8f5d-0cb4-4215-ad3c-f7b4d96ee943	South America	Sports	10	231.7	189.92449	1899.2449	1649.623437162384	Bradley Howe	1	1899.2449	1995	1899.2449	56	64186.396558	951.6581100155678
c8e1b7e7-fc6d-4101-9b05-82054000a344	2019-07-14	9eae1312-badf-4610-807a-8a91c94c283e	North America	Books	7	413.45	343.452915	2404.170405	2147.462693103017	Michelle Andersen	1	2404.170405	1995	2404.170405	60	66978.268402	921.082547231716
f8e1e3df-74f9-487a-a578-d3ee5cb0b408	2019-07-15	88509dd1-0ae7-437b-b2cd-ca92d4573608	Asia	Toys	6	452.18	402.168892	2413.013352	2156.2059881720697	Charles Smith	1	2413.013352	1994	2413.013352	70	95387.089343	1149.437576059358
e7a01a02-31d4-4e7a-ab4f-afeabf3d9fdb	2019-07-15	2716d3c4-0279-4a74-af76-feda939ab2ad	South America	Clothing	2	490.01	489.617992	979.235984	757.0509763989744	Susan Edwards	1	979.235984	1994	979.235984	68	86058.98736700001	1063.159646603474
16533ec0-aebf-4cf1-91bd-74f910df6431	2019-07-16	38e2c374-0058-47ec-be2d-f20de1143763	Asia	Home & Kitchen	1	106.82	98.723044	98.723044	25.24106111946409	Christina Thompson	1	98.723044	1993	98.723044	53	64491.182614000005	1021.7261378833904
e380b4eb-b14f-479e-941a-6b26e075ce5e	2019-07-25	d8a941f0-7a6b-47df-8439-a8758815375a	North America	Sports	2	82.13	65.991455	131.98291	41.53409558114035	Roger Brown	1	131.98291	1984	131.98291	54	68595.667163	1076.1212096324236
993d146e-b779-4196-876d-3a85d97a96fc	2019-07-27	937d6443-4e6c-4409-b77d-c85dbc3b9e0b	Australia	Beauty	9	107.1	105.18291	946.64619	726.1831633808425	Caleb Camacho	1	946.64619	1982	946.64619	66	91544.242731	1177.604080808591
0f1478e6-2388-4bf5-ac2c-8276f5dd43f8	2019-07-29	baf99d07-10cd-4a26-9419-81b5a12181f4	Asia	Electronics	9	241.18	200.854704	1807.692336	1559.7201640909204	Michelle Garza	1	1807.692336	1980	1807.692336	65	76798.491008	980.44596940906
fa0a1d19-a842-430a-b9a0-e8e0f7071d98	2019-07-30	6d069035-a6a6-4439-b0cb-f55d9d08cc93	South America	Clothing	1	295.7	266.51441	266.51441	128.2305880729518	Joseph Brooks	1	266.51441	1979	266.51441	60	60657.854394	824.8550359343124
2aa0c014-f2e5-4d92-b7ea-9dadf3b41bf3	2019-08-02	22a22e89-f1ff-4204-83e4-f7539c678722	Australia	Beauty	6	447.11	332.113308	1992.679848	1741.510158577796	Steven Coleman	1	1992.679848	1976	1992.679848	59	68355.922945	964.8650638967956
715337c6-2d52-4b79-9672-b8b5d88cea12	2019-08-03	1067ad9b-97a3-4904-a07f-8c08cf0e02e1	Asia	Sports	10	484.16	448.96156800000006	4489.615680000001	4219.511619067972	Christina Thompson	1	4489.615680000001	1975	4489.615680000001	53	64491.182614000005	1021.7261378833904
2ba10d89-99c4-422e-9fde-ad1dd6bb292b	2019-08-04	0e05d887-5e27-45e8-943e-a59a19fb6b74	North America	Home & Kitchen	5	309.48	261.789132	1308.94566	1073.2949092708743	Jason Nelson	1	1308.94566	1974	1308.94566	70	87933.283392	1049.1629849529377
05deb7b2-9816-4dc3-8e63-6c4dc490ffa7	2019-08-08	ba6bca1b-439b-4ce2-8bff-cf083af1f865	Europe	Beauty	2	477.64	375.759388	751.5187759999999	543.6240137659132	Jason Nelson	1	751.5187759999999	1970	751.5187759999999	70	87933.283392	1049.1629849529377
401f3828-a397-4d2f-a0d5-9fdde306c978	2019-08-12	0260e8e8-68c2-46d9-92db-b561e580a6b7	Europe	Clothing	6	137.19	105.938118	635.628708	437.7183465092007	Kristen Ramos	1	635.628708	1966	635.628708	62	73461.618973	988.8412277570784
4b5c2ff5-c227-42fe-8c18-6c5e1a209950	2019-08-16	53347c76-6739-40c9-a879-b38d585d87e7	Europe	Clothing	1	419.21	364.125806	364.125806	203.5056886643141	Michelle Garza	1	364.125806	1962	364.125806	65	76798.491008	980.44596940906
862f6673-d864-43ba-bb1b-1fbf8341a5be	2019-08-20	0acdd49d-2332-4026-a57f-27b3cdd41d9c	Australia	Beauty	3	412.61	347.12879300000003	1041.386379	816.1535779358942	Jason Nelson	1	1041.386379	1958	1041.386379	70	87933.283392	1049.1629849529377
a701f92e-582c-4714-8ee5-bd05b745d320	2019-08-22	97743533-7e12-44f6-b609-25d70a435546	South America	Books	10	340.21	303.195152	3031.95152	2769.4403492437964	Michelle Andersen	1	3031.95152	1956	3031.95152	60	66978.268402	921.082547231716
10968930-3611-459d-8595-85a4ec6a5a0b	2019-08-26	02373f18-707f-43aa-99f3-668b063d4396	South America	Electronics	2	123.99	118.720425	237.44085	107.42176665754025	Crystal Williams	1	237.44085	1952	237.44085	65	72555.900913	927.0834787540324
54e57773-fd8a-4e9c-8d6d-56ac26a58257	2019-08-30	8b2d0bab-d173-42fb-8461-ed2e54f98814	South America	Beauty	3	409.28	399.334496	1198.003488	966.2140930111252	Michelle Garza	1	1198.003488	1948	1198.003488	65	76798.491008	980.44596940906
64fa6323-dfc8-4e8e-8a69-ab42d709266b	2019-08-30	b45952d3-f470-4a98-bd8b-f20f5ea49f6f	Australia	Electronics	2	251.78	229.648538	459.297076	282.521971697021	Jason Nelson	1	459.297076	1948	459.297076	70	87933.283392	1049.1629849529377
6b5b8337-12ae-41cd-81e5-7f8070abeff1	2019-09-01	5f9b8be9-9fe1-46c4-a239-819e58d3087c	Asia	Toys	5	35.33	25.833296	129.16648	40.05542101414281	Diane Andrews	1	129.16648	1946	129.16648	58	66389.094387	950.0340815608216
d63b929c-3b55-462a-8f45-a89ecd735d18	2019-09-01	8b7ef812-59c9-444c-913b-f190d6c96647	Asia	Toys	9	131.9	106.98409	962.85681	741.5256811123371	Caleb Camacho	1	962.85681	1946	962.85681	66	91544.242731	1177.604080808591
6e5623fc-a134-4172-ac52-b4b0cdb29a15	2019-09-03	c5bd5aef-3eaf-4183-8a4a-9ae91cf7fdda	North America	Electronics	3	284.59	214.29627	642.8888099999999	444.28244299351246	Jason Nelson	1	642.8888099999999	1944	642.8888099999999	70	87933.283392	1049.1629849529377
b200109a-167a-4103-93d9-8440f67b9916	2019-09-03	5e5de608-d7a1-4b47-82dc-f8fd62591092	Australia	Electronics	8	79.66	62.45344	499.62752	317.18183075406245	Caleb Camacho	1	499.62752	1944	499.62752	66	91544.242731	1177.604080808591
7c0055f9-bfef-4c42-9ee0-42d0e9243677	2019-09-07	bcd8835e-0f59-4e0b-bc07-681847029466	South America	Toys	1	320.5	244.4774	244.4774	112.37743782352624	Steven Coleman	1	244.4774	1940	244.4774	59	68355.922945	964.8650638967956
045fa8be-ce9d-4c74-8039-8c513588cec2	2019-09-12	5384acea-8b60-444e-8b32-003b9fa76921	North America	Toys	3	113.69	106.845862	320.537586	169.00466584683022	Michelle Andersen	1	320.537586	1935	320.537586	60	66978.268402	921.082547231716
0009db93-da9e-4420-9dcc-c0f3b1e713cb	2019-09-12	85139095-6e09-403f-af75-ffe3b5a3ebdf	Australia	Books	2	165.74	137.415034	274.830068	134.34544498716966	Sandra Luna	1	274.830068	1935	274.830068	56	72688.198308	1090.9576938669472
b230cac1-c85f-4cdb-a916-ac2dfa0f74bc	2019-09-12	728e88ad-5b01-4f02-a12f-c52f09d62e16	Europe	Home & Kitchen	3	361.97	290.98768300000006	872.9630490000002	656.7492907337462	Michelle Andersen	1	872.9630490000002	1935	872.9630490000002	60	66978.268402	921.082547231716
91226729-a136-477c-b175-aa03c1fc3ff1	2019-09-15	b9e3b672-b1eb-47a7-a099-2f247ea6f4d0	Australia	Beauty	2	133.09	117.478543	234.957086	105.68932301584508	Susan Edwards	1	234.957086	1932	234.957086	68	86058.98736700001	1063.159646603474
24aa13fa-f8cc-4bd0-8715-5e55d9bee116	2019-09-16	ac1b372f-f106-4155-90db-49eed813a534	Australia	Home & Kitchen	5	409.96	378.229096	1891.14548	1641.6638658158647	Joseph Brooks	1	1891.14548	1931	1891.14548	60	60657.854394	824.8550359343124
3a58aad3-d295-47f1-a683-2c6306116b13	2019-09-19	59fbec3f-b4c6-4a11-8c46-3e0d80d964e9	Europe	Sports	5	199	142.8024	714.0120000000001	509.0952281023993	Johnny Marshall	1	714.0120000000001	1928	714.0120000000001	61	67804.798966	913.3835523608234
dbada6fb-44c7-47d1-a94a-1ef4c25634d3	2019-09-24	bbb89b6f-64ac-4b62-ae7b-aa5184685900	Asia	Clothing	9	250.01	216.308652	1946.777868	1696.3530017166672	Bradley Howe	1	1946.777868	1923	1946.777868	56	64186.396558	951.6581100155678
7d297d2d-7a44-4f81-b0fe-2b3e0c5fa26d	2019-09-24	b9d2b242-b3e1-4a7a-aecc-f2aaff29bbef	Australia	Home & Kitchen	9	487.8	471.26358	4241.37222	3972.215460258916	Roger Brown	1	4241.37222	1923	4241.37222	54	68595.667163	1076.1212096324236
698a23b8-c9da-4172-910b-1555299d136c	2019-09-25	b692761b-f1f4-41e0-a03c-39fe2197c172	Europe	Books	7	209.07	152.24477399999998	1065.7134179999998	839.360795341659	Susan Edwards	1	1065.7134179999998	1922	1065.7134179999998	68	86058.98736700001	1063.159646603474
31831acb-ae0e-43d1-b430-6741bb0abdd1	2019-09-27	30e9807e-4c63-42dc-bfc2-3d49aca22cdb	Asia	Electronics	9	462.12	433.00644000000005	3897.057960000001	3629.402880329671	Caitlyn Boyd	1	3897.057960000001	1920	3897.057960000001	58	71709.8323	1035.5858485437743
8e87473b-e40a-4336-8aeb-e144deab8fed	2019-09-30	4833ec30-6435-4c73-82b7-28acffdffb6c	Asia	Toys	2	64.71	46.87592399999999	93.75184799999998	23.059759325591912	Mary Scott	1	93.75184799999998	1917	93.75184799999998	63	77562.23517100001	1033.152899764227
23e34778-0cdc-4fc3-a23a-f9f16e19e45c	2019-10-02	ceb3c5fc-41d3-46ed-ad01-31256fdf0708	South America	Home & Kitchen	10	76.24	55.00716	550.0716	361.3030344543583	Bradley Howe	1	550.0716	1915	550.0716	56	64186.396558	951.6581100155678
01b89e2f-d08d-4c0c-8306-d69ffcc7ce1e	2019-10-02	d7bce075-128b-4109-9a87-53fa113bd7f9	Asia	Toys	7	169.62	168.51747	1179.62229	948.5277087481634	Kristen Ramos	1	1179.62229	1915	1179.62229	62	73461.618973	988.8412277570784
18bacb9a-b2dc-424f-9170-4a12796b8087	2019-10-02	3401d199-8d53-41e8-b86c-18986d905b6c	Asia	Electronics	1	484.88	391.5406	391.5406	225.80211371486624	Roger Brown	1	391.5406	1915	391.5406	54	68595.667163	1076.1212096324236
55f906d9-6bc9-4e63-93c4-946768e27342	2019-10-03	9a4a2cb1-44ce-45bb-a8d5-18cc9d930de7	Europe	Clothing	6	366.05	290.53388500000005	1743.2033100000003	1496.4828641716797	Caleb Camacho	1	1743.2033100000003	1914	1743.2033100000003	66	91544.242731	1177.604080808591
e3e14dd2-4306-447b-8cbd-cc533a4aab2c	2019-10-04	bce52048-eacc-4cdb-a1ee-f721c74c0a3e	North America	Toys	6	141.25	103.1125	618.675	422.4384408602151	Adam Smith	1	618.675	1913	618.675	55	62372.113224	936.3944649146875
36fd04d7-a839-4ecc-a398-5c37a319912b	2019-10-07	4bc9ba92-266f-4083-b5f6-d98cfd8c5092	North America	Sports	10	168.93	164.858787	1648.58787	1403.855914772353	Charles Smith	1	1648.58787	1910	1648.58787	70	95387.089343	1149.437576059358
41e085ff-fbbc-4395-aac0-3bca83b39b42	2019-10-09	834fb3b2-eaa9-43e0-989a-76a433c1be4b	South America	Sports	1	54.57	48.687354	48.687354	7.052879910723448	Joseph Brooks	1	48.687354	1908	48.687354	60	60657.854394	824.8550359343124
bfbe8247-09c4-42bb-a761-d7bf3aa85138	2019-10-09	7310e5dc-ff86-4675-be5d-a5da3bea8205	Asia	Clothing	3	140.59	104.542724	313.628172	163.6601272431502	Steven Coleman	1	313.628172	1908	313.628172	59	68355.922945	964.8650638967956
eec12104-4e50-4352-bcba-e3efd2e1524f	2019-10-11	8820f339-dee8-4968-95ae-0339325c6d09	North America	Beauty	10	367.08	335.621244	3356.21244	3091.487249316853	Charles Smith	1	3356.21244	1906	3356.21244	70	95387.089343	1149.437576059358
17b88319-6804-4508-80be-0eabb77bb726	2019-10-12	d204fdfd-b850-4006-b6bb-d991907f891e	South America	Books	10	201.58	172.814534	1728.14534	1481.7320992539785	Johnny Marshall	1	1728.14534	1905	1728.14534	61	67804.798966	913.3835523608234
0ba2c887-b4c2-42e6-b449-2cdd5a4b3472	2019-10-12	9eff292e-7f28-49f0-9b07-2dfd52125440	Asia	Clothing	3	173.55	139.239165	417.717495	247.4637778612187	Caitlyn Boyd	1	417.717495	1905	417.717495	58	71709.8323	1035.5858485437743
24909c05-27ea-48ab-a4a0-5c10f70a0f77	2019-10-13	826a483b-ffd9-4162-8b73-5bae3abe4511	Asia	Toys	7	499.76	454.231864	3179.6230480000004	2916.051390451673	Susan Edwards	1	3179.6230480000004	1904	3179.6230480000004	68	86058.98736700001	1063.159646603474
5ab99e4e-13a6-4777-9eb8-13c517e49ce0	2019-10-14	b7b6d342-1838-4423-86be-7d05a1af91a5	Asia	Sports	10	184.78	144.553394	1445.53394	1205.802283892003	Charles Smith	1	1445.53394	1903	1445.53394	70	95387.089343	1149.437576059358
d4fc6352-4518-4d90-90b8-4c25dd109123	2019-10-15	e955b5c9-01f8-4d1e-8d74-1a81eb5fd78c	Europe	Beauty	1	185.81	142.08890699999998	142.08890699999998	47.00800028158457	Christina Thompson	1	142.08890699999998	1902	142.08890699999998	53	64491.182614000005	1021.7261378833904
5b276dd0-9076-4e8d-b899-fa07d6ac3fba	2019-10-17	9f596fac-b352-4f4e-9863-cc6573f63889	Europe	Electronics	6	52.15	42.215425	253.29255	118.65557025195343	Charles Smith	1	253.29255	1900	253.29255	70	95387.089343	1149.437576059358
55885fe3-894e-418a-bc52-28ad50fc9bf9	2019-10-18	eaf2f7ac-1a86-4165-a56f-fea5c632591e	Asia	Books	8	333.51	279.047817	2232.382536	1977.768151839958	Michelle Andersen	1	2232.382536	1899	2232.382536	60	66978.268402	921.082547231716
223a660b-684f-496c-a376-fdde07b3ea3e	2019-10-23	f8039d2e-b14b-47ff-a11c-91ed35c9e7e6	North America	Beauty	7	25.14	18.658908	130.612356	40.81355503746991	Jason Nelson	1	130.612356	1894	130.612356	70	87933.283392	1049.1629849529377
99add11c-f612-4ea5-90f8-0e196050c803	2019-10-26	7bcf1866-c0f4-426f-9580-3cf9c407b1a6	Australia	Clothing	8	275.94	195.475896	1563.8071679999998	1321.02897602012	Crystal Williams	1	1563.8071679999998	1891	1563.8071679999998	65	72555.900913	927.0834787540324
8415aa6d-ab66-4dc1-b1e2-395e1972a496	2019-10-29	5eb7a524-ad70-4aa6-8302-bdd2a12a093c	South America	Toys	4	53.3	40.26282	161.05128	57.83974449628301	Caleb Camacho	1	161.05128	1888	161.05128	66	91544.242731	1177.604080808591
1fee224d-bdcb-4b65-8c32-acf60292cff5	2019-11-04	1078b7d4-d2da-4ea3-98c9-b0a2941aa34b	Australia	Home & Kitchen	6	7.86	6.94038	41.64228	5.2702999144030045	Roger Brown	1	41.64228	1882	41.64228	54	68595.667163	1076.1212096324236
4cca17cc-fa70-4767-b691-5f211bb4658c	2019-11-04	11eb2260-a2ac-4a74-9eee-0d1421f32ed6	South America	Sports	5	434.44	340.991956	1704.9597799999997	1459.0225596610169	Emily Matthews	1	1704.9597799999997	1882	1704.9597799999997	72	80570.187359	919.786031455556
585a4b31-c0ab-4cac-9a36-450c0e50a9bf	2019-11-05	935c23c3-d038-4899-b226-2d52df570aaa	South America	Toys	10	460.5	443.7378	4437.378	4167.466138150011	Johnny Marshall	1	4437.378	1881	4437.378	61	67804.798966	913.3835523608234
9c899244-1484-4aa4-ba3c-716b2ff0eccd	2019-11-05	e570c789-13c9-446d-89ec-cfafb149f912	South America	Beauty	3	263.22	244.47873600000003	733.4362080000001	526.9507890810811	Emily Matthews	1	733.4362080000001	1881	733.4362080000001	72	80570.187359	919.786031455556
385e6b0e-340a-45e0-b8cb-a5bf580f6bd6	2019-11-05	793c0555-95cb-43b8-a59f-8ca1f559c129	Australia	Toys	1	495.17	346.718034	346.718034	189.5760679013778	Sandra Luna	1	346.718034	1881	346.718034	56	72688.198308	1090.9576938669472
d9a271a9-284d-4f92-9117-b1c778ed5c19	2019-11-05	d3cc7579-3ca7-4b2b-9bf3-3f2b41c96713	Asia	Sports	10	443.72	434.490624	4344.90624	4075.342685530856	Christina Thompson	1	4344.90624	1881	4344.90624	53	64491.182614000005	1021.7261378833904
13fb2d98-1b7d-49a0-9bc0-9fa2ad2fb3cd	2019-11-13	240eb86b-2cec-46db-8581-b6c5a0f32271	North America	Toys	7	486.41	450.464301	3153.2501070000003	2889.862498767389	Kristen Ramos	1	3153.2501070000003	1873	3153.2501070000003	62	73461.618973	988.8412277570784
91ce5e61-83b2-483b-9dfa-0564b01541be	2019-11-14	0099cbbc-fa79-485d-8504-ef48f8c36533	Europe	Electronics	7	480.59	413.739931	2896.179517	2634.73012300863	Michelle Garza	1	2896.179517	1872	2896.179517	65	76798.491008	980.44596940906
ad9db7d1-f9aa-4bd0-968b-33d3c4f82a94	2019-11-15	975610ab-c16e-4ccc-b893-fe8b70c20132	Europe	Electronics	8	267.41	264.067375	2112.539	1859.56152505778	Charles Smith	1	2112.539	1871	2112.539	70	95387.089343	1149.437576059358
de4697e6-94ed-476c-87e0-d758c2535ae0	2019-11-17	c8b30193-4b66-4212-80fe-a8b32ba80572	Asia	Books	8	166.7	155.56444	1244.51552	1011.0404487107908	Bradley Howe	1	1244.51552	1869	1244.51552	56	64186.396558	951.6581100155678
b7f33eb3-f6c2-4911-bfa4-693acdae487d	2019-11-18	d1813c06-84d2-47cb-a12f-630ccff05113	Australia	Home & Kitchen	1	96.98	94.031808	94.031808	23.18204308137432	Emily Matthews	1	94.031808	1868	94.031808	72	80570.187359	919.786031455556
0e77b65f-2827-444e-81b5-9636f4d42f61	2019-11-18	4c2b4366-ba50-430b-bfb5-26082b7d13ad	Asia	Clothing	5	484.95	427.289445	2136.447225	1883.130583232846	Kristen Ramos	1	2136.447225	1868	2136.447225	62	73461.618973	988.8412277570784
37fd7417-a68f-4274-a69f-8ae70b3d9fba	2019-11-18	84178d5d-6278-4673-846d-7e5ace286333	Australia	Toys	7	427.95	360.67626	2524.73382	2266.7103532297724	Diane Andrews	1	2524.73382	1868	2524.73382	58	66389.094387	950.0340815608216
ae921c2c-8c37-42d5-bc3a-c8006f33f919	2019-11-26	de938c0e-a404-443f-9fff-ea29ea056cbf	Australia	Electronics	2	439.85	326.28073	652.56146	453.0379903002507	Charles Smith	1	652.56146	1860	652.56146	70	95387.089343	1149.437576059358
5392d1ee-3040-42b5-8169-b3ed53c0e702	2019-11-27	6a5acc70-446a-47d1-a8c0-9f6924041e93	South America	Toys	4	291.73	211.241693	844.966772	630.513643399203	Adam Smith	1	844.966772	1859	844.966772	55	62372.113224	936.3944649146875
af097793-6c3d-47a2-9a42-b05e1782e44e	2019-11-28	f8576361-07a6-4daf-ac4f-6b6a7ab4c2e5	Asia	Electronics	2	201.62	187.990488	375.980976	213.09172203587207	Emily Matthews	1	375.980976	1858	375.980976	72	80570.187359	919.786031455556
2f5e5573-6b4d-4a21-83d2-e6b718a09331	2019-11-28	aae7781d-5dc2-4b70-8387-31435ee0e9ba	Asia	Sports	6	104.18	75.655516	453.933096	277.9559314332235	Caleb Camacho	1	453.933096	1858	453.933096	66	91544.242731	1177.604080808591
64d6533e-dccb-4c82-bfb6-c6864718d151	2019-11-28	d19bd9fb-f580-491a-b354-a89e28f20abd	North America	Beauty	1	223.26	187.449096	187.449096	73.99485559326959	Michelle Andersen	1	187.449096	1858	187.449096	60	66978.268402	921.082547231716
a69311a8-769e-4a47-b962-c1546110c243	2019-11-29	512378d9-bbe4-4024-b0ca-1455ce454458	Asia	Clothing	1	138.73	131.571532	131.571532	41.318045925092605	Susan Edwards	1	131.571532	1857	131.571532	68	86058.98736700001	1063.159646603474
e4fb3ad0-40d5-47c8-8a37-8c859704e503	2019-11-30	c81ccf2e-4a1a-4ff3-89cf-2b2d3b720947	Europe	Clothing	10	70.44	57.648096	576.48096	384.6978135214079	Caitlyn Boyd	1	576.48096	1856	576.48096	58	71709.8323	1035.5858485437743
bcb99a7b-6213-4272-b615-15ed80664dfe	2019-12-02	a1a48cfb-8972-48d5-a75b-6d5ffd82a965	Asia	Clothing	1	187.12	178.79316	178.79316	68.56989386351027	Jason Nelson	1	178.79316	1854	178.79316	70	87933.283392	1049.1629849529377
11ed1a38-8ccb-4d28-a03d-98b8cc6bb7fe	2019-12-03	da49a741-1e57-40b1-b2cb-75c057728d12	Australia	Books	3	60.98	57.119966	171.359898	64.01171908626198	Mary Scott	1	171.359898	1853	171.359898	63	77562.23517100001	1033.152899764227
f45c1bd2-d176-4338-b548-d5a8b6973d87	2019-12-04	1892b1d1-9690-4732-86bc-b90e011aa113	South America	Beauty	8	51.42	46.797342	374.378736	211.79623024588528	Michelle Andersen	1	374.378736	1852	374.378736	60	66978.268402	921.082547231716
f7ecd108-a09c-4667-abd8-4bfa4fe155b9	2019-12-10	0555f386-0f83-41bf-92f4-3fe13fa2dbf1	Australia	Toys	5	235.63	200.379752	1001.89876	778.5697153742589	Diane Andrews	1	1001.89876	1846	1001.89876	58	66389.094387	950.0340815608216
7f22cb39-598f-4d13-bd74-021cfa8488c5	2019-12-12	30a079c4-1453-4aca-b6b8-8be96679f4e4	Asia	Electronics	8	177.32	146.714568	1173.716544	942.851763512195	Christina Thompson	1	1173.716544	1844	1173.716544	53	64491.182614000005	1021.7261378833904
a75db13c-4f7d-45c9-9d76-bf5da71eb446	2019-12-15	299c1694-a5dc-417b-9358-8b34f42dbdae	North America	Electronics	8	301.13	248.221459	1985.771672	1734.7132528637603	Adam Smith	1	1985.771672	1841	1985.771672	55	62372.113224	936.3944649146875
a3856471-0db9-45ef-b167-bf168cc98ae5	2019-12-16	0046530b-cdfa-4eef-868c-0ab173b72c39	South America	Beauty	4	320.27	314.50514	1258.02056	1024.0703321905044	Diane Andrews	1	1258.02056	1840	1258.02056	58	66389.094387	950.0340815608216
6d8ecdcc-1906-4d32-88f4-1c1f72b59c55	2019-12-16	953318a1-ecd9-45e2-ad17-20fc9e430097	Asia	Toys	3	103.57	88.05521399999999	264.165642	126.52201861525634	Joseph Brooks	1	264.165642	1840	264.165642	60	60657.854394	824.8550359343124
95350b66-8c61-458e-9bda-f193544f4b9c	2019-12-18	790cb4cd-e9b6-4091-8e69-150474215289	South America	Beauty	2	423.72	370.797372	741.594744	534.4685167628198	Mary Scott	1	741.594744	1838	741.594744	63	77562.23517100001	1033.152899764227
32f9171b-bd88-441e-91c7-62c92923946b	2019-12-20	470d3e22-54aa-4f75-a219-11fe209ce8cb	North America	Home & Kitchen	2	290.93	275.80164	551.60328	362.6527507635392	Charles Smith	1	551.60328	1836	551.60328	70	95387.089343	1149.437576059358
cf930be6-f46a-41d9-b2e3-9a7491a66d06	2019-12-23	6bedfb83-7930-44aa-933f-21818c6ed205	Australia	Clothing	5	442.12	412.763232	2063.8161600000003	1811.552902776121	Caitlyn Boyd	1	2063.8161600000003	1833	2063.8161600000003	58	71709.8323	1035.5858485437743
f87b42ee-2086-426f-baf5-84ab21e1c7e9	2019-12-24	f2a9949d-4149-43cc-a854-88feb9c61266	South America	Home & Kitchen	6	479.47	402.467118	2414.802708	2157.974376084745	Jason Nelson	1	2414.802708	1832	2414.802708	70	87933.283392	1049.1629849529377
14debc25-b032-409c-b3ca-ed0f702bf046	2019-12-25	a0c74017-0008-4a69-96cb-08fb64f405ea	Asia	Books	1	153.87	153.839226	153.839226	53.63781520080765	Mary Scott	1	153.839226	1831	153.839226	63	77562.23517100001	1033.152899764227
0639ba4e-907b-45e7-8b9e-4ffe1d8c053e	2019-12-27	c17110b7-c454-4b0a-8029-7c4f7cea926d	Asia	Books	5	92.77	65.105986	325.52993000000004	172.8924610639096	Johnny Marshall	1	325.52993000000004	1829	325.52993000000004	61	67804.798966	913.3835523608234
4e655475-2c1b-4a62-b592-7cb9ff818baa	2019-12-31	722d9001-4d4c-4b70-a4d8-246b14dfda16	Australia	Beauty	6	459.93	334.36911	2006.21466	1754.8313653015398	Johnny Marshall	1	2006.21466	1825	2006.21466	61	67804.798966	913.3835523608234
06e8eb52-4f63-4554-9949-88a47e92f60d	2020-01-03	56660054-7fbe-4d0e-ba9d-390ad98bc22f	Australia	Sports	4	208.45	161.236075	644.9443	446.1389919022225	Susan Edwards	1	644.9443	1822	644.9443	68	86058.98736700001	1063.159646603474
40c16986-0848-45f4-b652-9d8c8fdd6ca3	2020-01-03	1b55b120-3fdd-455c-8f8a-5673f937ab9f	Australia	Electronics	6	422.86	361.418442	2168.510652	1914.747147424439	Diane Andrews	1	2168.510652	1822	2168.510652	58	66389.094387	950.0340815608216
3b39c66d-91d2-4641-bde2-2c423fea30f3	2020-01-05	91529359-62e2-46f5-9320-7f86c7550f5e	Europe	Electronics	10	48.24	41.87232	418.7232	248.3026871794872	Joseph Brooks	1	418.7232	1820	418.7232	60	60657.854394	824.8550359343124
02feef39-76ea-4ffa-9f6e-734c3dd5eb57	2020-01-11	54523150-45c6-432e-b26c-7d665ffa5694	Europe	Sports	3	214.73	151.878529	455.635587	279.40150832745417	Michelle Garza	1	455.635587	1814	455.635587	65	76798.491008	980.44596940906
81dc03b4-77b9-4f3e-bdaa-dd08e6c929f1	2020-01-12	f6261b96-cb4f-4dbc-8040-d7b35de4a0c6	Europe	Toys	10	409.78	355.811974	3558.11974	3292.203432808992	Johnny Marshall	1	3558.11974	1813	3558.11974	61	67804.798966	913.3835523608234
bd5dc9ce-1099-4b6f-8a5b-3ccb6da00b27	2020-01-13	907ea9c9-7a2d-4d15-8f61-dd5b356e376f	North America	Toys	9	137.16	111.799116	1006.192044	782.6484559881807	Jason Nelson	1	1006.192044	1812	1006.192044	70	87933.283392	1049.1629849529377
ae57ca11-e8e2-4969-b464-aaa2ef8682fe	2020-01-15	c29cd174-c9a3-4654-a8d3-3621ae3397e8	North America	Books	10	16.33	15.335503	153.35503	53.358270740740736	Crystal Williams	1	153.35503	1810	153.35503	65	72555.900913	927.0834787540324
e38dc580-1e36-4ebb-a073-e63eee7a66c6	2020-01-15	3a2b75d5-ac54-4a42-917e-3f02c7209f62	Australia	Home & Kitchen	3	381.45	328.8099	986.4297	763.8748864720347	Caleb Camacho	1	986.4297	1810	986.4297	66	91544.242731	1177.604080808591
a516b8e3-bf50-47f9-84e4-f776bc759c8e	2020-01-16	3698c3ac-2be9-4733-b22e-3e1678044c08	North America	Books	1	149.73	111.414093	111.414093	31.127220477120417	Adam Smith	1	111.414093	1809	111.414093	55	62372.113224	936.3944649146875
12dad0a7-62ab-4de3-b176-a70b669351f9	2020-01-17	93d5237c-a006-467f-bcd7-88f00bb194f5	South America	Home & Kitchen	4	394.92	294.2154	1176.8616	945.8734353647764	Diane Andrews	1	1176.8616	1808	1176.8616	58	66389.094387	950.0340815608216
6757684c-06d5-4a35-9e94-75439993b845	2020-01-18	5152b37a-8d0e-4fd6-a5a0-94b58068250a	South America	Books	8	311.34	288.861252	2310.890016	2055.283209522697	Adam Smith	1	2310.890016	1807	2310.890016	55	62372.113224	936.3944649146875
d4a09ad4-7b34-4f1e-89d4-a9c181c27e51	2020-01-21	72b00358-5d9e-4c11-b833-14997ac4e024	South America	Clothing	7	396.16	358.12864	2506.90048	2249.065833958181	Caleb Camacho	1	2506.90048	1804	2506.90048	66	91544.242731	1177.604080808591
4a9c8cf5-0e18-406b-af15-756c8e3f3c74	2020-01-22	16e31370-84ec-4a3b-94a6-c1a07ed525ba	Asia	Books	9	360.21	275.416566	2478.749094	2221.2140449085805	Charles Smith	1	2478.749094	1803	2478.749094	70	95387.089343	1149.437576059358
371f1f3b-c770-47c1-b09e-cf98a1a1f5ff	2020-01-23	46bf70ba-5b7e-45df-b8a4-7b4e05fba3e5	North America	Home & Kitchen	10	245.36	216.382984	2163.8298400000003	1910.130171805232	Joseph Brooks	1	2163.8298400000003	1802	2163.8298400000003	60	60657.854394	824.8550359343124
687e14d0-5966-4d68-a108-82f9a21f9577	2020-01-29	3be097c5-64b3-4dd2-a6ac-a292850bfab2	Australia	Clothing	1	165.78	118.134828	118.134828	34.41064089865344	Emily Matthews	1	118.134828	1796	118.134828	72	80570.187359	919.786031455556
3a0e1622-61a9-488f-9768-ff935939ab69	2020-02-04	093145d7-2b52-4d8e-9156-50264e1335db	Europe	Toys	2	483.53	464.285506	928.571012	709.1025619881824	Susan Edwards	1	928.571012	1790	928.571012	68	86058.98736700001	1063.159646603474
e0a00fd5-2d5c-4054-876d-8988fbd7ea9a	2020-02-06	1d6fa625-d2a0-4eec-908f-c03124223895	South America	Electronics	10	444.02	438.425348	4384.253479999999	4114.539574295979	Roger Brown	1	4384.253479999999	1788	4384.253479999999	54	68595.667163	1076.1212096324236
c0c75f17-f445-4b3f-b492-55139be15ec3	2020-02-09	29242958-d031-4479-aeb6-ad259729998c	Europe	Beauty	6	374.47	272.08990200000005	1632.5394120000003	1388.1655759098871	Susan Edwards	1	1632.5394120000003	1785	1632.5394120000003	68	86058.98736700001	1063.159646603474
09816cee-6096-4483-9c8b-0313bbaa224e	2020-02-11	67420f05-a6fa-4619-abbe-042847a057db	Europe	Toys	1	414.62	378.050516	378.050516	214.7739693989807	Christina Thompson	1	378.050516	1783	378.050516	53	64491.182614000005	1021.7261378833904
63617502-03d5-429c-ab4c-612f0eb746bb	2020-02-16	30691e5f-1b7f-4279-ae91-e41c4dfa1175	South America	Home & Kitchen	7	455.76	453.526776	3174.687432	2911.151348324244	Jason Nelson	1	3174.687432	1778	3174.687432	70	87933.283392	1049.1629849529377
647800f2-8c77-42a6-b758-c5450b948513	2020-02-16	72e994a4-1864-450b-819d-abded6b82480	Europe	Toys	4	331.82	258.122778	1032.491112	807.6748615100814	Caleb Camacho	1	1032.491112	1778	1032.491112	66	91544.242731	1177.604080808591
d31da186-6440-4e0c-a0a1-b379ff885e74	2020-02-16	6a3f73b1-3573-4b0a-bb11-7f3c5116adb4	Australia	Home & Kitchen	1	431.81	398.47426800000005	398.47426800000005	231.50411589440608	Adam Smith	1	398.47426800000005	1778	398.47426800000005	55	62372.113224	936.3944649146875
4c562f81-2f05-4eae-a345-3ffdbac41071	2020-02-17	588e964e-2ef3-4613-8a5a-95879c79c66d	Europe	Clothing	3	251.49	219.575919	658.727757	458.63427350921904	Adam Smith	1	658.727757	1777	658.727757	55	62372.113224	936.3944649146875
3d78cb02-ed5b-4507-8731-2dae49a9065c	2020-02-20	4a3a6555-844a-463c-83c2-50ecb5049a35	Australia	Beauty	9	107.48	80.244568	722.201112	516.6156663567992	Joseph Brooks	1	722.201112	1774	722.201112	60	60657.854394	824.8550359343124
034037f3-f12c-4b76-b109-8530fef17b2e	2020-02-22	646ac59d-0905-4f5a-abf2-8ee4f89e5147	North America	Books	3	211.78	203.224088	609.672264	414.3521307264689	Crystal Williams	1	609.672264	1772	609.672264	65	72555.900913	927.0834787540324
158ec849-a206-4d49-b9b4-f31025717802	2020-02-22	c8de2121-f36f-4d84-9fa7-e9790f9034a8	North America	Home & Kitchen	7	123.72	122.532288	857.726016	642.4603575735977	Crystal Williams	1	857.726016	1772	857.726016	65	72555.900913	927.0834787540324
b24c4e02-df5b-4bc0-a1cd-aa04010db888	2020-02-24	a5307f42-50e6-4b51-8b6b-d0c7b91b1550	Europe	Clothing	2	198.96	185.012904	370.025808	208.26589193442624	Roger Brown	1	370.025808	1770	370.025808	54	68595.667163	1076.1212096324236
1e920a42-b70d-401a-84f7-1fb696d59592	2020-02-25	dfa27875-da44-49e7-b7ed-b4957a3221c8	South America	Toys	8	14.94	11.200518	89.604144	21.29788999786554	Susan Edwards	1	89.604144	1769	89.604144	68	86058.98736700001	1063.159646603474
88b1f18a-47ed-4d28-be65-ebb0b9b8aaf7	2020-02-29	90423dfc-e28c-47bd-9f42-015090ffdee9	North America	Books	1	461.28	335.857968	335.857968	180.98479267951672	Jason Nelson	1	335.857968	1765	335.857968	70	87933.283392	1049.1629849529377
dd041904-f92a-4e78-a7c0-d0dabc97a84f	2020-03-01	ba4b3619-9d53-4511-bb82-6ea8568c38b2	Asia	Sports	10	76.75	57.20945	572.0945	380.7969342941216	Mary Scott	1	572.0945	1764	572.0945	63	77562.23517100001	1033.152899764227
74f496d1-3f20-4585-8019-67714fe0b601	2020-03-04	f5dc3233-3ebc-4643-83c0-83472a9e9495	Europe	Clothing	5	476.23	350.743395	1753.7169749999998	1506.7876195980764	Michelle Andersen	1	1753.7169749999998	1761	1753.7169749999998	60	66978.268402	921.082547231716
5ac71de1-3a90-43c2-a3f6-64aa0ef42199	2020-03-05	4d37f977-ae9c-49d6-ab35-37fd050f8786	North America	Electronics	6	277.17	275.396112	1652.376672	1407.5619935793763	Crystal Williams	1	1652.376672	1760	1652.376672	65	72555.900913	927.0834787540324
9eb905f4-4ebf-4406-84cd-808ff38d155c	2020-03-07	c429d424-c599-47c9-a5fc-055196f174a1	North America	Toys	3	182.98	148.85423	446.56269	271.7006452040097	Jason Nelson	1	446.56269	1758	446.56269	70	87933.283392	1049.1629849529377
f0c22511-96a9-4841-86e2-9ceeb9abde79	2020-03-09	6fba3af3-7e09-4ac6-9bd4-212cec225de3	Asia	Electronics	2	198.08	195.524768	391.049536	225.3997134897276	Christina Thompson	1	391.049536	1756	391.049536	53	64491.182614000005	1021.7261378833904
3742dba2-ab39-43e1-bd4a-785eb403e88e	2020-03-11	8eecc5d1-fa2c-41a6-938b-41b3c4ed7717	South America	Toys	7	354.81	264.972108	1854.804756	1605.967938226754	Johnny Marshall	1	1854.804756	1754	1854.804756	61	67804.798966	913.3835523608234
c564d7f8-57a0-4f10-87b0-2e52eb500918	2020-03-12	20e6da18-605a-4247-9488-55e3145401d0	Australia	Sports	6	477.87	348.271656	2089.6299360000003	1836.984556239391	Crystal Williams	1	2089.6299360000003	1753	2089.6299360000003	65	72555.900913	927.0834787540324
c0d52cbf-bdcd-43ce-8eba-6e6b6947b8bb	2020-03-13	f7f9e0d0-f2cd-47e4-8316-a566c3a10364	Europe	Toys	8	185.33	148.18986800000002	1185.518944	954.202687926948	Mary Scott	1	1185.518944	1752	1185.518944	63	77562.23517100001	1033.152899764227
d423d562-55d4-4058-b210-0f9216d61710	2020-03-14	12cdcc94-52f7-437a-a683-ffbf11fbd422	Asia	Beauty	10	147.45	112.165215	1121.65215	892.8742781716571	Sandra Luna	1	1121.65215	1751	1121.65215	56	72688.198308	1090.9576938669472
b80eee54-d174-4776-93e1-b16a527402d6	2020-03-15	e425690e-603a-4261-bcfa-c171653b0d16	North America	Books	9	432.33	417.241683	3755.175147	3488.212609090244	Susan Edwards	1	3755.175147	1750	3755.175147	68	86058.98736700001	1063.159646603474
9b9acbfa-8291-485d-81c2-cd03bbb08e94	2020-03-15	33e53667-7da6-4ce3-87a2-8ed84c0ce2c0	Europe	Clothing	10	332.28	243.528012	2435.28012	2178.223202428196	Caitlyn Boyd	1	2435.28012	1750	2435.28012	58	71709.8323	1035.5858485437743
5d5599cf-1a9f-40af-a98c-2087b5667f65	2020-03-16	a075bba2-590a-4665-a6f5-5bbd8d6a19f3	Australia	Home & Kitchen	5	385.19	307.651253	1538.256265	1296.1027065024243	Kristen Ramos	1	1538.256265	1749	1538.256265	62	73461.618973	988.8412277570784
ccce15ac-b978-4553-9d11-920973fd0e0d	2020-03-29	eab8fa34-744a-4327-8ab1-b0f8a632e42f	North America	Clothing	6	226.74	226.39989000000003	1358.3993400000002	1121.1906402479658	Charles Smith	1	1358.3993400000002	1736	1358.3993400000002	70	95387.089343	1149.437576059358
2a9abd6d-e1f2-4d4d-812f-65e03bec7af8	2020-03-31	3a4f5516-4512-4ba1-8d7b-6df008a0fe45	North America	Beauty	4	478.96	335.846752	1343.387008	1106.6418000484985	Michelle Andersen	1	1343.387008	1734	1343.387008	60	66978.268402	921.082547231716
7d66ade3-784b-4241-83f8-47cdbb8ba54c	2020-04-02	00bbcf87-a427-4d0d-90fd-5bc04267abdd	South America	Sports	5	250.93	205.135275	1025.676375	801.1854964515528	Caleb Camacho	1	1025.676375	1732	1025.676375	66	91544.242731	1177.604080808591
8708059a-abda-4ff9-b6b1-298683f86252	2020-04-06	8879f243-c666-4747-9888-99f3fcb60ac8	North America	Books	3	21.73	20.221938	60.665814000000005	10.574315362397826	Jason Nelson	1	60.665814000000005	1728	60.665814000000005	70	87933.283392	1049.1629849529377
085267c8-b04e-4f08-8232-a1a05fba7d36	2020-04-07	d1372275-bae7-40e5-ba1f-d8fc4b462eff	South America	Home & Kitchen	4	273.95	265.101415	1060.40566	834.2919085873295	Michelle Andersen	1	1060.40566	1727	1060.40566	60	66978.268402	921.082547231716
61d3cbef-2b32-470d-b035-a43de923ede1	2020-04-07	186b21ba-81f2-4438-9b6d-bfccd2f0489a	South America	Home & Kitchen	3	67.58	57.199712	171.599136	64.15493338275624	Adam Smith	1	171.599136	1727	171.599136	55	62372.113224	936.3944649146875
34c58365-cdce-49b3-a2e9-75e06b01a55b	2020-04-10	aef9daab-b134-4a02-9754-b466a18b3548	Australia	Beauty	5	198.26	172.268114	861.34057	645.8491962540342	Adam Smith	1	861.34057	1724	861.34057	55	62372.113224	936.3944649146875
68b13286-ce9e-4383-b9fe-41d296aada39	2020-04-11	a45a0b15-b4bf-4a36-a3b7-0203bbc49af0	North America	Home & Kitchen	10	217.42	208.462296	2084.62296	1832.048541874356	Joseph Brooks	1	2084.62296	1723	2084.62296	60	60657.854394	824.8550359343124
247877f9-cd00-43ec-b09b-a9b31c72fd24	2020-04-15	fbf29203-d178-40a5-af82-bb772f66cba4	Australia	Sports	9	349.43	337.095121	3033.856089	2771.3323067995066	Roger Brown	1	3033.856089	1719	3033.856089	54	68595.667163	1076.1212096324236
a90cb8ff-601a-466e-af90-149faffbcf68	2020-04-15	bf47fa6d-6fe3-4159-b04b-338bae63f2aa	Australia	Electronics	3	418.03	342.7846	1028.3538	803.7341241448605	Caitlyn Boyd	1	1028.3538	1719	1028.3538	58	71709.8323	1035.5858485437743
a6fd7b82-865f-40d1-9289-82c5ff523050	2020-04-15	6c95c0ea-cb0b-4645-8bde-f9e2fd1a0feb	North America	Books	8	69.17	67.108734	536.869872	349.6832773903281	Roger Brown	1	536.869872	1719	536.869872	54	68595.667163	1076.1212096324236
4781ce67-e6a7-4b12-a236-eb45bbcc39ec	2020-04-17	4e9ebe6a-2487-4729-b394-b88978a181df	Asia	Toys	3	417.41	349.706098	1049.118294	823.5257138473281	Steven Coleman	1	1049.118294	1717	1049.118294	59	68355.922945	964.8650638967956
ced5508d-37de-4ba5-b1e8-5dd993ee0e70	2020-04-19	6feaf5a0-9352-42cc-bf20-53c74107710c	South America	Clothing	3	381.75	369.76305	1109.28915	881.0309603625665	Mary Scott	1	1109.28915	1715	1109.28915	63	77562.23517100001	1033.152899764227
03a2201e-0e23-44d3-9bed-fa7d34df93ed	2020-04-25	72916e72-6032-4c32-9807-7e1c77aa71aa	South America	Home & Kitchen	2	437.73	382.313382	764.626764	555.7465902579904	Bradley Howe	1	764.626764	1709	764.626764	56	64186.396558	951.6581100155678
d0948ff8-866e-4157-bc73-409fbc65462e	2020-04-27	d0a4170b-c634-4ef0-97f7-21da4a2bce02	Australia	Clothing	1	70.83	52.371702000000006	52.371702000000006	8.071497296904077	Caleb Camacho	1	52.371702000000006	1707	52.371702000000006	66	91544.242731	1177.604080808591
afe2f411-35a7-4256-bc72-1f7152286893	2020-04-29	57dadf50-4054-4279-863c-8e4baa1177ff	South America	Toys	7	415.93	344.39004000000006	2410.73028	2153.9472672819074	Steven Coleman	1	2410.73028	1705	2410.73028	59	68355.922945	964.8650638967956
0bb80432-cc79-4391-8a7b-0bead0728c30	2020-05-02	b6d957fa-4829-4835-89ea-ca15c9e10b30	South America	Toys	6	208.33	197.371842	1184.231052	952.9630263780026	Caleb Camacho	1	1184.231052	1702	1184.231052	66	91544.242731	1177.604080808591
b2870124-f7dc-489d-9e0b-320ae8c937e0	2020-05-03	0ad4ebed-76d2-4928-8ae9-456834fa4657	Australia	Beauty	2	57.46	47.6918	95.3836	23.76891421277874	Adam Smith	1	95.3836	1701	95.3836	55	62372.113224	936.3944649146875
05636340-6f11-44ec-93c9-89f273afeb61	2020-05-07	447a68a8-edb8-4890-8569-a665f9397924	Europe	Clothing	1	69.39	58.946805000000005	58.946805000000005	10.03235391710232	Diane Andrews	1	58.946805000000005	1697	58.946805000000005	58	66389.094387	950.0340815608216
2d79c08f-aaf6-4b7d-9ac8-e3a6468d08cf	2020-05-07	cc56db77-224e-444d-a624-abea0731f38a	Australia	Books	6	329.11	256.969088	1541.814528	1299.5736833544493	Jason Nelson	1	1541.814528	1697	1541.814528	70	87933.283392	1049.1629849529377
7551d51f-01dd-4d27-a253-d5178dd8fd84	2020-05-09	d19e8c84-9f57-4936-848c-db89341af3ce	Asia	Beauty	5	467.92	371.856024	1859.28012	1610.3605119993572	Roger Brown	1	1859.28012	1695	1859.28012	54	68595.667163	1076.1212096324236
d6412840-052b-4b54-ae8d-ee3159f71e44	2020-05-12	5eaf7af0-add1-45a5-b44c-258089a4a4df	Europe	Electronics	7	42.26	38.422792	268.959544	130.0269834338551	Charles Smith	1	268.959544	1692	268.959544	70	95387.089343	1149.437576059358
02fd6c13-ef23-4711-bdd2-9c9f312ae39e	2020-05-13	a2343200-f78c-4073-b7ad-af65922c8c16	South America	Books	7	82.05	74.394735	520.763145	335.5699924395448	Emily Matthews	1	520.763145	1691	520.763145	72	80570.187359	919.786031455556
a73e8c60-0c15-46be-a04e-e1c82d7aeddd	2020-05-13	484a8c94-5f4a-448c-ba7f-f4d5113b976d	Australia	Clothing	2	365.67	330.017175	660.03435	459.8176570436207	Caitlyn Boyd	1	660.03435	1691	660.03435	58	71709.8323	1035.5858485437743
e49e5a1b-a31e-41a4-96f3-5d5d7127830e	2020-05-14	ef1b2d97-9127-4a5c-963f-2e823993fd80	Australia	Electronics	10	267.68	228.1972	2281.972	2026.7235715532088	Bradley Howe	1	2281.972	1690	2281.972	56	64186.396558	951.6581100155678
4e7dfd08-8cec-4b44-8662-c5659b034f9f	2020-05-15	c2ed31d9-3a1a-41f1-89a2-038d533a8fb5	South America	Sports	2	26.22	25.902738	51.805476	7.913689166144195	Kristen Ramos	1	51.805476	1689	51.805476	62	73461.618973	988.8412277570784
09b01c7a-2ba8-4cf7-8ed7-63776d8ddfc0	2020-05-17	dfeacb6f-01d1-4c81-9b77-b6a0ba286243	North America	Sports	6	372.99	279.183015	1675.09809	1429.7918647122397	Michelle Andersen	1	1675.09809	1687	1675.09809	60	66978.268402	921.082547231716
c568fa31-820b-490a-8504-caf07642e20f	2020-05-18	62e5053b-1713-44ad-9885-f0a53e4ec462	Europe	Home & Kitchen	8	291.62	222.622708	1780.981664	1533.5199905249408	Michelle Garza	1	1780.981664	1686	1780.981664	65	76798.491008	980.44596940906
9c9c8ac9-deb4-49be-90ed-fb46f76c76be	2020-05-19	08094f4e-b630-4c96-9b77-91daa94cde7a	Europe	Books	6	282.7	265.65319	1593.91914	1350.4277267921357	Michelle Andersen	1	1593.91914	1685	1593.91914	60	66978.268402	921.082547231716
38177857-edf6-40e3-8d7f-6c84ccfda6c6	2020-05-19	4a52a940-3323-4442-87c6-54b4fc0ae52a	North America	Home & Kitchen	7	202.19	171.012302	1197.086114	965.3307243808104	Bradley Howe	1	1197.086114	1685	1197.086114	56	64186.396558	951.6581100155678
179088a0-9071-40c1-ad8c-8439352f0d6b	2020-05-22	77c982dc-4e31-4b30-9e20-ce4530bcb61e	Australia	Sports	6	172.79	141.031198	846.1871879999999	631.6584414225737	Johnny Marshall	1	846.1871879999999	1682	846.1871879999999	61	67804.798966	913.3835523608234
061756ff-4225-479e-acb4-6c507291bc98	2020-05-23	36361505-b8fa-48f0-80a4-1c684ab4699e	Asia	Beauty	9	376.64	365.3408	3288.0672	3023.7743618037134	Caitlyn Boyd	1	3288.0672	1681	3288.0672	58	71709.8323	1035.5858485437743
494b9d35-ef55-4225-87da-191ec43987c0	2020-05-24	82cb8bc0-0682-4c5b-93e6-3044b66b767f	Europe	Electronics	8	22.81	20.622521	164.980168	60.17096401041866	Jason Nelson	1	164.980168	1680	164.980168	70	87933.283392	1049.1629849529377
05d07d49-2750-4b60-9541-0bd0343c1627	2020-05-26	b85a649e-f7e4-491b-b7ea-4cf3e24bb1d1	Europe	Clothing	9	20.4	15.39384	138.54456	45.06600929491937	Emily Matthews	1	138.54456	1678	138.54456	72	80570.187359	919.786031455556
f71dc3ef-9078-4d48-ad31-00fabbfe1c16	2020-05-28	973dc65c-7dcc-4ff3-9e0b-4a850d774652	North America	Toys	10	169.52	128.682632	1286.82632	1051.9011118796554	Caitlyn Boyd	1	1286.82632	1676	1286.82632	58	71709.8323	1035.5858485437743
8200643b-4312-4d7f-bc8d-048b93444c92	2020-06-03	fee83918-ed61-4155-a394-431ab746bf5a	Asia	Sports	4	416.96	312.594912	1250.379648	1016.698768879121	Adam Smith	1	1250.379648	1670	1250.379648	55	62372.113224	936.3944649146875
e11e3c17-4fd3-4e65-a615-c99ac429e6ea	2020-06-06	2e9952e8-59fb-44e1-8c39-2a4b899e6867	Asia	Beauty	2	483.44	449.550856	899.1017119999999	681.3224430161075	Susan Edwards	1	899.1017119999999	1667	899.1017119999999	68	86058.98736700001	1063.159646603474
1a7824e5-2a96-48a9-adfc-ae4965690aa6	2020-06-09	887bbac3-64ad-42ef-87e4-ffbff02de08a	North America	Clothing	10	360.9	308.17251	3081.7251	2818.8465620830843	Caleb Camacho	1	3081.7251	1664	3081.7251	66	91544.242731	1177.604080808591
2ff5184d-4eaa-4ab3-85f8-7f8513d4d303	2020-06-10	19a7f80a-6d5a-4ca5-861c-d4e67ff6d214	North America	Clothing	9	372.61	306.918857	2762.269713	2501.9581883189967	Kristen Ramos	1	2762.269713	1663	2762.269713	62	73461.618973	988.8412277570784
ac626a8d-59c8-44b0-891c-b127a6d3ca6c	2020-06-11	80f0cc88-f01b-4efd-b09e-e31c8a576baa	North America	Sports	9	139.48	112.42088	1011.78792	787.9707452886785	Sandra Luna	1	1011.78792	1662	1011.78792	56	72688.198308	1090.9576938669472
56648e32-e04f-449c-a522-8c6678a5f9eb	2020-06-12	b2fb7d64-7eef-415f-bfb7-0bf2cd3c3490	Europe	Electronics	2	239.73	187.372968	374.745936	212.09579016666663	Charles Smith	1	374.745936	1661	374.745936	70	95387.089343	1149.437576059358
fec3a4cb-2c61-412f-b587-f4148a249e3f	2020-06-13	e0d56bb2-7c77-4d17-b09a-d54b26d6b5c7	North America	Toys	1	234.23	211.064653	211.064653	89.37147207287822	Sandra Luna	1	211.064653	1660	211.064653	56	72688.198308	1090.9576938669472
085eabd2-6713-4ed3-bf05-916f8db65fa1	2020-06-15	2b8f9f51-83c5-4a49-ba31-a118c73bb649	Australia	Electronics	2	318.62	295.488188	590.976376	397.6130360137421	Kristen Ramos	1	590.976376	1658	590.976376	62	73461.618973	988.8412277570784
c848806b-0bb4-4a89-88f1-52f743e20ebc	2020-06-16	0f14db51-d3b2-464b-904f-367e6ed4b53d	Australia	Toys	6	259.86	204.24996	1225.4997600000002	992.7008997743249	Johnny Marshall	1	1225.4997600000002	1657	1225.4997600000002	61	67804.798966	913.3835523608234
41fe40be-e0d6-49a6-bd7f-17677df07bb9	2020-06-16	0ea9becd-6396-422e-a98d-53d32813a2aa	South America	Toys	5	372.32	340.710032	1703.55016	1457.642463250765	Christina Thompson	1	1703.55016	1657	1703.55016	53	64491.182614000005	1021.7261378833904
f77092cb-68c9-4eec-b730-4dd35d7dcf79	2020-06-16	ba10177e-e07c-4b03-95b3-7658f8e2bf3a	North America	Sports	3	217.41	153.92628	461.77884	284.6348933988031	Michelle Andersen	1	461.77884	1657	461.77884	60	66978.268402	921.082547231716
b9e04daf-1420-4601-a38b-3b921036783f	2020-06-18	72f65fad-cf32-4061-af11-df9d29afb655	Asia	Clothing	2	327.82	244.652066	489.304132	308.2480239518964	Susan Edwards	1	489.304132	1655	489.304132	68	86058.98736700001	1063.159646603474
a2c8c147-5f73-4d1c-b6d7-60f91d3ca229	2020-06-19	54165b3a-33bf-42a2-9fa1-da2050fe1648	Europe	Home & Kitchen	8	228.79	226.364826	1810.918608	1562.8883379074125	Charles Smith	1	1810.918608	1654	1810.918608	70	95387.089343	1149.437576059358
93350410-dfa5-4530-ab13-544b63fcf39a	2020-06-22	62af3644-c4a8-43b7-8fed-ff883477ed76	Australia	Toys	10	391.23	324.99476100000004	3249.94761	2985.90240391955	Caleb Camacho	1	3249.94761	1651	3249.94761	66	91544.242731	1177.604080808591
c9dcfaf5-c987-4014-b103-5e0e2124921d	2020-06-22	00d02303-05a1-4277-b8f6-0dbab9083665	Australia	Beauty	9	243.27	233.39323800000005	2100.539142	1847.733217990805	Steven Coleman	1	2100.539142	1651	2100.539142	59	68355.922945	964.8650638967956
7370a12f-00f6-4827-91e9-77746963470b	2020-06-23	d3f8f160-d379-4266-b0b9-45f9404a4c30	South America	Clothing	2	6.44	5.623408	11.246816	0.4232032582042144	Diane Andrews	1	11.246816	1650	11.246816	58	66389.094387	950.0340815608216
f46c842a-248b-471d-9a0b-d9d8cfcd82a7	2020-06-25	f146b24c-a4be-4bf7-8434-22e7ea9a113c	Asia	Books	1	214.05	171.32562	171.32562	63.99219060518733	Joseph Brooks	1	171.32562	1648	171.32562	60	60657.854394	824.8550359343124
20663a26-1f25-49c7-a0da-81e89de2a303	2020-06-25	c89ad1ef-0841-49a6-a0e0-8ebd2613e7b1	North America	Sports	3	189.73	143.13231199999998	429.396936	257.23185200176414	Diane Andrews	1	429.396936	1648	429.396936	58	66389.094387	950.0340815608216
dd294a76-00f9-452a-9b6d-40eb94454608	2020-07-02	b230535c-0263-498d-b576-f28b3409bd1c	Australia	Home & Kitchen	5	482.7	445.19421	2225.97105	1971.440548250509	Crystal Williams	1	2225.97105	1641	2225.97105	65	72555.900913	927.0834787540324
fd8e8e62-1888-44ae-acd5-88d56aa758eb	2020-07-06	9baecdb1-e458-43a2-ab99-51bef7799e71	North America	Books	2	241.99	241.409224	482.8184480000001	302.66231068656714	Michelle Andersen	1	482.8184480000001	1637	482.8184480000001	60	66978.268402	921.082547231716
777c0821-41c5-46ff-88aa-f83c8955eb6d	2020-07-07	e0b7c3fc-9399-483b-981b-8a05ee999207	South America	Sports	7	153.51	127.628214	893.397498	675.9517748826364	Sandra Luna	1	893.397498	1636	893.397498	56	72688.198308	1090.9576938669472
f881a4e1-2327-445d-82bd-79ae3640976c	2020-07-08	b19feead-c91a-4cf0-a20a-640adc1cf527	Europe	Home & Kitchen	3	192.48	162.510864	487.532592	306.7238870600801	Susan Edwards	1	487.532592	1635	487.532592	68	86058.98736700001	1063.159646603474
170e86c5-346c-4fa8-8cff-f5d068352ba1	2020-07-08	74cab180-c2b8-47f9-a37d-908334407d44	Europe	Electronics	1	237.68	170.77308000000002	170.77308000000002	63.65158959729018	Crystal Williams	1	170.77308000000002	1635	170.77308000000002	65	72555.900913	927.0834787540324
ed9514b3-9523-46fe-beaa-19d8b90f265e	2020-07-09	375e087d-1536-4c56-8081-15f1564745f5	Asia	Clothing	4	21.51	20.025810000000003	80.10324000000001	17.458960653789006	Johnny Marshall	1	80.10324000000001	1634	80.10324000000001	61	67804.798966	913.3835523608234
2d275520-f241-4e7b-b7dd-27316c11dd11	2020-07-09	dc47628a-fc0a-43a5-8025-7503a4674115	North America	Sports	8	353.45	282.97207	2263.77656	2008.75774036702	Caleb Camacho	1	2263.77656	1634	2263.77656	66	91544.242731	1177.604080808591
0481149a-fd91-4123-a67b-3ef7c16e5611	2020-07-09	6b747dc8-7c60-4cad-a55f-c7d89f8e4b10	Australia	Sports	4	161.77	122.670191	490.680764	309.4371766620618	Joseph Brooks	1	490.680764	1634	490.680764	60	60657.854394	824.8550359343124
8d013a0f-7c60-4316-a90a-be47f20bdb28	2020-07-10	23ff2ad3-b0dc-43ac-a47a-6a6af4329d50	North America	Toys	8	409.67	327.121495	2616.97196	2358.017096009657	Emily Matthews	1	2616.97196	1633	2616.97196	72	80570.187359	919.786031455556
1c90c905-776a-4f31-abb2-83e5c01536b1	2020-07-13	8d6e78ee-3746-446a-97c5-20bc98744bd1	South America	Sports	8	14.96	13.464	107.712	29.364604015129476	Kristen Ramos	1	107.712	1630	107.712	62	73461.618973	988.8412277570784
678dd2a1-647b-4b03-8ffe-f5c4175ab9f2	2020-07-14	6dcf54e3-c77b-458b-a088-ba18568e415b	Europe	Books	3	400.89	285.43368	856.30104	641.1229925065962	Bradley Howe	1	856.30104	1629	856.30104	56	64186.396558	951.6581100155678
3833b55d-7b15-4c91-b3c5-8b7edffba7f4	2020-07-14	95dfbf8a-de12-474c-ae38-7235f9f49cd6	Australia	Clothing	1	165.95	139.66352	139.66352	45.677301965006734	Bradley Howe	1	139.66352	1629	139.66352	56	64186.396558	951.6581100155678
1f847ea2-4295-45e1-a239-1441cff8b6c2	2020-07-16	6ec1562b-8aca-48af-bd06-cbdda004d3d4	South America	Toys	3	231.53	198.050762	594.152286	400.4532946718393	Michelle Andersen	1	594.152286	1627	594.152286	60	66978.268402	921.082547231716
ccc58828-e8e4-4935-9ca3-27f1f8591028	2020-07-17	feaf4d74-2f5d-4380-9b7a-973174cf731a	North America	Toys	8	301.49	249.181485	1993.45188	1742.270362164233	Michelle Garza	1	1993.45188	1626	1993.45188	65	76798.491008	980.44596940906
d3eab343-3a89-4a1d-b344-fb7d4df0a232	2020-07-18	e9bd87de-854b-4b3d-82b7-c3556bbaacc1	Europe	Books	5	248.88	240.144312	1200.72156	968.8324985863268	Caitlyn Boyd	1	1200.72156	1625	1200.72156	58	71709.8323	1035.5858485437743
17261126-a24b-4b86-9524-d52b6ce3cf07	2020-07-21	787d0d7e-467a-4df3-b4fe-742538d5e5ee	Australia	Beauty	6	326.86	292.768502	1756.611012	1509.625408108096	Michelle Garza	1	1756.611012	1622	1756.611012	65	76798.491008	980.44596940906
1b4f98ae-af68-406c-b63d-7569b48719fc	2020-07-22	e0a366ed-e431-4c3c-8803-3dea3ad5e358	Asia	Sports	8	102.05	94.82486	758.59888	550.1696899791186	Diane Andrews	1	758.59888	1621	758.59888	58	66389.094387	950.0340815608216
ef1c9dbe-b6b6-4eb5-a332-164dd12ded92	2020-07-24	6e837469-ce85-4b2e-ac41-433ace23aacf	Australia	Toys	5	297.52	286.51176	1432.5587999999998	1193.1886060053134	Johnny Marshall	1	1432.5587999999998	1619	1432.5587999999998	61	67804.798966	913.3835523608234
306c676a-4174-4623-a1df-87cafb1fe33c	2020-07-24	e03e3de2-fed8-4335-84a8-7f8cef80f778	Asia	Sports	10	179.16	140.407692	1404.07692	1165.5155294875628	Steven Coleman	1	1404.07692	1619	1404.07692	59	68355.922945	964.8650638967956
d5e5e143-4238-4868-9919-d03df26741f8	2020-07-25	345863e0-374f-44c0-bb6f-24c17da23ec8	Europe	Home & Kitchen	8	65.55	60.155235	481.24188	301.3047403477285	Sandra Luna	1	481.24188	1618	481.24188	56	72688.198308	1090.9576938669472
0503717b-d058-4b67-9e93-289cf5409672	2020-07-25	a2f4b464-4f24-4284-8bfd-2340b5810a08	South America	Sports	1	451.68	407.957376	407.957376	239.34511065592068	Charles Smith	1	407.957376	1618	407.957376	70	95387.089343	1149.437576059358
6d7cc022-e1cb-4bd4-a76d-bb5001d8877f	2020-07-30	c5115174-8c74-4d71-b4e4-b065fa0c3fdc	Europe	Clothing	3	485.7	404.34525	1213.03575	980.6890311063438	Charles Smith	1	1213.03575	1613	1213.03575	70	95387.089343	1149.437576059358
96daea1c-0bea-4d61-8903-cf6191165b60	2020-07-31	857c59eb-ec4e-42f9-a450-7871eb4c63d5	Europe	Clothing	4	98.12	84.98173200000001	339.92692800000003	184.1971643936229	Steven Coleman	1	339.92692800000003	1612	339.92692800000003	59	68355.922945	964.8650638967956
3cd6940b-554a-4df8-a7b4-65d1f29d5e06	2020-08-03	46142107-d876-4698-ab79-941a4adca07f	Asia	Toys	6	80.16	72.135984	432.81590399999993	260.1040508475658	Charles Smith	1	432.81590399999993	1609	432.81590399999993	70	95387.089343	1149.437576059358
1f58eb82-d572-4796-a2b3-cd1dbbfb1044	2020-08-03	e184fffa-fd1c-456c-8a02-1b644f95665d	South America	Toys	10	286.82	285.844812	2858.44812	2597.309621356648	Caleb Camacho	1	2858.44812	1609	2858.44812	66	91544.242731	1177.604080808591
6e457f13-dad2-49a0-8486-b2b8e9b90478	2020-08-04	fcb0a1b0-23a6-4ac3-b3da-71f2678795bc	South America	Sports	9	475.98	373.215918	3358.943262	3094.201052125793	Sandra Luna	1	3358.943262	1608	3358.943262	56	72688.198308	1090.9576938669472
26133422-ed61-43bb-b4b2-7cb734150771	2020-08-06	9af855c0-bfb1-49ff-a260-c86ac9b35a15	South America	Home & Kitchen	5	231.36	220.578624	1102.8931200000002	874.9095909773444	Diane Andrews	1	1102.8931200000002	1606	1102.8931200000002	58	66389.094387	950.0340815608216
42757294-5acb-4430-9c22-16e234d77454	2020-08-06	a7a119a2-1ae1-4d20-9136-c082f40a08c9	Asia	Beauty	3	128.02	94.67079	284.01237000000003	141.1633759350166	Adam Smith	1	284.01237000000003	1606	284.01237000000003	55	62372.113224	936.3944649146875
9f5c2a53-cd2b-4e27-893b-fa3992ddfdad	2020-08-07	fac94b8a-41ed-4fbc-b051-d9a2f40ab408	Asia	Clothing	8	338.42	276.31993	2210.55944	1956.229511447473	Christina Thompson	1	2210.55944	1605	2210.55944	53	64491.182614000005	1021.7261378833904
e505a72c-3711-4bfc-9dc0-5b45e4a99f81	2020-08-08	f7f87d0c-be1a-4359-a447-2a552e1bc084	North America	Beauty	7	266.55	201.218595	1408.530165	1169.8366952491103	Emily Matthews	1	1408.530165	1604	1408.530165	72	80570.187359	919.786031455556
773ba6df-5888-4d68-81fa-55f2156836ec	2020-08-10	9b99fab9-1558-4eaf-bf77-c7317478b7b3	Europe	Toys	2	113.13	107.756325	215.51265	92.35552673581348	Emily Matthews	1	215.51265	1602	215.51265	72	80570.187359	919.786031455556
6e810f83-53c0-472c-8f16-8039f92048fd	2020-08-11	9191ac7f-d51b-4582-aa94-9bca8149cf06	South America	Sports	6	384.11	354.034187	2124.205122	1871.0613752623076	Mary Scott	1	2124.205122	1601	2124.205122	63	77562.23517100001	1033.152899764227
38d75334-8117-4294-8ed2-122b0eda9c4b	2020-08-15	88e2ba7c-0548-499b-9573-dd25aef926ef	Australia	Clothing	7	362.18	267.07153200000005	1869.5007240000004	1620.4000279307131	Kristen Ramos	1	1869.5007240000004	1597	1869.5007240000004	62	73461.618973	988.8412277570784
7510fbe2-6b90-4676-853d-3780371528d7	2020-08-15	abbb7c0d-8d7c-46ef-866c-617e4a8a8998	South America	Clothing	6	452.33	346.258615	2077.55169	1825.081531169537	Sandra Luna	1	2077.55169	1597	2077.55169	56	72688.198308	1090.9576938669472
12f75eab-2ab5-46e2-a51f-1a45bf91881a	2020-08-17	3ef9121e-2a6b-4a97-847a-c14a7dcaa25c	South America	Books	2	265.62	222.403626	444.807252	270.2155606705656	Bradley Howe	1	444.807252	1595	444.807252	56	64186.396558	951.6581100155678
6c636644-434d-4d59-8ea0-2dd07f6527fa	2020-08-17	c7031058-e188-436c-9474-f813d3ad41b3	Asia	Sports	5	292.83	225.625515	1128.127575	899.0847409154586	Michelle Andersen	1	1128.127575	1595	1128.127575	60	66978.268402	921.082547231716
69c0427e-bae9-4083-aa03-a8392efbe857	2020-08-20	34d1e2fc-79de-4c1d-b06d-b521b3e96caa	South America	Electronics	8	209.95	176.085065	1408.68052	1169.985840591026	Caitlyn Boyd	1	1408.68052	1592	1408.68052	58	71709.8323	1035.5858485437743
881d0247-0080-4ad5-823f-2a573da8bcb4	2020-08-20	99a08be0-464a-4307-bdce-92b919560619	Asia	Home & Kitchen	6	279.56	213.360192	1280.161152	1045.4586820674683	Kristen Ramos	1	1280.161152	1592	1280.161152	62	73461.618973	988.8412277570784
9ddfd2fc-c4a3-4e7a-bbfe-c8ded0517e21	2020-08-23	a260eeb8-6ff6-49b4-9e8a-b72968941d2b	Australia	Sports	5	108.95	97.24877	486.24385000000007	305.6116385508377	Christina Thompson	1	486.24385000000007	1589	486.24385000000007	53	64491.182614000005	1021.7261378833904
f2b2e465-9989-47db-becc-74849845d9d8	2020-08-25	734fee46-7bd7-4e9a-9047-c216b7346079	Europe	Clothing	8	177.79	151.29928999999998	1210.39432	978.1442777864764	Michelle Andersen	1	1210.39432	1587	1210.39432	60	66978.268402	921.082547231716
ed923de8-5f47-4693-adca-42cb26e00083	2020-08-26	07cb2691-8302-41ed-9ae8-70153b1db1b9	Australia	Clothing	6	267.67	254.179432	1525.076592	1283.2542801362383	Roger Brown	1	1525.076592	1586	1525.076592	54	68595.667163	1076.1212096324236
04597ed7-22b6-4215-bfca-c0a8a1b00441	2020-08-27	401f8cfb-8a89-416a-a7a5-ec3d12ebda0a	Australia	Sports	7	344.18	316.404674	2214.832718	1960.447226763467	Joseph Brooks	1	2214.832718	1585	2214.832718	60	60657.854394	824.8550359343124
6725eb40-4c64-4989-9969-9e4516a0f48b	2020-08-29	f082abc1-b023-4025-b93f-ef657c804bd4	Australia	Books	5	15.33	14.519043000000002	72.59521500000001	14.639590698547025	Roger Brown	1	72.59521500000001	1583	72.59521500000001	54	68595.667163	1076.1212096324236
a97ab948-d661-4b3c-ad10-79748900a427	2020-08-31	cef62570-4572-405d-8d0d-95e20c77be38	Australia	Toys	3	44.71	43.444707	130.334121	40.66496310526317	Bradley Howe	1	130.334121	1581	130.334121	56	64186.396558	951.6581100155678
fad8cf7e-dc2a-4f43-a5d6-ccf59a27aa00	2020-09-02	73c7f21c-b09d-4f63-beb1-9b98c8c68c72	North America	Home & Kitchen	10	348.73	322.854234	3228.54234	2964.638864383266	Steven Coleman	1	3228.54234	1579	3228.54234	59	68355.922945	964.8650638967956
ffcab7d4-5ee5-4831-8e82-0df210508c5d	2020-09-03	13beec05-44dd-4a2f-94c8-c48c1c6a9b0a	Australia	Clothing	1	288.6	215.12244000000004	215.12244000000004	92.08987494423792	Bradley Howe	1	215.12244000000004	1578	215.12244000000004	56	64186.396558	951.6581100155678
3fd76435-4639-494a-b7b6-0ee298b9de2b	2020-09-04	89d9b230-ef0b-4a36-83d4-8ac4fdd75968	Asia	Books	4	371.78	355.23578999999995	1420.9431599999998	1181.896162927223	Jason Nelson	1	1420.9431599999998	1577	1420.9431599999998	70	87933.283392	1049.1629849529377
224e9f7b-a6f7-4990-843a-8f7995803fb1	2020-09-08	98eae08f-cb95-471a-b781-64aa5551bb9b	North America	Toys	4	171.23	159.34663799999998	637.3865519999999	439.3050826731306	Adam Smith	1	637.3865519999999	1573	637.3865519999999	55	62372.113224	936.3944649146875
845c919e-8fa3-4223-bc41-c2b2400e57f5	2020-09-08	38a720f8-9520-4029-be87-5fceee83f7ae	North America	Books	2	262.34	201.660758	403.321516	235.50861927036692	Mary Scott	1	403.321516	1573	403.321516	63	77562.23517100001	1033.152899764227
ea1b6c78-767a-4f29-80dd-701eef15b39b	2020-09-09	f5394d0e-45da-4b9a-8f87-a4143b7820d7	North America	Sports	1	361.42	259.716412	259.716412	123.28923755024428	Emily Matthews	1	259.716412	1572	259.716412	72	80570.187359	919.786031455556
9d3a3b7b-7ed8-409d-bd42-bfc0fd477306	2020-09-09	6673d90e-64d9-41e9-ab0e-f096bf793342	Australia	Sports	8	271.25	264.387375	2115.099	1862.0846213215943	Charles Smith	1	2115.099	1572	2115.099	70	95387.089343	1149.437576059358
80112eff-f7aa-4e0d-8c41-3d1145fa6df4	2020-09-09	e0083759-20dc-4bb9-a22f-19f7f3792478	North America	Books	6	17.07	16.380372	98.282232	25.046589675111772	Steven Coleman	1	98.282232	1572	98.282232	59	68355.922945	964.8650638967956
c9dc4ab7-2d8f-43ff-994b-81821dd1af87	2020-09-10	132a133a-cb0e-42ef-a719-45388ed3a4df	South America	Toys	9	220.15	199.081645	1791.734805	1544.066055	Adam Smith	1	1791.734805	1571	1791.734805	55	62372.113224	936.3944649146875
5099f3eb-34c9-4949-b80a-50aca3c32deb	2020-09-16	491579a9-5aae-484d-ad99-4672d48a5711	Asia	Toys	6	282.99	220.053024	1320.318144	1084.2983831805652	Michelle Garza	1	1320.318144	1565	1320.318144	65	76798.491008	980.44596940906
d4e1f246-322b-419e-b197-efb215ade87f	2020-09-16	fd81a634-62b1-4f77-8c28-b60186ba1666	Asia	Books	1	390.08	355.245856	355.245856	196.37735459129732	Susan Edwards	1	355.245856	1565	355.245856	68	86058.98736700001	1063.159646603474
9a0dc73b-56ce-4869-968f-d5b7aabbb6b4	2020-09-18	fdfea77d-db1f-4214-8092-640c93213b8c	North America	Electronics	3	51.9	38.20878	114.62634	32.68600116234184	Steven Coleman	1	114.62634	1563	114.62634	59	68355.922945	964.8650638967956
ce9b2fe4-ba7a-411d-9ad3-d7e187311643	2020-09-24	1a0fe267-21a7-4ccb-923a-f3d59ddf551c	North America	Electronics	6	157.72	112.895976	677.375856	475.5957380375335	Emily Matthews	1	677.375856	1557	677.375856	72	80570.187359	919.786031455556
60408360-380f-416c-b3e4-2baeb0a44670	2020-09-25	7a1a9f78-ad9c-494c-a27f-dee6a42b5433	Asia	Electronics	5	138.76	112.992268	564.96134	374.46928389372175	Joseph Brooks	1	564.96134	1556	564.96134	60	60657.854394	824.8550359343124
ac5a5a5e-00b0-42eb-93d0-0230d090deaf	2020-09-25	c807a512-9887-44e2-a09f-cfdafd1ff478	Europe	Books	3	160.79	135.947945	407.843835	239.25062471518336	Joseph Brooks	1	407.843835	1556	407.843835	60	60657.854394	824.8550359343124
3ae36515-9c29-4e10-900d-5a2358deece3	2020-09-27	96341ddd-4a05-4705-84a4-e0743a739e67	Europe	Beauty	7	348.17	287.483969	2012.387783	1760.9084669369174	Caleb Camacho	1	2012.387783	1554	2012.387783	66	91544.242731	1177.604080808591
977eedbb-d91f-46f5-b83a-f7be4f3296b7	2020-09-29	cc2afa97-6f11-4a31-876f-ec8e579ee7f8	Europe	Books	6	433.56	338.82714	2032.96284	1781.1653171483067	Roger Brown	1	2032.96284	1552	2032.96284	54	68595.667163	1076.1212096324236
9ed84e2f-db35-47bc-b18c-697465673d52	2020-10-03	8027bfbc-c7c6-4366-b771-40dea499d769	Asia	Sports	1	82.15	76.87597000000001	76.87597000000001	16.224317140039453	Michelle Garza	1	76.87597000000001	1548	76.87597000000001	65	76798.491008	980.44596940906
bce65fb9-4bcd-45c1-b374-f97a8f6a40bb	2020-10-07	b4cf0ada-2b17-4139-aeb6-83eba89c70a5	South America	Clothing	1	433.72	430.206868	430.206868	257.9104732705355	Mary Scott	1	430.206868	1544	430.206868	63	77562.23517100001	1033.152899764227
fb3bdb82-2590-43cc-8a30-d3df6b13ebbb	2020-10-07	8a174a87-6b0b-4d7c-a561-8f53bd0d0265	North America	Clothing	4	462.57	367.419351	1469.677404	1229.290508125094	Mary Scott	1	1469.677404	1544	1469.677404	63	77562.23517100001	1033.152899764227
512a6ee4-167d-4422-9f76-99a5d224e409	2020-10-08	7437af44-0efd-4794-80b9-792dc688a614	Europe	Clothing	7	204.8	160.13312000000002	1120.9318400000002	892.1842449547988	Susan Edwards	1	1120.9318400000002	1543	1120.9318400000002	68	86058.98736700001	1063.159646603474
67e3a6ff-0c5d-4ff4-be17-0e9394c6d770	2020-10-08	897ae0b6-f781-449b-bf77-4d47b32d2196	North America	Toys	5	192.11	151.690056	758.45028	550.0332867873925	Emily Matthews	1	758.45028	1543	758.45028	72	80570.187359	919.786031455556
6261dc20-7f50-4f94-91a3-c091b29c5c17	2020-10-09	647b687f-04e9-4b99-b8af-cf845b63dc4e	Europe	Clothing	10	326.26	253.634524	2536.34524	2278.200934991501	Charles Smith	1	2536.34524	1542	2536.34524	70	95387.089343	1149.437576059358
16a07122-af8d-4a53-99c1-1ca51e0833a1	2020-10-11	52da8de4-b171-40d6-883d-1adbcfd72ecd	Asia	Electronics	10	300.26	258.043444	2580.4344399999995	2321.840190248028	Adam Smith	1	2580.4344399999995	1540	2580.4344399999995	55	62372.113224	936.3944649146875
85fceeb0-44ff-4078-a004-6431820d0f34	2020-10-16	6e192b43-b28e-4854-b715-2140e464a378	Asia	Beauty	10	382.57	315.428965	3154.28965	2890.8944138929483	Emily Matthews	1	3154.28965	1535	3154.28965	72	80570.187359	919.786031455556
4d81567e-0929-4314-b4be-8263a2cec645	2020-10-17	492c688e-fefe-40c6-91b6-f1bad8946945	Europe	Home & Kitchen	7	472.03	345.950787	2421.655509	2164.751367502276	Joseph Brooks	1	2421.655509	1534	2421.655509	60	60657.854394	824.8550359343124
669f31cf-c3ea-47f0-9452-6307617e53ca	2020-10-17	e8ff484a-9e89-47b3-bb42-c86ffcad99e1	South America	Beauty	4	301.12	257.216704	1028.866816	804.2234063930131	Jason Nelson	1	1028.866816	1534	1028.866816	70	87933.283392	1049.1629849529377
3b9605f8-b7d7-400f-bd65-a6fc428e1971	2020-10-17	705e0a30-566d-4cc2-8a58-8e31a237fb2a	North America	Electronics	6	367.59	262.716573	1576.299438	1333.223408207254	Crystal Williams	1	1576.299438	1534	1576.299438	65	72555.900913	927.0834787540324
c07f87e2-d653-47af-8cd7-8a7faf315f67	2020-10-18	945c48ff-5aaf-4864-8aad-1deabaeaa3dd	Australia	Home & Kitchen	10	169.69	128.540175	1285.40175	1050.522213764938	Joseph Brooks	1	1285.40175	1533	1285.40175	60	60657.854394	824.8550359343124
3d3f5774-0275-472a-a3c7-383550a25a74	2020-10-19	0298dc4a-c273-4dac-ae9a-84faf6785238	Asia	Home & Kitchen	1	267.11	234.389025	234.389025	105.29174310971578	Kristen Ramos	1	234.389025	1532	234.389025	62	73461.618973	988.8412277570784
ece8230e-6e74-45e5-8bf0-ac3d08e2d67d	2020-10-23	65bacb9a-04a9-491e-98f2-172912380909	Europe	Clothing	8	99.63	70.308891	562.471128	372.2607435016739	Christina Thompson	1	562.471128	1528	562.471128	53	64491.182614000005	1021.7261378833904
170abc73-b2e1-4d18-94bc-de302f139418	2020-10-27	f404e9fa-21f9-430a-92a1-cba77ae92fe0	Australia	Sports	4	394.12	325.70076800000004	1302.8030720000002	1067.351060144293	Charles Smith	1	1302.8030720000002	1524	1302.8030720000002	70	95387.089343	1149.437576059358
abe971c4-33fa-463e-838e-e5e527f80c21	2020-10-27	9d545d1d-4af1-4652-be42-21d661ec9f25	South America	Beauty	10	447.54	340.846464	3408.46464	3143.418672301962	Michelle Garza	1	3408.46464	1524	3408.46464	65	76798.491008	980.44596940906
78a6526b-4013-417f-a595-bd373205cb09	2020-10-28	6f84c07b-d9c0-4405-ac2c-4bb5f4fbb6ab	South America	Sports	2	379.06	309.42667800000004	618.8533560000001	422.5975744378271	Diane Andrews	1	618.8533560000001	1523	618.8533560000001	58	66389.094387	950.0340815608216
d208e014-d94d-404e-a3e9-85c8441b109a	2020-10-31	05e19efd-b6ce-4a22-8f37-945e568b31e4	North America	Toys	6	281.8	224.25644	1345.53864	1108.727249444024	Mary Scott	1	1345.53864	1520	1345.53864	63	77562.23517100001	1033.152899764227
c803da81-cf0b-4d70-9441-213e5015ff2b	2020-11-02	00b25b77-9813-4407-b678-8164a26c2015	Europe	Clothing	4	280.96	273.205504	1092.822016	865.2692797168143	Emily Matthews	1	1092.822016	1518	1092.822016	72	80570.187359	919.786031455556
6264dff8-3780-44a1-bc05-658a583fdea5	2020-11-03	5eb5278e-7d20-48f8-beaa-e85fad24b669	South America	Clothing	9	129.58	103.780622	934.025598	714.2548690588236	Bradley Howe	1	934.025598	1517	934.025598	56	64186.396558	951.6581100155678
8ed2a614-782b-4b23-9fbd-8b6936fde222	2020-11-04	c42eb0d4-2865-4044-ae3b-2653db8213d5	North America	Electronics	10	404.91	347.979654	3479.79654	3214.327361400508	Crystal Williams	1	3479.79654	1516	3479.79654	65	72555.900913	927.0834787540324
69ee4f39-492e-4a2c-b4b7-806bb7c69383	2020-11-08	2c902b0c-dd47-4868-8958-604e2c1ae494	South America	Sports	2	97.52	80.610032	161.220064	57.94007424983984	Michelle Andersen	1	161.220064	1512	161.220064	60	66978.268402	921.082547231716
c8c613cf-545c-4b16-b868-cab9f948ae38	2020-11-12	cfb66414-aeb3-4263-822d-dd23fcd50d4e	Asia	Books	10	126.01	92.894572	928.94572	709.456146954611	Johnny Marshall	1	928.94572	1508	928.94572	61	67804.798966	913.3835523608234
f4fa6ba7-0d0c-4d32-b323-eb7ab66e0f49	2020-11-13	c2fc89b6-439f-4f2e-a2aa-dd63ead1c6c9	Europe	Clothing	10	159.13	140.718659	1407.18659	1168.5347702455736	Johnny Marshall	1	1407.18659	1507	1407.18659	61	67804.798966	913.3835523608234
763a8400-f5ed-4c6c-a996-56c7c4f808b8	2020-11-15	5c9a958b-267a-45f0-acdd-1ccf7a19ac04	Australia	Clothing	10	200.51	170.914724	1709.14724	1463.1241166823568	Emily Matthews	1	1709.14724	1505	1709.14724	72	80570.187359	919.786031455556
81f24664-3704-45cf-9c38-1937ecf358ae	2020-11-18	fd3ef85d-64e0-4cfd-893f-493c78c70a4e	South America	Toys	7	269.61	216.550752	1515.855264	1274.2654538159215	Caleb Camacho	1	1515.855264	1502	1515.855264	66	91544.242731	1177.604080808591
027b551d-51f3-4e55-a0b9-69d84443e368	2020-11-21	19aa76e8-010d-4585-8717-4a238c0ab2e3	Asia	Sports	8	188.11	187.188261	1497.506088	1256.3889694787383	Caleb Camacho	1	1497.506088	1499	1497.506088	66	91544.242731	1177.604080808591
e857c65a-3118-4864-b927-8d827e437757	2020-11-22	2d52fe72-4350-45ed-9a86-9242c35d6b9d	Australia	Electronics	3	428.46	302.749836	908.249508	689.9360431056415	Jason Nelson	1	908.249508	1498	908.249508	70	87933.283392	1049.1629849529377
1be17b86-cd10-4fec-ae5b-864b16d4a826	2020-11-26	ea0a5a38-e0af-4ecf-9906-5e217044f716	North America	Beauty	4	354.48	252.17707200000004	1008.7082880000002	785.0429544005855	Michelle Garza	1	1008.7082880000002	1494	1008.7082880000002	65	76798.491008	980.44596940906
5fe6e67b-3ee4-43bd-a21c-c2bf12472690	2020-11-28	50e25075-7461-44d4-8b76-66d9ef7a3d8b	Asia	Home & Kitchen	5	117.29	117.160981	585.8049050000001	392.9981034991608	Johnny Marshall	1	585.8049050000001	1492	585.8049050000001	61	67804.798966	913.3835523608234
84e87653-023c-43d2-87af-f99db6fd5244	2020-11-28	26f82a47-31cd-4456-a235-d1fef4e9e956	Europe	Beauty	8	426.19	326.29106399999995	2610.328512	2351.4392637753	Michelle Andersen	1	2610.328512	1492	2610.328512	60	66978.268402	921.082547231716
3f7d025f-7876-4c6c-aff9-654f5d0e2f10	2020-11-30	03652680-7e4b-4d4d-9b78-69aa8e1cf74b	North America	Electronics	9	499.31	383.120563	3448.085067	3182.802860241933	Susan Edwards	1	3448.085067	1490	3448.085067	68	86058.98736700001	1063.159646603474
ad7f34d8-6c9c-40f3-a837-79770db006f2	2020-11-30	98173b4f-ca32-48d2-a0a1-f1862079349c	Europe	Toys	7	213.04	177.31319200000002	1241.192344	1007.83287494683	Sandra Luna	1	1241.192344	1490	1241.192344	56	72688.198308	1090.9576938669472
4a97aca7-61ba-4ba7-822d-8ef6338de453	2020-12-03	2ae5e27e-cd03-40dc-a579-43d3a5348fe4	Europe	Books	7	279.44	220.729656	1545.107592	1302.7871880039522	Caleb Camacho	1	1545.107592	1487	1545.107592	66	91544.242731	1177.604080808591
8ed7f27a-a5b7-4c52-a77c-512cdaae7654	2020-12-08	8d15625f-7d94-4c39-95c7-60b6010768bf	South America	Home & Kitchen	1	210.35	201.26288	201.26288	82.8938392424866	Caleb Camacho	1	201.26288	1482	201.26288	66	91544.242731	1177.604080808591
b0c98422-d7b3-4ed0-a476-b92f1c65b566	2020-12-09	508564ba-2bf2-4f2c-b3e2-6f007f81e78c	Asia	Sports	7	20.6	14.564200000000003	101.94940000000004	26.69332854506534	Christina Thompson	1	101.94940000000004	1481	101.94940000000004	53	64491.182614000005	1021.7261378833904
e276ad08-a3d9-420d-b764-b0a8ec2c6274	2020-12-14	982b35a9-3c9e-4201-8c17-afaafaafc30f	Australia	Sports	10	169.95	145.68113999999997	1456.8113999999996	1216.7699763717249	Adam Smith	1	1456.8113999999996	1476	1456.8113999999996	55	62372.113224	936.3944649146875
065dcda0-8dc5-4d85-9fce-6cb85ee34f78	2020-12-14	3301f1b6-b269-4901-8022-bc0007deb37c	North America	Books	9	142.02	122.56326	1103.06934	875.0776612765078	Caleb Camacho	1	1103.06934	1476	1103.06934	66	91544.242731	1177.604080808591
52c4de6a-16de-40e0-a50e-c7af0f340308	2020-12-15	2e7666d1-80f1-49c6-8186-557812328335	South America	Clothing	6	248.14	191.142242	1146.8534519999998	917.0461276837992	Emily Matthews	1	1146.8534519999998	1475	1146.8534519999998	72	80570.187359	919.786031455556
cf329c89-fc81-45e2-8616-b1b90e978c60	2020-12-15	62a52000-c76f-427d-b404-497e479038b5	Europe	Sports	8	386.83	329.96599	2639.72792	2380.5524656598363	Adam Smith	1	2639.72792	1475	2639.72792	55	62372.113224	936.3944649146875
86330b97-c546-489b-8fe2-068a01a1242c	2020-12-16	202035ea-f206-489b-a45b-fcc85fb5269f	Australia	Home & Kitchen	4	143.92	141.530928	566.123712	375.4968307285339	Michelle Garza	1	566.123712	1474	566.123712	65	76798.491008	980.44596940906
53b4babc-abbd-4178-b01c-ab4d0240ce27	2020-12-16	6751983f-9323-4c70-84da-3640a42a8a0f	Australia	Toys	6	238.72	200.64416	1203.86496	971.857220402012	Emily Matthews	1	1203.86496	1474	1203.86496	72	80570.187359	919.786031455556
fb09bc5f-aec3-48cb-a399-b4afc3d8de7c	2020-12-16	bb37f3db-38a4-4be9-b0c2-ceb7bc8ed949	Europe	Electronics	4	171.92	122.23512	488.94048	307.93856240476805	Susan Edwards	1	488.94048	1474	488.94048	68	86058.98736700001	1063.159646603474
19da02c0-4a42-4885-90b4-99dd76f20a83	2020-12-20	168ccf46-262e-4271-aa65-4ac607a381ad	Asia	Clothing	10	72.34	63.13111800000001	631.31118	433.8227763337192	Crystal Williams	1	631.31118	1470	631.31118	65	72555.900913	927.0834787540324
8209ca50-a93c-4b9a-8d42-b5ecce2f9133	2020-12-23	bf0e5444-4dbf-400c-82ec-c0dab64278e3	Australia	Sports	8	43.25	33.10355	264.8284	127.00461649752796	Steven Coleman	1	264.8284	1467	264.8284	59	68355.922945	964.8650638967956
1cbfc9c6-d78d-4e15-bf6c-a0e46a0f1976	2020-12-25	061d6b66-3643-4d56-be4e-a8464d2e5b5b	South America	Toys	9	405.1	296.49269000000004	2668.4342100000003	2408.982566328209	Susan Edwards	1	2668.4342100000003	1465	2668.4342100000003	68	86058.98736700001	1063.159646603474
2913c71f-a34c-467c-a7b6-90e358e0a81c	2020-12-28	553c7de9-e74d-4366-97b7-81ee5dc61ad9	Australia	Clothing	6	485.53	390.269014	2341.614084	2085.635632148714	Mary Scott	1	2341.614084	1462	2341.614084	63	77562.23517100001	1033.152899764227
5fb7b6d6-fc47-4ebf-a68c-6bd3861a9242	2020-12-30	a0b8d25f-b71d-4551-ba56-f67f7c2b2c3e	Europe	Electronics	2	296.43	268.980582	537.961164	350.64225874563886	Jason Nelson	1	537.961164	1460	537.961164	70	87933.283392	1049.1629849529377
af2711f0-054d-4ec6-9b80-bf425994f284	2021-01-03	d431813f-161e-41bc-b100-21e99643752c	North America	Sports	4	464.19	379.985934	1519.943736	1278.249310125018	Emily Matthews	1	1519.943736	1456	1519.943736	72	80570.187359	919.786031455556
fd5a0b1b-e0f5-4322-8e4b-6776678ede97	2021-01-05	788ae47a-1fa0-445b-8532-bfe1b895c738	North America	Home & Kitchen	10	409.5	335.33955	3353.3955	3088.6878833505675	Charles Smith	1	3353.3955	1454	3353.3955	70	95387.089343	1149.437576059358
fdee3e88-0ea3-4565-a372-788420e5745b	2021-01-08	38fbb56d-4f56-47aa-b974-a141660b98cf	Europe	Home & Kitchen	10	245.94	237.307506	2373.07506	2116.7259414760406	Roger Brown	1	2373.07506	1451	2373.07506	54	68595.667163	1076.1212096324236
d60478de-c287-4886-aa4d-ec1e12b56e4e	2021-01-09	c5b950cc-cfb4-445d-8353-8d9a02f6548b	South America	Books	7	210.37	200.69298	1404.85086	1166.2633697652934	Steven Coleman	1	1404.85086	1450	1404.85086	59	68355.922945	964.8650638967956
bd65c8ab-fdbb-4f86-aad9-fa160994b01b	2021-01-13	36fd7291-2add-42df-8323-6ef9b767d1d9	North America	Books	9	377.25	344.052	3096.4680000000003	2833.4826845247703	Adam Smith	1	3096.4680000000003	1446	3096.4680000000003	55	62372.113224	936.3944649146875
7e60ecf2-3b02-4f53-897c-ea7c4b3b3b21	2021-01-14	097e28b5-1ea9-469c-94bb-16eb11475ca7	South America	Books	1	491.94	392.518926	392.518926	226.60510150088768	Roger Brown	1	392.518926	1445	392.518926	54	68595.667163	1076.1212096324236
4777e431-e4e3-41ca-8f5a-93c457281ba5	2021-01-16	5029734a-5126-4ff2-825d-46a1e0f0fcdd	Asia	Clothing	9	422.84	298.440472	2685.964248	2426.347950916131	Caleb Camacho	1	2685.964248	1443	2685.964248	66	91544.242731	1177.604080808591
ab342dbc-4f08-4afd-bfd5-3d0d50b0e120	2021-01-16	a8e6e2d2-4c05-43fd-ba3b-fa9e68baec66	North America	Toys	10	315.42	224.29516200000003	2242.9516200000003	1988.198130835492	Charles Smith	1	2242.9516200000003	1443	2242.9516200000003	70	95387.089343	1149.437576059358
dc9ee6f7-4bb7-4b4e-9170-0bc2ed004077	2021-01-20	0c8a85c3-4a28-4dff-90db-ca28d7d72f87	South America	Electronics	6	252.79	204.304878	1225.829268	993.016461892086	Crystal Williams	1	1225.829268	1439	1225.829268	65	72555.900913	927.0834787540324
a6660ab9-668f-4020-b363-b3fc381d6478	2021-01-21	c58130f3-758c-404b-8766-801671c6697d	Australia	Home & Kitchen	6	481.84	407.829376	2446.976256	2189.789648752039	Joseph Brooks	1	2446.976256	1438	2446.976256	60	60657.854394	824.8550359343124
6bda5f08-3c22-4f3b-b2ef-558fceee4c17	2021-01-25	e5ab827c-1070-4e11-8c9c-4e448a8c082e	Australia	Home & Kitchen	2	406.76	370.314304	740.628608	533.5813887441782	Emily Matthews	1	740.628608	1434	740.628608	72	80570.187359	919.786031455556
729e0f3e-66a7-4497-8232-9ac31ab6c52f	2021-01-27	a086b4b3-2248-4156-9655-1d138a5cf561	South America	Sports	10	194.25	149.2617	1492.617	1251.623555153707	Joseph Brooks	1	1492.617	1432	1492.617	60	60657.854394	824.8550359343124
53fd74ad-e895-4af2-b89a-97ce05bd9b84	2021-01-28	86503626-2daa-4322-839d-dcd0e39cbcac	Australia	Beauty	3	349.46	269.538498	808.615494	596.5808039433606	Mary Scott	1	808.615494	1431	808.615494	63	77562.23517100001	1033.152899764227
e0cb2458-510a-4abc-9351-5cc8ad7f7dd0	2021-01-30	6e5b72bd-4a06-467b-8c9c-7b664fdf73df	South America	Home & Kitchen	6	463.57	447.205979	2683.235874	2423.6474374886084	Adam Smith	1	2683.235874	1429	2683.235874	55	62372.113224	936.3944649146875
8ce2de3b-8792-43d3-add8-8a4f7f6abdd8	2021-02-01	d790728a-5ab7-4733-b5cb-264bb99235aa	Europe	Electronics	2	15.61	13.14362	26.28724	2.203648612001832	Christina Thompson	1	26.28724	1427	26.28724	53	64491.182614000005	1021.7261378833904
4f1dfd48-7277-45e2-9174-2edfdc94a2ca	2021-02-02	71f42f60-740c-4932-951f-e4b2674d3fd4	Australia	Toys	8	437.52	386.855184	3094.841472	2831.866991433067	Michelle Andersen	1	3094.841472	1426	3094.841472	60	66978.268402	921.082547231716
52a3a03a-67bb-4a7e-a8d3-fc56adfee832	2021-02-03	e9b3905e-6aff-43d5-98fb-371d1ffce345	Asia	Books	6	304.63	289.15479600000003	1734.9287760000002	1488.3779608567531	Sandra Luna	1	1734.9287760000002	1425	1734.9287760000002	56	72688.198308	1090.9576938669472
3b98a470-330e-4abb-a952-232450fbc656	2021-02-05	1cb7a014-7a51-4c75-9349-50bb89697a70	Europe	Sports	3	108.98	85.734566	257.20369800000003	121.46899009984696	Joseph Brooks	1	257.20369800000003	1423	257.20369800000003	60	60657.854394	824.8550359343124
29ef938b-5c02-448d-98d7-e68bfb637e3b	2021-02-07	729bbacd-448f-4daa-9c59-2839b32a6ac3	Europe	Toys	8	488.26	358.675796	2869.406368	2608.176021866462	Johnny Marshall	1	2869.406368	1421	2869.406368	61	67804.798966	913.3835523608234
ef39eeac-3ca5-420c-a11a-f18c0e83261c	2021-02-08	51eee85e-415f-43f0-b0d6-dbe0cfe12855	Asia	Home & Kitchen	6	259.68	227.168064	1363.0083840000002	1125.6621210923086	Steven Coleman	1	1363.0083840000002	1420	1363.0083840000002	59	68355.922945	964.8650638967956
6bfed9ae-60c4-4f82-be47-181aa186f166	2021-02-09	3e9c29fb-6643-4605-a027-76e2b4d2fe0c	Europe	Sports	3	46.95	41.926350000000006	125.77905	38.29275244139946	Johnny Marshall	1	125.77905	1419	125.77905	61	67804.798966	913.3835523608234
c241a139-3eb4-4b02-90b3-102d6c0aacc5	2021-02-10	bf1fc9d8-9e9d-4d9b-b0d9-4c478a5e6ab9	North America	Electronics	7	154.54	138.40602399999997	968.8421679999998	747.1949469343642	Diane Andrews	1	968.8421679999998	1418	968.8421679999998	58	66389.094387	950.0340815608216
85f1250b-6e7f-4b5a-b524-470c4c071163	2021-02-17	1739af28-f838-411d-be9a-74fb6e6635fb	Australia	Clothing	9	335.17	294.51387900000003	2650.6249110000003	2391.3443758341978	Jason Nelson	1	2650.6249110000003	1411	2650.6249110000003	70	87933.283392	1049.1629849529377
5fe83d81-8d1a-439c-bfc3-ea96a57ba57d	2021-02-18	984f17b1-b503-4102-86de-bdaca713830d	North America	Clothing	6	71.8	63.19836	379.19016	215.7038445735966	Kristen Ramos	1	379.19016	1410	379.19016	62	73461.618973	988.8412277570784
f5be24dd-8bff-4a5f-ba6a-c395c0c70583	2021-02-18	7dc7c916-729e-4835-a212-77f21104ebea	South America	Sports	3	200.3	143.97564	431.92692	259.3563338798993	Crystal Williams	1	431.92692	1410	431.92692	65	72555.900913	927.0834787540324
6b52373a-6dfa-4eaa-acac-dfb2e103aed6	2021-02-20	82efd9b7-2d4c-420c-8f95-bdec13b06666	Europe	Books	4	211.07	174.15385700000002	696.6154280000001	493.15871839983646	Caitlyn Boyd	1	696.6154280000001	1408	696.6154280000001	58	71709.8323	1035.5858485437743
0208fe92-f711-4a32-8887-31b64eb43cf1	2021-02-22	0292a582-de6c-495a-8dae-5c6ae921e95d	Europe	Beauty	3	401.61	375.264384	1125.793152	896.8431088860327	Christina Thompson	1	1125.793152	1406	1125.793152	53	64491.182614000005	1021.7261378833904
da876ba2-9c36-4bcc-afbc-453d60bba666	2021-02-24	1189860e-c074-4531-a96f-8a4bc5facf95	South America	Toys	5	191.39	185.552605	927.763025	708.340333310865	Diane Andrews	1	927.763025	1404	927.763025	58	66389.094387	950.0340815608216
17f37bb2-d9ab-4d48-8d47-0e9acb6dd9bd	2021-02-24	41a3eeef-c39d-45be-a261-6d5b46908911	Asia	Toys	4	138.62	116.801212	467.204848	289.2627212480195	Sandra Luna	1	467.204848	1404	467.204848	56	72688.198308	1090.9576938669472
549b44d6-5533-4579-b5e6-ab8a0ccf68d9	2021-02-26	0624e5e9-9feb-4a33-86cc-cbceb8dcde6e	Europe	Home & Kitchen	8	71.14	55.282894	442.263152	268.0683621303714	Sandra Luna	1	442.263152	1402	442.263152	56	72688.198308	1090.9576938669472
8a16bf66-ddb8-4c22-b5b7-5621d54bacad	2021-02-27	c6e0535d-c5ed-4aa8-baea-66bdc97d4952	South America	Sports	2	361.72	310.93451200000004	621.8690240000001	425.3113958313421	Emily Matthews	1	621.8690240000001	1401	621.8690240000001	72	80570.187359	919.786031455556
9431e071-003e-47a6-b82b-b4376eeb5025	2021-03-01	e834a656-f8c7-40d5-85cd-e91a82684299	Australia	Books	7	477.09	347.273811	2430.916677	2173.9079888359147	Christina Thompson	1	2430.916677	1399	2430.916677	53	64491.182614000005	1021.7261378833904
d1477d56-7d9a-48d9-8f09-51d1943cc843	2021-03-03	3ba201aa-3768-4f93-bccb-f45c809375d4	South America	Electronics	10	126.09	119.520711	1195.20711	963.5239453105372	Emily Matthews	1	1195.20711	1397	1195.20711	72	80570.187359	919.786031455556
f0755b44-f7d3-4dc1-bc76-f70697154431	2021-03-04	dfd5a7dc-3176-4c33-9d00-92f5539c62b5	Asia	Toys	6	327.99	247.894842	1487.369052	1246.5151717655212	Jason Nelson	1	1487.369052	1396	1487.369052	70	87933.283392	1049.1629849529377
4b0e114d-9ec3-4fc8-bdd3-aa10b6e1a041	2021-03-05	472f3a96-c3ed-49e4-bbaf-704a9e9657a2	Australia	Books	6	295.5	244.70355	1468.2213	1227.872076761013	Steven Coleman	1	1468.2213	1395	1468.2213	59	68355.922945	964.8650638967956
e508ba19-1028-4f25-8973-bc09a4c26165	2021-03-10	4dd5bae3-ce34-4f36-845f-01cc5e9ef533	Australia	Home & Kitchen	3	7.71	5.398541999999999	16.195625999999997	0.8646661363120032	Caitlyn Boyd	1	16.195625999999997	1390	16.195625999999997	58	71709.8323	1035.5858485437743
f70df7f4-8264-40b9-8a75-c945cd046a7a	2021-03-17	ba47290f-31da-4f12-8f21-5ccbabd224ad	South America	Clothing	7	361.48	337.007804	2359.0546280000003	2102.86955480596	Adam Smith	1	2359.0546280000003	1383	2359.0546280000003	55	62372.113224	936.3944649146875
dd820585-5eb3-4eae-b932-46c0b371fba3	2021-03-17	b27796a9-26af-4be0-98f5-7b31a4b27f9c	North America	Books	5	484.9	374.29431	1871.47155	1622.3373030052317	Bradley Howe	1	1871.47155	1383	1871.47155	56	64186.396558	951.6581100155678
ac716c89-37fb-46e3-b4e7-035cfa7fa44a	2021-03-21	e757ee60-3666-420d-91e6-25ceecb1bbfe	South America	Sports	7	59.55	47.252925	330.770475	176.98811645241526	Jason Nelson	1	330.770475	1379	330.770475	70	87933.283392	1049.1629849529377
5f67731c-f950-424b-8290-c5e6d5987f1f	2021-03-22	e5e56e04-1003-46cc-8e3d-6ae161ca451b	Europe	Sports	10	38.65	30.591475	305.91475	157.72895751792288	Michelle Andersen	1	305.91475	1378	305.91475	60	66978.268402	921.082547231716
309d8b13-7309-48ac-ab94-ff052d91c01f	2021-03-27	b676473f-813b-43fe-9262-728b71af878d	South America	Electronics	8	313.33	251.353326	2010.826608	1759.3727004369746	Caitlyn Boyd	1	2010.826608	1373	2010.826608	58	71709.8323	1035.5858485437743
74ca5c07-b394-4fe7-beac-f843141ea3f9	2021-04-02	90fa9816-6a6b-47cc-81fc-5eefd6cdc94e	North America	Electronics	6	351.66	283.0863	1698.5178	1452.715597426955	Bradley Howe	1	1698.5178	1367	1698.5178	56	64186.396558	951.6581100155678
6f44bd6d-af99-4fb9-ae3b-a3437efe0a03	2021-04-04	c2a9602c-f867-4977-a438-0fb5d828cc75	Asia	Electronics	10	418.1	388.74938	3887.4938	3619.883551285564	Crystal Williams	1	3887.4938	1365	3887.4938	65	72555.900913	927.0834787540324
a1545695-3dbc-457a-a355-468e6ce5eb6d	2021-04-05	93b6692e-8b66-4f43-8fd7-24b16bce9198	Europe	Sports	5	247.43	236.39462200000003	1181.97311	950.7893695106304	Diane Andrews	1	1181.97311	1364	1181.97311	58	66389.094387	950.0340815608216
9c032633-ee9f-4599-a06c-d262daedad97	2021-04-09	2608079a-6f0f-4cb1-89c0-18a5e4c64079	North America	Books	9	132.79	121.077922	1089.701298	862.2869569519378	Steven Coleman	1	1089.701298	1360	1089.701298	59	68355.922945	964.8650638967956
5058d61d-6be5-4453-b809-e18de53a059f	2021-04-15	5dc5d254-8187-4d77-b960-7f86c723bce4	Europe	Home & Kitchen	1	165.75	120.649425	120.649425	35.67307269685871	Susan Edwards	1	120.649425	1354	120.649425	68	86058.98736700001	1063.159646603474
81c6ce14-da43-4f54-a647-2c909992e00b	2021-04-17	10972159-cb7c-4287-9735-e641c4b1b670	Australia	Sports	8	58.28	50.336436	402.691488	234.98722013393305	Bradley Howe	1	402.691488	1352	402.691488	56	64186.396558	951.6581100155678
56527005-10c0-4edd-9f3b-d8a552e50289	2021-04-17	dcd7f2ae-e628-4ed1-98e3-f824e9b49fe5	Europe	Sports	1	13.81	11.502349	11.502349	0.4423980384615387	Christina Thompson	1	11.502349	1352	11.502349	53	64491.182614000005	1021.7261378833904
74ea1c47-e6d4-4b8d-bf0a-76f42861c1d4	2021-04-19	b4e8ea8f-bac3-4124-8a31-f7125e1fa46a	South America	Clothing	8	128.71	126.830834	1014.646672	790.6875787431851	Joseph Brooks	1	1014.646672	1350	1014.646672	60	60657.854394	824.8550359343124
7e7ec9c0-b532-42b5-b50f-424da3aeefe4	2021-04-19	4988ec3a-6f54-4364-b830-02716be8f981	Asia	Toys	8	211.24	171.31564000000003	1370.5251200000002	1132.94969356816	Susan Edwards	1	1370.5251200000002	1350	1370.5251200000002	68	86058.98736700001	1063.159646603474
a7654bbc-bc80-4954-960a-93ef4c0e21a1	2021-04-21	f789ccb4-3fe7-491c-9977-29888f3337e0	Europe	Beauty	6	265.43	252.264672	1513.588032	1272.0554573981426	Michelle Garza	1	1513.588032	1348	1513.588032	65	76798.491008	980.44596940906
2c549213-db74-4ee8-a0cf-9e01279ad514	2021-04-25	e676b7cd-1653-4537-93aa-4801e783a19e	North America	Sports	5	38.96	33.392616	166.96308	61.35040367638688	Joseph Brooks	1	166.96308	1344	166.96308	60	60657.854394	824.8550359343124
de45208e-0dd8-44e9-b51a-4d83394c47a6	2021-04-26	6a5046eb-16a3-4573-a1ca-8d23e3a6ecb4	Australia	Sports	1	452.33	393.210469	393.210469	227.1727741262562	Mary Scott	1	393.210469	1343	393.210469	63	77562.23517100001	1033.152899764227
2b31a478-a811-461a-a72c-0d533eecbe7d	2021-04-27	98196daf-d21a-4933-bdc0-285391dd3839	Asia	Books	2	356.71	312.335276	624.670552	427.8371287582556	Michelle Andersen	1	624.670552	1342	624.670552	60	66978.268402	921.082547231716
f9af9af2-7d6a-467e-9a1c-1ce0b3dc451b	2021-05-02	f4d81e9e-d75b-48c2-8701-156704e5d2f9	Australia	Beauty	6	125.06	122.971498	737.828988	530.9977744771676	Kristen Ramos	1	737.828988	1337	737.828988	62	73461.618973	988.8412277570784
f1f2dfc7-5d9f-49ec-bf2d-dbe4fb4a14f9	2021-05-06	57fc6f7c-3287-4d9d-bd7a-d31219722ee8	Asia	Electronics	1	52.39	44.908708	44.908708	6.070423817694369	Mary Scott	1	44.908708	1333	44.908708	63	77562.23517100001	1033.152899764227
6010a7e7-1d87-449c-9628-c834a5742328	2021-05-08	80e639a9-df4e-4d8a-92aa-86b31dd47c1e	South America	Toys	1	330.84	265.33368	265.33368	127.36899613976706	Bradley Howe	1	265.33368	1331	265.33368	56	64186.396558	951.6581100155678
2e139e80-8082-43f2-bd50-ea93d44e59c7	2021-05-12	d8873f11-2c27-4cc5-84dc-5edb21d70980	Australia	Clothing	3	433.33	413.136822	1239.410466	1006.1140638616872	Michelle Garza	1	1239.410466	1327	1239.410466	65	76798.491008	980.44596940906
a2ee3711-b7af-4015-a5de-8d801fc1871f	2021-05-14	b071f5f4-78ea-4927-bd60-9bc960a67c99	Europe	Home & Kitchen	9	122.17	85.714472	771.430248	562.041439574833	Charles Smith	1	771.430248	1325	771.430248	70	95387.089343	1149.437576059358
36f8b42c-21be-4c72-92ef-810702ebe7c9	2021-05-16	404d0675-6a80-492b-aead-0ff3644946f8	Asia	Beauty	6	339.01	253.104866	1518.629196	1276.96703339915	Charles Smith	1	1518.629196	1323	1518.629196	70	95387.089343	1149.437576059358
a7c4177a-1191-414a-8a92-77ca9624fa9f	2021-05-17	6dc3f0a2-d7de-49d2-b254-8a8e6d9c5d61	Europe	Sports	6	82.28	67.107568	402.645408	234.94636260224905	Roger Brown	1	402.645408	1322	402.645408	54	68595.667163	1076.1212096324236
5e7f51da-4cda-4a21-9f8f-561728cb028f	2021-05-18	20eff3c3-337f-4d5c-845d-b50602fdad6e	North America	Toys	7	53.63	37.610719	263.275033	125.87352316230886	Roger Brown	1	263.275033	1321	263.275033	54	68595.667163	1076.1212096324236
3c00608e-43cd-4ff7-883f-0725bd6cd151	2021-05-18	f8a86866-5697-4021-901c-32e03cde5b54	Asia	Toys	9	468.53	460.56499	4145.08491	3876.32494695779	Jason Nelson	1	4145.08491	1321	4145.08491	70	87933.283392	1049.1629849529377
9707f490-9023-4033-9717-5f35e39faefb	2021-05-19	8715cb90-a0de-4741-a781-47f16bafdd7a	Europe	Sports	4	86.94	86.487912	345.951648	188.96492203911603	Kristen Ramos	1	345.951648	1320	345.951648	62	73461.618973	988.8412277570784
4900aefa-3c3c-40e2-b0ae-d8868caca558	2021-05-21	ed9aa6c4-655f-44e5-a5e4-774deb633add	South America	Toys	3	407.97	364.439601	1093.318803	865.7479179595155	Charles Smith	1	1093.318803	1318	1093.318803	70	95387.089343	1149.437576059358
7c8a7e08-de74-4d9e-a897-26791ff8feba	2021-05-22	5bcc9cd0-fd2b-402b-9be3-365ee612e127	South America	Toys	5	421.01	405.474731	2027.373655	1775.6604514937983	Sandra Luna	1	2027.373655	1317	2027.373655	56	72688.198308	1090.9576938669472
6429d13b-b04f-48d5-8d52-2c20300c91e0	2021-05-25	a92a4764-68a2-4c6b-9ded-c116422837d8	Asia	Toys	3	8.91	6.982767000000001	20.948301	1.423367641811911	Michelle Andersen	1	20.948301	1314	20.948301	60	66978.268402	921.082547231716
6ebf08a3-e731-4223-b8a6-f673420413f1	2021-05-25	f00e63f8-2b4d-4198-a73e-bf512a67ccd2	Australia	Toys	7	287.85	276.62385	1936.36695	1686.1159774887888	Emily Matthews	1	1936.36695	1314	1936.36695	72	80570.187359	919.786031455556
9df88036-e2e3-4c95-8ccc-f81c9dcb89d9	2021-05-28	3f521819-f7aa-4463-85d9-4a82741477d9	Asia	Electronics	5	249.46	201.239382	1006.19691	782.6522409191086	Kristen Ramos	1	1006.19691	1311	1006.19691	62	73461.618973	988.8412277570784
72bd832a-b99b-40f4-973c-f94fc7da558a	2021-05-30	64085663-e96a-46af-b6c5-4eab6b2477c8	South America	Home & Kitchen	2	404.03	358.819043	717.6380859999999	512.4286021419462	Emily Matthews	1	717.6380859999999	1309	717.6380859999999	72	80570.187359	919.786031455556
05b73ad3-b1da-4a9e-a395-8a2e3e289698	2021-06-02	8b4be6c9-dad2-4e6f-95ff-8a0cffac76db	North America	Sports	2	398.12	339.59636	679.19272	477.2503657645765	Mary Scott	1	679.19272	1306	679.19272	63	77562.23517100001	1033.152899764227
722a6f6c-d60c-42d2-9174-8b8b94e9dd6e	2021-06-05	77437510-a7a4-4b4f-94e8-462f2436a81f	Australia	Toys	7	78.86	58.955736	412.690152	243.27711751724135	Sandra Luna	1	412.690152	1303	412.690152	56	72688.198308	1090.9576938669472
c64cea16-097e-4f72-b9a7-690a4299d273	2021-06-05	424f01e9-699c-4dfa-82c8-b91a2e72c530	South America	Beauty	6	10.52	10.086576	60.51945599999999	10.52816573071204	Diane Andrews	1	60.51945599999999	1303	60.51945599999999	58	66389.094387	950.0340815608216
437e43ea-c232-4024-a1b2-6ec121053145	2021-06-07	14b38d32-e6bd-46fc-aaf0-86b16d75d3bd	Europe	Toys	8	302.21	226.6575	1813.26	1565.184260873134	Roger Brown	1	1813.26	1301	1813.26	54	68595.667163	1076.1212096324236
2a533d00-b905-4a04-9cde-545972bf609d	2021-06-12	e29df444-cc09-4e9c-b0fb-a2c02fcf69e7	South America	Electronics	9	29.91	27.693669	249.243021	115.75811258097688	Caitlyn Boyd	1	249.243021	1296	249.243021	58	71709.8323	1035.5858485437743
b2db69af-f9a7-4fd2-92e8-1e0e55ec73cb	2021-06-13	f4f83481-e722-43fd-831d-7cc542421091	Europe	Books	1	259.61	191.384492	191.384492	76.5009503708506	Emily Matthews	1	191.384492	1295	191.384492	72	80570.187359	919.786031455556
375f4284-c3a9-406e-adaf-7fec217f1730	2021-06-17	235ed144-0b5b-40ed-b211-9a34fd3a28be	Australia	Electronics	5	135.09	130.848174	654.24087	454.5641204196551	Jason Nelson	1	654.24087	1291	654.24087	70	87933.283392	1049.1629849529377
cc5f7a82-02a5-48d9-88e2-c0594daefea5	2021-06-17	0d251995-6982-40ff-8ffc-363e0c374ada	Europe	Home & Kitchen	9	56.13	55.394697	498.552273	316.2462529612389	Diane Andrews	1	498.552273	1291	498.552273	58	66389.094387	950.0340815608216
d0e58399-378b-4b26-af44-38533007f7a8	2021-06-21	8c7e5583-69ca-47fd-9de5-114e8cdaf0b2	North America	Beauty	5	395.57	322.231322	1611.15661	1367.2673848898746	Christina Thompson	1	1611.15661	1287	1611.15661	53	64491.182614000005	1021.7261378833904
f930ca04-9ea9-4174-8e02-9398929613e3	2021-06-24	c361c8ab-2132-47d8-a4a9-18f7a8b5dee8	Australia	Home & Kitchen	8	376.45	365.043565	2920.34852	2658.703712402455	Roger Brown	1	2920.34852	1284	2920.34852	54	68595.667163	1076.1212096324236
d688e61b-2e38-454a-b631-d030fffc5c83	2021-06-27	e5094586-c238-4297-a0cd-879ffdc1c6aa	South America	Sports	9	277.43	198.778595	1789.0073549999995	1541.390453035959	Joseph Brooks	1	1789.0073549999995	1281	1789.0073549999995	60	60657.854394	824.8550359343124
55dbf0d7-bd2d-467a-9fb7-02d7026271aa	2021-06-29	e632dacd-0477-429e-898d-1236967be00f	Australia	Toys	5	59.98	56.23125	281.15625	139.03612160693524	Steven Coleman	1	281.15625	1279	281.15625	59	68355.922945	964.8650638967956
9f4bc823-09f5-42ae-bb61-94665327c3c5	2021-06-29	1c07c700-edd4-4044-8b90-aadace7243f6	South America	Electronics	1	285.23	277.64288200000004	277.64288200000004	136.42784614221048	Diane Andrews	1	277.64288200000004	1279	277.64288200000004	58	66389.094387	950.0340815608216
35ce6c04-9be9-47fe-8620-b1fbf29483bb	2021-06-30	c7a8fc65-4d61-4cba-80d4-f6f7729a031a	North America	Books	8	488.14	465.19742	3721.57936	3454.788002665634	Charles Smith	1	3721.57936	1278	3721.57936	70	95387.089343	1149.437576059358
f5d105ec-83a7-4376-b66e-120d70a0f6cb	2021-07-01	74cebf35-0d91-435d-b800-8ed82f9cb8dc	Australia	Sports	8	12	8.538	68.304	13.117767471923727	Michelle Garza	1	68.304	1277	68.304	65	76798.491008	980.44596940906
6eb293ae-aee4-4af9-b51f-1b220131bdc2	2021-07-02	d49d7760-d896-4022-8dc9-53070ba30e99	Europe	Sports	5	69.9	49.167660000000005	245.83830000000003	113.3394857281449	Steven Coleman	1	245.83830000000003	1276	245.83830000000003	59	68355.922945	964.8650638967956
dd9c1a88-5c3a-4e29-8a98-456588306733	2021-07-04	6c3d00da-3f0e-438b-bd51-52840cf48910	Asia	Home & Kitchen	3	23.75	21.325125	63.975375	11.648060260919353	Johnny Marshall	1	63.975375	1274	63.975375	61	67804.798966	913.3835523608234
76fc440f-a310-4484-8995-f5c7afca6280	2021-07-05	dc30b344-e239-409b-b77f-037ff8dc27c0	Europe	Clothing	8	253.45	244.858045	1958.86436	1708.2387941662507	Bradley Howe	1	1958.86436	1273	1958.86436	56	64186.396558	951.6581100155678
26104e28-9a40-4874-be4d-edf8e52148d4	2021-07-05	3e4a57fe-bb51-4f6e-a1f6-68cb4a7ac127	Australia	Toys	7	361.16	360.329332	2522.305324	2264.30856401432	Michelle Garza	1	2522.305324	1273	2522.305324	65	76798.491008	980.44596940906
5db7c3c6-e5ce-451b-b2be-af8d2572d4e3	2021-07-09	809cfdd2-34b6-4848-b904-c04701661ebf	Asia	Clothing	7	375.38	366.708722	2566.961054	2308.504861932017	Kristen Ramos	1	2566.961054	1269	2566.961054	62	73461.618973	988.8412277570784
d77d3af1-aa4b-4435-94ee-3d1c02543dde	2021-07-10	296db052-5d95-434d-b047-773eb5b6f755	Asia	Home & Kitchen	2	51.26	50.583368	101.166736	26.339268544378697	Christina Thompson	1	101.166736	1268	101.166736	53	64491.182614000005	1021.7261378833904
ab2f1881-fd35-49d7-9af9-d57800992e1c	2021-07-14	a94e1ccd-4917-485d-9681-9235e4dd337d	Asia	Clothing	3	278.43	274.893939	824.6818169999999	611.5582049054141	Bradley Howe	1	824.6818169999999	1264	824.6818169999999	56	64186.396558	951.6581100155678
527f981d-e81b-4f1d-af2c-1389643d9e5f	2021-07-15	6ba29154-7ecb-43ae-88b6-fb07edf20dac	Asia	Sports	4	405.7	346.18381	1384.73524	1146.7387049296185	Bradley Howe	1	1384.73524	1263	1384.73524	56	64186.396558	951.6581100155678
126bd67b-d5f4-4827-8502-78708e6cfd08	2021-07-21	eed36772-0150-4226-b7e5-cb10a138ec15	North America	Books	8	227.58	205.04958	1640.3966400000002	1395.8460213172723	Michelle Garza	1	1640.3966400000002	1257	1640.3966400000002	65	76798.491008	980.44596940906
11dcfe87-bb7d-4a76-9f3e-4e3c36d6ca6b	2021-07-25	40039a97-0e95-4acd-a3f9-bcb31aa328bb	Australia	Home & Kitchen	8	445.46	366.39085	2931.1268	2669.3956811501025	Joseph Brooks	1	2931.1268	1253	2931.1268	60	60657.854394	824.8550359343124
743bee50-0dd8-4fc3-8305-094d0c1d3b5c	2021-07-26	602f29e7-0fde-47c2-b641-a679d4a0d292	Europe	Toys	10	362.87	266.745737	2667.45737	2408.014937475563	Jason Nelson	1	2667.45737	1252	2667.45737	70	87933.283392	1049.1629849529377
0b787ee4-244d-40de-ae85-8fa7406c7866	2021-07-26	c6f72d86-0150-40eb-b02b-37b5475ee786	South America	Electronics	3	389.76	293.411328	880.2339840000001	663.5770026078567	Christina Thompson	1	880.2339840000001	1252	880.2339840000001	53	64491.182614000005	1021.7261378833904
36cdff69-6d5f-4e31-90eb-a1863d1459fd	2021-07-27	b1a04bc4-9c6b-4d49-ade8-e1d9fa444ce1	Asia	Toys	3	94.74	68.288592	204.865776	85.2640619478078	Kristen Ramos	1	204.865776	1251	204.865776	62	73461.618973	988.8412277570784
1184aebd-1e55-4d3c-a72a-b617f2dcf420	2021-07-31	daac7a1f-9416-4e01-b16b-24829da9a619	Asia	Home & Kitchen	6	198.5	145.67915	874.0749	657.7946753253823	Michelle Garza	1	874.0749	1247	874.0749	65	76798.491008	980.44596940906
67b3253e-c7aa-4da4-8b47-2400bbf6853c	2021-08-01	69e42404-bac8-4989-80c5-bcee0f897309	North America	Electronics	10	67.52	52.726368	527.26368	341.25377384040075	Michelle Garza	1	527.26368	1246	527.26368	65	76798.491008	980.44596940906
4c351c3a-2185-4eb8-9cf2-c05ab1d54e63	2021-08-03	aa13bebd-20e1-48c7-b09c-e0fc81d8cb19	Australia	Sports	8	115.87	82.638484	661.107872	460.7964333864986	Kristen Ramos	1	661.107872	1244	661.107872	62	73461.618973	988.8412277570784
df817907-7997-4a6f-ac23-4d23609a1fba	2021-08-08	f79681c3-bf78-4778-99cf-ab54bce0ae42	Europe	Books	1	324.51	296.342532	296.342532	150.4400496012998	Kristen Ramos	1	296.342532	1239	296.342532	62	73461.618973	988.8412277570784
85404cd8-cdf8-423b-88b6-9ec933f2f45c	2021-08-09	0be1925e-0ed8-41af-a469-45ab796cdcfe	South America	Home & Kitchen	6	381.79	380.491914	2282.951484	2027.6905729574669	Johnny Marshall	1	2282.951484	1238	2282.951484	61	67804.798966	913.3835523608234
8996c724-8558-402a-a46b-c3b18ca5223c	2021-08-09	a196c3a7-afdd-43c5-8044-2b9fa4c54271	Asia	Electronics	5	192.4	145.08884	725.4442	519.5977100164577	Adam Smith	1	725.4442	1238	725.4442	55	62372.113224	936.3944649146875
a7ac145d-90d8-4df8-a879-43585b834228	2021-08-11	eb4961fb-45e9-46d8-a8dd-c3351b248337	Asia	Clothing	9	205.35	155.470485	1399.234365	1160.811142650928	Michelle Garza	1	1399.234365	1236	1399.234365	65	76798.491008	980.44596940906
0be13121-bbec-45a4-99cc-1d99cdf7b547	2021-08-12	82b2a9bc-03bd-4c1c-866a-db0bce1f2c5e	Europe	Electronics	7	368.15	314.657805	2202.604635	1948.379723296399	Caleb Camacho	1	2202.604635	1235	2202.604635	66	91544.242731	1177.604080808591
6907bd2a-aada-48ba-a8c4-46f010b06a03	2021-08-13	3f90c583-55b9-4b93-9dec-24683629f022	South America	Clothing	9	102.11	96.095721	864.861489	649.147651422368	Michelle Garza	1	864.861489	1234	864.861489	65	76798.491008	980.44596940906
9e343e2e-a95c-4bbc-b08d-4cf2f6097ddc	2021-08-14	1d570c45-c6a1-4564-9f2c-0f88f0e6bbd2	North America	Clothing	3	56.57	52.293308	156.87992400000002	55.39863543023482	Susan Edwards	1	156.87992400000002	1233	156.87992400000002	68	86058.98736700001	1063.159646603474
3f023466-0f5c-40d0-8d89-1108458def15	2021-08-15	afe15478-3238-49a6-9e42-4b23d4ea7cfd	Asia	Electronics	4	142.98	100.98677399999998	403.94709599999993	236.0276181150648	Bradley Howe	1	403.94709599999993	1232	403.94709599999993	56	64186.396558	951.6581100155678
3f47f2df-d8b0-4653-ab46-77515329b74f	2021-08-15	4ad09505-42dd-41f3-a48e-ea8d0c3b6c48	Europe	Electronics	3	196.54	177.731122	533.193366	346.45524180989736	Adam Smith	1	533.193366	1232	533.193366	55	62372.113224	936.3944649146875
0cb23dac-ec90-4c0f-87a5-faae00ff612d	2021-08-17	ec57a694-c03e-4e18-bc53-9f0e3b0cac57	Australia	Electronics	10	495.15	397.159815	3971.59815	3703.598220853071	Michelle Garza	1	3971.59815	1230	3971.59815	65	76798.491008	980.44596940906
14b63a78-3e12-40c3-b7f3-2ce2545d49b5	2021-08-18	f52e36cd-210d-4426-9a65-c8f9b2807409	Australia	Clothing	9	295.09	234.567041	2111.1033689999995	1858.1463529318448	Mary Scott	1	2111.1033689999995	1229	2111.1033689999995	63	77562.23517100001	1033.152899764227
d5bace46-a064-4850-95f8-3f426ec38074	2021-08-19	b1cb397b-65bb-4c95-a26a-b1c92d98ce82	Australia	Toys	4	150.39	133.967412	535.869648	348.8035138102353	Crystal Williams	1	535.869648	1228	535.869648	65	72555.900913	927.0834787540324
c263d9bc-7aba-48d1-aab5-c656cd1b375a	2021-08-21	d208f534-4e94-4add-b90e-c634c883892c	South America	Electronics	3	180.27	159.052221	477.156663	297.79468765887304	Bradley Howe	1	477.156663	1226	477.156663	56	64186.396558	951.6581100155678
b1760b66-5738-46d8-93cc-19501345ab32	2021-08-23	5d92ecff-b64b-4476-9353-108f6380ada4	Australia	Electronics	3	356.44	301.72646000000003	905.17938	687.0428415384615	Diane Andrews	1	905.17938	1224	905.17938	58	66389.094387	950.0340815608216
342b0ce0-ed45-4054-9aeb-7a08bb3b26c7	2021-08-24	696f6843-9163-49de-9d1d-fdf76c1ea90b	South America	Electronics	5	189.24	182.162424	910.81212	692.3500361469827	Crystal Williams	1	910.81212	1223	910.81212	65	72555.900913	927.0834787540324
79f9fd16-0d63-412b-ac88-a45584660809	2021-08-28	45e5fda1-a69b-45e5-96b1-a09178b1fb4e	Australia	Home & Kitchen	8	213.47	210.374685	1682.99748	1437.523014925103	Emily Matthews	1	1682.99748	1219	1682.99748	72	80570.187359	919.786031455556
3cffbe14-861d-42d8-8fec-736d5bc77950	2021-09-01	a581976f-4340-482c-9568-a745256dc4c2	Australia	Home & Kitchen	4	175.55	146.09271	584.37084	391.718995474236	Caleb Camacho	1	584.37084	1215	584.37084	66	91544.242731	1177.604080808591
d3e1e4cf-4799-4f37-a2fc-1883e8ae8320	2021-09-03	0083537c-a9ee-449c-a023-780a3d2180aa	South America	Books	2	270.63	236.341179	472.682358	293.95420055303055	Susan Edwards	1	472.682358	1213	472.682358	68	86058.98736700001	1063.159646603474
900fb59e-3076-472a-8e60-af4de619acee	2021-09-03	f6253d72-b866-4b61-bd3f-f11346beb864	Australia	Home & Kitchen	2	312.86	235.552294	471.104588	292.60178866686874	Diane Andrews	1	471.104588	1213	471.104588	58	66389.094387	950.0340815608216
b49099e3-1db1-4415-893f-beabc7960371	2021-09-05	80fa92df-fe68-43f3-b56c-fa0a4dbee07b	Europe	Beauty	3	458.49	396.59385	1189.7815500000002	958.3020367798986	Michelle Andersen	1	1189.7815500000002	1211	1189.7815500000002	60	66978.268402	921.082547231716
a87d8376-6354-461e-a9fd-745a8a1c25f0	2021-09-07	9ad4339f-31ff-4cbf-a53c-cd7e37c9285d	Asia	Books	6	355.93	349.808004	2098.848024	1846.0661350442008	Kristen Ramos	1	2098.848024	1209	2098.848024	62	73461.618973	988.8412277570784
c98c354f-aa11-489a-b76d-39e283c755b3	2021-09-07	829d953b-9826-48ba-9745-6f075ed8fd84	South America	Home & Kitchen	2	135.57	132.085851	264.171702	126.524921049604	Johnny Marshall	1	264.171702	1209	264.171702	61	67804.798966	913.3835523608234
e4076a69-dd06-445b-be5c-8e91f723d009	2021-09-10	ab80fec8-0774-4753-8efe-8da7319d1bad	Australia	Clothing	9	228.52	206.376412	1857.387708	1608.5048731770762	Steven Coleman	1	1857.387708	1206	1857.387708	59	68355.922945	964.8650638967956
9ac7e8b6-25fd-461a-acf1-259aceb76dc2	2021-09-11	a0081cf3-2155-4623-ab19-59a5170b49f5	Australia	Toys	1	498.49	423.317708	423.317708	252.1419263582693	Michelle Garza	1	423.317708	1205	423.317708	65	76798.491008	980.44596940906
316f194d-189e-4000-bf87-88c33199f6ec	2021-09-12	f31d70b3-7bfb-48c3-87e0-1dd80f39c168	South America	Beauty	8	203.59	144.671054	1157.368432	927.1425697732687	Michelle Andersen	1	1157.368432	1204	1157.368432	60	66978.268402	921.082547231716
0b3b167d-0e5a-4f33-b346-f0409be8fcc1	2021-09-14	4b4c5fc6-7b23-41e8-acf2-06e77ea2dee7	North America	Toys	4	131.43	112.096647	448.386588	273.2492596662761	Emily Matthews	1	448.386588	1202	448.386588	72	80570.187359	919.786031455556
7e5f57c5-9bfa-4c6c-9b15-f164298eb152	2021-09-15	0e0eb1e0-986d-48d4-8125-0c4ec917997e	South America	Electronics	10	414.75	325.288425	3252.88425	2988.8192867333687	Caitlyn Boyd	1	3252.88425	1201	3252.88425	58	71709.8323	1035.5858485437743
dd4600fb-b800-46c7-8b39-826a4d7a2a3c	2021-09-17	7837653d-e6c1-4a31-bcbb-7cdbfa1d2cdf	Australia	Clothing	6	78.43	71.49678800000001	428.98072800000006	256.8859199605248	Emily Matthews	1	428.98072800000006	1199	428.98072800000006	72	80570.187359	919.786031455556
9421b755-d87b-4930-9445-272be3b5e5d1	2021-09-18	2ca1d225-b436-4e5f-9771-47675559fb73	Australia	Clothing	10	239.02	218.63159400000004	2186.3159400000004	1932.3117180514448	Steven Coleman	1	2186.3159400000004	1198	2186.3159400000004	59	68355.922945	964.8650638967956
18d9211c-2787-4178-b074-abafa444fe58	2021-09-19	5cc68a92-de7c-4606-87fd-436314682bfc	Australia	Home & Kitchen	10	136.66	121.846056	1218.46056	985.9166051934272	Johnny Marshall	1	1218.46056	1197	1218.46056	61	67804.798966	913.3835523608234
40d8eda9-6e89-4e33-a179-ab9891b0e57c	2021-09-21	9d6e57e2-6cf1-4096-8ba8-c391ae3fb75c	Asia	Beauty	5	269.49	234.72579	1173.62895	942.7677760518914	Adam Smith	1	1173.62895	1195	1173.62895	55	62372.113224	936.3944649146875
addcfd3a-710f-4159-8bd6-6b1eecbabbe4	2021-09-22	24b787e2-898e-4bd8-8635-8e8d06da6db0	Europe	Sports	6	173.55	126.27498	757.64988	549.2925167461431	Roger Brown	1	757.64988	1194	757.64988	54	68595.667163	1076.1212096324236
949802a5-6621-4f32-8ab7-ba40b4b6b202	2021-09-24	5b468093-0eb4-4026-b24d-0e2a95916ba8	Europe	Beauty	7	85.46	65.83838399999999	460.8686879999999	283.8565939763404	Bradley Howe	1	460.8686879999999	1192	460.8686879999999	56	64186.396558	951.6581100155678
f294eaaf-529d-456d-87e6-2eeb6378b9de	2021-09-24	38fe541a-5546-48f7-99ab-5b12c1e087fb	South America	Beauty	5	133.21	99.947463	499.737315	317.27818359688195	Jason Nelson	1	499.737315	1192	499.737315	70	87933.283392	1049.1629849529377
4efb2779-c867-4bcc-87c1-92e75ca42f65	2021-09-26	ebc9bf26-cfb7-474e-a282-73744ae1343c	North America	Beauty	6	58.52	41.203932	247.223592	114.32197281926672	Crystal Williams	1	247.223592	1190	247.223592	65	72555.900913	927.0834787540324
3c0584c3-bfc6-4f8a-b0e1-b361a4b42866	2021-09-27	0266a04c-121d-4f85-b7cb-7a8567c4faff	Asia	Electronics	3	12.43	9.985019	29.955057	2.826767740807828	Steven Coleman	1	29.955057	1189	29.955057	59	68355.922945	964.8650638967956
7dcdf07e-dfaf-452b-b20d-7fe7a2997153	2021-09-27	7f2dfc13-d017-4d4c-ba8e-7416d59c0f39	Australia	Clothing	3	368.82	325.11483	975.34449	753.3574426367298	Jason Nelson	1	975.34449	1189	975.34449	70	87933.283392	1049.1629849529377
ac26e739-c29f-444c-9bd9-e9200145ddc0	2021-09-30	e7695ebd-a9c1-42e4-8b36-fcc72609cbe4	Asia	Beauty	4	223.39	182.129867	728.519468	522.4260939300121	Susan Edwards	1	728.519468	1186	728.519468	68	86058.98736700001	1063.159646603474
12916739-5ebc-4d73-a96f-185e1a4e4f5a	2021-10-01	65a07793-fb60-481f-87a3-84ea5b72495a	Australia	Beauty	9	410.22	382.201974	3439.817766	3174.583918671756	Christina Thompson	1	3439.817766	1185	3439.817766	53	64491.182614000005	1021.7261378833904
7feb34bc-389f-4207-b3e3-d74efc87c431	2021-10-02	c9b8d1b7-3a0f-494f-8a0e-770481876c72	Australia	Beauty	6	104.3	88.21694	529.3016399999999	343.0393181504029	Kristen Ramos	1	529.3016399999999	1184	529.3016399999999	62	73461.618973	988.8412277570784
4992c2e1-e1ed-4e89-98d1-4aba5486d596	2021-10-03	069f01ff-e378-4eb8-a6c5-6a086d05975d	North America	Sports	10	153.31	118.293996	1182.9399600000002	951.7208751502122	Charles Smith	1	1182.9399600000002	1183	1182.9399600000002	70	95387.089343	1149.437576059358
6f44a1db-1e60-41d5-a1d0-4d60b39913f2	2021-10-04	f4b1fdba-8fab-40e9-83d8-8575bf7d1272	Europe	Electronics	6	25.99	24.443595	146.66156999999998	49.55399534595775	Joseph Brooks	1	146.66156999999998	1182	146.66156999999998	60	60657.854394	824.8550359343124
a76a6024-17c6-4888-a9a8-8d6e0e8c93ed	2021-10-05	021000ea-9487-46b9-b855-9359c86cace7	Europe	Sports	2	381.66	298.496286	596.992572	402.9937509555779	Adam Smith	1	596.992572	1181	596.992572	55	62372.113224	936.3944649146875
ffc9e683-f57c-416b-be19-eeddd5db5494	2021-10-08	e8d5c470-7f0b-4f06-81d2-f46b470a9828	North America	Clothing	8	477.77	337.78339	2702.26712	2442.501182310746	Christina Thompson	1	2702.26712	1178	2702.26712	53	64491.182614000005	1021.7261378833904
a6fcf494-7b1a-4346-9941-8fef9e6b60c9	2021-10-09	1b8a8b76-5e9f-4a1e-a5a7-3a9f470c9c29	Europe	Beauty	5	259.51	247.105422	1235.52711	1002.369194504916	Mary Scott	1	1235.52711	1177	1235.52711	63	77562.23517100001	1033.152899764227
c8a1a22a-5662-40d8-aa41-a0624931293b	2021-10-10	92c753f1-b6d0-41a3-b63d-4a272f7fc5ab	Asia	Clothing	6	93.58	67.14365000000001	402.8619000000001	235.1285749937547	Crystal Williams	1	402.8619000000001	1176	402.8619000000001	65	72555.900913	927.0834787540324
91486ef6-6cf6-4ac6-ae8b-1851e28df119	2021-10-15	7e3d6c38-af19-422f-b749-7a37efa8123b	Australia	Home & Kitchen	8	443.06	311.869934	2494.959472	2237.250334590768	Caleb Camacho	1	2494.959472	1171	2494.959472	66	91544.242731	1177.604080808591
a3efac81-cb3c-49ba-8a1e-0047ae4dae7d	2021-10-15	15ba8564-7d68-49a5-87b8-65355088056f	Europe	Sports	5	272.9	210.02384	1050.1192	824.4763628096866	Crystal Williams	1	1050.1192	1171	1050.1192	65	72555.900913	927.0834787540324
5cb43d88-bac2-422b-bea1-fa035fc33da3	2021-10-16	231679a5-ca32-48a5-a457-358536a53406	Europe	Sports	9	444.5	390.0043	3510.0387	3244.3943340959486	Crystal Williams	1	3510.0387	1170	3510.0387	65	72555.900913	927.0834787540324
75ede199-8a76-4b85-aec7-0cbd2a0e4219	2021-10-18	c61dec50-d193-49b8-a614-bd67facbc01a	South America	Toys	9	477.26	431.156684	3880.410156	3612.83441483148	Steven Coleman	1	3880.410156	1168	3880.410156	59	68355.922945	964.8650638967956
77b165a6-55c9-4eff-9eaf-e7eb9b114954	2021-10-21	7998683a-ce42-4f6e-93c1-ee0b168d930d	South America	Books	3	439.79	351.87597900000003	1055.6279370000002	829.7333623065418	Roger Brown	1	1055.6279370000002	1165	1055.6279370000002	54	68595.667163	1076.1212096324236
501bf1a4-5760-44b5-bea9-79691eac1fe4	2021-10-21	ec5185a7-8fb8-4ced-962b-a922a31364bb	Asia	Home & Kitchen	1	352.95	340.490865	340.490865	184.64554048517027	Sandra Luna	1	340.490865	1165	340.490865	56	72688.198308	1090.9576938669472
a439a196-c83b-44d5-b34a-7bb9fb721a04	2021-10-21	4582fc67-6486-46e4-9b0a-459026be7172	South America	Toys	10	105.01	88.43942200000001	884.3942200000001	667.4873894994238	Adam Smith	1	884.3942200000001	1165	884.3942200000001	55	62372.113224	936.3944649146875
620ae236-0909-40e0-826b-d109d374463b	2021-10-22	5efd90bf-6c10-4eaf-9c17-d86f8b5ccbcb	Australia	Beauty	7	429.01	411.463491	2880.244437	2618.924298276186	Roger Brown	1	2880.244437	1164	2880.244437	54	68595.667163	1076.1212096324236
21787ddc-9450-48f8-a1dd-fda33071bef4	2021-10-27	0a5d027f-50c2-40cc-8593-63c7ff51110c	Australia	Toys	3	94.03	81.157293	243.471879	111.66596789129494	Caleb Camacho	1	243.471879	1159	243.471879	66	91544.242731	1177.604080808591
20d4cc4e-4ad3-43ec-98b6-392be7f217f6	2021-10-27	46150b76-df8b-4292-83da-06cdc0802dfc	South America	Books	6	268.92	232.669584	1396.017504	1157.6875844097312	Mary Scott	1	1396.017504	1159	1396.017504	63	77562.23517100001	1033.152899764227
7e8bcd46-de9d-4b44-b856-fe1d3cd2094d	2021-10-29	1b6ca793-ac1e-466c-bae4-e2baa3629923	Asia	Books	8	213.73	153.97109199999997	1231.7687359999998	998.744003499054	Jason Nelson	1	1231.7687359999998	1157	1231.7687359999998	70	87933.283392	1049.1629849529377
4b1faee4-0fc8-4dde-8b9f-c9937598257a	2021-11-03	cc4d4734-9ced-4e68-bdaf-fce3bb946001	Europe	Clothing	6	31.33	29.29355	175.7613	66.70117341772152	Mary Scott	1	175.7613	1152	175.7613	63	77562.23517100001	1033.152899764227
a4a942ed-e261-49cf-bc42-375ee520cc90	2021-11-07	89deef7f-98b3-44f0-9833-6c60c579d064	Asia	Home & Kitchen	7	390.97	381.19575	2668.3702500000004	2408.9197798841974	Mary Scott	1	2668.3702500000004	1148	2668.3702500000004	63	77562.23517100001	1033.152899764227
cbad1d43-bc99-485e-8a8f-f44923a8ac59	2021-11-13	a900f4d7-2388-4453-b815-31b082195e8e	Australia	Home & Kitchen	6	350.32	254.227224	1525.363344	1283.533909032659	Michelle Garza	1	1525.363344	1142	1525.363344	65	76798.491008	980.44596940906
dbb6bc11-d5bb-4d1a-9754-4f85be2c2245	2021-11-13	4f88d5e2-5c96-4349-886e-06dfd5c0d6d5	Europe	Beauty	9	214.23	207.653139	1868.878251	1619.7907980151542	Michelle Andersen	1	1868.878251	1142	1868.878251	60	66978.268402	921.082547231716
0e25327a-a793-408a-b012-f4e1b86d20ce	2021-11-14	f5bafefa-5bd1-41bc-9e38-82c05999f2fb	Australia	Sports	8	348.73	314.06623800000006	2512.5299040000004	2254.636149419554	Jason Nelson	1	2512.5299040000004	1141	2512.5299040000004	70	87933.283392	1049.1629849529377
88050e14-d143-4316-aeaf-e2d8b303f686	2021-11-14	1ae9347f-36cb-4d0d-ac60-b7dc32bce30b	South America	Beauty	9	227.66	209.310604	1883.795436	1634.4446343904272	Emily Matthews	1	1883.795436	1141	1883.795436	72	80570.187359	919.786031455556
47039da6-4a6f-4bc4-8a3f-e64e8d00a469	2021-11-15	efd87d89-5365-438a-879d-e8c1cfbafbfe	South America	Electronics	8	121.1	98.73283	789.8626399999999	579.1426954903425	Charles Smith	1	789.8626399999999	1140	789.8626399999999	70	95387.089343	1149.437576059358
bce718ab-6835-4708-abdc-68884c8c8a1c	2021-11-18	3200bd8c-0ff8-4632-8a86-aaa914a3850e	Europe	Beauty	7	432.74	424.431392	2971.019744	2708.9742198242343	Sandra Luna	1	2971.019744	1137	2971.019744	56	72688.198308	1090.9576938669472
90abaa10-55b6-43d6-b087-cce2a258e36e	2021-11-22	4537f086-eac8-436e-aa64-75e7982e6a89	Europe	Electronics	1	446.01	415.725921	415.725921	245.8060644643996	Michelle Andersen	1	415.725921	1133	415.725921	60	66978.268402	921.082547231716
d3d62e43-e641-4b6f-8ddb-aa5569376189	2021-11-23	03755245-81dd-4a25-82b5-4c8cc8f0bd2e	Asia	Books	8	16.18	11.36645	90.9316	21.855635247645097	Joseph Brooks	1	90.9316	1132	90.9316	60	60657.854394	824.8550359343124
6bbf387d-50e3-4e35-8731-75b67955687d	2021-12-01	75981f14-792d-4c97-b493-a296c72cef82	Asia	Sports	6	202.63	172.964968	1037.789808	812.7215347404034	Crystal Williams	1	1037.789808	1124	1037.789808	65	72555.900913	927.0834787540324
edfcad5b-34cc-430c-a7a7-5d569084316e	2021-12-02	a735c037-db65-4bdb-929b-7362fc58a73b	South America	Sports	6	309.69	283.521195	1701.1271699999998	1455.271121612903	Crystal Williams	1	1701.1271699999998	1123	1701.1271699999998	65	72555.900913	927.0834787540324
4faa9160-aa43-49f2-adea-39352ab06960	2021-12-02	f8eae8bc-c50e-4a96-a51c-6018e9a8d04e	Asia	Beauty	1	229.15	205.157995	205.157995	85.4555648698874	Sandra Luna	1	205.157995	1123	205.157995	56	72688.198308	1090.9576938669472
31e3e845-8b9d-4a19-96d4-d260151590b3	2021-12-02	8e93c43f-1bd8-4292-a5ef-2b07e386d800	Australia	Books	7	287.14	224.945476	1574.618332	1331.5841705553323	Johnny Marshall	1	1574.618332	1123	1574.618332	61	67804.798966	913.3835523608234
9302a98a-64e1-4fa5-9c4f-ff1a27607fc8	2021-12-03	7f9b15c2-8d78-4fbf-ba49-5dd6890d79f5	Australia	Clothing	6	386.73	358.344018	2150.064108	1896.5546862200636	Susan Edwards	1	2150.064108	1122	2150.064108	68	86058.98736700001	1063.159646603474
a4eb9125-f841-486d-94a0-a840e95e9aed	2021-12-03	71c8a06d-00df-4af6-920d-97af7c01debf	North America	Electronics	7	122.34	109.787916	768.515412	559.3443464329223	Christina Thompson	1	768.515412	1122	768.515412	53	64491.182614000005	1021.7261378833904
87daf565-d9f9-47bf-a523-83079c8a163b	2021-12-08	4e7fe0ca-04ec-487d-8003-cee1efcb7d86	North America	Electronics	1	94.99	83.230238	83.230238	18.69066138709678	Michelle Garza	1	83.230238	1117	83.230238	65	76798.491008	980.44596940906
0fade92b-4086-4717-bbc6-f16b4142ea1e	2021-12-13	fbcd71f3-78bc-4986-ae69-9e6289323b88	Europe	Electronics	3	67.25	57.297	171.891	64.33139797259246	Crystal Williams	1	171.891	1112	171.891	65	72555.900913	927.0834787540324
8a8e7148-fc0e-468b-8155-b45dd4eb6626	2021-12-15	e9f95f8e-afc2-4bd3-9941-f6236e30c68a	South America	Clothing	9	475.29	355.32680400000004	3197.941236000001	2934.2457006008217	Sandra Luna	1	3197.941236000001	1110	3197.941236000001	56	72688.198308	1090.9576938669472
b4cf5018-6341-498e-abaa-7063a2bb4d77	2021-12-18	902393a4-a0ed-4bbb-b8bb-4b9e403c0815	Europe	Electronics	2	178.45	168.77801	337.55602	182.3293024427481	Jason Nelson	1	337.55602	1107	337.55602	70	87933.283392	1049.1629849529377
6ab7e504-b5f7-4fb8-9da6-c085d75f46fe	2021-12-21	71a28f4e-bb84-4ac3-8e53-b73661a151c3	Europe	Clothing	7	259.85	254.91285	1784.3899500000002	1536.863982099211	Mary Scott	1	1784.3899500000002	1104	1784.3899500000002	63	77562.23517100001	1033.152899764227
9bc9241d-e643-4081-9467-3b86d4df54ee	2021-12-22	19803faa-cc0d-4658-b835-7003318ffebf	Asia	Books	9	278.24	249.386512	2244.478608	1989.7079426046448	Michelle Garza	1	2244.478608	1103	2244.478608	65	76798.491008	980.44596940906
d59ea421-10ed-4367-9306-f026f2cbd290	2021-12-23	d6e24819-09b9-4a53-ad29-7153cc796d3e	Asia	Electronics	7	114.22	95.807736	670.654152	469.474000812095	Christina Thompson	1	670.654152	1102	670.654152	53	64491.182614000005	1021.7261378833904
1cc0a147-2bff-41b6-b689-f5af3d9503cb	2021-12-24	575dd75c-8c0e-4163-b75a-352d6a96ab36	South America	Clothing	8	450.41	436.8076180000001	3494.4609440000004	3228.9062370671554	Christina Thompson	1	3494.4609440000004	1101	3494.4609440000004	53	64491.182614000005	1021.7261378833904
d7bc83ab-ab70-4de8-8600-c60d7e823d42	2021-12-26	98974303-7f53-473b-8133-016302e33aed	Europe	Home & Kitchen	1	291.4	267.62176	267.62176	129.04379811101904	Diane Andrews	1	267.62176	1099	267.62176	58	66389.094387	950.0340815608216
d790e0fe-2335-407b-905d-18ee089b79ed	2021-12-27	b396d262-cc04-4b91-9790-1e62b3fc4908	Asia	Electronics	10	431.06	387.048774	3870.487740000001	3602.957915220322	Diane Andrews	1	3870.487740000001	1098	3870.487740000001	58	66389.094387	950.0340815608216
ed9e3c5d-13dc-4852-8436-d978c2696ed3	2021-12-29	c5c8029c-6b0b-4e84-b696-618d763b12ef	Europe	Toys	10	375.33	271.250991	2712.50991	2452.648638528592	Mary Scott	1	2712.50991	1096	2712.50991	63	77562.23517100001	1033.152899764227
345bb543-2604-4938-969d-b3d57b782be9	2022-01-02	8dfc1cba-b066-4cfa-aba9-b04c9eca7cd6	South America	Books	3	449.6	321.77872	965.33616	743.8729100975017	Christina Thompson	1	965.33616	1092	965.33616	53	64491.182614000005	1021.7261378833904
03ac0ca0-ac7b-45b7-8a8a-54e2773e0e19	2022-01-02	3dbe13ea-fda9-4c09-aeb7-3336bd053fec	South America	Clothing	5	35.79	29.179587	145.89793500000002	49.12939019665717	Michelle Andersen	1	145.89793500000002	1092	145.89793500000002	60	66978.268402	921.082547231716
5dfaeec6-9699-408d-b464-94f2f4ec7724	2022-01-03	6ff1eb29-8e7f-4f4c-9ad5-addf45ae9a6e	South America	Sports	1	77.95	72.314215	72.314215	14.536798093640144	Caitlyn Boyd	1	72.314215	1091	72.314215	58	71709.8323	1035.5858485437743
9c2f5549-c6bb-4414-b88d-c5d2236ffb02	2022-01-04	ceafdb47-7040-4978-a75e-5205ffaa880f	North America	Sports	8	159.54	124.552878	996.423024	773.3648824764164	Adam Smith	1	996.423024	1090	996.423024	55	62372.113224	936.3944649146875
32b36af2-471d-4fef-b561-5d6e4444c79b	2022-01-04	af0a4e9b-98d2-46c7-8833-32094d993917	Asia	Electronics	8	267.13	215.520484	1724.163872	1477.8301140527765	Emily Matthews	1	1724.163872	1090	1724.163872	72	80570.187359	919.786031455556
371513ad-b2fd-46d6-801c-1a4c78b09961	2022-01-05	44d3c26e-8a56-4e58-b6b7-07d3d4b2eaf5	Australia	Beauty	4	18.44	17.173172	68.692688	13.250647644874896	Emily Matthews	1	68.692688	1089	68.692688	72	80570.187359	919.786031455556
eae17bc0-92f4-4bae-817a-59599195bb4d	2022-01-06	37ebf553-85f0-4ccf-825b-7c15eb72921a	Europe	Home & Kitchen	2	47.43	40.566879	81.133758	17.86170153895344	Bradley Howe	1	81.133758	1088	81.133758	56	64186.396558	951.6581100155678
15d44710-8e08-4bde-9a53-ac251c52c392	2022-01-08	0cec9a85-4323-4f27-8a15-3fe46d2b21c9	Asia	Electronics	5	294.67	283.855611	1419.278055	1180.277978380035	Michelle Garza	1	1419.278055	1086	1419.278055	65	76798.491008	980.44596940906
ed9018d8-7957-479c-b618-449070655b04	2022-01-10	db4fc602-2b00-405e-a9bc-75309e27c3e8	Australia	Sports	6	165.1	132.37717999999998	794.26308	583.2305641246645	Steven Coleman	1	794.26308	1084	794.26308	59	68355.922945	964.8650638967956
fcb835d2-46dd-48c2-a872-0b33ea2c13c6	2022-01-13	1dd5b076-0118-4a6a-b660-00315cf20d6f	Asia	Toys	8	9.57	9.336492	74.691936	15.4079166333836	Bradley Howe	1	74.691936	1081	74.691936	56	64186.396558	951.6581100155678
19869f31-f33f-469b-92e4-793c37263b82	2022-01-13	ad47f34e-fc8a-4f9d-82e0-ba5615dd2565	Europe	Clothing	5	76.4	67.99600000000001	339.98	184.2401923957856	Diane Andrews	1	339.98	1081	339.98	58	66389.094387	950.0340815608216
94ad5116-b54d-4e1a-9884-f2cca12c313a	2022-01-14	485de274-2233-4521-bfd1-f0267e5c2ea9	North America	Home & Kitchen	6	298.77	235.908792	1415.452752	1176.5618046742163	Adam Smith	1	1415.452752	1080	1415.452752	55	62372.113224	936.3944649146875
5b3e0fd3-2330-408f-84bf-a54d2b354677	2022-01-14	a2733f0e-8580-4cae-bf1b-0e06ca7b78b7	Australia	Electronics	4	484.7	473.93966	1895.75864	1646.1985009867833	Michelle Garza	1	1895.75864	1080	1895.75864	65	76798.491008	980.44596940906
dbecdf1c-fd09-4129-b005-25aca6171a7e	2022-01-15	55547294-b53e-4e5c-98c5-5f733a54e5fb	Australia	Sports	2	378.61	306.82554400000004	613.6510880000001	417.9216008859404	Michelle Andersen	1	613.6510880000001	1079	613.6510880000001	60	66978.268402	921.082547231716
95021db4-4b2e-4308-94b1-7385e4241c04	2022-01-15	a959cbfe-e102-4a5c-8034-bf625aa0e13d	Europe	Clothing	6	378.57	265.86971099999994	1595.2182659999996	1351.695799966354	Charles Smith	1	1595.2182659999996	1079	1595.2182659999996	70	95387.089343	1149.437576059358
726c9525-4d3d-4fdc-9665-fe08250ba9a8	2022-01-17	12607c65-790b-44af-a138-7dbdb795ddbd	South America	Toys	2	182.83	179.24653200000003	358.49306400000006	198.97848537581208	Diane Andrews	1	358.49306400000006	1077	358.49306400000006	58	66389.094387	950.0340815608216
6a7d1dbe-a9fe-47b2-bb3a-13c5d64ec2b1	2022-01-17	d5690dac-2c52-499b-ba0b-0e3ed4c7d7d4	North America	Beauty	6	441.72	425.994768	2555.968608	2297.622949392416	Caleb Camacho	1	2555.968608	1077	2555.968608	66	91544.242731	1177.604080808591
1fcc7b31-a2cf-4367-a6f3-044e0ab97ca5	2022-01-19	e4029b0f-e5c5-4142-8f85-e2c8e05ce6cb	South America	Beauty	3	179.56	167.61926	502.85778	319.98045520093103	Caitlyn Boyd	1	502.85778	1075	502.85778	58	71709.8323	1035.5858485437743
25c25972-3c23-41b7-bfab-218e062b53fd	2022-01-20	fdc56112-ae7c-4285-b941-37cf0007e444	South America	Sports	1	251.63	201.933075	201.933075	83.33030570597909	Caleb Camacho	1	201.933075	1074	201.933075	66	91544.242731	1177.604080808591
55238b6a-1094-4ea5-9490-a7c5baaba010	2022-01-20	8677edd1-69a1-46a3-b2b2-89a747ed09c2	Europe	Beauty	5	489.64	436.611988	2183.05994	1929.1005933195283	Michelle Andersen	1	2183.05994	1074	2183.05994	60	66978.268402	921.082547231716
99e12377-4796-4ad7-a5ab-6f7838573c52	2022-01-22	7081f2c5-c821-434a-97e5-b7da060acce2	North America	Toys	4	256.19	245.301925	981.2077	758.9233223098183	Susan Edwards	1	981.2077	1072	981.2077	68	86058.98736700001	1063.159646603474
e586c85f-30b4-4583-a716-7439900a48a2	2022-01-25	7f4d9682-2488-41fc-84ce-8f838aa56c3f	North America	Books	4	108.09	97.789023	391.15609200000006	225.48920283816872	Johnny Marshall	1	391.15609200000006	1069	391.15609200000006	61	67804.798966	913.3835523608234
2af508b4-08b7-40a2-981a-53c3a8a2e314	2022-01-25	91a9159c-2603-4b02-98e7-94606bc03edd	North America	Toys	5	240.12	185.73282000000003	928.6641000000002	709.1892104861391	Susan Edwards	1	928.6641000000002	1069	928.6641000000002	68	86058.98736700001	1063.159646603474
ae774a2f-968f-4ff9-b79d-3774a3cfa65b	2022-01-25	a665e396-015f-45ad-9fed-61ec78bb068b	Asia	Sports	8	337.24	294.680312	2357.442496	2101.2767099348894	Emily Matthews	1	2357.442496	1069	2357.442496	72	80570.187359	919.786031455556
71bba807-27a3-48d1-a600-538260687d1f	2022-01-26	2faacfba-8001-41a6-a561-7485f8d7dd2e	Australia	Electronics	3	33.5	29.08135	87.24405	20.318574393985884	Kristen Ramos	1	87.24405	1068	87.24405	62	73461.618973	988.8412277570784
9fddb742-f43e-4b2f-b2ab-e35345d289b1	2022-01-26	c7f0ea0e-3f1c-49e4-b80d-75f6d7ac1ecc	Australia	Electronics	10	490.17	446.152734	4461.527340000001	4191.526109070631	Mary Scott	1	4461.527340000001	1068	4461.527340000001	63	77562.23517100001	1033.152899764227
9a36cf21-3a16-403b-b803-399f3be66615	2022-02-01	3d23176a-0572-4ce8-8631-ba410d4b84c7	Asia	Electronics	3	379.77	307.006068	921.018204	701.973277132447	Bradley Howe	1	921.018204	1062	921.018204	56	64186.396558	951.6581100155678
6a220120-e82d-42e5-b308-7356fb0ebc98	2022-02-01	02bbe991-e1d2-4691-9b7a-a33741193cf8	Australia	Sports	6	351	340.4349	2042.6094	1790.6655709055922	Adam Smith	1	2042.6094	1062	2042.6094	55	62372.113224	936.3944649146875
6d332dab-5e63-4651-8e58-13d7d945c492	2022-02-02	91fcf263-2df9-4ef4-b771-313abe7fa46b	South America	Toys	9	80.13	71.411856	642.706704	444.113648968019	Diane Andrews	1	642.706704	1061	642.706704	58	66389.094387	950.0340815608216
86ca44a0-464d-46ee-ac02-56e173f02013	2022-02-02	f448e95f-667d-4783-b9e5-2c4cbcc96580	South America	Electronics	9	367.53	262.41642	2361.74778	2105.531787029877	Kristen Ramos	1	2361.74778	1061	2361.74778	62	73461.618973	988.8412277570784
48da48d8-3015-40c7-aa37-270c079f733b	2022-02-07	7dd501ff-5ea3-4983-aefe-9b45ed962140	South America	Toys	1	430.05	344.38404	344.38404	187.72478512123	Kristen Ramos	1	344.38404	1056	344.38404	62	73461.618973	988.8412277570784
3796c714-f37f-43d2-999a-8440de2fd403	2022-02-07	1b603877-227c-438d-8432-32deac9c49d0	Asia	Sports	9	353.33	281.60401	2534.43609	2276.312704012038	Diane Andrews	1	2534.43609	1056	2534.43609	58	66389.094387	950.0340815608216
378da813-e0eb-4cae-a2a0-bd531b7b60b2	2022-02-10	d23faf0d-538e-4c90-afa6-d8cba2ba1cb9	Australia	Sports	10	336.85	308.655655	3086.55655	2823.642654533297	Caitlyn Boyd	1	3086.55655	1053	3086.55655	58	71709.8323	1035.5858485437743
474fc15c-3001-4364-a9c7-f1ea50ae7645	2022-02-16	3e4afba7-d36d-43e7-8fd2-14e126bdc280	North America	Home & Kitchen	1	15.83	11.679374	11.679374	0.4556818992888711	Kristen Ramos	1	11.679374	1047	11.679374	62	73461.618973	988.8412277570784
610eb46b-3336-45ad-80ea-e6951ba36e8d	2022-02-16	4bc52f5c-863e-4715-9b68-f01ba3a95129	North America	Sports	3	298.27	215.977307	647.9319209999999	448.8439133183284	Susan Edwards	1	647.9319209999999	1047	647.9319209999999	68	86058.98736700001	1063.159646603474
d118134a-781c-4ef8-af8a-8e1cd5685c13	2022-02-18	b6cb05fc-bc21-442d-a1cd-88c833cab6dc	South America	Books	7	173.34	130.421016	912.947112	694.3661480811168	Jason Nelson	1	912.947112	1045	912.947112	70	87933.283392	1049.1629849529377
70339345-105d-47a2-a295-2922db7a9e51	2022-02-19	675ba5de-b4f8-4838-960a-338cf1618594	South America	Beauty	1	182.65	156.14748500000002	156.14748500000002	54.96982349543187	Joseph Brooks	1	156.14748500000002	1044	156.14748500000002	60	60657.854394	824.8550359343124
aae657e9-2bb0-46ba-b2a9-0917b12efb86	2022-02-22	28af2b3a-7ac9-455f-ba44-4ee63c9fa3c0	North America	Beauty	5	238.98	167.931246	839.6562299999999	625.5456042350061	Kristen Ramos	1	839.6562299999999	1041	839.6562299999999	62	73461.618973	988.8412277570784
30717fc5-ef38-4be8-b826-c1e1bc5d1592	2022-02-23	4bcbf1ee-a324-44aa-93a9-53e8113e8d7d	Australia	Clothing	9	52.51	52.499498	472.495482	293.7974441043077	Steven Coleman	1	472.495482	1040	472.495482	59	68355.922945	964.8650638967956
7af0235b-b7d6-4908-8682-113b8c1d3cfd	2022-02-27	99a41985-13dd-4b18-ab63-9b0650ce38d1	Asia	Books	10	302.52	285.306612	2853.0661199999995	2591.973259850284	Sandra Luna	1	2853.0661199999995	1036	2853.0661199999995	56	72688.198308	1090.9576938669472
49aa84c2-4b5b-4297-91b3-6453282d481c	2022-02-27	ec2fb58c-ef2c-4b94-aea4-87e25d6dc57d	Asia	Books	9	400.93	400.36869800000005	3603.3182820000006	3337.1530509080294	Johnny Marshall	1	3603.3182820000006	1036	3603.3182820000006	61	67804.798966	913.3835523608234
272f9c2c-ce4c-450f-a300-64fc54523559	2022-03-01	28a1aba1-177c-4b09-9d24-81252f011f82	Europe	Toys	8	309.48	291.62300400000004	2332.9840320000003	2077.1098496952523	Jason Nelson	1	2332.9840320000003	1034	2332.9840320000003	70	87933.283392	1049.1629849529377
63396ff1-bff2-4d6b-8bc5-53c923e326cb	2022-03-01	8dcb29f3-d5fb-4acb-940c-bfd0ee47c102	Australia	Toys	4	260.92	239.13318	956.53272	735.5377057911883	Caleb Camacho	1	956.53272	1034	956.53272	66	91544.242731	1177.604080808591
9cab80c7-2451-4e70-b7d8-26398ea66f8e	2022-03-01	9c5fe264-aac9-41cf-b3eb-9b971118dfe3	North America	Beauty	7	445.64	318.231524	2227.620668	1973.067449776005	Steven Coleman	1	2227.620668	1034	2227.620668	59	68355.922945	964.8650638967956
29b10c97-56a4-4c95-a2bd-f90ff0684e57	2022-03-03	e609f42a-d6a7-4e74-a042-283697b9f5ed	Europe	Electronics	4	330.12	263.699856	1054.799424	828.9419823486788	Mary Scott	1	1054.799424	1032	1054.799424	63	77562.23517100001	1033.152899764227
737d12d0-18a4-433d-afd4-83e2aa2eb30f	2022-03-04	b82602ba-b24a-4071-984b-4dba0890ef51	Australia	Clothing	3	393.86	313.039928	939.119784	719.0668786880052	Caitlyn Boyd	1	939.119784	1031	939.119784	58	71709.8323	1035.5858485437743
8fe8bf01-0ced-4d8d-9014-71a84d8cc4cf	2022-03-06	b3b9b092-e544-4708-87cd-1d7f55b991f4	Europe	Clothing	2	177.23	153.02038199999998	306.040764	157.8298269086154	Emily Matthews	1	306.040764	1029	306.040764	72	80570.187359	919.786031455556
f4d445ab-380f-4270-bc1c-69208fc504a5	2022-03-06	3d52ccb0-08b6-4d73-92d1-9c9b9267bbfc	North America	Books	8	125.48	89.25392400000001	714.0313920000001	509.11493569349983	Caitlyn Boyd	1	714.0313920000001	1029	714.0313920000001	58	71709.8323	1035.5858485437743
81c00816-784a-4631-a4d1-e2aa38db0a1f	2022-03-11	16518886-ed35-44d7-8f83-bb0c18942b0c	Asia	Books	1	318.28	259.87562	259.87562	123.40782605996952	Sandra Luna	1	259.87562	1024	259.87562	56	72688.198308	1090.9576938669472
5d491933-3168-4b51-ba76-f66236596de3	2022-03-11	1565af89-0fbe-4ff1-9940-59e460fb7cd8	South America	Beauty	4	162.46	122.16992	488.67968	307.7140156539772	Michelle Garza	1	488.67968	1024	488.67968	65	76798.491008	980.44596940906
6dd4d317-a1ac-41bc-894d-7b0d9c910187	2022-03-12	7808c49a-47c8-434c-a8f0-7f947cef4609	Asia	Home & Kitchen	2	131.38	130.407788	260.815576	124.0839503119266	Jason Nelson	1	260.815576	1023	260.815576	70	87933.283392	1049.1629849529377
9b226dbf-cdf1-4694-9e66-ffb314d99cbb	2022-03-13	e0a60e89-5003-4d60-8bca-dc0fdb28c116	South America	Sports	5	265.97	261.501704	1307.50852	1071.9001733020991	Crystal Williams	1	1307.50852	1022	1307.50852	65	72555.900913	927.0834787540324
885a0e04-10b4-415b-89fa-175c3b2968bb	2022-03-18	2eed7d26-ee66-41ba-b9f2-a19021f7265f	Asia	Books	1	32.82	24.939918	24.939918	1.991888923813029	Emily Matthews	1	24.939918	1017	24.939918	72	80570.187359	919.786031455556
b401cce7-bc5a-4482-8032-c2c60bfe2fd8	2022-03-20	bf5f047b-afe4-4c9e-a282-99b0bec54af3	Australia	Clothing	5	32.95	27.625280000000004	138.12640000000002	44.8355719573146	Sandra Luna	1	138.12640000000002	1015	138.12640000000002	56	72688.198308	1090.9576938669472
23ad635e-34e3-4d0b-a92f-e8ca7caa38db	2022-03-22	7962b8d6-1495-4504-9d8b-fda5801a3c40	Asia	Electronics	10	30.88	30.126528	301.26528	154.1846375159889	Adam Smith	1	301.26528	1013	301.26528	55	62372.113224	936.3944649146875
984e727d-2b9f-4821-b7a1-e45b0b2d5d2a	2022-03-25	692c8209-fdea-4856-a063-1b1f5314e65a	South America	Home & Kitchen	1	469.94	387.982464	387.982464	222.88354314893616	Charles Smith	1	387.982464	1010	387.982464	70	95387.089343	1149.437576059358
e93b46e4-8312-44da-98e5-8c6c9cf78fb0	2022-03-25	97af76a0-3c40-4d60-b122-e8e44501b963	Australia	Sports	9	382.25	284.355775	2559.201975	2300.8246087469333	Susan Edwards	1	2559.201975	1010	2559.201975	68	86058.98736700001	1063.159646603474
b6ebd6ea-1260-4ad4-b5dd-4e4e3654bff7	2022-03-26	8539ecd2-55f0-458f-8e5a-1900cb42dddb	Australia	Beauty	10	15.79	15.30051	153.0051	53.15838895849648	Johnny Marshall	1	153.0051	1009	153.0051	61	67804.798966	913.3835523608234
b5a25ac1-32af-4f80-8c38-f158f9298045	2022-03-26	68d8406a-8730-49f3-a819-04f0d6d22d1d	South America	Books	9	110.85	83.00447999999999	747.0403199999998	539.494529034839	Christina Thompson	1	747.0403199999998	1009	747.0403199999998	53	64491.182614000005	1021.7261378833904
b1907ec3-6352-44f1-9193-6d5a15bfb449	2022-03-28	0b6762bd-ebf3-44f8-8938-122fc2bde23f	Asia	Electronics	5	240.93	202.18845600000003	1010.9422800000002	787.1636630352401	Michelle Garza	1	1010.9422800000002	1007	1010.9422800000002	65	76798.491008	980.44596940906
963b3e62-7bbf-4f1b-805e-ab91f047162d	2022-03-28	3a25ff5c-686b-4f0f-accf-8654d39baeef	North America	Toys	3	28.78	24.451488	73.35446400000001	14.914005108986608	Michelle Andersen	1	73.35446400000001	1007	73.35446400000001	60	66978.268402	921.082547231716
4b275710-38d4-423d-aa6a-de6997013280	2022-03-28	988d41e1-cdeb-4b00-9424-904864140da2	North America	Toys	5	285.22	254.216586	1271.08293	1036.6868744567382	Bradley Howe	1	1271.08293	1007	1271.08293	56	64186.396558	951.6581100155678
52f4c96e-2be8-46e1-8640-ac2adcaaec23	2022-03-29	05623563-82c2-4e43-b34b-b733df4e3879	Asia	Beauty	5	327.53	260.55011499999995	1302.7505749999998	1067.299540299114	Bradley Howe	1	1302.7505749999998	1006	1302.7505749999998	56	64186.396558	951.6581100155678
51f3a1f6-e947-47e8-a867-a634e2a9bca8	2022-03-29	34d9e37c-ce44-447f-9cc8-afa21cc23a9c	Australia	Electronics	10	355.39	279.478696	2794.7869599999995	2534.1910440684032	Mary Scott	1	2794.7869599999995	1006	2794.7869599999995	63	77562.23517100001	1033.152899764227
59c07ad6-8b45-4721-8ccc-97cd3d892022	2022-03-30	3f9f0ebd-fe66-4f9b-bf89-f456f68e0886	Europe	Toys	7	300.3	264.11385	1848.79695	1600.0687177922778	Caitlyn Boyd	1	1848.79695	1005	1848.79695	58	71709.8323	1035.5858485437743
7fbcd10e-2f6d-4c7f-9475-14f322ec1c0f	2022-03-31	e36a23d7-6a45-4f3b-90f0-0a7b1f1532c4	Europe	Electronics	1	339.85	261.61653	261.61653	124.66603531330156	Michelle Andersen	1	261.61653	1004	261.61653	60	66978.268402	921.082547231716
0c02b71e-6bc6-485b-b983-0f514cdf6f9d	2022-03-31	ba751491-7ca6-4088-870e-d2adbef01cc0	North America	Home & Kitchen	1	409.73	300.086252	300.086252	153.28738104803836	Mary Scott	1	300.086252	1004	300.086252	63	77562.23517100001	1033.152899764227
5d2ce773-d5dd-47b6-b800-5b1e91ade2e2	2022-04-01	a8544072-02af-4c2b-acc7-dd2cbfedfe27	Europe	Home & Kitchen	1	52.82	37.42297	37.42297	4.311157931339579	Kristen Ramos	1	37.42297	1003	37.42297	62	73461.618973	988.8412277570784
487e0460-1d88-40cf-a29f-36a433eb6704	2022-04-06	f79f5c26-4767-47c5-a513-acf0d3093597	North America	Electronics	7	158.43	131.069139	917.483973	698.639403540979	Bradley Howe	1	917.483973	998	917.483973	56	64186.396558	951.6581100155678
2f305950-f9ff-4e0a-9497-085ec1f048c4	2022-04-07	86cc697d-da69-481e-b1e9-d1caa811a625	South America	Toys	7	82.22	65.595116	459.165812	282.4072132395581	Adam Smith	1	459.165812	997	459.165812	55	62372.113224	936.3944649146875
844af16e-015c-4ae7-91bd-b6ee9d98eaf0	2022-04-08	af63f155-6d0d-4884-b08c-e59cdab93c34	Europe	Books	8	426.71	299.806446	2398.451568	2141.8091659883366	Joseph Brooks	1	2398.451568	996	2398.451568	60	60657.854394	824.8550359343124
cc3fa6a3-b437-4fe6-9690-8766fc6e8986	2022-04-08	9398d29b-e2f5-4b2d-a052-4e56595c8798	South America	Toys	2	16.05	11.775885	23.55177	1.7828726897125442	Michelle Garza	1	23.55177	996	23.55177	65	76798.491008	980.44596940906
6ff43114-8f30-4d37-b3cb-f33b66d4bbd2	2022-04-09	25f7449b-2f79-4ce2-8aa3-6d02ff563e61	North America	Books	6	11.27	10.269224	61.61534399999999	10.878071272727269	Adam Smith	1	61.61534399999999	995	61.61534399999999	55	62372.113224	936.3944649146875
98437323-ff48-422d-9c7e-bb60ab820ee4	2022-04-12	f04a5a0e-5f0a-4ec8-a446-c29ca9ac2374	South America	Sports	7	117.58	109.161272	764.1289039999999	555.2820405475019	Mary Scott	1	764.1289039999999	992	764.1289039999999	63	77562.23517100001	1033.152899764227
e45e611c-4824-48ca-aaf8-d7e0ac12e32a	2022-04-13	d8d17379-c538-427e-a5c8-63b77298c7de	South America	Beauty	6	184.9	144.01861000000002	864.1116600000001	648.4449866778148	Jason Nelson	1	864.1116600000001	991	864.1116600000001	70	87933.283392	1049.1629849529377
4209ca5e-702b-4085-bcbb-ffb213f5d019	2022-04-14	11af7761-d009-4015-be23-6b6fa2f70d77	North America	Home & Kitchen	8	487.47	362.238957	2897.911656	2636.447515393327	Mary Scott	1	2897.911656	990	2897.911656	63	77562.23517100001	1033.152899764227
a1c92295-116e-496d-b282-56d1ebcfc6ac	2022-04-16	8faa7e94-4766-43c4-bc98-bff5c16ee283	South America	Home & Kitchen	5	30.88	21.949504	109.74751999999998	30.32967500398001	Johnny Marshall	1	109.74751999999998	988	109.74751999999998	61	67804.798966	913.3835523608234
870447d1-ca01-42c4-b0f9-b144689e7bfd	2022-04-17	c6d877a0-310d-416a-8404-f385c18892c0	South America	Beauty	3	442.07	348.395367	1045.186101	819.7750198664596	Susan Edwards	1	1045.186101	987	1045.186101	68	86058.98736700001	1063.159646603474
2583d587-9262-4b73-8db0-79d742384352	2022-04-18	5f2cb3f7-3139-4c6c-acf8-a6d24125e834	Europe	Home & Kitchen	4	120.27	100.485585	401.94234	234.3686136596348	Bradley Howe	1	401.94234	986	401.94234	56	64186.396558	951.6581100155678
e2954ad4-ce55-4089-8057-5df53ebd316f	2022-04-18	aa8b54ad-5f92-4408-b343-2b035fec37ed	Europe	Home & Kitchen	2	98.78	77.650958	155.301916	54.48270280862114	Emily Matthews	1	155.301916	986	155.301916	72	80570.187359	919.786031455556
1991a06f-1fd1-483d-8460-384f3d53c20b	2022-04-18	72151ca4-7d67-48b0-9494-627ba64ac0a8	Europe	Home & Kitchen	7	201.19	147.633222	1033.432554	808.5728847295633	Sandra Luna	1	1033.432554	986	1033.432554	56	72688.198308	1090.9576938669472
f4ca7f1f-a31f-41b1-a33e-a817b89bc007	2022-04-20	e883ace5-f9c4-4db5-b41b-c62d0f1eef4c	Asia	Books	2	239.64	203.909676	407.819352	239.22929329805703	Michelle Garza	1	407.819352	984	407.819352	65	76798.491008	980.44596940906
9f2a8659-489b-4858-b3ab-b3de497a9f64	2022-04-21	4a1a82dc-1841-4516-b685-6433f7a782f9	North America	Toys	1	213.87	199.433775	199.433775	81.69732361562075	Emily Matthews	1	199.433775	983	199.433775	72	80570.187359	919.786031455556
b4097d8e-8665-40bc-8d2a-68dc4ce63b33	2022-04-21	b734d7f6-0047-4cc3-b89b-3efc3286931b	Australia	Electronics	5	387.63	341.967186	1709.8359299999995	1463.798671204403	Michelle Garza	1	1709.8359299999995	983	1709.8359299999995	65	76798.491008	980.44596940906
caf4a7ec-7541-4f78-986e-66740b9f40b5	2022-04-21	3b24725d-1df9-4b9e-b63a-206695ad435a	North America	Clothing	8	387.22	279.57284	2236.58272	1981.913360037348	Sandra Luna	1	2236.58272	983	2236.58272	56	72688.198308	1090.9576938669472
2e3c67d8-5090-4edf-a727-5cbee73ee85e	2022-04-22	ed0a4910-e4a7-4f1e-b989-26faa434270f	North America	Beauty	6	370.21	368.618097	2211.708582	1957.363493967984	Roger Brown	1	2211.708582	982	2211.708582	54	68595.667163	1076.1212096324236
42cf1168-e78c-4875-9973-fbffe87de807	2022-04-22	314c069e-e838-445b-baed-6b5f63cedf25	Australia	Clothing	6	22.1	20.27896	121.67376000000002	36.19268651398062	Caitlyn Boyd	1	121.67376000000002	982	121.67376000000002	58	71709.8323	1035.5858485437743
250db69c-185e-4384-80ae-dae4cd76cdad	2022-04-22	0636750c-dea2-46f1-a806-62e6c870f13a	Australia	Clothing	10	438.97	349.156738	3491.5673800000004	3226.0307744528527	Mary Scott	1	3491.5673800000004	982	3491.5673800000004	63	77562.23517100001	1033.152899764227
1bc2c374-2581-43c6-ad70-6fbc3de9bcb0	2022-04-24	67c49cc5-1d5a-4c5d-bce0-ea2f2b70f926	South America	Home & Kitchen	4	47.27	33.81695800000001	135.26783200000003	43.29269635030938	Diane Andrews	1	135.26783200000003	980	135.26783200000003	58	66389.094387	950.0340815608216
336e0dbe-92cd-4340-bece-831047f865a6	2022-04-26	1bff6fa3-227d-4d4f-9ee0-d3e69beb41a0	South America	Toys	4	283.71	224.216013	896.8640519999999	679.2155815944863	Charles Smith	1	896.8640519999999	978	896.8640519999999	70	95387.089343	1149.437576059358
e6a86bba-1c91-465f-b478-8b44f6ba4801	2022-04-27	a30e77f6-4636-46a7-93ca-a55eb2201a86	Europe	Home & Kitchen	8	486.97	448.596764	3588.774112	3322.68867518166	Susan Edwards	1	3588.774112	977	3588.774112	68	86058.98736700001	1063.159646603474
7f576789-2b92-42f7-b1ed-8a5dcd3d156d	2022-04-28	d58e3df5-8fe6-4900-b9c3-751152373512	South America	Toys	8	378.34	356.01793999999995	2848.14352	2587.0902377503617	Kristen Ramos	1	2848.14352	976	2848.14352	62	73461.618973	988.8412277570784
067cec7b-9a15-499d-8928-5d830e3cb4f4	2022-04-29	21996da1-8e87-49b8-bc1b-3bb6a03a9e24	South America	Clothing	6	50.86	49.761424000000005	298.56854400000003	152.1324539514444	Bradley Howe	1	298.56854400000003	975	298.56854400000003	56	64186.396558	951.6581100155678
45e257bd-ac50-4d98-b149-e4b789a90d11	2022-05-04	0e8860f8-c714-499c-8943-c8a1fd517fbb	Europe	Beauty	1	67.41	63.608076	63.608076	11.525806287398671	Emily Matthews	1	63.608076	970	63.608076	72	80570.187359	919.786031455556
82ace7a6-0840-4265-848a-5c8a8bff41ee	2022-05-04	4532aeb5-7f4b-4cd9-acf5-6febee14188c	Europe	Sports	2	376.18	309.069488	618.138976	421.9542051481528	Charles Smith	1	618.138976	970	618.138976	70	95387.089343	1149.437576059358
0a222d65-1194-4515-9c5a-4cf84fc8efb7	2022-05-05	12b60fdd-0987-4b71-af24-9101690d22ad	Asia	Toys	5	395.63	381.980765	1909.903825	1660.099515985665	Susan Edwards	1	1909.903825	969	1909.903825	68	86058.98736700001	1063.159646603474
0f0be7d2-83ce-4e79-a7ce-27aa2040f7bf	2022-05-06	dbd89dff-b1e7-4195-b243-6db058011674	Europe	Toys	3	246.28	227.390324	682.170972	479.9623604277923	Crystal Williams	1	682.170972	968	682.170972	65	72555.900913	927.0834787540324
577626a7-751a-483b-a039-8d558a576eda	2022-05-08	3cdded0b-0d65-45ab-bdd5-590bbcccffdf	Australia	Toys	10	440.27	313.64834799999994	3136.4834799999994	2873.212108866412	Steven Coleman	1	3136.4834799999994	966	3136.4834799999994	59	68355.922945	964.8650638967956
60fbf8d3-79a5-43ff-bfc1-ed7d0acd2412	2022-05-14	df75fec3-a3b4-489e-b800-7ab442f00572	Asia	Beauty	5	99.17	77.34268300000001	386.71341500000005	221.84582674965895	Joseph Brooks	1	386.71341500000005	960	386.71341500000005	60	60657.854394	824.8550359343124
38602e21-fcb4-47e5-84cd-249b6a5de68d	2022-05-14	88b7ed10-9b60-4e3e-98dc-0980eb6b1320	North America	Home & Kitchen	6	306.67	241.073287	1446.439722	1206.685085500746	Joseph Brooks	1	1446.439722	960	1446.439722	60	60657.854394	824.8550359343124
5828ccd1-0a73-4e2d-a6ce-424fb0eac5ad	2022-05-16	88d2f16f-030c-4b4e-b7e5-c58398e23bb2	Australia	Home & Kitchen	6	232.59	205.84215	1235.0529	1001.9096787971458	Emily Matthews	1	1235.0529	958	1235.0529	72	80570.187359	919.786031455556
701c9c88-24c8-4363-8383-f94d84c7846e	2022-05-18	73eec104-d198-4640-807e-3135508482a0	North America	Home & Kitchen	8	48.41	42.237725	337.9018	182.5946344900492	Jason Nelson	1	337.9018	956	337.9018	70	87933.283392	1049.1629849529377
eb0f943d-c7ad-45d0-9c61-e905550c1cf7	2022-05-18	d8e8d853-edfa-475e-8797-cc7a92a27487	Europe	Beauty	8	314.4	221.30616	1770.4492799999998	1523.1936406502427	Mary Scott	1	1770.4492799999998	956	1770.4492799999998	63	77562.23517100001	1033.152899764227
7158d51b-63e8-4965-afd7-5941231652b7	2022-05-19	4b5ea003-e800-41e5-bee0-aacd8edfd39c	North America	Electronics	10	22.79	21.541108	215.41108000000003	92.2838550785939	Susan Edwards	1	215.41108000000003	955	215.41108000000003	68	86058.98736700001	1063.159646603474
fb9e0d42-1ce9-4fd7-a34b-0aea81042208	2022-05-19	4ccf34a6-2465-4fe0-bbcc-21cc6b42a709	North America	Clothing	5	444.12	380.433192	1902.16596	1652.4952865255227	Emily Matthews	1	1902.16596	955	1902.16596	72	80570.187359	919.786031455556
873e4913-040d-417b-b680-27b1009d271e	2022-05-22	45b2fc58-4c60-430e-aa8b-bc8fcd5fb9ea	Asia	Home & Kitchen	1	435.14	419.69253	419.69253	249.10661364833555	Caitlyn Boyd	1	419.69253	952	419.69253	58	71709.8323	1035.5858485437743
9254d920-5a1d-4964-801a-b27487f608cf	2022-05-25	a50ae0f0-846b-41be-852a-2915cd8b99fc	North America	Clothing	8	331.23	317.550201	2540.401608	2282.2149697903533	Roger Brown	1	2540.401608	949	2540.401608	54	68595.667163	1076.1212096324236
8126e119-1748-4130-8d1f-dd9132490932	2022-05-27	f114c095-7349-478f-aec1-943c54d20542	Australia	Beauty	8	190.06	156.970554	1255.764432	1021.8945312643634	Joseph Brooks	1	1255.764432	947	1255.764432	60	60657.854394	824.8550359343124
bb46b8b7-cfab-4e80-a3f0-b5b02ebc8591	2022-05-28	8dd1a09d-de3f-40de-99a6-d807e61d28f2	Europe	Beauty	1	316.46	247.851472	247.851472	114.7697108316151	Kristen Ramos	1	247.851472	946	247.851472	62	73461.618973	988.8412277570784
41903ef0-cccd-43aa-9239-843797217fcb	2022-05-28	26c74811-9818-454d-814f-21f5e4784196	North America	Sports	10	361.16	273.109192	2731.09192	2471.0597460290014	Roger Brown	1	2731.09192	946	2731.09192	54	68595.667163	1076.1212096324236
41b723a5-d53d-486e-b602-d19e5d347ed4	2022-05-28	af5e22b8-e496-4192-b865-79ef4df9c041	North America	Beauty	6	430.21	319.990198	1919.941188	1669.9651202960742	Michelle Garza	1	1919.941188	946	1919.941188	65	76798.491008	980.44596940906
3f54707a-f456-424c-b7df-95db0bfeb163	2022-05-31	20b8ad2c-bf28-4643-8b82-1bc364c2dda4	South America	Electronics	1	373.27	372.598114	372.598114	210.3520377970825	Mary Scott	1	372.598114	943	372.598114	63	77562.23517100001	1033.152899764227
3cdf4cdc-c074-4839-8743-1ac07f913418	2022-06-02	64c8b0fd-303b-421f-acb0-c06d374c9440	South America	Clothing	4	450.56	318.09536	1272.38144	1037.9404767217584	Bradley Howe	1	1272.38144	941	1272.38144	56	64186.396558	951.6581100155678
567bfbba-97b5-4861-bd3d-30e5b59a0610	2022-06-02	1b89302b-5323-441a-a97f-ae6f77f0cb66	Asia	Toys	1	472.13	353.71979600000003	353.71979600000003	195.15793657737132	Adam Smith	1	353.71979600000003	941	353.71979600000003	55	62372.113224	936.3944649146875
d8ed7f6e-fc1b-4ebd-ba86-e82249a6a0ba	2022-06-03	8984c4ff-41da-4d2f-9abd-4c2cba0e380b	Australia	Books	4	455.52	447.730608	1790.9224319999998	1543.2701237971123	Sandra Luna	1	1790.9224319999998	940	1790.9224319999998	56	72688.198308	1090.9576938669472
50d76e56-d83f-448a-9077-9565569b1926	2022-06-05	84b2a2f5-52fa-4fd8-8cf4-037d0b011295	North America	Toys	9	381.6	361.10808	3249.97272	2985.9276190933024	Caleb Camacho	1	3249.97272	938	3249.97272	66	91544.242731	1177.604080808591
17ceb443-1cee-41ba-bd08-2099f0777ef4	2022-06-08	23a7eacf-4b21-4bd0-8d67-6fc1b83c63c0	Australia	Books	7	139.89	102.063744	714.446208	509.4989308915663	Adam Smith	1	714.446208	935	714.446208	55	62372.113224	936.3944649146875
7c73b885-1d90-45df-bf48-28c00beee4ae	2022-06-09	405f9787-e595-453f-a6cc-e441617c4e62	Australia	Electronics	10	297.3	214.17492	2141.7492	1888.3567269453283	Emily Matthews	1	2141.7492	934	2141.7492	72	80570.187359	919.786031455556
5ad6546a-bafd-40d3-9c21-d6336aeaa1c6	2022-06-11	3343c4d8-980f-4b4d-96a1-8e442034d6a7	Australia	Electronics	8	408.86	291.31275	2330.502	2074.6587223984807	Bradley Howe	1	2330.502	932	2330.502	56	64186.396558	951.6581100155678
c2c12a7b-0f96-4183-9dbc-7482aae2f1b7	2022-06-14	3d3686e2-9fc0-4a61-ba85-12c948b7b76e	Asia	Clothing	1	470.24	457.120304	457.120304	280.66685537805915	Jason Nelson	1	457.120304	929	457.120304	70	87933.283392	1049.1629849529377
057fd123-a7f5-48dd-97a9-38d294756489	2022-06-14	8dd7e03e-f56f-4b88-86a2-b8ef054004ff	South America	Books	1	271.41	210.749865	210.749865	89.1610661769457	Michelle Andersen	1	210.749865	929	210.749865	60	66978.268402	921.082547231716
06b257a2-9b47-4511-a2d5-56e0e5cb2b31	2022-06-15	bdd9eb3f-9104-4787-840e-b73127c2ff1a	Asia	Clothing	3	167.95	121.9317	365.7951	204.85040623020063	Michelle Andersen	1	365.7951	928	365.7951	60	66978.268402	921.082547231716
22a9ad8d-0c9f-40dc-8434-5613e4038ab7	2022-06-15	31fa2150-d479-4c5f-b7ff-6a711bc36d74	South America	Home & Kitchen	5	374.57	301.865963	1509.329815	1267.906574493266	Susan Edwards	1	1509.329815	928	1509.329815	68	86058.98736700001	1063.159646603474
87ee7ce4-b94f-40cf-bdb7-4b3c7e188d4d	2022-06-18	c55535af-812e-4eee-be4f-6a5c0f0e2798	Asia	Clothing	2	104.67	102.608001	205.216002	85.49369758368823	Mary Scott	1	205.216002	925	205.216002	63	77562.23517100001	1033.152899764227
0d895c24-b3f2-4913-9786-ea43dc783a6a	2022-06-19	fafb49d8-f5b5-4d18-97a3-c2daf56b9357	Asia	Books	5	470.15	389.66032	1948.3016	1697.851476593994	Crystal Williams	1	1948.3016	924	1948.3016	65	72555.900913	927.0834787540324
2f30158d-5553-41a6-bb18-d3487222d253	2022-06-20	e9d492d9-ebf2-46e1-8f87-8c30b3728454	Asia	Clothing	6	72.26	70.446274	422.677644	251.601574869794	Christina Thompson	1	422.677644	923	422.677644	53	64491.182614000005	1021.7261378833904
6cf16c64-8c96-489d-a9e7-6f7ee11c79d4	2022-06-23	68c9d1dd-b487-4b73-b9a2-386c61309465	South America	Toys	3	327.52	299.648048	898.944144	681.1713917530949	Joseph Brooks	1	898.944144	920	898.944144	60	60657.854394	824.8550359343124
4e8ca304-cbeb-40e7-a936-005d49643f50	2022-06-23	edca868c-4986-411a-a6f4-3c3b198206ac	Australia	Books	2	125.51	118.330828	236.661656	106.8773642533589	Roger Brown	1	236.661656	920	236.661656	54	68595.667163	1076.1212096324236
12e82cf4-f28c-4440-9cdf-d52aa0cd4e46	2022-06-29	90963ffd-0855-43ea-9cf6-761cdcb1a620	South America	Electronics	2	456.44	369.48818	738.97636	532.0555300501218	Michelle Andersen	1	738.97636	914	738.97636	60	66978.268402	921.082547231716
497c23b4-0d91-463b-b928-1796c558e722	2022-06-30	eefa521f-8cff-4e73-97dd-e48708a40683	North America	Clothing	9	200.65	181.327405	1631.946645	1387.5847252287972	Crystal Williams	1	1631.946645	913	1631.946645	65	72555.900913	927.0834787540324
156e3a99-2de3-46c9-b843-9b818f5b5b67	2022-07-03	5006184a-fd90-4d40-ba1f-d642881288b5	Australia	Clothing	7	239.39	171.355362	1199.487534	967.6442624535244	Adam Smith	1	1199.487534	910	1199.487534	55	62372.113224	936.3944649146875
1e8b3d5e-c470-45f9-92bd-7387735dbce7	2022-07-05	10d22c3f-f1fd-4c82-807f-d71fb8c84be0	Australia	Electronics	9	280.62	237.460644	2137.145796	1883.8184136167276	Jason Nelson	1	2137.145796	908	2137.145796	70	87933.283392	1049.1629849529377
80c09ab2-beb9-4315-8b8e-f6a9b8863ae8	2022-07-06	a1b3fb80-fb91-4414-8954-bf871257c360	South America	Beauty	9	21.84	18.71688	168.45192	62.24681313410253	Crystal Williams	1	168.45192	907	168.45192	65	72555.900913	927.0834787540324
f553ff98-61f8-4c36-aba4-72fa7b97c9d1	2022-07-06	b9652d21-8f81-4f19-bd15-fe90629fe0c5	South America	Books	9	215.69	187.154213	1684.387917	1438.8825289313793	Jason Nelson	1	1684.387917	907	1684.387917	70	87933.283392	1049.1629849529377
f6ae995b-3efb-41d4-b214-a90d5cdd05e8	2022-07-10	aff1cf95-daf8-4ad9-9cac-3048c06914e7	North America	Home & Kitchen	2	356.25	257.746875	515.49375	330.9736691036976	Caitlyn Boyd	1	515.49375	903	515.49375	58	71709.8323	1035.5858485437743
4c030524-3a90-481b-bd66-6b16a0de8a6e	2022-07-11	b5a9d152-5363-47db-9521-6134f36593bd	South America	Books	10	426.95	329.09306	3290.9306	3026.617931839465	Roger Brown	1	3290.9306	902	3290.9306	54	68595.667163	1076.1212096324236
32c8b3e2-272a-4799-96f8-9c7c434e9b92	2022-07-12	2d1d9653-2be0-47d3-9968-f2444df4dc27	Australia	Electronics	8	87.15	75.89022000000001	607.1217600000001	412.0625600000001	Sandra Luna	1	607.1217600000001	901	607.1217600000001	56	72688.198308	1090.9576938669472
2f67f78f-6c0d-44c0-a31b-40feb2a1c848	2022-07-13	ffb3f608-aba0-4b5d-b458-34696c1be4f1	Europe	Sports	9	402.04	348.44806800000003	3136.0326120000004	2872.765938729349	Jason Nelson	1	3136.0326120000004	900	3136.0326120000004	70	87933.283392	1049.1629849529377
897ca44a-fb1f-4bb9-8afa-e65a8f199ff6	2022-07-13	87f787d2-349a-442b-a71d-71cf1b432977	North America	Books	4	425.1	324.22377	1296.89508	1061.6349341523055	Susan Edwards	1	1296.89508	900	1296.89508	68	86058.98736700001	1063.159646603474
17c18464-60b9-4dda-9fca-0b473bc01a7d	2022-07-15	c93228c3-759a-4b76-a523-a60ec9685426	South America	Clothing	3	230.42	197.93078	593.79234	400.1286173555983	Michelle Garza	1	593.79234	898	593.79234	65	76798.491008	980.44596940906
5ce8505e-dc00-41f8-af24-c5a77c97f3d6	2022-07-20	9781a7b6-90df-44e4-ba07-58e4c58e2eac	North America	Electronics	7	234.19	209.36586	1465.56102	1225.2854203606853	Joseph Brooks	1	1465.56102	893	1465.56102	60	60657.854394	824.8550359343124
4e40b590-e80c-4bd2-be85-273125b92dcf	2022-07-21	e335d930-5c94-4839-9bc7-4fd80efcc739	Europe	Sports	7	159.57	150.203241	1051.422687	825.7228507866266	Caitlyn Boyd	1	1051.422687	892	1051.422687	58	71709.8323	1035.5858485437743
3c490c04-cd25-4817-8f92-e810af41123c	2022-07-21	be037267-aae8-4141-ac37-a82cc5bb02aa	Australia	Electronics	2	223.84	208.39504	416.7900800000001	246.6855660827688	Jason Nelson	1	416.7900800000001	892	416.7900800000001	70	87933.283392	1049.1629849529377
07e65b91-90dc-4a06-828f-a72c3b9d71a4	2022-07-22	5abbc265-eab0-4a6e-a523-f3c4650bb013	North America	Home & Kitchen	5	99.35	92.9916	464.958	287.3439729543892	Kristen Ramos	1	464.958	891	464.958	62	73461.618973	988.8412277570784
91e5f0d2-8c48-4411-af54-2f984ca8dcc2	2022-07-27	bcf8873f-f4a9-4e86-9f6a-c98faf1390bf	Asia	Clothing	8	176.76	157.722948	1261.783584	1027.7038155227071	Susan Edwards	1	1261.783584	886	1261.783584	68	86058.98736700001	1063.159646603474
51c8017e-9b7c-421e-9b5e-b9c5a5447f0d	2022-07-30	5333c18e-b6f7-4b4b-84f5-6061141630a3	North America	Clothing	5	177.15	140.76339	703.8169499999999	499.7528879530298	Emily Matthews	1	703.8169499999999	883	703.8169499999999	72	80570.187359	919.786031455556
f28dc480-5e0f-46e8-bd3e-7a959d4e7da2	2022-07-30	84d32142-5b5a-439d-a621-e338c98b2523	Asia	Home & Kitchen	2	135.88	105.157532	210.315064	88.87201976856451	Charles Smith	1	210.315064	883	210.315064	70	95387.089343	1149.437576059358
007b4d07-ca63-49f7-a511-e6f61567e244	2022-07-31	9c977091-4867-4bf4-889f-794219e09e71	Asia	Home & Kitchen	10	204.15	157.338405	1573.38405	1330.375362204615	Charles Smith	1	1573.38405	882	1573.38405	70	95387.089343	1149.437576059358
4d9d64cf-b0ba-4c37-805f-2633f43c670c	2022-08-01	4a2f2512-83e3-4aa0-b0d0-7e495d937166	Europe	Toys	6	478.9	466.83172	2800.99032	2540.340944406767	Emily Matthews	1	2800.99032	881	2800.99032	72	80570.187359	919.786031455556
7b234077-ccc0-4862-9d4b-94e9b30b4b2e	2022-08-01	3d1f33a4-7d26-4c50-b75d-80b540fe0fc1	Asia	Sports	3	386.75	314.11835	942.35505	722.127181339098	Adam Smith	1	942.35505	881	942.35505	55	62372.113224	936.3944649146875
acedfc4b-6cb8-45ab-ac63-ca4b41ebe848	2022-08-04	2c72635f-8418-47a1-a9ab-ed4fe5f269d6	Europe	Toys	2	105.23	90.971335	181.94267	70.5332829447064	Steven Coleman	1	181.94267	878	181.94267	59	68355.922945	964.8650638967956
4c00e4c5-77cb-401d-a2b9-533d8e00b05f	2022-08-05	a06cbc7e-cb64-4474-baff-1e161422b7d6	Asia	Beauty	1	476.54	458.19321	458.19321	281.57785711097404	Kristen Ramos	1	458.19321	877	458.19321	62	73461.618973	988.8412277570784
fb27271e-5a51-4e51-b7c0-13caa724fe6e	2022-08-08	d352e370-3902-4069-9ad0-9b75f8fdde90	Europe	Sports	6	270.98	270.03157000000004	1620.1894200000002	1376.0930855367233	Emily Matthews	1	1620.1894200000002	874	1620.1894200000002	72	80570.187359	919.786031455556
26a00867-66bd-42e4-9721-889fef94e109	2022-08-08	effdbfcf-32c1-4ebe-a629-3310c77b8f09	North America	Home & Kitchen	2	383.9	318.21471	636.4294199999999	438.4423551376574	Susan Edwards	1	636.4294199999999	874	636.4294199999999	68	86058.98736700001	1063.159646603474
abb4a539-0ce9-4a13-9543-18218615a4cc	2022-08-08	9746f76c-cf8e-4fbc-8827-78d0261088d4	Europe	Home & Kitchen	7	117.59	98.646251	690.523757	487.58968787842014	Caleb Camacho	1	690.523757	874	690.523757	66	91544.242731	1177.604080808591
ffb2e571-e2cb-4379-9be9-694e6112ad6c	2022-08-08	5e3644ea-f877-4dad-a306-289be885dd03	Asia	Beauty	3	182.37	148.120914	444.362742	269.8427742048543	Mary Scott	1	444.362742	874	444.362742	63	77562.23517100001	1033.152899764227
07cecbfa-1d03-4d0d-9be3-2d35ce50e30b	2022-08-08	cf3f8ae3-585f-4f11-b7da-1425e8ab4aa2	Asia	Toys	7	133.4	131.27894	918.95258	700.0240320547946	Kristen Ramos	1	918.95258	874	918.95258	62	73461.618973	988.8412277570784
1409ff83-26fb-4aba-8f7c-b89180118318	2022-08-09	f8a002bc-2409-451d-9a38-685b4cba50bf	Europe	Sports	4	433.79	369.285427	1477.141708	1236.5570459588912	Caitlyn Boyd	1	1477.141708	873	1477.141708	58	71709.8323	1035.5858485437743
e8d693ff-5a6e-4bf7-aeae-d47f89f7339d	2022-08-10	9681606a-99bd-4c7e-85b0-b7a02ecd96ab	South America	Books	7	71.11	70.82556	495.77892	313.8483780015412	Sandra Luna	1	495.77892	872	495.77892	56	72688.198308	1090.9576938669472
2257fa17-d497-4d4a-823b-8c984295677c	2022-08-11	436e7f37-259c-4fa7-ad7e-e9d387fb113c	Asia	Toys	1	181.19	175.319444	175.319444	66.4253794037267	Crystal Williams	1	175.319444	871	175.319444	65	72555.900913	927.0834787540324
48f1dc8e-3e48-4ed9-bd21-e77ad9c34f43	2022-08-13	da4cf752-d35d-485d-b7bd-4ce87778b7db	Australia	Sports	4	131.61	100.879065	403.5162600000001	235.67122027619484	Emily Matthews	1	403.5162600000001	869	403.5162600000001	72	80570.187359	919.786031455556
1caf092a-9f7e-4cf0-aa23-6c6110a43364	2022-08-13	dd68a139-269f-438c-b035-bde4cae42ecd	Europe	Books	6	473.28	407.872704	2447.236224	2190.046621570229	Bradley Howe	1	2447.236224	869	2447.236224	56	64186.396558	951.6581100155678
259a3e7c-c830-4e0e-bc64-c770776c1011	2022-08-19	da964803-898c-45f1-a297-40ef18f3d7a9	Australia	Electronics	4	434.73	367.738107	1470.952428	1230.5300116030205	Michelle Andersen	1	1470.952428	863	1470.952428	60	66978.268402	921.082547231716
17b309b3-238d-4236-9ce7-e790c972fd02	2022-08-20	377ddcce-1c30-40ee-bfd6-3e55d835661d	Australia	Electronics	3	107.75	82.77355	248.32065	115.10141716738198	Caleb Camacho	1	248.32065	862	248.32065	66	91544.242731	1177.604080808591
b3b2a45f-23d0-4a72-8085-9153e81598d5	2022-08-22	31619871-047e-4cde-8803-2906c989276f	Europe	Home & Kitchen	3	291.1	256.95397	770.8619100000001	561.5137187013199	Joseph Brooks	1	770.8619100000001	860	770.8619100000001	60	60657.854394	824.8550359343124
b79d7cff-d0c8-4511-aa99-83572ca548b3	2022-08-23	78aff5b4-a608-42b6-ac97-c0bcdd7275ba	Europe	Sports	2	156.35	125.29889	250.59778	116.73144452991453	Johnny Marshall	1	250.59778	859	250.59778	61	67804.798966	913.3835523608234
e866b86d-534a-4484-850e-ade6d2311438	2022-08-23	8f67905f-71e5-4215-a937-8ce8777800b7	Asia	Sports	1	168.24	141.18700800000002	141.18700800000002	46.51322807644338	Mary Scott	1	141.18700800000002	859	141.18700800000002	63	77562.23517100001	1033.152899764227
502c982e-b05f-40d9-9a51-675554c1dc5e	2022-08-25	3193c906-33a9-48bf-8dff-121a105e84ed	Europe	Electronics	9	81.31	78.033207	702.298863	498.3615679394546	Caitlyn Boyd	1	702.298863	857	702.298863	58	71709.8323	1035.5858485437743
1f6ea03f-bbcc-4a54-b221-d251f9454136	2022-08-26	73554abc-6678-434b-a199-a6f3a34e6bd9	Europe	Electronics	9	104.33	92.95803	836.62227	622.7125591769579	Sandra Luna	1	836.62227	856	836.62227	56	72688.198308	1090.9576938669472
11df0e1a-6092-4c92-8840-d2b6630e0bf3	2022-08-27	4aa84f84-80bc-42f0-b559-40b73f007452	Australia	Books	5	103.58	97.033744	485.16872	304.6878331612231	Diane Andrews	1	485.16872	855	485.16872	58	66389.094387	950.0340815608216
c7e66d6a-efe3-4c06-a7c8-1a3e29bc86b6	2022-08-27	e16e5ddb-0f45-427a-b971-fa68f6753ac1	Asia	Electronics	5	424.03	382.432657	1912.163285	1662.318342229467	Adam Smith	1	1912.163285	855	1912.163285	55	62372.113224	936.3944649146875
d7d81d69-1c64-4b16-842d-b29d0c33b0ab	2022-08-29	b2b0c00a-d190-43c7-8a13-a53de35e56a3	Asia	Clothing	4	58.37	48.604699	194.418796	78.451724124068	Michelle Garza	1	194.418796	853	194.418796	65	76798.491008	980.44596940906
4478d618-cacc-462a-87e7-a09acf756809	2022-08-29	fe86de17-0014-4357-b353-26f1d2d61964	Europe	Home & Kitchen	6	217.16	203.934956	1223.609736	990.8781215751673	Crystal Williams	1	1223.609736	853	1223.609736	65	72555.900913	927.0834787540324
ea241e43-552c-4ef6-95b0-8b3ce0ad465b	2022-08-29	adc86310-b277-40cd-be75-d063b24436ae	Asia	Electronics	7	93.64	92.244764	645.713348	446.836500642602	Johnny Marshall	1	645.713348	853	645.713348	61	67804.798966	913.3835523608234
1f04c823-70b4-47f1-9925-496fa9d5cc7b	2022-08-30	d8165a34-2f86-4b3a-a091-d9678c0f92f1	South America	Sports	6	331.14	321.735624	1930.413744	1680.2596997594371	Emily Matthews	1	1930.413744	852	1930.413744	72	80570.187359	919.786031455556
45b7b34d-df47-47eb-a485-46cd35957dec	2022-08-30	652fae47-10be-404a-b2ae-7f01bf8ff8fb	Australia	Electronics	7	140.26	129.123356	903.863492	685.8023359083232	Christina Thompson	1	903.863492	852	903.863492	53	64491.182614000005	1021.7261378833904
bc1e1af9-65e7-40b6-8602-3e5aa97cc9c9	2022-09-02	387c56c4-bc71-4e55-b2c8-d7cda0d511d0	Europe	Home & Kitchen	10	140.53	99.059597	990.59597	767.8299427444454	Jason Nelson	1	990.59597	849	990.59597	70	87933.283392	1049.1629849529377
2476bcf2-36a2-44ea-829a-4dc61406d713	2022-09-03	6abf3f8f-75f0-44d9-82cc-419e11af211c	Asia	Electronics	10	449.6	364.98528	3649.8528	3383.4362975693075	Adam Smith	1	3649.8528	848	3649.8528	55	62372.113224	936.3944649146875
efa39a85-b071-4c3e-8552-4756c110a6b2	2022-09-05	bb05e2fe-018e-4a6f-9331-fc9d47eccdff	Europe	Sports	9	223.42	161.10816200000002	1449.9734580000002	1210.1181251739563	Kristen Ramos	1	1449.9734580000002	846	1449.9734580000002	62	73461.618973	988.8412277570784
6144e24a-a6fc-4993-a039-9a70560eae2c	2022-09-06	9860b2d9-e0ca-4e33-bb9d-38a8d5e88dda	Asia	Sports	1	122.36	91.598696	91.598696	22.137335569272764	Roger Brown	1	91.598696	845	91.598696	54	68595.667163	1076.1212096324236
2b6ed03e-de77-4711-bc9f-86a916332978	2022-09-08	62a42450-6cbf-46b9-a0d0-ae65c2fc9438	Australia	Electronics	8	176.04	157.39736399999998	1259.178912	1025.1916759647677	Jason Nelson	1	1259.178912	843	1259.178912	70	87933.283392	1049.1629849529377
4fa932e7-5d07-46d7-b534-6497da85ae0a	2022-09-09	8fe05be9-e842-4977-9990-e9be25e24bf9	North America	Clothing	3	461.77	385.808835	1157.426505	927.1982502708212	Michelle Andersen	1	1157.426505	842	1157.426505	60	66978.268402	921.082547231716
4d552e64-8c66-4a6c-9aeb-50a2412c18c0	2022-09-11	39f0d9be-6029-4f0b-bc63-80ad1b4c2b72	Asia	Electronics	7	314.32	272.955488	1910.688416	1660.8697090978126	Sandra Luna	1	1910.688416	840	1910.688416	56	72688.198308	1090.9576938669472
7c900e89-53c4-43db-9f40-c1bc4d28512e	2022-09-11	5b2810ca-8d50-419f-b460-1967ae3cc7fa	South America	Sports	8	85.62	78.88170600000001	631.0536480000001	433.5902122405658	Caitlyn Boyd	1	631.0536480000001	840	631.0536480000001	58	71709.8323	1035.5858485437743
049c5d27-56d0-4905-934d-cb862333d992	2022-09-11	b14a4561-6b2c-4508-9c63-c9d5122510ac	Europe	Electronics	10	359.24	283.368512	2833.68512	2572.75647174954	Diane Andrews	1	2833.68512	840	2833.68512	58	66389.094387	950.0340815608216
a2fdf895-7c39-4470-a524-5084e4a56d95	2022-09-12	fc287b87-31d2-483c-bbb4-f0e61b000d58	South America	Toys	8	347.37	313.154055	2505.23244	2247.4155563618774	Crystal Williams	1	2505.23244	839	2505.23244	65	72555.900913	927.0834787540324
62064315-7081-4bbe-a834-52ba94d2e333	2022-09-13	d00ad2b8-1d84-43fa-8211-e09f6fa586d5	Australia	Home & Kitchen	7	486.37	358.016957	2506.118699	2248.292862185943	Emily Matthews	1	2506.118699	838	2506.118699	72	80570.187359	919.786031455556
3079ebe4-701e-442a-9fde-1e5a9e37dc6a	2022-09-15	64f9d241-6ae4-4065-9ea5-483a9be99a2b	Asia	Beauty	3	315.28	295.00749599999995	885.0224879999998	668.0786252717244	Christina Thompson	1	885.0224879999998	836	885.0224879999998	53	64491.182614000005	1021.7261378833904
3c45b533-5eb6-41c4-bb55-0d0a1b77e8dc	2022-09-17	9e44f1b8-f35d-4b2f-b800-66fc35158af2	South America	Home & Kitchen	4	453.58	383.320458	1533.281832	1291.2522141565562	Johnny Marshall	1	1533.281832	834	1533.281832	61	67804.798966	913.3835523608234
626a473c-4e3b-4451-af18-9f76d2521533	2022-09-18	d0e7ea93-dcaf-49f6-9146-10c1bfeed940	Europe	Clothing	5	181.5	177.2166	886.083	669.0759956896552	Jason Nelson	1	886.083	833	886.083	70	87933.283392	1049.1629849529377
8df88942-db1e-4377-8750-c37807e1de0a	2022-09-18	9ee2b9b9-0eed-4dbf-bea0-e23bf57c57c0	Europe	Toys	6	18.25	16.120224999999998	96.72135	24.352214197530856	Christina Thompson	1	96.72135	833	96.72135	53	64491.182614000005	1021.7261378833904
73d68d27-4de4-44e4-8734-203c488b8172	2022-09-19	5d89c715-82d8-4433-aa6b-bdbde4e5004b	South America	Home & Kitchen	1	443.49	441.449946	441.449946	267.376623444795	Michelle Garza	1	441.449946	832	441.449946	65	76798.491008	980.44596940906
fc26eb8d-4fe8-4f3b-8eef-75860b1919e1	2022-09-25	9aff3a56-1036-4edc-ab7a-f5e8a383b51a	South America	Books	10	86.99	69.226642	692.2664199999999	489.18427379019	Adam Smith	1	692.2664199999999	826	692.2664199999999	55	62372.113224	936.3944649146875
06467c39-a76c-4b16-8863-e46d85880093	2022-09-25	d5c4551a-0e82-42c0-bee7-a4f0fd3c5603	Australia	Toys	2	230.19	198.723027	397.446054	230.65514628251293	Michelle Andersen	1	397.446054	826	397.446054	60	66978.268402	921.082547231716
a17e787e-f42c-42b4-b7ec-c682970342ed	2022-09-26	c13db6c1-01de-432b-a17c-3a32d6541c30	Australia	Beauty	2	359.51	265.282429	530.564858	344.14665133122514	Michelle Andersen	1	530.564858	825	530.564858	60	66978.268402	921.082547231716
b76ea69d-eb8e-4cfc-8e8b-67e3c402d684	2022-09-30	0b391f4d-e053-4d41-9139-10e260b33df4	Australia	Electronics	3	120.24	106.520616	319.561848	168.24699028893411	Charles Smith	1	319.561848	821	319.561848	70	95387.089343	1149.437576059358
3d5b9fa9-feb8-4e54-8329-352e7ae5cbfc	2022-10-03	3a0c5bc9-c41e-4fb6-908f-87a9e2be5388	North America	Clothing	4	107.88	101.547444	406.189776	237.8837446748985	Joseph Brooks	1	406.189776	818	406.189776	60	60657.854394	824.8550359343124
dc28fc6b-9e11-4802-971b-3da1532d84c9	2022-10-12	a1576fa4-787b-4cdb-820e-4272097cddd6	North America	Clothing	6	165.91	127.053878	762.323268	553.6105320657084	Johnny Marshall	1	762.323268	809	762.323268	61	67804.798966	913.3835523608234
2920066c-3220-48e0-982e-b25dfdb854ef	2022-10-16	7c3b36a2-a586-442f-9552-31147f7c9df9	Australia	Toys	8	358.8	342.90516	2743.24128	2483.1000517634566	Diane Andrews	1	2743.24128	805	2743.24128	58	66389.094387	950.0340815608216
118746ed-118e-48d5-a8e3-026d96a513b1	2022-10-17	20beaa2f-f040-44de-b6c9-52284259355a	Europe	Electronics	5	306.92	256.707888	1283.53944	1048.7212990951502	Susan Edwards	1	1283.53944	804	1283.53944	68	86058.98736700001	1063.159646603474
d18961b3-26f4-4867-ac8f-27ce8db06dd4	2022-10-19	df347c50-9f60-42d0-904c-15dc17f7a816	Europe	Clothing	1	474.62	456.58444	456.58444	280.20848295592384	Susan Edwards	1	456.58444	802	456.58444	68	86058.98736700001	1063.159646603474
62195bbe-82b6-49c6-aa31-dd0171c7b8cf	2022-10-20	d62afd30-721c-44e4-b134-15738d8fc547	Asia	Electronics	10	159.45	111.71067	1117.1066999999998	888.5192844076118	Mary Scott	1	1117.1066999999998	801	1117.1066999999998	63	77562.23517100001	1033.152899764227
290a3339-9fb3-481f-a9a5-90c618be1648	2022-10-23	26a459da-460e-4269-848e-e6ee0fd31da0	South America	Books	10	73.04	52.844440000000006	528.4444000000001	342.2872153732343	Roger Brown	1	528.4444000000001	798	528.4444000000001	54	68595.667163	1076.1212096324236
d21caf20-80ad-4717-89c7-f5664716f022	2022-10-25	6b3c71fd-f693-401b-82a4-4f800ffbe918	Asia	Clothing	3	23.1	22.45089	67.35267	12.78516615166491	Joseph Brooks	1	67.35267	796	67.35267	60	60657.854394	824.8550359343124
d1b0ff6d-e4de-4acc-ba45-5d09ca1efe59	2022-10-25	e0292fe8-dee7-421d-8f86-cf62a260d74c	Asia	Sports	1	247.34	235.09667	235.09667	105.780569889989	Joseph Brooks	1	235.09667	796	235.09667	60	60657.854394	824.8550359343124
09ede531-b51d-4428-be8c-5d826940a111	2022-10-26	87893887-02c7-417a-be88-6c53aea47b8f	South America	Toys	10	190.42	154.77337599999998	1547.7337599999998	1305.3474161530992	Bradley Howe	1	1547.7337599999998	795	1547.7337599999998	56	64186.396558	951.6581100155678
e71de416-be5a-47bc-a5b1-1bbf54722f12	2022-10-27	59840b8b-7d18-43cb-bc76-01b5f93f73b1	Asia	Electronics	2	354.21	292.506618	585.013236	392.2957383059692	Johnny Marshall	1	585.013236	794	585.013236	61	67804.798966	913.3835523608234
563a0e1e-971c-46a5-9ecf-c918e6eed7a5	2022-10-29	53370a3a-73ee-4ca9-b864-faa81726eb50	Europe	Home & Kitchen	8	75.29	69.229155	553.83324	364.6243848191043	Michelle Garza	1	553.83324	792	553.83324	65	76798.491008	980.44596940906
4fa76d4b-2f48-412e-af17-9dbf024bd193	2022-10-31	0f3b7778-7100-4cec-abdd-2ebd202e4a50	Australia	Clothing	9	339.01	323.856253	2914.706277	2653.1076019984293	Roger Brown	1	2914.706277	790	2914.706277	54	68595.667163	1076.1212096324236
47ed07f2-ac8f-4204-a535-8248bc3b5361	2022-10-31	fdfe990d-60d2-476a-99e2-220c492809ff	Europe	Home & Kitchen	10	290.69	248.045777	2480.45777	2222.90574786292	Emily Matthews	1	2480.45777	790	2480.45777	72	80570.187359	919.786031455556
b8c34506-c74b-49de-80aa-9f165a44d120	2022-11-02	24f96b48-ef4a-4ea8-8137-fe7a8ed7c6b3	Asia	Home & Kitchen	10	414.27	394.38504	3943.8504	3675.976734664601	Mary Scott	1	3943.8504	788	3943.8504	63	77562.23517100001	1033.152899764227
a256ad19-bc56-4fb4-89d5-b4d2faa1034b	2022-11-05	b7450346-4d7f-4d9a-9f5d-96ab5b93caea	Asia	Books	9	329.83	234.344215	2109.097935	1856.1690689897105	Jason Nelson	1	2109.097935	785	2109.097935	70	87933.283392	1049.1629849529377
d0396790-59ff-40ef-af69-43d6fd3d7ff8	2022-11-05	ad3b331e-9596-42a5-baaf-fc05da45c0a4	Asia	Sports	10	405.03	334.87880399999995	3348.7880399999995	3084.109836037084	Diane Andrews	1	3348.7880399999995	785	3348.7880399999995	58	66389.094387	950.0340815608216
d12877c1-9d5c-459c-84a7-1890a45573f3	2022-11-10	535fbdce-b143-4261-9a4c-0a732e798bb5	North America	Electronics	6	435.03	305.82609	1834.95654	1586.479053812155	Caitlyn Boyd	1	1834.95654	780	1834.95654	58	71709.8323	1035.5858485437743
f441f59f-6045-4b39-b82e-f1011425a7b0	2022-11-14	d6583bf8-7417-4b9b-bf81-295f89367d36	Asia	Toys	10	256.08	199.87044	1998.7044	1747.4404269529578	Kristen Ramos	1	1998.7044	776	1998.7044	62	73461.618973	988.8412277570784
bbe92cce-ce3f-4e70-bdf4-9f8739f8920f	2022-11-15	88ef5ab7-feff-4583-8084-d74a07660277	Australia	Books	3	450.13	365.820651	1097.461953	869.7113246147509	Diane Andrews	1	1097.461953	775	1097.461953	58	66389.094387	950.0340815608216
ed8a5a68-2f2f-486a-9946-7570a4c4f5ec	2022-11-18	1d7373b3-90e1-4092-8258-3f241b40f9a2	Australia	Home & Kitchen	5	213.89	166.98392299999998	834.9196149999999	621.1172501437862	Christina Thompson	1	834.9196149999999	772	834.9196149999999	53	64491.182614000005	1021.7261378833904
696aa71b-f7fb-47ed-99a8-1828e866852f	2022-11-21	486351b6-c9ef-461b-be49-0b18a3a4d5d9	Europe	Electronics	9	491.43	400.712022	3606.408198	3340.227073759298	Susan Edwards	1	3606.408198	769	3606.408198	68	86058.98736700001	1063.159646603474
4ad7a4bc-15b3-4560-adbd-e3b29882dbb5	2022-11-22	6188ef46-9bbb-4baa-8c7e-f9f7642d37b6	Australia	Electronics	10	99.07	90.262677	902.62677	684.6378381768783	Steven Coleman	1	902.62677	768	902.62677	59	68355.922945	964.8650638967956
fcdda3e4-5f7a-4d52-8f3e-b426d2ccb403	2022-11-23	c75cc6f4-461e-4fc1-91d4-03f715abffc5	Australia	Electronics	7	124.62	113.304504	793.1315280000001	582.1754602286354	Susan Edwards	1	793.1315280000001	767	793.1315280000001	68	86058.98736700001	1063.159646603474
f556fa3a-4265-4361-8581-f0b8a3c2f9f5	2022-11-24	d16c2bce-12fa-4c28-8291-0a6501d17a17	North America	Electronics	8	349.89	281.801406	2254.411248	1999.5113409412163	Mary Scott	1	2254.411248	766	2254.411248	63	77562.23517100001	1033.152899764227
68112f9b-174c-4088-b51d-cff4a91dbc81	2022-11-24	715d8c96-af0d-40f5-8f81-3412e3661593	North America	Electronics	8	376.52	357.355132	2858.841056	2597.70005979082	Mary Scott	1	2858.841056	766	2858.841056	63	77562.23517100001	1033.152899764227
fbbea10a-fd9d-4672-a857-13ee415aad43	2022-11-27	82bc6b65-6f9f-4768-b139-0bdfbcf9b2f1	South America	Toys	2	419.84	370.466816	740.9336319999999	533.8590303957966	Johnny Marshall	1	740.9336319999999	763	740.9336319999999	61	67804.798966	913.3835523608234
3d82d735-bfa0-41e6-8bf1-53bd29a625b1	2022-12-01	1cd46093-8a9d-4dba-95f9-b8350883b460	Australia	Toys	9	157.69	145.453256	1309.079304	1073.4214634959496	Emily Matthews	1	1309.079304	759	1309.079304	72	80570.187359	919.786031455556
e29d56b6-e2fe-4505-bb73-6c0368da68ab	2022-12-02	22a54cb2-5bc4-4e53-ba7b-4f6307c2381a	South America	Clothing	10	437.96	346.119788	3461.19788	3195.8377837060884	Crystal Williams	1	3461.19788	758	3461.19788	65	72555.900913	927.0834787540324
3bea2cd0-f309-4215-982e-c92f7702788d	2022-12-08	26c813f9-4cee-4b52-8f1f-800e26b2a355	Europe	Electronics	4	435.39	346.526901	1386.107604	1148.067486534776	Roger Brown	1	1386.107604	752	1386.107604	54	68595.667163	1076.1212096324236
64eb2f25-febb-4bfd-b9ca-772b9a93998b	2022-12-09	f805b6fd-61bd-4daa-a00a-f6c43d070a89	Asia	Clothing	7	498.17	460.358897	3222.512279	2958.650929197742	Susan Edwards	1	3222.512279	751	3222.512279	68	86058.98736700001	1063.159646603474
84dafdd4-0ba3-42c7-aac6-f93d3dd8d193	2022-12-11	b62f1c15-7256-4b3e-abd3-020a3d396693	Asia	Sports	8	393.78	346.014486	2768.115888	2507.753965465716	Sandra Luna	1	2768.115888	749	2768.115888	56	72688.198308	1090.9576938669472
611cedce-96ab-4902-bf62-9270af8a804e	2022-12-12	b8d16568-d80b-41b5-9a65-d5970788f47b	Australia	Sports	2	431.83	327.974885	655.94977	456.11130728978793	Michelle Andersen	1	655.94977	748	655.94977	60	66978.268402	921.082547231716
273ea614-dcd7-497a-af69-c67d4c573f4a	2022-12-16	eb10d6c6-f929-4659-b484-544bd4f954ce	Europe	Toys	7	28.83	26.212236	183.485652	71.50173256148916	Roger Brown	1	183.485652	744	183.485652	54	68595.667163	1076.1212096324236
0f565696-61fe-4ab8-b42e-df70d540b3af	2022-12-18	f619fc90-303e-4dc3-a67f-10957ff84ae7	Asia	Home & Kitchen	10	252.83	205.980601	2059.80601	1807.601336427662	Michelle Garza	1	2059.80601	742	2059.80601	65	76798.491008	980.44596940906
c23a15fb-74e4-4a2a-a44f-b044a08965e0	2022-12-19	791094d7-3ce6-4fbe-a3ea-18101055ba80	Australia	Electronics	5	355	275.409	1377.045	1139.2749922299922	Caleb Camacho	1	1377.045	741	1377.045	66	91544.242731	1177.604080808591
276981bb-4695-4c19-b79e-d75c31651a48	2022-12-20	65425deb-df07-409c-9905-15c516a14826	Europe	Home & Kitchen	4	211.65	160.34604000000002	641.3841600000001	442.9176686796424	Johnny Marshall	1	641.3841600000001	740	641.3841600000001	61	67804.798966	913.3835523608234
199504a3-fc1a-40b7-bae4-7ab158e4e43d	2022-12-20	21f4a7f4-9044-4e5e-a6a0-bc8628611aaa	Australia	Toys	8	173.74	140.868392	1126.947136	897.9533465541219	Caleb Camacho	1	1126.947136	740	1126.947136	66	91544.242731	1177.604080808591
8b84eabe-1910-4631-9b74-2620f2c209cf	2022-12-21	70900c9e-8001-4b67-a5e6-5563297a45e7	North America	Toys	5	10.09	7.387898	36.93949	4.206224603455915	Michelle Andersen	1	36.93949	739	36.93949	60	66978.268402	921.082547231716
1500eacc-3afb-4156-b8d1-fe5d30a5517b	2022-12-21	f1b7bdb3-b940-4560-940b-4be82099e28b	Asia	Books	8	165.84	119.554056	956.432448	735.4401773837658	Diane Andrews	1	956.432448	739	956.432448	58	66389.094387	950.0340815608216
0b23634e-88f0-493c-a241-79399311a1ae	2022-12-23	8c968e39-2fe9-4631-82dd-e82e07728b05	North America	Home & Kitchen	7	118.75	110.08125	770.5687500000001	561.2433262251441	Emily Matthews	1	770.5687500000001	737	770.5687500000001	72	80570.187359	919.786031455556
1d5d748f-3cf3-4266-b90f-e79ba2c4b956	2022-12-29	5931eb28-2367-431b-8b30-17cd69a9ad45	South America	Sports	7	258.49	211.832555	1482.8278850000002	1242.0934403932074	Roger Brown	1	1482.8278850000002	731	1482.8278850000002	54	68595.667163	1076.1212096324236
6e5ad5d2-35a9-485c-9654-460babfdbf01	2022-12-29	c97aeb99-599f-428f-afcc-bbdcb3f4b6d5	North America	Sports	7	345.85	273.01399000000004	1911.0979300000004	1661.274675797276	Caleb Camacho	1	1911.0979300000004	731	1911.0979300000004	66	91544.242731	1177.604080808591
d68b7771-4910-4fe6-88bf-e48f2896a65f	2022-12-29	fbbb45ea-8c45-4aad-9055-e7225efefd03	Asia	Toys	10	123.89	88.556572	885.56572	668.5897509697653	Kristen Ramos	1	885.56572	731	885.56572	62	73461.618973	988.8412277570784
86d6e885-d1de-4cc3-8e4b-d99e33b26295	2022-12-30	9a2ee84d-b280-4aba-9342-bead88f4cb45	Europe	Clothing	8	87.16	77.319636	618.557088	422.33303318288233	Charles Smith	1	618.557088	730	618.557088	70	95387.089343	1149.437576059358
6aed3c68-1953-49bb-b1ce-0ce9984a8f79	2022-12-30	f90b201f-9218-4fa2-93f5-7373f333a830	Europe	Beauty	7	94.36	77.922488	545.457416	357.2388459516908	Christina Thompson	1	545.457416	730	545.457416	53	64491.182614000005	1021.7261378833904
7c05a9e7-30ea-4580-a938-413e234b246b	2022-12-31	6bd77469-9e37-40bf-bbcd-ef8b5719ad2a	South America	Sports	7	489.74	485.82208	3400.7545600000003	3135.755880024001	Christina Thompson	1	3400.7545600000003	729	3400.7545600000003	53	64491.182614000005	1021.7261378833904
18399f4c-2c82-4224-bc2f-e45eecc8b3e5	2023-01-01	b4ce5262-320e-476a-b0ee-f7b6391108a8	Australia	Beauty	9	164.35	161.16161	1450.45449	1210.5870389093586	Steven Coleman	1	1450.45449	728	1450.45449	59	68355.922945	964.8650638967956
4bc7337f-576c-4e67-b537-9cc5089a335f	2023-01-02	539d45f5-71bd-4c41-8779-b7f14f99ed62	Europe	Home & Kitchen	3	326.23	302.937178	908.811534	690.4626958855414	Roger Brown	1	908.811534	727	908.811534	54	68595.667163	1076.1212096324236
58e46d75-5d50-467d-b41d-339495eb3759	2023-01-05	19a036f0-03f7-437c-a553-4e01dd72b88f	North America	Clothing	8	340.12	245.668676	1965.349408	1714.619114193787	Charles Smith	1	1965.349408	724	1965.349408	70	95387.089343	1149.437576059358
49e357ea-c20c-4cb9-8b98-7c49518682c8	2023-01-06	4bf8a8b3-ffed-4e67-9837-b03b057bff0a	Europe	Sports	1	331.71	267.192405	267.192405	128.72922160361713	Joseph Brooks	1	267.192405	723	267.192405	60	60657.854394	824.8550359343124
0cc73e50-61b2-42b9-be7c-568f58984994	2023-01-07	cb303480-577e-492e-9ba1-066e21d8e257	North America	Clothing	10	223.04	199.933056	1999.33056	1748.0573647456265	Steven Coleman	1	1999.33056	722	1999.33056	59	68355.922945	964.8650638967956
2a75e96d-5f14-4c87-b58f-c03a55c2ad43	2023-01-08	21aa0be2-03d9-44f7-81dd-4b741f713fc3	North America	Toys	2	222.91	206.749025	413.49805	243.9482509184845	Roger Brown	1	413.49805	721	413.49805	54	68595.667163	1076.1212096324236
71dba09b-31fb-48be-8cda-3f29a276149e	2023-01-11	fec70190-2791-4aa8-8729-d25e6856ec7f	South America	Toys	7	264.98	193.77987400000004	1356.4591180000002	1119.3117696197835	Caitlyn Boyd	1	1356.4591180000002	718	1356.4591180000002	58	71709.8323	1035.5858485437743
0e7a530a-7cb3-4ee5-a197-55d23647fa2d	2023-01-19	088f08fb-1c7c-4e78-bf0a-2a1bcafaf64d	Australia	Home & Kitchen	5	11.16	8.059752	40.29876	4.955171155937556	Adam Smith	1	40.29876	710	40.29876	55	62372.113224	936.3944649146875
601887cb-abc5-4587-aa53-dec4449d19ca	2023-01-21	5916a156-3cc2-423f-815a-719d85c6bb1f	South America	Toys	2	295.15	215.016775	430.03355	257.76517280174653	Michelle Garza	1	430.03355	708	430.03355	65	76798.491008	980.44596940906
0a0358ea-f078-4157-807b-7bb83b8c3e3a	2023-01-22	6fb1abf9-b499-43a1-b184-892803ef803d	North America	Toys	2	93.02	66.993004	133.986008	42.60283517228208	Jason Nelson	1	133.986008	707	133.986008	70	87933.283392	1049.1629849529377
aaaad0c2-8a89-4ff9-920e-4fc23d9b61c2	2023-01-23	6125fb79-5c0f-4f9a-a186-9d0ef89930c9	North America	Clothing	6	380.7	317.42766	1904.56596	1654.8523163655434	Kristen Ramos	1	1904.56596	706	1904.56596	62	73461.618973	988.8412277570784
154bbc68-7ee3-4ef7-bc3b-99f36e43cfe9	2023-01-24	52f62cbe-da8a-4cf6-b40b-af5ec821bed6	Europe	Beauty	7	295.97	262.466196	1837.263372	1588.742734082026	Roger Brown	1	1837.263372	705	1837.263372	54	68595.667163	1076.1212096324236
be04833a-541f-4f75-a84b-0febed75fddc	2023-01-25	9aeb679c-0218-42b5-9571-631b0e11f677	Europe	Toys	6	429.2	386.19416	2317.16496	2061.483434626767	Adam Smith	1	2317.16496	704	2317.16496	55	62372.113224	936.3944649146875
b2f66671-d96c-45ae-9dee-9c758381463e	2023-01-25	cd01b8a1-f0b6-4acc-9fb8-668f29f7c7b0	South America	Sports	6	146.1	103.89171	623.35026	426.6477481666141	Mary Scott	1	623.35026	704	623.35026	63	77562.23517100001	1033.152899764227
95872200-ea75-4b29-9859-7d75ce123bbf	2023-01-28	f5ca141c-73e7-4426-9281-0d86330c288e	South America	Beauty	9	200.42	197.974876	1781.773884	1534.2949773788907	Charles Smith	1	1781.773884	701	1781.773884	70	95387.089343	1149.437576059358
6d86f552-1360-43c7-9c25-cb892fab114b	2023-01-28	35738aa6-076a-4297-abf6-213b1f4451b1	Europe	Books	6	419.1	407.44902	2444.69412	2187.53114347892	Sandra Luna	1	2444.69412	701	2444.69412	56	72688.198308	1090.9576938669472
c35ac6c2-a619-4485-9ed7-2eb3d03f7343	2023-01-28	d0008a83-62f5-488b-816b-12385ea15f02	South America	Clothing	1	378.15	365.633235	365.633235	204.7172790982308	Steven Coleman	1	365.633235	701	365.633235	59	68355.922945	964.8650638967956
23a53abe-11bb-4b8f-b84f-cade78cc7a98	2023-01-29	856aef66-5eda-4fe5-9a09-db90a87710fc	Europe	Home & Kitchen	10	267.5	266.0555	2660.555	2401.178446258835	Bradley Howe	1	2660.555	700	2660.555	56	64186.396558	951.6581100155678
bd643cf7-13de-404e-9fd1-f75d4765af89	2023-01-30	480fb382-e407-4aac-a474-80fba4c71e10	Europe	Books	4	81.54	62.78580000000001	251.14320000000004	117.12153395592082	Caitlyn Boyd	1	251.14320000000004	699	251.14320000000004	58	71709.8323	1035.5858485437743
21d169ea-9bb0-4df9-a942-dcae05fdf2c3	2023-01-31	4ef9c06c-acad-479d-a26a-d23b26254b5d	Europe	Electronics	2	461.43	374.450445	748.90089	541.2074821570802	Charles Smith	1	748.90089	698	748.90089	70	95387.089343	1149.437576059358
3f80b794-22b7-42b9-be62-7088ead14415	2023-02-05	24d3eab6-a8e5-420e-ad9e-cc874d79699b	South America	Sports	4	433.28	312.308224	1249.232896	1015.5916720903716	Charles Smith	1	1249.232896	693	1249.232896	70	95387.089343	1149.437576059358
51bd77db-9f23-45f5-855f-6540550a0ea1	2023-02-07	a5ef64c7-7550-4b1e-9d6e-defdca95dfef	South America	Electronics	1	480.75	446.664825	446.664825	271.79017736081744	Adam Smith	1	446.664825	691	446.664825	55	62372.113224	936.3944649146875
1d955cb6-24a8-4930-b5a9-5fe355d327ef	2023-02-08	ff90928a-0b0d-4187-a9a5-4d1e67b586b1	North America	Toys	3	189.33	173.483079	520.449237	335.2952873753247	Mary Scott	1	520.449237	690	520.449237	63	77562.23517100001	1033.152899764227
7ef90000-c413-48ed-a582-a892ea515c3c	2023-02-08	0ed98c1c-0653-4259-aad8-61d3361b7a48	South America	Electronics	2	329.7	261.61695	523.2339	337.72943286534775	Adam Smith	1	523.2339	690	523.2339	55	62372.113224	936.3944649146875
6dbe124e-5bc4-4c6b-add2-a046f3fdd841	2023-02-08	d52203e4-5af4-431d-aa95-28f58dd14421	North America	Home & Kitchen	4	483.92	358.487936	1433.951744	1194.540817545371	Emily Matthews	1	1433.951744	690	1433.951744	72	80570.187359	919.786031455556
1cc8bf40-00d6-4df0-aad2-9155ee0ba435	2023-02-09	aa490009-9e9a-4f1a-9644-947a10bcd856	Europe	Books	6	382.66	361.843296	2171.059776	1917.2622968374733	Jason Nelson	1	2171.059776	689	2171.059776	70	87933.283392	1049.1629849529377
002f3ec3-64ab-461e-8abe-31392097e106	2023-02-12	8a1bb1e1-2828-40dc-819c-a8d466071503	North America	Books	4	74.27	63.89448099999999	255.577924	120.30140677139678	Mary Scott	1	255.577924	686	255.577924	63	77562.23517100001	1033.152899764227
4c115568-018b-46d5-a37c-383d1b2f3f47	2023-02-13	1f2c1e36-d0e4-45ee-8f41-d731f6cdba1e	Australia	Clothing	1	10.71	8.230635	8.230635	0.2288510217771726	Bradley Howe	1	8.230635	685	8.230635	56	64186.396558	951.6581100155678
fd9fb1cf-b814-4b91-aeda-ce40fdac1610	2023-02-15	924d955a-0d38-42fd-9611-4417e787c46e	Asia	Sports	9	64.37	46.14685300000001	415.3216770000001	245.4629076245144	Sandra Luna	1	415.3216770000001	683	415.3216770000001	56	72688.198308	1090.9576938669472
4a4c3045-b44e-4971-ae5b-fce8330d3125	2023-02-18	f9b5d687-7b35-4797-a31b-638ce9f93e22	Asia	Books	2	436.82	422.84176	845.6835199999999	631.184580214072	Crystal Williams	1	845.6835199999999	680	845.6835199999999	65	72555.900913	927.0834787540324
a37351a1-8892-4f63-8ecd-c38cb0fcef4d	2023-02-18	a52de200-3cdb-4c0c-8fb4-e6140cf77b12	Europe	Clothing	9	489.64	416.92846	3752.35614	3485.408027738769	Bradley Howe	1	3752.35614	680	3752.35614	56	64186.396558	951.6581100155678
16bf164d-059b-4d93-b9c4-46b1312314b8	2023-02-19	eb97bf1a-e96b-4aed-8481-f220007c3b8e	South America	Beauty	10	6.42	5.831928	58.31927999999999	9.837045400282657	Crystal Williams	1	58.31927999999999	679	58.31927999999999	65	72555.900913	927.0834787540324
c227b251-d868-42bd-9a93-00cb1c0064fa	2023-02-20	69683ad7-369c-439b-8ec9-ac3d10a29f9b	Asia	Sports	10	452.8	385.92144	3859.2144	3591.739063335251	Caleb Camacho	1	3859.2144	678	3859.2144	66	91544.242731	1177.604080808591
e76ff1ae-fa96-4c47-90aa-965d21fde16f	2023-02-22	22e91f84-5fe1-47ad-962a-73bcaeb8c138	Asia	Toys	1	346.45	255.437585	255.437585	120.19955821050402	Susan Edwards	1	255.437585	676	255.437585	68	86058.98736700001	1063.159646603474
8adc7764-9359-4a35-8b20-64a0d6eb6ffc	2023-02-22	b9f73409-27ec-4f98-a64c-ab9cfadfe389	Asia	Toys	1	35.36	30.671264	30.671264	2.957101173579108	Crystal Williams	1	30.671264	676	30.671264	65	72555.900913	927.0834787540324
2aed2ee7-e735-4221-bf68-59367d8be4f7	2023-02-23	6549ee66-6515-4921-8435-d412bf515926	Australia	Toys	3	53.51	37.794113	113.382339	32.07553441054141	Adam Smith	1	113.382339	675	113.382339	55	62372.113224	936.3944649146875
85a54f98-9ff8-4851-a98e-c7f6fa5a1369	2023-02-27	550eee95-293d-417e-b772-be121f9e448b	South America	Books	9	157.54	153.380944	1380.428496	1142.5589224814846	Sandra Luna	1	1380.428496	671	1380.428496	56	72688.198308	1090.9576938669472
010e43f5-b471-4299-a2e7-914fe1b1932b	2023-03-02	b50d13e7-c753-4e53-b1e1-b1baa404fa35	South America	Electronics	4	275.59	194.621658	778.4866319999999	568.5840672890422	Michelle Andersen	1	778.4866319999999	668	778.4866319999999	60	66978.268402	921.082547231716
4698e069-7ddd-42a3-bbdc-d710b827478e	2023-03-04	6138c4f3-53ec-4c07-9147-b6b9a831040d	Asia	Beauty	8	480.67	456.924902	3655.399216	3388.9532234786247	Kristen Ramos	1	3655.399216	666	3655.399216	62	73461.618973	988.8412277570784
4400dd49-f6f1-4580-9f7f-bfa2628c51bd	2023-03-05	10746fe8-a3d0-4228-9bf4-4972b8bc4e15	Asia	Clothing	1	224.38	214.148272	214.148272	91.43423154386568	Michelle Garza	1	214.148272	665	214.148272	65	76798.491008	980.44596940906
9ee69bc6-3555-4999-ab07-5a3a10a9358f	2023-03-07	c8b02005-9323-4bd1-b9f6-cdcc7081454e	Asia	Clothing	8	194.56	144.791552	1158.332416	928.0705303027532	Diane Andrews	1	1158.332416	663	1158.332416	58	66389.094387	950.0340815608216
8b45d74d-67b3-460c-a0ba-88536c2f6dd4	2023-03-11	7c35bcc0-287c-400e-8484-38bee6e4f941	Australia	Clothing	6	59.82	55.357428	332.144568	178.06720658607412	Johnny Marshall	1	332.144568	659	332.144568	61	67804.798966	913.3835523608234
77a261e4-8ea9-4823-a70a-2725cbdf52b8	2023-03-13	bce33a13-f04b-4aaa-b8d3-40889949e879	Asia	Electronics	4	371.94	292.977138	1171.908552	941.113398288674	Diane Andrews	1	1171.908552	657	1171.908552	58	66389.094387	950.0340815608216
aba27cc8-b25d-4c26-8d11-af0b7e1d8b81	2023-03-13	43c626da-858a-401c-9d5e-9a26ed48d622	Asia	Books	8	34.22	33.747764	269.982112	130.77302052841085	Adam Smith	1	269.982112	657	269.982112	55	62372.113224	936.3944649146875
3d459d74-55af-4a57-8f97-d04ebe93ac62	2023-03-15	b9a43638-e850-4e06-83cf-b6b648e618b7	Europe	Home & Kitchen	5	191.52	134.56195200000002	672.8097600000001	471.4360327844124	Johnny Marshall	1	672.8097600000001	655	672.8097600000001	61	67804.798966	913.3835523608234
c3101ecb-78c2-4472-bab9-9ae72b513049	2023-03-20	46e222b4-937c-4c74-ac84-e8c2a368a9e8	Europe	Electronics	7	417.56	371.00206	2597.01442	2338.25486278825	Charles Smith	1	2597.01442	650	2597.01442	70	95387.089343	1149.437576059358
0514666f-2590-4451-b96c-6245572d0aa8	2023-03-21	ee52f9c3-eb47-489c-b4d2-4e021cb0b1e3	Asia	Clothing	6	317.04	300.99777600000004	1805.9866560000005	1558.0477960329492	Michelle Andersen	1	1805.9866560000005	649	1805.9866560000005	60	66978.268402	921.082547231716
ea8a6226-41d2-48aa-8daa-c799efc50b32	2023-03-21	93a5aa1d-595a-4944-8136-cb7a81338d8e	North America	Books	5	173.28	151.723968	758.6198400000001	550.1906178113582	Bradley Howe	1	758.6198400000001	649	758.6198400000001	56	64186.396558	951.6581100155678
a5378821-8ace-4084-b1d1-e0a3c0ec4900	2023-03-22	b8043ff4-f82c-492d-9a6c-11e37906f79a	Australia	Books	8	480.86	421.329532	3370.636256	3105.821924471045	Christina Thompson	1	3370.636256	648	3370.636256	53	64491.182614000005	1021.7261378833904
1f2be432-0baa-4b86-88c0-41776bfe0266	2023-03-23	ae299ec5-483d-4974-970c-6cefc23d3b1e	North America	Sports	3	288.79	231.378548	694.1356440000001	490.8926949179282	Crystal Williams	1	694.1356440000001	647	694.1356440000001	65	72555.900913	927.0834787540324
c1d51263-756a-4884-b1c8-a8eaa9b32e53	2023-03-24	85f26949-d4d0-47a0-b617-3f967c651af9	Asia	Beauty	8	152.47	135.484842	1083.878736	856.7171616193152	Kristen Ramos	1	1083.878736	646	1083.878736	62	73461.618973	988.8412277570784
5e9103df-8ac5-437d-89ef-d8f4ed321348	2023-03-24	8716fc25-ee6d-4e0e-a4b2-31e79e9d3d78	South America	Home & Kitchen	7	362.03	341.792523	2392.547661	2135.974185289544	Kristen Ramos	1	2392.547661	646	2392.547661	62	73461.618973	988.8412277570784
c6a33e12-7b34-4940-acc7-348ab33fff7e	2023-03-27	61205014-eeb2-444b-99b9-b97a78ae9432	North America	Clothing	4	195.84	155.634048	622.536192	425.91684009550886	Charles Smith	1	622.536192	643	622.536192	70	95387.089343	1149.437576059358
a7d1c78b-3609-41ad-b788-3057288226d7	2023-03-27	8f08eae1-6501-4eea-9197-bcdb3c581ea7	Asia	Home & Kitchen	2	285.22	265.93912800000004	531.8782560000001	345.3001327320308	Steven Coleman	1	531.8782560000001	643	531.8782560000001	59	68355.922945	964.8650638967956
8ab37e40-7620-48a3-9208-74f2b8da8d31	2023-03-27	d7794db7-9fc5-4e92-bf00-ec5d841fe3d5	Asia	Beauty	7	327.49	246.730966	1727.116762	1480.7237064761468	Caleb Camacho	1	1727.116762	643	1727.116762	66	91544.242731	1177.604080808591
d0c56d4b-91de-4fa2-a3bf-f5f4ad33cd1f	2023-03-27	8f4d7785-b492-428b-af41-4a4559aa77b1	Asia	Home & Kitchen	2	31.32	25.256448	50.512896	7.552446944038103	Michelle Garza	1	50.512896	643	50.512896	65	76798.491008	980.44596940906
3b3cbf93-1066-4544-8e0a-de7a0f285565	2023-03-28	9912a616-f2da-414a-801d-9541d472088c	Australia	Clothing	8	306.81	248.945634	1991.565072	1740.415601395445	Jason Nelson	1	1991.565072	642	1991.565072	70	87933.283392	1049.1629849529377
84074402-7f4a-4c0c-b0ed-503a9a587e56	2023-03-29	d530b0a4-bda8-49a0-bcc5-85ec08eed0ad	North America	Books	10	166.51	142.932184	1429.32184	1190.0407203696388	Joseph Brooks	1	1429.32184	641	1429.32184	60	60657.854394	824.8550359343124
a10166c9-42eb-42c6-b8ae-b407b57a2d9d	2023-04-01	2342e7b8-33c8-40d5-ad9b-f9a09a7c1fab	Asia	Clothing	9	336.85	301.244955	2711.204595	2451.3538617989307	Susan Edwards	1	2711.204595	638	2711.204595	68	86058.98736700001	1063.159646603474
4666b5f2-f2b2-4ac1-9521-0f6ce9eeb635	2023-04-03	95777970-e01b-45e7-b78e-4a43ca8c8d14	North America	Home & Kitchen	10	112.47	107.735013	1077.35013	850.477484855013	Emily Matthews	1	1077.35013	636	1077.35013	72	80570.187359	919.786031455556
c9530a02-c465-40e7-8a95-582dadccfb27	2023-04-04	de5282aa-97e0-4be4-9d70-d6c3eed5e64b	Europe	Toys	3	342.69	274.871649	824.614947	611.497600968418	Caleb Camacho	1	824.614947	635	824.614947	66	91544.242731	1177.604080808591
41272116-2229-4905-9076-201269884986	2023-04-04	53a80034-4e21-404a-8ed0-dca24860aac6	North America	Toys	2	162.67	150.697488	301.394976	154.2797439015961	Bradley Howe	1	301.394976	635	301.394976	56	64186.396558	951.6581100155678
8b822f14-a5f7-4179-98ee-0db3f099dac7	2023-04-06	bd5aea01-2b61-4ed2-926d-8e019c9e289f	Europe	Sports	3	128.58	102.208242	306.624726	158.2746722963859	Joseph Brooks	1	306.624726	633	306.624726	60	60657.854394	824.8550359343124
8325a528-232e-49ff-a86d-73fe8a8a0920	2023-04-11	4343a808-310c-4188-961b-9d4098dee862	Asia	Electronics	10	195.04	147.06016	1470.6016	1230.189371783554	Crystal Williams	1	1470.6016	628	1470.6016	65	72555.900913	927.0834787540324
7561e8ce-6d9f-4b70-9ef3-9a6f7544612d	2023-04-12	a29fd427-f729-4e9a-a81a-b2a9cde43a96	Europe	Sports	9	12.81	10.459365	94.134285	23.223335847457637	Crystal Williams	1	94.134285	627	94.134285	65	72555.900913	927.0834787540324
065df2e4-f446-4962-a943-4102b2b18814	2023-04-16	dd0cc0fd-f11e-4391-a317-945f5c02c97e	Australia	Clothing	6	157.01	115.857679	695.146074	491.81564402457	Joseph Brooks	1	695.146074	623	695.146074	60	60657.854394	824.8550359343124
046e3113-7c69-449f-9c3c-11ceb174fc1b	2023-04-21	6d7ca131-9e96-41cd-9d9d-ea52b5998160	North America	Sports	5	160.18	145.89194400000002	729.4597200000001	523.2928215770731	Jason Nelson	1	729.4597200000001	618	729.4597200000001	70	87933.283392	1049.1629849529377
9e56f354-f754-430f-af64-b4f47ec6a123	2023-04-22	5cccad41-6bbf-4672-929a-9affd63105e9	North America	Home & Kitchen	8	86.44	61.614432	492.915456	311.36948863231555	Sandra Luna	1	492.915456	617	492.915456	56	72688.198308	1090.9576938669472
ab4feb01-cc1b-43ed-99ce-3b268424f583	2023-04-22	b4003917-a14a-4e82-9907-92f73a3854cf	North America	Sports	2	480.61	415.391223	830.7824459999999	617.2521182954738	Caitlyn Boyd	1	830.7824459999999	617	830.7824459999999	58	71709.8323	1035.5858485437743
4ce1a7bd-4d4b-47ae-85a1-69b25d6b04ed	2023-04-23	0126800c-31cf-4388-a76a-3de90aac83e9	Asia	Home & Kitchen	7	19.17	17.078553000000003	119.54987100000002	35.121996	Roger Brown	1	119.54987100000002	616	119.54987100000002	54	68595.667163	1076.1212096324236
12f30452-3b72-4e7a-810f-2ed9f75d143a	2023-04-23	9f79369d-53de-4f6c-915e-9ecd0bdb3c9b	Asia	Home & Kitchen	3	318.9	287.87103	863.61309	647.9793596629214	Charles Smith	1	863.61309	616	863.61309	70	95387.089343	1149.437576059358
824eb084-f651-4c5a-860f-32ea9ced6096	2023-04-24	fc980f60-bdf8-41c5-886f-e7f8dac30ed0	North America	Home & Kitchen	3	365.58	277.548336	832.645008	618.9928967406343	Roger Brown	1	832.645008	615	832.645008	54	68595.667163	1076.1212096324236
1f3b80da-a8ea-4130-bec4-88fa55bfb068	2023-04-25	ebad3b91-ffa9-46b2-bd9b-e6f5ed4619b0	Asia	Toys	8	358.7	354.79017	2838.32136	2577.352689244858	Caleb Camacho	1	2838.32136	614	2838.32136	66	91544.242731	1177.604080808591
5379cc87-ad19-4c09-b9c9-1821ce729e72	2023-04-25	7659c6b7-73ed-496c-b61d-d95315871e38	Australia	Electronics	7	263.12	217.889672	1525.227704	1283.400603747903	Charles Smith	1	1525.227704	614	1525.227704	70	95387.089343	1149.437576059358
c16ae38d-1179-4fd8-aafb-6081466cd855	2023-04-28	b245f45f-323d-4e1d-9758-ae009c9540a5	Europe	Beauty	10	267.72	192.73162800000003	1927.31628	1677.2168431828918	Roger Brown	1	1927.31628	611	1927.31628	54	68595.667163	1076.1212096324236
a3d0cf85-91b6-4d99-99b0-1d6559629586	2023-04-28	33f9061c-7967-4516-a460-1edafd063b2a	North America	Books	3	53.32	51.69374	155.08122	54.35296590802807	Joseph Brooks	1	155.08122	611	155.08122	60	60657.854394	824.8550359343124
7901a3c8-30f5-4751-9743-81bc2a12123a	2023-04-29	6414478a-08b3-48f9-ba54-d0c9daf81e64	South America	Toys	10	303	225.5835	2255.835	2000.9182269219036	Christina Thompson	1	2255.835	610	2255.835	53	64491.182614000005	1021.7261378833904
ee05e5e0-9794-4950-8a67-1b010dc5e8ea	2023-05-06	be4aeb27-92c6-484f-8eab-c58b10c48834	South America	Clothing	9	164.45	119.900495	1079.104455	852.1539092357198	Susan Edwards	1	1079.104455	603	1079.104455	68	86058.98736700001	1063.159646603474
df81bd39-ba9f-4083-977b-7a2168b2e281	2023-05-16	1dde31bd-75ad-4dde-bfa9-807a0f0411f7	Australia	Electronics	8	64.88	59.59876799999999	476.790144	297.47831850169234	Adam Smith	1	476.790144	593	476.790144	55	62372.113224	936.3944649146875
837f40da-5128-408c-8513-58a4fc8255b7	2023-05-19	52eb21a7-a5bd-45c0-8e64-0d63c6c4d69d	Australia	Home & Kitchen	4	283.07	247.374873	989.499492	766.7897256259284	Joseph Brooks	1	989.499492	590	989.499492	60	60657.854394	824.8550359343124
a542212e-b0fa-4af1-baed-8b9d3acc9d83	2023-05-20	195d1430-f3a8-4e64-b61e-67898b9d172b	North America	Electronics	10	268.31	247.972102	2479.72102	2222.1759684332646	Adam Smith	1	2479.72102	589	2479.72102	55	62372.113224	936.3944649146875
1771db89-6613-4ade-8f43-5bfc9bf77462	2023-05-20	01135888-fe97-44ae-877f-8948267f921a	South America	Clothing	10	125.62	120.884126	1208.84126	976.6486319795628	Jason Nelson	1	1208.84126	589	1208.84126	70	87933.283392	1049.1629849529377
3f4a04c3-c47b-4505-833a-6a50cb6ff64b	2023-05-22	b34fa233-e6f0-48e7-a710-e4217980d6cf	Europe	Toys	6	54.79	41.234954	247.409724	114.45807479800098	Susan Edwards	1	247.409724	587	247.409724	68	86058.98736700001	1063.159646603474
295c7cbf-7dbc-493c-a493-8c2d9512a070	2023-05-23	3b5596ee-e60f-495b-9eaa-b82c8e457691	Asia	Toys	8	372.68	278.876444	2231.011552	1976.414152508964	Diane Andrews	1	2231.011552	586	2231.011552	58	66389.094387	950.0340815608216
38317991-3569-4010-b952-29055ee86c32	2023-05-23	73dcc186-6504-4ecf-8710-4ff58d1c8766	Australia	Sports	10	318.87	255.127887	2551.27887	2292.981676434957	Kristen Ramos	1	2551.27887	586	2551.27887	62	73461.618973	988.8412277570784
604267a6-c147-42c9-a809-44add76f0f84	2023-05-24	73616bf7-5117-43a5-b930-7d4f8690d35d	Australia	Clothing	9	408.18	292.62424200000004	2633.618178	2374.500704417285	Bradley Howe	1	2633.618178	585	2633.618178	56	64186.396558	951.6581100155678
a1f10cc5-2a4b-45fd-adfc-3da6e52b11f9	2023-05-25	2433cff5-cf5e-4c7e-b43e-fb0b1da0368a	Asia	Toys	7	250.97	242.462117	1697.2348189999998	1451.458229130908	Christina Thompson	1	1697.2348189999998	584	1697.2348189999998	53	64491.182614000005	1021.7261378833904
648e0405-520e-4068-8d70-c58962f83d79	2023-05-27	b0057053-d1f9-4e5b-9779-65d7c3aff390	North America	Beauty	3	413.38	359.764614	1079.293842	852.3321054478698	Kristen Ramos	1	1079.293842	582	1079.293842	62	73461.618973	988.8412277570784
9d54f919-4f1c-44d3-95c7-c87848fa9de9	2023-05-29	7865280f-b370-4ba3-a8b0-adead4f1331d	Australia	Electronics	3	306.96	249.834744	749.504232	541.7644853329638	Michelle Garza	1	749.504232	580	749.504232	65	76798.491008	980.44596940906
a6abfcf0-db08-4e0a-822a-69df3014f85f	2023-05-31	37fc8edf-ba4a-4e18-a04b-6684658e3b6b	Australia	Clothing	4	86.15	66.705945	266.82378	128.4584097448662	Caitlyn Boyd	1	266.82378	578	266.82378	58	71709.8323	1035.5858485437743
e74474fa-cca8-46e1-a3aa-3a04d68fcc99	2023-05-31	c27246b7-a7f3-4e9a-8530-a319a0e01c32	North America	Electronics	2	84.77	69.290998	138.581996	45.08449498799082	Diane Andrews	1	138.581996	578	138.581996	58	66389.094387	950.0340815608216
1f8adfaa-25cb-4650-89b6-20743bbaf7f4	2023-06-01	b13cf1b7-b5d2-45cc-bcd7-8199ca325cbc	Asia	Clothing	5	30.02	24.070036	120.35018	35.52484873414153	Diane Andrews	1	120.35018	577	120.35018	58	66389.094387	950.0340815608216
3ebe7596-0572-44e9-ac9d-36a44823499f	2023-06-04	feba7a3c-7b75-4db1-8285-2570d745d445	North America	Sports	3	93.13	88.697012	266.09103600000003	127.92652278539904	Crystal Williams	1	266.09103600000003	574	266.09103600000003	65	72555.900913	927.0834787540324
a9424837-2bcb-45ab-9935-a8d89882bb26	2023-06-06	0e834a17-cdfa-4b9f-980e-dba709582761	Asia	Books	5	218.79	161.182593	805.912965	594.0647538123653	Johnny Marshall	1	805.912965	572	805.912965	61	67804.798966	913.3835523608234
2d1b8e67-891d-4be1-ade1-27a571de4c87	2023-06-08	48b3ddab-410a-455a-9237-748f1c3c81a0	North America	Electronics	5	57.21	56.23743	281.18715000000003	139.05858651435506	Christina Thompson	1	281.18715000000003	570	281.18715000000003	53	64491.182614000005	1021.7261378833904
0de9223b-fedf-4f96-b972-556a5b3b8e7d	2023-06-10	b84d3933-b57f-4b2a-8b35-71aeddd6a3a1	South America	Electronics	7	416.28	311.71046399999994	2181.973248	1928.028058935372	Bradley Howe	1	2181.973248	568	2181.973248	56	64186.396558	951.6581100155678
24b0d94d-03f1-4612-a958-ef55990e526a	2023-06-10	144ebc50-cf2a-4dba-ada2-f6a40e79ce03	South America	Beauty	8	358.71	340.308177	2722.465416	2462.51455034546	Mary Scott	1	2722.465416	568	2722.465416	63	77562.23517100001	1033.152899764227
54996540-1dfb-4120-aacc-01ea141b597e	2023-06-10	a08be9d5-04e1-4481-abf4-89249553eb24	Asia	Clothing	4	329.64	233.088444	932.353776	712.6766222372179	Michelle Andersen	1	932.353776	568	932.353776	60	66978.268402	921.082547231716
e4da35f1-4f7d-47b1-8a53-dc0d710c8880	2023-06-12	5819f31e-e3b0-4264-8926-02ec8ba53818	North America	Sports	6	467.11	445.295963	2671.775778	2412.294417356681	Johnny Marshall	1	2671.775778	566	2671.775778	61	67804.798966	913.3835523608234
61c962de-b687-4103-bfc5-c1d0293fad88	2023-06-12	19f96e81-8e66-4139-8364-416ab3913f9a	South America	Electronics	9	124.39	122.076346	1098.687114	870.8807912481288	Joseph Brooks	1	1098.687114	566	1098.687114	60	60657.854394	824.8550359343124
493af3ac-733a-46f8-b772-6733dbb2cbe9	2023-06-12	f1e47fbd-e39a-4d45-ac3e-7b80a38763da	Asia	Clothing	5	54.63	38.634336000000005	193.17168000000004	77.64528803779679	Charles Smith	1	193.17168000000004	566	193.17168000000004	70	95387.089343	1149.437576059358
49db8bbc-afe2-4987-a620-6b58229eff9e	2023-06-15	07308d21-0cb4-446c-974d-73070e82f675	North America	Sports	10	399.22	337.74012	3377.4012	3112.5443797863827	Caitlyn Boyd	1	3377.4012	563	3377.4012	58	71709.8323	1035.5858485437743
edb7dabd-c6ce-4350-9db3-df4e23ebb275	2023-06-22	e5a37a99-eb0b-40e8-a5af-755f7d9dd376	Australia	Electronics	6	108.43	99.007433	594.0445980000001	400.35545616759055	Kristen Ramos	1	594.0445980000001	556	594.0445980000001	62	73461.618973	988.8412277570784
52d1fa0d-8c0e-4464-b5cd-1aff76c74257	2023-06-23	12fffe04-5839-4572-bad2-d8c4b9f7db5f	Australia	Home & Kitchen	10	27.88	22.106052	221.06052	96.11109653176578	Johnny Marshall	1	221.06052	555	221.06052	61	67804.798966	913.3835523608234
b6de9b87-0d42-4c6e-b7ea-7f25a3cd2f59	2023-06-24	d0743937-54f0-4e94-9155-f2450c718314	Asia	Clothing	9	354.77	270.831418	2437.482762	2180.399581212555	Joseph Brooks	1	2437.482762	554	2437.482762	60	60657.854394	824.8550359343124
c8fcd37a-0ff5-4f23-ac9c-3d617641afb7	2023-06-24	daadbd44-a576-4159-8b8a-3a2f96796bae	South America	Books	1	432.78	420.705438	420.705438	249.95766495726284	Johnny Marshall	1	420.705438	554	420.705438	61	67804.798966	913.3835523608234
b9aeb07f-f2e1-4c67-ae5e-5c20d94c4506	2023-06-27	795f7d88-18c3-43af-8b9e-dffa79ad725a	Asia	Electronics	4	277.62	205.327752	821.311008	608.4147956509928	Susan Edwards	1	821.311008	551	821.311008	68	86058.98736700001	1063.159646603474
4019413f-37ac-4d3a-94aa-c3d12fc17387	2023-06-28	e7701bfe-9eb3-4b92-a351-bd11f73b1bdd	Europe	Toys	7	444.81	313.101759	2191.712313	1937.636090213605	Jason Nelson	1	2191.712313	550	2191.712313	70	87933.283392	1049.1629849529377
39b65f0b-ee6a-4ddb-9042-f6d690e1adc5	2023-07-04	f3ac3dab-3769-4cac-9afc-d57f3e55af22	Australia	Sports	9	356.07	344.746974	3102.722766	2839.6932252195725	Johnny Marshall	1	3102.722766	544	3102.722766	61	67804.798966	913.3835523608234
2ae77f9f-205a-4f30-bfe0-2dc23f9f60a4	2023-07-17	d71a2ddd-8162-409b-a797-13f049faa1ab	South America	Sports	1	330.14	279.859678	279.859678	138.07242599878407	Mary Scott	1	279.859678	531	279.859678	63	77562.23517100001	1033.152899764227
e80e9af6-a49e-4a4d-911c-1d9b2f9f4562	2023-07-18	18abcf02-f16a-41a2-b22b-ae734cd42d26	South America	Sports	10	459.87	411.3997020000001	4113.997020000001	3845.368176005956	Charles Smith	1	4113.997020000001	530	4113.997020000001	70	95387.089343	1149.437576059358
73039e7e-853e-4fb8-b6d8-80b3c345d394	2023-07-19	39615bd0-2245-48fc-bfac-f2acdf3c3149	Australia	Toys	2	495.25	472.022775	944.04555	723.7263943604285	Steven Coleman	1	944.04555	529	944.04555	59	68355.922945	964.8650638967956
3953dab9-559d-4df9-8ebe-41fef1bba979	2023-07-19	ae43a08f-0396-471a-8ab4-82f534445abf	North America	Home & Kitchen	1	426.44	413.561512	413.561512	243.9995964608446	Susan Edwards	1	413.561512	529	413.561512	68	86058.98736700001	1063.159646603474
48634b03-52c1-4c46-b5ec-e0ca8c364a81	2023-07-19	19fc7a75-f3f9-4f8b-97ef-d1380ae9909e	Asia	Electronics	7	112.25	93.7512	656.2583999999999	456.39289063499314	Adam Smith	1	656.2583999999999	529	656.2583999999999	55	62372.113224	936.3944649146875
d61480c4-5ce2-49ac-bf9e-4cebcf74534c	2023-07-21	ee6ebc59-0992-434c-b514-96a7caf56ebb	South America	Electronics	2	456.97	330.206522	660.413044	460.1604456798569	Sandra Luna	1	660.413044	527	660.413044	56	72688.198308	1090.9576938669472
7aaec9e4-7b72-44d7-858d-19df6abffefa	2023-07-23	e93a9120-92e8-40d1-8bbd-abc836275ff8	Asia	Beauty	9	334.96	234.907448	2114.167032	1861.164263789189	Steven Coleman	1	2114.167032	525	2114.167032	59	68355.922945	964.8650638967956
3ca9562d-7907-4e15-ba8f-eba65e62adc1	2023-07-30	fdf5d0e6-9604-4080-abae-bed40aacaa69	Australia	Books	7	44.29	36.09635	252.67444999999995	118.2159304171988	Sandra Luna	1	252.67444999999995	518	252.67444999999995	56	72688.198308	1090.9576938669472
fc5fc4d3-3cce-47e6-9bf3-6c7db7903797	2023-07-30	a5454c71-0135-44ae-9ca3-82e272629701	Australia	Toys	4	472.07	357.781853	1431.127412	1191.7964402121177	Christina Thompson	1	1431.127412	518	1431.127412	53	64491.182614000005	1021.7261378833904
577cf6d7-fa2f-43d7-bc73-dce0f76e7d9f	2023-07-30	44e8f830-bca4-4bff-9375-09235b34dc78	North America	Toys	4	124.23	123.621273	494.485092	312.72919550657946	Steven Coleman	1	494.485092	518	494.485092	59	68355.922945	964.8650638967956
126daad8-3803-49dd-bf35-9d8f3611bce4	2023-08-03	3412a4bb-8929-4050-a334-18e2413b8611	South America	Beauty	6	189.13	137.251641	823.509846	610.4633706028872	Emily Matthews	1	823.509846	514	823.509846	72	80570.187359	919.786031455556
50b0d985-fbba-4677-9c77-3ed79518fb45	2023-08-04	81b29062-1443-4a43-a520-1f50c8f2c9d0	Australia	Books	1	156.86	122.63314800000002	122.63314800000002	36.67734229452584	Johnny Marshall	1	122.63314800000002	513	122.63314800000002	61	67804.798966	913.3835523608234
046074e3-cc63-4e94-8391-44b5e0aeea3c	2023-08-10	edfd4bf6-9e61-4d45-b5ab-c79ffa2aadcc	Europe	Sports	2	475.88	447.3272	894.6543999999999	677.135703185023	Roger Brown	1	894.6543999999999	507	894.6543999999999	54	68595.667163	1076.1212096324236
590913cc-ccd2-4372-805f-8c43e255d753	2023-08-11	5029d989-03b6-47de-9203-20097c8fea01	Asia	Home & Kitchen	2	215.23	174.09954699999997	348.19909399999995	190.75692814722368	Steven Coleman	1	348.19909399999995	506	348.19909399999995	59	68355.922945	964.8650638967956
b2ba45fc-3e4c-4880-9ac1-e3dbaad8c9ed	2023-08-12	fc08ae2f-fe9c-4a41-8849-d55d3a42a16f	Europe	Electronics	5	181.94	153.666524	768.33262	559.1714559557903	Michelle Andersen	1	768.33262	505	768.33262	60	66978.268402	921.082547231716
d759f33e-032e-40df-a932-26e0627bb61b	2023-08-14	aaa0eded-e4e2-419d-87f5-8886ec620a5c	Asia	Beauty	3	201.53	147.298277	441.89483100000007	267.7559474092056	Crystal Williams	1	441.89483100000007	503	441.89483100000007	65	72555.900913	927.0834787540324
0a29e103-799f-423b-8e91-9a7906bcfea6	2023-08-16	27da785c-80e9-49b0-afc9-4ee6c61ca41f	Europe	Sports	8	263.3	248.95015	1991.6012	1740.450340594459	Caleb Camacho	1	1991.6012	501	1991.6012	66	91544.242731	1177.604080808591
9e337bc2-b482-4f61-9a89-19113f35a4cc	2023-08-22	c6df6321-9e24-43fb-8db1-9988a4a63859	North America	Toys	8	399.43	334.163138	2673.305104	2413.808787398208	Steven Coleman	1	2673.305104	495	2673.305104	59	68355.922945	964.8650638967956
1b5e5606-5332-4382-8ffd-97a93667af01	2023-08-23	419f28e0-7e58-42a8-bcdf-ed2dba685d05	Australia	Books	3	235.3	172.73373	518.20119	333.3340108055367	Mary Scott	1	518.20119	494	518.20119	63	77562.23517100001	1033.152899764227
c63db560-449a-4217-b77b-eed3a908d1e6	2023-08-26	fe473ee8-8c0b-426f-bea6-6693d86b128c	Asia	Sports	6	201.27	148.074339	888.446034	671.2963947567092	Susan Edwards	1	888.446034	491	888.446034	68	86058.98736700001	1063.159646603474
ffcfe410-b778-4e56-a405-a9e85cb265d6	2023-08-28	3fb1f133-52a0-4ab9-8c6d-20a7d622842a	Europe	Home & Kitchen	9	444.96	425.515248	3829.637232	3562.305273939492	Charles Smith	1	3829.637232	489	3829.637232	70	95387.089343	1149.437576059358
a4643a71-0dc7-4776-8275-b68706a7d00b	2023-08-29	10d0abdd-c192-432a-b177-ebeac6981bae	Australia	Home & Kitchen	8	446.24	348.468816	2787.750528	2527.215530383155	Caitlyn Boyd	1	2787.750528	488	2787.750528	58	71709.8323	1035.5858485437743
5538770b-b5ca-48c1-8581-5f4294f4b283	2023-08-30	13037ced-5b97-4fd3-8c8b-f7533d45d157	Australia	Sports	2	157.08	113.820168	227.640336	100.61598691233748	Johnny Marshall	1	227.640336	487	227.640336	61	67804.798966	913.3835523608234
eea23727-e0a3-4968-a0e4-1781c92c1d25	2023-08-31	d9aabc40-53d0-4625-833a-8fb7cfe9ef5b	North America	Beauty	7	300.83	219.816481	1538.7153669999998	1296.5505311485676	Diane Andrews	1	1538.7153669999998	486	1538.7153669999998	58	66389.094387	950.0340815608216
4a416c0a-6f4b-4d09-9d03-e350cfcc0ec1	2023-09-01	0eb9d670-4a45-48af-97c9-159ddb035eab	Europe	Clothing	9	137.17	129.255291	1163.297619	932.8412580110544	Mary Scott	1	1163.297619	485	1163.297619	63	77562.23517100001	1033.152899764227
dad15541-3dcf-49f5-90eb-b3311ce1c194	2023-09-03	43f90661-4c1a-4b36-b555-029dfcb210d2	North America	Sports	3	348.23	321.451113	964.353339	742.9428605245092	Bradley Howe	1	964.353339	483	964.353339	56	64186.396558	951.6581100155678
f87628bf-9461-4741-a039-8680ef90ba2b	2023-09-08	e80a4b7e-36e1-4efe-8aa4-18bce8836b4b	South America	Books	8	315.37	244.979416	1959.835328	1709.1977691080133	Caitlyn Boyd	1	1959.835328	478	1959.835328	58	71709.8323	1035.5858485437743
ceca6059-f112-4394-b83c-095e2f14e0d2	2023-09-11	f84f45d0-3be6-4a05-b600-2f168a60d2b7	Asia	Home & Kitchen	1	129.71	112.354802	112.354802	31.57631181378963	Michelle Andersen	1	112.354802	475	112.354802	60	66978.268402	921.082547231716
6dea94b4-89a8-440c-9752-6668eae9293c	2023-09-12	cb3e3cf8-77fb-4769-945a-1d24f1cf505d	South America	Toys	6	349.21	264.35197	1586.11182	1342.8020867627974	Joseph Brooks	1	1586.11182	474	1586.11182	60	60657.854394	824.8550359343124
18b0e270-1879-481c-807f-f6fdf22b1897	2023-09-12	32352837-fa84-4d30-8fff-410eebc8c392	Europe	Home & Kitchen	5	413.77	365.60717199999993	1828.03586	1579.6850428222856	Emily Matthews	1	1828.03586	474	1828.03586	72	80570.187359	919.786031455556
fae26bc3-82fc-42ea-9949-26629655d9b6	2023-09-13	c3c9edd6-a97a-485f-8891-8916146505c4	North America	Electronics	5	298.57	293.972022	1469.8601099999998	1229.4669217885646	Christina Thompson	1	1469.8601099999998	473	1469.8601099999998	53	64491.182614000005	1021.7261378833904
ed8ff44d-08d0-4547-8965-62cbead9f0ae	2023-09-15	9f1647d4-98b8-44cf-a419-961e5e5fbb77	Asia	Sports	6	230.95	205.799545	1234.79727	1001.6626962248656	Roger Brown	1	1234.79727	471	1234.79727	54	68595.667163	1076.1212096324236
79def4ab-40af-4567-ac8c-17b06f9bbb34	2023-09-16	ab6260e5-d663-4430-b11d-6b20d0094cb4	Australia	Books	8	408.89	389.999282	3119.994256	2856.8390653386527	Kristen Ramos	1	3119.994256	470	3119.994256	62	73461.618973	988.8412277570784
e48eed4a-5c9e-4e4d-975c-29ee003c4459	2023-09-17	931faeba-8562-4efa-ae3d-fd7b653a3e3a	Europe	Toys	10	422.54	378.38457	3783.8457	3516.740025184772	Diane Andrews	1	3783.8457	469	3783.8457	58	66389.094387	950.0340815608216
1fac9a5e-4466-4537-b4a5-b306d14ccafe	2023-09-18	88e3fd5f-8e73-4c17-99b7-895c369065e0	Europe	Clothing	5	388.43	360.307668	1801.53834	1553.682752189585	Sandra Luna	1	1801.53834	468	1801.53834	56	72688.198308	1090.9576938669472
1838c3c3-3e01-452c-a404-0383c6499050	2023-09-18	80b8739d-c03f-46b1-abe6-94cf8c5bdbd0	Australia	Toys	10	34.65	30.79692	307.9692	159.3067168951535	Emily Matthews	1	307.9692	468	307.9692	72	80570.187359	919.786031455556
fac8b236-5b2f-4ecb-8e68-9db5fbe826d4	2023-09-20	7eb90783-f6ef-4df7-afcd-d4f45b2d5769	Asia	Beauty	10	453.63	405.862761	4058.627610000001	3790.238909281851	Sandra Luna	1	4058.627610000001	466	4058.627610000001	56	72688.198308	1090.9576938669472
dee4257f-9cd7-4793-ad16-41a3f3d24fcb	2023-09-22	be96c38e-58c9-48fe-94d5-3c9804aaf069	Australia	Beauty	3	311.6	245.72776	737.1832800000001	530.4055514650361	Adam Smith	1	737.1832800000001	464	737.1832800000001	55	62372.113224	936.3944649146875
bc686dbc-b05e-4001-bf3f-84dda0e9cdc9	2023-09-23	d4e491eb-c2aa-458e-a03f-fcbb914d95a6	North America	Clothing	5	211.44	163.56998399999998	817.8499199999999	605.1838462032919	Susan Edwards	1	817.8499199999999	463	817.8499199999999	68	86058.98736700001	1063.159646603474
eee9754e-a9c2-4684-a834-6d7eb5a7c851	2023-09-23	7c636d20-c616-4f44-ae3b-6541a9abbb3d	Europe	Books	10	170.97	153.667836	1536.67836	1294.5635701025697	Caitlyn Boyd	1	1536.67836	463	1536.67836	58	71709.8323	1035.5858485437743
4657f19b-b2a4-4f9e-a63f-4cb360f345e1	2023-09-24	bbb00eb5-5764-4984-8060-3baf18373639	Australia	Toys	6	14.51	10.36014	62.16083999999999	11.054336670229382	Bradley Howe	1	62.16083999999999	462	62.16083999999999	56	64186.396558	951.6581100155678
d5b7ec8a-1f8d-4fef-898b-7d94c8e9a9af	2023-09-27	a9496a2d-ae78-4291-9623-11c2ba29c655	Asia	Home & Kitchen	1	335.91	275.64774600000004	275.64774600000004	134.94653319820327	Caitlyn Boyd	1	275.64774600000004	459	275.64774600000004	58	71709.8323	1035.5858485437743
6457ee26-e7ac-492d-913f-61309a129893	2023-09-28	6733bac1-60b2-45a2-9d56-cab72843b903	South America	Beauty	7	441.89	375.871634	2631.101438	2372.007254051206	Michelle Andersen	1	2631.101438	458	2631.101438	60	66978.268402	921.082547231716
7c30b4e8-a7d4-4c67-87a5-0a510257fb15	2023-09-28	2df68fe7-c3fa-47e5-aaac-92565cde2222	South America	Clothing	2	189.86	184.904654	369.809308	208.0945502599266	Kristen Ramos	1	369.809308	458	369.809308	62	73461.618973	988.8412277570784
0c567a5e-f593-4c8a-8d01-82ed54963a03	2023-09-30	1d0adc5e-5495-4ada-a58b-099181894c39	Australia	Beauty	8	373.1	275.75821	2206.06568	1951.7964023291568	Mary Scott	1	2206.06568	456	2206.06568	63	77562.23517100001	1033.152899764227
656a0e58-34de-4991-84b2-1525f07d9da7	2023-10-02	2a84fdb6-0421-4269-8acb-b7181644c084	North America	Electronics	2	412.86	376.363176	752.726352	544.7449329018568	Crystal Williams	1	752.726352	454	752.726352	65	72555.900913	927.0834787540324
a7faf896-cc17-4f43-a8f6-f68cf6b5ecba	2023-10-05	240252bc-10fc-4f10-8ac8-1224431bb229	Australia	Clothing	4	159.6	127.48847999999998	509.9539199999999	326.146999584775	Crystal Williams	1	509.9539199999999	451	509.9539199999999	65	72555.900913	927.0834787540324
f216d464-680f-4f0b-b17f-c50a3aaa6070	2023-10-06	a05854e5-2a9f-4f8e-acef-fbb14ebb0b50	South America	Books	6	386.32	344.867864	2069.207184	1816.861767104672	Joseph Brooks	1	2069.207184	450	2069.207184	60	60657.854394	824.8550359343124
05ebaa0c-20d6-43f8-ab4c-c268b047751d	2023-10-09	1725493e-1028-4b1e-9864-79b8cf39e90f	South America	Beauty	6	485.67	467.70021	2806.2012600000003	2545.506067558318	Caitlyn Boyd	1	2806.2012600000003	447	2806.2012600000003	58	71709.8323	1035.5858485437743
2072be0a-f974-493a-9998-06be301fd5ca	2023-10-09	8b87f603-74e5-4074-aae3-7717f7b8580c	North America	Home & Kitchen	10	34.08	28.034208	280.34208	138.432649476082	Caitlyn Boyd	1	280.34208	447	280.34208	58	71709.8323	1035.5858485437743
829d6662-accc-493e-9d32-6d60bc66ecaa	2023-10-10	fcb2b9e9-4c9f-4a35-80ef-fc3b6f6be6c7	Europe	Beauty	8	83.52	77.42304	619.38432	423.0784376470589	Michelle Garza	1	619.38432	446	619.38432	65	76798.491008	980.44596940906
c2f8db4d-5c26-40ae-9725-b894ddf29143	2023-10-11	cf0dc78c-1de2-4576-8594-6b6696d12510	North America	Electronics	9	437.93	362.868798	3265.819182	3001.671265373775	Susan Edwards	1	3265.819182	445	3265.819182	68	86058.98736700001	1063.159646603474
114306c6-1abd-442d-851f-4076925f3282	2023-10-11	7e80537a-3d09-4183-bb83-2953cb394f0f	South America	Books	4	402.81	395.237172	1580.948688	1337.763226071066	Mary Scott	1	1580.948688	445	1580.948688	63	77562.23517100001	1033.152899764227
1325df67-3c36-4c7c-8bfe-766664566e7f	2023-10-11	224506ce-01d8-49fa-bf97-fd32f058cf96	South America	Beauty	10	222.94	166.068006	1660.68006	1415.6841819166764	Diane Andrews	1	1660.68006	445	1660.68006	58	66389.094387	950.0340815608216
604982e7-6f2e-40b0-9c14-54fc6706227b	2023-10-14	14b636ee-b1f0-4113-b8f2-5fbe90e621a7	Europe	Clothing	1	221.91	182.698503	182.698503	71.0041195556031	Crystal Williams	1	182.698503	442	182.698503	65	72555.900913	927.0834787540324
c268f9d4-605a-4b16-9cf0-fa016624abfd	2023-10-16	2e3f8307-8868-4738-9f0c-c22b64bce04d	Europe	Home & Kitchen	2	441.2	431.75832	863.51664	647.8908403146304	Diane Andrews	1	863.51664	440	863.51664	58	66389.094387	950.0340815608216
67613268-0474-410f-a22d-c57c0bfed61e	2023-10-18	3400b941-efa4-4623-9fcc-a12c36b8185c	South America	Home & Kitchen	1	124.19	112.317436	112.317436	31.560004306010924	Joseph Brooks	1	112.317436	438	112.317436	60	60657.854394	824.8550359343124
60757c77-82c9-4e3d-ade5-c4c7319fd3a9	2023-10-19	5bcc7728-0dd0-4a5c-a414-bce330fc451a	Asia	Books	8	293.15	253.252285	2026.01828	1774.3264841343669	Emily Matthews	1	2026.01828	437	2026.01828	72	80570.187359	919.786031455556
854c801a-abf6-49d7-bb0a-4bc89dc8b32d	2023-10-21	db454235-87e4-4f76-b99f-0dbb43c82e84	South America	Books	7	398.4	290.67264	2034.70848	1782.8850069372147	Johnny Marshall	1	2034.70848	435	2034.70848	61	67804.798966	913.3835523608234
abc9eac1-53ae-4cb9-90a1-2b64c955210b	2023-10-21	61612b84-ac41-4018-88b5-05ef80eea3d5	Australia	Clothing	8	106.54	101.12776800000002	809.0221440000001	596.9586724403671	Michelle Garza	1	809.0221440000001	435	809.0221440000001	65	76798.491008	980.44596940906
044b18ae-3e04-455a-814c-886e1c791584	2023-10-25	c2d155a0-ce20-4c24-9d40-1a4e81f2132c	Australia	Toys	6	455.55	421.702635	2530.21581	2272.135862019584	Charles Smith	1	2530.21581	431	2530.21581	70	95387.089343	1149.437576059358
a1b801d2-b4ad-4166-9a7c-a7b34ca07df9	2023-11-01	d416ce8c-211b-4008-8708-4cb2cc71ccf8	Australia	Home & Kitchen	9	265.37	192.764768	1734.8829119999998	1488.3316071084328	Crystal Williams	1	1734.8829119999998	424	1734.8829119999998	65	72555.900913	927.0834787540324
63468186-0e80-4567-b441-965c5110f938	2023-11-01	ae205167-f753-44b4-8bd1-9ce1e74a9fcd	Asia	Toys	2	205.55	172.764775	345.52955000000003	188.6346900808246	Diane Andrews	1	345.52955000000003	424	345.52955000000003	58	66389.094387	950.0340815608216
ff2b3788-ec1e-4ff7-bf83-f19d2ec0ca35	2023-11-04	169deb96-58b1-41d4-b3f8-b18403fefaa3	North America	Books	8	159.33	122.253909	978.031272	755.9079334430743	Steven Coleman	1	978.031272	421	978.031272	59	68355.922945	964.8650638967956
0dc1b04e-3601-486a-8f61-f18b9fb64274	2023-11-14	ea1c9407-08d9-4a3d-93d9-f1957b31f2ca	Europe	Home & Kitchen	5	269.95	208.752335	1043.761675	818.414795816961	Emily Matthews	1	1043.761675	411	1043.761675	72	80570.187359	919.786031455556
aca3dc5e-5ae2-4ad3-8d91-dfc442d81fb1	2023-11-14	605887f0-4477-4b8c-8965-75389c5d091d	Asia	Beauty	8	109.51	92.875431	743.003448	535.7673874192955	Roger Brown	1	743.003448	411	743.003448	54	68595.667163	1076.1212096324236
3c40a873-b0f4-4723-b155-5fd0f10f0e6e	2023-11-17	a09956a5-253f-41aa-86e4-1271f633ba03	South America	Toys	4	143.61	133.29880200000002	533.1952080000001	346.4564386937975	Mary Scott	1	533.1952080000001	408	533.1952080000001	63	77562.23517100001	1033.152899764227
9cea8d91-0e4e-458c-a377-33269e2ac26e	2023-11-17	cf53f2b5-1761-40c4-bd6b-0276fb2a3b0a	North America	Toys	1	137.3	111.11689	111.11689	30.980664700706768	Jason Nelson	1	111.11689	408	111.11689	70	87933.283392	1049.1629849529377
7236cff5-ac09-4878-9c22-ab1fff8f47ac	2023-11-23	5bc43b47-c38f-4acb-b025-acb74eb4321f	Asia	Sports	4	497.03	455.527995	1822.11198	1573.8712230620836	Crystal Williams	1	1822.11198	402	1822.11198	65	72555.900913	927.0834787540324
cb0d1da7-58f5-4f98-8bf9-f4595576e401	2023-11-23	0b73f2bf-84bd-47d9-89e3-4ef17078e5fc	Europe	Sports	6	132.04	130.204644	781.227864	571.1243586346448	Johnny Marshall	1	781.227864	402	781.227864	61	67804.798966	913.3835523608234
e8061a0c-4e08-4557-94c6-cabf25ea85ec	2023-11-28	b50b7776-db93-4dc9-9564-591431ca4bca	North America	Toys	2	386.05	381.80345	763.6069	554.7999817610063	Johnny Marshall	1	763.6069	397	763.6069	61	67804.798966	913.3835523608234
34145a3e-e8c7-49a3-a258-3b6006f13751	2023-12-01	4e015532-9579-4988-9f26-c0a6a63db2e5	South America	Beauty	6	412.93	386.585066	2319.510396	2063.7986179870354	Susan Edwards	1	2319.510396	394	2319.510396	68	86058.98736700001	1063.159646603474
00c7b717-c7fb-48c7-ab84-ea5f881459ec	2023-12-02	f46c379f-f985-4838-a285-243981762456	Asia	Electronics	8	82.74	70.511028	564.088224	373.69797693641146	Charles Smith	1	564.088224	393	564.088224	70	95387.089343	1149.437576059358
a2c83831-36b8-4916-94a4-ae67830193b1	2023-12-06	9f9a5203-15d1-412f-bd4f-eda0ad148fcd	Australia	Toys	3	403.95	332.410455	997.231365	774.1321088645159	Diane Andrews	1	997.231365	389	997.231365	58	66389.094387	950.0340815608216
b2e761f3-f887-461e-9072-fcf23b06aaae	2023-12-07	f8393892-bf27-4eba-8c8f-ce696613939d	Asia	Electronics	1	470.22	434.71839	434.71839	261.7030314073072	Johnny Marshall	1	434.71839	388	434.71839	61	67804.798966	913.3835523608234
da52a72e-65ce-4f34-ad27-3c56b886d795	2023-12-07	5d4c960c-2502-4194-a01e-913c84506ad5	Asia	Electronics	9	439.68	343.69785600000006	3093.2807040000007	2830.318184957563	Diane Andrews	1	3093.2807040000007	388	3093.2807040000007	58	66389.094387	950.0340815608216
2c54fa73-1023-4f40-b104-ae99397cd548	2023-12-11	81d354b2-a85d-43a6-a063-416465290258	South America	Toys	6	217.92	158.122752	948.736512	728.1616696304286	Crystal Williams	1	948.736512	384	948.736512	65	72555.900913	927.0834787540324
23c4f112-6338-42a0-bda3-d9699d42529a	2023-12-13	6b7cfe15-77c3-465d-952e-f3fc4f993bf2	Asia	Clothing	6	431.98	408.00511	2448.03066	2190.830548632065	Steven Coleman	1	2448.03066	382	2448.03066	59	68355.922945	964.8650638967956
acbcf819-5706-416f-a1d4-ce1fd2a3c7fb	2023-12-16	da8c71f7-7e2e-449b-ba8b-4322eb7085d7	Europe	Clothing	4	151.22	109.952062	439.8082480000001	265.9916064950402	Emily Matthews	1	439.8082480000001	379	439.8082480000001	72	80570.187359	919.786031455556
d0ae9102-d82e-4ead-9890-ef022d453ca8	2023-12-18	96ddb5bd-e6dd-4d1b-9d38-6e8e582bf132	Asia	Home & Kitchen	3	471.36	403.814112	1211.442336	979.1561135391636	Christina Thompson	1	1211.442336	377	1211.442336	53	64491.182614000005	1021.7261378833904
559911a8-299d-4640-a3ca-3e19068d0bed	2023-12-19	fc46d2cd-4162-44f4-94d8-6601ba1f778d	Europe	Clothing	8	239.07	235.699113	1885.592904	1636.2088405163338	Jason Nelson	1	1885.592904	376	1885.592904	70	87933.283392	1049.1629849529377
c33f0251-6f8b-4363-ac1f-4db94cca9134	2023-12-27	26579c7e-5067-4d40-a34a-21251e845cb2	North America	Toys	6	383.96	321.604896	1929.629376	1679.4894553342149	Caitlyn Boyd	1	1929.629376	368	1929.629376	58	71709.8323	1035.5858485437743
def8d83b-58b2-484f-9031-10d0db6d2972	2023-12-27	faf9d838-3378-48ca-8b1e-ce2affe23e77	Asia	Home & Kitchen	6	243.47	183.284216	1099.705296	871.8579333148244	Charles Smith	1	1099.705296	368	1099.705296	70	95387.089343	1149.437576059358
490a3ba2-c816-4b06-89fa-7960f59c354a	2023-12-28	5e0515c3-18a2-4b19-b572-2b195c1452ff	Australia	Beauty	1	84.92	81.370344	81.370344	17.953350780453583	Caitlyn Boyd	1	81.370344	367	81.370344	58	71709.8323	1035.5858485437743
a7dc88f8-44e0-4b0b-9d58-c101e073ce93	2023-12-28	8088b25b-241a-40f9-af60-8c3cb35a41a7	Australia	Clothing	9	85.13	80.68621399999999	726.1759259999999	520.2737126621299	Sandra Luna	1	726.1759259999999	367	726.1759259999999	56	72688.198308	1090.9576938669472
d1448933-fb31-426d-8c86-53429f4d1e8c	2023-12-28	c91ca00e-a7c9-4332-bbaf-0fdb62057ab0	Europe	Books	9	449.35	448.81078	4039.29702	3770.992546373473	Crystal Williams	1	4039.29702	367	4039.29702	65	72555.900913	927.0834787540324
6b113256-fd29-49dc-b326-c7c83f965ffc	2023-12-28	24dcf568-8115-4232-8cc4-7b98a15af584	Australia	Electronics	10	205.53	184.648152	1846.48152	1597.793790872335	Emily Matthews	1	1846.48152	367	1846.48152	72	80570.187359	919.786031455556
6cbe5fb9-a21f-47ac-a765-9a1f24bcd86c	2023-12-31	19aa4db6-02c4-43a3-ab4d-10d6db404b65	North America	Toys	3	322.24	291.72387200000003	875.1716160000001	658.8234463174133	Steven Coleman	1	875.1716160000001	364	875.1716160000001	59	68355.922945	964.8650638967956
2caea0ca-072f-4b75-b109-708e081f46c3	2024-01-01	e6b74bc2-88a3-4153-a1c9-4c9aff9f9cfb	Australia	Books	9	127.63	98.581412	887.232708	670.1567860974751	Crystal Williams	1	887.232708	363	887.232708	65	72555.900913	927.0834787540324
0bf7f031-e98c-452a-a105-866e0f8c54e7	2024-01-01	a7e56a21-062c-4938-a2b8-e673ca24f70b	South America	Electronics	7	16.28	14.671536	102.700752	27.03527494997421	Kristen Ramos	1	102.700752	363	102.700752	62	73461.618973	988.8412277570784
87c4d1ff-3814-4ef1-a54d-eaf0cb7eb0a9	2024-01-02	5e0aaf7c-46e4-436f-bc17-a09ac62e6ca3	Australia	Beauty	5	17.11	16.078267	80.391335	17.570880987340786	Kristen Ramos	1	80.391335	362	80.391335	62	73461.618973	988.8412277570784
7a27571a-e637-45fa-aa9c-7716d93e766a	2024-01-02	402a976a-69a3-436f-96aa-2b3876eace74	North America	Books	8	195.29	181.365823	1450.9265839999998	1211.0484991539197	Sandra Luna	1	1450.9265839999998	362	1450.9265839999998	56	72688.198308	1090.9576938669472
39ef1db6-06d1-43f9-a868-dc4ae1b93d43	2024-01-03	58ce3683-1017-4c4e-83f9-3600100cda9d	South America	Electronics	10	404.48	389.7164800000001	3897.164800000001	3629.507897326292	Bradley Howe	1	3897.164800000001	361	3897.164800000001	56	64186.396558	951.6581100155678
cdf9256b-5913-42a6-8ac7-ef3fca789549	2024-01-03	8de1766b-426b-4122-942c-01f6f11ced1c	South America	Beauty	7	282.45	209.5779	1467.0453	1226.7312305125558	Caitlyn Boyd	1	1467.0453	361	1467.0453	58	71709.8323	1035.5858485437743
4354b576-d9b4-4ed1-8ab7-6801124c4510	2024-01-07	fb595f5b-96cc-4ddb-9389-7ddfb0b95423	Australia	Clothing	8	394.04	367.875744	2943.005952	2681.179670495058	Susan Edwards	1	2943.005952	357	2943.005952	68	86058.98736700001	1063.159646603474
984fe30d-8bd7-4905-8223-e2bd683ea773	2024-01-09	46e99656-3291-4510-b60c-342ec19705d0	South America	Books	9	421.72	316.627376	2849.646384	2588.5821740233614	Caleb Camacho	1	2849.646384	355	2849.646384	66	91544.242731	1177.604080808591
68784433-42bb-4d65-b547-5f844eb83ef6	2024-01-11	779e8163-c7e6-4058-9413-212745202720	Asia	Books	6	376.19	348.502416	2091.014496	1838.3483494039003	Steven Coleman	1	2091.014496	353	2091.014496	59	68355.922945	964.8650638967956
2fd58cdf-9e2a-41b1-bfa5-c51ef1bc76dd	2024-01-15	6ad75fce-78c2-4671-ba0b-cae9b92cfb0f	Asia	Home & Kitchen	2	143.44	113.24588	226.49176	99.82560038923998	Steven Coleman	1	226.49176	349	226.49176	59	68355.922945	964.8650638967956
642cbe37-4464-4847-9ac3-fe062ee76e1f	2024-01-15	57bd971c-5368-41d5-8bcc-fa32bc926465	South America	Toys	7	49.45	35.282575	246.978025	114.15129325857802	Roger Brown	1	246.978025	349	246.978025	54	68595.667163	1076.1212096324236
0cc58b6b-2eaf-4914-a0a2-4b056be41e5b	2024-01-16	2c26e559-5f2c-4fa2-8522-18e4a5f4c425	South America	Sports	7	411.92	337.403672	2361.825704	2105.609596125275	Caleb Camacho	1	2361.825704	348	2361.825704	66	91544.242731	1177.604080808591
9e20bbee-b100-4378-a1ad-7156907a3fa6	2024-01-20	81295c8d-4488-43a6-8613-eb42d846a7e3	Europe	Toys	5	119.23	116.96463	584.8231499999999	392.1238353603084	Diane Andrews	1	584.8231499999999	344	584.8231499999999	58	66389.094387	950.0340815608216
e7185c8d-3f44-48f4-ae1d-ae0082e42982	2024-01-23	e9aba1f9-dba6-41c5-91d8-d05ccf5323bd	Australia	Home & Kitchen	2	194.63	189.491768	378.983536	215.53697715236984	Caleb Camacho	1	378.983536	341	378.983536	66	91544.242731	1177.604080808591
f84f9bc5-69d2-4ff0-a006-1c7f3a6acc9a	2024-01-23	3a6d779c-8aa5-4e2f-be18-b70ada57fdf3	South America	Beauty	2	451.26	397.78569	795.57138	584.4436850793481	Steven Coleman	1	795.57138	341	795.57138	59	68355.922945	964.8650638967956
7eb67f68-ffaf-40f9-a76f-1330e595ef11	2024-01-25	46f8163e-c0cf-4370-8a12-45d60eff0255	Europe	Clothing	2	53.43	42.396705	84.79341	19.31587332046331	Mary Scott	1	84.79341	339	84.79341	63	77562.23517100001	1033.152899764227
67c997a5-603f-4509-a421-2236e3dd20d5	2024-01-28	7b046c06-1e8e-44ab-856f-21620bc812c4	Australia	Books	5	73.35	62.618895	313.094475	163.24548725232123	Joseph Brooks	1	313.094475	336	313.094475	60	60657.854394	824.8550359343124
e8b03586-d124-49a3-9543-3cb9748a2dfd	2024-01-30	af754ceb-47bf-4c64-980c-bef123dbb956	Asia	Clothing	3	487.23	420.674382	1262.023146	1027.938018850704	Kristen Ramos	1	1262.023146	334	1262.023146	62	73461.618973	988.8412277570784
2aa6ac4e-be97-480d-b6bc-7f4a089dadb6	2024-02-03	69938caf-4952-4b27-b98e-5322acf04270	Asia	Toys	7	111.14	78.73157599999999	551.1210319999999	362.22569610748553	Johnny Marshall	1	551.1210319999999	330	551.1210319999999	61	67804.798966	913.3835523608234
c7ab35ef-6611-4c4e-b389-1be94eabb946	2024-02-06	cb0e80c4-f4c6-4dec-b25d-904ffabeadbe	Asia	Clothing	10	52.66	48.905342	489.05342	308.0364973216863	Johnny Marshall	1	489.05342	327	489.05342	61	67804.798966	913.3835523608234
9d6ff473-4177-4d67-a789-83e54fce8865	2024-02-06	4a7f0baa-7dcb-4d0b-811c-692347987fff	Australia	Toys	9	347.94	283.536306	2551.826754	2293.523778657867	Caleb Camacho	1	2551.826754	327	2551.826754	66	91544.242731	1177.604080808591
2e74c9af-6f18-41d7-8cb1-0bef8b4a1fe2	2024-02-06	0fa577ec-e90c-42ac-8fd7-5e8db28f3d4e	Asia	Sports	1	216.57	158.78912400000002	158.78912400000002	56.50949501449276	Sandra Luna	1	158.78912400000002	327	158.78912400000002	56	72688.198308	1090.9576938669472
33856d6c-6755-4af4-b6ee-4a34f5a17ae7	2024-02-08	d1f46aa7-c1b3-4398-88a3-1e4dd0ab6ab1	South America	Electronics	7	105.58	79.12165200000001	553.851564	364.6364486981655	Joseph Brooks	1	553.851564	325	553.851564	60	60657.854394	824.8550359343124
28feb809-c11c-40ed-8483-0a932d66cf3e	2024-02-14	94ebabae-e0c4-4bd2-b0fb-6a2ce3054cfb	Australia	Books	2	69.4	50.77304000000001	101.54608000000002	26.510182564102564	Christina Thompson	1	101.54608000000002	319	101.54608000000002	53	64491.182614000005	1021.7261378833904
b8a76c8b-97c2-43a1-b8ff-9abd3a44623c	2024-02-16	12dbcb29-aca1-491e-83c8-3481e66c8e7f	South America	Toys	1	38.55	35.40432	35.40432	3.8833798290598263	Joseph Brooks	1	35.40432	317	35.40432	60	60657.854394	824.8550359343124
fbd98bb4-8196-4b94-a415-0ce3f5678f49	2024-02-16	a67d7e81-5783-489f-b9d8-e9aef7a7f7cb	Europe	Home & Kitchen	3	138.05	122.25708	366.77124	205.6381058290133	Charles Smith	1	366.77124	317	366.77124	70	95387.089343	1149.437576059358
5baa4776-1c08-4efe-b8da-a4946266b46c	2024-02-17	9d25e8fd-468a-459f-8b0d-d2c2cd15bfdf	Europe	Beauty	4	86.99	82.17075399999999	328.68301599999995	175.35791640584034	Crystal Williams	1	328.68301599999995	316	328.68301599999995	65	72555.900913	927.0834787540324
02716b45-640a-4d78-a34b-3995352a4fd8	2024-02-19	be73ab95-ea18-4615-9da7-dc7290cc3b8b	South America	Sports	2	425.14	305.420576	610.841152	415.3970002114289	Jason Nelson	1	610.841152	314	610.841152	70	87933.283392	1049.1629849529377
a34733a6-1fc0-4b22-bacc-e79428423713	2024-02-25	62b316ac-b034-42c1-be1f-0768af0fda9c	Asia	Sports	7	486.75	376.890525	2638.233675	2379.07006913348	Jason Nelson	1	2638.233675	308	2638.233675	70	87933.283392	1049.1629849529377
4db6078a-c426-43e3-96e3-030aa16d616c	2024-03-01	c56fc223-efca-4e4d-ad78-57ecc62e6023	South America	Electronics	8	262.72	204.52752	1636.22016	1391.763739400296	Johnny Marshall	1	1636.22016	303	1636.22016	61	67804.798966	913.3835523608234
8cf0dd98-9ccf-4907-b89d-10aece81938a	2024-03-02	e3e66da6-4b65-4764-9fed-8f547064b39b	Australia	Toys	7	307.42	215.624388	1509.370716	1267.9447949200085	Jason Nelson	1	1509.370716	302	1509.370716	70	87933.283392	1049.1629849529377
aea3a729-3fb8-4ae3-9ad8-4cffccbb702a	2024-03-02	64f50245-1c34-42bc-861c-df121780e9c1	South America	Sports	3	343.44	315.1062	945.3186	724.9286529223883	Bradley Howe	1	945.3186	302	945.3186	56	64186.396558	951.6581100155678
34adc3e8-19fc-4dc8-8484-c17500bafb78	2024-03-04	af01fd28-d2d9-4bea-b37a-2d313ed64480	Asia	Clothing	1	74.1	52.92221999999999	52.92221999999999	8.228173889029641	Joseph Brooks	1	52.92221999999999	300	52.92221999999999	60	60657.854394	824.8550359343124
cf0c5248-aef3-4a5c-af97-ef57778ed958	2024-03-06	8555b800-e5d3-4044-854f-0b3a50b236ea	South America	Home & Kitchen	1	218.38	214.733054	214.733054	91.8318097234432	Emily Matthews	1	214.733054	298	214.733054	72	80570.187359	919.786031455556
ee082c55-9968-4391-babf-c3eb62ffcbe4	2024-03-09	230016c6-684f-4491-8e1d-c05792947edd	Europe	Beauty	8	323.51	272.136612	2177.092896	1923.2133937085343	Susan Edwards	1	2177.092896	295	2177.092896	68	86058.98736700001	1063.159646603474
0959f396-c600-41f8-b44c-b516a1be0513	2024-03-11	f69bd21f-bf9b-4a3c-8381-e27446383626	South America	Books	5	403.93	316.479155	1582.395775	1339.174782838918	Caleb Camacho	1	1582.395775	293	1582.395775	66	91544.242731	1177.604080808591
8d3146ed-3231-4926-aa44-d6d01e11a404	2024-03-12	f40225f4-f0fc-438e-b836-b693813c5b3b	South America	Beauty	1	171.41	131.454329	131.454329	41.25649106943872	Bradley Howe	1	131.454329	292	131.454329	56	64186.396558	951.6581100155678
4cff04b9-6742-40ce-ac3d-2a78edb6f7ee	2024-03-12	581c4fea-d0eb-4bbb-b148-68681e5427d2	North America	Clothing	8	393.54	283.191384	2265.531072	2010.489861598109	Diane Andrews	1	2265.531072	292	2265.531072	58	66389.094387	950.0340815608216
d894e614-5017-44d6-a057-cb9a9e1b28ac	2024-03-13	2a0d4726-eb2b-4019-a475-82da04c557a6	Australia	Clothing	1	463.61	347.058446	347.058446	189.8476985819895	Caleb Camacho	1	347.058446	291	347.058446	66	91544.242731	1177.604080808591
fdeae106-74c9-4cb1-9423-2bed43afdc12	2024-03-14	07f36ccc-53bd-4b1a-a422-f41d1f23697b	South America	Electronics	5	74.26	58.494602	292.47301	147.519344935818	Roger Brown	1	292.47301	290	292.47301	54	68595.667163	1076.1212096324236
67454061-4c03-4f96-bd76-e86dc50bcb1d	2024-03-15	ffd4bb27-4d55-446d-9cbb-84099e58bda3	Europe	Clothing	8	35.44	26.186616	209.492928	88.3217046788131	Caitlyn Boyd	1	209.492928	289	209.492928	58	71709.8323	1035.5858485437743
79ade4c7-28d5-4205-a082-820393c52bea	2024-03-17	5ab4367e-8bba-407a-baab-919d1b1486f9	Europe	Toys	4	439.14	362.114844	1448.459376	1208.6482210331126	Charles Smith	1	1448.459376	287	1448.459376	70	95387.089343	1149.437576059358
6ed4a42a-b21c-4ee7-af30-195ed318bf20	2024-03-19	384f6a20-4ed7-46f5-b694-6675cf176bb5	Europe	Beauty	8	41.91	35.112198	280.897584	138.84358177485586	Mary Scott	1	280.897584	285	280.897584	63	77562.23517100001	1033.152899764227
433aa504-2038-4ccd-9a22-de184327dc88	2024-03-22	d82e714e-3480-403b-8c2b-881e7f84592a	Europe	Toys	2	422.64	367.189632	734.379264	527.8202495708379	Diane Andrews	1	734.379264	282	734.379264	58	66389.094387	950.0340815608216
65b5ae24-0624-4b05-bb37-ad538482bbd4	2024-03-25	43072b8a-92b8-4564-a59b-e528555cff17	Asia	Beauty	10	478.87	449.227947	4492.27947	4222.16628025308	Charles Smith	1	4492.27947	279	4492.27947	70	95387.089343	1149.437576059358
80e9b781-5e81-46ab-8d94-fe7a481e3cc0	2024-03-28	7f59be10-39c3-4340-93ed-b9035005863e	South America	Beauty	6	264.2	250.09172	1500.5503199999998	1259.3508215109623	Roger Brown	1	1500.5503199999998	276	1500.5503199999998	54	68595.667163	1076.1212096324236
9c287e41-8c99-436b-bfc6-5f4b0cc238e9	2024-03-30	930f9f03-7906-4f7c-b313-66293a0b3a2c	North America	Toys	1	354.02	339.044954	339.044954	183.4983402458136	Steven Coleman	1	339.044954	274	339.044954	59	68355.922945	964.8650638967956
d196497d-a106-422f-bca9-733cb50a6907	2024-03-30	2b221b70-ced6-4aa7-87c1-c1fd19d9e277	Asia	Books	10	83.89	62.66583	626.6583	429.6269212859614	Caleb Camacho	1	626.6583	274	626.6583	66	91544.242731	1177.604080808591
716abdd1-1041-4d31-8cee-f88844aa1f75	2024-04-03	fe60687a-dd89-42b2-a817-1c2314742e3f	North America	Electronics	1	252	199.8108	199.8108	81.94222991977345	Emily Matthews	1	199.8108	270	199.8108	72	80570.187359	919.786031455556
bf80b407-b8a9-47fb-82fc-8183bc3f293a	2024-04-04	55779bb6-fe68-4f0b-a127-bb51d76b5025	Asia	Beauty	9	311.32	253.507876	2281.570884	2026.32735198228	Michelle Garza	1	2281.570884	269	2281.570884	65	76798.491008	980.44596940906
f87b91e0-8486-4aa6-9fdf-8e0b6088fc76	2024-04-07	1443ed35-929a-4ef2-b511-af85ee1d82f1	Australia	Books	1	366.45	332.37015	332.37015	178.24534128217022	Caleb Camacho	1	332.37015	266	332.37015	66	91544.242731	1177.604080808591
3b0197c1-1421-4d40-9271-4364ed1da479	2024-04-10	29db9bf0-e00c-4c26-a67e-fbb4eaff4a4a	Europe	Beauty	3	249.75	178.496325	535.488975	348.470857792582	Sandra Luna	1	535.488975	263	535.488975	56	72688.198308	1090.9576938669472
3b370b29-659e-40f4-b8e7-30bee26a70ef	2024-04-10	9fb9f398-73e5-443f-922a-c8a3db795542	Asia	Toys	3	478.27	454.691289	1364.073867	1126.6908784682491	Michelle Garza	1	1364.073867	263	1364.073867	65	76798.491008	980.44596940906
db39d7a9-8186-4366-bafb-b2c9d3da099c	2024-04-12	445274fd-ea39-428d-8e59-0ca4f9ef1941	South America	Electronics	2	143.87	143.222585	286.44517	142.98587716682528	Sandra Luna	1	286.44517	261	286.44517	56	72688.198308	1090.9576938669472
3926fb61-85b9-4ffe-aec9-f250fe03bda8	2024-04-19	736ad6f3-66af-43eb-a80e-d0762369841f	Europe	Beauty	6	206.36	148.04266400000003	888.2559840000001	671.1156451826828	Christina Thompson	1	888.2559840000001	254	888.2559840000001	53	64491.182614000005	1021.7261378833904
4a6889ff-4a97-459f-ad48-113f8c51ce80	2024-04-20	cf6c685c-c87c-4fd7-9325-40a3e7902b78	South America	Sports	4	384.3	346.33116	1385.32464	1147.308620207206	Sandra Luna	1	1385.32464	253	1385.32464	56	72688.198308	1090.9576938669472
5a75873a-ef94-4932-b542-db8f4f328c13	2024-04-23	3b6beae9-23fb-417e-9866-4b9af6053ab5	North America	Beauty	9	22.34	19.947386	179.526474	69.02824417295501	Jason Nelson	1	179.526474	250	179.526474	70	87933.283392	1049.1629849529377
1622df55-10c2-4e45-b837-b5c304c22b26	2024-04-26	ea1a5878-8bff-4245-9312-6d5e456d9d1e	North America	Toys	7	449.66	395.5659020000001	2768.961314	2508.590893207688	Sandra Luna	1	2768.961314	247	2768.961314	56	72688.198308	1090.9576938669472
a6ad1d77-5776-4989-b327-f7d8b6621db1	2024-04-28	0b818008-ec15-4f19-8edc-e5669cb06f11	Australia	Sports	10	317.79	275.23791900000003	2752.379190000001	2492.1561409312662	Joseph Brooks	1	2752.379190000001	245	2752.379190000001	60	60657.854394	824.8550359343124
d0282bae-eec4-4feb-aa53-47854949d6e9	2024-04-28	03d3c64f-4574-4891-ad1e-cddc26635d94	Europe	Electronics	10	123.66	90.803538	908.03538	689.736654160977	Crystal Williams	1	908.03538	245	908.03538	65	72555.900913	927.0834787540324
2ce4f285-12bb-455e-afe4-07791162ae5a	2024-05-08	a9b1e8c4-6b2d-4bb7-9724-56884d163664	South America	Sports	7	35.69	32.781265	229.468855	101.87983359327217	Bradley Howe	1	229.468855	235	229.468855	56	64186.396558	951.6581100155678
c1a2d4b4-6227-459c-8d88-21fdf250f9d9	2024-05-09	cb55196d-ebe0-42fb-bfda-da77ba8efb46	Asia	Books	10	479.28	358.453512	3584.53512	3318.473994456304	Michelle Garza	1	3584.53512	234	3584.53512	65	76798.491008	980.44596940906
63819a88-35ed-4a14-bfb3-cacf397bcece	2024-05-11	b6d866c9-c37b-44c6-b11c-98dd496fee60	South America	Books	4	463.43	436.319345	1745.27738	1498.518334077593	Joseph Brooks	1	1745.27738	232	1745.27738	60	60657.854394	824.8550359343124
c010a100-9b34-4d5b-9876-18370c13e189	2024-05-12	287529db-82b0-40ec-9a99-b7376da49718	Australia	Home & Kitchen	5	70.01	66.36247900000001	331.81239500000004	177.80339291134837	Kristen Ramos	1	331.81239500000004	231	331.81239500000004	62	73461.618973	988.8412277570784
aac83f6d-bf03-4aa8-8907-1cfcebeb5cc8	2024-05-14	9bbe257a-87d2-45f8-a29e-178e761e5267	Europe	Clothing	7	336.43	264.97226800000004	1854.8058760000004	1605.9689079698417	Susan Edwards	1	1854.8058760000004	229	1854.8058760000004	68	86058.98736700001	1063.159646603474
3a3623fa-1b1f-4bb4-8eb9-4240b3f47c0e	2024-05-14	da3cb604-d522-41dd-809e-21af1e8d19ad	North America	Toys	8	449.32	423.618896	3388.951168	3124.023778381488	Michelle Andersen	1	3388.951168	229	3388.951168	60	66978.268402	921.082547231716
14f0253f-6846-4c6c-a640-9857c1a87cf5	2024-05-19	df382ccf-243d-419a-91d1-89e5cbd66d82	South America	Sports	1	137.86	111.73553	111.73553	31.280799297235035	Charles Smith	1	111.73553	224	111.73553	70	95387.089343	1149.437576059358
6f2a06d2-e398-4376-af08-13d22871daf8	2024-05-20	fa953990-9c14-4d8f-bbac-df5132e81ee0	North America	Electronics	5	255.59	239.692302	1198.46151	966.6552567360396	Joseph Brooks	1	1198.46151	223	1198.46151	60	60657.854394	824.8550359343124
ad4b4e71-a08f-4500-b1c0-4b58ce148d7d	2024-05-20	36445a91-ebc1-4fe4-b3d5-86eb1b0b890e	Australia	Books	3	235.3	206.02868	618.08604	421.9118437896341	Christina Thompson	1	618.08604	223	618.08604	53	64491.182614000005	1021.7261378833904
5f5b0f94-f6e3-4d7b-8108-3a11e4aeea5b	2024-05-21	f338dff2-e09f-4905-a7dd-80d0e93ca0b1	Australia	Clothing	10	187.58	165.089158	1650.89158	1406.1083437857153	Joseph Brooks	1	1650.89158	222	1650.89158	60	60657.854394	824.8550359343124
bcc10ad3-714d-467e-b452-c498e7c79bff	2024-05-23	c1c64c78-4ed6-4761-9d9b-b6dea74c5079	Australia	Toys	1	293.38	217.306566	217.306566	93.56272111645124	Charles Smith	1	217.306566	220	217.306566	70	95387.089343	1149.437576059358
47465813-1801-4f50-b6cc-15cd2203c065	2024-05-24	02a440b0-542a-4fe5-97c9-abf80f851f74	Asia	Sports	10	328.55	241.51710500000004	2415.1710500000004	2158.339053020088	Steven Coleman	1	2415.1710500000004	219	2415.1710500000004	59	68355.922945	964.8650638967956
70094bad-016e-47af-abad-033d9237446a	2024-05-24	ec33c7ad-2d40-44d6-89cd-87ac69ed969c	South America	Electronics	10	184.4	175.2722	1752.722	1505.8145380703509	Caleb Camacho	1	1752.722	219	1752.722	66	91544.242731	1177.604080808591
984da73c-7ec0-42e4-ae7d-cd99349a0273	2024-05-25	8d92abb3-6e6a-4319-9ddf-908d892d970b	Australia	Toys	9	63.16	51.336448	462.028032	284.8496633226215	Adam Smith	1	462.028032	218	462.028032	55	62372.113224	936.3944649146875
513e2701-956a-400c-ac54-30229020bbac	2024-05-26	ea75e4fd-3449-4fbd-87b1-67a58c819143	South America	Home & Kitchen	8	363.63	323.776152	2590.209216	2331.519417342281	Emily Matthews	1	2590.209216	217	2590.209216	72	80570.187359	919.786031455556
4dd2fb3b-bfc7-4674-b272-ec3310975ba2	2024-05-28	e586d917-0d07-400f-8632-68de84d00911	South America	Toys	9	201.9	167.1732	1504.5588	1263.2579916859122	Caitlyn Boyd	1	1504.5588	215	1504.5588	58	71709.8323	1035.5858485437743
dd4c10ab-a0f8-436a-91e3-71728c69eeb3	2024-05-29	29b5d56b-1636-409e-97de-b5e37e70c471	Australia	Books	5	281.47	225.11970600000004	1125.5985300000002	896.660131513241	Caitlyn Boyd	1	1125.5985300000002	214	1125.5985300000002	58	71709.8323	1035.5858485437743
89164799-16c3-4843-bb49-49f75691dd34	2024-05-31	6dbb2d3a-21e6-465f-b996-d0a130912f57	Europe	Toys	5	152.84	134.31579200000002	671.57896	470.3145869479741	Charles Smith	1	671.57896	212	671.57896	70	95387.089343	1149.437576059358
32a695a3-91db-4c15-bc4a-7a302246138d	2024-06-02	9e6d2c5a-60dd-46f7-bcd8-c596b1323f19	South America	Beauty	3	202.34	151.85617	455.56851	279.3467437923565	Bradley Howe	1	455.56851	210	455.56851	56	64186.396558	951.6581100155678
92dd8937-57aa-46cc-96cb-08472dd01b45	2024-06-04	e49aa5b4-4b66-4fed-8968-b86873a67dd0	Asia	Beauty	10	456.63	326.26213499999994	3262.6213499999994	2998.4928122259635	Caitlyn Boyd	1	3262.6213499999994	208	3262.6213499999994	58	71709.8323	1035.5858485437743
7073e670-5019-4915-878b-b78492ec6349	2024-06-05	ca38634a-3255-46d2-b4df-65b5752e7377	Asia	Sports	6	258.21	240.677541	1444.065246	1204.3744321835445	Kristen Ramos	1	1444.065246	207	1444.065246	62	73461.618973	988.8412277570784
4192fc88-a798-4d04-bb9a-f56550e0d421	2024-06-07	3e1dff9e-7f09-4f06-bd39-e1e415c5c91b	Australia	Sports	1	329.12	306.048688	306.048688	157.83391343464572	Roger Brown	1	306.048688	205	306.048688	54	68595.667163	1076.1212096324236
8aaa1022-c5a2-4450-8424-511a1671ea5a	2024-06-07	7063c3e9-ed3a-4808-85b2-e34c2df41f46	South America	Beauty	6	194.82	163.395534	980.373204	758.1268302241567	Jason Nelson	1	980.373204	205	980.373204	70	87933.283392	1049.1629849529377
f88e7d24-a8bd-4094-9960-1352ba506b04	2024-06-07	a38159f6-9d08-4ea5-ac3e-396c36dfc914	Australia	Clothing	1	422.84	296.537692	296.537692	150.58942346963283	Charles Smith	1	296.537692	205	296.537692	70	95387.089343	1149.437576059358
f493721a-ca1a-4c96-9946-5ebaf3567f4e	2024-06-09	0daf272a-bb29-447b-9d97-d55e1a6d5063	Australia	Beauty	7	243.08	196.384332	1374.690324	1136.9903388704026	Jason Nelson	1	1374.690324	203	1374.690324	70	87933.283392	1049.1629849529377
d3b54a1c-0936-4a80-b209-43e1dbe6f06c	2024-06-09	1367cbd3-2885-4de9-ba84-383bbe1a4c76	South America	Books	4	251.53	176.272224	705.088896	500.9165163162101	Kristen Ramos	1	705.088896	203	705.088896	62	73461.618973	988.8412277570784
ddc310c8-7dce-4b29-b178-caa093b6d5e6	2024-06-09	09a75e16-9443-4247-8d29-9096db8645cd	Asia	Beauty	10	241.77	230.962881	2309.62881	2054.0399415221605	Joseph Brooks	1	2309.62881	203	2309.62881	60	60657.854394	824.8550359343124
972d7dec-5b02-4514-bdbe-20654039497b	2024-06-12	ff930cb1-6ac4-4ba0-a073-93180c1206d0	Europe	Sports	6	354.17	299.167399	1795.004394	1547.274068294074	Mary Scott	1	1795.004394	200	1795.004394	63	77562.23517100001	1033.152899764227
643580bf-878c-4327-95d3-3358097b5547	2024-06-12	80fc4760-c1a8-4fa2-a6b9-c7cd5bff40ce	North America	Clothing	1	478.44	464.278176	464.278176	286.7678812188874	Johnny Marshall	1	464.278176	200	464.278176	61	67804.798966	913.3835523608234
c4ceca6f-2702-4cdd-bef7-7ca2ff143530	2024-06-14	4503e3d8-7c1f-42bd-a927-1d559bb87405	Europe	Electronics	1	485.72	446.230964	446.230964	271.4235193335684	Emily Matthews	1	446.230964	198	446.230964	72	80570.187359	919.786031455556
d6b59e11-e4ea-4bc5-a764-1e8ffd04429d	2024-06-15	6086bcfe-032d-4cf0-afe9-304c3404838c	South America	Home & Kitchen	8	243.79	239.791844	1918.334752	1668.3855993074567	Michelle Garza	1	1918.334752	197	1918.334752	65	76798.491008	980.44596940906
2208f8c7-ce66-4d82-b654-5d728409228a	2024-06-17	a2fbb36e-fbf3-45f7-96b9-1dc0c8cd9d91	Asia	Clothing	3	474.03	419.232132	1257.6963959999998	1023.7585968109815	Michelle Garza	1	1257.6963959999998	195	1257.6963959999998	65	76798.491008	980.44596940906
bc1b5654-cbeb-46e1-add2-32220404d032	2024-06-18	46149825-931a-4a8c-b73e-41f1d34aa4a0	South America	Electronics	10	429.2	421.2598	4212.598	3943.558218164632	Kristen Ramos	1	4212.598	194	4212.598	62	73461.618973	988.8412277570784
e2aadaed-30aa-49f7-b532-59c53238ae59	2024-06-19	03728b15-126a-493c-91bf-ecea186e239f	Australia	Home & Kitchen	6	70.79	69.83433500000001	419.00601000000006	248.53977322213183	Caitlyn Boyd	1	419.00601000000006	193	419.00601000000006	58	71709.8323	1035.5858485437743
5abe6042-7882-4b19-9a60-a1f492c57eba	2024-06-27	d24516bb-4925-40c9-a4a0-35bd7fb7dcf0	Asia	Sports	7	299.33	211.177315	1478.241205	1237.6263855130542	Michelle Andersen	1	1478.241205	185	1478.241205	60	66978.268402	921.082547231716
b79e0e44-d45b-4bed-b0c2-d1e171e3fb5c	2024-06-28	5d5e32e2-280b-48a6-a3c7-cd6a026fc815	South America	Beauty	3	129.82	106.06293999999998	318.18882	167.18805120728925	Diane Andrews	1	318.18882	184	318.18882	58	66389.094387	950.0340815608216
669f5441-07fb-40fb-a2c1-75050d1933c9	2024-06-30	8ac2e0e5-0f07-45f5-ab5c-32a6f49e813e	North America	Electronics	8	319.33	246.937889	1975.503112	1724.6073422319082	Steven Coleman	1	1975.503112	182	1975.503112	59	68355.922945	964.8650638967956
ee84f947-c007-4f47-b305-8776fc3748ce	2024-07-01	a349a57b-b9ee-4a27-a0cb-2accd55b9c9b	Asia	Home & Kitchen	1	395.2	394.0144	394.0144	227.83371674398987	Caleb Camacho	1	394.0144	181	394.0144	66	91544.242731	1177.604080808591
5629c97d-e5ba-4ff6-82ac-64a23f4936be	2024-07-01	6eea9d45-3257-42ee-832f-9f92345de2ea	Australia	Clothing	1	120.24	102.8052	102.8052	27.08508509980113	Crystal Williams	1	102.8052	181	102.8052	65	72555.900913	927.0834787540324
d5fdf3d5-a820-4c8a-a9b0-7be11921f11d	2024-07-02	3cd9b0e6-6b85-4298-80d0-fe6bf8dc5132	Europe	Clothing	7	270.05	234.646445	1642.525115	1397.9306642680892	Michelle Garza	1	1642.525115	180	1642.525115	65	76798.491008	980.44596940906
3e7a9e9c-4fbe-41a4-a658-8aa05d7648a6	2024-07-05	6c0bfe51-0f94-483f-8efc-e4c69168902b	Europe	Clothing	6	95.49	71.378775	428.27265	256.2894157216288	Michelle Garza	1	428.27265	177	428.27265	65	76798.491008	980.44596940906
e3ff5c49-e6de-42a7-878a-dbe45c88d764	2024-07-06	e2b2dbfa-0255-49b8-9235-bbc1ddf665c1	Europe	Books	2	253.99	202.379232	404.758464	236.69731801096165	Jason Nelson	1	404.758464	176	404.758464	70	87933.283392	1049.1629849529377
0733d93d-41f3-42b5-861e-293c18b9af4f	2024-07-08	ca33e728-48a4-451b-b104-fdaee5498cec	Asia	Clothing	7	84.87	80.38886400000001	562.7220480000001	372.4847092576066	Johnny Marshall	1	562.7220480000001	174	562.7220480000001	61	67804.798966	913.3835523608234
924e66d5-2a6e-40cb-aba1-4a1920062e84	2024-07-13	ba434c38-8e7a-4704-a8fb-037e2f150be3	North America	Clothing	9	146.35	143.36446	1290.28014	1055.2393100670358	Johnny Marshall	1	1290.28014	169	1290.28014	61	67804.798966	913.3835523608234
9c5961ae-943d-40fe-b49d-26de3a8f00d0	2024-07-15	1022715b-ea1f-4b67-a15b-0d039d1932e1	Asia	Beauty	5	123.23	97.425638	487.12819	306.3756148608535	Caleb Camacho	1	487.12819	167	487.12819	66	91544.242731	1177.604080808591
fdab0de9-ff1e-4149-a814-8fa349d71683	2024-07-19	b90ebe59-7175-406e-b474-7656d71a3e7a	Asia	Books	1	377.26	320.369192	320.369192	168.87290789350735	Christina Thompson	1	320.369192	163	320.369192	53	64491.182614000005	1021.7261378833904
99326907-eba8-4c14-8ba4-15f4c36a8c8e	2024-07-25	5f7feffc-ee48-4016-a0de-0e8ca741aa8d	Asia	Electronics	10	92.02	82.799596	827.99596	614.6554225235113	Steven Coleman	1	827.99596	157	827.99596	59	68355.922945	964.8650638967956
0fcbc535-23d2-465f-b6f9-ae0327b959ac	2024-07-25	9fdf1460-9ef7-490a-b3cb-6cd2f8a44eb0	South America	Clothing	7	70.41	68.36811	478.57677	299.01172047276003	Diane Andrews	1	478.57677	157	478.57677	58	66389.094387	950.0340815608216
4da1eb91-93d0-4d1e-8d2c-13e88087ef5a	2024-07-26	dd8ace36-8ffe-49be-95e6-7b68b5940ff8	North America	Sports	6	416.3	336.07899000000003	2016.4739400000003	1764.930361835238	Diane Andrews	1	2016.4739400000003	156	2016.4739400000003	58	66389.094387	950.0340815608216
3f06b878-d82e-4471-995f-15827b74ec27	2024-07-27	5f79c571-55fa-4c0b-b8d9-dc3869b72be3	Asia	Home & Kitchen	8	70.78	67.021582	536.172656	349.06606191848124	Joseph Brooks	1	536.172656	155	536.172656	60	60657.854394	824.8550359343124
249c75ea-8e6b-4b61-8ca0-b3693cbab68e	2024-07-28	0e923150-3a6c-416f-82d6-312317e177b1	Asia	Sports	9	62.49	47.317428	425.856852	254.2649219492304	Charles Smith	1	425.856852	154	425.856852	70	95387.089343	1149.437576059358
82d44359-9bc6-432e-b3c0-dff5c1f3f575	2024-07-28	2d13dd1b-0d2e-4fce-b955-e8fc9bf787d5	Asia	Beauty	9	215.46	165.537918	1489.841262	1248.9225585717982	Charles Smith	1	1489.841262	154	1489.841262	70	95387.089343	1149.437576059358
8c63052b-649e-4bc2-b521-c701eb1788f6	2024-07-30	a549ae55-2beb-4c7f-baf5-28ba2152995b	Australia	Sports	10	456.01	358.515062	3585.15062	3319.085281254054	Crystal Williams	1	3585.15062	152	3585.15062	65	72555.900913	927.0834787540324
e8215cea-9418-414b-b75c-f9919e1a2b3c	2024-07-30	cd2b8672-86ba-431f-aa1f-321b20080a04	Europe	Beauty	1	172.82	169.53642	169.53642	62.90303425246872	Susan Edwards	1	169.53642	152	169.53642	68	86058.98736700001	1063.159646603474
e796b1db-aed1-4f9d-8122-e1e19dc9a278	2024-07-30	c8d4c89b-e3d1-4d18-8110-52355495da86	Australia	Beauty	6	222.96	187.8438	1127.0628000000002	898.0641206818783	Caitlyn Boyd	1	1127.0628000000002	152	1127.0628000000002	58	71709.8323	1035.5858485437743
71a557b5-2544-4e14-ae2b-6b65e71351f1	2024-08-01	e0d9206c-bc4e-43bd-8685-cae99e1e1c92	Asia	Home & Kitchen	9	121.58	105.251806	947.266254	726.7717929772119	Susan Edwards	1	947.266254	150	947.266254	68	86058.98736700001	1063.159646603474
53250561-f709-455f-9c6a-e17d570a7e52	2024-08-02	f9afed72-335f-449f-b215-302f0492615a	South America	Beauty	10	111.27	81.839085	818.39085	605.6892048185882	Michelle Garza	1	818.39085	149	818.39085	65	76798.491008	980.44596940906
f2371ecf-7ec6-4d9a-9651-848f96ee5d22	2024-08-04	ecc7f22b-d586-4516-bb33-907f895da9dc	Asia	Toys	6	77.86	56.471858000000005	338.83114800000004	183.33268632033048	Susan Edwards	1	338.83114800000004	147	338.83114800000004	68	86058.98736700001	1063.159646603474
d3bda6c6-62cb-4de6-88b1-ce596af2799a	2024-08-05	3ff282e9-423b-4477-b682-a8dcc4a27dc8	Europe	Clothing	1	353.65	284.794345	284.794345	141.74630391305436	Steven Coleman	1	284.794345	146	284.794345	59	68355.922945	964.8650638967956
86088150-5f21-46bc-a10f-2890b7b191c4	2024-08-08	42e1e997-8310-4797-826f-4f1a6ac8702b	Australia	Books	9	242.62	201.690006	1815.210054	1567.0983477630705	Sandra Luna	1	1815.210054	143	1815.210054	56	72688.198308	1090.9576938669472
ddae4e82-b8d6-4450-b297-c331a583b87e	2024-08-11	bf436245-1864-41ec-92fb-677ec5b239c7	Australia	Sports	3	457.36	413.956536	1241.869608	1008.4837276369173	Roger Brown	1	1241.869608	140	1241.869608	54	68595.667163	1076.1212096324236
107414cc-0ed7-48bf-ac17-5af98862a9bd	2024-08-12	3944cdc2-6e1b-41fb-9add-00ab72469291	Asia	Beauty	1	121.6	117.50208	117.50208	34.09628783645657	Michelle Garza	1	117.50208	139	117.50208	65	76798.491008	980.44596940906
babc9b6c-43e0-44e8-84b0-8a160de0e02e	2024-08-13	35f78674-9a1c-4582-b3ad-d3aa5885e724	South America	Electronics	7	351.24	313.165584	2192.159088	1938.0752547651864	Adam Smith	1	2192.159088	138	2192.159088	55	62372.113224	936.3944649146875
f23d5361-0717-40fc-8d39-d9ec89517b5b	2024-08-14	2a129f52-fb3d-48c3-8dc8-6ba21aa94c2a	South America	Electronics	2	372.22	371.624448	743.2488960000001	535.9964014375105	Emily Matthews	1	743.2488960000001	137	743.2488960000001	72	80570.187359	919.786031455556
89871406-6020-429b-a5e6-119751c3e65f	2024-08-16	4d04c96b-5635-4dfb-ade7-797bdade9a72	North America	Toys	2	285.93	238.980294	477.960588	298.48531932815143	Crystal Williams	1	477.960588	135	477.960588	65	72555.900913	927.0834787540324
b8b6aa7f-adf0-4809-9049-b1ca647366b1	2024-08-20	adae3c4a-5ef0-4886-8753-8482321d8422	Australia	Toys	4	283.18	274.03328600000003	1096.133144	868.4361884536769	Johnny Marshall	1	1096.133144	131	1096.133144	61	67804.798966	913.3835523608234
f4590ec1-75e2-45a3-969d-b8d2cbd038c1	2024-08-21	c46bb23b-86b0-4172-b874-9d1d7929404a	Australia	Electronics	1	267.76	249.391664	249.391664	115.87005354920224	Johnny Marshall	1	249.391664	130	249.391664	61	67804.798966	913.3835523608234
53de74b8-2029-4a4f-9598-c400d028f1c1	2024-08-22	4bf6b8e3-4a49-400d-8692-34534b5588db	Europe	Home & Kitchen	5	13.25	10.437025	52.185125	8.020327268111032	Caitlyn Boyd	1	52.185125	129	52.185125	58	71709.8323	1035.5858485437743
296bb66f-f67e-4f28-9012-a49c491237e8	2024-08-25	9663c95c-9390-4b12-a9c2-3a3fc63aabd8	Europe	Electronics	9	208.21	151.306207	1361.755863	1124.4458821694404	Steven Coleman	1	1361.755863	126	1361.755863	59	68355.922945	964.8650638967956
7ad15131-c682-47e0-9cb7-776156b311e0	2024-08-26	065446b6-31f6-4940-8ab4-f368dfd554e1	Australia	Sports	7	9.53	7.037904999999999	49.26533499999999	7.208535443913263	Caleb Camacho	1	49.26533499999999	125	49.26533499999999	66	91544.242731	1177.604080808591
6c7a7754-9d5e-4e1d-b548-5dc307712006	2024-08-28	76171519-7715-4fa2-90f5-45099a17ec35	Asia	Books	4	14.44	12.168588	48.674352	7.04743675156076	Roger Brown	1	48.674352	123	48.674352	54	68595.667163	1076.1212096324236
ecf62f4f-3aec-4ac8-9102-ad7d888c1cda	2024-08-30	2b3ae79d-25c2-4235-8661-fd281a550e4e	North America	Home & Kitchen	7	115.93	93.219313	652.535191	453.0136527031036	Susan Edwards	1	652.535191	121	652.535191	68	86058.98736700001	1063.159646603474
4d2d2322-16f5-4df3-bcfc-f513a5579f7d	2024-09-02	1980e03a-0f02-416e-956f-74ebf9bff3b2	Asia	Books	1	249.21	215.392203	215.392203	92.27576801857674	Michelle Garza	1	215.392203	118	215.392203	65	76798.491008	980.44596940906
677413ad-db9f-4652-87a4-f0d8a9dd5eaf	2024-09-07	21c88814-9f29-4bfd-a37f-efc022596857	North America	Toys	5	381.41	327.89817700000003	1639.4908850000002	1394.9622878964758	Adam Smith	1	1639.4908850000002	113	1639.4908850000002	55	62372.113224	936.3944649146875
3c371de1-7920-4f9b-9194-dc419b8df1cb	2024-09-07	45736515-8733-49e5-a5e2-82ae228e0557	South America	Clothing	8	12.31	9.178336000000002	73.42668800000001	14.94266729111908	Susan Edwards	1	73.42668800000001	113	73.42668800000001	68	86058.98736700001	1063.159646603474
3a62684c-02aa-4c29-8ba0-f2b2e7346919	2024-09-08	37ef4504-0e5c-4269-b9d9-c90f30b94215	Europe	Books	9	15.46	10.979692	98.817228	25.281561978270588	Michelle Andersen	1	98.817228	112	98.817228	60	66978.268402	921.082547231716
e6e55e3a-bd6b-4f0b-bee6-294abd8c5c31	2024-09-08	c1cb0b24-5c62-48dd-b1a0-f37644e88dd8	Asia	Beauty	7	332.33	265.465204	1858.256428	1609.357242637217	Susan Edwards	1	1858.256428	112	1858.256428	68	86058.98736700001	1063.159646603474
bd002a21-81fe-4a70-bdc8-cf0928defbb7	2024-09-09	90ff1f83-1219-4293-b614-4f353971424a	Europe	Toys	4	294.99	210.150876	840.6035039999999	626.4315495553008	Diane Andrews	1	840.6035039999999	111	840.6035039999999	58	66389.094387	950.0340815608216
2581e437-f879-4d25-8b8e-1e90bb247dcf	2024-09-13	3219f00f-7bc5-4869-8079-d55cab3cf428	South America	Beauty	7	20.3	19.10839	133.75873	42.48076493926574	Crystal Williams	1	133.75873	107	133.75873	65	72555.900913	927.0834787540324
f0901680-2a71-444f-8b1e-428ecfe2726d	2024-09-15	40485b3c-f2d2-4cf0-bd23-6abf18b49cf7	Australia	Beauty	9	428.72	319.18204	2872.63836	2611.3825408012367	Michelle Andersen	1	2872.63836	105	2872.63836	60	66978.268402	921.082547231716
96e1b1bb-ad0c-4c05-bdf6-973428509907	2024-09-18	875a72cd-c67e-4d4f-8c90-3cd828864b11	North America	Electronics	8	47.79	42.695586	341.564688	185.49217806168608	Joseph Brooks	1	341.564688	102	341.564688	60	60657.854394	824.8550359343124
9d096431-a6d7-450f-a250-2fc26b37366d	2024-09-19	1d4296ee-4aeb-422b-9530-4379d3349cd1	Australia	Books	1	63.57	52.203684	52.203684	8.023179599187543	Caleb Camacho	1	52.203684	101	52.203684	66	91544.242731	1177.604080808591
d1bda999-f923-451c-963f-964de3c9a5a9	2024-09-19	6d8e3314-7360-418a-a1f8-1c5104607fa8	Australia	Beauty	5	356.89	288.652632	1443.26316	1203.5940920978428	Charles Smith	1	1443.26316	101	1443.26316	70	95387.089343	1149.437576059358
7e6b914c-882f-4dfd-802f-f912630c9771	2024-09-19	04cef8cd-22ab-4390-bfac-51d336e6113f	Europe	Toys	3	481.65	406.5126	1219.5377999999998	986.952492756608	Kristen Ramos	1	1219.5377999999998	101	1219.5377999999998	62	73461.618973	988.8412277570784
1c3fc774-5de5-4e52-9061-82eafc547e11	2024-09-21	7b4d2852-a507-4f98-b11e-74ddd89daeda	North America	Sports	3	475.03	349.76458899999994	1049.293767	823.6925614787253	Michelle Andersen	1	1049.293767	99	1049.293767	60	66978.268402	921.082547231716
077631d6-c76b-4281-bb9e-352c87e19b05	2024-09-22	085ede62-7661-4410-b24b-4ead2fc9e98c	Australia	Sports	3	18.1	14.186780000000002	42.56034000000001	5.4901022158348525	Crystal Williams	1	42.56034000000001	98	42.56034000000001	65	72555.900913	927.0834787540324
a84ae7da-de2f-4636-a657-734dc859c1a6	2024-09-24	980eae7d-932b-4edd-ab4d-401bf897f714	South America	Beauty	2	432.74	310.101484	620.202968	423.8119078353389	Susan Edwards	1	620.202968	96	620.202968	68	86058.98736700001	1063.159646603474
eeaa14a8-589e-40d6-b465-91f0ea199956	2024-09-25	d13cd45c-7ccb-4fa0-8ad1-79a78387b045	Europe	Electronics	6	491.84	444.918464	2669.510784	2410.05032893765	Crystal Williams	1	2669.510784	95	2669.510784	65	72555.900913	927.0834787540324
650f62c3-583d-49f1-9fd5-5b5e23b9e62a	2024-09-27	fdc26a4c-7232-4572-afeb-8d0d4ab42bdf	South America	Home & Kitchen	6	62.58	47.867442	287.204652	143.55204758845596	Diane Andrews	1	287.204652	93	287.204652	58	66389.094387	950.0340815608216
3b26b42d-8ede-4bd2-8fa6-66b4f30d06b9	2024-10-01	10c153ff-3044-4b10-82e4-76f763c75eb3	North America	Toys	6	215.9	164.19195	985.1517	762.6643583707852	Mary Scott	1	985.1517	89	985.1517	63	77562.23517100001	1033.152899764227
4e8bd212-1c54-448f-8106-474d9628a6a5	2024-10-02	152a10bd-1d87-418c-af22-ad230c8ae1c1	Australia	Toys	1	151.98	151.919208	151.919208	52.53466789794582	Christina Thompson	1	151.919208	88	151.919208	53	64491.182614000005	1021.7261378833904
7f52713d-3c26-45d2-9a71-1992e39c2a2a	2024-10-03	1df1ebda-c289-474d-95bb-c3ae08dc01c2	Asia	Clothing	7	235.86	214.656186	1502.5933020000002	1261.3407448014068	Steven Coleman	1	1502.5933020000002	87	1502.5933020000002	59	68355.922945	964.8650638967956
9b94d874-62ee-4dba-8fde-f3f7e32e6824	2024-10-04	f518ce01-8083-473f-bb16-2b562dba5eb6	Europe	Books	9	173.21	126.61651000000002	1139.54859	910.0368802660572	Roger Brown	1	1139.54859	86	1139.54859	54	68595.667163	1076.1212096324236
88db6644-1cf2-46a3-95d0-736197802445	2024-10-04	99854151-3793-411a-8a6d-2d2d4888a969	North America	Electronics	2	64.87	47.348613	94.697226	23.469526864986832	Roger Brown	1	94.697226	86	94.697226	54	68595.667163	1076.1212096324236
dbd46dc1-0a1e-4ee0-aee8-9838328be071	2024-10-10	f739c60e-dc9c-4b71-a28f-1ed26d59b425	Australia	Home & Kitchen	7	153.57	122.303148	856.122036	640.9565289503129	Diane Andrews	1	856.122036	80	856.122036	58	66389.094387	950.0340815608216
2918e1d8-c249-4714-97a7-445f748e3886	2024-10-12	05decca7-8988-4928-9694-40f848214224	Asia	Home & Kitchen	9	247.14	196.674012	1770.0661079999998	1522.8156389400751	Roger Brown	1	1770.0661079999998	78	1770.0661079999998	54	68595.667163	1076.1212096324236
a4085abf-914c-45e6-a916-919865b67cf1	2024-10-13	7d01a905-4c06-4ff9-bf4b-5a7bafd64ff2	North America	Clothing	10	57.83	49.728017	497.28017	315.1462762886862	Crystal Williams	1	497.28017	77	497.28017	65	72555.900913	927.0834787540324
d0df4c18-a304-48e9-b44e-9e65a402033a	2024-10-14	f4560f19-7291-44f9-a10a-fb547bd2ef60	Australia	Electronics	3	214.48	213.278912	639.836736	441.52383741334	Emily Matthews	1	639.836736	76	639.836736	72	80570.187359	919.786031455556
f4f08b7f-1f65-4905-9e7a-a162e1719b8c	2024-10-16	56e8783a-4e55-4e4f-a6af-99488a04d6ba	Australia	Books	5	38.94	29.131014	145.65507	48.98990541279534	Steven Coleman	1	145.65507	74	145.65507	59	68355.922945	964.8650638967956
bb5c001d-5787-4eb4-89c8-a65a52c1f6d3	2024-10-19	15e42953-b8b6-41d5-89e2-261492ce9a52	Asia	Beauty	2	280.69	220.257443	440.514886	266.5908154061908	Sandra Luna	1	440.514886	71	440.514886	56	72688.198308	1090.9576938669472
d0461c9d-c241-40d6-814c-52b4d2badf38	2024-10-20	98a60d5f-a93d-40c1-a1a5-7459c9ab1104	Asia	Beauty	6	125.46	111.270474	667.622844	466.7131708131207	Jason Nelson	1	667.622844	70	667.622844	70	87933.283392	1049.1629849529377
08b576d0-4e21-449f-8896-d2b5bbaf142b	2024-10-21	5ada7041-7191-423f-ac9f-178d559522c7	North America	Electronics	10	347.42	252.296404	2522.96404	2264.960599905101	Bradley Howe	1	2522.96404	69	2522.96404	56	64186.396558	951.6581100155678
62005a86-0030-4303-bd7d-a4d18ceac743	2024-10-24	0135118f-e6a5-4a21-bba1-a77d8507cc9a	Asia	Sports	7	445.7	333.16075	2332.12525	2076.263876190372	Johnny Marshall	1	2332.12525	66	2332.12525	61	67804.798966	913.3835523608234
ee93f02a-4e1c-4dc2-85ad-3400e1bf311b	2024-10-28	1fbb7254-ef85-44b5-a4af-70a310c18fa3	Europe	Clothing	3	308.13	286.406835	859.220505	643.8608275806452	Johnny Marshall	1	859.220505	62	859.220505	61	67804.798966	913.3835523608234
99db655e-bfe1-425c-8a4e-eda17baa94c2	2024-10-28	2dd4f4f5-9abe-4604-bcf8-118449d2aa00	South America	Home & Kitchen	1	224.36	211.952892	211.952892	89.96561602877699	Emily Matthews	1	211.952892	62	211.952892	72	80570.187359	919.786031455556
99570ba7-1111-467c-a40a-da9460741135	2024-10-31	f8ea9201-5fb8-46da-b121-01aae6322ece	Australia	Home & Kitchen	10	370.48	342.916288	3429.16288	3163.992032715378	Diane Andrews	1	3429.16288	59	3429.16288	58	66389.094387	950.0340815608216
8c3bad81-1cfe-420d-b6f2-f32f4303f1a8	2024-11-02	86abfa3a-13c7-489d-be28-0974f6a2ffd1	North America	Books	2	186.49	162.60063100000002	325.20126200000004	172.63205627633124	Michelle Garza	1	325.20126200000004	57	325.20126200000004	65	76798.491008	980.44596940906
bcc636f2-d836-4a28-ba84-7fede3996449	2024-11-02	a6d52b51-0ac1-49e8-835b-d8114f87d5b9	Asia	Home & Kitchen	5	389	302.9532	1514.7659999999998	1273.2034950165053	Christina Thompson	1	1514.7659999999998	57	1514.7659999999998	53	64491.182614000005	1021.7261378833904
c432a55d-daa0-4690-be42-2b0aaaa0e7c1	2024-11-03	23ffa77a-df7e-4059-a96f-7ffa4e7dc080	North America	Toys	8	177.62	141.758522	1134.068176	904.7782091581076	Caitlyn Boyd	1	1134.068176	56	1134.068176	58	71709.8323	1035.5858485437743
4ab2a74d-25ba-4edc-a1c3-5e1b7429bc24	2024-11-03	17676d6c-ea87-4c6b-91c8-2e77a1e20dd1	North America	Books	8	135.63	118.350738	946.805904	726.3364887013622	Caleb Camacho	1	946.805904	56	946.805904	66	91544.242731	1177.604080808591
0bd97240-88cf-4bfd-9862-7bc02fef362d	2024-11-05	e3759bcd-3182-4507-8b84-1ebe0a2e71a9	South America	Home & Kitchen	6	464.07	418.173477	2509.040862	2251.182331224998	Michelle Garza	1	2509.040862	54	2509.040862	65	76798.491008	980.44596940906
abc2ab6c-13c2-43b4-9b99-015f2ee80baf	2024-11-08	de461cce-8d9c-4525-94e6-5d1aec43a641	North America	Clothing	2	468.72	443.59660800000006	887.1932160000001	670.1163341795939	Emily Matthews	1	887.1932160000001	51	887.1932160000001	72	80570.187359	919.786031455556
45123af0-6707-4c05-8cfa-d138869664ad	2024-11-08	304d33df-4812-40e6-bf6a-a9f151cf6e2f	Australia	Electronics	7	348.59	324.049264	2268.344848	2013.2682862871532	Sandra Luna	1	2268.344848	51	2268.344848	56	72688.198308	1090.9576938669472
2f930aab-2ce1-4fa2-9257-a5cc8dce76d7	2024-11-11	6e1938a1-17b8-48ee-94a6-78dae38e7331	South America	Beauty	3	330.75	319.669875	959.009625	737.8817168167354	Jason Nelson	1	959.009625	48	959.009625	70	87933.283392	1049.1629849529377
0b76690a-29d8-4a4d-b362-f5f9dc51c549	2024-11-12	d1c20587-40ab-46f5-8e02-ab9ae6c5fd01	Australia	Electronics	8	146.49	127.929717	1023.437736	799.0537637126131	Diane Andrews	1	1023.437736	47	1023.437736	58	66389.094387	950.0340815608216
20925516-1615-456e-bf80-3bf3bcb28a52	2024-11-12	cb1cc062-fd48-4ab5-9a77-05dd7e338107	Australia	Books	2	133.51	107.836027	215.672054	92.4590432595978	Susan Edwards	1	215.672054	47	215.672054	68	86058.98736700001	1063.159646603474
cd6ade33-f224-4d10-8845-9da828295af3	2024-11-15	631f805d-16da-4596-9321-9755ea69799a	North America	Clothing	10	496.29	362.390958	3623.90958	3357.6335998095465	Sandra Luna	1	3623.90958	44	3623.90958	56	72688.198308	1090.9576938669472
e8280b37-9e54-4925-b4a0-82534d330d3d	2024-11-15	a80ba347-696a-4eb8-b615-5906311ca698	Asia	Electronics	7	97.55	96.82813	677.79691	475.97553374940446	Sandra Luna	1	677.79691	44	677.79691	56	72688.198308	1090.9576938669472
4150d21f-3eb8-49e1-b794-5f9a3ccb5f6f	2024-11-18	be4c3aa1-cb2c-4fb4-9a67-d32d2d5b35d0	North America	Toys	2	81.51	64.050558	128.101116	39.49274911890433	Caleb Camacho	1	128.101116	41	128.101116	66	91544.242731	1177.604080808591
e0e257f3-de38-4d44-ac4b-740bac408ac2	2024-11-20	782c8632-d5e7-446c-9251-8e1ef7b221cf	Europe	Clothing	5	336.18	298.225278	1491.12639	1250.175207968813	Michelle Andersen	1	1491.12639	39	1491.12639	60	66978.268402	921.082547231716
28ff810f-f429-4a86-8f17-984bbe1cb136	2024-11-21	225f11ab-cd90-4e93-8691-ced066601e63	Europe	Beauty	7	258.52	197.483428	1382.383996	1144.4562501780692	Kristen Ramos	1	1382.383996	38	1382.383996	62	73461.618973	988.8412277570784
2c0396ea-a4a0-43c8-9d64-8e28773e941f	2024-11-22	a26db452-fd1e-4710-8b33-7ed6d97080c6	South America	Toys	1	290.43	275.792328	275.792328	135.05323430740967	Adam Smith	1	275.792328	37	275.792328	55	62372.113224	936.3944649146875
16a3754f-aa86-4ce8-a49d-3a62dece1e1e	2024-11-23	5d45f553-a83f-45e5-abf0-581f0f452f48	Europe	Clothing	5	442.7	440.66358	2203.3179	1949.0869559158148	Charles Smith	1	2203.3179	36	2203.3179	70	95387.089343	1149.437576059358
4cd37e92-f91a-4405-8015-93b082c34966	2024-11-25	a5532f3e-4737-4cc8-862d-2c81f54a4fcd	Australia	Home & Kitchen	9	204.32	165.560496	1490.044464	1249.1201727651787	Johnny Marshall	1	1490.044464	34	1490.044464	61	67804.798966	913.3835523608234
61c1fae6-6913-4dde-af72-67ce30aa1bd9	2024-11-26	63761be5-6bda-46f8-9b71-97eb945d4403	South America	Toys	3	110.27	104.524933	313.574799	163.61793467022142	Charles Smith	1	313.574799	33	313.574799	70	95387.089343	1149.437576059358
564d9c0d-6e6e-4fc8-b4ee-bf2b337bb9f5	2024-11-29	6fb57954-e15e-44e5-b587-ca968f54fa7b	Australia	Clothing	4	287.1	241.85304	967.41216	745.8386367183529	Christina Thompson	1	967.41216	30	967.41216	53	64491.182614000005	1021.7261378833904
09ae4c71-4c48-430c-ae16-d9f777d228df	2024-12-01	6b50f2c2-809b-4586-b238-3e6933487f1c	North America	Electronics	3	74.8	70.76079999999999	212.2824	90.1827796157828	Jason Nelson	1	212.2824	28	212.2824	70	87933.283392	1049.1629849529377
38a6bd1f-74e2-422d-be13-5804ae91d40c	2024-12-03	fdfe2328-2e79-4249-9b1c-92e8d14c6409	Asia	Clothing	2	225.25	199.34625	398.6925	231.68688696435305	Michelle Garza	1	398.6925	26	398.6925	65	76798.491008	980.44596940906
9391574b-3826-4952-98df-8459222cd390	2024-12-05	343f3a4e-aff7-42dc-a316-ac2eb3d5221f	Asia	Clothing	8	351.23	297.105457	2376.843656	2120.4502646318674	Jason Nelson	1	2376.843656	24	2376.843656	70	87933.283392	1049.1629849529377
066c13f1-6c1c-4dbe-9683-3c4ef00c0f8c	2024-12-07	5dec1bc7-da01-43e0-812b-8e7711174877	North America	Beauty	8	271.05	197.134665	1577.07732	1333.9825500578036	Roger Brown	1	1577.07732	22	1577.07732	54	68595.667163	1076.1212096324236
92beffaa-bb28-42a1-bc64-a44fbf203263	2024-12-07	ea78983a-8725-43bf-9d4e-a620cc42f5ff	Australia	Clothing	5	491.45	396.79673	1983.98365	1732.9513407114748	Charles Smith	1	1983.98365	22	1983.98365	70	95387.089343	1149.437576059358
8ab666fa-f770-46a6-a052-0f7e64ff856e	2024-12-08	b3c9af37-9fe5-481c-b7a8-1853fc9bc2a3	Asia	Beauty	4	402.24	296.088864	1184.355456	953.0812017527828	Mary Scott	1	1184.355456	21	1184.355456	63	77562.23517100001	1033.152899764227
6030fa33-ade8-4eff-960c-9b7d99f09dab	2024-12-08	dedf9311-96e7-440d-8be1-0f0a1a67af8e	North America	Clothing	4	372.3	327.32616	1309.30464	1073.6401740365025	Kristen Ramos	1	1309.30464	21	1309.30464	62	73461.618973	988.8412277570784
8b8afcd4-545a-49fd-af84-fcf08631e7dc	2024-12-10	198e6ccb-d343-4525-958d-c28d1f938e8d	Asia	Electronics	2	295.16	287.840032	575.680064	383.9847944452066	Charles Smith	1	575.680064	19	575.680064	70	95387.089343	1149.437576059358
2867ac0e-0de2-44dd-9f45-06ce164c4580	2024-12-12	8cfbb186-eb24-4b32-8f7e-73111361df11	Asia	Home & Kitchen	9	210.7	189.14539	1702.3085099999996	1456.427425834934	Emily Matthews	1	1702.3085099999996	17	1702.3085099999996	72	80570.187359	919.786031455556
617522e1-3540-4b4a-961a-1c7a9202deea	2024-12-15	fdcc7df4-c774-41e8-b3a0-8b40cc3fd03d	South America	Home & Kitchen	2	250.72	234.79928	469.59856	291.31512795747915	Caitlyn Boyd	1	469.59856	14	469.59856	58	71709.8323	1035.5858485437743
ec534f90-e785-4a95-aa18-42e1fcc615e4	2024-12-16	ff64ce70-7782-4846-a5ee-50fcfb856776	South America	Electronics	3	241.81	224.206232	672.618696	471.2599677039875	Caleb Camacho	1	672.618696	13	672.618696	66	91544.242731	1177.604080808591
6fbfb532-652f-4484-8f00-311f7f2af338	2024-12-17	4c0a8787-862c-4e61-9e85-b8c12966db98	South America	Electronics	5	199.11	185.650164	928.25082	708.8009937629732	Kristen Ramos	1	928.25082	12	928.25082	62	73461.618973	988.8412277570784
df7f55b4-6efc-48ab-b2b1-5e7053ac50e5	2024-12-17	eeda0367-60f0-43dd-996f-ff15733e74b0	Europe	Sports	4	191.76	138.239784	552.959136	363.848624372093	Michelle Garza	1	552.959136	12	552.959136	65	76798.491008	980.44596940906
6d0e739c-3bac-4260-a95a-556b3c35da81	2024-12-17	9451b34d-5f55-426c-82f1-6b49b05c83e7	Europe	Toys	7	161.13	133.7379	936.1653	716.2739813548176	Johnny Marshall	1	936.1653	12	936.1653	61	67804.798966	913.3835523608234
48d45dac-c47b-4875-8ba8-d6ae96d59f18	2024-12-18	5f02de8f-c5b9-46ba-8bac-433a6659f498	South America	Home & Kitchen	1	257.94	239.987376	239.987376	109.21119159588036	Michelle Andersen	1	239.987376	11	239.987376	60	66978.268402	921.082547231716
cd06ef2d-25a6-408b-bfed-c1db54ebf960	2024-12-19	9ff0a2fa-026d-4da3-b1ff-4d1f2482c9c4	Europe	Electronics	6	249.27	187.999434	1127.996604	898.9571100001218	Joseph Brooks	1	1127.996604	10	1127.996604	60	60657.854394	824.8550359343124
08658d26-1d8a-4f92-8f1e-7eff6ab20391	2024-12-24	0dea74ee-f038-4d63-920e-aac5279ca630	Australia	Clothing	2	205.55	155.27247	310.54494	161.28036898341742	Steven Coleman	1	310.54494	5	310.54494	59	68355.922945	964.8650638967956
27bf7e2b-a73f-4f73-922d-9766c8f1924b	2024-12-27	bad45895-d1d6-41ec-9fbc-db0f80317c9d	South America	Home & Kitchen	4	65.92	54.060992000000006	216.243968	92.84521885596897	Charles Smith	1	216.243968	2	216.243968	70	95387.089343	1149.437576059358
ccea564f-7638-4ebe-a058-652574e18dc8	2024-12-29	f2ed5398-d529-48c0-b2d2-884772b92195	South America	Sports	4	235.03	226.968471	907.873884	689.5824956855013	Steven Coleman	1	907.873884	0	907.873884	59	68355.922945	964.8650638967956
\.


--
-- Data for Name: archetype_growth; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.archetype_growth (total_sales_yoy, total_profit_yoy, avg_order_value_yoy, avg_profit_per_order_yoy, growth_score) FROM stdin;
44.2	53.33	47.24	55.5	200.27
26.06	31.58	11.86	15.11	84.61
11.91	10.41	-11.08	-12.26	-1.0199999999999996
-32.73	-34.7	-20.36	-22.71	-110.5
\.


--
-- Data for Name: discount_impact_analysis_summary; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.discount_impact_analysis_summary (discount_band, avg_discount, num_orders, avg_profit_per_order, avg_order_value, profit_margin, total_revenue, total_profit, order_uplift_vs_low, revenue_uplift_vs_low, profit_uplift_vs_low, profit_per_discount_pct) FROM stdin;
Low	5.053670588235297	425	1086.5575161004315	1287.3110234705875	0.8440520560222307	547107.1849749997	461786.94434268336	0	0	0	91376.54231316564
Medium	17.570981067125643	581	985.7690711045673	1186.4016101807215	0.8308898627964669	689299.3355149992	572731.8303117536	36.705882352941174	25.989815971160567	24.025123994570986	32595.32453673312
High	27.51324444444445	225	874.3406432709459	1065.3104223466667	0.8207379041171377	239694.845028	196726.64473596282	-47.05882352941176	-56.188686310351976	-57.39882923368754	7150.2524950555735
\.


--
-- Data for Name: discount_simulation_results; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.discount_simulation_results (region, scenario, predicted_profit) FROM stdin;
Asia	-5% Discount	940.3228823122906
Australia	-5% Discount	1043.6045127102282
Europe	-5% Discount	824.5310797744513
North America	-5% Discount	968.4275559020542
South America	-5% Discount	1271.7401374011893
Asia	-5% Discount	890.0509954545762
Australia	-5% Discount	1011.1886723154862
Europe	-5% Discount	938.7169330566297
North America	-5% Discount	1092.7097767972032
South America	-5% Discount	1161.4751492582593
Asia	-5% Discount	1034.4771811963415
Australia	-5% Discount	1264.2566713236995
Europe	-5% Discount	828.8658868999648
North America	-5% Discount	1117.9540066415798
South America	-5% Discount	1093.8939239721788
Asia	-5% Discount	1012.6942423354434
Australia	-5% Discount	1114.0560346571597
Europe	-5% Discount	975.0549556292407
North America	-5% Discount	1049.0706433342937
South America	-5% Discount	796.9778938704297
Asia	-5% Discount	1037.7387945820474
Australia	-5% Discount	940.5029913097247
Europe	-5% Discount	1316.2312134370054
North America	-5% Discount	889.133313181323
South America	-5% Discount	1148.7714879295218
Asia	-5% Discount	1036.6551648370307
Australia	-5% Discount	839.920216036484
Europe	-5% Discount	738.3522525829121
North America	-5% Discount	1001.654746227597
South America	-5% Discount	822.4824527128574
Asia	0% Discount	939.2374635693578
Australia	0% Discount	1042.5190939672952
Europe	0% Discount	823.4456610315184
North America	0% Discount	967.3421371591213
South America	0% Discount	1270.6547186582563
Asia	0% Discount	888.9655767116433
Australia	0% Discount	1010.1032535725534
Europe	0% Discount	937.6315143136969
North America	0% Discount	1091.6243580542703
South America	0% Discount	1160.3897305153264
Asia	0% Discount	1033.3917624534085
Australia	0% Discount	1263.1712525807666
Europe	0% Discount	827.7804681570319
North America	0% Discount	1116.8685878986469
South America	0% Discount	1092.8085052292458
Asia	0% Discount	1011.6088235925106
Australia	0% Discount	1112.970615914227
Europe	0% Discount	973.9695368863078
North America	0% Discount	1047.9852245913607
South America	0% Discount	795.8924751274968
Asia	0% Discount	1036.6533758391147
Australia	0% Discount	939.4175725667919
Europe	0% Discount	1315.1457946940725
North America	0% Discount	888.0478944383901
South America	0% Discount	1147.6860691865888
Asia	0% Discount	1035.5697460940978
Australia	0% Discount	838.8347972935511
Europe	0% Discount	737.2668338399792
North America	0% Discount	1000.5693274846641
South America	0% Discount	821.3970339699245
Asia	5% Discount	938.1520448264249
Australia	5% Discount	1041.4336752243623
Europe	5% Discount	822.3602422885856
North America	5% Discount	966.2567184161885
South America	5% Discount	1269.5692999153234
Asia	5% Discount	887.8801579687104
Australia	5% Discount	1009.0178348296205
Europe	5% Discount	936.546095570764
North America	5% Discount	1090.5389393113373
South America	5% Discount	1159.3043117723937
Asia	5% Discount	1032.3063437104756
Australia	5% Discount	1262.0858338378337
Europe	5% Discount	826.6950494140991
North America	5% Discount	1115.783169155714
South America	5% Discount	1091.7230864863132
Asia	5% Discount	1010.5234048495777
Australia	5% Discount	1111.885197171294
Europe	5% Discount	972.884118143375
North America	5% Discount	1046.899805848428
South America	5% Discount	794.807056384564
Asia	5% Discount	1035.5679570961818
Australia	5% Discount	938.332153823859
Europe	5% Discount	1314.0603759511396
North America	5% Discount	886.9624756954572
South America	5% Discount	1146.600650443656
Asia	5% Discount	1034.4843273511651
Australia	5% Discount	837.7493785506183
Europe	5% Discount	736.1814150970464
North America	5% Discount	999.4839087417312
South America	5% Discount	820.3116152269915
\.


--
-- Data for Name: order_loss_summary; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.order_loss_summary (customer_id, order_status, payment_method, region, salesperson, order_date, num_orders, num_customers, total_value_lost, avg_discount_applied, units_affected, avg_order_value_lost) FROM stdin;
00199efa-f77b-439f-b061-9132e01d8a11	Returned	Gift Card	Australia	Caitlyn Boyd	2019-07-07	1	1	1597.284096	9.76	4	1597.284096
002353f2-a753-407c-bfbc-01e741ebfd13	Pending	Amazon Pay	North America	Adam Smith	2021-11-20	1	1	2343.066624	2.72	9	2343.066624
00412af2-4904-4a21-b72d-7e82f94df7ba	Pending	Debit Card	South America	Michelle Andersen	2023-07-08	1	1	2030.754656	23.96	7	2030.754656
004d41f0-66f9-4fab-8159-a02199ecda80	Returned	PayPal	Europe	Crystal Williams	2022-04-17	1	1	1478.537255	12.51	5	1478.537255
004e7a8d-1c8b-4784-94d0-944d567d92ae	Pending	Credit Card	South America	Emily Matthews	2023-04-02	1	1	1259.559354	0.57	6	1259.559354
0077e1c6-1045-48c4-93ef-9725af7bdb9c	Cancelled	Debit Card	North America	Susan Edwards	2023-09-17	1	1	356.80023	15.67	5	356.80023
0083a777-2a47-485d-860b-323c583098fb	Pending	Amazon Pay	Australia	Jason Nelson	2021-05-22	1	1	3405.179883	1.97	7	3405.179883
00885ae6-3931-4be9-84dc-b66fc90a0b47	Returned	Amazon Pay	Asia	Johnny Marshall	2019-08-08	1	1	1175.99778	23.16	9	1175.99778
008f50c0-8ed3-40d4-a3d0-3ed46f541cd3	Returned	PayPal	North America	Caleb Camacho	2024-04-24	1	1	337.907712	17.76	1	337.907712
00923a77-5bca-4c40-b544-fdc675b0be1e	Returned	Amazon Pay	Australia	Joseph Brooks	2020-06-21	1	1	728.698782	21.18	3	728.698782
0093a899-536a-4761-8d6d-c654d7ab2c52	Cancelled	Debit Card	Australia	Jason Nelson	2024-11-26	1	1	533.86508	5.96	10	533.86508
009b3368-ece4-466b-959b-d863e4a1430e	Cancelled	Amazon Pay	North America	Steven Coleman	2021-08-05	1	1	2559.670416	1.82	9	2559.670416
00c84a9f-b775-408f-8e3a-42b40c3de2a9	Cancelled	Gift Card	Asia	Adam Smith	2024-08-23	1	1	2233.97262	0.52	5	2233.97262
00f05a8d-d3cc-442e-b271-61029ac61567	Pending	PayPal	South America	Joseph Brooks	2022-04-04	1	1	643.431936	5.92	8	643.431936
00feb97d-bde9-4abf-9d0b-9326a5ae6462	Returned	Credit Card	Europe	Diane Andrews	2022-11-23	1	1	1602.071328	15.96	8	1602.071328
012a177c-acf0-4faa-9a2a-312d09ef5f83	Returned	Amazon Pay	North America	Crystal Williams	2019-01-14	1	1	1550.602396	13.22	7	1550.602396
013e4daa-d67d-4b18-9266-4efe35878001	Pending	Credit Card	South America	Mary Scott	2020-09-22	1	1	148.17741600000002	15.77	6	148.17741600000002
015a7619-9ae7-4743-95cf-f975a583bc61	Cancelled	PayPal	Australia	Joseph Brooks	2020-07-24	1	1	449.697396	7.69	2	449.697396
015e6d76-df4f-4668-b645-6671f820e3ab	Returned	Gift Card	Europe	Emily Matthews	2022-07-12	1	1	712.0382970000001	23.37	3	712.0382970000001
01734ad3-f17a-47f8-b176-0dd557fedb12	Returned	Gift Card	Europe	Emily Matthews	2024-05-06	1	1	3593.882592	0.08	9	3593.882592
01803f52-a9de-4df4-92e8-32b402d15e03	Cancelled	PayPal	Australia	Adam Smith	2024-08-31	1	1	724.2744	21.36	2	724.2744
018a95e1-23ed-4513-9673-127dddc8e0b7	Cancelled	Debit Card	North America	Bradley Howe	2022-05-29	1	1	2302.805584	13.47	8	2302.805584
018c7876-aafb-4ea3-bdd0-cdb9da681fa6	Cancelled	Debit Card	North America	Charles Smith	2022-02-04	1	1	339.706512	27.52	3	339.706512
01b45082-a27b-4bc2-ad0c-e62803f3e634	Returned	PayPal	Australia	Susan Edwards	2022-05-03	1	1	143.66352	7.6	2	143.66352
01bee0ee-7af1-414b-b490-335bb4a3a116	Returned	Credit Card	Asia	Sandra Luna	2020-01-30	1	1	1215.513236	26.54	7	1215.513236
01c6de38-a402-4f65-bfb5-0cab5742c3d4	Returned	Amazon Pay	Europe	Crystal Williams	2022-08-05	1	1	2340.7968	18.25	8	2340.7968
01f38c27-e2d8-42a3-a75f-0e32484b5e00	Returned	Debit Card	South America	Michelle Garza	2023-04-22	1	1	2947.4795000000004	12.75	7	2947.4795000000004
020668db-11f2-4a0c-b52b-94402004b965	Cancelled	Credit Card	Europe	Joseph Brooks	2024-05-08	1	1	1354.643504	25.08	4	1354.643504
0223fdac-eb6b-4b74-9174-5b715f03eac1	Returned	PayPal	Asia	Susan Edwards	2019-06-05	1	1	166.97436	28.46	5	166.97436
023b07fa-1276-4d30-ab2e-b58b5c0c3318	Returned	Amazon Pay	Europe	Jason Nelson	2023-06-24	1	1	381.84132	7.23	10	381.84132
0240d371-4258-4170-9940-bdd46fa11527	Pending	PayPal	North America	Jason Nelson	2024-08-13	1	1	507.626028	1.72	9	507.626028
0246f64d-ec5f-4984-b038-72311d66ffbb	Pending	Amazon Pay	North America	Diane Andrews	2023-06-22	1	1	86.13864000000001	9.28	1	86.13864000000001
0277f7eb-3e66-475f-a7ea-b1696511e83e	Returned	Credit Card	South America	Joseph Brooks	2020-01-18	1	1	563.10864	1.52	5	563.10864
0283e5a2-4c1d-4ad2-9f33-c8dfe9d8fb8e	Cancelled	PayPal	Europe	Emily Matthews	2024-08-27	1	1	76.37865400000001	23.33	1	76.37865400000001
029fb6ba-e02b-4f5b-9a39-d474e797bc99	Pending	Amazon Pay	Europe	Caleb Camacho	2022-08-30	1	1	609.2107199999999	27.1	4	609.2107199999999
02a0c45e-041f-4f19-b297-9a9a2a028fb5	Pending	Gift Card	Asia	Bradley Howe	2022-10-20	1	1	861.0268	22.29	4	861.0268
02b691f4-9954-4ac7-8f35-276841c26168	Returned	Amazon Pay	Europe	Mary Scott	2021-09-17	1	1	372.642816	20.02	4	372.642816
02ba0e8e-c328-47fe-ab6f-1a68f8db3cde	Returned	Amazon Pay	Asia	Kristen Ramos	2021-10-08	1	1	1189.916424	24.58	4	1189.916424
02cfa60b-a441-43e3-a6b1-e434d6bb1278	Pending	Debit Card	Australia	Caitlyn Boyd	2021-12-19	1	1	136.525625	23.75	1	136.525625
02f1f4b8-4f0e-4753-a667-7edc3d92dfe5	Returned	Debit Card	Asia	Kristen Ramos	2021-05-25	1	1	907.102872	0.09	4	907.102872
02fcc52c-d50e-4bc8-bf29-400bbbaa55a8	Returned	PayPal	Australia	Bradley Howe	2020-08-27	1	1	227.703545	15.21	1	227.703545
032663bd-c7d1-426e-b3df-9f2c791f579b	Returned	Gift Card	Australia	Kristen Ramos	2024-04-02	1	1	116.805058	28.38	1	116.805058
0333e426-1311-4c21-be49-bcd27fd6b37f	Returned	Debit Card	Europe	Roger Brown	2024-08-11	1	1	1676.190285	28.51	5	1676.190285
0337cc58-9537-4923-adef-c6e22cd31a90	Cancelled	PayPal	South America	Jason Nelson	2024-05-28	1	1	4164.765066	6.39	9	4164.765066
03423bd7-1608-4395-9acc-48a1ec0184fa	Pending	Gift Card	South America	Sandra Luna	2021-12-13	1	1	2439.6920640000003	24.79	8	2439.6920640000003
0344da41-bd05-4f07-aceb-f70cfcb697ef	Pending	Gift Card	South America	Kristen Ramos	2022-10-20	1	1	354.363828	19.78	1	354.363828
03575cdf-1322-44cd-8b35-a6cf70993b8e	Returned	Gift Card	North America	Susan Edwards	2021-11-18	1	1	801.28624	13.58	5	801.28624
03b14d51-d192-42f0-8493-b71cc4904852	Pending	PayPal	South America	Michelle Andersen	2019-12-16	1	1	720.00028	19.65	4	720.00028
03e14d6c-e74b-42b4-a50b-74094ecc7dda	Returned	Amazon Pay	South America	Jason Nelson	2019-04-12	1	1	954.45837	9.59	3	954.45837
03f4c0e2-78f2-42f0-a5e7-4d55b4e4f27f	Returned	Gift Card	Europe	Michelle Garza	2023-02-25	1	1	627.5785500000001	14.65	5	627.5785500000001
0415751d-f654-4db9-8936-db599219e56e	Pending	Amazon Pay	South America	Jason Nelson	2019-03-26	1	1	1415.88594	9.7	9	1415.88594
043c7492-3e51-4213-a764-e8a941669fd6	Returned	Amazon Pay	Asia	Emily Matthews	2019-04-19	1	1	296.233224	7.56	1	296.233224
043fde29-5da1-4704-9e19-6a3739652ff0	Pending	Gift Card	Asia	Steven Coleman	2020-11-25	1	1	2935.97304	11.12	10	2935.97304
0447f9d7-714f-4ff5-b531-83844cfad057	Pending	PayPal	South America	Michelle Garza	2020-02-14	1	1	601.9621	29.43	4	601.9621
047e3739-7fdc-4a5f-9b74-5b9d0877c6b2	Pending	Debit Card	Asia	Adam Smith	2020-01-22	1	1	195.999015	16.55	1	195.999015
04aa5cb6-1737-4e4e-adee-b8372b751797	Returned	Credit Card	Australia	Joseph Brooks	2019-04-12	1	1	799.64192	29.45	8	799.64192
04e271a6-11d1-4699-ae85-144ebf745bbc	Cancelled	Amazon Pay	North America	Christina Thompson	2023-07-20	1	1	997.29918	25.43	6	997.29918
04e54e78-f7cf-490b-b586-8e16feec987a	Returned	Amazon Pay	North America	Mary Scott	2024-07-18	1	1	639.4731240000001	29.91	4	639.4731240000001
04ea1c22-3c55-4708-8ba4-981af7cc6a67	Cancelled	Amazon Pay	Europe	Crystal Williams	2022-10-15	1	1	197.076453	0.27	7	197.076453
04fcad2a-4503-4f86-a5b1-8f77d2dbb4ff	Cancelled	Amazon Pay	South America	Emily Matthews	2021-06-30	1	1	3582.36684	4.78	10	3582.36684
050eba47-6b3c-4423-8b0c-0c19e9f3a6b4	Cancelled	Debit Card	North America	Jason Nelson	2023-09-05	1	1	102.831912	11.26	2	102.831912
0517f850-8e14-4ffa-8c62-9ec33fa12999	Pending	Credit Card	South America	Bradley Howe	2022-11-13	1	1	207.766038	28.93	1	207.766038
053fb4d1-2954-4e10-8122-7ad64a9bc054	Pending	Debit Card	Europe	Christina Thompson	2022-07-26	1	1	1643.6250999999995	3.8	5	1643.6250999999995
0577743e-d316-4cfa-9022-365ec45a7aea	Returned	Gift Card	North America	Diane Andrews	2023-12-18	1	1	1634.85072	1.42	6	1634.85072
057f81ec-f691-489d-8a72-cbbcf4162f97	Pending	Gift Card	South America	Diane Andrews	2023-05-31	1	1	730.8311449999999	20.91	5	730.8311449999999
05802553-5e67-4cd7-ae8d-da6930f3b000	Pending	Gift Card	Australia	Jason Nelson	2021-11-24	1	1	87.74420399999998	29.17	2	87.74420399999998
05867659-2234-4306-96cf-bb4b1c58f211	Returned	Debit Card	North America	Mary Scott	2021-01-28	1	1	1075.069248	19.26	4	1075.069248
059eb438-d78b-4970-804a-659b5c7d8398	Pending	Gift Card	North America	Johnny Marshall	2021-12-21	1	1	2643.52212	28.4	9	2643.52212
05a4d898-48d4-4176-860c-5705a33a37ba	Cancelled	Credit Card	South America	Kristen Ramos	2021-09-25	1	1	2194.172316	4.33	7	2194.172316
05baab16-33c0-4f58-b280-8c2bf6572d48	Pending	Credit Card	South America	Caleb Camacho	2024-04-02	1	1	828.790272	3.07	8	828.790272
05e18ad8-ccaf-4f42-8bfe-86e28b8736e0	Cancelled	PayPal	Australia	Diane Andrews	2022-06-11	1	1	1694.03892	5.04	7	1694.03892
05f0090b-febc-493e-b948-f56a651449b7	Pending	Amazon Pay	Europe	Emily Matthews	2022-01-18	1	1	1212.435648	24.01	4	1212.435648
060beb87-6877-4b17-ba48-0b1c930e0187	Pending	Debit Card	South America	Caleb Camacho	2023-01-11	1	1	86.52744	10.98	1	86.52744
060e5b6f-c1aa-43cd-9920-d3e7e7db7683	Returned	Debit Card	Australia	Johnny Marshall	2022-07-21	1	1	96.711148	12.81	2	96.711148
061364a2-4015-4b3d-bf2c-2ac609d7bb64	Pending	Debit Card	Asia	Roger Brown	2022-03-09	1	1	209.33784	19.84	5	209.33784
06193dfe-14c2-47c5-9dfb-376f8c1e93e9	Returned	Debit Card	Asia	Roger Brown	2020-11-18	1	1	746.459056	29.06	8	746.459056
061a6345-a598-443c-89f6-212c173c82a1	Pending	Credit Card	Australia	Charles Smith	2023-10-24	1	1	675.393714	24.67	9	675.393714
0628e8e4-b6ae-416f-8ef3-ca7130929b4e	Returned	PayPal	South America	Kristen Ramos	2023-09-28	1	1	385.718554	3.02	1	385.718554
06347e1e-c058-4592-97dd-0838ba186554	Returned	Debit Card	Australia	Mary Scott	2021-01-09	1	1	264.964968	10.99	4	264.964968
063d210a-e50d-4a8b-b583-74db7846332c	Pending	Debit Card	South America	Jason Nelson	2022-08-24	1	1	2189.0007	28.45	10	2189.0007
0663f627-b9e1-4276-9489-5258e65b8eb9	Returned	Gift Card	Europe	Jason Nelson	2023-03-22	1	1	906.973992	21.71	9	906.973992
0675f4d5-efe2-44aa-9b4b-d7613f2b1045	Returned	Gift Card	North America	Charles Smith	2019-03-28	1	1	2689.6077	15.64	9	2689.6077
06972845-2801-4d69-8c9f-62eefc4612d0	Returned	PayPal	South America	Johnny Marshall	2020-07-18	1	1	1157.7096	17.2	5	1157.7096
06c99f6f-fb7f-4e35-bc87-569b09c042ca	Cancelled	Gift Card	Europe	Bradley Howe	2022-09-23	1	1	1438.97108	27.42	5	1438.97108
06ce769e-736a-45f7-b993-7a2371f77964	Pending	Amazon Pay	North America	Roger Brown	2022-07-30	1	1	911.5354079999998	23.12	7	911.5354079999998
06d9c68a-39ae-4e9d-b994-5424baa3ddd6	Returned	Amazon Pay	Europe	Caleb Camacho	2022-05-22	1	1	352.039392	22.06	6	352.039392
06df7e76-7ecf-4bdd-ab68-3b5cd9c24904	Pending	Amazon Pay	North America	Caitlyn Boyd	2023-02-13	1	1	308.033344	22.08	2	308.033344
06e71c62-9d3b-4514-866d-55b5fd210a76	Cancelled	Credit Card	North America	Diane Andrews	2020-10-27	1	1	390.84553199999993	23.66	3	390.84553199999993
06e74fa2-7e21-44b1-b528-96004e6eda3e	Returned	Gift Card	South America	Michelle Garza	2024-07-31	1	1	393.307324	0.69	2	393.307324
06fffe27-d876-4ae5-a619-a40e0b1b8bc5	Returned	PayPal	North America	Joseph Brooks	2020-12-18	1	1	409.722312	1.83	1	409.722312
070c7283-dbbe-494d-9000-06f05b3ac4d7	Pending	Debit Card	Europe	Mary Scott	2021-05-04	1	1	1529.1737999999998	22.12	5	1529.1737999999998
073e8b08-97c5-4951-bb1a-aa831d1ceed1	Cancelled	Credit Card	North America	Diane Andrews	2019-05-03	1	1	2065.7472	12	8	2065.7472
077a9743-411c-46c5-bed4-dfc225623d88	Pending	Credit Card	Europe	Roger Brown	2024-10-20	1	1	386.893024	1.02	8	386.893024
07851736-7ce1-4992-b5d3-3d7973e1fa95	Returned	PayPal	North America	Steven Coleman	2022-03-27	1	1	2995.4251080000004	10.04	9	2995.4251080000004
079eea78-2623-4892-93d9-01f1d9abef5d	Returned	Debit Card	Europe	Roger Brown	2024-09-08	1	1	326.5128	9.1	2	326.5128
07a5b787-3141-473a-8dc7-ab0be6798183	Returned	Amazon Pay	Australia	Diane Andrews	2019-05-02	1	1	1092.07359	21.7	9	1092.07359
07d2bf48-ccd6-4a7e-b865-0944441858ab	Pending	PayPal	Europe	Charles Smith	2019-12-08	1	1	2689.485568	26.52	8	2689.485568
07eb84a1-8233-4c68-875a-17e4d3b62b69	Pending	Debit Card	North America	Mary Scott	2021-08-29	1	1	541.465344	17.92	8	541.465344
07ece805-d95a-4432-a18a-1c35bcdec30b	Cancelled	Credit Card	South America	Susan Edwards	2021-05-17	1	1	1688.6540999999995	23.78	6	1688.6540999999995
07efb14c-3bcd-4653-a23e-6c177b2d2be3	Returned	Debit Card	Europe	Emily Matthews	2023-10-02	1	1	283.563	26.5	1	283.563
07f96a57-a5e0-4a63-8fcf-71169bb3e201	Returned	Debit Card	Europe	Caitlyn Boyd	2019-09-10	1	1	2144.076156	5.86	9	2144.076156
07f9a047-3aa7-45b5-8a35-45f3817372e6	Returned	Credit Card	North America	Sandra Luna	2022-11-01	1	1	778.1330159999999	22.68	9	778.1330159999999
081cf87a-f2fa-4a9f-b966-3be6e5f48806	Pending	Debit Card	North America	Kristen Ramos	2019-05-01	1	1	1264.787622	1.54	9	1264.787622
0847026e-3f8d-4b1d-9be4-a8ff373d6016	Cancelled	Amazon Pay	Australia	Diane Andrews	2019-05-07	1	1	129.120221	20.79	1	129.120221
08811bb5-ffc1-432e-a371-586bd0f70991	Cancelled	PayPal	North America	Bradley Howe	2022-11-14	1	1	1182.09336	22.86	5	1182.09336
0889be0f-0ca5-409d-b97c-90ddfd166524	Cancelled	Debit Card	North America	Caleb Camacho	2020-03-27	1	1	285.2139	5.87	10	285.2139
08984c88-7bf7-4739-83df-2804ea37442f	Pending	Amazon Pay	North America	Diane Andrews	2019-05-07	1	1	1429.191114	0.03	6	1429.191114
08a00960-95af-41de-aae4-3cf95186ca3e	Cancelled	Credit Card	South America	Bradley Howe	2021-07-10	1	1	593.8704	11.5	2	593.8704
08aa1c5c-5a42-4d68-bbc4-869711b4dfa7	Pending	Gift Card	Europe	Crystal Williams	2024-11-24	1	1	3232.483956	1.98	9	3232.483956
08e2016d-3da2-46b4-ae38-a826ae3c600f	Pending	Debit Card	North America	Susan Edwards	2022-11-18	1	1	253.957344	19.44	2	253.957344
090c211d-681e-4fc3-ba02-28105f60c56e	Returned	Amazon Pay	Europe	Bradley Howe	2020-06-19	1	1	262.54752	26.35	8	262.54752
091cddea-22f1-4346-9cb8-62ae4b1ec234	Returned	Gift Card	Australia	Michelle Andersen	2021-05-27	1	1	126.253062	14.59	2	126.253062
095a49ef-b2ea-4b0d-8f09-3452da2d19f1	Cancelled	PayPal	South America	Charles Smith	2024-06-18	1	1	784.286888	17.61	8	784.286888
095c0b0d-0763-4468-bc65-ef77bd505929	Cancelled	Amazon Pay	Asia	Christina Thompson	2023-02-15	1	1	2831.8621000000003	21.3	10	2831.8621000000003
095fff0e-2a2c-4921-a91f-ed4dfec18460	Cancelled	Amazon Pay	Europe	Michelle Andersen	2023-05-01	1	1	4013.952588	0.14	9	4013.952588
096d7312-56cd-48e3-bfce-5a71a34ecdb9	Pending	Amazon Pay	Asia	Kristen Ramos	2019-12-17	1	1	1024.215192	26.29	4	1024.215192
09816b60-8c88-4eb7-bf20-f5104648d2f9	Pending	PayPal	Europe	Johnny Marshall	2019-04-10	1	1	1082.436736	23.52	4	1082.436736
09832ed7-7c5e-4634-b626-b20b109a6d3b	Pending	Debit Card	North America	Joseph Brooks	2024-03-20	1	1	179.27164499999998	10.61	3	179.27164499999998
09e4e2a2-87fa-4958-84f6-e0bca3d51443	Returned	Debit Card	Europe	Adam Smith	2019-08-23	1	1	1079.3128	25.4	4	1079.3128
09ea6a14-f61e-4929-8948-0a77442e9246	Cancelled	Amazon Pay	South America	Charles Smith	2023-09-11	1	1	1466.286125	22.47	5	1466.286125
0a0768ee-8a2f-4ce0-aff7-e151699527c0	Returned	Amazon Pay	North America	Steven Coleman	2021-02-04	1	1	697.681632	6.16	4	697.681632
0a1055d9-9a97-4e2f-bebf-52628e9ec4ac	Cancelled	Debit Card	North America	Sandra Luna	2021-05-13	1	1	107.8575	25	1	107.8575
0a24e2dd-9de0-4370-a66d-36f5cb870bba	Returned	Credit Card	South America	Jason Nelson	2019-07-05	1	1	1067.34933	22.06	5	1067.34933
0a264f88-3509-4bb9-a7cb-ce8d3e2b3fc1	Cancelled	Amazon Pay	North America	Johnny Marshall	2023-08-11	1	1	274.318008	4.83	3	274.318008
0a3d9233-2812-4c89-8ba9-192654b5b9b9	Returned	Debit Card	South America	Kristen Ramos	2022-08-06	1	1	297.06093000000004	11.51	6	297.06093000000004
0a40eedf-aa0f-437d-b3a7-d1664f6759c5	Cancelled	PayPal	Australia	Adam Smith	2022-05-23	1	1	2416.29927	19.7	7	2416.29927
0a47266f-64f1-4ec7-94ac-9e6db05d3ef0	Cancelled	Gift Card	South America	Steven Coleman	2019-07-11	1	1	540.323028	8.44	3	540.323028
0a4b8316-16f6-4c17-8028-201b67026d68	Pending	PayPal	Australia	Roger Brown	2024-01-18	1	1	56.33170199999999	9.42	1	56.33170199999999
0a4fc649-92a0-4498-b0a4-de4f6e53daa9	Returned	PayPal	Asia	Kristen Ramos	2021-07-17	1	1	208.21	29.12	1	208.21
0a54d286-e6a9-4c17-b6f7-01258392cc83	Cancelled	Amazon Pay	North America	Jason Nelson	2020-05-07	1	1	299.809808	29.21	2	299.809808
0a617603-34a9-4bc4-a8c0-081f351ec025	Pending	PayPal	North America	Caleb Camacho	2023-04-17	1	1	677.016324	22.76	3	677.016324
0a6ed291-b5f5-4abf-b78d-0aa1666f7bad	Cancelled	Gift Card	Asia	Mary Scott	2023-01-30	1	1	240.161992	13.01	8	240.161992
0a737678-6cee-4c15-a2c7-04fad604690c	Returned	Amazon Pay	Europe	Susan Edwards	2022-10-18	1	1	12.33276	6.57	2	12.33276
0a77722e-2e26-48bb-b3b5-9f69734e1fa3	Pending	PayPal	Australia	Sandra Luna	2022-01-01	1	1	3167.5607820000005	10.93	9	3167.5607820000005
0a807e7e-1eab-4414-b70e-a30583d8a7f8	Cancelled	PayPal	Asia	Caleb Camacho	2023-02-25	1	1	1235.550204	29.74	6	1235.550204
0a83ce7e-41e7-4b9d-9e5d-9f79d40b23f8	Cancelled	PayPal	North America	Charles Smith	2023-05-16	1	1	355.126464	14.32	2	355.126464
0a9129a9-ccb4-4bcc-b3d7-54f29522ce33	Cancelled	Debit Card	North America	Michelle Andersen	2021-07-30	1	1	957.094	22.5	8	957.094
0a9638ff-0edb-4ee5-a821-ca373c9afa27	Pending	Gift Card	Asia	Steven Coleman	2020-11-24	1	1	175.4123	13.59	2	175.4123
0a9f9324-09ac-429f-b793-431388169a10	Returned	PayPal	Asia	Crystal Williams	2021-05-12	1	1	1015.269066	8.47	3	1015.269066
0ad510d6-f53d-439e-98d3-b44687f4a3cf	Pending	Gift Card	South America	Steven Coleman	2019-07-11	1	1	1186.478964	24.53	4	1186.478964
0ad9ce33-c399-4410-b3f5-f4d3d457a422	Cancelled	Gift Card	Asia	Roger Brown	2022-09-21	1	1	1983.29208	29.79	8	1983.29208
0adca1fa-93a4-4f27-89d7-6985442ecc32	Returned	Amazon Pay	Europe	Caitlyn Boyd	2021-10-19	1	1	1471.4633340000005	8.59	9	1471.4633340000005
0ae5983a-5996-48eb-b039-ec7f142ab6de	Pending	Debit Card	North America	Diane Andrews	2024-09-08	1	1	1785.249531	28.33	9	1785.249531
0b0ea4e5-741a-4504-aa68-dda83082681d	Cancelled	Debit Card	Europe	Roger Brown	2020-02-16	1	1	580.903816	25.67	2	580.903816
0b131e4f-5ddb-4a4f-b1d2-bb4477e55ca6	Pending	Credit Card	South America	Joseph Brooks	2022-10-26	1	1	1841.4988900000003	20.69	7	1841.4988900000003
0b14bf78-f3e5-4f3c-ae14-daadd20a3af4	Pending	Debit Card	North America	Sandra Luna	2023-03-13	1	1	359.475744	22.48	1	359.475744
0b1c7992-da17-462d-a0ae-e3ecc1fcafd4	Returned	Credit Card	North America	Caitlyn Boyd	2021-05-24	1	1	694.783448	1.41	4	694.783448
0b3a7d18-df7d-4070-9d7a-07750ff4a5f3	Cancelled	PayPal	Australia	Diane Andrews	2023-09-01	1	1	2563.715934	0.49	9	2563.715934
0b49ba52-6959-4715-b90c-7e2f2f4dfce5	Cancelled	Gift Card	Asia	Steven Coleman	2022-07-22	1	1	369.2157	23.7	2	369.2157
0b7c9a48-3b09-4828-853e-0579b30aeb23	Pending	Debit Card	South America	Steven Coleman	2021-11-28	1	1	335.854008	14.84	1	335.854008
0b7da17e-3251-4862-ab34-832bce9d47ea	Cancelled	Credit Card	North America	Roger Brown	2024-07-28	1	1	808.561764	24.13	3	808.561764
0b8d8ede-3a43-4d44-9bf3-46e4558bcabb	Pending	Gift Card	Australia	Michelle Andersen	2024-05-21	1	1	1030.518288	0.19	6	1030.518288
0ba3c409-c77f-4a16-b170-fc35d2572b13	Returned	Credit Card	South America	Michelle Garza	2023-03-27	1	1	1403.8945439999998	7.44	6	1403.8945439999998
0bbdf2de-46c1-4de7-a536-595e64d9ef40	Returned	PayPal	North America	Emily Matthews	2022-06-10	1	1	2730.508074	9.22	7	2730.508074
0bcca77a-daaf-4e96-908c-b26567038834	Cancelled	PayPal	North America	Mary Scott	2021-08-19	1	1	166.83503199999998	9.24	2	166.83503199999998
0bcf291e-2621-474c-9839-68e3957252ea	Pending	Debit Card	South America	Emily Matthews	2019-12-22	1	1	1883.227122	5.14	7	1883.227122
0bd75bfe-e2fa-456e-9ea3-8c6a04fceb91	Returned	Credit Card	Europe	Mary Scott	2023-06-04	1	1	336.892638	16.87	2	336.892638
0be85b12-bbeb-4213-882e-a564ea80071c	Pending	PayPal	Europe	Charles Smith	2020-11-25	1	1	807.587865	10.67	5	807.587865
0be905da-8355-4208-ace6-5b3e99d7a0ee	Cancelled	PayPal	Australia	Sandra Luna	2020-06-27	1	1	1030.445226	3.94	3	1030.445226
0bfd30d7-5459-487f-8b35-b67c84e2c012	Cancelled	Amazon Pay	Australia	Bradley Howe	2021-11-15	1	1	778.462408	26.61	8	778.462408
0c1883b4-d085-4f66-ab90-f998b3bb363e	Returned	Gift Card	North America	Johnny Marshall	2022-10-05	1	1	2002.2244480000004	5.96	7	2002.2244480000004
0c1932d6-abfd-4a2a-8478-138143c7054e	Returned	Gift Card	North America	Joseph Brooks	2020-09-17	1	1	1028.792004	4.76	3	1028.792004
0c1ad83d-b4d5-444d-b4a7-54cd1a07b57f	Returned	Debit Card	Europe	Adam Smith	2020-02-11	1	1	1232.1236970000002	9.33	3	1232.1236970000002
0c1b342f-5dfa-4994-a6b9-c2e54faca9d8	Pending	Debit Card	Europe	Susan Edwards	2023-04-21	1	1	1220.390262	5.69	7	1220.390262
0c1e943b-159d-454b-9b6e-17b81d94c53d	Returned	Amazon Pay	Europe	Caitlyn Boyd	2024-07-26	1	1	276.397016	10.47	4	276.397016
0c23a455-ffb2-44a4-b631-9023cb26b8c4	Cancelled	Credit Card	Australia	Joseph Brooks	2020-04-05	1	1	1119.96972	28.99	4	1119.96972
0c263ebe-c422-451b-b951-add6bb8e314b	Pending	PayPal	Asia	Adam Smith	2020-02-09	1	1	583.765128	29.22	2	583.765128
0c29530c-872d-449a-8fdd-000bbcf95d71	Returned	Amazon Pay	Australia	Charles Smith	2020-05-26	1	1	786.1230720000001	3.12	2	786.1230720000001
0c2e5c5b-3698-4a14-a450-65289ff1ef71	Returned	Gift Card	Asia	Kristen Ramos	2023-10-08	1	1	514.2112	20.45	8	514.2112
0c2f83cb-51ce-4905-9312-d870d06c2933	Returned	Amazon Pay	Europe	Emily Matthews	2024-05-17	1	1	2996.7597	9.8	9	2996.7597
0c31f2fc-00f8-42f4-8b60-bff7636e8752	Pending	Credit Card	North America	Charles Smith	2020-11-05	1	1	224.482137	27.71	1	224.482137
0c3424b1-ad03-49f3-b548-422e0b250639	Pending	Amazon Pay	South America	Caitlyn Boyd	2020-12-17	1	1	1008.3755	23.55	4	1008.3755
0c4a8f63-0751-4a8b-a37c-b056810af1d1	Returned	Credit Card	Asia	Johnny Marshall	2020-10-23	1	1	2353.293943	9.23	7	2353.293943
0c4ed198-3bc6-49cc-9883-092c7a780967	Returned	Gift Card	South America	Adam Smith	2020-04-24	1	1	1250.698756	19.17	4	1250.698756
0c8fd427-17b7-490c-9f30-577b77b88c5c	Returned	Amazon Pay	North America	Jason Nelson	2021-02-26	1	1	1220.31	3.15	8	1220.31
0ca49d26-85e2-4507-8abf-63e0dd4dcfd8	Pending	Debit Card	North America	Joseph Brooks	2023-07-07	1	1	3924.7140600000007	7.3	9	3924.7140600000007
0cc21b84-c9fd-4b76-95ab-173702035ec1	Pending	Amazon Pay	North America	Michelle Garza	2024-03-28	1	1	783.525912	16.01	8	783.525912
0cc41540-9aae-40ad-99ab-c2db5b3573ee	Cancelled	Debit Card	Asia	Sandra Luna	2019-10-05	1	1	3638.952	8.2	10	3638.952
0cc49d6f-f570-4b3d-9db9-ede55cc8f9e8	Returned	Amazon Pay	North America	Kristen Ramos	2019-02-18	1	1	2435.256999	17.41	7	2435.256999
0cd76810-ff36-4616-a991-a3bf33441793	Pending	Gift Card	Europe	Adam Smith	2019-09-14	1	1	1737.629376	8.32	7	1737.629376
0ce8322c-3c89-4aa6-a884-a202b0c4761d	Pending	Debit Card	Australia	Caleb Camacho	2024-12-26	1	1	2980.130144	22.04	8	2980.130144
0cefed1c-6a10-45a6-9bd4-6a6769125cff	Pending	Debit Card	Australia	Roger Brown	2024-11-25	1	1	195.285006	24.58	9	195.285006
0d03b9c7-608c-4eaf-a128-ebb7ddd7f226	Pending	Debit Card	Australia	Michelle Garza	2019-02-04	1	1	1847.47392	6.58	6	1847.47392
0d088aaf-a40f-4a0e-b4ee-5234902413f2	Pending	PayPal	Asia	Mary Scott	2023-02-19	1	1	285.62382	29.35	4	285.62382
0d34e1e7-629a-483d-a90d-31fcb8d493a6	Returned	Credit Card	South America	Caitlyn Boyd	2021-04-27	1	1	2376.40531	26.67	10	2376.40531
0d4632b9-3174-498a-a160-a038d3ced892	Pending	Gift Card	Asia	Johnny Marshall	2020-11-08	1	1	1088.5593179999998	18.93	3	1088.5593179999998
0d60ed84-0ce0-4a08-b571-ecb4ebb6c8ec	Pending	Amazon Pay	Australia	Caitlyn Boyd	2024-07-28	1	1	265.228964	5.37	2	265.228964
0d6cccf1-6648-4b9d-9ef3-55483bcce4f1	Pending	Amazon Pay	Europe	Christina Thompson	2023-10-12	1	1	2045.319176	17.07	8	2045.319176
0d86895a-5e74-4dbe-a9cb-6b7777bf6978	Pending	Credit Card	Australia	Diane Andrews	2020-07-04	1	1	802.3695840000001	9.92	3	802.3695840000001
0d8a0b11-4da7-43e9-a253-5aa20ae495b9	Pending	Credit Card	Asia	Christina Thompson	2024-08-22	1	1	2458.794345	28.41	7	2458.794345
0d8b9eb7-7085-4d87-8260-4d08de5e3ca4	Returned	PayPal	Europe	Sandra Luna	2020-01-19	1	1	207.270147	3.33	3	207.270147
0d8ee330-8761-4b4a-83a9-dcd8981b1da9	Returned	PayPal	North America	Roger Brown	2023-05-21	1	1	1513.227144	29.54	6	1513.227144
0d91e9ac-00f3-4f02-a939-2d53f1fe38f0	Cancelled	Amazon Pay	Australia	Kristen Ramos	2020-08-20	1	1	2455.610024	28.44	7	2455.610024
0d9a37bc-54fb-4d3c-ac9c-67b409ee0a5e	Cancelled	Gift Card	Asia	Christina Thompson	2024-10-06	1	1	538.8179759999999	4.91	4	538.8179759999999
0da4411d-7633-43f0-a3e3-ceaa0a494d7d	Pending	Credit Card	South America	Christina Thompson	2019-11-10	1	1	3644.95582	3.86	10	3644.95582
0dcfa7b5-880b-4820-b8cb-bde92a959b8d	Returned	Gift Card	South America	Jason Nelson	2023-05-07	1	1	1520.39736	9.64	4	1520.39736
0dff63f2-80b9-464d-aaa6-25a7b7600552	Cancelled	Gift Card	North America	Michelle Garza	2020-03-18	1	1	2444.710098	9.71	6	2444.710098
0e1bdd72-0c62-4eaa-ba5b-3db76fd3e26a	Cancelled	PayPal	Australia	Susan Edwards	2023-03-02	1	1	58.432	17	5	58.432
0e25d35f-97a0-4355-b9f1-34e54b3ee9a5	Pending	Debit Card	Europe	Bradley Howe	2024-09-30	1	1	215.03466	0.86	2	215.03466
0e4bef2d-ad20-49e8-9ea8-40888029cd76	Returned	Gift Card	South America	Joseph Brooks	2019-10-21	1	1	588.0926479999999	15.63	2	588.0926479999999
0e4e6ebf-5a8a-4c68-8595-00210afd3c84	Pending	Gift Card	South America	Crystal Williams	2024-12-13	1	1	510.806556	11.86	2	510.806556
0e771643-5ea5-460d-8fc3-10e52ca45dc6	Cancelled	Gift Card	South America	Diane Andrews	2022-11-04	1	1	2956.47204	26.39	10	2956.47204
0e8d4121-b06e-43ff-895a-e3a97f873cb2	Cancelled	Amazon Pay	Asia	Michelle Andersen	2019-03-16	1	1	310.777224	4.01	1	310.777224
0e8e064c-e3df-4fc4-8aa7-bebc1e03da91	Pending	PayPal	North America	Diane Andrews	2019-08-27	1	1	270.02821600000004	12.02	4	270.02821600000004
0ecc986c-b98a-4422-bca0-73dd8409c215	Pending	Gift Card	Asia	Emily Matthews	2023-12-09	1	1	396.628974	13.06	9	396.628974
0edb1d84-ed19-41a1-8445-2024fc507b36	Returned	Debit Card	South America	Jason Nelson	2023-01-04	1	1	3247.0753400000003	2.82	10	3247.0753400000003
0ee70bef-9566-4fec-b7f7-fc5a1587833d	Cancelled	Gift Card	North America	Johnny Marshall	2024-07-16	1	1	787.8146320000001	20.58	4	787.8146320000001
0ef3d562-0ba7-4a49-88b5-0b5e66238020	Cancelled	Amazon Pay	Australia	Christina Thompson	2024-02-21	1	1	608.28117	14.89	7	608.28117
0f0647ee-b6a6-4874-9efc-efb5e13e39f1	Cancelled	Amazon Pay	Asia	Jason Nelson	2019-03-19	1	1	180.32778800000003	3.06	2	180.32778800000003
0f19e3a2-920a-41fa-8898-276e9d5a1a3d	Returned	Debit Card	Australia	Christina Thompson	2020-04-02	1	1	1064.284424	10.19	4	1064.284424
0f35f313-56be-4627-abfb-80b1db5813dc	Pending	Credit Card	North America	Crystal Williams	2021-11-20	1	1	699.7993560000001	28.09	4	699.7993560000001
0f470f5a-0753-4adb-b38e-c9a7b6ee371a	Returned	Debit Card	Europe	Adam Smith	2019-07-12	1	1	39.755286000000005	9.11	6	39.755286000000005
0f531748-a144-485f-b584-d120dacbf88f	Cancelled	Debit Card	South America	Sandra Luna	2020-11-19	1	1	1268.7134400000002	29.68	4	1268.7134400000002
0f61eb23-e92a-45c5-9bec-69129c952a72	Returned	Credit Card	South America	Diane Andrews	2024-07-20	1	1	4072.45401	6.49	10	4072.45401
0f7fbfc6-b085-482c-b4ac-fa1c6fe4ce42	Returned	Gift Card	Europe	Jason Nelson	2024-07-27	1	1	178.78492799999998	22.51	4	178.78492799999998
0f8db64e-77d7-4c20-9be8-bc6b70ddbe63	Pending	Debit Card	North America	Caitlyn Boyd	2023-04-09	1	1	237.71646	16.45	4	237.71646
0f9469d7-b960-4fa0-94ab-b1c9ba4b4d7f	Pending	Debit Card	South America	Mary Scott	2019-12-20	1	1	540.89238	11.59	10	540.89238
0fabae3a-e487-4409-bfbd-71253bedb892	Pending	Amazon Pay	South America	Susan Edwards	2024-02-24	1	1	2958.56064	18.47	8	2958.56064
0fb70590-920c-4338-9ee7-28812f1d223c	Returned	Gift Card	Australia	Christina Thompson	2020-04-10	1	1	2833.10208	0.4	8	2833.10208
0fc0565d-6b39-4d33-bcee-492a59d88dc1	Returned	Gift Card	South America	Caleb Camacho	2020-01-23	1	1	97.494432	0.88	2	97.494432
0fc52cfd-033c-4c9f-a433-6d9ac582594e	Returned	PayPal	Asia	Crystal Williams	2020-11-26	1	1	431.811912	28.12	2	431.811912
0fc86943-fd8b-4f66-9d31-aa652c30faa2	Pending	PayPal	Australia	Adam Smith	2023-08-27	1	1	2928.2248320000003	26.68	8	2928.2248320000003
0fe4588a-ad5e-4fc2-be8a-2e573c33921a	Returned	PayPal	South America	Susan Edwards	2021-08-13	1	1	420.07184400000006	23.48	3	420.07184400000006
0ff5f9f2-6915-4129-bb11-7da41ee028e0	Cancelled	Debit Card	South America	Susan Edwards	2020-08-08	1	1	1326.3700799999997	21.04	10	1326.3700799999997
10018696-5d2f-4704-aa68-42618a58f2f0	Cancelled	Credit Card	South America	Roger Brown	2023-10-21	1	1	4285.75602	2.29	10	4285.75602
100b61aa-1626-4b0c-a938-192d5bf4ac0b	Cancelled	Gift Card	Europe	Emily Matthews	2021-05-02	1	1	116.34925499999996	23.55	3	116.34925499999996
100c3aa8-226c-4e47-acba-28b75c006b37	Cancelled	Gift Card	South America	Charles Smith	2022-11-12	1	1	401.55722	25.61	10	401.55722
10201cec-e2b5-4d62-a536-f52563d11c90	Returned	Debit Card	Europe	Jason Nelson	2020-07-10	1	1	2196.31554	2.26	5	2196.31554
1024883c-4a29-4a1b-8c5f-46da99b54564	Pending	Amazon Pay	North America	Christina Thompson	2023-09-26	1	1	1602.678438	9.89	6	1602.678438
102ac7b1-27e1-4f70-a253-a9d7737ada81	Cancelled	PayPal	Australia	Emily Matthews	2024-02-22	1	1	2062.71624	15.78	8	2062.71624
1043bdcc-d7f1-45b8-a1c6-fd723bf232d8	Returned	Gift Card	Asia	Steven Coleman	2022-01-16	1	1	1723.7388600000002	18.7	9	1723.7388600000002
1045f5fe-d6db-4a9a-a96a-d613f13e1b1d	Pending	Credit Card	Europe	Roger Brown	2021-02-15	1	1	540.24138	29.26	2	540.24138
104f2072-edc2-4fce-a67f-b58bed65a6e0	Returned	Amazon Pay	Asia	Caitlyn Boyd	2020-01-16	1	1	676.471365	22.07	5	676.471365
10507065-7161-49c8-84f2-c36ce72081b3	Returned	Credit Card	North America	Caleb Camacho	2024-09-21	1	1	1597.25439	11.71	5	1597.25439
1052f8bf-de32-4875-88a9-39c020dec626	Cancelled	Gift Card	Asia	Emily Matthews	2024-06-03	1	1	2183.718042	6.94	9	2183.718042
106420ae-a75c-4962-91a2-8d3cdfac1922	Cancelled	Credit Card	Europe	Michelle Garza	2022-06-27	1	1	262.01340000000005	19.8	10	262.01340000000005
106570c4-fa77-4292-a995-dcb5cfe78d9e	Pending	Amazon Pay	North America	Caleb Camacho	2022-09-04	1	1	627.1902000000001	23.42	9	627.1902000000001
1073e044-aaff-4120-a368-f74559af3703	Pending	Credit Card	Asia	Emily Matthews	2023-01-06	1	1	359.294682	18.13	1	359.294682
108ca0b4-a767-4457-8645-a911cfa602fe	Pending	PayPal	Europe	Caitlyn Boyd	2023-04-29	1	1	856.2294800000001	4.46	4	856.2294800000001
10b3382f-7b4e-4538-b6bb-43db4d25a2d2	Returned	Amazon Pay	North America	Johnny Marshall	2023-01-13	1	1	3237.21432	21.2	9	3237.21432
10e00317-0e11-4a91-88bf-56f439afc2ee	Returned	Amazon Pay	South America	Charles Smith	2020-11-09	1	1	2353.3152	15.47	6	2353.3152
10f70481-e02c-4e47-ae07-827e546b6cc3	Returned	Gift Card	North America	Susan Edwards	2019-01-27	1	1	502.65891	29.57	5	502.65891
10fffb0b-a7e7-4334-b361-16f667440b66	Pending	Gift Card	Europe	Emily Matthews	2020-11-17	1	1	504.546777	29.81	7	504.546777
110efdc6-75e6-4da4-9076-a5b4a40d27aa	Cancelled	Credit Card	Australia	Roger Brown	2020-07-29	1	1	1589.4656400000003	26.48	7	1589.4656400000003
1112c99c-af54-471b-a178-fa919573c129	Pending	PayPal	Australia	Charles Smith	2021-02-09	1	1	189.54864	19.9	8	189.54864
113f1142-17af-41d3-98cb-3908714472dd	Returned	Debit Card	North America	Michelle Garza	2023-09-23	1	1	576.91212	15.15	6	576.91212
11504716-c235-40e5-b4c6-d786543dbb79	Returned	PayPal	Europe	Steven Coleman	2023-06-13	1	1	1790.88378	6.45	6	1790.88378
115e8a64-82d4-42a7-83b2-b7d2fa05d7f4	Cancelled	PayPal	Europe	Johnny Marshall	2020-06-04	1	1	3115.088262	27.98	9	3115.088262
1161a209-6126-40d6-8353-c0f34e056d3f	Returned	PayPal	North America	Jason Nelson	2023-09-10	1	1	1883.325192	6.62	6	1883.325192
11687bbd-6fb9-4a19-951b-8e037812411e	Pending	Amazon Pay	North America	Caitlyn Boyd	2021-06-05	1	1	472.346056	28.11	8	472.346056
11721057-4e8d-4850-9ca2-0dac94acee25	Cancelled	Credit Card	South America	Emily Matthews	2021-07-08	1	1	3680.2283	9.51	10	3680.2283
1182eb38-5205-40d6-b8db-1162a5ba89c6	Cancelled	Amazon Pay	South America	Michelle Garza	2023-11-17	1	1	1539.74304	14.23	4	1539.74304
1183d64d-93d5-405c-8319-e6eef63e34c4	Returned	Amazon Pay	Australia	Mary Scott	2024-06-27	1	1	3033.5544	26.8	10	3033.5544
118f0d61-31c2-4778-9874-a7b3fd50660b	Pending	PayPal	Australia	Caleb Camacho	2024-12-13	1	1	402.915024	1.13	8	402.915024
11d704c5-f07f-4800-ad94-28fe71c159d8	Returned	Credit Card	Asia	Johnny Marshall	2024-10-22	1	1	1163.979376	20.16	7	1163.979376
11d932a7-21e3-4766-8c12-0f79cb37d276	Pending	Amazon Pay	Australia	Steven Coleman	2020-09-27	1	1	2382.9672930000006	8.53	7	2382.9672930000006
11e17e44-c37b-41d4-8ed5-96bcd8245b07	Pending	Amazon Pay	Asia	Roger Brown	2023-10-18	1	1	264.137959	25.37	1	264.137959
11edce34-c058-4a2a-9385-03463c1bf3c8	Returned	PayPal	Europe	Caleb Camacho	2021-04-25	1	1	1412.5998599999998	8.65	4	1412.5998599999998
11f78e0b-05b1-4806-9e84-e5379f89e486	Cancelled	Debit Card	Australia	Adam Smith	2024-09-02	1	1	485.863232	27.63	4	485.863232
1207f398-70e2-48ce-81ba-e738826a45e9	Returned	Credit Card	North America	Caleb Camacho	2021-05-22	1	1	486.5389200000001	16.66	10	486.5389200000001
1211b934-1e2f-410d-b8cb-14d7e12201e7	Pending	Credit Card	North America	Michelle Andersen	2019-12-02	1	1	2147.523868	2.34	7	2147.523868
121b3687-240e-45c8-abdf-b697e8c6e739	Cancelled	Gift Card	North America	Kristen Ramos	2024-02-18	1	1	804.6478079999999	18.28	4	804.6478079999999
121bf059-567a-4229-97b3-367cfdad2f4d	Returned	Gift Card	North America	Bradley Howe	2024-03-01	1	1	3490.43046	10.79	10	3490.43046
12319aa6-747c-4fa9-b5cf-fbd4f21ea19c	Pending	Credit Card	Australia	Emily Matthews	2020-04-11	1	1	1340.969728	23.52	7	1340.969728
1241f47e-168e-424c-be71-221fab4a983c	Pending	Amazon Pay	Asia	Bradley Howe	2024-03-30	1	1	544.174296	15.38	3	544.174296
12438d3e-7859-466c-a616-f4253179652e	Pending	Debit Card	Australia	Diane Andrews	2021-01-28	1	1	900.4447759999999	20.34	7	900.4447759999999
1244eab5-a1f2-4c68-b59e-ace7b8278b00	Pending	Credit Card	Asia	Emily Matthews	2022-01-11	1	1	683.8615500000001	28.26	5	683.8615500000001
124cf762-0e09-4502-8751-6c41b337d1e1	Pending	Debit Card	Australia	Michelle Andersen	2023-01-04	1	1	13.921908	18.87	1	13.921908
124d19c9-a06a-485a-a7fa-1de343e13d3e	Pending	PayPal	Australia	Joseph Brooks	2020-06-04	1	1	1010.966334	4.57	7	1010.966334
12521889-a202-4653-bddd-c06463a72a3f	Pending	Gift Card	Europe	Christina Thompson	2023-12-14	1	1	872.5826519999999	15.49	4	872.5826519999999
1267303e-bfcf-46b2-a2f3-499e61ad475d	Cancelled	PayPal	South America	Caleb Camacho	2022-01-08	1	1	394.0029	0.05	4	394.0029
126c5c71-b5e6-4fa1-87fb-ae1e7d253e7e	Pending	PayPal	South America	Susan Edwards	2022-09-27	1	1	1094.9972	6.5	4	1094.9972
127c1d70-e133-4f36-9085-fdd290005cfa	Cancelled	Amazon Pay	Europe	Emily Matthews	2019-06-22	1	1	180.40264	22.2	1	180.40264
127ebd53-68b5-4577-a247-e035f67465e3	Returned	Gift Card	Asia	Michelle Andersen	2020-11-22	1	1	100.708275	29.55	5	100.708275
128b8734-888b-4a0a-808b-21b1d9aaf201	Returned	PayPal	Australia	Caleb Camacho	2022-06-22	1	1	2755.053558	2.03	9	2755.053558
12ac7f68-edcb-42c6-838a-37261196fc00	Pending	Credit Card	Europe	Christina Thompson	2020-02-28	1	1	1117.096442	28.61	7	1117.096442
12b14ce7-daa8-4769-b54e-585f75afded6	Returned	Amazon Pay	North America	Caleb Camacho	2022-12-18	1	1	306.046034	8.79	1	306.046034
12ba52d8-ffe3-49ae-ac8a-9ca13e1abe37	Cancelled	Debit Card	South America	Caitlyn Boyd	2024-04-22	1	1	487.6067280000001	29.36	3	487.6067280000001
12dd9f4a-c49d-4737-a566-79813d126445	Pending	Gift Card	Asia	Johnny Marshall	2020-02-08	1	1	2074.575552	28.08	7	2074.575552
12effac6-f232-4ab6-b231-361c1f6b0d6b	Returned	Amazon Pay	Europe	Charles Smith	2020-05-27	1	1	1675.63602	14.9	6	1675.63602
12f3ccec-d3f0-43a9-b652-0f88a60737b8	Returned	Amazon Pay	Europe	Crystal Williams	2022-02-23	1	1	3321.397248	4.32	8	3321.397248
131f8498-ec7c-4644-b248-73794461ca96	Returned	PayPal	Europe	Crystal Williams	2019-07-20	1	1	178.93509999999998	26.75	2	178.93509999999998
13286a9c-1a02-4e57-841a-b93bc15818be	Returned	PayPal	Asia	Crystal Williams	2021-12-15	1	1	4031.67296	12.84	10	4031.67296
133b209f-9d63-4788-9857-1be4e54fd1aa	Cancelled	Amazon Pay	Europe	Roger Brown	2024-02-06	1	1	165.35857	8.49	5	165.35857
133cca53-4292-4311-9478-20d194ca0e5d	Cancelled	Gift Card	Europe	Steven Coleman	2024-05-01	1	1	122.98254	17.15	1	122.98254
134b5daf-4858-4e29-a0f0-a7da18afa4bf	Pending	Credit Card	Asia	Steven Coleman	2022-02-03	1	1	841.3212	15.53	8	841.3212
1358dbc1-cee2-4917-8289-428b91c190be	Returned	Amazon Pay	Europe	Roger Brown	2023-02-27	1	1	1944.568944	24.58	6	1944.568944
13608523-b251-4585-a429-9c87f98e71ab	Returned	Gift Card	Asia	Charles Smith	2024-06-24	1	1	12.641632	6.08	1	12.641632
13765e8c-c3ee-4130-8e93-5c3ca40a1bf3	Cancelled	Amazon Pay	Europe	Joseph Brooks	2019-09-16	1	1	1727.1087839999998	1.68	6	1727.1087839999998
1391007d-084f-4125-a80c-e121af41c0f2	Cancelled	Amazon Pay	Europe	Caleb Camacho	2020-01-10	1	1	1415.5375	12.89	5	1415.5375
139ac87f-6361-4f68-ad9a-49bd3eb75464	Returned	Credit Card	South America	Emily Matthews	2023-12-31	1	1	244.855608	19.73	6	244.855608
13a65d83-bd0c-498d-90a7-cd94c95cc7ed	Returned	Credit Card	Asia	Michelle Garza	2021-08-14	1	1	146.834424	14.76	9	146.834424
13d0ada9-bf30-4544-984e-49cc95e15c2c	Pending	Amazon Pay	South America	Bradley Howe	2020-03-19	1	1	2143.293383	9.89	7	2143.293383
13f4cac0-f50b-42f2-9612-ca9bd63218aa	Returned	Amazon Pay	North America	Steven Coleman	2019-11-19	1	1	120.99540000000002	4.2	10	120.99540000000002
13fbecd0-8f00-4786-9519-7d1776eed88f	Cancelled	Credit Card	North America	Michelle Garza	2020-02-14	1	1	357.064435	23.81	1	357.064435
142c5c38-0918-4987-b0e9-312df6836fd2	Returned	Amazon Pay	Australia	Bradley Howe	2023-06-23	1	1	1923.53557	3.42	5	1923.53557
143e7cf0-b71e-4ce5-b857-79d08216a725	Cancelled	Credit Card	Asia	Emily Matthews	2022-03-21	1	1	1161.7919519999998	2.58	8	1161.7919519999998
147ab830-dd1b-413a-9b7e-ad1c644836d8	Cancelled	PayPal	South America	Jason Nelson	2019-11-04	1	1	1009.688904	13.69	8	1009.688904
147e6471-3073-4dbe-b9af-22ab15457d12	Returned	Credit Card	Asia	Roger Brown	2023-06-19	1	1	904.7686	8.6	5	904.7686
148e1f50-c64e-46e1-ae49-823487bdce51	Pending	Gift Card	Asia	Crystal Williams	2022-01-03	1	1	1286.026485	19.49	5	1286.026485
148ef578-c3ec-4e13-961e-f36c2b042c34	Cancelled	Debit Card	South America	Crystal Williams	2019-10-12	1	1	343.782873	29.77	9	343.782873
14cba2fa-82d6-44b6-816e-d13217a76151	Cancelled	Gift Card	Australia	Bradley Howe	2019-11-17	1	1	1282.323492	12.06	6	1282.323492
14d606dc-adf6-4785-b28e-f79e97c88d31	Cancelled	PayPal	Australia	Roger Brown	2020-11-14	1	1	231.245504	22.38	7	231.245504
14d6947a-4fb2-45d2-8bcc-017c9365b3e2	Cancelled	Gift Card	South America	Christina Thompson	2019-02-04	1	1	193.08635	11.55	10	193.08635
14eac9a8-650f-4021-92e7-8ff295f85aad	Returned	Gift Card	North America	Steven Coleman	2019-11-13	1	1	148.19	12.5	8	148.19
14f01528-f8f5-4200-963f-73373a20d70f	Cancelled	Debit Card	North America	Johnny Marshall	2020-05-13	1	1	1086.80397	15.46	5	1086.80397
14f93e38-3406-4ab7-89eb-1d3cba94dce8	Returned	Gift Card	Europe	Bradley Howe	2020-04-30	1	1	652.1910399999999	3.92	4	652.1910399999999
15042d37-aa59-4c27-9727-b159ff7fce55	Cancelled	Debit Card	South America	Michelle Andersen	2023-04-19	1	1	748.929519	17.71	3	748.929519
151268cc-2296-4181-853f-2cd041227733	Returned	Debit Card	Australia	Roger Brown	2021-08-03	1	1	929.75155	18.45	10	929.75155
1513b64b-aedb-4f87-acf3-806b5486d740	Cancelled	Amazon Pay	North America	Diane Andrews	2019-04-19	1	1	1892.70115	18.18	5	1892.70115
1526425a-2441-4bd9-a909-e9b261f76ac1	Returned	PayPal	Australia	Michelle Garza	2024-09-05	1	1	895.196322	11.93	6	895.196322
1532bcbb-23ba-4c01-8e9e-0dbd784887ac	Returned	Amazon Pay	South America	Michelle Andersen	2024-08-30	1	1	763.3286909999999	8.89	3	763.3286909999999
154a5712-2285-40e9-9d5b-91a414717ba8	Returned	Amazon Pay	South America	Adam Smith	2020-05-08	1	1	1000.75565	23.81	5	1000.75565
154c0ed8-a576-4bc2-bb76-e9fb984c2d0a	Cancelled	Credit Card	Europe	Caleb Camacho	2019-09-01	1	1	1306.8806400000003	3.28	5	1306.8806400000003
154f5732-97f4-4796-958d-23d8051f5933	Cancelled	Debit Card	Australia	Kristen Ramos	2024-10-18	1	1	3111.553837	1.17	7	3111.553837
15556d96-2f83-4f93-819e-c43e45914e79	Cancelled	Amazon Pay	Australia	Sandra Luna	2022-08-27	1	1	1040.6186	22.86	5	1040.6186
155778e7-2899-47bc-b41c-04460c9d78cd	Pending	Amazon Pay	Asia	Michelle Garza	2023-12-07	1	1	523.76184	28.6	6	523.76184
15657c0c-e4bc-45ca-af63-5cc917317dd5	Pending	Gift Card	Asia	Susan Edwards	2019-06-29	1	1	884.17238	2.42	2	884.17238
157710ae-dc29-4ec0-aed8-9e25e28b5cbd	Cancelled	PayPal	Australia	Roger Brown	2021-07-04	1	1	1684.5138099999997	12.57	5	1684.5138099999997
15905865-7698-4eea-aaf2-9358f44a0f99	Returned	Amazon Pay	South America	Jason Nelson	2020-03-31	1	1	328.093698	8.41	1	328.093698
15a3ae52-0f8a-47d1-af9f-5617d8a0f862	Returned	Gift Card	Australia	Emily Matthews	2019-04-15	1	1	1689.346952	10.29	4	1689.346952
15ae1d35-0f17-4082-821d-62a02d8b92f3	Pending	Credit Card	Australia	Mary Scott	2024-02-05	1	1	1612.761435	18.19	5	1612.761435
15da795b-b85b-4cf0-8dee-bdb6ef1b029f	Cancelled	Amazon Pay	Europe	Sandra Luna	2022-12-29	1	1	184.644207	17.83	1	184.644207
15e5a6f8-dcc3-444f-b3bf-451c2bca202d	Cancelled	Credit Card	Europe	Steven Coleman	2024-12-31	1	1	563.4501	10.2	5	563.4501
15edc679-5424-4786-8c01-2fa59ed3e417	Returned	Credit Card	North America	Sandra Luna	2022-02-07	1	1	202.031368	16.44	7	202.031368
15f8770f-f58c-4487-ad52-6f489127a569	Returned	PayPal	South America	Steven Coleman	2020-01-29	1	1	556.732935	12.55	3	556.732935
1600b6a8-30be-468c-86c2-cfaddde1cb2a	Cancelled	Gift Card	Asia	Jason Nelson	2021-01-15	1	1	2323.700736	15.72	8	2323.700736
160c2ea2-084b-4e7c-93b8-cd9e38379116	Returned	Gift Card	Asia	Sandra Luna	2021-11-21	1	1	1770.3814149999998	26.63	5	1770.3814149999998
1620ad91-e780-4103-9c16-266597207efd	Cancelled	Gift Card	South America	Susan Edwards	2022-06-25	1	1	294.91021800000004	24.81	3	294.91021800000004
16230dd4-28ae-470a-b779-99c0b3078493	Returned	Gift Card	Europe	Adam Smith	2024-12-15	1	1	537.4907999999999	16.9	8	537.4907999999999
162aa5fa-e6ad-4b08-896f-34147c34eea6	Cancelled	Debit Card	North America	Susan Edwards	2024-04-27	1	1	570.374	26.64	5	570.374
163ea91a-0bf5-4e09-ad6f-ef62c1051fa9	Returned	Amazon Pay	Asia	Caleb Camacho	2021-12-03	1	1	657.7333760000001	14.96	2	657.7333760000001
16423c53-ee35-4011-957c-51d9ca3a02b0	Returned	Credit Card	Australia	Michelle Garza	2019-03-08	1	1	796.6800000000001	20	5	796.6800000000001
164f69d7-31fb-48ca-af22-29ce4863da8e	Returned	Credit Card	Australia	Bradley Howe	2020-04-27	1	1	2356.243182	18.79	9	2356.243182
1650d7e1-0e7a-487b-a1ed-2d117178157a	Cancelled	Gift Card	North America	Crystal Williams	2019-12-11	1	1	701.8128000000002	26.65	10	701.8128000000002
165a27ba-03d1-4dbb-b8b5-a946c9c3da6e	Pending	Gift Card	Australia	Caitlyn Boyd	2024-11-06	1	1	736.72731	15.74	5	736.72731
165b8c35-ae10-4780-839d-455edfee1760	Returned	Amazon Pay	Asia	Crystal Williams	2022-11-02	1	1	165.3828	8.88	6	165.3828
16712e7a-e9d4-4e76-b410-da65d30f5ca2	Cancelled	PayPal	South America	Sandra Luna	2019-07-13	1	1	626.00076	23.77	10	626.00076
16b48f31-75ba-4b5e-aa66-07130cf097a1	Cancelled	Amazon Pay	South America	Diane Andrews	2020-12-11	1	1	1546.498304	18.72	4	1546.498304
16be0ae9-61fd-40a8-aadf-9ca95c74557d	Pending	Amazon Pay	North America	Johnny Marshall	2023-12-06	1	1	3577.9519600000003	21.02	10	3577.9519600000003
16c282de-2b41-46b4-b6d9-5f4b6596553c	Cancelled	Credit Card	South America	Michelle Garza	2023-01-27	1	1	430.2126080000001	23.84	2	430.2126080000001
16c9ed3e-3aac-49ad-a9c1-265e2e1c77f4	Cancelled	Credit Card	Asia	Caleb Camacho	2020-03-18	1	1	1118.732016	24.78	8	1118.732016
16cca0e6-c137-4345-9e6b-977b061bbf7f	Pending	Debit Card	South America	Susan Edwards	2022-04-20	1	1	1108.908486	0.33	9	1108.908486
16d5b741-ebde-43ac-9e21-25d511484a96	Pending	Debit Card	Europe	Kristen Ramos	2023-09-13	1	1	21.417165	2.87	3	21.417165
16f3c50c-27e5-4024-99e8-c5aadee96c83	Pending	Amazon Pay	South America	Caitlyn Boyd	2023-12-31	1	1	207.11493	4.18	3	207.11493
16f71c33-6a0a-40e2-8304-7e6c55f5ee6c	Cancelled	Debit Card	Asia	Steven Coleman	2022-12-18	1	1	250.19618400000004	14.96	7	250.19618400000004
17211c67-c44f-43ca-86d1-3847e75a2eee	Returned	Amazon Pay	North America	Emily Matthews	2023-03-07	1	1	398.200725	25.25	3	398.200725
17213d10-1727-41a7-9af8-7ab6072c9a10	Returned	Credit Card	Asia	Steven Coleman	2023-07-23	1	1	3081.70272	18.68	8	3081.70272
17720dfd-d4b2-4629-a74e-05758913e669	Returned	Debit Card	South America	Emily Matthews	2021-03-13	1	1	384.4673	25.8	5	384.4673
17765ce1-bf82-4b86-9315-0e9c78798452	Cancelled	Debit Card	Asia	Kristen Ramos	2024-08-09	1	1	1186.709349	19.49	7	1186.709349
179387a5-a464-4eb9-9388-a2885b404a52	Pending	Amazon Pay	South America	Adam Smith	2021-10-24	1	1	1322.185424	12.78	4	1322.185424
17ab84d0-d3e8-483d-844d-3d745e555d9a	Cancelled	Gift Card	South America	Michelle Garza	2020-12-12	1	1	299.00696000000005	16.08	2	299.00696000000005
17c50e75-f42e-4f51-9c9b-6e8c8fd338ef	Pending	Debit Card	South America	Steven Coleman	2020-05-18	1	1	1886.7576	13.61	10	1886.7576
17c84bee-0d1e-4171-939d-d682f67ae07c	Cancelled	Debit Card	Europe	Mary Scott	2024-10-13	1	1	1800.06084	25.3	6	1800.06084
17cb3429-6399-46cc-a2c0-46a269832f8a	Returned	Debit Card	Europe	Caitlyn Boyd	2020-12-12	1	1	2811.65152	1.04	8	2811.65152
17d4f9a0-efbd-4458-86dd-1b7eb3f895ea	Returned	PayPal	Australia	Susan Edwards	2020-11-23	1	1	601.1406799999999	7.4	2	601.1406799999999
17d7214f-c96f-4ed6-9ab4-55e7c1e95874	Pending	Credit Card	Australia	Roger Brown	2023-12-09	1	1	418.09452	19.24	10	418.09452
17dd1bc8-80f6-4845-ab0f-73d306584194	Cancelled	Credit Card	South America	Susan Edwards	2020-12-28	1	1	262.178477	1.47	1	262.178477
17e2194e-3922-4d84-ab30-b4cfa67b9af3	Cancelled	Gift Card	Australia	Caitlyn Boyd	2019-03-04	1	1	269.72676	29.2	3	269.72676
1826755d-b696-4547-a2db-03785b3e12eb	Cancelled	Credit Card	Australia	Christina Thompson	2021-09-11	1	1	1095.519978	11.37	9	1095.519978
1826e86f-5b06-4656-8595-284ee8956e46	Returned	Debit Card	Europe	Joseph Brooks	2024-01-31	1	1	364.3064	24.8	5	364.3064
183b9fc9-7342-401f-836c-19b5d0ba0f25	Returned	PayPal	South America	Mary Scott	2020-04-25	1	1	340.001123	22.89	1	340.001123
1855a109-6b2f-4b1f-b402-48a1d8950f70	Returned	Amazon Pay	Australia	Charles Smith	2020-05-15	1	1	917.63784	10.64	5	917.63784
1874cd66-90b7-40df-94fd-65845347417d	Returned	Gift Card	Europe	Roger Brown	2022-11-06	1	1	1993.476618	26.31	9	1993.476618
187854c6-2d1b-4de9-8c17-61b2a5d80b69	Cancelled	PayPal	North America	Caleb Camacho	2023-09-23	1	1	1005.384963	1.11	3	1005.384963
1880e3bf-6e50-4fa4-8830-e1aae1bd0be4	Cancelled	PayPal	Australia	Adam Smith	2019-11-17	1	1	77.60705	12.06	1	77.60705
189aa4af-0c25-4dbd-bc85-383e19fdfad5	Pending	Credit Card	Australia	Adam Smith	2024-04-20	1	1	673.50048	9.67	5	673.50048
189d171e-716e-4648-9dc5-eb023fcb719e	Cancelled	Debit Card	North America	Crystal Williams	2020-05-17	1	1	1630.8409	16.41	5	1630.8409
18a488d6-18b1-4bea-b8c4-5cfd08455045	Pending	Amazon Pay	South America	Crystal Williams	2023-07-07	1	1	3359.2435200000004	7.52	10	3359.2435200000004
18b77f69-e860-4da6-af09-a8f54e5bca1a	Pending	PayPal	Australia	Crystal Williams	2023-07-20	1	1	2071.731195	13.95	9	2071.731195
18b79058-21ce-4e82-9533-b354b5c9bcf7	Pending	Gift Card	Europe	Steven Coleman	2020-02-05	1	1	938.9648699999998	25.99	6	938.9648699999998
190d3a19-7c0a-4b2c-85c8-05175e04f2d9	Pending	PayPal	South America	Emily Matthews	2019-09-03	1	1	249.86200800000003	4.08	1	249.86200800000003
1916f739-d7cf-41d8-9d1e-dcd1a46bee7b	Cancelled	Credit Card	Asia	Diane Andrews	2021-04-23	1	1	1574.217442	25.43	7	1574.217442
1920afb1-e3f6-499f-8172-a3f0932c7c08	Cancelled	Debit Card	Australia	Sandra Luna	2022-04-23	1	1	496.692	9.28	5	496.692
193151af-83ed-4e82-828a-e3351fc95231	Pending	Gift Card	Europe	Caitlyn Boyd	2019-03-27	1	1	1629.705825	4.57	9	1629.705825
1934b2e9-1fc4-4412-b578-cff4de5ab059	Returned	Amazon Pay	North America	Diane Andrews	2023-10-19	1	1	2107.501328	13.61	8	2107.501328
194a2192-cb1b-4f81-9f81-f66fc9fa6568	Returned	Amazon Pay	North America	Christina Thompson	2022-10-30	1	1	173.3184	29.2	10	173.3184
194b72b7-0c62-4841-a810-ccd640bf7f68	Cancelled	Gift Card	South America	Caleb Camacho	2022-05-05	1	1	480.517272	14.52	9	480.517272
1988529c-5145-4fd4-9e68-f8b4452cc8d1	Returned	Gift Card	South America	Kristen Ramos	2020-12-30	1	1	2645.415136	22.52	7	2645.415136
1994e41a-2104-48d3-aac8-5ebdc17ec4ac	Returned	Credit Card	Asia	Christina Thompson	2020-01-30	1	1	1761.48024	4.9	8	1761.48024
19a031c2-7c2b-4199-ae86-900799d4619c	Pending	Debit Card	North America	Emily Matthews	2022-12-21	1	1	604.397112	13.43	2	604.397112
19a7d3b8-c504-4ccb-934e-c5c5bd5f8327	Cancelled	Gift Card	South America	Michelle Andersen	2024-07-18	1	1	978.77916	25.3	3	978.77916
19aedbd9-b1c6-4498-8b15-2a855ee4ed86	Pending	Gift Card	Australia	Caitlyn Boyd	2020-02-05	1	1	1594.79481	7.81	10	1594.79481
19e8b2b9-54e8-400a-ab0d-5373811695b0	Returned	Credit Card	Europe	Jason Nelson	2021-09-27	1	1	670.87554	10.65	4	670.87554
19ebeb0a-2e71-4c52-a67a-29970d9fa307	Cancelled	Debit Card	North America	Christina Thompson	2023-07-11	1	1	183.26115	16.3	5	183.26115
1a1a6f14-e49e-402f-9708-8842c3ae057b	Cancelled	Gift Card	North America	Charles Smith	2021-11-10	1	1	1233.32256	17.2	8	1233.32256
1a289ad1-983a-4b87-8ca8-3cb59ef0806c	Cancelled	Credit Card	Asia	Emily Matthews	2024-07-29	1	1	1967.040516	9.83	7	1967.040516
1a3329f1-235d-4d96-a429-e76709f2b703	Pending	PayPal	Asia	Susan Edwards	2024-09-17	1	1	115.07148	13.61	3	115.07148
1a3c0ffe-3868-4cca-bfaf-661d35d1fe16	Pending	Gift Card	Europe	Diane Andrews	2022-05-17	1	1	1376.6243599999998	19.16	10	1376.6243599999998
1a506c3e-53ce-498c-8d29-9e866b08b415	Returned	Amazon Pay	Australia	Roger Brown	2020-05-20	1	1	389.45907	13.54	1	389.45907
1a5f3542-5498-4df4-855b-1e0a9638276b	Pending	Debit Card	South America	Caitlyn Boyd	2019-09-14	1	1	637.085475	22.15	5	637.085475
1a65bdcf-3cd2-4e10-ad55-e933b897b107	Returned	Debit Card	Europe	Susan Edwards	2024-02-29	1	1	574.03	16.2	2	574.03
1aa07b11-9627-4462-bb8d-e8100e6714e3	Cancelled	Gift Card	Australia	Crystal Williams	2021-09-09	1	1	626.63264	22.08	2	626.63264
1ac2557c-6c33-4a48-8231-98f36b357f24	Cancelled	Debit Card	Australia	Susan Edwards	2022-07-08	1	1	744.4967039999999	9.19	6	744.4967039999999
1ae9818a-59c5-49d6-a843-6690b9d099a9	Pending	PayPal	Australia	Kristen Ramos	2019-06-15	1	1	3108.85064	18.42	10	3108.85064
1aee5256-cbd5-4c0d-87eb-e4e203001e06	Cancelled	PayPal	South America	Bradley Howe	2022-02-24	1	1	2943.123456	9.76	8	2943.123456
1af61522-043b-42d0-a22e-fd67f9dc56da	Pending	Credit Card	North America	Charles Smith	2023-10-15	1	1	3893.059017	2.53	9	3893.059017
1b17900f-daf5-4623-bc8f-274f13ac3b68	Pending	Amazon Pay	North America	Kristen Ramos	2019-12-02	1	1	1649.0821600000002	29.88	10	1649.0821600000002
1b2589a6-eb6d-41e5-b291-cd411d364a75	Pending	PayPal	Europe	Charles Smith	2020-03-07	1	1	153.50973299999998	4.23	9	153.50973299999998
1b2830f3-33c0-49f0-9b85-e271bbd71c1f	Pending	PayPal	Europe	Michelle Garza	2023-11-04	1	1	347.588865	10.95	1	347.588865
1b38e7a9-75f3-4b1d-89d5-a4fd249d8a7b	Pending	Debit Card	Europe	Diane Andrews	2020-02-21	1	1	2936.384937	21.27	9	2936.384937
1b630c26-dfd4-4c56-b990-bc0208008b86	Returned	Amazon Pay	Australia	Michelle Garza	2022-01-07	1	1	2315.00412	24.73	8	2315.00412
1b6e4bb1-8738-4db2-a2c8-54fee2872b9e	Returned	Credit Card	South America	Joseph Brooks	2022-06-02	1	1	1073.093544	5.74	4	1073.093544
1b886ccc-901f-47d1-b6f5-4ef0f9fed20f	Pending	Debit Card	South America	Michelle Garza	2020-10-10	1	1	2544.123384	11.89	8	2544.123384
1b8d610d-7532-41df-966e-0a3c15b6860f	Cancelled	Credit Card	Asia	Christina Thompson	2023-11-27	1	1	3290.548	13.86	10	3290.548
1b9a5c31-f873-4c1e-9ec4-95c93319ee02	Cancelled	Amazon Pay	Australia	Johnny Marshall	2024-12-10	1	1	3736.4598	0.1	10	3736.4598
1bb3577b-efb5-4e2b-a16f-74cd3962e739	Cancelled	Credit Card	South America	Adam Smith	2023-09-18	1	1	1773.010404	6.82	9	1773.010404
1bc7d8ba-bc06-4546-b0fa-1262f55ba0b6	Cancelled	PayPal	Australia	Caleb Camacho	2024-07-25	1	1	1196.905686	13.02	3	1196.905686
1bd76dd1-5c69-40c7-8bb1-475868235560	Cancelled	Gift Card	South America	Mary Scott	2020-08-12	1	1	2375.053788	3.62	6	2375.053788
1bd81021-d9e2-45b2-928b-6e1af5cdcef6	Returned	Debit Card	South America	Mary Scott	2024-03-18	1	1	1104.81344	4.56	5	1104.81344
1bf87114-3515-46df-a54a-35c4f61edc73	Cancelled	Gift Card	Australia	Caleb Camacho	2022-08-17	1	1	349.45687200000003	26.32	1	349.45687200000003
1c048052-9601-4df0-8ed9-986476b99532	Cancelled	Gift Card	North America	Jason Nelson	2024-04-11	1	1	258.807276	29.02	3	258.807276
1c23ac05-026f-46bc-a589-9f9c86ea29e3	Pending	Credit Card	South America	Michelle Garza	2022-11-21	1	1	3719.253384	12.08	9	3719.253384
1c43e98b-7eff-44b4-8343-0a4865347d11	Pending	PayPal	Europe	Diane Andrews	2022-03-26	1	1	599.673348	8.29	3	599.673348
1c453376-ed06-4634-8cc2-c3de48e07353	Cancelled	Credit Card	Asia	Johnny Marshall	2019-08-07	1	1	240.411624	19.67	4	240.411624
1c4b4921-dd00-40cb-b9af-3507843869c4	Pending	Gift Card	South America	Sandra Luna	2019-01-21	1	1	1668.7007400000002	22.84	5	1668.7007400000002
1c761929-ec95-4c0c-8298-ddcd81aa00fb	Cancelled	PayPal	Asia	Michelle Andersen	2020-10-27	1	1	493.37965	9.18	5	493.37965
1c77bc86-2056-4bc2-a22d-7c503a2a2e76	Cancelled	PayPal	Australia	Emily Matthews	2024-11-19	1	1	1619.970408	13.06	4	1619.970408
1c8156dd-69f9-4463-870b-308c841a9d35	Cancelled	Debit Card	Asia	Johnny Marshall	2021-05-05	1	1	3612.50562	23.54	10	3612.50562
1c9f684f-284c-4d6b-9b85-e5d6b48fd3ab	Returned	Gift Card	Australia	Emily Matthews	2024-08-17	1	1	295.15335	3.45	10	295.15335
1cc2d1ff-64a8-429e-97cd-e11b2d56fa1c	Returned	PayPal	North America	Christina Thompson	2024-03-07	1	1	766.0659719999999	4.59	2	766.0659719999999
1cf3b3f6-51cc-48cd-84cb-c9452236b2a6	Returned	Amazon Pay	Europe	Roger Brown	2020-05-02	1	1	423.522594	10.57	2	423.522594
1cf629af-9f4e-4c54-8427-ec032268f930	Cancelled	Amazon Pay	Asia	Diane Andrews	2019-07-18	1	1	21.315276	4.33	4	21.315276
1cfd5970-5cc5-4fad-9b98-ad71ca473237	Pending	Debit Card	Asia	Charles Smith	2023-12-23	1	1	2768.597118	27.41	9	2768.597118
1d1a8110-e47a-40c0-bc51-4290f1108530	Cancelled	Gift Card	South America	Caitlyn Boyd	2020-08-12	1	1	726.5881919999999	0.56	6	726.5881919999999
1d3387f4-8c00-4b3e-8203-e8e1b1e87877	Cancelled	PayPal	North America	Michelle Andersen	2024-02-27	1	1	1747.5199999999998	14	10	1747.5199999999998
1d4079aa-a8df-4358-9eae-6882a1b7e187	Pending	Credit Card	South America	Roger Brown	2021-09-16	1	1	1562.74944	0.74	5	1562.74944
1d520b6c-1d12-4f37-a944-5f50b215f832	Pending	Amazon Pay	Australia	Roger Brown	2022-09-27	1	1	133.52411999999998	17.04	5	133.52411999999998
1d66f19e-ab83-4d8b-95d9-277a0da41dab	Cancelled	Debit Card	Europe	Diane Andrews	2021-07-27	1	1	531.0274320000001	26.68	3	531.0274320000001
1d7f526d-138d-41db-be97-eac92a144af4	Pending	Credit Card	Australia	Charles Smith	2019-01-29	1	1	574.4483799999999	17.63	10	574.4483799999999
1db75666-feb6-4cfa-bb78-69bac6c16b5d	Cancelled	Amazon Pay	North America	Charles Smith	2022-07-22	1	1	836.6562809999999	23.57	9	836.6562809999999
1dbf50e2-0b0a-4af0-a7a9-d28c71a5512a	Pending	Credit Card	South America	Michelle Garza	2023-03-19	1	1	2851.71621	18.31	10	2851.71621
1dc0f0ca-729b-4079-865f-fee7880684ac	Returned	Debit Card	Asia	Caitlyn Boyd	2021-11-26	1	1	2627.0835420000003	8.31	6	2627.0835420000003
1dce4a08-b65f-45b7-85cf-b5a42e8f05ff	Pending	Gift Card	South America	Caleb Camacho	2021-10-25	1	1	941.3834879999998	23.92	4	941.3834879999998
1dd1c34f-4f46-45eb-ac54-314d7fab80f1	Returned	PayPal	Europe	Charles Smith	2019-04-08	1	1	675.146608	25.16	4	675.146608
1df948c2-4a0d-4f6d-ab21-e86a2b2c50fa	Pending	PayPal	Asia	Jason Nelson	2022-09-23	1	1	3047.45328	12.91	9	3047.45328
1dff2229-3c41-4079-a1e9-1f9e87405e75	Returned	PayPal	North America	Caitlyn Boyd	2024-08-22	1	1	1163.962812	15.53	6	1163.962812
1e023262-0260-4feb-9bc6-8d8ab9536611	Returned	Debit Card	Asia	Diane Andrews	2019-05-16	1	1	1306.107	24.85	10	1306.107
1e1c45c6-80ee-4daf-a335-e15a80abe77f	Pending	Debit Card	Europe	Jason Nelson	2022-12-01	1	1	437.703616	8.69	1	437.703616
1e5269dd-14f2-490c-b884-278c8c687186	Pending	Gift Card	South America	Adam Smith	2024-07-17	1	1	2460.709696	13.86	8	2460.709696
1e53b0ec-8091-432b-aa55-36190d377793	Returned	Debit Card	Europe	Johnny Marshall	2023-04-13	1	1	489.009904	8.76	4	489.009904
1e551b5d-a02d-4a8e-949a-f68b401ba87f	Pending	Credit Card	Australia	Susan Edwards	2024-08-01	1	1	1344.18384	7.92	3	1344.18384
1e55d55f-02a1-4242-85b5-4744aa9744d6	Pending	Debit Card	North America	Joseph Brooks	2021-05-05	1	1	446.838063	14.99	3	446.838063
1e779b21-a08c-401a-a478-0d931fbfdab2	Cancelled	PayPal	South America	Susan Edwards	2023-07-03	1	1	470.377024	11.36	2	470.377024
1edf3f69-50bc-4565-a76e-89d6c3e962e4	Cancelled	Credit Card	Asia	Joseph Brooks	2019-06-18	1	1	144.55675799999997	15.73	9	144.55675799999997
1ef0af2a-4706-478e-9a9b-2fb3ae163a8b	Returned	Credit Card	North America	Michelle Garza	2020-10-11	1	1	907.80954	27.32	3	907.80954
1f02b381-196b-491a-adc7-821d96ada9ee	Cancelled	Credit Card	Asia	Jason Nelson	2024-12-27	1	1	2265.426081	23.79	9	2265.426081
1f0554eb-74bc-4608-8bee-deb0e42e24ce	Cancelled	Credit Card	North America	Caitlyn Boyd	2019-07-10	1	1	1738.9344	20.9	5	1738.9344
1f0c37cc-74b3-4a5d-ad3c-fc343dfea16f	Cancelled	PayPal	Asia	Caleb Camacho	2024-12-25	1	1	1856.060856	24.34	6	1856.060856
1f2565d4-4725-4d3b-9265-5220d25ec819	Returned	Credit Card	Australia	Diane Andrews	2020-12-20	1	1	971.461504	10.56	4	971.461504
1f33303e-1d27-4926-b049-3333d83e895c	Pending	PayPal	Asia	Joseph Brooks	2023-11-21	1	1	796.314204	13.83	2	796.314204
1f502e1d-0d9c-4f58-91ea-5e74b65f0dc4	Cancelled	Gift Card	Asia	Michelle Garza	2019-08-20	1	1	962.25831	14.15	9	962.25831
1f5405a5-312e-43d7-ba96-80309f86870d	Pending	Gift Card	North America	Michelle Garza	2020-08-16	1	1	552.395936	24.84	8	552.395936
1f557c4f-d23f-4f99-804c-bafacdc5bfb2	Cancelled	Amazon Pay	North America	Crystal Williams	2023-09-30	1	1	3495.492	3.97	8	3495.492
1f60091f-6bb6-4b4e-8378-cfca512dc39f	Cancelled	PayPal	Asia	Mary Scott	2019-08-18	1	1	239.645961	24.93	9	239.645961
1f6505bf-96b5-4eb0-85e8-2f5b9ae9a26f	Returned	Amazon Pay	Asia	Roger Brown	2023-03-27	1	1	1161.310752	4.72	7	1161.310752
1f89bd0e-5437-4f6d-9deb-95bd8435bde7	Pending	Debit Card	North America	Steven Coleman	2021-09-11	1	1	412.507485	8.35	1	412.507485
1f99f41e-abbf-4682-a010-aa3cb4b52845	Cancelled	Gift Card	Australia	Charles Smith	2022-04-29	1	1	322.13024	16.46	8	322.13024
1f9aca22-1f3c-4566-a550-d12a7e463c89	Returned	Credit Card	Australia	Susan Edwards	2020-02-10	1	1	1773.2914560000002	6.99	9	1773.2914560000002
1f9f5cc1-8d78-4716-978a-c38c5ae8a54b	Returned	Gift Card	Europe	Johnny Marshall	2021-05-23	1	1	227.213532	28.63	7	227.213532
1fa7260d-d369-47e0-94c6-6ccbb9dfb862	Pending	Gift Card	Asia	Adam Smith	2024-11-17	1	1	258.808081	4.17	1	258.808081
1fdc2cb9-0d20-4000-b36e-09d6d144b39a	Returned	Credit Card	South America	Emily Matthews	2021-08-08	1	1	4007.92916	12.18	10	4007.92916
1fdc7d66-2c00-4bb7-8a4f-2cb8664f2afe	Pending	PayPal	Australia	Caleb Camacho	2024-01-26	1	1	871.9920450000001	23.23	5	871.9920450000001
1fe0d9f9-0128-43ae-9fb8-2cd70c5f2a64	Cancelled	Credit Card	North America	Crystal Williams	2024-08-14	1	1	357.39279	6.1	9	357.39279
1fe39f47-b1a4-4cfb-ba9c-c5c3d3c30697	Returned	Credit Card	Europe	Bradley Howe	2021-05-13	1	1	37.840124	17.09	1	37.840124
20108f37-f7b4-42f7-bb3a-9da034c85e78	Returned	Gift Card	North America	Steven Coleman	2022-02-01	1	1	88.654972	5.06	7	88.654972
201bf2e5-1eda-4b73-8d1d-07f8a62f7ed4	Cancelled	Gift Card	Australia	Jason Nelson	2024-09-11	1	1	340.88958	22.15	3	340.88958
206c5a7e-9153-4012-8db4-e5752f8bd695	Returned	PayPal	Australia	Bradley Howe	2023-04-19	1	1	209.844855	15.85	1	209.844855
207123f9-5ff7-4aad-9e0d-5220186d92d9	Returned	Credit Card	Australia	Sandra Luna	2019-12-01	1	1	700.305376	0.57	8	700.305376
2072d47c-fbc3-40f1-80a7-9ff9a3085ebd	Returned	PayPal	North America	Caitlyn Boyd	2022-03-01	1	1	1151.869376	17.36	4	1151.869376
208b4a74-3257-492a-91b8-abd833918832	Pending	Amazon Pay	Asia	Johnny Marshall	2021-10-11	1	1	1784.36778	17.45	6	1784.36778
208f488e-f956-4dd7-b294-cc735a66d106	Pending	PayPal	Australia	Kristen Ramos	2021-12-23	1	1	75.23762500000001	23.81	5	75.23762500000001
2096c1ae-2731-41cd-b10c-1df03f1ddac4	Cancelled	Credit Card	Asia	Bradley Howe	2020-01-10	1	1	1207.4639939999995	23.34	9	1207.4639939999995
20a43b06-b47f-4d64-9ac8-773cdb74849a	Returned	Gift Card	North America	Kristen Ramos	2024-01-05	1	1	2810.816604	2.39	6	2810.816604
20a7ba7f-3cb0-4a5f-b13e-46f5263242b6	Returned	Gift Card	North America	Christina Thompson	2019-08-22	1	1	356.03099999999995	28.4	3	356.03099999999995
20c0abc3-2e79-4cac-a026-3d160fc0a92d	Returned	Gift Card	Asia	Susan Edwards	2024-03-31	1	1	470.53768	13.52	10	470.53768
20c82f8a-1bb5-4c6b-8e02-bef2ced8ae1a	Returned	Credit Card	Asia	Diane Andrews	2020-12-18	1	1	2286.334988	13.08	7	2286.334988
20d02122-3110-4962-8972-5dfeda149bfc	Pending	Credit Card	Europe	Diane Andrews	2019-02-15	1	1	1368.70332	20.95	4	1368.70332
20e16ce4-7cc5-46ca-b4cd-488641c6a10f	Cancelled	Debit Card	North America	Johnny Marshall	2022-08-11	1	1	1222.8957860000005	25.46	7	1222.8957860000005
20e3a52b-a197-4ad4-8a89-bbf51fcbca9c	Cancelled	PayPal	Europe	Bradley Howe	2023-10-21	1	1	1117.0530720000002	23.59	8	1117.0530720000002
20e56fbd-0dab-4bbc-a4fc-aa0f5a4142f9	Cancelled	Debit Card	Australia	Diane Andrews	2019-02-05	1	1	1644.84915	27.81	5	1644.84915
21071d77-05ea-41ab-b5c7-f0020a8ef007	Cancelled	Debit Card	North America	Diane Andrews	2019-08-17	1	1	2283.24285	12.85	9	2283.24285
2113376b-4fee-4f2d-9285-d8f764fe661b	Pending	Credit Card	Asia	Johnny Marshall	2021-11-06	1	1	1831.85976	3.91	10	1831.85976
212828ac-5b95-490c-bd16-8503e546bd2c	Pending	Credit Card	North America	Crystal Williams	2021-08-15	1	1	115.411276	8.28	1	115.411276
214450c8-c2ee-453a-aba4-c163b19e565b	Cancelled	Credit Card	Australia	Adam Smith	2019-11-28	1	1	190.17507	10.59	6	190.17507
21514820-c632-4ab6-974f-78ba9340894e	Cancelled	Gift Card	South America	Caitlyn Boyd	2022-01-12	1	1	300.196064	26.22	8	300.196064
215265e7-9582-41c7-bfd5-323e8dc7d06d	Cancelled	Gift Card	Europe	Joseph Brooks	2021-04-03	1	1	4169.722986000001	3.02	9	4169.722986000001
21650084-f7da-447a-a6e4-f40b15f58d59	Pending	Debit Card	South America	Kristen Ramos	2024-04-19	1	1	74.86728600000001	26.73	6	74.86728600000001
217241ed-2e41-4a00-8870-5510b9e85923	Returned	PayPal	Europe	Steven Coleman	2024-02-22	1	1	2511.724649	25.49	7	2511.724649
21749ab4-f310-4554-ab26-f251c66d7750	Returned	Amazon Pay	North America	Susan Edwards	2020-08-18	1	1	439.833972	27.03	3	439.833972
217cde70-5d09-425a-8a6f-b95ad0e2af35	Pending	Gift Card	Europe	Michelle Andersen	2021-04-01	1	1	640.8217799999999	20.71	10	640.8217799999999
2192d919-648f-40dd-ba6d-876b9a7f4e2b	Pending	Debit Card	North America	Joseph Brooks	2022-09-17	1	1	150.0114	15.96	6	150.0114
21a900e9-af27-47b4-abd8-af6a8a08ca45	Pending	Amazon Pay	South America	Susan Edwards	2019-10-31	1	1	992.311452	16.18	3	992.311452
21b01c3d-ffda-4f0a-9af9-5c56b5262890	Returned	Gift Card	North America	Sandra Luna	2019-01-20	1	1	517.234788	18.73	7	517.234788
220b9604-8057-4d59-b7b4-54faa5bced5e	Pending	Credit Card	Europe	Sandra Luna	2022-08-01	1	1	936.452601	3.29	9	936.452601
221faca7-b354-4d88-86ef-06c2ea95961b	Pending	Debit Card	Australia	Diane Andrews	2020-02-12	1	1	76.604856	11.09	3	76.604856
22349f8a-ed79-49b4-bcf5-da1da98f76ed	Cancelled	Debit Card	North America	Emily Matthews	2021-10-03	1	1	126.850194	4.81	1	126.850194
223581f8-4889-4bd3-b454-500004610446	Cancelled	Gift Card	Australia	Michelle Andersen	2022-04-27	1	1	784.5709950000002	0.55	3	784.5709950000002
2255a212-a30c-4c01-abcf-1501f937eaac	Pending	Gift Card	Australia	Michelle Andersen	2020-05-29	1	1	823.3136099999999	7.95	9	823.3136099999999
225a288e-9cda-4d2c-a83a-03efe9b51980	Cancelled	PayPal	North America	Diane Andrews	2022-09-22	1	1	568.605807	26.71	3	568.605807
2267ce03-37ba-446a-b279-17ecee550c6e	Cancelled	PayPal	North America	Kristen Ramos	2019-01-04	1	1	3652.1505	20.5	10	3652.1505
2270d2cb-42e6-46f9-8f07-436ac4e68f62	Cancelled	Debit Card	Australia	Susan Edwards	2023-07-25	1	1	3692.15696	4.04	10	3692.15696
22b20451-1363-4c33-9939-3903b2592d03	Returned	PayPal	North America	Kristen Ramos	2021-12-15	1	1	721.780272	24.17	8	721.780272
22cc615f-1d7a-45ea-b7c9-24dfb20c6248	Cancelled	PayPal	Europe	Kristen Ramos	2024-04-17	1	1	1517.967594	24.21	6	1517.967594
22e02bbc-9a2a-4b00-a163-0e81c981968d	Returned	Amazon Pay	North America	Diane Andrews	2020-03-11	1	1	2197.960056	12.97	8	2197.960056
22e36a58-5bed-4b6b-83a4-561bf35faef2	Returned	Debit Card	North America	Adam Smith	2024-02-11	1	1	183.463686	3.43	7	183.463686
22ebeb34-e554-4c88-8d62-73cf476829bf	Returned	Credit Card	Australia	Michelle Andersen	2020-10-29	1	1	2279.43294	28.34	10	2279.43294
22f51f73-93e0-48c4-b63d-975d259b42a6	Pending	Debit Card	Asia	Crystal Williams	2020-02-10	1	1	625.87476	14.04	10	625.87476
23056515-e75e-4c06-ada9-77f1ca48756b	Returned	Amazon Pay	South America	Mary Scott	2022-07-04	1	1	1596.515736	23.81	8	1596.515736
23143df1-4b56-40f9-90a2-f79a089068fa	Cancelled	Amazon Pay	Asia	Roger Brown	2023-05-30	1	1	998.187088	17.27	8	998.187088
2323b061-d911-4d06-a924-ffbf3f923b0e	Cancelled	PayPal	Europe	Sandra Luna	2019-06-04	1	1	59.507604	2.19	3	59.507604
23522b18-6ac9-48d2-a3f6-44e1f5e12d81	Pending	Credit Card	South America	Sandra Luna	2024-07-25	1	1	1175.75808	20.32	7	1175.75808
235cf003-bd15-4acb-a048-1ccbbcd201b9	Pending	Gift Card	Europe	Roger Brown	2019-05-07	1	1	239.712381	15.97	1	239.712381
236454af-fcd2-406d-860b-ab1a588c540c	Pending	Gift Card	Asia	Sandra Luna	2019-07-10	1	1	33.472452000000004	6.71	2	33.472452000000004
2383da23-6d12-488a-b68f-14f9d055b8fd	Returned	PayPal	South America	Michelle Garza	2021-01-24	1	1	78.22074	24.86	6	78.22074
23840efc-e83b-493c-aa51-07654319dcdc	Cancelled	PayPal	Australia	Johnny Marshall	2019-04-25	1	1	447.14622	12.82	2	447.14622
238f0128-505d-46da-99f0-d6d149098d1b	Returned	Debit Card	South America	Christina Thompson	2020-02-02	1	1	2213.996736	12.36	8	2213.996736
2397a79f-7dfb-4c36-8707-ecd2b52fc3f5	Returned	Amazon Pay	Asia	Kristen Ramos	2023-07-27	1	1	203.34915	2.82	9	203.34915
23a1f1d6-9afe-4722-a941-2f62a1bd120f	Returned	Credit Card	South America	Jason Nelson	2024-11-27	1	1	111.86067	18.7	1	111.86067
23b5b024-89aa-4ed2-a25d-a2971587b059	Returned	Debit Card	Asia	Christina Thompson	2023-07-10	1	1	533.331484	9.77	2	533.331484
23c23747-aac5-43ef-b291-3d17281a6aca	Returned	Amazon Pay	Australia	Crystal Williams	2022-01-30	1	1	1797.3296039999996	7.42	7	1797.3296039999996
23dc2101-a4e3-4dcf-8332-1aa2a6415e86	Pending	Debit Card	North America	Roger Brown	2020-09-21	1	1	1206.445023	18.73	7	1206.445023
23f6c847-89a5-419c-a353-a5774b4a77e3	Pending	Gift Card	Australia	Kristen Ramos	2019-04-24	1	1	684.067671	1.93	3	684.067671
23f9070e-00b8-499f-871a-5749f3f93c02	Pending	Credit Card	Europe	Caitlyn Boyd	2023-09-30	1	1	1116.082176	17.43	8	1116.082176
23fb9ef0-ab93-4b8a-b4c8-50b1625c11e2	Pending	Gift Card	Europe	Diane Andrews	2022-04-08	1	1	2202.1551	6.52	5	2202.1551
2405ed11-7a0a-4899-9d03-4cd3d50bc48b	Returned	PayPal	Europe	Kristen Ramos	2019-11-14	1	1	1839.04656	11.14	8	1839.04656
241b8293-106e-4611-be10-a938a6e3d613	Cancelled	Amazon Pay	Australia	Sandra Luna	2022-03-18	1	1	742.446342	1.11	6	742.446342
243d7f47-31d1-47a2-95c1-1050a8cf3968	Pending	Debit Card	North America	Charles Smith	2021-04-22	1	1	920.296134	27.74	9	920.296134
244967e5-63f3-4d16-ba28-15ba7cebbb2e	Returned	Gift Card	South America	Michelle Andersen	2021-11-01	1	1	1102.5191939999995	21.53	6	1102.5191939999995
244eb7cb-25aa-41ac-86e6-0e5c52b1b413	Pending	PayPal	North America	Sandra Luna	2021-04-28	1	1	713.670672	23.88	3	713.670672
2451ead3-b4c4-4408-946c-0332dc073a1a	Cancelled	Credit Card	South America	Charles Smith	2024-12-21	1	1	75.55610999999999	11.1	1	75.55610999999999
2485d45a-a422-46ed-ac01-f8d1556f15b3	Cancelled	PayPal	Europe	Sandra Luna	2019-04-10	1	1	333.51696	11.44	10	333.51696
248b5f10-12e1-4b4e-8c8c-63cf3bf6288b	Pending	Credit Card	North America	Johnny Marshall	2020-05-01	1	1	341.458016	2.06	8	341.458016
249e90a1-66a0-4bf4-a59a-2e6711438af4	Cancelled	Amazon Pay	Asia	Adam Smith	2024-02-16	1	1	226.84134	20.07	2	226.84134
24b78644-f33d-42f3-b3c8-50391012de7c	Pending	Gift Card	South America	Emily Matthews	2024-06-06	1	1	187.58922	7.18	10	187.58922
24bb7e1d-f966-480d-98ee-86daf55a759e	Cancelled	Gift Card	Europe	Michelle Garza	2020-12-27	1	1	2486.617956	16.89	6	2486.617956
24c9c374-2ff0-4d7c-92bc-8dd757b54eea	Pending	Credit Card	Australia	Emily Matthews	2024-05-28	1	1	350.44671600000004	23.62	1	350.44671600000004
24cd73fa-52d3-4365-893c-a8b3fcb181b3	Pending	PayPal	Australia	Crystal Williams	2019-09-03	1	1	2510.661048	6.16	7	2510.661048
24e029eb-dc38-48b8-9b1d-0ed58cc57230	Pending	Debit Card	Australia	Joseph Brooks	2024-12-07	1	1	986.148716	20.01	7	986.148716
24f5d926-3034-44ba-9273-f3dd16d0dcbf	Pending	Gift Card	South America	Susan Edwards	2022-06-06	1	1	8.778744	18.64	1	8.778744
24fe04fa-a113-42b1-aefa-2d7286f555ea	Cancelled	Amazon Pay	Asia	Steven Coleman	2020-02-26	1	1	333.49008	9.77	5	333.49008
24ffec07-efee-463f-b8d0-9951d666c76e	Cancelled	Credit Card	Australia	Kristen Ramos	2024-02-10	1	1	208.236072	28.51	1	208.236072
2522e7de-4f88-427d-b9da-0db59e37b235	Pending	Credit Card	South America	Sandra Luna	2019-07-18	1	1	577.53616	11.84	5	577.53616
252ae074-13c0-47b6-b0e9-d9846fad6e26	Cancelled	Gift Card	Australia	Sandra Luna	2023-12-17	1	1	1941.52959	11.45	6	1941.52959
252b35ad-77ba-40ff-9736-7036fc8ba580	Returned	Gift Card	Asia	Michelle Garza	2023-12-04	1	1	102.638837	29.81	1	102.638837
252b3d51-4440-4e90-804b-ef1292582313	Returned	Debit Card	South America	Joseph Brooks	2019-09-07	1	1	2152.81935	0.02	5	2152.81935
25364b10-fc32-45ec-aeb6-14118dc9ba55	Cancelled	Debit Card	North America	Bradley Howe	2020-01-21	1	1	1023.343482	28.74	3	1023.343482
253d4ed8-9fc6-4b92-a766-18b73fd23188	Returned	Amazon Pay	North America	Crystal Williams	2024-02-25	1	1	60.633056	10.08	1	60.633056
254b51fc-150a-4c6d-a1b0-e5eab6317fcc	Returned	Gift Card	Asia	Mary Scott	2019-11-14	1	1	1132.99893	7.74	5	1132.99893
254e4e36-2b8a-4ea4-9848-4e48be343e01	Returned	PayPal	Australia	Emily Matthews	2020-05-02	1	1	1921.2164930000004	19.61	7	1921.2164930000004
2556f0fe-92c8-4ea1-936f-d16f92b22d7b	Returned	PayPal	Asia	Johnny Marshall	2021-06-29	1	1	1122.906429	22.21	3	1122.906429
256373c3-f542-4932-aad7-d4b077b820e4	Cancelled	Debit Card	South America	Sandra Luna	2021-05-15	1	1	358.53258000000005	22.63	10	358.53258000000005
256b5bc7-341f-422e-9c4a-3f884707b110	Returned	Debit Card	South America	Mary Scott	2022-06-09	1	1	2288.057112	1.66	9	2288.057112
256c4056-cb20-4990-9f93-836b5ce1e61f	Pending	Gift Card	Europe	Christina Thompson	2022-12-10	1	1	144.14276	9.23	1	144.14276
257d3ce0-aa46-4f3e-b538-311ce3bcd113	Cancelled	Amazon Pay	South America	Michelle Garza	2023-07-14	1	1	2908.205776	21.18	8	2908.205776
25a5480b-ecd5-4179-a3fb-993f7aac3627	Pending	Credit Card	Europe	Crystal Williams	2021-02-23	1	1	537.65536	26.63	4	537.65536
25bcbe2f-30da-439b-bce9-52481f47a6ba	Pending	Credit Card	Australia	Emily Matthews	2022-02-16	1	1	1928.219832	23.33	6	1928.219832
25ceee3f-1b3c-433c-ae80-47f79b50044c	Cancelled	Credit Card	Europe	Sandra Luna	2024-08-24	1	1	896.746004	8.73	7	896.746004
25cf847e-b5e8-48ea-9330-bea5295bb9e8	Cancelled	Gift Card	Europe	Steven Coleman	2020-10-27	1	1	213.14957	1.91	1	213.14957
25f86eab-c3f0-4566-94fd-e5e175cbd9ac	Cancelled	PayPal	Australia	Caleb Camacho	2023-01-01	1	1	955.31568	1.4	4	955.31568
2601e47d-bef4-431e-beab-c51fc70666ed	Returned	Debit Card	Asia	Christina Thompson	2022-06-23	1	1	1631.9469750000003	29.33	5	1631.9469750000003
2609327a-5c32-4471-8800-7b7821dfea66	Pending	Gift Card	South America	Michelle Garza	2020-05-19	1	1	519.0086	3.53	2	519.0086
260a5849-faed-4c7b-9e72-5ca08ccc7b46	Pending	Amazon Pay	Europe	Adam Smith	2022-01-04	1	1	3472.55667	8.47	10	3472.55667
2612dcad-a9bc-4775-a76a-b207d432a6c1	Returned	Debit Card	Europe	Mary Scott	2022-02-11	1	1	3717.06036	12.12	10	3717.06036
26292016-7bdd-4e7f-8c8d-c92b47604212	Pending	PayPal	North America	Adam Smith	2021-11-08	1	1	137.27196	18.87	9	137.27196
26336dba-783f-47a7-ae7b-a3c46683c86d	Cancelled	Credit Card	North America	Susan Edwards	2023-10-20	1	1	3150.10098	13.4	9	3150.10098
26350afc-2cbb-43f1-83fa-5f34bb2befa4	Returned	Amazon Pay	Europe	Charles Smith	2020-03-08	1	1	841.1853449999999	21.35	3	841.1853449999999
264b9d07-e22c-4914-87a5-2f0385ab16a3	Cancelled	Gift Card	Asia	Emily Matthews	2022-10-30	1	1	154.745388	16.39	1	154.745388
26538a42-685b-4b29-848e-c04211052936	Pending	Debit Card	Europe	Susan Edwards	2020-07-17	1	1	944.677888	1.44	4	944.677888
26686992-638d-483d-a9b7-080e6adcd3c3	Pending	PayPal	Australia	Roger Brown	2023-07-17	1	1	187.310048	25.04	2	187.310048
267e254b-37a4-4a4d-91d8-59555494008f	Pending	Amazon Pay	North America	Sandra Luna	2020-11-18	1	1	1182.1399700000002	3.66	5	1182.1399700000002
26a98f96-e0fe-4108-af64-daa727110a27	Returned	PayPal	Europe	Christina Thompson	2024-03-29	1	1	201.431448	29.53	3	201.431448
26b4d9db-67f6-423e-b0d6-aa97a55f8f34	Returned	PayPal	South America	Emily Matthews	2023-10-05	1	1	733.3638	15.55	4	733.3638
26bfa1bb-e6b1-44c1-ad47-535afe1e8221	Returned	Gift Card	Asia	Johnny Marshall	2020-02-18	1	1	1462.9455000000005	29.5	6	1462.9455000000005
26ca2768-cc7c-40c9-a797-ef74b14ccb40	Pending	Amazon Pay	South America	Michelle Andersen	2023-11-19	1	1	1685.23875	13.75	9	1685.23875
26d1dfe2-32ac-4321-a58b-2c4385c004c6	Cancelled	Debit Card	Australia	Steven Coleman	2019-03-07	1	1	82.16208	17.92	7	82.16208
26e393b6-4b2b-401b-8584-0f67dfcaf852	Cancelled	Debit Card	South America	Bradley Howe	2022-12-21	1	1	612.60852	17.3	3	612.60852
2712a0c0-ecbd-4a9c-bf99-9331c3f810ef	Pending	Amazon Pay	North America	Steven Coleman	2024-06-27	1	1	2619.9338	6.23	10	2619.9338
271e5e8c-2a26-4399-aa20-592f9253f799	Returned	PayPal	South America	Christina Thompson	2020-06-27	1	1	1350.7110759999998	1.07	4	1350.7110759999998
272c5079-6b80-40e7-83a6-c05521899a77	Returned	Gift Card	Australia	Caleb Camacho	2019-09-21	1	1	2550.22515	16.29	10	2550.22515
273db8aa-4745-4991-a0f1-e1fd01cc60be	Returned	Amazon Pay	Australia	Susan Edwards	2024-01-04	1	1	379.058258	11.81	1	379.058258
273e6a7d-0132-41e4-9513-d9d0db617b70	Pending	Amazon Pay	Europe	Johnny Marshall	2023-06-19	1	1	341.66018999999994	14.3	3	341.66018999999994
274e58f6-2147-4d60-96e4-df92588f2665	Cancelled	Amazon Pay	Europe	Joseph Brooks	2024-07-04	1	1	2046.726864	11.59	6	2046.726864
27578733-b0b5-44ef-b216-381163dbfc56	Returned	PayPal	Asia	Kristen Ramos	2022-02-09	1	1	1366.40889	27.73	5	1366.40889
27a9598f-3c7f-434c-831e-54833730a796	Cancelled	Debit Card	Asia	Susan Edwards	2019-11-21	1	1	1158.60508	18.74	4	1158.60508
27b78c7a-d1dd-40aa-9d7f-b86717944a1c	Pending	Credit Card	Asia	Kristen Ramos	2021-06-30	1	1	143.96067599999998	22.66	1	143.96067599999998
27c3b5ff-17c0-4eb0-a0ee-9ea67f321378	Cancelled	PayPal	South America	Kristen Ramos	2023-02-02	1	1	258.25971	19.47	1	258.25971
27c72c16-4306-4709-a00e-36ecff5b5d10	Returned	Amazon Pay	Asia	Diane Andrews	2024-08-10	1	1	763.560174	21.78	3	763.560174
27cc0452-feb4-4802-9376-b74a197e2c13	Returned	PayPal	North America	Emily Matthews	2020-12-19	1	1	552.3063980000001	22.37	2	552.3063980000001
27d08c40-a63c-4548-801d-9bc128ef2e04	Pending	Amazon Pay	Europe	Caleb Camacho	2024-04-28	1	1	3611.741508	11.64	9	3611.741508
27d5ba22-8c4d-49c9-8d4c-47060c90d317	Pending	Gift Card	South America	Mary Scott	2020-03-08	1	1	1956.406193	21.53	7	1956.406193
27de3904-2ffa-49f2-8e6a-432cc849b0fd	Returned	Credit Card	Australia	Charles Smith	2023-03-19	1	1	718.42629	13.93	5	718.42629
27f285e5-610a-4b08-aabf-278b0df27cc9	Returned	Amazon Pay	Europe	Steven Coleman	2019-04-29	1	1	1290.8124	12.07	10	1290.8124
2802b04c-72d1-455c-a4d3-815918bb3383	Returned	Amazon Pay	South America	Susan Edwards	2020-12-28	1	1	127.081152	28.83	9	127.081152
2802d13f-b224-401b-963e-4dc3c404add6	Cancelled	Credit Card	South America	Caitlyn Boyd	2022-06-24	1	1	986.363973	22.09	9	986.363973
281dff72-87de-4293-a205-1afa0614425f	Returned	Debit Card	North America	Emily Matthews	2023-04-28	1	1	2086.592733	4.83	9	2086.592733
281efd65-08e7-4211-b303-68840b03e2dc	Returned	Amazon Pay	South America	Kristen Ramos	2019-07-18	1	1	4138.69831	12.93	10	4138.69831
281f50d1-6691-429f-95ad-3cbd9aa05177	Returned	Debit Card	South America	Christina Thompson	2020-10-12	1	1	2242.90345	10.23	5	2242.90345
2822ceda-675a-4c50-a215-782c89ec1c8f	Returned	Credit Card	Australia	Charles Smith	2021-11-20	1	1	1768.70538	26.55	6	1768.70538
2866a0fd-af81-4c10-b479-bdc7cf5b3ac0	Returned	Debit Card	Asia	Caitlyn Boyd	2021-02-10	1	1	2409.17504	21.05	8	2409.17504
287f38c0-be88-4773-a20b-d5f8b40e4559	Cancelled	Credit Card	South America	Steven Coleman	2023-04-09	1	1	88.180224	12.96	1	88.180224
287f851a-9dc8-4f0c-83a1-363d18a2ce62	Returned	PayPal	Australia	Susan Edwards	2023-03-21	1	1	255.809268	18.23	3	255.809268
2889c745-71ea-4811-a1dc-15218e6be2a7	Returned	Gift Card	Australia	Diane Andrews	2021-12-28	1	1	1382.619952	27.66	8	1382.619952
28b768cb-2ad9-41c8-bf1a-c0da51b331f1	Pending	Gift Card	South America	Diane Andrews	2020-09-15	1	1	795.06144	26.56	10	795.06144
28c9de6a-2ece-4e46-aad8-56d5d391b7c7	Cancelled	Debit Card	Asia	Crystal Williams	2022-05-29	1	1	1454.9914080000003	13.52	6	1454.9914080000003
28d2da9a-5de1-4342-85f9-6b17e9acbfd3	Pending	Credit Card	South America	Susan Edwards	2020-03-13	1	1	2140.2803240000003	26.42	7	2140.2803240000003
28dbcfaa-4057-40f9-8fd9-28d78c243592	Pending	Gift Card	North America	Jason Nelson	2023-02-09	1	1	1048.786704	4.16	9	1048.786704
28dea405-1cd3-4e4c-9066-311f4b0a8341	Pending	Debit Card	Asia	Susan Edwards	2021-12-22	1	1	2430.539214	13.11	6	2430.539214
28f30b88-aff7-4732-9876-429c9a5cd662	Cancelled	Debit Card	Europe	Emily Matthews	2023-09-27	1	1	2815.376984	10.89	8	2815.376984
294a4aed-e24b-465a-9c62-a76fe1b40d0e	Cancelled	Debit Card	North America	Diane Andrews	2019-02-04	1	1	748.650896	11.94	2	748.650896
294e513e-1dea-47ce-b5e8-1e1ac93fc64c	Cancelled	PayPal	South America	Michelle Garza	2021-06-16	1	1	1293.43527	9.67	6	1293.43527
29692002-3006-4173-bb94-b5b23d1fd0e2	Pending	PayPal	North America	Jason Nelson	2022-12-26	1	1	2866.9329	8.5	9	2866.9329
298b46ab-1073-4f0b-8e66-cb5621d64e8c	Pending	Debit Card	Australia	Kristen Ramos	2024-02-08	1	1	453.9392370000001	7.91	9	453.9392370000001
29b55bc6-a9aa-4412-bed1-978b21f44f18	Cancelled	Amazon Pay	Asia	Roger Brown	2019-06-17	1	1	133.62048	17.15	7	133.62048
29c1685f-073a-4574-98cc-7ad3abaf5d90	Returned	Amazon Pay	Asia	Crystal Williams	2021-05-26	1	1	1309.66905	3.5	3	1309.66905
29d692b0-43f6-4ba0-a04b-79ceede30c15	Cancelled	PayPal	Asia	Susan Edwards	2019-11-26	1	1	1012.8490800000002	24.74	6	1012.8490800000002
29ee47fb-ef95-49ee-b32c-48a79bf9bad8	Pending	Gift Card	Asia	Christina Thompson	2019-03-23	1	1	3092.8197600000003	19.18	10	3092.8197600000003
2a0d4d13-12a1-4c62-976f-1ef06dc48ba3	Returned	Debit Card	North America	Roger Brown	2024-08-27	1	1	294.44536800000003	15.94	6	294.44536800000003
2a274f25-bebc-4482-ad77-3924bded134f	Pending	Debit Card	North America	Michelle Garza	2022-09-01	1	1	51.156960000000005	21.2	4	51.156960000000005
2a2771aa-dfbb-42ea-bc6e-738e17b3629b	Cancelled	Gift Card	Asia	Jason Nelson	2019-10-16	1	1	1479.7259399999998	6.83	6	1479.7259399999998
2a39084e-d1c3-4efc-a77b-8b5d2734f714	Returned	PayPal	Europe	Michelle Garza	2019-02-12	1	1	3033.562752	28.54	9	3033.562752
2a6adce9-a924-47bc-bcd8-c217edf4a9ce	Pending	Amazon Pay	North America	Caitlyn Boyd	2023-01-17	1	1	215.780148	17.24	9	215.780148
2aa4d9d2-33df-47ac-aea9-fd1fa0e82127	Pending	Gift Card	South America	Adam Smith	2019-05-06	1	1	1079.7601000000002	26.9	5	1079.7601000000002
2aa9b33c-a8d4-4fbe-b986-06dbf9a3d80f	Cancelled	Gift Card	Europe	Jason Nelson	2019-09-21	1	1	301.07025	8.35	6	301.07025
2adc6eaa-d04d-4c73-88dc-06a39bbad5a7	Pending	Debit Card	Australia	Michelle Garza	2024-04-02	1	1	2083.161411	15.33	9	2083.161411
2aefbaf5-7aad-4954-ac3f-ca03b8e419ff	Cancelled	Debit Card	Europe	Susan Edwards	2023-06-18	1	1	786.459144	16.27	4	786.459144
2af9eefb-3825-40e5-86c1-8000ffd69c88	Pending	PayPal	North America	Joseph Brooks	2023-04-17	1	1	61.11925	8.75	1	61.11925
2afbf9ef-bfc4-45bd-9bbf-0096f8d11dae	Returned	Gift Card	Europe	Roger Brown	2019-06-06	1	1	1615.29044	1.29	4	1615.29044
2b033cf7-9d84-4d17-b1a3-3f7d2aec1f27	Cancelled	PayPal	Asia	Johnny Marshall	2020-09-28	1	1	1295.3766420000002	9.06	7	1295.3766420000002
2b049388-e679-4bdf-9daa-685da16074c8	Cancelled	Debit Card	Asia	Emily Matthews	2019-06-01	1	1	4453.68675	9.89	10	4453.68675
2b1571a7-45f4-49d6-8c46-5944ac5d42da	Pending	Gift Card	Asia	Roger Brown	2024-07-06	1	1	535.255392	17.46	6	535.255392
2b2dca01-a678-42b4-b303-2433d1559cb2	Cancelled	Gift Card	Asia	Diane Andrews	2020-04-17	1	1	2304.528075	3.55	5	2304.528075
2b5c363e-a413-4535-ae16-8f71f9595af8	Pending	PayPal	Asia	Bradley Howe	2022-09-27	1	1	1475.35656	9.22	10	1475.35656
2b5d25e9-132a-477b-880f-9112fc153d8a	Pending	Amazon Pay	South America	Crystal Williams	2019-06-15	1	1	2829.0287	3.65	10	2829.0287
2b64618c-90d0-4ebb-ab6e-0a367ec71510	Cancelled	Gift Card	Australia	Bradley Howe	2020-01-09	1	1	4300.610616	0.54	9	4300.610616
2b6cf338-2035-4813-accc-780c6ef79edb	Pending	Gift Card	Asia	Michelle Garza	2024-06-27	1	1	593.0561999999999	23.85	2	593.0561999999999
2b8cbadb-55b5-43b8-9c46-3c8b0d73fcd3	Pending	Debit Card	South America	Christina Thompson	2021-10-21	1	1	857.5798800000002	25.04	3	857.5798800000002
2b9ea992-baf4-4de0-8d84-bb2ea7e675ed	Returned	Gift Card	Europe	Crystal Williams	2020-07-03	1	1	342.64447199999995	19.18	6	342.64447199999995
2baa51b5-a0fb-41ac-b8a2-c7d3ee9c857b	Returned	Gift Card	Europe	Roger Brown	2022-05-02	1	1	2982.0441560000004	12.51	7	2982.0441560000004
2bf6d9fc-8f3e-4656-ad71-f07d060581d7	Pending	Amazon Pay	North America	Adam Smith	2020-06-29	1	1	349.08174	12.28	1	349.08174
2bfd1279-ea78-4528-930e-eb22e9d9969b	Returned	Credit Card	Australia	Sandra Luna	2019-08-14	1	1	2068.1232	13.54	5	2068.1232
2c1294a1-b6d2-4690-b459-438838d71f37	Returned	Gift Card	Australia	Crystal Williams	2022-10-11	1	1	222.619607	20.97	1	222.619607
2c3dd873-6348-4e51-9a7e-ab2e7a2aabca	Cancelled	PayPal	Asia	Caleb Camacho	2024-06-27	1	1	2046.140568	25.16	6	2046.140568
2c455d0c-15e5-48a4-9b90-56c885df24f6	Cancelled	Gift Card	Australia	Jason Nelson	2022-12-17	1	1	373.772	21.6	1	373.772
2c53a103-9dec-40bf-b9c8-c1205d3b53b4	Pending	Gift Card	Australia	Kristen Ramos	2021-05-08	1	1	919.13952	5.98	8	919.13952
2c57b92f-8764-40ed-b6f8-237ea50b55bc	Pending	Debit Card	North America	Susan Edwards	2024-08-10	1	1	1250.18144	11.4	8	1250.18144
2c7d9dd0-e39e-4039-9fb3-a383fc4ca00a	Pending	PayPal	South America	Johnny Marshall	2020-06-06	1	1	3622.898304	3.36	9	3622.898304
2c7f832e-c576-4751-8294-66caa3a43858	Returned	Amazon Pay	North America	Susan Edwards	2020-12-27	1	1	296.314726	24.69	2	296.314726
2c9a01b6-6fcd-4c8c-8325-44307d64eab4	Returned	Debit Card	South America	Steven Coleman	2021-09-10	1	1	909.407196	7.62	6	909.407196
2ca00f3b-862d-41b1-8b16-51a8b67e2add	Pending	Gift Card	Australia	Michelle Andersen	2024-11-23	1	1	308.5366	2.3	1	308.5366
2ca29088-72b6-4f09-a944-57eb0fc86802	Cancelled	Debit Card	Australia	Sandra Luna	2019-09-26	1	1	328.847736	27.13	2	328.847736
2cb32926-a2d7-4553-8835-fdd26f7b61bb	Pending	Debit Card	Australia	Bradley Howe	2022-08-26	1	1	154.882105	29.87	1	154.882105
2cbd6dc3-1c1d-4b1d-8e6c-52ec85e715fb	Pending	Debit Card	Asia	Bradley Howe	2024-06-12	1	1	444.73644	21.16	2	444.73644
2cc309cf-1e7a-4f65-b9f0-e4468a9fa30b	Cancelled	Credit Card	Asia	Emily Matthews	2020-08-26	1	1	2053.228851	6.19	9	2053.228851
2cca85bf-bffc-4c22-9a64-fb7575652e09	Cancelled	Gift Card	North America	Christina Thompson	2024-10-09	1	1	1025.868216	11.02	4	1025.868216
2cdebbc4-017f-4210-b7ce-17dbb59fdc57	Pending	Amazon Pay	Europe	Michelle Garza	2020-11-19	1	1	1126.110024	0.68	9	1126.110024
2cdff30a-71aa-44fa-bda4-14ffffdcb76a	Cancelled	Gift Card	South America	Sandra Luna	2021-05-05	1	1	2283.253308	11.66	6	2283.253308
2cf2b714-b9dd-458a-9a0b-635d0729cae8	Pending	PayPal	Asia	Michelle Garza	2020-12-14	1	1	2614.197677	15.89	7	2614.197677
2cfbd6c8-ef9b-4b3b-9c37-83133be71d14	Returned	Credit Card	South America	Mary Scott	2021-05-07	1	1	163.953657	15.23	9	163.953657
2cfe0020-da86-4f39-96c8-f5928d7247b8	Returned	Amazon Pay	Asia	Joseph Brooks	2024-06-06	1	1	336.91887999999994	28.98	2	336.91887999999994
2d045a8d-e8c9-4b82-a0e2-55edf8817ccb	Returned	Amazon Pay	South America	Michelle Andersen	2019-02-09	1	1	193.564686	26.73	2	193.564686
2d07cfba-a569-4cd9-a3e6-80c072aff3b7	Cancelled	Amazon Pay	Australia	Christina Thompson	2022-08-08	1	1	460.52620800000005	7.51	4	460.52620800000005
2d2371c4-3f2b-45fd-97b7-7cba8fdb9a8e	Returned	Amazon Pay	North America	Bradley Howe	2023-10-29	1	1	1161.509488	21.26	4	1161.509488
2d32b0dc-b446-4402-8b72-1c69d4d8b1d5	Cancelled	PayPal	Asia	Sandra Luna	2019-05-14	1	1	1598.55762	10.46	10	1598.55762
2d47726d-6402-4c98-8a93-634b80d35454	Pending	Gift Card	Australia	Emily Matthews	2021-05-21	1	1	446.9422	26.75	8	446.9422
2d511016-80ca-4db4-9e8f-538a63d41343	Pending	PayPal	Australia	Johnny Marshall	2022-07-06	1	1	3291.5051600000006	7.08	10	3291.5051600000006
2d6a0464-07c1-4894-b8b7-be4db1b794b9	Cancelled	Amazon Pay	Asia	Sandra Luna	2020-10-21	1	1	416.559249	10.11	3	416.559249
2d6ae1e8-4839-4270-921a-83e15e011d69	Returned	PayPal	Australia	Michelle Garza	2023-04-29	1	1	3443.191722	20.67	9	3443.191722
2d988de5-525f-4d18-b18f-3e4aefb0b3b9	Cancelled	Credit Card	South America	Johnny Marshall	2021-03-07	1	1	700.9403239999999	22.86	2	700.9403239999999
2da22c9b-dc53-46a4-a121-73451881e81b	Returned	Credit Card	North America	Charles Smith	2022-05-24	1	1	1483.141932	2.17	4	1483.141932
2ddc6095-9231-4cb6-ad94-bd08986e81d8	Pending	Amazon Pay	South America	Christina Thompson	2023-12-21	1	1	1644.2001	0.17	9	1644.2001
2df1fc7f-b7c8-46bc-b89a-266df682ddf9	Returned	PayPal	Australia	Joseph Brooks	2020-02-19	1	1	2211.0492	0.5	8	2211.0492
2e05ec18-86ff-420a-aa18-8d2628bc3b22	Returned	Gift Card	North America	Joseph Brooks	2021-11-08	1	1	96.430383	5.71	3	96.430383
2e2f0733-ea8f-4bb1-9f42-33294874c671	Returned	Credit Card	Australia	Mary Scott	2022-12-09	1	1	1151.40816	17.6	9	1151.40816
2e322a17-7e70-4547-a3d0-807749eb1eb0	Cancelled	Gift Card	South America	Adam Smith	2022-12-13	1	1	650.193984	22.56	9	650.193984
2e472b55-0eff-4e26-a6de-56627a1e4500	Cancelled	PayPal	Asia	Crystal Williams	2024-12-17	1	1	2589.642	4.88	10	2589.642
2e67bff1-db39-4976-ac43-fc438632afc1	Returned	PayPal	North America	Susan Edwards	2019-08-20	1	1	415.997883	16.31	9	415.997883
2e889d38-cfa1-408f-9c22-2dab0cb744a2	Returned	PayPal	North America	Caleb Camacho	2021-11-28	1	1	2965.896765	25.77	9	2965.896765
2e96f378-d808-498d-85df-0f10f0e1da04	Pending	PayPal	South America	Jason Nelson	2024-05-21	1	1	1955.47716	21.22	10	1955.47716
2eb0227b-be64-4059-9fa7-a7006355a54f	Cancelled	PayPal	Europe	Steven Coleman	2022-12-15	1	1	226.832089	22.67	1	226.832089
2ec3725d-7704-4d95-b50e-0b588ccd577b	Cancelled	Amazon Pay	Europe	Mary Scott	2020-12-02	1	1	2639.076048	3.39	8	2639.076048
2ed4bc82-24e5-4e07-9474-371faff17911	Cancelled	Amazon Pay	North America	Caleb Camacho	2022-03-31	1	1	1624.11576	27.74	6	1624.11576
2edd336d-944a-45b6-b254-56400954129f	Pending	Amazon Pay	North America	Jason Nelson	2022-12-08	1	1	376.472856	25.56	2	376.472856
2ee5d821-dd20-424a-be9b-3a4527840394	Cancelled	Gift Card	South America	Caleb Camacho	2024-05-02	1	1	1218.442392	11.48	9	1218.442392
2ee7d678-de13-4ff9-b16d-92cbf0507930	Returned	Amazon Pay	North America	Kristen Ramos	2023-07-28	1	1	2237.1331199999995	19.3	8	2237.1331199999995
2ef563d5-26f3-49ab-afbb-04b62f047638	Returned	Amazon Pay	Europe	Sandra Luna	2021-08-28	1	1	1878.512064	8.59	8	1878.512064
2f03b49c-e280-4b11-a754-2a63c35cf43b	Cancelled	Gift Card	Australia	Charles Smith	2023-08-30	1	1	1469.3875860000005	17.49	6	1469.3875860000005
2f1d956d-f9f7-4df8-8b9a-304a5b5496cf	Cancelled	Gift Card	Asia	Adam Smith	2024-02-19	1	1	907.868544	12.11	4	907.868544
2f225613-776d-42b4-99f6-24a3c2ac7885	Returned	Gift Card	South America	Joseph Brooks	2024-02-26	1	1	323.64023999999995	7.04	1	323.64023999999995
2f256460-3641-445b-929e-a14c8f25028f	Cancelled	PayPal	Europe	Roger Brown	2022-07-20	1	1	445.159368	8.08	3	445.159368
2f3142eb-c8f7-497b-9f9a-63a994d1e7f9	Cancelled	Amazon Pay	Australia	Michelle Andersen	2021-01-01	1	1	517.1250540000001	8.69	6	517.1250540000001
2f4d8fa3-3d1e-42ba-8c10-d78a2538b3d2	Cancelled	PayPal	South America	Crystal Williams	2024-12-16	1	1	1403.659532	26.19	4	1403.659532
2f73a7e6-58f4-428e-9aeb-576998781184	Returned	Credit Card	Asia	Charles Smith	2021-04-17	1	1	2697.1164	19.7	9	2697.1164
2f74a406-835c-45a2-99a6-a624e3c6ad03	Cancelled	Debit Card	South America	Charles Smith	2024-03-16	1	1	1541.4023039999995	18.62	6	1541.4023039999995
2f8c1cc8-0ef1-4d5d-a5b3-cd82835f5e44	Cancelled	Amazon Pay	Asia	Susan Edwards	2021-01-02	1	1	396.501336	8.37	6	396.501336
2f8c212a-e31a-4524-94b9-999e0586baa4	Cancelled	Credit Card	Australia	Caitlyn Boyd	2024-04-10	1	1	507.27006	22.45	4	507.27006
2f9beb8b-8fe2-476d-ab21-a736337979be	Pending	PayPal	Asia	Emily Matthews	2024-01-27	1	1	1760.7382289999998	0.19	9	1760.7382289999998
2fb2b567-98f3-44e0-bfd7-5e4028beba9a	Cancelled	Amazon Pay	Australia	Joseph Brooks	2023-08-10	1	1	2511.3978540000003	19.09	7	2511.3978540000003
2fbc399d-d0bb-4972-b227-948ebb0467d1	Pending	PayPal	South America	Jason Nelson	2023-02-21	1	1	330.252384	0.67	2	330.252384
2fcf6e10-aaff-4720-8c42-befa7b48e4b8	Cancelled	PayPal	North America	Emily Matthews	2022-04-01	1	1	1146.61368	16.33	10	1146.61368
2fdea199-ab05-40f4-abdc-b6c3ef7c45db	Pending	Gift Card	Asia	Kristen Ramos	2019-08-30	1	1	243.047164	18.21	2	243.047164
2fe30b29-9485-4b15-b835-b538511d8c64	Pending	Amazon Pay	South America	Christina Thompson	2022-11-20	1	1	1351.892556	29.69	4	1351.892556
2ffe8324-369d-48b9-aca7-ba4967149dd3	Pending	Debit Card	South America	Emily Matthews	2022-07-13	1	1	3186.67614	16.81	10	3186.67614
2fffbf46-3d80-40ba-805c-efad6fabc1e9	Returned	PayPal	North America	Emily Matthews	2020-05-09	1	1	2878.0795890000004	18.59	9	2878.0795890000004
3032c7dc-1396-4dec-9c1e-10b4361ab672	Pending	Gift Card	Australia	Emily Matthews	2024-08-23	1	1	612.930248	26.69	8	612.930248
303472e0-842d-410c-bd8d-a057ac8d60c5	Returned	Debit Card	Asia	Emily Matthews	2022-08-27	1	1	857.7488699999999	29.71	5	857.7488699999999
303cd35f-5359-4c3e-96e5-b09291c6c250	Returned	Debit Card	Australia	Christina Thompson	2019-01-24	1	1	563.5698840000001	16.27	3	563.5698840000001
30567856-f39e-4a5b-a4cc-0123be2ca8e2	Cancelled	Amazon Pay	North America	Roger Brown	2023-12-08	1	1	910.83069	25.09	7	910.83069
305a7ed1-b57d-4fb7-aaa2-3030f3017fba	Cancelled	Amazon Pay	Australia	Emily Matthews	2022-03-14	1	1	1692.896982	23.21	6	1692.896982
305bb7f8-d018-40b6-a83a-9536fbf0bd53	Returned	PayPal	Europe	Michelle Andersen	2021-01-06	1	1	1196.172684	10.27	7	1196.172684
306a3ce3-91bd-480f-8da9-96fc7650e8c3	Pending	PayPal	Asia	Emily Matthews	2022-11-28	1	1	3330.41808	25.72	10	3330.41808
306a9d85-414f-4fa2-8ce9-2aed411fed0c	Returned	PayPal	Europe	Steven Coleman	2024-08-13	1	1	143.1133	29.75	1	143.1133
30781c7e-bea1-4d4a-bcdf-e14747c05234	Returned	Amazon Pay	Europe	Sandra Luna	2019-09-19	1	1	45.602848	9.23	8	45.602848
3085fa0f-8f7c-4349-b6b4-aa1963164cce	Pending	Debit Card	Europe	Bradley Howe	2020-09-29	1	1	3759.958944	1.58	9	3759.958944
308a1d6d-e303-4a20-820b-6d13996d096d	Pending	PayPal	South America	Caleb Camacho	2024-07-24	1	1	2220.777	15.64	10	2220.777
3090bd99-fdda-45fb-8e15-3c01d4e26c66	Returned	Amazon Pay	South America	Roger Brown	2020-02-26	1	1	804.1668480000001	27.88	3	804.1668480000001
3090de2e-307d-4a5f-82e4-06eaff6318ed	Returned	Amazon Pay	Europe	Roger Brown	2020-07-29	1	1	77.07187499999999	6.25	1	77.07187499999999
309a21b6-a69a-4e49-b10d-3a60137e6397	Cancelled	Debit Card	Asia	Diane Andrews	2024-04-14	1	1	287.290746	8.29	2	287.290746
30d8f866-9074-41f0-bc2f-9399e4a2c261	Pending	PayPal	Australia	Johnny Marshall	2021-10-14	1	1	806.7790640000001	2.91	2	806.7790640000001
30dfb889-9b79-4887-8174-a98df7159f1d	Cancelled	Debit Card	South America	Joseph Brooks	2024-06-11	1	1	420.3059520000001	25.72	4	420.3059520000001
310d2e97-a10c-4583-ab57-334bfc39a945	Returned	Credit Card	North America	Steven Coleman	2023-03-08	1	1	1017.170328	20.72	3	1017.170328
311646d4-97a6-4a03-b498-e2866d952a67	Cancelled	Amazon Pay	Asia	Christina Thompson	2023-03-24	1	1	195.82722	0.19	5	195.82722
313142e7-111c-43bc-a3ec-06f95830b6e4	Returned	PayPal	Europe	Kristen Ramos	2019-06-09	1	1	1284.37232	10.08	7	1284.37232
3147ce57-8390-4aaa-9744-8ea169bca5c2	Cancelled	Amazon Pay	Europe	Joseph Brooks	2021-12-29	1	1	1673.4468600000002	25.85	9	1673.4468600000002
3156c63f-5f0c-4cef-8146-4c3691476d93	Cancelled	Credit Card	North America	Caitlyn Boyd	2019-08-09	1	1	530.77032	23.36	9	530.77032
31591354-0245-4600-a847-082b6e2a74a7	Pending	Gift Card	Asia	Christina Thompson	2019-04-20	1	1	834.0431999999998	24.8	6	834.0431999999998
315cd95b-6e2f-4c1b-baef-d49c0d80838b	Returned	Credit Card	Europe	Susan Edwards	2023-03-17	1	1	981.94584	4.4	6	981.94584
3173a4c2-ffa9-43d9-943a-9a21bfa5623d	Cancelled	Credit Card	Australia	Steven Coleman	2019-11-23	1	1	458.200665	0.35	9	458.200665
31abb764-2f65-4917-bb16-52517a9ea31e	Cancelled	Debit Card	South America	Adam Smith	2024-11-18	1	1	720.0945839999999	22.73	6	720.0945839999999
31b97e8f-ca55-4cd0-9681-8c2ff888630f	Pending	PayPal	Europe	Steven Coleman	2021-11-13	1	1	1814.250224	22.74	8	1814.250224
31dfde18-d157-44ea-8100-5059fcda2538	Pending	Credit Card	South America	Michelle Andersen	2021-11-19	1	1	854.021289	18.27	3	854.021289
31f34cce-93fe-42b0-8c24-80e52f3732cc	Pending	Debit Card	Australia	Roger Brown	2024-12-27	1	1	405.06575	19.55	5	405.06575
3200f511-c977-4b80-9342-0d1200e726ab	Pending	Credit Card	South America	Caleb Camacho	2020-05-26	1	1	2098.9476000000004	28.68	6	2098.9476000000004
320f1e5a-4ab0-4a5c-8c8f-ff93234533bf	Cancelled	Gift Card	Australia	Adam Smith	2021-01-14	1	1	630.9619559999999	15.07	6	630.9619559999999
325e8766-d126-4932-9c76-233384f6e303	Cancelled	Credit Card	Australia	Sandra Luna	2024-11-19	1	1	348.249798	19.66	1	348.249798
3269666c-c5c6-4331-b777-2547c476a33e	Returned	Credit Card	South America	Steven Coleman	2024-10-24	1	1	1850.102784	1.54	4	1850.102784
326ac062-730b-4d81-9d35-7ccbb8a3543b	Cancelled	Debit Card	Asia	Kristen Ramos	2021-11-21	1	1	1176.081624	21.08	9	1176.081624
328ce470-c490-4861-a1a3-60f1da91d93c	Pending	Credit Card	North America	Steven Coleman	2024-04-12	1	1	88.93498600000001	24.42	1	88.93498600000001
32cb4c46-5bbc-4954-aba0-083f02362d80	Pending	Debit Card	Asia	Michelle Garza	2023-08-11	1	1	1342.95525	15.67	5	1342.95525
32cbeb45-dd6b-47f2-8583-f14d5cd4fac9	Pending	Gift Card	Europe	Susan Edwards	2023-03-14	1	1	796.55268	27.4	7	796.55268
32ecfe6d-7530-4d11-8c22-88f3d0861359	Returned	Amazon Pay	North America	Susan Edwards	2019-06-29	1	1	827.699445	21.07	3	827.699445
32f1563b-959a-48b0-af84-b4a166e27896	Cancelled	Debit Card	North America	Kristen Ramos	2023-12-21	1	1	119.735904	25.44	1	119.735904
32fcb260-82ba-493c-94ab-424ea25fa0c9	Returned	Gift Card	South America	Joseph Brooks	2021-03-02	1	1	944.575224	7.42	4	944.575224
3302bc10-408b-45e1-85e0-8cb088dd9152	Returned	Credit Card	South America	Crystal Williams	2024-03-22	1	1	1134.969066	12.22	3	1134.969066
331abfcc-cbd0-4502-b8a9-9978103a20d6	Pending	Credit Card	South America	Johnny Marshall	2020-03-11	1	1	1745.3601839999997	20.94	6	1745.3601839999997
332de05f-9815-4cfd-87bd-ac44ba4be5e7	Pending	Debit Card	South America	Kristen Ramos	2020-12-28	1	1	386.48264	27.12	2	386.48264
33382eac-191e-473f-9056-78b0dd52c9b1	Pending	Gift Card	Europe	Sandra Luna	2020-10-21	1	1	638.7333480000001	2.54	6	638.7333480000001
334643d5-1a82-45d7-801a-95591f0f3bbc	Cancelled	Debit Card	Asia	Christina Thompson	2022-06-12	1	1	1106.133588	14.92	7	1106.133588
33480a87-f411-4737-b237-263a7dc953dd	Cancelled	PayPal	Asia	Charles Smith	2023-08-28	1	1	555.2442	0.1	2	555.2442
334dded4-b49f-4b70-a08a-cd2bde7e8672	Returned	Amazon Pay	Australia	Emily Matthews	2019-04-21	1	1	714.161336	27.96	2	714.161336
33507e78-5ef1-4be7-b254-4a8f30869378	Pending	Gift Card	Asia	Joseph Brooks	2023-12-02	1	1	1164.52628	28.85	4	1164.52628
336c7bef-a048-4084-a2d7-9a900907b59e	Cancelled	Amazon Pay	South America	Michelle Garza	2021-05-24	1	1	140.982606	24.58	1	140.982606
337c41c7-c1e5-4244-993f-87ff12b5d626	Returned	PayPal	Europe	Roger Brown	2020-09-29	1	1	361.116192	24.56	2	361.116192
3383bfe8-cb2e-41a8-9190-9f358647185c	Cancelled	Debit Card	Australia	Charles Smith	2022-04-11	1	1	270.851684	29.96	1	270.851684
338bab3f-35f0-4a72-9624-ec77f593a5b0	Cancelled	Debit Card	North America	Emily Matthews	2024-10-17	1	1	404.1754199999999	18.6	3	404.1754199999999
3399d4f9-1d02-470a-8c8e-6117c3ca4266	Cancelled	PayPal	North America	Crystal Williams	2020-09-13	1	1	1686.6725499999998	3.66	5	1686.6725499999998
33b28259-cb43-4339-9d5d-848ddb9206e8	Pending	Debit Card	Europe	Johnny Marshall	2020-01-07	1	1	221.48105	15.06	7	221.48105
33d253fd-7c6f-40b4-ac71-696b05e3df00	Returned	PayPal	South America	Michelle Garza	2024-08-18	1	1	2165.53225	1.23	10	2165.53225
33d2f789-9210-46e1-abb8-ffe9766513c7	Returned	Credit Card	South America	Johnny Marshall	2023-01-29	1	1	2240.5131	17.56	7	2240.5131
33d63713-22f5-4259-9dc1-568bece846d6	Cancelled	Amazon Pay	Australia	Emily Matthews	2021-01-26	1	1	355.916007	2.71	1	355.916007
33e10cad-f962-442e-9e40-dc5a710cc32d	Returned	Debit Card	Europe	Michelle Garza	2022-09-23	1	1	2548.196112	23.11	7	2548.196112
3412d0da-5749-40c4-8f71-4ad4c0b044e8	Cancelled	Amazon Pay	Europe	Michelle Andersen	2019-02-11	1	1	2650.0734400000006	28.88	10	2650.0734400000006
3421b366-a34a-4010-a593-e8f310b49249	Cancelled	Debit Card	North America	Diane Andrews	2024-08-13	1	1	1808.898	9	6	1808.898
34440aea-ca2f-407d-a0ba-164a39691887	Cancelled	PayPal	South America	Crystal Williams	2021-08-31	1	1	867.3481530000001	16.77	9	867.3481530000001
3451cdb6-9353-48fd-b8bf-f999a1211dd5	Cancelled	Amazon Pay	North America	Charles Smith	2024-06-04	1	1	2163.510888	16.62	6	2163.510888
3468af96-3a89-44b8-8c2c-4879df8220b5	Returned	Gift Card	South America	Susan Edwards	2022-07-28	1	1	404.756352	8.74	7	404.756352
346f306c-cbac-403f-8b05-616c8db7a16e	Pending	Debit Card	South America	Sandra Luna	2024-09-18	1	1	2300.0849820000003	1.41	9	2300.0849820000003
347b6b7b-1d15-4667-8460-78f376752065	Cancelled	PayPal	Australia	Kristen Ramos	2022-05-29	1	1	2959.7125800000003	10.58	10	2959.7125800000003
34bef5b3-ce8a-44f2-96db-acd88bd36c1b	Returned	PayPal	South America	Diane Andrews	2020-10-20	1	1	437.54091	8.33	10	437.54091
34f45b48-b384-433d-a678-5e57621a36d4	Returned	Debit Card	Europe	Emily Matthews	2024-07-08	1	1	4309.27695	5.95	10	4309.27695
3502a0f4-3b47-49cd-bf5b-58348cb38aeb	Returned	Amazon Pay	Europe	Crystal Williams	2021-08-13	1	1	678.7751360000001	21.08	8	678.7751360000001
3534cd1e-3d98-4b4f-a862-930bb2cff509	Pending	Amazon Pay	North America	Emily Matthews	2024-09-13	1	1	1784.0057580000002	16.79	9	1784.0057580000002
35355c42-e253-4898-b7b4-cd1112567d35	Returned	Credit Card	Asia	Caleb Camacho	2022-09-11	1	1	427.1451760000001	12.42	4	427.1451760000001
353e1d24-cb61-41fa-8711-36da975580dd	Returned	PayPal	Asia	Jason Nelson	2019-10-14	1	1	1083.04864	19.44	5	1083.04864
35401647-8aa5-4451-8543-5d2ba532f6a6	Cancelled	Credit Card	North America	Mary Scott	2021-03-23	1	1	1855.411134	5.81	6	1855.411134
355cfd31-52d6-4db7-905b-a4de0429fc1f	Returned	Debit Card	Asia	Mary Scott	2022-11-14	1	1	297.721644	6.12	1	297.721644
35658044-6f1a-442d-95f4-174dac391890	Pending	Debit Card	North America	Susan Edwards	2020-02-07	1	1	3079.160316	13.88	9	3079.160316
356d8ce3-d89e-44ac-918f-ef1bcf6e1fb7	Pending	PayPal	Asia	Caitlyn Boyd	2021-12-21	1	1	39.57849	12.34	5	39.57849
3585646c-9cb0-4337-9fda-3f386ea34469	Returned	Gift Card	North America	Caitlyn Boyd	2022-04-10	1	1	1050.928515	14.77	7	1050.928515
35a092db-1d51-4bc7-b15a-31144c213430	Returned	Amazon Pay	Australia	Mary Scott	2024-12-16	1	1	1480.619232	15.64	6	1480.619232
35c3cb8b-8306-4735-af23-0e7342844935	Pending	Gift Card	South America	Caleb Camacho	2023-02-09	1	1	2454.002568	18.28	9	2454.002568
36309c4f-bcc4-4aa3-9ab0-7948d56954b1	Pending	Gift Card	Asia	Johnny Marshall	2022-08-29	1	1	1427.906312	14.39	4	1427.906312
3635013b-0448-49f1-a19c-e47390ebe236	Pending	PayPal	Europe	Jason Nelson	2022-01-14	1	1	1883.1519	22.79	6	1883.1519
364188df-3128-4f99-b6e5-fbc1b7c6b539	Pending	Amazon Pay	Australia	Susan Edwards	2021-05-11	1	1	1654.219553	28.23	7	1654.219553
36670fe0-98a3-4f21-909e-9a070cb7f008	Pending	Gift Card	South America	Johnny Marshall	2019-12-22	1	1	2810.99082	11.23	10	2810.99082
36886038-efbf-466d-8b4f-28351f2e3de8	Pending	Gift Card	Europe	Michelle Garza	2020-11-15	1	1	1922.76718	9.89	10	1922.76718
368c32b8-061b-4f6c-8a86-1ac7786e5398	Returned	Credit Card	South America	Bradley Howe	2020-04-09	1	1	244.668872	5.94	2	244.668872
36944f31-8bd5-49c6-b132-09121761def4	Returned	PayPal	Asia	Adam Smith	2021-10-26	1	1	2345.74794	29.17	10	2345.74794
369537b3-57f6-4fbb-bd12-5832ea355556	Pending	Amazon Pay	Europe	Caleb Camacho	2022-01-06	1	1	1203.234318	20.77	9	1203.234318
369ae49a-979a-457f-98b8-9b67fb7ddce1	Pending	Amazon Pay	North America	Johnny Marshall	2021-09-20	1	1	1322.32842	5.24	3	1322.32842
369f760b-ea56-4ed2-9923-05d34f7c2440	Returned	Debit Card	Europe	Caitlyn Boyd	2022-08-07	1	1	1467.9505620000002	0.29	9	1467.9505620000002
36d31f21-2eb3-4778-a35a-fe06e12e020e	Returned	Amazon Pay	Australia	Adam Smith	2023-06-11	1	1	1930.164456	3.31	4	1930.164456
36d55319-c5f4-418e-90ef-608b00597296	Returned	Debit Card	Asia	Steven Coleman	2019-07-01	1	1	1702.36341	13.59	9	1702.36341
36d75056-3ff8-4fdb-b4c9-9074344bb54c	Cancelled	Gift Card	North America	Jason Nelson	2024-12-24	1	1	514.27656	11.8	4	514.27656
36e77a73-b872-4c1a-be42-fe5971f88bde	Returned	PayPal	Asia	Michelle Andersen	2019-05-22	1	1	1197.80316	15.1	4	1197.80316
373108df-ce7a-43ef-b1e5-8f5307d2e492	Pending	PayPal	Australia	Michelle Garza	2019-02-14	1	1	243.11956	4.92	2	243.11956
37494eae-7281-4dfa-a991-c385c6138a8e	Pending	Credit Card	South America	Joseph Brooks	2021-06-05	1	1	32.02017	27.85	1	32.02017
3766f0af-68ba-4003-91ca-2dbc2c637837	Cancelled	Credit Card	South America	Caleb Camacho	2020-03-11	1	1	1170.48582	10.39	3	1170.48582
37865568-a928-4cc9-9c16-a2368fd566a9	Pending	Credit Card	Europe	Bradley Howe	2021-04-02	1	1	76.74011999999999	27.74	10	76.74011999999999
379deff2-5958-44ae-acd9-802824f09ce1	Cancelled	Credit Card	Asia	Emily Matthews	2020-06-05	1	1	3351.53355	26.59	10	3351.53355
379e2928-bd5f-4339-8644-46c4588406e1	Returned	PayPal	Asia	Johnny Marshall	2022-10-18	1	1	331.14471	7.7	1	331.14471
37d0b868-31cd-4d77-a3fe-a9839b8d5cbb	Cancelled	Amazon Pay	South America	Sandra Luna	2019-11-13	1	1	1723.682592	20.08	9	1723.682592
37e32a34-8955-4ec3-88a0-a39774950128	Cancelled	Debit Card	Europe	Christina Thompson	2020-01-05	1	1	58.212315	28.53	9	58.212315
37ef617e-cdcb-4003-9c4b-d6ad7202f5a5	Pending	Gift Card	South America	Susan Edwards	2024-06-07	1	1	1588.2762240000002	25.07	6	1588.2762240000002
380cf534-262b-4614-9b04-d3d7cdb45954	Pending	PayPal	Europe	Crystal Williams	2022-06-29	1	1	69.18704	3.8	4	69.18704
38278554-2487-4a89-89ab-622d1e898c6b	Cancelled	PayPal	Europe	Johnny Marshall	2019-08-15	1	1	271.168352	3.54	7	271.168352
382879f4-f530-4d12-85eb-adb96d466eb7	Cancelled	Amazon Pay	Europe	Michelle Garza	2020-04-30	1	1	978.72372	15.24	9	978.72372
385fa37a-9ddc-4038-a6f3-55a2805246e0	Returned	Gift Card	North America	Jason Nelson	2023-07-18	1	1	1322.428044	10.89	3	1322.428044
386bd0cc-e085-4f09-9619-5553020a885a	Cancelled	Amazon Pay	Europe	Roger Brown	2021-01-29	1	1	308.342316	6.37	4	308.342316
387688c9-fb68-401e-bf63-99f947e38c53	Cancelled	PayPal	North America	Bradley Howe	2024-06-07	1	1	464.1726	1.7	4	464.1726
3880a29b-161c-40e4-b3ae-fea6a00675f9	Pending	PayPal	Europe	Christina Thompson	2019-05-10	1	1	122.677128	15.79	1	122.677128
389331ca-bdbf-4c83-8108-73e2a1ae12dd	Pending	Amazon Pay	South America	Joseph Brooks	2024-08-26	1	1	208.06632	24.94	2	208.06632
389632e8-2b48-4682-a83f-330624617108	Cancelled	Debit Card	South America	Johnny Marshall	2023-08-14	1	1	325.611472	15.17	1	325.611472
3896ad02-31a9-479c-8e7f-6e64fec4cd11	Pending	Amazon Pay	North America	Roger Brown	2020-11-22	1	1	1364.6468	27.18	8	1364.6468
38b8c49d-9457-4e7c-846d-ac2fc2465cce	Returned	Amazon Pay	South America	Steven Coleman	2021-10-09	1	1	1238.3359870000002	7.19	7	1238.3359870000002
38dbaadb-b2ee-46c9-8cea-35f459520fed	Returned	PayPal	Asia	Charles Smith	2024-01-01	1	1	1584.000704	2.76	8	1584.000704
3907cc47-a8c0-4c58-a85d-c036a5f66973	Cancelled	Amazon Pay	Asia	Caleb Camacho	2020-02-22	1	1	3467.6885600000005	26.04	10	3467.6885600000005
390b3170-173e-4154-b3db-f2766ce7ef35	Cancelled	Credit Card	Asia	Kristen Ramos	2022-11-05	1	1	29.193119999999997	26.28	3	29.193119999999997
393c9996-a43e-4423-9a32-73528f430659	Pending	Gift Card	South America	Joseph Brooks	2022-12-28	1	1	301.26231	5.59	10	301.26231
393fba46-fedb-498d-9bd3-0b0c09a49288	Pending	Gift Card	Asia	Kristen Ramos	2020-08-13	1	1	228.848648	21.32	1	228.848648
39461132-4a62-44a1-a135-9257ead1b886	Cancelled	PayPal	Europe	Michelle Andersen	2022-08-31	1	1	699.820083	22.57	3	699.820083
39517d66-6aba-4d9b-8aad-f99e8fa38375	Cancelled	Amazon Pay	Asia	Joseph Brooks	2023-01-26	1	1	1510.5906	21	6	1510.5906
3951cbc3-e231-469e-baa6-f36229e47ff5	Pending	PayPal	Europe	Charles Smith	2024-10-30	1	1	658.5144	11.49	6	658.5144
3953d4e3-7d75-44b1-a54d-2bd39facada5	Pending	Debit Card	South America	Roger Brown	2024-04-26	1	1	3116.44944	27.98	9	3116.44944
396af5d9-0529-4891-a7f0-fc0c7b9c06be	Returned	Gift Card	Australia	Johnny Marshall	2021-02-24	1	1	823.454775	14.69	5	823.454775
397211c9-39a6-4f04-9fa2-1cca130ca0aa	Returned	Gift Card	North America	Roger Brown	2020-01-07	1	1	919.459224	17.13	4	919.459224
397d49c0-f2c0-4558-9a07-97c0dd038462	Cancelled	Credit Card	South America	Caleb Camacho	2022-01-20	1	1	1099.1792280000002	17.08	7	1099.1792280000002
397e1c44-8b95-4277-bf4d-1a826a2ae047	Cancelled	Debit Card	Asia	Mary Scott	2021-12-24	1	1	1803.5028	6.5	9	1803.5028
397e4b6a-1ef1-43df-be74-0bf737747a65	Cancelled	Gift Card	Europe	Roger Brown	2023-04-20	1	1	378.525549	14.71	1	378.525549
39a20b09-facf-4390-81db-8e6f3b3587d3	Returned	Debit Card	South America	Susan Edwards	2019-05-28	1	1	158.082795	12.83	1	158.082795
39a3e912-4029-473b-a98d-d6d3e341dcba	Cancelled	Gift Card	Europe	Crystal Williams	2019-02-05	1	1	847.2303	2.55	9	847.2303
39b79055-13c4-47c2-98b7-8bfbba3ea59d	Pending	Amazon Pay	Europe	Steven Coleman	2023-03-18	1	1	679.088158	1.43	7	679.088158
39b8b444-3f5b-4169-bdd6-3785b88a785d	Pending	Gift Card	Europe	Kristen Ramos	2023-09-02	1	1	2160.8489200000004	25.65	8	2160.8489200000004
39bbc2d3-0a5f-4a10-869e-cdfca3bba39b	Cancelled	Amazon Pay	Australia	Kristen Ramos	2020-04-14	1	1	255.866	24.3	5	255.866
39c01dfa-ce93-4001-97dd-60a03e6109c5	Pending	Amazon Pay	South America	Charles Smith	2024-03-10	1	1	318.559758	15.47	6	318.559758
39dccac2-7e7e-43fa-a3c3-6c04b3084837	Returned	PayPal	Europe	Susan Edwards	2020-04-30	1	1	1035.6223410000002	8.61	3	1035.6223410000002
39e4a19c-7047-4c23-97ee-425b53be9655	Returned	Credit Card	North America	Joseph Brooks	2021-03-01	1	1	18.527964	14.46	2	18.527964
39e7504d-12ed-41db-b91f-a32c800febf2	Pending	Gift Card	Europe	Roger Brown	2022-08-31	1	1	1399.481344	5.42	4	1399.481344
3a04fbc6-e2f4-4d59-9af8-7d928675d313	Cancelled	Credit Card	Asia	Crystal Williams	2022-11-13	1	1	756.439944	14.98	4	756.439944
3a0c327a-7faf-4c2a-9e6a-fe2601875443	Returned	Gift Card	South America	Steven Coleman	2022-06-29	1	1	2140.65457	6.54	5	2140.65457
3a0d80cf-60a1-46eb-8070-7486cbff9122	Cancelled	Debit Card	South America	Bradley Howe	2021-10-29	1	1	1594.25371	16.7	7	1594.25371
3a5cd3ab-9d07-40a0-b938-6295d7fce816	Cancelled	Credit Card	Australia	Caleb Camacho	2019-11-12	1	1	1698.957666	6.46	9	1698.957666
3a6bba2e-7a3c-4506-a7e2-bf3e0e137dd4	Pending	Debit Card	Asia	Adam Smith	2019-12-09	1	1	177.27177999999998	4.59	5	177.27177999999998
3a823052-1ef6-4667-a3e4-9b493e8aa0b1	Returned	Credit Card	Asia	Michelle Andersen	2024-10-03	1	1	3584.565824	7.32	8	3584.565824
3a932698-4555-4a57-a7ab-12bc5bfe245a	Returned	Debit Card	North America	Michelle Garza	2022-05-01	1	1	809.485124	21.29	7	809.485124
3a978daf-38fe-47a7-ab33-70117d31ba8c	Returned	Gift Card	Europe	Kristen Ramos	2019-10-04	1	1	711.980325	9.95	5	711.980325
3a9a2831-b9aa-4272-bc9c-11ab96e8cd64	Returned	Gift Card	Australia	Susan Edwards	2019-12-13	1	1	603.24924	23.62	5	603.24924
3aa238c0-f3c3-44bc-9bfa-9e4960b0c3f1	Returned	Credit Card	Asia	Caleb Camacho	2021-07-12	1	1	1494.17008	24.78	10	1494.17008
3abdf570-0949-4730-9193-765c1d11b25a	Returned	PayPal	South America	Steven Coleman	2023-11-04	1	1	692.657784	29.26	4	692.657784
3ac13f80-3c7f-4a2c-9d7a-8cf9047f664d	Returned	Amazon Pay	Europe	Crystal Williams	2024-08-08	1	1	306.630125	25.89	1	306.630125
3ac8e660-6a7a-4cc7-97b3-8726cd79a8fa	Pending	Credit Card	Asia	Adam Smith	2024-06-19	1	1	521.982972	20.23	3	521.982972
3af0f8f7-5947-47ed-9176-85bf755d43f2	Returned	Credit Card	North America	Michelle Garza	2024-04-28	1	1	473.362484	29.22	2	473.362484
3afe0988-912d-465e-b327-7706d698b3c8	Returned	Debit Card	Europe	Roger Brown	2021-09-16	1	1	2066.48121	13.67	10	2066.48121
3afe25f0-ce21-46c6-97c0-e72c2796b6c9	Returned	Amazon Pay	North America	Emily Matthews	2021-12-25	1	1	1823.4396	9.01	6	1823.4396
3b04bea9-39c9-48f6-97d4-6d9a44e7e539	Pending	Debit Card	Asia	Diane Andrews	2022-03-02	1	1	110.463348	22.92	3	110.463348
3b06889f-70bf-4cff-b987-7d203967aa2f	Cancelled	PayPal	North America	Kristen Ramos	2019-03-23	1	1	709.413994	22.71	2	709.413994
3b07a1ca-6bc9-4dca-a091-fea49bf3f6ed	Pending	Amazon Pay	Asia	Susan Edwards	2022-05-26	1	1	2749.921002	13.46	9	2749.921002
3b2eecca-37d8-4b43-a7b9-d33bfd5c440b	Returned	Gift Card	North America	Bradley Howe	2019-02-26	1	1	1376.6515649999997	22.05	9	1376.6515649999997
3b3ecd15-146b-4522-9172-0f64177edd5b	Returned	Amazon Pay	Europe	Johnny Marshall	2019-10-26	1	1	2735.0153600000003	11.12	10	2735.0153600000003
3b5b96df-677d-4f07-94e1-df7b0afecd13	Pending	PayPal	Asia	Mary Scott	2024-12-15	1	1	460.337724	23.77	2	460.337724
3b6d05b0-f28a-4756-bcb2-43c7aaa69e26	Cancelled	Debit Card	South America	Joseph Brooks	2019-03-11	1	1	274.446144	9.28	1	274.446144
3b716cba-c2e8-40db-9a7d-c86858155d2e	Pending	PayPal	North America	Mary Scott	2020-08-05	1	1	352.489513	23.87	1	352.489513
3b7a4594-a29c-40b8-bce8-b04c6b36eb94	Returned	Debit Card	North America	Christina Thompson	2019-06-06	1	1	66.357024	24.56	2	66.357024
3b7fa66d-4590-41b5-9a12-5ac020033f4e	Cancelled	Amazon Pay	Europe	Charles Smith	2024-01-22	1	1	84.180978	0.46	1	84.180978
3ba7e717-5e5a-4903-acb5-5ae9f4bd5a31	Returned	Credit Card	North America	Steven Coleman	2023-07-20	1	1	746.5336800000001	3.76	2	746.5336800000001
3beb84df-4340-4f35-a673-dbcbe8a37a6e	Pending	PayPal	North America	Caleb Camacho	2019-08-03	1	1	1204.900096	5.12	8	1204.900096
3bf05e76-77ed-49c0-a912-0a0ddd8f5030	Returned	Amazon Pay	Asia	Crystal Williams	2022-12-24	1	1	313.49333	23.37	1	313.49333
3bf6f83f-c12b-4fe9-8923-5d09dd5ff00d	Cancelled	Credit Card	South America	Kristen Ramos	2024-01-20	1	1	588.423168	20.19	6	588.423168
3bfc8d0c-b6ed-47b3-be8e-72da6ea3199d	Pending	PayPal	Asia	Diane Andrews	2022-03-28	1	1	346.398624	25.64	4	346.398624
3c1a10c4-4bf7-45ee-b94b-7a1572e6a872	Cancelled	Amazon Pay	Australia	Steven Coleman	2024-04-12	1	1	1053.986844	26.21	4	1053.986844
3c218eb8-7db5-4f51-b8c0-8e1f53da7c27	Returned	Debit Card	North America	Crystal Williams	2023-12-07	1	1	1194.1317359999998	13.48	3	1194.1317359999998
3c4088f1-8f3f-4923-8870-140f01e16930	Pending	PayPal	South America	Mary Scott	2024-04-03	1	1	652.911336	28.39	2	652.911336
3c4d31fe-6cb6-405c-981f-0c4c2ee223a0	Returned	Gift Card	Australia	Michelle Andersen	2021-08-26	1	1	1310.08874	7.98	5	1310.08874
3c571447-a683-424d-b812-e93b4c299548	Cancelled	Gift Card	Europe	Joseph Brooks	2020-01-26	1	1	549.6490399999999	0.57	8	549.6490399999999
3c6c8923-f13d-4555-9572-02de3c45b340	Cancelled	PayPal	North America	Crystal Williams	2024-02-02	1	1	180.816939	2.99	3	180.816939
3ca2c80b-e733-4fd2-95ed-2847d4abd699	Returned	Gift Card	North America	Christina Thompson	2022-09-12	1	1	267.219322	27.39	1	267.219322
3cb31bd9-758f-4e58-890f-88ce32eb737e	Returned	PayPal	Australia	Crystal Williams	2024-01-26	1	1	126.792542	18.78	1	126.792542
3cbcfb68-8b27-4b5c-90bc-866b25ff6d1a	Cancelled	Gift Card	South America	Charles Smith	2019-03-15	1	1	1294.91402	17.85	4	1294.91402
3cc51adc-b046-427e-a843-586e323c2651	Returned	PayPal	South America	Johnny Marshall	2022-04-20	1	1	3226.0691099999995	9.03	10	3226.0691099999995
3cdc9b64-df21-4dd8-8e23-b3234ca58bcf	Pending	Amazon Pay	Europe	Jason Nelson	2019-01-10	1	1	2115.46797	1.95	7	2115.46797
3ce4cf68-27cf-4cfb-9cee-e324cc2dd933	Pending	Debit Card	Europe	Michelle Andersen	2019-12-21	1	1	22.156288	10.08	4	22.156288
3cfdfb49-fe96-484a-b490-a85b6f1dc4ed	Cancelled	Credit Card	North America	Caleb Camacho	2020-12-29	1	1	584.0267	21.75	4	584.0267
3d3a7b93-9ead-4034-bd27-f40a0774c7ec	Pending	Gift Card	Australia	Michelle Garza	2021-11-02	1	1	414.810352	14.97	8	414.810352
3d46fb29-972c-4741-b1fc-551ecc7e43ba	Pending	Credit Card	Asia	Johnny Marshall	2019-07-28	1	1	91.181468	12.92	1	91.181468
3d483deb-05c4-455e-b4fb-ec05fc7107c6	Pending	Credit Card	South America	Jason Nelson	2023-10-06	1	1	3076.51008	10.96	8	3076.51008
3d7cdb3f-e20c-4333-8f27-44e1e600a443	Cancelled	Amazon Pay	North America	Kristen Ramos	2020-10-31	1	1	1504.7493719999998	20.23	4	1504.7493719999998
3d7f1bfb-40c8-4d84-981f-4aba21d2f32c	Returned	Credit Card	Asia	Steven Coleman	2024-05-24	1	1	1697.16547	24.21	5	1697.16547
3d85c973-1e0d-4f47-be63-1f94e3549972	Pending	Debit Card	South America	Crystal Williams	2021-01-12	1	1	632.217264	13.97	2	632.217264
3d8f64f6-22fa-4166-9bb3-c866bf38c26c	Returned	PayPal	North America	Steven Coleman	2021-12-01	1	1	232.3864	26.46	2	232.3864
3daf7052-f1af-4328-bdd9-c1f7cf79798e	Cancelled	Credit Card	Europe	Charles Smith	2020-07-19	1	1	929.778003	10.47	3	929.778003
3db8d61e-4019-44a8-87a7-4fe29631692b	Pending	Debit Card	Australia	Mary Scott	2021-12-02	1	1	292.6336	18.35	2	292.6336
3dc330d2-86ae-4c63-ac65-aab7ebb0c8b8	Returned	Debit Card	North America	Jason Nelson	2019-11-26	1	1	84.164475	24.55	1	84.164475
3ddbaf7b-c30d-4fb2-bb40-40acee294568	Cancelled	Credit Card	South America	Caitlyn Boyd	2021-06-13	1	1	2343.831744	5.24	8	2343.831744
3df0fe55-2858-4324-8790-1e1bd1758397	Pending	Debit Card	Asia	Bradley Howe	2022-06-22	1	1	66.52606	24.23	5	66.52606
3e0dd7fa-ca0b-4241-ab80-045a02cd470f	Pending	Debit Card	Asia	Mary Scott	2024-11-07	1	1	516.318972	22.52	3	516.318972
3e27c1ff-fd9a-4f4b-b558-f5cb4f9c5f59	Cancelled	PayPal	North America	Sandra Luna	2024-03-10	1	1	968.172948	24.44	3	968.172948
3e3be74f-da19-4902-86d9-ea5aaf1dc1a2	Cancelled	Credit Card	Asia	Caleb Camacho	2022-01-31	1	1	174.252869	17.49	1	174.252869
3e64550e-b485-4b31-a514-d2afa3fb4c07	Cancelled	Amazon Pay	North America	Michelle Garza	2020-07-12	1	1	1165.0194269999995	20.91	9	1165.0194269999995
3e6808ec-ba3f-4696-8e57-a02327bac25f	Returned	Gift Card	South America	Caleb Camacho	2023-06-18	1	1	3295.41906	9.67	10	3295.41906
3e6a0653-066f-4b9b-b85d-be922230e62f	Cancelled	Gift Card	Australia	Kristen Ramos	2023-05-02	1	1	302.212288	11.52	2	302.212288
3e811544-a627-468f-98a5-05bc5d73fa98	Returned	Amazon Pay	North America	Sandra Luna	2024-07-01	1	1	466.464565	6.21	1	466.464565
3e8cefe6-3056-4379-abc5-275f5f2f38a8	Cancelled	Gift Card	Asia	Jason Nelson	2022-12-06	1	1	1828.770818	24.18	7	1828.770818
3ea6afdc-efe2-47af-8521-2ce7e2f92628	Pending	Gift Card	North America	Michelle Andersen	2023-07-25	1	1	454.827648	24.16	4	454.827648
3ecf593f-d11e-44d9-b063-6a6a3ff91921	Pending	Amazon Pay	South America	Caleb Camacho	2023-02-19	1	1	283.386899	17.31	1	283.386899
3ee25f6a-4197-4579-8116-a20178872866	Cancelled	Debit Card	Asia	Crystal Williams	2021-10-05	1	1	784.3071	6.75	6	784.3071
3ee7c596-2fe0-48a3-b296-429e328d2434	Cancelled	Amazon Pay	Europe	Christina Thompson	2023-08-05	1	1	1065.683712	27.54	4	1065.683712
3ee8d891-dac1-4dec-8888-40324fd499b2	Pending	Gift Card	Europe	Diane Andrews	2019-08-19	1	1	2093.383376	10.01	8	2093.383376
3f09244a-c39c-4ba6-b600-0368f5ee8068	Cancelled	Debit Card	Australia	Steven Coleman	2022-11-06	1	1	1064.1304260000002	21.27	9	1064.1304260000002
3f0db2e3-3dd4-4d26-8157-42f541fea345	Returned	Gift Card	South America	Bradley Howe	2023-12-13	1	1	219.126796	11.22	1	219.126796
3f13a2dd-d68f-4405-9ab3-025c633eca7a	Cancelled	PayPal	South America	Mary Scott	2019-11-25	1	1	1424.3451249999998	28.25	5	1424.3451249999998
3f352309-75fe-487b-9db9-1ed17ad884ae	Cancelled	Gift Card	North America	Bradley Howe	2019-02-16	1	1	1200.709488	5.84	6	1200.709488
3f59814f-172e-43ad-833b-a6418af4356b	Cancelled	PayPal	Asia	Adam Smith	2019-11-26	1	1	905.807096	7.34	2	905.807096
3f5b8b6b-9b03-4613-b8b0-1fd225cd072b	Pending	Debit Card	Australia	Christina Thompson	2024-09-24	1	1	1079.54364	2.02	4	1079.54364
3f5d2a59-93cf-4e7a-9654-96effe8452dd	Returned	PayPal	Australia	Christina Thompson	2021-10-29	1	1	981.04448	18.68	4	981.04448
3f908a12-f421-423c-b8a2-4d99a8a33da6	Cancelled	Gift Card	Europe	Joseph Brooks	2022-11-16	1	1	2009.694645	26.65	7	2009.694645
3fc76fbe-275d-4ef4-9176-ff4afee85d0e	Pending	Credit Card	Europe	Jason Nelson	2022-04-17	1	1	261.18675	8.5	1	261.18675
3fcc0f4a-418e-4fbc-9f02-d8d185485cce	Returned	PayPal	Asia	Roger Brown	2023-01-25	1	1	3649.0168	26.52	10	3649.0168
3fcc7a92-e5c9-4a6a-83e9-46ca4b3f8da1	Returned	Gift Card	South America	Kristen Ramos	2022-09-17	1	1	239.299612	10.22	1	239.299612
3fe387e3-412c-47b1-97a5-db4895de0c93	Pending	Debit Card	North America	Jason Nelson	2021-07-06	1	1	675.145072	17.04	2	675.145072
4005041e-859e-4062-808c-266d47eef4e1	Returned	Amazon Pay	Europe	Susan Edwards	2019-02-15	1	1	2990.309553	18.71	9	2990.309553
401a9e23-1f02-4480-8a12-247f2908739e	Cancelled	Credit Card	Europe	Crystal Williams	2021-02-12	1	1	1620.786375	12.25	5	1620.786375
402125a9-2c97-408e-8696-1e59d79335d8	Returned	PayPal	South America	Charles Smith	2020-12-21	1	1	261.38027700000004	29.53	1	261.38027700000004
407c3115-f969-4c25-bfea-96fb6e29e639	Cancelled	Gift Card	Europe	Bradley Howe	2021-02-10	1	1	1523.510308	13.49	4	1523.510308
4094ef96-1ab1-4ddb-9d7a-5a910bc2120f	Cancelled	PayPal	Asia	Joseph Brooks	2023-07-31	1	1	1744.175736	28.34	9	1744.175736
40be4db5-49a1-424e-9e1c-4d5f4e722443	Pending	Gift Card	Asia	Steven Coleman	2023-01-29	1	1	252.075006	19.47	2	252.075006
410ba704-e844-4fab-803a-631852bb7cee	Returned	Gift Card	South America	Charles Smith	2023-06-05	1	1	1033.69235	21.05	10	1033.69235
41104de8-7801-401c-9fd3-6c7666acfa43	Returned	PayPal	Asia	Roger Brown	2021-07-18	1	1	1592.879632	9.96	4	1592.879632
41173414-ee00-440e-8ece-2ab1fb414783	Cancelled	Gift Card	Europe	Caitlyn Boyd	2021-09-04	1	1	1306.175184	0.84	6	1306.175184
4119152c-bb54-4d71-a951-8432d3402099	Pending	PayPal	Asia	Steven Coleman	2019-03-16	1	1	1667.362788	23.56	7	1667.362788
411de139-1a24-49e9-9ecf-eb72ea555677	Pending	Gift Card	Australia	Roger Brown	2019-01-11	1	1	3040.972	17.6	10	3040.972
4149e68a-4bae-4086-8b90-d820215634db	Returned	Amazon Pay	South America	Johnny Marshall	2021-01-03	1	1	2368.614262	22.53	7	2368.614262
4151b1c7-034e-431e-8e3c-b416843f6a04	Pending	Gift Card	South America	Steven Coleman	2019-10-23	1	1	1720.471536	25.03	7	1720.471536
4159b3a1-8d5c-41c6-b902-0e9b754325bc	Cancelled	Gift Card	Europe	Michelle Garza	2020-08-12	1	1	652.400343	1.03	7	652.400343
41676259-c11b-49f1-a95f-c3ede2558a3b	Pending	PayPal	North America	Crystal Williams	2023-04-14	1	1	200.433475	4.25	1	200.433475
417f5a65-0a13-4f40-934b-53cc43df9462	Cancelled	Gift Card	North America	Steven Coleman	2020-07-19	1	1	502.840224	16.66	2	502.840224
4192c214-7340-480a-8185-7da41282f6e1	Cancelled	Amazon Pay	Asia	Jason Nelson	2021-10-06	1	1	1046.727145	10.31	5	1046.727145
419a102c-78bc-4ce0-a5b1-a088ba80bdd5	Pending	Debit Card	South America	Sandra Luna	2020-06-18	1	1	1240.6043	7.7	10	1240.6043
41a65988-29c8-4ec6-b609-5eea1252f27d	Returned	Gift Card	Australia	Michelle Garza	2021-03-03	1	1	1634.2836250000005	20.81	5	1634.2836250000005
41a90624-76c1-4cc1-bb5d-8618ff2c433b	Returned	Gift Card	North America	Michelle Garza	2023-12-02	1	1	796.5428999999999	22.95	4	796.5428999999999
41b66060-33fb-4db5-a739-f2e1293926a9	Returned	Amazon Pay	Australia	Susan Edwards	2024-05-09	1	1	169.733148	16.09	1	169.733148
41ccac5d-6107-4da5-9585-1bc1edcfef8f	Returned	Credit Card	North America	Joseph Brooks	2022-05-16	1	1	876.2032199999999	26.53	10	876.2032199999999
41e68116-76e3-4f86-98fa-166b4dd54032	Returned	Debit Card	Australia	Roger Brown	2019-03-26	1	1	1461.4182	8.26	5	1461.4182
4208c50e-0ed8-4e8f-b26b-b16ee6870916	Returned	Credit Card	Asia	Diane Andrews	2020-05-25	1	1	814.791516	12.22	2	814.791516
421467cc-1688-4c0f-af93-6cd432bf7421	Cancelled	Amazon Pay	North America	Steven Coleman	2021-02-10	1	1	1744.61914	8.04	5	1744.61914
42363c69-dc08-4240-8503-0f68eb759e20	Returned	PayPal	Europe	Steven Coleman	2021-04-18	1	1	534.044232	29.46	3	534.044232
48ba21e9-60da-492f-876f-df32e4419c38	Returned	Amazon Pay	Asia	Jason Nelson	2022-09-11	1	1	2066.13117	4.78	5	2066.13117
423a75d5-bb1d-4c85-b261-3295a9310c13	Pending	Credit Card	North America	Christina Thompson	2021-12-31	1	1	2156.925267	9.21	7	2156.925267
423b770b-5dae-4693-9704-bad694b16076	Returned	Amazon Pay	Australia	Susan Edwards	2024-11-05	1	1	627.193235	26.13	5	627.193235
42520fd6-5803-489d-afa6-486a342ad86a	Cancelled	Amazon Pay	Asia	Caleb Camacho	2023-10-14	1	1	1228.84785	24.91	6	1228.84785
426674a2-5e72-4d2b-b0df-dafe1ea75213	Returned	PayPal	North America	Caitlyn Boyd	2022-02-25	1	1	402.72756	19.39	8	402.72756
42879361-aa66-4836-803c-6de0b5ca8114	Returned	Debit Card	Europe	Sandra Luna	2023-08-12	1	1	2685.210864	13.84	7	2685.210864
42903e38-156c-473b-93a9-13d2d5848760	Cancelled	Debit Card	Australia	Crystal Williams	2019-03-12	1	1	539.844304	6.42	2	539.844304
429d5a5b-dd49-41f7-9126-1b3d12db6d44	Returned	Credit Card	Asia	Adam Smith	2022-11-26	1	1	18.21864	11.56	2	18.21864
42ad88c0-6ec0-4d11-b93e-6e7fa88db77a	Cancelled	Amazon Pay	Europe	Sandra Luna	2023-03-31	1	1	2014.81854	6.73	10	2014.81854
42c37c70-0abe-457e-b299-18db9351343a	Returned	Debit Card	Asia	Crystal Williams	2023-03-19	1	1	617.26824	22.18	3	617.26824
42d27ef4-c997-44b7-b20f-958b39ff14e8	Returned	Amazon Pay	North America	Bradley Howe	2019-04-29	1	1	1175.91912	4.49	9	1175.91912
42e7e283-85cb-4c26-8844-35faa115cc8b	Pending	PayPal	Europe	Emily Matthews	2023-09-01	1	1	771.8520599999999	26.2	7	771.8520599999999
42f2512d-38ae-473d-9c75-30d181e0568a	Cancelled	Credit Card	Asia	Johnny Marshall	2024-11-12	1	1	283.311375	28.75	1	283.311375
43181d29-9715-4e2e-a454-040d0edc9aa8	Pending	Amazon Pay	Europe	Christina Thompson	2022-02-02	1	1	1276.6928400000002	15.26	5	1276.6928400000002
43248d6c-25a4-40e3-bd32-73124317c75b	Returned	Debit Card	Australia	Michelle Andersen	2020-05-02	1	1	407.037642	7.63	2	407.037642
434b201f-cad2-41d2-bf7e-afd0ba416578	Cancelled	PayPal	North America	Diane Andrews	2021-09-20	1	1	678.2257440000001	11.52	9	678.2257440000001
4363f735-fde0-4568-bdd1-fbe3be16eee1	Returned	Credit Card	Europe	Diane Andrews	2024-08-28	1	1	1069.682691	14.53	7	1069.682691
4371e0ee-cc64-4468-813c-cf304895637d	Pending	Amazon Pay	North America	Joseph Brooks	2024-01-28	1	1	417.1689	15.8	9	417.1689
43832d73-84c6-425f-b9cb-a560a43e665e	Pending	Gift Card	North America	Joseph Brooks	2022-04-30	1	1	1108.7443750000002	25.65	5	1108.7443750000002
43935499-64f8-4932-8d81-32c20a99fe2b	Cancelled	Amazon Pay	North America	Kristen Ramos	2019-08-04	1	1	2373.66464	21.96	8	2373.66464
43b03673-139a-42fc-82f8-92cd079eab65	Returned	Gift Card	Asia	Crystal Williams	2023-07-29	1	1	2406.8096	16.8	10	2406.8096
43d2b83a-f76b-4cd6-8625-0315b26bdb5f	Pending	PayPal	North America	Kristen Ramos	2022-05-17	1	1	182.178945	6.79	1	182.178945
440bf639-e605-4bd2-af97-a9f4808237b9	Returned	Credit Card	Asia	Johnny Marshall	2022-12-28	1	1	165.44169000000002	16.57	2	165.44169000000002
44329139-5342-4247-bb44-0844f31a68d9	Cancelled	PayPal	Australia	Caleb Camacho	2023-03-09	1	1	238.961216	25.77	2	238.961216
4437e7db-0ead-454f-b644-d490a35287b3	Pending	Debit Card	Australia	Sandra Luna	2024-08-13	1	1	2328.1065900000003	3.37	6	2328.1065900000003
444e6ad7-1c25-4480-9e17-fa8ac2f12b59	Pending	Debit Card	North America	Sandra Luna	2019-06-22	1	1	195.882596	8.79	1	195.882596
44579d98-e939-464a-8919-f2c8342f81fe	Pending	Debit Card	Europe	Roger Brown	2021-06-28	1	1	393.491952	23.08	4	393.491952
4461f8c5-baef-4c57-b249-d8076eadea65	Pending	Credit Card	Asia	Adam Smith	2020-11-11	1	1	567.5995360000001	27.48	4	567.5995360000001
44622af5-357f-4e3e-a11e-959e5ca0889c	Returned	Debit Card	Europe	Caleb Camacho	2020-07-18	1	1	1764.56961	25.93	6	1764.56961
4474445e-015d-4d1d-bff0-2ea89790a548	Pending	Amazon Pay	Australia	Michelle Andersen	2019-12-28	1	1	66.41356	14.15	1	66.41356
4479077a-1e2b-488b-84e3-507e685823d2	Returned	Debit Card	South America	Emily Matthews	2020-01-14	1	1	1956.939824	13.44	7	1956.939824
44793f0c-8c92-43aa-8046-83a32e99a1e4	Cancelled	Amazon Pay	Australia	Johnny Marshall	2020-02-18	1	1	989.5342829999998	28.77	3	989.5342829999998
447dc4eb-876a-473b-92af-ee2619e026be	Cancelled	Credit Card	Europe	Michelle Andersen	2019-10-15	1	1	2432.482902	10.03	6	2432.482902
44974f1c-7f2a-4426-8729-fd703f94d9cf	Returned	Gift Card	Australia	Crystal Williams	2019-09-08	1	1	1791.0312	25.6	5	1791.0312
44d19145-316c-4cd3-859f-b9c2811edd97	Returned	Amazon Pay	Australia	Caitlyn Boyd	2022-07-31	1	1	694.4877100000001	1.86	5	694.4877100000001
44d91ac0-491c-408d-82f3-a919ceb89957	Pending	Credit Card	North America	Johnny Marshall	2019-10-27	1	1	249.52455	10.9	3	249.52455
44de7775-50b2-4379-8f3b-cefd204b6663	Cancelled	Credit Card	Australia	Johnny Marshall	2021-01-28	1	1	895.9074499999999	0.51	10	895.9074499999999
44e89d81-2c72-4f3d-8f29-0021c6f238c4	Pending	Gift Card	South America	Michelle Andersen	2021-08-09	1	1	916.14138	2.65	4	916.14138
44f5d995-e0b6-4549-b7cc-ee9e9ebbe6ea	Returned	Amazon Pay	Australia	Steven Coleman	2019-11-17	1	1	1770.696564	17.41	7	1770.696564
44fc89ef-2be4-4113-93c8-751509f30f7d	Pending	PayPal	Australia	Kristen Ramos	2022-01-11	1	1	2918.787416	22.47	8	2918.787416
44fe9453-9151-44ed-8e51-15d7bbeb1766	Returned	Credit Card	Australia	Jason Nelson	2021-09-30	1	1	980.1518999999998	9	3	980.1518999999998
451944d4-f8b3-4612-bf8d-af0bfe0a1bd1	Cancelled	PayPal	Asia	Diane Andrews	2019-07-04	1	1	1787.564625	0.15	7	1787.564625
452643ae-9534-4c21-a060-67bd0b6b9ce9	Returned	Debit Card	Asia	Michelle Garza	2020-05-18	1	1	1334.278008	17.14	7	1334.278008
45347b67-02fa-4400-ae70-7bb8e1d72a6a	Returned	PayPal	South America	Sandra Luna	2023-03-18	1	1	1423.368086	27.93	7	1423.368086
45393add-c0db-4de3-871a-93c98215eb7b	Pending	Gift Card	Australia	Jason Nelson	2020-12-08	1	1	267.917616	21.08	2	267.917616
4546ab0c-d453-49e9-aa76-95d2613a830b	Returned	Amazon Pay	Asia	Michelle Garza	2020-10-14	1	1	3131.577834	3.86	7	3131.577834
45472127-7347-4bc2-a968-5c8f867808e0	Pending	PayPal	Australia	Michelle Andersen	2024-10-01	1	1	258.492608	24.32	2	258.492608
454a0a35-d5d0-43e2-b948-7436e7c73eda	Cancelled	Gift Card	Asia	Jason Nelson	2019-08-02	1	1	90.52665	3.5	3	90.52665
4550220b-34c4-4366-aa1c-0d838f3649a2	Pending	Amazon Pay	South America	Bradley Howe	2021-03-01	1	1	133.294616	22.44	2	133.294616
456743cb-34ad-475c-a495-ced942744285	Pending	Amazon Pay	Asia	Caitlyn Boyd	2019-07-11	1	1	2116.657692	13.64	9	2116.657692
45689aaa-dde7-4bf6-8cfa-1cc9b604cdc9	Pending	Credit Card	Europe	Roger Brown	2023-05-13	1	1	1929.4401000000005	7.1	5	1929.4401000000005
456e85b0-5deb-4794-aba4-f153afdf580a	Returned	Credit Card	Asia	Johnny Marshall	2024-07-24	1	1	714.771575	22.79	7	714.771575
458fb6e0-8f6f-41ab-81fb-295526303a47	Cancelled	Amazon Pay	Australia	Kristen Ramos	2019-11-17	1	1	1014.972516	23.89	6	1014.972516
4598035d-3067-482c-ae8f-33a7aeb52e70	Returned	Debit Card	Europe	Bradley Howe	2024-01-03	1	1	179.3896	8.25	1	179.3896
45a1e801-06e6-4545-87b5-638c2a178e53	Returned	Credit Card	Asia	Caleb Camacho	2023-01-30	1	1	1615.7218240000002	9.53	4	1615.7218240000002
45afd0a4-6c08-494b-b836-a0123c914b6a	Pending	Gift Card	North America	Mary Scott	2024-07-26	1	1	2064.66816	5.2	8	2064.66816
45dbb238-13fc-44c7-930b-f00af21bf5b6	Returned	Amazon Pay	Europe	Mary Scott	2020-03-24	1	1	56.770654	2.69	1	56.770654
45e89360-0384-4c6e-a5d5-afd14f53973f	Pending	Credit Card	Asia	Joseph Brooks	2021-09-04	1	1	512.33168	25.01	2	512.33168
45f2d504-2f4d-49bc-9293-e1f02c237c33	Returned	Credit Card	Australia	Diane Andrews	2024-09-03	1	1	1522.3367879999998	6.62	6	1522.3367879999998
4620e2a2-f8a7-4499-8174-0bfc4df90178	Returned	Debit Card	Australia	Steven Coleman	2022-08-19	1	1	312.98472	1.36	2	312.98472
46274089-db72-4e6c-a94a-1c9325ee484a	Cancelled	Debit Card	Europe	Sandra Luna	2022-10-03	1	1	3229.13063	20.81	10	3229.13063
463fc029-f0d9-4073-a570-8e5f46c23ad6	Pending	PayPal	North America	Caleb Camacho	2023-01-29	1	1	590.514444	22.59	2	590.514444
464f29f5-7526-406b-9f0c-95f9579694c1	Returned	Amazon Pay	Asia	Roger Brown	2021-03-08	1	1	371.236624	5.04	2	371.236624
4653aa40-4715-459b-bbbc-95145f9e985c	Cancelled	PayPal	Australia	Charles Smith	2021-01-28	1	1	657.390272	9.56	7	657.390272
465abf06-94ce-4732-9a2c-ea8a08a77910	Returned	Gift Card	North America	Kristen Ramos	2021-01-29	1	1	1448.2042399999998	1.67	8	1448.2042399999998
466506dc-6747-407f-b847-d160f67d0c40	Cancelled	PayPal	South America	Sandra Luna	2024-09-27	1	1	316.335912	0.86	6	316.335912
466a8efe-7d5d-4c85-ba1a-184648e71b38	Returned	PayPal	Australia	Mary Scott	2019-03-10	1	1	690.6291200000001	22.7	4	690.6291200000001
46700085-40c6-4dc1-b4b6-26f8e59ab8eb	Cancelled	Debit Card	South America	Charles Smith	2021-02-28	1	1	2161.368144	9.52	6	2161.368144
4673a755-ec57-4177-8b47-233c6ea32496	Returned	Credit Card	South America	Diane Andrews	2024-11-04	1	1	1166.751936	15.58	8	1166.751936
46831dc1-4061-4763-ad24-5b43b01d8a37	Returned	Amazon Pay	Asia	Roger Brown	2020-05-24	1	1	1121.1255	17.64	5	1121.1255
469d4424-2d5a-437e-be0c-99340145144d	Pending	Gift Card	Australia	Diane Andrews	2020-07-28	1	1	1578.1891	6.3	10	1578.1891
46e7cc05-b54c-4438-afe9-0d80757f72f6	Pending	Amazon Pay	South America	Steven Coleman	2023-06-29	1	1	3301.553151	5.97	9	3301.553151
46f7184c-a832-4462-bed8-69fdc41774b7	Returned	Amazon Pay	North America	Bradley Howe	2023-07-20	1	1	890.412188	1.49	2	890.412188
4700b66f-a260-4076-88de-9fe46ced1e41	Returned	Gift Card	North America	Michelle Garza	2023-02-16	1	1	1947.47462	13.88	7	1947.47462
4718ced5-5c96-495a-aa33-d0604c9c2813	Returned	Credit Card	Australia	Diane Andrews	2020-06-16	1	1	1089.126996	6.21	6	1089.126996
47249ad3-9f35-41b4-9a4e-e627c20dc1a0	Pending	Gift Card	Australia	Joseph Brooks	2020-05-21	1	1	3857.14862	4.71	10	3857.14862
47486479-a4d5-423a-a791-458aa92f50b2	Returned	Credit Card	Europe	Adam Smith	2023-01-15	1	1	1582.25886	26.29	5	1582.25886
474bd3d8-5994-4b55-b010-4942415244af	Pending	PayPal	South America	Sandra Luna	2023-04-02	1	1	55.704620000000006	27.05	2	55.704620000000006
47522774-730e-44d7-b0f2-8ad92fa4161f	Returned	Gift Card	South America	Roger Brown	2019-01-19	1	1	3344.1899000000003	8.9	10	3344.1899000000003
4752a01d-3189-4dc3-a934-6b3f4a0c0c4a	Cancelled	PayPal	South America	Sandra Luna	2024-03-31	1	1	656.23897	19.47	5	656.23897
475cdba1-2c93-433b-87e8-8e3cdaed4451	Cancelled	PayPal	Australia	Roger Brown	2024-10-24	1	1	764.2166399999999	12.88	6	764.2166399999999
475e70d4-df85-46ca-a2c9-90e74f9fdbaf	Returned	PayPal	Asia	Charles Smith	2022-05-21	1	1	1690.650444	13.73	4	1690.650444
47b0a73a-331b-49cb-aa38-5048b2e5b507	Cancelled	Amazon Pay	Australia	Bradley Howe	2023-11-12	1	1	1130.227128	18.76	3	1130.227128
47b576ef-2ab5-4a2c-b593-6b497bd100e3	Pending	Gift Card	Europe	Emily Matthews	2023-08-17	1	1	2666.16805	9.26	7	2666.16805
47bb8e7c-64d3-400d-af2d-615bbdcb0b63	Pending	PayPal	North America	Joseph Brooks	2023-11-23	1	1	1717.371	13.5	10	1717.371
47c694d4-4fe3-4ab8-8b5b-c14ccde69b08	Cancelled	PayPal	Asia	Caitlyn Boyd	2023-06-25	1	1	1043.49924	12.85	8	1043.49924
47c6fd74-6fc1-440e-8f63-74204c181419	Pending	Amazon Pay	South America	Steven Coleman	2021-10-17	1	1	1950.0817400000003	28.29	10	1950.0817400000003
48014752-b2fe-4784-a4c8-9f4896585de7	Pending	Credit Card	Asia	Mary Scott	2020-03-30	1	1	3856.0586	13.05	10	3856.0586
4846b8c5-4fdd-4ee0-9c4a-985be351dc55	Pending	Debit Card	Australia	Steven Coleman	2022-12-20	1	1	2627.926938	12.01	6	2627.926938
485818b7-d033-4018-83e5-2007d01d0209	Cancelled	Credit Card	South America	Johnny Marshall	2024-05-03	1	1	173.60437	13.05	2	173.60437
485ed15e-ffed-453f-9ba0-44a3c72a5a52	Cancelled	Amazon Pay	South America	Sandra Luna	2021-11-17	1	1	112.444104	19.98	6	112.444104
48683d3b-67e2-4048-a82b-b38784e3ebf0	Pending	Gift Card	Europe	Michelle Garza	2019-12-23	1	1	358.552944	23.12	1	358.552944
4873ae8a-af92-4c5c-b7b8-dea352f9125a	Returned	Debit Card	Asia	Charles Smith	2023-08-13	1	1	1030.559964	25.26	3	1030.559964
488a724e-7b5c-4d12-a516-5d2c9a0ee5bd	Returned	Amazon Pay	Asia	Crystal Williams	2020-07-07	1	1	32.195268000000006	29.72	1	32.195268000000006
489da55c-412e-4d17-82f6-a4871c55c36b	Cancelled	Credit Card	Australia	Charles Smith	2024-08-10	1	1	2189.793636	10.18	6	2189.793636
48aa940a-5cb5-4103-8d89-19c10fd26aaf	Returned	Debit Card	South America	Johnny Marshall	2019-01-01	1	1	3430.122138	21.33	9	3430.122138
48ba2d70-e015-47f1-ab98-391259041f15	Cancelled	Credit Card	Asia	Christina Thompson	2022-11-10	1	1	211.590423	7.03	1	211.590423
48bb8fbd-cb40-44ab-b93d-6eb94a818dfc	Returned	Amazon Pay	Europe	Steven Coleman	2019-03-16	1	1	2400.609328	13.58	8	2400.609328
48ceb901-448f-4d95-a148-5e5ac969a200	Cancelled	Gift Card	North America	Charles Smith	2022-01-04	1	1	2681.91652	22.05	8	2681.91652
48d8d46d-7647-4ccb-a84c-d881383e53b2	Returned	PayPal	North America	Roger Brown	2024-06-28	1	1	463.283964	11.34	2	463.283964
48f09b05-5117-473a-9057-522ccf1f876f	Returned	Debit Card	Europe	Johnny Marshall	2022-07-12	1	1	1183.747656	3.12	3	1183.747656
4918fff7-3f14-4d52-9ba4-02272fe58663	Pending	Credit Card	Australia	Joseph Brooks	2020-11-07	1	1	1872.034299	23.39	9	1872.034299
49308992-ff2d-4216-b61c-de5c655c2742	Returned	Amazon Pay	South America	Diane Andrews	2022-06-10	1	1	565.8708399999999	14.21	5	565.8708399999999
4930b813-adf3-49a5-8fd2-869b7e5e7238	Returned	Debit Card	Asia	Jason Nelson	2019-01-17	1	1	822.152136	15.27	8	822.152136
49389fa4-96c1-4fdd-b9e3-ef859ba19539	Cancelled	Debit Card	Europe	Emily Matthews	2023-07-05	1	1	521.623756	6.23	2	521.623756
494af1df-1fd6-4d06-944d-72682f94ee00	Pending	Amazon Pay	Australia	Michelle Garza	2023-07-19	1	1	2356.733808	15.08	9	2356.733808
49573826-62d5-4843-aaca-8cae1d8d16b0	Cancelled	Amazon Pay	South America	Michelle Andersen	2021-11-20	1	1	37.776576	27.52	2	37.776576
495f31fc-e7fa-4821-957d-441abcb32c76	Pending	Amazon Pay	South America	Christina Thompson	2020-12-05	1	1	763.690545	2.41	3	763.690545
496d3e52-b71e-42d0-8079-64f9ee1701e1	Returned	Credit Card	Asia	Michelle Andersen	2022-08-14	1	1	163.72125	5.5	3	163.72125
497ea4ee-15df-444f-8c9c-1202bc57a7aa	Returned	Debit Card	Australia	Christina Thompson	2023-07-15	1	1	439.018608	22.99	2	439.018608
4986866e-4f0b-4358-a29b-5d14dae90c4e	Cancelled	Debit Card	Australia	Caleb Camacho	2024-07-18	1	1	120.97803600000002	23.32	1	120.97803600000002
499c2b6e-b65e-45c2-873e-7e3f4da0f7e8	Cancelled	Credit Card	Europe	Mary Scott	2023-05-12	1	1	892.257376	2.66	2	892.257376
499ea2ef-3c7b-419a-813b-2671b4a79205	Cancelled	Credit Card	Australia	Susan Edwards	2024-08-09	1	1	741.29482	19.56	5	741.29482
49a94f7a-a135-4442-9b39-ab364a892dd8	Returned	Debit Card	South America	Susan Edwards	2019-05-30	1	1	279.59239	27.18	5	279.59239
49f8c5a8-2868-46c6-97ad-405df72c588b	Returned	Debit Card	Australia	Joseph Brooks	2022-06-01	1	1	149.907609	25.63	1	149.907609
49fe15be-ad84-4617-9997-3b690b869379	Returned	Amazon Pay	North America	Michelle Garza	2020-09-02	1	1	272.2785	2.5	1	272.2785
4a1b578d-aa2d-4b3e-a38c-464e92fc7c87	Returned	Gift Card	North America	Bradley Howe	2023-10-11	1	1	699.486788	11.73	4	699.486788
4a2634b6-2929-4ca7-9b8d-6a60d6a4ea42	Cancelled	Gift Card	Asia	Christina Thompson	2021-07-30	1	1	227.247344	24.17	8	227.247344
4a268ea7-80d1-4df5-b8ed-3308679d2eba	Pending	Credit Card	Australia	Joseph Brooks	2021-02-23	1	1	528.51864	16.69	8	528.51864
4a433141-d83f-4831-af9e-159da73bb7ed	Pending	Gift Card	Europe	Caitlyn Boyd	2019-02-27	1	1	441.45675000000006	6.57	6	441.45675000000006
4a746ae3-caee-43b0-be3c-9347ee4b411b	Pending	Amazon Pay	South America	Bradley Howe	2022-08-03	1	1	2403.933504	18.14	7	2403.933504
4a7de686-d513-40be-8100-1ae09e18a868	Pending	Credit Card	Australia	Kristen Ramos	2021-08-19	1	1	249.4074	14.44	1	249.4074
4a93d6ce-2b4a-4fcd-a3f3-0d98fc6bbffc	Cancelled	Debit Card	Europe	Charles Smith	2019-02-14	1	1	660.477632	10.64	4	660.477632
4a9a6fee-cf49-46c7-9f29-bba9ff3fa25d	Returned	PayPal	Europe	Kristen Ramos	2020-07-28	1	1	1090.793817	16.89	9	1090.793817
4aa4a623-8f54-4bfb-b3b5-02f0dba33b7f	Returned	Amazon Pay	Europe	Sandra Luna	2023-03-25	1	1	1737.6994250000002	5.15	5	1737.6994250000002
4ad95c11-fbfb-4b8e-96fc-b08bb66c02ac	Pending	Credit Card	North America	Michelle Andersen	2021-03-24	1	1	223.2219	13.5	3	223.2219
4b43abcc-bf67-4af8-96d4-8b9ef8e5a501	Pending	PayPal	Asia	Christina Thompson	2022-09-08	1	1	149.67045	21.7	5	149.67045
4b45b863-381a-4667-be2e-c17fadb0e0fc	Returned	Amazon Pay	Asia	Bradley Howe	2019-09-18	1	1	1205.8835	7.4	5	1205.8835
4b47a8f4-38cc-4673-bcf8-7580b57fa044	Pending	PayPal	North America	Christina Thompson	2019-03-28	1	1	1503.91384	18.23	10	1503.91384
4b57666a-656f-4e83-976d-38b4b4f948d5	Pending	Credit Card	Australia	Michelle Garza	2022-02-18	1	1	362.235902	5.81	2	362.235902
4b7f52e3-47d9-424f-b945-7e2ce421a2c2	Returned	Credit Card	Asia	Michelle Garza	2024-11-02	1	1	290.16	0	2	290.16
4b8c465a-f469-4702-bfe8-29bcb0854ee2	Returned	PayPal	Australia	Johnny Marshall	2019-02-04	1	1	428.39055	12.26	5	428.39055
4bd76117-6637-45d8-8770-2fbc7130a61e	Pending	PayPal	Australia	Crystal Williams	2021-07-14	1	1	307.59862000000004	20.55	1	307.59862000000004
4c0ef3ac-0128-4e7f-9288-2a8a304de027	Pending	Debit Card	North America	Diane Andrews	2022-09-19	1	1	3998.50368	10.62	10	3998.50368
4c14d7cd-7e22-4f6b-ad50-018dc0e4ceec	Pending	Gift Card	Australia	Steven Coleman	2022-02-22	1	1	94.186684	17.87	2	94.186684
4c16037c-eb43-4abd-9517-95388e22e933	Cancelled	Credit Card	North America	Susan Edwards	2022-10-14	1	1	2013.4176	3.94	5	2013.4176
4c233c90-a403-4313-a11b-da999134cc36	Returned	Amazon Pay	Australia	Johnny Marshall	2021-10-13	1	1	147.946752	24.64	8	147.946752
4c4a4b8f-ba99-47fa-a00d-a165bf237cba	Returned	Gift Card	South America	Crystal Williams	2020-07-09	1	1	681.236088	13.01	3	681.236088
4c58c076-ae79-4cba-b1ac-61b94874b309	Pending	Debit Card	Asia	Jason Nelson	2024-12-25	1	1	490.0898880000001	22.88	3	490.0898880000001
4c6f22fc-9e83-4034-9c9d-be742e346623	Cancelled	Credit Card	Australia	Johnny Marshall	2023-10-27	1	1	1266.881088	0.44	6	1266.881088
4c7d30df-fc7d-47ad-946f-a358491ff8af	Pending	PayPal	Europe	Kristen Ramos	2024-11-06	1	1	2771.325522	16.97	9	2771.325522
4c97ab49-0aa5-406f-ae16-0aa6937ac195	Returned	Debit Card	North America	Charles Smith	2019-12-05	1	1	451.274082	9.43	7	451.274082
4c9f2d19-2d71-4b30-b6be-2f9e0ff58505	Returned	Credit Card	South America	Diane Andrews	2021-09-29	1	1	3812.577336	11.79	9	3812.577336
4cbcb553-0c0a-4b94-a0b2-b116629f8727	Returned	Credit Card	North America	Diane Andrews	2020-04-11	1	1	284.7936	22	8	284.7936
4ce3686a-4608-4037-bd43-68f220341055	Pending	PayPal	Europe	Charles Smith	2022-07-29	1	1	1436.994	13.75	4	1436.994
4cf060d8-fbc9-4523-b69d-ebfe3feff3f3	Pending	PayPal	South America	Charles Smith	2020-04-10	1	1	764.789736	25.99	8	764.789736
4cf99057-d2bc-4716-88a6-e2689c182edf	Returned	Gift Card	South America	Caitlyn Boyd	2021-02-12	1	1	1231.692708	7.97	6	1231.692708
4d0183a4-40b1-41ac-a497-ac0719290bde	Cancelled	Debit Card	Australia	Charles Smith	2023-03-28	1	1	1391.9984960000002	7.56	7	1391.9984960000002
4d0671a8-6ec6-4438-b456-01e9390ebd47	Returned	Debit Card	South America	Caitlyn Boyd	2021-08-01	1	1	18.017032	22.74	4	18.017032
4d38a536-eab5-430a-8a67-ab773fde9df1	Returned	Credit Card	South America	Susan Edwards	2019-08-31	1	1	1369.963952	15.38	8	1369.963952
4d39d057-71ce-4e6d-a49c-06760ea8dc3a	Cancelled	PayPal	Australia	Christina Thompson	2022-12-02	1	1	2915.1160320000004	16.24	8	2915.1160320000004
4d444226-e7b4-4e34-b24a-898aeae8179b	Pending	Credit Card	North America	Crystal Williams	2023-03-11	1	1	1155.8518559999998	12.24	6	1155.8518559999998
4d4c7437-b5f3-4d36-8ebc-c69a1e3bb693	Returned	Gift Card	South America	Caitlyn Boyd	2021-03-19	1	1	2258.60862	14.02	10	2258.60862
4d55e486-07a2-43c8-b5cd-132642297d9c	Returned	Gift Card	Asia	Susan Edwards	2020-03-13	1	1	1782.838944	9.64	4	1782.838944
4d639db2-f240-435f-bd1d-2051f9525dd0	Cancelled	Amazon Pay	North America	Joseph Brooks	2020-09-15	1	1	634.149756	26.83	4	634.149756
4d6cef9b-f115-4142-b5c7-51df0e20646f	Pending	PayPal	Asia	Caitlyn Boyd	2024-02-23	1	1	759.66192	25.93	4	759.66192
4d6fd0ff-8879-433d-96a5-94009a947bf8	Cancelled	Credit Card	North America	Sandra Luna	2019-09-22	1	1	175.03530000000003	10.1	3	175.03530000000003
4d9778ca-d57d-48dc-84ec-7e5d1f1d1a63	Cancelled	Credit Card	North America	Christina Thompson	2021-03-15	1	1	2372.73378	3.13	5	2372.73378
4dbbc518-bf2a-4399-8eb9-d9425d6ab88f	Pending	Amazon Pay	Australia	Mary Scott	2023-09-28	1	1	3139.18255	9.5	7	3139.18255
4dcb0ee1-991b-4ca3-9f7b-ea33ee21bf46	Returned	Debit Card	North America	Emily Matthews	2023-01-15	1	1	4359.31989	11.81	10	4359.31989
4de26023-97d7-41d2-8217-885dcc2ff02f	Pending	Credit Card	South America	Jason Nelson	2019-04-08	1	1	290.00062	27.9	2	290.00062
4de2c923-a05e-490c-9e96-3b4a7806ff17	Returned	Debit Card	Asia	Emily Matthews	2021-07-22	1	1	468.829872	13.78	4	468.829872
4dee63d2-6fd6-4d42-9d77-a4b84e347a40	Pending	Debit Card	Asia	Christina Thompson	2020-10-11	1	1	24.17068	18.48	1	24.17068
4df0274a-5a0d-438d-bde8-e837d3656c68	Returned	Credit Card	North America	Bradley Howe	2023-11-06	1	1	3310.181784	14.37	9	3310.181784
4df50aba-9564-460f-a1b8-ff882fbf5181	Cancelled	Amazon Pay	Australia	Sandra Luna	2022-01-08	1	1	698.848002	22.14	3	698.848002
4e00ad83-ad28-4757-85f3-129d3c9eea70	Returned	Credit Card	Asia	Michelle Andersen	2023-12-28	1	1	119.620392	17.08	2	119.620392
4e0da400-6a39-44df-af9d-7b7265f998d2	Pending	Gift Card	South America	Charles Smith	2019-02-28	1	1	369.4397799999999	27.35	2	369.4397799999999
4e23d00d-7d22-4637-8262-6682e71d88cc	Cancelled	Credit Card	Australia	Michelle Garza	2023-01-24	1	1	2583.998571	17.93	7	2583.998571
4e2d8ee9-f252-43e9-b433-baf9d50724dd	Pending	Gift Card	North America	Crystal Williams	2021-08-17	1	1	248.071212	14.47	6	248.071212
4e2d9d88-2171-4d06-b72f-7d5cf62f706f	Cancelled	Gift Card	Europe	Kristen Ramos	2022-10-24	1	1	129.24948999999998	20.3	1	129.24948999999998
4ea4a063-d041-431c-bd75-fc101874e730	Cancelled	PayPal	North America	Caitlyn Boyd	2021-08-21	1	1	70.469448	8.86	4	70.469448
4ead216c-dd71-4c0f-b727-962de4f86504	Cancelled	Credit Card	Australia	Diane Andrews	2024-04-19	1	1	710.43945	15.07	10	710.43945
4ee17122-89d8-4d0a-bc80-96d3f19b0b5f	Pending	Gift Card	Europe	Adam Smith	2022-10-12	1	1	2364.78247	13.59	10	2364.78247
4ef692b5-75aa-4ab7-bf30-878c429fd200	Returned	Debit Card	South America	Mary Scott	2024-12-10	1	1	648.8871999999999	10.56	10	648.8871999999999
4f0a2672-a954-42d9-94cd-f83875b5aeb7	Cancelled	Amazon Pay	South America	Caitlyn Boyd	2021-04-13	1	1	1646.749146	14.02	7	1646.749146
4f1ba263-760f-4f6e-8b94-f45cefd8f685	Pending	PayPal	South America	Mary Scott	2024-02-25	1	1	1806.95334	18.15	6	1806.95334
4f2e9fec-512c-46e7-bcce-21f39a5010f3	Cancelled	Amazon Pay	Australia	Mary Scott	2021-03-29	1	1	1188.040392	18.03	3	1188.040392
4f37d180-3299-4974-a403-3632def2e858	Returned	PayPal	South America	Steven Coleman	2021-11-21	1	1	1160.92575	16.25	6	1160.92575
4f572f36-802f-4ed6-b874-bc24d52b2559	Returned	PayPal	North America	Charles Smith	2020-01-19	1	1	2322.2848	29.6	10	2322.2848
4f69da6d-23dc-4727-808f-1cd89d441bdd	Returned	PayPal	Europe	Charles Smith	2019-12-02	1	1	1115.829456	2.23	7	1115.829456
4f7018ef-be74-4d15-a697-307182c2770a	Cancelled	Credit Card	Australia	Sandra Luna	2024-04-08	1	1	1363.541712	11.77	8	1363.541712
4f84a6f2-02eb-4df8-b534-5d04d10a6afd	Cancelled	Debit Card	Europe	Adam Smith	2021-02-17	1	1	221.6925	26.25	10	221.6925
4f876343-482f-419b-b5ad-a6e1681bfe84	Pending	Credit Card	Australia	Michelle Andersen	2019-03-13	1	1	1413.8851679999998	24.53	8	1413.8851679999998
4f8d6320-1104-45c4-822b-8c06fb69b070	Returned	Gift Card	Europe	Diane Andrews	2022-10-04	1	1	292.49514	3.4	3	292.49514
4f9846db-fd38-43e2-8485-4245c5340e6f	Returned	PayPal	North America	Mary Scott	2019-06-13	1	1	161.760426	8.78	3	161.760426
4faac007-9fba-41c0-b068-ec24eba6694a	Cancelled	Debit Card	North America	Roger Brown	2019-08-29	1	1	3592.7304300000005	6.31	10	3592.7304300000005
4fae3cb7-6b5c-4a7e-b0b2-14288d5647de	Returned	Amazon Pay	Australia	Joseph Brooks	2024-09-13	1	1	98.739954	28.62	1	98.739954
4fbca919-a7cf-4e96-a4b2-5a2ed737d1f1	Returned	Debit Card	Europe	Caitlyn Boyd	2019-10-17	1	1	218.83419000000004	9.61	3	218.83419000000004
4fc50240-cf0e-43cc-a7af-04e37975ce97	Returned	Gift Card	Europe	Emily Matthews	2024-10-17	1	1	1186.340472	12.31	9	1186.340472
4fdbbd54-24c6-486b-89bf-87090d3d70db	Cancelled	Amazon Pay	Europe	Johnny Marshall	2022-08-27	1	1	373.333062	6.86	1	373.333062
4fe34d59-6032-422a-a393-9672cc7c2032	Pending	Debit Card	South America	Susan Edwards	2024-07-03	1	1	329.460978	11.23	7	329.460978
4feaa4b7-5b98-4aa5-9e22-e69c8b0fa3c9	Returned	Amazon Pay	Australia	Diane Andrews	2023-08-28	1	1	638.340384	26.96	6	638.340384
5016aff3-21e7-4375-9d71-543ee4fae325	Pending	Gift Card	Australia	Steven Coleman	2021-01-18	1	1	1730.537676	11.03	6	1730.537676
50198ca1-6f43-4735-9c10-98525d60002f	Returned	Debit Card	Australia	Christina Thompson	2021-04-10	1	1	570.71262	8.12	5	570.71262
502f2f52-d285-4d82-9d53-1e15465ae10b	Returned	Amazon Pay	South America	Caitlyn Boyd	2021-10-15	1	1	1085.432832	28.62	8	1085.432832
5031b2a3-4f2d-44b2-993d-0a356e9b6e1c	Cancelled	PayPal	North America	Charles Smith	2021-01-09	1	1	199.48874400000005	22.39	2	199.48874400000005
50658bc8-1875-4d70-894c-5a27c797cbd2	Returned	Credit Card	Europe	Caleb Camacho	2022-07-12	1	1	422.825046	15.33	1	422.825046
506e6389-a74c-462a-8c54-265effcd9c66	Pending	Credit Card	Europe	Adam Smith	2019-11-15	1	1	138.290416	26.19	2	138.290416
506ef909-b114-46d6-83f1-01b00bc1b99a	Pending	PayPal	Asia	Michelle Andersen	2022-06-11	1	1	2684.7862720000003	1.19	7	2684.7862720000003
506f1b01-cdfc-4380-9df9-36559035c70e	Pending	PayPal	Asia	Susan Edwards	2019-07-25	1	1	515.724944	10.19	8	515.724944
508498e7-5f99-4008-975a-891fb510bdac	Returned	Gift Card	North America	Joseph Brooks	2021-07-21	1	1	1731.168054	10.57	6	1731.168054
5090372f-e5b8-4c14-b73d-cd12e2b1e886	Pending	Amazon Pay	Asia	Adam Smith	2020-07-13	1	1	553.0575959999999	27.82	7	553.0575959999999
50c21c9f-5d76-40f4-91f6-c26203899628	Pending	PayPal	South America	Emily Matthews	2024-11-01	1	1	352.993032	26.22	1	352.993032
50d094c3-ad5e-403b-a448-456b68769ff9	Pending	Gift Card	South America	Joseph Brooks	2021-03-27	1	1	541.915024	27.06	2	541.915024
50e62cdd-a0c4-4590-9f82-2c151bc6fdfb	Returned	Gift Card	North America	Bradley Howe	2024-02-17	1	1	2862.294624	22.51	8	2862.294624
50e65b1f-7338-4138-87d0-7a39d157345f	Pending	Debit Card	South America	Sandra Luna	2020-06-17	1	1	655.26954	22.49	5	655.26954
50f97fe0-28af-4830-ba88-e50d6fdcdba8	Returned	Credit Card	Australia	Charles Smith	2019-03-19	1	1	794.379948	15.61	2	794.379948
50fb49c9-1366-4c69-9cb8-c5b971128334	Returned	Amazon Pay	Europe	Susan Edwards	2021-02-19	1	1	686.3881200000001	25.86	6	686.3881200000001
5106d404-23c3-4f2f-8f9a-0aec5c887f72	Pending	PayPal	South America	Emily Matthews	2019-06-25	1	1	202.59724	8.6	1	202.59724
511f7230-f6b8-4a32-a5cf-ca46f908c37d	Pending	Debit Card	South America	Bradley Howe	2019-11-18	1	1	2616.49152	8.8	6	2616.49152
512b1077-f0b1-4465-9a3a-71cf6f655eb5	Returned	Debit Card	South America	Caleb Camacho	2021-10-12	1	1	79.673526	5.89	1	79.673526
514c4e1f-ef38-404b-9366-2956affabf63	Pending	PayPal	Europe	Caitlyn Boyd	2023-11-12	1	1	1460.78688	9.56	6	1460.78688
514dc893-3e0a-4983-865b-f966dc7568dd	Cancelled	Debit Card	Australia	Johnny Marshall	2024-06-18	1	1	216.33934	1.26	1	216.33934
517d060e-05fc-4f71-a1a6-880d063068e2	Returned	Amazon Pay	North America	Mary Scott	2020-05-10	1	1	893.285712	28.84	9	893.285712
51b27c8b-afe2-4360-b36d-635afae6c1ed	Cancelled	Debit Card	South America	Diane Andrews	2019-06-02	1	1	834.53901	9.05	6	834.53901
51b2fb64-37c2-4be4-9ff3-d729855cf067	Cancelled	Gift Card	Australia	Emily Matthews	2019-02-05	1	1	1028.5032159999998	27.98	8	1028.5032159999998
51b904be-e9e8-45de-a67b-3eb54a5c111c	Returned	Amazon Pay	Australia	Susan Edwards	2021-01-26	1	1	3049.6610720000003	14.37	8	3049.6610720000003
51c63d77-a662-4ee6-9abc-f15d92779cf5	Pending	Amazon Pay	Europe	Michelle Andersen	2024-08-14	1	1	1216.43844	23.48	5	1216.43844
51f0eb27-ba11-4cb2-a7e5-bb57fd0308c2	Pending	PayPal	Asia	Roger Brown	2024-10-17	1	1	1612.619008	20.64	7	1612.619008
5207a397-f446-488f-8744-85e516500ed1	Returned	Amazon Pay	North America	Kristen Ramos	2020-04-19	1	1	660.164985	28.15	3	660.164985
5215b9e8-a1b8-49a2-987a-d43d6ed333b7	Pending	Gift Card	Europe	Steven Coleman	2020-07-14	1	1	2633.6188799999995	0.06	10	2633.6188799999995
523cd808-48cb-4102-a7db-636d42de8bd3	Returned	Debit Card	North America	Adam Smith	2019-08-28	1	1	1498.613408	15.06	4	1498.613408
5240687d-2054-477e-9854-9c7ed8070f37	Cancelled	PayPal	Australia	Joseph Brooks	2021-04-08	1	1	1394.0225200000002	21.9	4	1394.0225200000002
52608352-fa6b-46b3-8a0b-fcb69da63474	Cancelled	PayPal	Australia	Mary Scott	2024-05-20	1	1	1605.22835	14.09	10	1605.22835
5267d25b-5132-4ccd-92a0-9b149886de77	Returned	PayPal	North America	Johnny Marshall	2024-09-26	1	1	1820.73234	22.38	6	1820.73234
526a2c42-0052-4098-988c-4ead85e08926	Cancelled	PayPal	South America	Steven Coleman	2023-07-03	1	1	559.7046760000001	19.46	2	559.7046760000001
526fd2c0-915f-48bd-a7f9-ef2904e7230a	Cancelled	Amazon Pay	North America	Crystal Williams	2021-08-05	1	1	106.058132	9.29	2	106.058132
5271751e-e514-43c2-b7cb-df2d8b087c26	Returned	Gift Card	Asia	Christina Thompson	2020-03-01	1	1	342.386121	5.29	1	342.386121
5275a82e-ec5e-4a0e-9371-57bcb59cd867	Returned	Debit Card	Asia	Christina Thompson	2024-01-04	1	1	1274.858232	15.56	6	1274.858232
52a0981d-21a5-4ec2-9c42-a9df613d7fbd	Cancelled	Gift Card	Europe	Diane Andrews	2019-05-24	1	1	2262.91464	18.45	9	2262.91464
52a0bb73-d5ba-4dad-aa9f-324c2bac45b2	Cancelled	Debit Card	South America	Steven Coleman	2022-01-27	1	1	3253.5444959999995	17.92	9	3253.5444959999995
52a40f87-a746-4995-ab80-6bc6c83c78dc	Cancelled	Gift Card	Australia	Bradley Howe	2023-12-25	1	1	1709.1201599999995	3.2	6	1709.1201599999995
52baafb0-d347-4a5b-a7d6-4cb70ae9e8e6	Cancelled	Credit Card	Europe	Caleb Camacho	2019-07-22	1	1	3474.3799890000005	7.89	9	3474.3799890000005
52c04e3c-ab93-4f6e-8314-c23eec0a36fa	Pending	Debit Card	North America	Joseph Brooks	2022-02-28	1	1	1700.27088	15.19	5	1700.27088
52ca2277-df0e-4e5d-b830-835bd116379a	Pending	Debit Card	Europe	Sandra Luna	2020-09-22	1	1	213.15030399999995	29.76	1	213.15030399999995
52dee88f-bca9-43aa-a4f0-7eb5520a9fee	Pending	PayPal	Australia	Diane Andrews	2021-11-12	1	1	1404.1793879999998	22.54	6	1404.1793879999998
52df305b-6847-47d4-83ef-c0e04a2532c7	Returned	Credit Card	Europe	Michelle Garza	2023-04-20	1	1	1229.7361440000002	13.04	7	1229.7361440000002
52e9762a-5f34-49b7-be38-826e05e67522	Pending	Gift Card	Australia	Joseph Brooks	2022-03-27	1	1	3262.60998	26.78	9	3262.60998
52ef35b9-3a2a-4d95-bd2b-3a6f2fff5589	Cancelled	Credit Card	Asia	Susan Edwards	2024-04-23	1	1	984.368718	6.86	3	984.368718
5319ce6b-8508-4529-9e95-7017768bf4ca	Returned	Debit Card	Asia	Charles Smith	2024-02-04	1	1	1362.20256	9.85	4	1362.20256
5336788a-ede1-4fed-837f-eaff41da811f	Cancelled	PayPal	South America	Caleb Camacho	2019-06-28	1	1	520.094498	12.62	7	520.094498
5339ced3-1988-4ed9-ac88-ac8cf1a8c307	Cancelled	Debit Card	Europe	Adam Smith	2024-06-22	1	1	1441.632792	13.14	4	1441.632792
533ff33a-abff-4ad5-8322-b1b26a39baa4	Pending	Amazon Pay	North America	Christina Thompson	2019-02-22	1	1	1513.78128	0.12	4	1513.78128
534599e9-bca0-4686-9d9a-8ceec33f2008	Pending	Debit Card	Europe	Michelle Andersen	2024-05-14	1	1	284.810085	13.45	1	284.810085
5345f625-62e8-4f1c-b835-e39cde37b551	Cancelled	Amazon Pay	South America	Susan Edwards	2022-10-29	1	1	833.423164	9.98	7	833.423164
5347cda2-fbc8-4afd-af59-3d2b146250c0	Pending	Debit Card	Australia	Christina Thompson	2019-01-22	1	1	805.763907	5.49	3	805.763907
535e7e42-44ad-4ccc-be69-94baa991443c	Pending	Gift Card	Europe	Caleb Camacho	2021-10-16	1	1	205.705008	16.57	8	205.705008
536b6dc6-2d7b-4272-b3fd-ad3b5f622550	Returned	Amazon Pay	South America	Adam Smith	2021-02-04	1	1	2073.98708	1.55	8	2073.98708
5372264b-8576-40ec-86b6-f1b1e93ed928	Pending	Amazon Pay	North America	Caleb Camacho	2024-01-31	1	1	1512.936144	29.98	9	1512.936144
5374e702-c5ce-4a3b-8f25-01f8e46fa9ac	Cancelled	PayPal	Europe	Susan Edwards	2019-03-14	1	1	131.248656	12.22	2	131.248656
537ad173-af7e-470b-b001-708378bc2aec	Cancelled	PayPal	Australia	Kristen Ramos	2020-06-09	1	1	729.26355	2.57	2	729.26355
537b458e-98be-4375-beb8-ae7a7b888ed7	Returned	Amazon Pay	Europe	Steven Coleman	2024-12-15	1	1	1039.37196	17.94	6	1039.37196
53805625-e9d5-494f-a651-c6d1377f79d2	Cancelled	PayPal	Asia	Caleb Camacho	2021-06-01	1	1	1434.041448	17.14	4	1434.041448
53a90a4c-3f32-44c2-b167-7a8b26b4aa17	Returned	PayPal	Asia	Crystal Williams	2021-06-25	1	1	292.44343200000003	22.83	1	292.44343200000003
53aee075-792d-43df-b1f4-bd95a1f63f44	Pending	PayPal	Australia	Jason Nelson	2022-03-20	1	1	2540.986987	9.47	7	2540.986987
53b5a138-7193-4f31-b99b-e3c46057da0f	Cancelled	Gift Card	Australia	Roger Brown	2020-01-06	1	1	169.294092	18.44	1	169.294092
53c76188-236f-40b5-add9-930e9d20da14	Pending	Amazon Pay	South America	Susan Edwards	2021-08-26	1	1	71.050035	23.97	1	71.050035
53e6b2b3-4b3d-4213-9e7b-12fa6f9c0bdb	Cancelled	Debit Card	Australia	Caitlyn Boyd	2020-02-07	1	1	264.7768	26.04	10	264.7768
541c2c4e-f797-49bc-a074-da1b89a61ca4	Cancelled	Amazon Pay	Asia	Caleb Camacho	2024-07-18	1	1	636.696	11.2	6	636.696
5421728d-2485-4ccf-b08c-7787a6e79044	Cancelled	Gift Card	South America	Susan Edwards	2023-03-28	1	1	944.336905	7.91	5	944.336905
5425c36d-8ba3-481a-aae6-15013353c0d7	Returned	PayPal	Europe	Emily Matthews	2019-06-24	1	1	1823.69502	28.45	7	1823.69502
54343fda-4d14-4c22-8fbd-ca2ce03e42a3	Returned	Amazon Pay	Australia	Crystal Williams	2022-01-17	1	1	1196.384112	23.77	4	1196.384112
5437cf61-2992-486a-a5ee-aacd00d7eac4	Pending	PayPal	Australia	Steven Coleman	2022-04-14	1	1	1390.826592	25.96	8	1390.826592
543c6b2f-3b5d-42d2-a4c2-1019e439f677	Pending	PayPal	Australia	Steven Coleman	2023-12-28	1	1	1603.315584	21.48	6	1603.315584
543d4494-13ed-439f-8635-0ac9160b63ea	Pending	Gift Card	Australia	Steven Coleman	2021-07-22	1	1	267.128862	28.11	6	267.128862
545b7c0c-1ad7-4cf3-a12a-15732754c337	Cancelled	PayPal	North America	Steven Coleman	2022-02-04	1	1	1611.599964	14.07	4	1611.599964
54604feb-3bf9-4e98-9b65-f4d355cee356	Cancelled	Gift Card	North America	Joseph Brooks	2020-12-17	1	1	378.650685	4.95	7	378.650685
546b38ca-b5e6-4caa-8252-17e19b48daf9	Pending	Gift Card	Asia	Michelle Garza	2023-03-28	1	1	222.19047	18.95	2	222.19047
5478e873-180e-4bda-bec1-243131263985	Pending	PayPal	South America	Jason Nelson	2020-03-18	1	1	324.290304	27.82	4	324.290304
5495ca28-da6b-45ed-94e7-022e681b3cf6	Cancelled	Credit Card	North America	Diane Andrews	2021-06-10	1	1	288.78878000000003	5.64	1	288.78878000000003
549faf2c-2fe5-45fd-b92a-d8d8c9f7f0c5	Pending	Credit Card	North America	Michelle Garza	2019-11-21	1	1	2753.905	28.47	8	2753.905
54b9e985-3059-4ada-b723-8dd0d141c968	Pending	Debit Card	Europe	Mary Scott	2021-01-26	1	1	385.752317	16.31	1	385.752317
54d9116b-1531-49a8-ac4e-415b2a431d04	Pending	Credit Card	Australia	Steven Coleman	2019-10-09	1	1	165.498627	20.13	1	165.498627
551d887b-f273-4d4b-8fe5-1d3fe5b886f5	Returned	PayPal	Europe	Sandra Luna	2022-05-23	1	1	659.9530649999999	18.79	5	659.9530649999999
553074c1-5ec6-415a-9010-e22b287cd80d	Returned	Amazon Pay	Australia	Mary Scott	2020-08-11	1	1	667.3755	26.46	5	667.3755
5554fe51-e5ec-4db9-b44b-b0387ea260b2	Pending	Credit Card	North America	Mary Scott	2022-07-18	1	1	29.572924	13.58	2	29.572924
55585ccc-a45c-4a33-8a67-fd66ca6acc09	Returned	Gift Card	South America	Joseph Brooks	2021-12-02	1	1	234.95792	9.44	1	234.95792
55689ca6-e6d7-47b1-8634-31e8898c47d8	Pending	Amazon Pay	Australia	Michelle Andersen	2020-02-25	1	1	78.25545	12.25	7	78.25545
55758120-c770-4ae1-836f-c203457bd03c	Returned	PayPal	Australia	Joseph Brooks	2019-05-25	1	1	763.905396	3.21	4	763.905396
55790977-587f-4c5a-a0ac-861ab041a7b6	Pending	Credit Card	North America	Michelle Andersen	2019-05-15	1	1	927.960088	1.88	2	927.960088
558ef4a7-3b92-4a2f-89d1-fd66a30bc929	Returned	Debit Card	Europe	Diane Andrews	2024-09-23	1	1	2995.233552	11.62	8	2995.233552
559f8de5-c0e8-4332-8458-038cdfc85327	Pending	Credit Card	South America	Diane Andrews	2024-11-16	1	1	709.274954	18.99	2	709.274954
55abbdcf-46ed-40fc-834c-09a5ba0879d6	Returned	Amazon Pay	Europe	Adam Smith	2020-01-22	1	1	765.122652	20.17	7	765.122652
55b67db3-1cda-4efe-a583-eea806e94acb	Pending	Amazon Pay	Asia	Michelle Andersen	2020-06-25	1	1	690.741888	8.69	4	690.741888
55d7605c-eda1-4095-b07d-798be4368934	Returned	Gift Card	South America	Mary Scott	2019-12-02	1	1	1212.853908	5.66	7	1212.853908
55e32fda-135c-47dd-ae89-e765f34950f7	Pending	Gift Card	Asia	Roger Brown	2020-02-03	1	1	2798.78736	21.65	8	2798.78736
55e5e687-345f-4d55-9284-f79953b389aa	Pending	Credit Card	North America	Kristen Ramos	2020-04-18	1	1	340.7705	14.25	2	340.7705
55f4fd57-734c-4cc0-938f-1933a92cfbea	Returned	PayPal	Asia	Roger Brown	2024-05-12	1	1	144.566311	28.23	1	144.566311
56050027-95c7-4aa0-944b-8f9a65ce4d88	Returned	Gift Card	Europe	Johnny Marshall	2020-07-05	1	1	2045.95611	16.29	6	2045.95611
560c0a20-8851-45a8-8422-e14eac211327	Returned	Credit Card	Australia	Sandra Luna	2021-01-19	1	1	787.272928	13.68	4	787.272928
561b327e-4e06-4730-879c-cf1a56883b2a	Cancelled	PayPal	South America	Susan Edwards	2020-12-29	1	1	2513.30366	15.26	7	2513.30366
563e2e2e-5336-46cd-a54a-d47f31c01441	Pending	Gift Card	Asia	Adam Smith	2019-10-17	1	1	298.612512	8.04	3	298.612512
5661790a-62a5-4ed4-83f2-9fe37fe52afb	Returned	Gift Card	South America	Susan Edwards	2021-09-09	1	1	1225.889016	28.83	8	1225.889016
5669680a-7869-4fb2-87af-72b5d4067a64	Pending	PayPal	Europe	Emily Matthews	2024-11-10	1	1	3296.722455	26.55	9	3296.722455
56743d55-415f-4d0b-a6aa-9c5cc62a841e	Pending	Gift Card	Australia	Michelle Andersen	2022-08-18	1	1	382.1568	0.48	4	382.1568
56920a55-9358-4b14-a198-c3899c68dd25	Cancelled	Debit Card	South America	Sandra Luna	2020-04-06	1	1	2186.90946	0.28	5	2186.90946
56ac0c8b-7c49-41cf-a4f4-2eec573727cf	Returned	Amazon Pay	Asia	Christina Thompson	2021-11-25	1	1	473.80713	29.85	3	473.80713
56c8a899-1916-4957-ac9c-64a1cebb1823	Returned	Gift Card	Asia	Bradley Howe	2021-12-05	1	1	302.639298	12.58	1	302.639298
56d47743-292a-49ab-8da7-1818dd01fbad	Returned	Gift Card	Europe	Diane Andrews	2021-05-19	1	1	166.185281	8.19	1	166.185281
56dd67d8-21e9-4d4e-a473-0ef9c25294d0	Returned	Credit Card	Europe	Kristen Ramos	2019-10-10	1	1	1455.0668159999998	10.03	4	1455.0668159999998
56e24e17-1708-4da7-8daf-9acb410a09bc	Cancelled	PayPal	Europe	Christina Thompson	2024-11-16	1	1	1327.447737	17.89	9	1327.447737
56e3a427-5419-4be6-9159-74f6b359ed1d	Cancelled	Gift Card	Europe	Caitlyn Boyd	2023-12-09	1	1	142.59466400000002	23.64	2	142.59466400000002
56eb26f4-42cc-42e5-83dc-e962a51c823f	Returned	Debit Card	South America	Caleb Camacho	2022-01-06	1	1	528.1248	24.12	8	528.1248
56f03ae1-05ce-464d-aa59-a5b4bbe15d1b	Returned	PayPal	North America	Steven Coleman	2024-03-05	1	1	607.854716	26.93	2	607.854716
56f408f5-6606-45d8-b5df-2f009aaf04cf	Cancelled	Debit Card	North America	Caitlyn Boyd	2024-05-27	1	1	913.80972	18.22	4	913.80972
570d9a94-569a-46b1-8497-7fa06e44ea83	Cancelled	Amazon Pay	South America	Bradley Howe	2021-10-22	1	1	904.551528	5.02	2	904.551528
571acd1d-d25b-4f81-9b3f-b4b6bfc342a9	Pending	Debit Card	South America	Mary Scott	2020-05-24	1	1	556.54854	28.35	6	556.54854
5723d765-edc5-4284-89e6-ad7e59d61942	Returned	Gift Card	Europe	Joseph Brooks	2020-11-20	1	1	65.70400000000001	17.87	4	65.70400000000001
5755de04-391c-45ec-8082-5174a9549e1f	Returned	Debit Card	South America	Caitlyn Boyd	2021-03-02	1	1	1145.418624	18.64	6	1145.418624
57720014-bf55-4ea1-a65e-063dffb7e01f	Cancelled	Credit Card	Australia	Susan Edwards	2024-12-28	1	1	987.776013	15.81	3	987.776013
5775ec48-7e8e-428c-a893-a12e954d7675	Pending	Gift Card	South America	Kristen Ramos	2020-03-22	1	1	490.26878	6.33	4	490.26878
579df428-bcd3-474e-a781-2ab24c35e1c9	Cancelled	Amazon Pay	Asia	Michelle Garza	2023-11-08	1	1	494.070915	12.45	3	494.070915
57b8532f-699c-4e94-86ee-95f2ff8416fa	Returned	Gift Card	South America	Johnny Marshall	2022-12-09	1	1	305.65304	14.45	4	305.65304
57d39ce9-ea00-4e32-b9af-4c1bb5172112	Returned	Gift Card	North America	Michelle Andersen	2022-11-14	1	1	1272.9889919999998	1.19	4	1272.9889919999998
5817d16c-a199-4b85-abeb-6737e88b851d	Pending	Amazon Pay	Europe	Johnny Marshall	2020-12-08	1	1	2939.66892	12.3	9	2939.66892
5821a7af-721a-435c-aee0-ed9d8c5064a1	Pending	Gift Card	Australia	Diane Andrews	2021-10-24	1	1	193.86224	23.04	10	193.86224
582e053b-e095-4126-bcf5-a50074326bc8	Pending	Amazon Pay	Asia	Jason Nelson	2023-07-28	1	1	991.088406	25.03	6	991.088406
583d65c7-363e-4279-8124-cc96b9a07252	Pending	Amazon Pay	Europe	Emily Matthews	2022-06-29	1	1	1605.793088	14.52	4	1605.793088
583f42da-ae9e-474f-b220-3efc7c023a64	Pending	Amazon Pay	Europe	Steven Coleman	2019-03-17	1	1	274.526592	25.14	8	274.526592
58559306-38c7-4eec-8064-be436fdec7bd	Cancelled	Credit Card	South America	Johnny Marshall	2023-01-18	1	1	332.425786	23.33	2	332.425786
586bb36f-4b6d-48ce-812b-860a78499eea	Returned	Amazon Pay	South America	Caleb Camacho	2020-09-18	1	1	503.25611	14.3	7	503.25611
5885c2a3-5e9a-4d27-96f6-ba89396a5952	Pending	Debit Card	Asia	Michelle Andersen	2022-04-26	1	1	1983.7755	20.17	5	1983.7755
5887ad05-0bde-462a-8ea6-7d7e72038dea	Cancelled	Credit Card	Europe	Susan Edwards	2022-03-07	1	1	486.76395600000006	7.06	3	486.76395600000006
588c14af-1e0c-4c94-a2ba-8bfbdef76812	Cancelled	Credit Card	Asia	Emily Matthews	2022-01-13	1	1	109.67268	20.18	6	109.67268
58963fb4-7e94-4ef4-ba64-6eca9ae2d383	Returned	PayPal	South America	Joseph Brooks	2023-01-17	1	1	652.03944	18.84	10	652.03944
58a41f75-d44a-4ab1-b1b9-5bccfcb3a5f5	Pending	PayPal	Australia	Emily Matthews	2020-06-25	1	1	1544.8130500000002	15.45	5	1544.8130500000002
58abe6de-d34a-45e6-9316-54d93f49cb73	Returned	Amazon Pay	Europe	Steven Coleman	2021-12-03	1	1	1157.28575	12.74	5	1157.28575
58ac037b-de63-4a7b-a5fa-eb7c54f92f73	Cancelled	Credit Card	South America	Roger Brown	2022-08-21	1	1	51.099972	10.68	3	51.099972
58b67352-947b-4ba7-b2c8-f513f5f58328	Returned	Debit Card	North America	Roger Brown	2022-07-06	1	1	702.135051	4.91	3	702.135051
58b70dc6-72ac-4268-9802-403fa0cd6532	Cancelled	Gift Card	Asia	Kristen Ramos	2023-10-20	1	1	372.64859	10.01	2	372.64859
58b856da-3222-4706-ab86-647827b743d1	Returned	Credit Card	Australia	Kristen Ramos	2022-03-30	1	1	255.917281	17.31	1	255.917281
58beaa69-1822-48a3-9e31-9031589f0ca6	Pending	Amazon Pay	Europe	Roger Brown	2022-12-12	1	1	1874.42502	16.67	10	1874.42502
58d749aa-e427-42ef-9ca3-6429742d7393	Pending	Gift Card	Asia	Bradley Howe	2023-06-28	1	1	95.258044	24.23	7	95.258044
58d9b566-e0e8-4e07-acf3-ed4e1c0b508a	Cancelled	Gift Card	Asia	Sandra Luna	2024-08-22	1	1	1756.3904	8	8	1756.3904
58dc1023-c378-4291-8b38-de9aeffd6824	Pending	Credit Card	Australia	Emily Matthews	2024-10-16	1	1	1141.00336	8.55	8	1141.00336
58ee3257-062f-451e-b5fb-33cd182098a5	Pending	Debit Card	Europe	Jason Nelson	2019-09-26	1	1	486.04864	1.37	5	486.04864
58ef6a60-c291-4ad8-9b09-a861c412a6cf	Cancelled	Amazon Pay	Europe	Johnny Marshall	2021-03-06	1	1	385.535095	3.95	1	385.535095
5931db4a-9ba4-4bbf-956e-0a42058fca60	Returned	Debit Card	South America	Charles Smith	2019-04-21	1	1	1033.82217	16.9	9	1033.82217
593e641f-5b40-4b32-97b3-e0400aebf8a2	Cancelled	Gift Card	Australia	Adam Smith	2019-07-24	1	1	2670.02394	8.82	10	2670.02394
593facfb-cc5a-452b-aee6-cc7ac581933a	Pending	Debit Card	North America	Diane Andrews	2021-01-01	1	1	320.36751000000004	25.27	6	320.36751000000004
5947a531-ac73-4e45-a38b-f7b83de6f960	Pending	Debit Card	Asia	Christina Thompson	2019-06-04	1	1	1084.423926	0.59	3	1084.423926
596f92f1-916b-4277-877f-f02037499379	Returned	Credit Card	Australia	Susan Edwards	2021-04-01	1	1	41.19718199999999	8.41	2	41.19718199999999
5971238c-54c3-4f2d-9da2-7bfe38f1bf83	Cancelled	Credit Card	South America	Susan Edwards	2022-01-31	1	1	2945.226825	16.75	9	2945.226825
59806a27-ab9c-4c14-839f-6caee2c78b3a	Cancelled	Gift Card	North America	Crystal Williams	2024-09-30	1	1	1096.6728750000002	18.99	3	1096.6728750000002
599539c1-e2c4-4b6f-92c7-0db8a618a5cb	Cancelled	Debit Card	South America	Sandra Luna	2021-08-28	1	1	1487.563364	27.32	7	1487.563364
59c2ca78-5f71-4e9a-a9ae-799ae918cd14	Cancelled	Amazon Pay	North America	Michelle Andersen	2019-03-07	1	1	1116.87457	12.65	7	1116.87457
59ce3af6-096c-4b00-b33f-8b22c6b99f49	Cancelled	Credit Card	North America	Crystal Williams	2021-01-02	1	1	341.859276	23.94	3	341.859276
59d2420b-babe-4555-bd54-2f92446149d6	Pending	PayPal	North America	Joseph Brooks	2024-08-01	1	1	757.43127	17.15	6	757.43127
59d44a3e-bea6-49df-9699-bc6a9a776725	Returned	Debit Card	Asia	Sandra Luna	2019-12-17	1	1	304.967862	6.42	3	304.967862
5a04f046-7c4f-401d-b551-e7cb28800afd	Pending	Amazon Pay	Asia	Sandra Luna	2022-03-11	1	1	188.921088	21.44	2	188.921088
5a1684c5-20b8-4369-94d9-cf718365e28b	Returned	Gift Card	Asia	Caleb Camacho	2020-07-20	1	1	1507.97958	26.79	10	1507.97958
5a2734f8-5453-484a-8505-993bbf7eb60e	Returned	Credit Card	Europe	Joseph Brooks	2020-04-12	1	1	1303.042244	0.71	7	1303.042244
5a2ab734-1980-4eba-8d10-e259f9f1211f	Pending	Amazon Pay	Europe	Steven Coleman	2022-07-11	1	1	3033.802512	19.14	9	3033.802512
5a481858-09bb-4c85-968b-349bdbd0d107	Pending	Debit Card	North America	Christina Thompson	2021-09-02	1	1	2626.967632	20.42	8	2626.967632
5a4fa575-add2-4083-8953-c96401cdb27b	Cancelled	Amazon Pay	North America	Michelle Garza	2023-04-15	1	1	1886.14956	16.24	5	1886.14956
5a61e4fd-6ed1-4a2c-be6c-a72d7754b6b9	Pending	PayPal	North America	Charles Smith	2019-02-08	1	1	2614.135258	19.83	7	2614.135258
5a8087ee-68e4-464f-8852-c7bfeabd1e85	Cancelled	Credit Card	Australia	Michelle Andersen	2024-09-17	1	1	606.5454779999999	3.53	7	606.5454779999999
5aa4410e-7752-40ec-82df-b024065a47ab	Returned	Credit Card	South America	Adam Smith	2024-01-14	1	1	845.349568	4.94	4	845.349568
5aa4f162-d1ea-4c29-91ab-90ca002de31a	Cancelled	PayPal	South America	Caitlyn Boyd	2020-05-02	1	1	1900.18768	18.18	10	1900.18768
5aa55c50-f53c-4604-b733-b4a61c907841	Pending	Debit Card	Australia	Mary Scott	2022-07-27	1	1	1653.571542	18.17	6	1653.571542
5af08d10-9328-4353-b44e-6eb113c8b27a	Returned	Credit Card	North America	Adam Smith	2021-11-25	1	1	2817.15063	14.1	7	2817.15063
5aff68d8-b522-41fb-bb0d-609513fd0566	Cancelled	PayPal	South America	Caleb Camacho	2021-02-10	1	1	2556.63646	21.59	7	2556.63646
5b04cba0-b687-4561-bbcf-ef775aaf3272	Returned	Credit Card	Asia	Mary Scott	2023-06-10	1	1	1334.62315	1.34	5	1334.62315
5b07f28a-c0fa-46c5-9e68-687c904fa412	Returned	Credit Card	South America	Joseph Brooks	2021-04-29	1	1	89.11583999999999	3.97	5	89.11583999999999
5b14efa9-cebf-4c77-9326-633b8771a613	Cancelled	Amazon Pay	Asia	Michelle Andersen	2019-05-29	1	1	1821.850548	16.06	7	1821.850548
5b170d2f-6f2f-439a-b77f-667adf8ee332	Pending	Debit Card	South America	Michelle Garza	2020-12-26	1	1	1753.870698	24.59	6	1753.870698
5b2df8f2-3e35-4365-88ae-4852a9f079fe	Pending	Debit Card	Europe	Sandra Luna	2023-12-24	1	1	576.947609	12.29	7	576.947609
5b35a3d5-4f82-4cb3-a213-02a692d26265	Cancelled	Amazon Pay	Asia	Jason Nelson	2021-09-01	1	1	605.8880239999999	29.96	2	605.8880239999999
5b42d46a-ad10-45e9-beed-e99db84939df	Pending	Debit Card	Europe	Adam Smith	2019-04-04	1	1	524.88724	26.9	4	524.88724
5b4a44ac-6214-426a-8d02-462b03931a63	Cancelled	Gift Card	Australia	Jason Nelson	2022-11-12	1	1	434.054376	9.82	2	434.054376
5b52a69c-20f2-40e8-af43-f60cf771c4e6	Pending	Debit Card	South America	Charles Smith	2023-02-22	1	1	450.10770600000006	18.29	3	450.10770600000006
5b5da5f5-bc24-40c8-b135-24297b34d77d	Pending	Debit Card	South America	Mary Scott	2020-09-10	1	1	242.657088	26.84	4	242.657088
5b6fc8a1-996c-4304-acb5-9077180a7b60	Cancelled	Amazon Pay	North America	Michelle Andersen	2024-01-24	1	1	832.3359300000002	11.74	3	832.3359300000002
5b862fee-8c72-400d-9cb8-402f9e1ff23c	Pending	Amazon Pay	Asia	Steven Coleman	2022-05-06	1	1	2238.895392	15.47	6	2238.895392
5b9d640a-6740-4814-9a8e-4fbc4338f0ed	Cancelled	Debit Card	South America	Kristen Ramos	2023-04-01	1	1	132.76449000000002	27.7	3	132.76449000000002
5bab861f-fef2-4a32-b307-49c943374592	Cancelled	PayPal	South America	Joseph Brooks	2022-02-27	1	1	664.627	28.4	5	664.627
5bb962f2-358b-42fd-adfb-77a9a3812157	Returned	Gift Card	Asia	Crystal Williams	2024-09-27	1	1	143.55451000000002	26.06	1	143.55451000000002
5bca676f-0d1f-499d-9eee-f0fb95bc3b01	Returned	PayPal	North America	Adam Smith	2022-07-08	1	1	774.852957	29.39	3	774.852957
5bcaac79-89b3-4605-a91f-eca55ce1e01a	Cancelled	Credit Card	Europe	Michelle Garza	2021-12-31	1	1	2904.5224739999994	11.06	7	2904.5224739999994
5be5f736-2288-4fd3-93ff-ab44132ceaaf	Cancelled	Credit Card	Australia	Caitlyn Boyd	2024-08-06	1	1	356.05386	11.35	4	356.05386
5bf37bc7-4c55-470a-87d1-6597ac0747e8	Returned	Debit Card	North America	Mary Scott	2024-05-29	1	1	782.0021879999999	11.71	3	782.0021879999999
5bf7585e-6143-4edb-9703-f389c5822d6f	Pending	Debit Card	North America	Johnny Marshall	2021-08-12	1	1	2420.46684	3.64	6	2420.46684
5bfa4bb8-d085-41df-81cd-e88b8bdfa71f	Cancelled	PayPal	Europe	Jason Nelson	2021-01-19	1	1	2034.531324	24.94	7	2034.531324
5c2146d9-1836-4d20-b9d9-b762c831dfca	Returned	Amazon Pay	South America	Michelle Andersen	2021-09-06	1	1	2742.16	9.2	10	2742.16
5c54528a-d425-4ea4-aafb-0e2bb869a269	Returned	Debit Card	Asia	Caitlyn Boyd	2021-12-13	1	1	283.204044	11.46	2	283.204044
5cea0985-a266-4563-aab1-fb2674e0c797	Cancelled	Amazon Pay	Europe	Roger Brown	2024-01-27	1	1	2228.71072	25.04	8	2228.71072
5cf7feff-bb36-4ab0-8ab9-a3940d77ce61	Cancelled	Credit Card	Australia	Kristen Ramos	2023-11-30	1	1	108.98568000000002	8.4	9	108.98568000000002
5d03a46c-b7cc-414f-ba06-a95de0c9bb31	Cancelled	Gift Card	North America	Roger Brown	2023-02-18	1	1	668.98258	7.95	4	668.98258
5d07cb90-8a9a-449f-a860-a7e68f1425b4	Cancelled	Amazon Pay	Australia	Steven Coleman	2024-12-12	1	1	346.053981	6.53	7	346.053981
5d1bb74a-f6e4-4ef1-84a5-b9be974cb095	Returned	Credit Card	Europe	Mary Scott	2021-03-09	1	1	1548.569205	8.29	5	1548.569205
5d2e87ec-4629-48f1-83ed-773839a5458b	Pending	Credit Card	South America	Sandra Luna	2020-12-18	1	1	2473.26336	16.96	6	2473.26336
5d42e59f-7f75-4eea-b267-658fe293a2dc	Cancelled	PayPal	Asia	Steven Coleman	2020-11-18	1	1	119.51335	14.45	2	119.51335
5d61ddec-6def-4c17-8594-18a32d114801	Cancelled	Credit Card	North America	Johnny Marshall	2019-11-21	1	1	1080.178368	4.48	4	1080.178368
5d63cd44-1f29-46e2-a043-fd89cc77503d	Cancelled	Amazon Pay	Europe	Emily Matthews	2023-09-28	1	1	160.72576	3.41	4	160.72576
5d94791a-8bab-439a-bf7d-c1ae0b9a8ca2	Cancelled	Debit Card	Australia	Sandra Luna	2022-03-06	1	1	1111.560132	18.42	3	1111.560132
5dade831-7891-444b-a832-ca5df75914e2	Cancelled	PayPal	Asia	Emily Matthews	2023-06-19	1	1	1600.8808800000002	12.73	4	1600.8808800000002
5dd3d035-b25f-4f50-9581-74178caaa15c	Cancelled	Amazon Pay	Asia	Sandra Luna	2022-02-20	1	1	400.856742	28.63	2	400.856742
5defc7cc-a046-4b3f-9171-2a8233ec72bf	Returned	Debit Card	South America	Roger Brown	2020-02-25	1	1	445.788984	0.83	6	445.788984
5df3ff98-2880-4812-8639-69b5c7a3b804	Returned	Gift Card	South America	Charles Smith	2023-02-08	1	1	312.994803	4.63	1	312.994803
5e14a223-44e2-43af-b28d-8aa3d1d181df	Cancelled	Amazon Pay	Europe	Mary Scott	2021-02-18	1	1	3030.142752	7.04	7	3030.142752
5e2124ae-16a7-4604-a7fc-df8c1769ad66	Cancelled	PayPal	Europe	Roger Brown	2020-09-15	1	1	377.028515	16.89	5	377.028515
5e2656e8-4a5f-4c79-8b42-96402f37e063	Pending	Credit Card	Europe	Crystal Williams	2024-03-19	1	1	274.787865	18.55	1	274.787865
5e544300-2bd6-404c-aa30-78be68ab2a8d	Cancelled	Amazon Pay	South America	Joseph Brooks	2024-08-31	1	1	1034.727129	25.21	3	1034.727129
5e70fa8e-47e0-4076-99de-504f83827e49	Pending	Amazon Pay	Europe	Mary Scott	2022-06-26	1	1	1685.03661	28.73	6	1685.03661
5e8b144b-d313-4b22-8d56-6cb6fc283c1e	Returned	Amazon Pay	South America	Christina Thompson	2023-01-02	1	1	2567.616732	6.04	9	2567.616732
5e96551e-2656-4f64-9232-24ee86e2645d	Cancelled	Amazon Pay	Asia	Michelle Garza	2020-02-25	1	1	1294.2910499999998	4.25	6	1294.2910499999998
5e9aed2a-a0f7-4897-9124-42c8ee31cb03	Returned	PayPal	Europe	Crystal Williams	2019-09-09	1	1	598.0471279999999	11.24	2	598.0471279999999
5ea197e7-1a9f-45ee-812a-bee611803edf	Cancelled	PayPal	Asia	Michelle Garza	2024-08-02	1	1	202.842684	25.42	3	202.842684
5ec62f2d-2147-4fac-814f-7caa5247e3c3	Returned	Amazon Pay	North America	Johnny Marshall	2024-08-03	1	1	260.92948	28.7	2	260.92948
5ece7c1f-46d3-411e-9d4f-90aff2d5570c	Pending	Credit Card	Australia	Joseph Brooks	2019-02-26	1	1	454.90028	12.62	4	454.90028
5edabc3e-ed74-484e-bf37-874ed8974803	Returned	Debit Card	South America	Kristen Ramos	2024-08-11	1	1	1764.8049	28.42	5	1764.8049
5efdc491-01c7-4c85-8da4-27399b54934a	Returned	Credit Card	Europe	Susan Edwards	2020-06-20	1	1	558.84	25	4	558.84
5f281feb-4dbb-4fd0-adeb-a7c67b20467c	Cancelled	Gift Card	South America	Susan Edwards	2021-06-20	1	1	533.4096400000001	3.56	5	533.4096400000001
5f39066b-e0e7-49cc-a004-6346429cc609	Pending	Credit Card	South America	Joseph Brooks	2022-02-19	1	1	214.49386	8.12	5	214.49386
5f4593a2-5202-492b-a907-740d7dff34d3	Pending	Gift Card	Europe	Jason Nelson	2024-07-16	1	1	449.34015	17.05	10	449.34015
5f4fe95b-56c6-4138-90cf-f867b8665e70	Cancelled	Debit Card	North America	Mary Scott	2024-07-22	1	1	1306.9666679999998	10.87	4	1306.9666679999998
5f5503b5-9691-4b88-9306-eed7e5498f29	Cancelled	PayPal	Europe	Bradley Howe	2021-09-29	1	1	218.73173	7.14	7	218.73173
5f61538c-cb1c-46ea-9b17-4bac64c1f56d	Pending	Amazon Pay	South America	Caitlyn Boyd	2023-10-24	1	1	2611.162044	5.79	6	2611.162044
5f66a2af-2684-4853-af37-082997977622	Cancelled	Credit Card	Australia	Caitlyn Boyd	2021-11-28	1	1	3530.469888	6.28	8	3530.469888
5f682704-8f0d-47e1-b567-73ecafafb83f	Pending	Amazon Pay	Australia	Charles Smith	2019-09-25	1	1	386.851641	9.43	1	386.851641
5f6a20a7-455f-4df1-809c-9df36a21c4c8	Cancelled	PayPal	Australia	Mary Scott	2021-04-25	1	1	104.985215	27.87	5	104.985215
5f7f90b5-8eca-4317-b086-d1504f38ee2c	Pending	Credit Card	Europe	Susan Edwards	2021-07-02	1	1	955.6469519999998	12.86	3	955.6469519999998
5f8f5912-c358-4420-8fbe-f043f6855932	Pending	Debit Card	Europe	Roger Brown	2023-04-28	1	1	755.397648	15.82	4	755.397648
5f9107c5-12c0-4eb2-8d3c-a19b41b8076a	Pending	PayPal	Asia	Caitlyn Boyd	2024-04-29	1	1	1612.9139879999998	6.54	6	1612.9139879999998
5fc0bd96-e2fd-4bd9-9406-abdb141d4e0f	Pending	PayPal	Asia	Bradley Howe	2021-09-02	1	1	1344.954576	27.79	4	1344.954576
5fc2c8dd-9c65-4a6f-a5b3-f88261d6eee6	Pending	Amazon Pay	Australia	Michelle Andersen	2020-02-23	1	1	37.39002	12.23	1	37.39002
5fc447e3-87da-4959-85d3-0cb24f1db40f	Pending	Gift Card	Europe	Caitlyn Boyd	2022-09-11	1	1	797.7569320000001	22.37	4	797.7569320000001
5fdb867c-5041-4050-9629-860248c9ff14	Returned	Gift Card	Asia	Kristen Ramos	2021-04-09	1	1	1431.566592	23.71	8	1431.566592
5fdc8308-af99-4815-b92e-f5f6e6f53208	Cancelled	Debit Card	South America	Diane Andrews	2023-08-03	1	1	1069.64433	19.63	5	1069.64433
5fdd7429-6cde-469f-88e7-a22f1e62c0f7	Cancelled	Gift Card	Australia	Steven Coleman	2024-11-17	1	1	408.11390000000006	26.73	10	408.11390000000006
5fefe92f-dcfb-4a27-876d-58678dd27bff	Returned	Gift Card	South America	Adam Smith	2019-05-25	1	1	1050.44368	11.34	5	1050.44368
60031276-9808-4586-89e7-2ed4ad111063	Returned	Gift Card	Australia	Susan Edwards	2024-03-13	1	1	789.565644	28.22	3	789.565644
601c7679-1208-4625-bcd6-25cc29ad5e9f	Pending	Credit Card	South America	Roger Brown	2024-07-10	1	1	631.6252020000001	2.26	3	631.6252020000001
60526f61-cfd6-407e-9a8b-fe5a932d00ce	Cancelled	Credit Card	South America	Crystal Williams	2021-10-14	1	1	768.20418	11.18	10	768.20418
60531a33-43fd-4b72-a72f-22f8620eff24	Pending	Credit Card	North America	Emily Matthews	2023-09-27	1	1	221.3341	11	1	221.3341
6053d60b-3af6-42d1-881a-8f6df4ef73d1	Cancelled	PayPal	South America	Emily Matthews	2021-09-19	1	1	1200.03678	2.44	5	1200.03678
6092590e-64d7-4a89-b32c-8fd42d1bf535	Cancelled	Amazon Pay	Europe	Crystal Williams	2020-03-12	1	1	1558.43142	27.74	10	1558.43142
6093a5d3-a006-46ee-a21c-bf10d4a15f9b	Pending	Amazon Pay	North America	Michelle Andersen	2020-06-01	1	1	797.64034	13.13	2	797.64034
6095ed35-abcc-4c66-b202-204ec7b72a89	Pending	Gift Card	North America	Emily Matthews	2020-11-14	1	1	759.6995999999999	11.56	2	759.6995999999999
60b204e4-8193-4e16-ba53-70e37ece5bd2	Returned	Amazon Pay	Europe	Michelle Garza	2023-12-27	1	1	351.78537800000004	4.13	7	351.78537800000004
60c9317e-9cff-474a-9051-f44658d40fd1	Returned	Gift Card	Asia	Michelle Garza	2021-11-12	1	1	25.23477	18.65	3	25.23477
60c9ec65-c16f-42b7-b712-ba8ae0ea9aa6	Cancelled	Debit Card	Australia	Johnny Marshall	2021-09-14	1	1	2852.6589000000004	20.06	9	2852.6589000000004
60cb4f5f-87ea-4e8e-97cf-32cd7e710f69	Pending	PayPal	Australia	Mary Scott	2020-02-03	1	1	971.20863	16.85	3	971.20863
60db5c75-36ca-44c2-8ba3-07c1fe767ddd	Pending	Amazon Pay	South America	Steven Coleman	2020-11-18	1	1	1256.184369	0.01	9	1256.184369
60f413cd-bc9b-4ea7-b3b4-d38bd533fec7	Pending	PayPal	Europe	Diane Andrews	2020-08-17	1	1	1153.145784	21.42	3	1153.145784
60fc144f-f2ad-4cd0-95b7-bfafd1084b5f	Cancelled	Gift Card	Europe	Steven Coleman	2023-05-04	1	1	25.543035	7.15	1	25.543035
61054d14-c1d6-4e39-882c-034cbebdfd7e	Cancelled	Gift Card	Asia	Susan Edwards	2021-05-30	1	1	2705.37816	27.22	8	2705.37816
610e8090-a80a-44e9-99b2-9c58dc4a34fd	Cancelled	PayPal	North America	Mary Scott	2022-03-07	1	1	266.705228	3.72	1	266.705228
6111b727-c0fd-48df-beb0-8b97e77dbbfc	Returned	PayPal	Europe	Adam Smith	2020-06-25	1	1	2077.765704	4.46	9	2077.765704
61131d64-6baf-49d5-b26d-46e18ee69ac5	Returned	Debit Card	North America	Caitlyn Boyd	2023-12-20	1	1	108.05001	28.42	1	108.05001
613609bf-2238-4d35-a7eb-510fbe447ba7	Returned	PayPal	Asia	Caitlyn Boyd	2022-01-19	1	1	1285.222968	3.91	3	1285.222968
61362fd7-e0a5-4e13-845a-57d393e76d23	Cancelled	Amazon Pay	Asia	Johnny Marshall	2024-03-29	1	1	3850.06892	18.41	10	3850.06892
61382908-0b90-4f82-bce5-482bba4a5446	Pending	PayPal	South America	Roger Brown	2024-07-06	1	1	2445.840424	8.39	8	2445.840424
6138c5ca-5b92-4c19-9229-2743cc35566b	Returned	PayPal	Asia	Jason Nelson	2020-05-17	1	1	89.497928	22.82	2	89.497928
6146d081-e633-4d47-a169-815f73e68d0e	Returned	Debit Card	South America	Charles Smith	2019-06-14	1	1	1195.0768320000002	23.83	4	1195.0768320000002
6162116e-f51e-4e38-8f1d-8cf0798744d2	Pending	Gift Card	Asia	Christina Thompson	2020-09-13	1	1	3866.59197	4.93	9	3866.59197
616fd8fe-4e02-4ce4-96ea-e6d023c5f66b	Cancelled	Gift Card	Australia	Emily Matthews	2020-01-03	1	1	771.114554	7.07	2	771.114554
61738448-ee9d-45e5-bdf8-54db7250e3f7	Returned	Amazon Pay	Australia	Caitlyn Boyd	2021-04-10	1	1	1057.316085	23.05	3	1057.316085
618a1f07-e3ce-43ff-89d6-8cc66d1477d8	Cancelled	Credit Card	Asia	Susan Edwards	2020-03-30	1	1	1113.378112	29.16	4	1113.378112
618c272a-83fa-4dfc-8457-2d29475c375c	Pending	Credit Card	North America	Steven Coleman	2023-05-12	1	1	1480.614912	7.84	7	1480.614912
619c6ba1-31b9-4978-bd73-516048601754	Pending	Credit Card	Europe	Michelle Garza	2021-04-11	1	1	268.33494	15.1	2	268.33494
619f42de-1762-4371-b516-cdb2934ae352	Returned	Gift Card	North America	Sandra Luna	2023-06-19	1	1	371.513688	10.47	7	371.513688
61a6c53c-c561-401a-98b8-3e615a232c8b	Cancelled	Credit Card	North America	Sandra Luna	2019-10-25	1	1	1710.702	21.25	8	1710.702
61b84a5c-bd4e-4afb-a8f4-759c02f4d34f	Returned	Gift Card	Europe	Mary Scott	2021-02-12	1	1	3836.02932	1.61	10	3836.02932
61d145af-defd-42bc-b6f4-6b461b37c734	Pending	Debit Card	North America	Diane Andrews	2024-03-28	1	1	1931.49093	3.13	10	1931.49093
61e0b723-1883-4e3b-9b1a-2c1682ddfffe	Cancelled	Gift Card	Asia	Christina Thompson	2021-08-06	1	1	267.61005	2.51	3	267.61005
61ef7b1e-01a0-4609-9e5f-2f076d7dd589	Cancelled	Debit Card	South America	Caleb Camacho	2024-01-17	1	1	392.271516	17.42	2	392.271516
61fc2847-ca88-41b1-bae5-426b8b729985	Returned	PayPal	North America	Bradley Howe	2024-03-14	1	1	385.89894	14.45	1	385.89894
6207d618-3661-4e19-9013-5171bd08a687	Returned	Debit Card	Asia	Crystal Williams	2020-11-15	1	1	2012.9778	29	9	2012.9778
6210273c-cf30-4647-903c-1786d503badd	Pending	PayPal	Europe	Caleb Camacho	2020-12-22	1	1	1308.278088	22.42	4	1308.278088
6213502a-978c-4b48-8150-37ff7f2e8c9c	Cancelled	PayPal	North America	Roger Brown	2022-07-16	1	1	448.62208	0.8	1	448.62208
6236ff5b-fcbf-4e49-a493-090a083099bb	Pending	Debit Card	North America	Susan Edwards	2023-12-24	1	1	1597.0091999999995	17.9	6	1597.0091999999995
62399067-18a5-47c2-a9f1-0bd051abb00d	Cancelled	Debit Card	Asia	Caleb Camacho	2023-05-23	1	1	140.917665	20.65	1	140.917665
623e1e85-adba-4ea0-ac4b-13539a50801a	Returned	Debit Card	South America	Jason Nelson	2022-02-16	1	1	245.71848	20.94	10	245.71848
6269775b-3bc3-445c-92cc-b9c1a4e5f015	Pending	Gift Card	Asia	Sandra Luna	2023-03-01	1	1	3119.767128	18.69	9	3119.767128
627874c2-5c42-49f3-9b1b-6aad3edbdca8	Pending	Gift Card	North America	Steven Coleman	2021-10-19	1	1	817.2653999999999	7	2	817.2653999999999
627d82c5-17d0-4504-9b81-ae4d6bfee54a	Cancelled	Credit Card	Europe	Christina Thompson	2019-07-02	1	1	1578.918432	15.09	4	1578.918432
628ec741-3d08-498b-96ac-e3bb721bc4f2	Returned	Gift Card	Australia	Sandra Luna	2020-02-06	1	1	2058.34365	10.9	5	2058.34365
6293891e-050a-4747-b9fc-1ce3cc17710a	Cancelled	PayPal	Asia	Michelle Andersen	2022-10-28	1	1	2175.95112	19.95	8	2175.95112
62967067-3307-4fa7-9a6a-ad3f140abcc4	Cancelled	Debit Card	Asia	Bradley Howe	2022-07-17	1	1	582.337536	27.44	8	582.337536
62e5fb16-9a9a-4ec5-8530-ed624649b932	Returned	Amazon Pay	South America	Michelle Andersen	2020-02-09	1	1	645.96984	18.96	10	645.96984
630eea89-3192-471d-807e-eb2dcd7c272c	Pending	Gift Card	Asia	Adam Smith	2020-03-24	1	1	2807.143605	15.69	7	2807.143605
63207c93-ceae-4880-9218-2c73682eeba7	Returned	Credit Card	Asia	Sandra Luna	2019-07-16	1	1	209.10351000000003	3.26	3	209.10351000000003
633fb141-e699-4588-b073-1dfaef605560	Pending	PayPal	Asia	Caleb Camacho	2020-11-19	1	1	1445.5834	20.75	4	1445.5834
63466f9d-15b5-46b7-b567-77480b34e9b2	Pending	Credit Card	South America	Johnny Marshall	2019-11-22	1	1	937.28425	6.9	5	937.28425
63576c11-7a21-432e-9695-d1225d2bb7ea	Returned	PayPal	Asia	Jason Nelson	2023-03-20	1	1	1375.7882400000003	6.16	5	1375.7882400000003
6372a78e-1b9b-473d-98d0-e733c003e44c	Returned	PayPal	South America	Kristen Ramos	2023-06-09	1	1	1349.379648	29.26	8	1349.379648
63911647-d31c-43b4-a159-0f7c8ef20ca2	Returned	Debit Card	South America	Kristen Ramos	2024-05-01	1	1	1076.397504	29.02	8	1076.397504
63b2233b-1b62-4bfd-a950-8c4b0527ef93	Cancelled	Amazon Pay	South America	Bradley Howe	2020-05-22	1	1	4252.900680000001	5.98	10	4252.900680000001
63b43679-2765-41f1-a2bd-aae6195b6b01	Pending	PayPal	Asia	Sandra Luna	2020-08-16	1	1	1313.88173	4.05	7	1313.88173
63be78dd-a262-4b01-8ddf-079b11479cfd	Returned	Amazon Pay	Europe	Charles Smith	2019-11-06	1	1	365.86077	2.65	1	365.86077
63c20592-94bc-4858-966f-b783b1c41fc4	Returned	Credit Card	North America	Michelle Garza	2019-04-02	1	1	1232.5684199999998	13.05	4	1232.5684199999998
63f3fca2-0fcb-42f7-8d99-701ca16996c9	Returned	Credit Card	South America	Crystal Williams	2020-09-01	1	1	1516.8662600000002	26.43	10	1516.8662600000002
63f5299a-7500-47fc-b7f0-50a99a159486	Returned	Debit Card	Asia	Roger Brown	2019-08-25	1	1	1483.391376	26.62	8	1483.391376
63fe620e-fda8-435b-bb2e-7bcd7fa0715f	Pending	PayPal	Australia	Mary Scott	2021-06-10	1	1	463.00056	26.96	2	463.00056
64150aa9-0adf-470f-9d73-c27568a87872	Returned	Debit Card	Europe	Kristen Ramos	2019-02-05	1	1	211.892476	25.61	2	211.892476
641a5f68-f1d5-46fa-a91b-81b6837badca	Pending	Gift Card	North America	Susan Edwards	2019-01-24	1	1	3859.0734	3.4	10	3859.0734
642e2f43-bf7b-4e34-af94-9d6658c94f0d	Returned	Debit Card	Australia	Roger Brown	2020-08-02	1	1	2200.49544	14.64	6	2200.49544
64319b1a-2906-4db1-b898-1888a4a6d17b	Cancelled	Amazon Pay	South America	Emily Matthews	2020-08-08	1	1	1478.124396	24.51	6	1478.124396
64376d46-4683-498c-8b23-048c5367e899	Cancelled	Debit Card	Australia	Crystal Williams	2021-05-27	1	1	738.25584	18.45	4	738.25584
64452475-ed77-4a73-b5b0-fd69787a294f	Returned	Amazon Pay	Australia	Emily Matthews	2021-04-29	1	1	515.6041600000001	21.2	2	515.6041600000001
644d7a99-daa8-49a0-a02f-bcab42cdb8be	Cancelled	Amazon Pay	North America	Caitlyn Boyd	2023-02-18	1	1	1338.1989600000002	13.62	8	1338.1989600000002
6450b526-1547-49cc-a56b-0b40b7c8a25f	Pending	Amazon Pay	South America	Roger Brown	2021-06-09	1	1	504.97671	15.03	10	504.97671
64553fac-a8f0-433c-b103-3683d1f70cd1	Cancelled	Amazon Pay	North America	Caitlyn Boyd	2022-02-10	1	1	2876.34366	0.7	6	2876.34366
645f5448-78aa-49ba-b28c-09766db05014	Returned	Credit Card	Europe	Michelle Garza	2020-03-22	1	1	516.088118	27.98	7	516.088118
6472470e-902a-4514-9308-d6d2167a960c	Returned	Amazon Pay	South America	Adam Smith	2023-09-14	1	1	1666.56939	2.85	6	1666.56939
64a2f303-d778-457c-87ba-cb44815400e7	Returned	Gift Card	South America	Jason Nelson	2022-03-28	1	1	1340.1461999999997	4.2	10	1340.1461999999997
64a36127-0926-4a68-ae13-6a1b0184d979	Returned	PayPal	Europe	Christina Thompson	2020-05-17	1	1	925.00224	15.97	4	925.00224
64a6ff6a-5aa4-4786-afda-adc304ebc144	Returned	Credit Card	Europe	Kristen Ramos	2020-08-12	1	1	144.737724	27.79	1	144.737724
64dd8c4e-9342-4749-8c78-d7d2acb21ed6	Returned	Debit Card	North America	Charles Smith	2024-03-17	1	1	1030.583022	18.83	7	1030.583022
64e472a0-b607-49cf-ac2a-e4fca7e99266	Pending	Gift Card	North America	Christina Thompson	2023-12-17	1	1	1569.255768	3.34	4	1569.255768
6533154f-4f21-414d-96ba-fe0e686e9d9d	Returned	Gift Card	Australia	Bradley Howe	2019-05-07	1	1	2203.428192	19.88	8	2203.428192
654e3d0a-9a15-402e-80f2-f1a123d1cb22	Pending	PayPal	South America	Bradley Howe	2022-11-10	1	1	1335.94407	25.57	10	1335.94407
65600a94-8620-4cac-bfc4-67179ad73511	Returned	Debit Card	Australia	Susan Edwards	2020-06-15	1	1	1586.12266	26.28	5	1586.12266
6568c425-05a2-4867-85fc-8070735fab7f	Pending	Credit Card	North America	Roger Brown	2023-10-03	1	1	530.710244	21.59	2	530.710244
656be432-4841-4e80-aa65-df5f18e04bb8	Pending	PayPal	Europe	Caleb Camacho	2022-11-10	1	1	1181.641032	4.97	4	1181.641032
656d071a-b5c1-4582-a4f4-4b1ac4879a4d	Returned	Credit Card	Australia	Jason Nelson	2023-08-28	1	1	372.507927	5.51	1	372.507927
656d68e4-1594-494d-8274-da79093ca066	Pending	Debit Card	Europe	Susan Edwards	2020-07-03	1	1	588.23872	27.36	10	588.23872
657da9a8-d655-4117-8645-ef5e2d48b31b	Pending	PayPal	North America	Johnny Marshall	2023-04-05	1	1	1034.64928	22.16	8	1034.64928
6589301e-41ff-4e3e-b0b7-7fdb6924000e	Returned	PayPal	North America	Adam Smith	2021-10-16	1	1	515.83833	28.05	6	515.83833
659b2be7-690a-47d0-9621-4c4186190612	Returned	Amazon Pay	North America	Crystal Williams	2022-12-22	1	1	3179.272336	1.49	8	3179.272336
65a9a866-4392-439d-82aa-e39a52ea1aa7	Pending	Amazon Pay	Asia	Caleb Camacho	2020-10-27	1	1	2514.987648	27.79	8	2514.987648
65bd785c-c195-4397-a262-197c4db3e649	Cancelled	Debit Card	Australia	Susan Edwards	2020-12-20	1	1	1086.13386	4.15	7	1086.13386
65dabbfd-0b9b-448c-8013-df9e85310092	Pending	Gift Card	Asia	Crystal Williams	2021-03-19	1	1	991.773846	17.89	6	991.773846
65f2180d-0371-4498-8ec8-8cbe8f4c742f	Cancelled	Gift Card	Europe	Caitlyn Boyd	2022-01-17	1	1	2162.022768	5.74	8	2162.022768
65fd43a4-e45f-4c89-a192-abf5d70b603b	Pending	Amazon Pay	Asia	Caitlyn Boyd	2023-10-22	1	1	512.6038800000001	26.54	10	512.6038800000001
6602fc0a-2228-4cf7-828c-e277e78c2a07	Pending	Debit Card	Asia	Joseph Brooks	2024-09-06	1	1	1447.1736	9.04	5	1447.1736
6611bb5a-e05c-4726-b72f-dbf026aebe41	Pending	Gift Card	South America	Adam Smith	2022-07-03	1	1	41.772094	17.82	1	41.772094
66210cae-4fe6-4c0f-94c2-e791eed15e2b	Cancelled	Amazon Pay	Europe	Susan Edwards	2024-10-10	1	1	3399.829472	11.07	8	3399.829472
6629aeb6-75f9-43d7-a151-da42c4da988b	Pending	Debit Card	North America	Adam Smith	2024-03-30	1	1	2178.921696	25.16	7	2178.921696
66301510-0d8b-4ee7-bce1-3208a94c69a8	Pending	Credit Card	Australia	Michelle Andersen	2024-09-13	1	1	381.12643	11.51	1	381.12643
663e3aeb-1a10-4184-8b64-0bd6faa0b504	Returned	Amazon Pay	South America	Michelle Garza	2022-01-30	1	1	2331.507024	12.79	8	2331.507024
664f55c8-e215-45c1-8018-4b077c0233f4	Cancelled	Credit Card	Asia	Michelle Andersen	2022-05-17	1	1	836.4584800000001	24.86	4	836.4584800000001
667a68aa-76c0-4d4a-a5b0-acbf9e35d1a1	Cancelled	Debit Card	Asia	Charles Smith	2019-02-12	1	1	1194.17424	27.22	5	1194.17424
66a2f351-47ea-4015-a5ea-79343d40e5cf	Returned	PayPal	Europe	Bradley Howe	2023-06-10	1	1	758.22909	3.57	2	758.22909
66a87701-2ef3-4e93-aeed-602433041d15	Pending	PayPal	North America	Jason Nelson	2022-03-27	1	1	525.194124	16.02	6	525.194124
66ae370d-3593-4452-89be-26deb7368ead	Returned	Gift Card	Australia	Michelle Garza	2021-07-11	1	1	423.15264	13.6	2	423.15264
66b27d0e-2efd-498f-9f06-82ad39a56e6e	Pending	PayPal	North America	Steven Coleman	2023-01-29	1	1	239.85036	28.87	1	239.85036
66cab100-143b-4a56-9291-b91933f3407e	Pending	Gift Card	North America	Jason Nelson	2023-10-01	1	1	568.6496000000001	14.36	8	568.6496000000001
66d1ec5b-b543-4ab7-93b4-379d584c2fa6	Cancelled	Debit Card	Asia	Johnny Marshall	2023-03-25	1	1	903.89964	8.4	3	903.89964
66d2d47d-b5d4-493d-a57c-e1a76fe4dbba	Pending	Amazon Pay	South America	Steven Coleman	2021-04-22	1	1	1899.1833599999995	28.96	10	1899.1833599999995
66e9d1bb-4bcb-45a0-af90-aae878bdf65f	Cancelled	Amazon Pay	Asia	Bradley Howe	2023-08-16	1	1	151.715025	12.43	9	151.715025
66f5af49-0d96-4365-a2b3-5d21cb4c7cc3	Pending	Gift Card	Europe	Jason Nelson	2019-11-15	1	1	568.010936	2.36	2	568.010936
67234cbe-94e3-423b-952f-a7b43fe8fc00	Pending	Amazon Pay	Europe	Emily Matthews	2021-05-05	1	1	623.884716	27.22	3	623.884716
67292e03-6ae7-4452-8f15-7fef5141abb4	Pending	Credit Card	Australia	Caitlyn Boyd	2020-04-07	1	1	778.879584	25.24	3	778.879584
672978f8-ddb7-4b25-aad5-a47679abbc16	Cancelled	Amazon Pay	Australia	Diane Andrews	2024-10-17	1	1	1166.13664	8.85	8	1166.13664
672dd61c-e278-425c-9422-2f85676710a5	Cancelled	PayPal	Asia	Sandra Luna	2024-02-17	1	1	756.3801599999999	29.4	4	756.3801599999999
6736c3ec-2587-4130-97b4-6f559414bab4	Cancelled	PayPal	North America	Jason Nelson	2023-08-11	1	1	797.37012	1.34	2	797.37012
675ee952-5a5f-48be-bd2c-c7c825198f0b	Returned	Gift Card	South America	Diane Andrews	2022-10-16	1	1	1315.90361	13.49	5	1315.90361
67629403-1a93-48cd-a925-76141ad42310	Pending	PayPal	North America	Diane Andrews	2022-01-11	1	1	178.39407599999998	29.86	6	178.39407599999998
6769eb87-03a7-4660-8cd8-74afd2475389	Returned	Amazon Pay	North America	Bradley Howe	2022-06-02	1	1	555.8203	19.5	2	555.8203
67a54056-f331-4574-aba0-8aeef2da1ab2	Returned	Credit Card	South America	Kristen Ramos	2024-07-25	1	1	230.192928	15.42	9	230.192928
67a67dfd-e606-42cf-a271-988ddc829911	Pending	Credit Card	Europe	Susan Edwards	2022-05-19	1	1	879.0657499999999	27.75	10	879.0657499999999
67b00c13-dd31-4da5-89b6-4d90a3858312	Pending	Amazon Pay	Australia	Michelle Andersen	2019-12-23	1	1	520.285788	18.14	9	520.285788
67c966f6-1a25-4c75-94d8-fbd3b9511451	Pending	Amazon Pay	Asia	Kristen Ramos	2019-08-31	1	1	3259.350495	4.15	9	3259.350495
67ce70ef-95aa-4c62-b55b-755b4a2fffb6	Pending	Debit Card	Asia	Christina Thompson	2020-04-25	1	1	1210.486464	17.44	3	1210.486464
68007e15-acd9-424b-a7d5-87c573c87c37	Pending	Debit Card	Australia	Caitlyn Boyd	2019-12-17	1	1	584.89288	29.48	4	584.89288
680a28ee-696e-48cf-868e-ddac6f3c0b0e	Returned	Gift Card	Asia	Michelle Andersen	2024-09-18	1	1	261.165951	2.59	1	261.165951
687b199e-ff9a-4ab0-8632-1ef01382eca6	Returned	Credit Card	North America	Roger Brown	2020-09-26	1	1	730.155636	16.78	3	730.155636
687cf166-a193-4ef6-9880-e3e6be30e08a	Returned	Credit Card	North America	Johnny Marshall	2019-12-06	1	1	383.77537	2.3	1	383.77537
68815446-bdff-4b6f-adb2-af8d513e3288	Cancelled	Gift Card	Asia	Susan Edwards	2023-03-06	1	1	1593.89307	4.3	7	1593.89307
68a1386e-8cf7-4aa3-bed2-9274ed164c2f	Cancelled	Amazon Pay	Australia	Michelle Andersen	2020-12-10	1	1	115.06109999999998	0.38	3	115.06109999999998
68aea67d-f3d5-476e-88d5-0701d2e827cc	Returned	PayPal	Australia	Emily Matthews	2021-10-12	1	1	2223.2075040000004	24.24	7	2223.2075040000004
68bdbc07-8f0f-429a-bbe6-5fad24ceb847	Pending	Debit Card	North America	Steven Coleman	2024-05-24	1	1	1899.9792	2.4	9	1899.9792
68c6c6c8-cb51-46d6-bf30-6e73f78dd9e4	Returned	Credit Card	South America	Joseph Brooks	2022-06-11	1	1	1274.1624	24.4	6	1274.1624
68f59000-ffe7-48db-ae5d-0726c2a420a3	Returned	PayPal	North America	Roger Brown	2019-02-13	1	1	851.4257439999999	27.59	8	851.4257439999999
68f929e6-8995-4bac-85a6-c32460dc5620	Cancelled	Debit Card	Australia	Diane Andrews	2021-04-16	1	1	337.205952	22.46	8	337.205952
68fa9916-f42a-4396-bbdc-00fb0eae77f2	Pending	PayPal	South America	Jason Nelson	2020-02-22	1	1	1366.97264	26.1	4	1366.97264
68fb4ad7-470b-4f51-ad6f-8e3f92e67d37	Pending	Amazon Pay	North America	Roger Brown	2021-12-28	1	1	2796.95808	2.64	9	2796.95808
690acc27-3d57-4626-8b4d-9896c81a5e7a	Pending	Credit Card	Australia	Bradley Howe	2019-10-24	1	1	3034.192095	25.09	9	3034.192095
69254feb-e996-4d7e-b2ec-c65b1787e3d5	Pending	Credit Card	South America	Jason Nelson	2019-01-09	1	1	1898.029325	3.69	5	1898.029325
692957b4-4c1f-4a87-a6e3-c29e2703ee4b	Returned	PayPal	Europe	Michelle Garza	2024-10-13	1	1	3875.04936	4.8	9	3875.04936
693988d2-9529-49f8-a661-33fe6a885471	Cancelled	PayPal	Australia	Jason Nelson	2022-01-23	1	1	2385.2772240000004	16.38	6	2385.2772240000004
6942241a-6b78-4e80-bc4c-068553e9cde1	Cancelled	Debit Card	Asia	Caleb Camacho	2020-01-14	1	1	1443.889152	2.08	4	1443.889152
69536a60-6ce7-4a5e-af4d-0e7566aa569d	Pending	Credit Card	North America	Diane Andrews	2023-09-01	1	1	315.725758	18.21	1	315.725758
696ccd10-3569-4871-b616-233f44f5936f	Cancelled	PayPal	Australia	Adam Smith	2022-10-21	1	1	1100.41272	18.27	6	1100.41272
6997dc7f-989a-4347-90a8-37e956578025	Returned	Gift Card	Europe	Caleb Camacho	2024-05-12	1	1	121.488384	9.12	4	121.488384
69ddde05-a645-492d-ada7-745670639ec1	Returned	Debit Card	North America	Kristen Ramos	2019-12-30	1	1	1911.13263	14.05	9	1911.13263
69ee6688-c404-4712-81be-83bfe581de9e	Returned	PayPal	Asia	Sandra Luna	2021-10-27	1	1	161.169988	22.11	2	161.169988
6a0a600a-6c39-4041-8c15-54d5a1f0796d	Returned	Gift Card	Asia	Michelle Garza	2023-12-04	1	1	675.313611	3.11	3	675.313611
6a10383d-a0e4-479c-887b-9c5d05441d1b	Pending	Credit Card	Australia	Sandra Luna	2023-08-19	1	1	1649.7079200000005	26.92	5	1649.7079200000005
6a1b1773-9158-4952-8e30-0b78bfbce99c	Cancelled	Gift Card	South America	Crystal Williams	2020-04-30	1	1	395.91936	18.08	3	395.91936
6a1fdea0-6864-4129-aeb6-3dbe3fd1d350	Pending	PayPal	Asia	Caleb Camacho	2020-02-27	1	1	226.432245	4.35	1	226.432245
6a2d044e-ebbd-4099-b5bb-dc9369b757bf	Returned	Amazon Pay	Australia	Diane Andrews	2022-04-02	1	1	38.733576	9.88	1	38.733576
6a401c7b-464b-4491-9fb5-a3851f562773	Returned	PayPal	North America	Roger Brown	2024-09-15	1	1	258.026262	4.71	3	258.026262
6a406212-6771-407f-abd6-717183186426	Cancelled	PayPal	South America	Caitlyn Boyd	2020-02-23	1	1	1263.6053849999998	6.41	5	1263.6053849999998
6a473b2b-1c33-4a96-b76c-160bca201879	Pending	Gift Card	North America	Adam Smith	2020-11-26	1	1	1217.095896	19.67	6	1217.095896
6a88bb84-1c8e-47fc-90f4-ef04a603efc7	Pending	Credit Card	Australia	Roger Brown	2020-12-06	1	1	1353.59406	7.18	3	1353.59406
6a8c9682-f15d-4374-a129-06d5d2269e9a	Cancelled	Amazon Pay	North America	Crystal Williams	2020-01-08	1	1	336.718239	11.81	3	336.718239
6a904bb7-d89b-462a-b488-e23d82018663	Returned	Amazon Pay	Asia	Joseph Brooks	2021-05-30	1	1	1798.25058	11.3	9	1798.25058
6a9119e5-b1ab-4b35-96ca-29e73283d133	Pending	Amazon Pay	South America	Bradley Howe	2019-06-10	1	1	2437.365006	10.06	9	2437.365006
6a998d5e-a744-401d-b870-e793a6ea41aa	Pending	Credit Card	Europe	Michelle Andersen	2024-11-23	1	1	3297.406968	26.02	9	3297.406968
6aa9ddfd-28e3-4d83-ab1d-c619c59cb432	Pending	Amazon Pay	Europe	Crystal Williams	2021-01-08	1	1	234.207433	4.37	1	234.207433
6aad1aa2-1000-41e0-a43c-c850afc4e63c	Returned	PayPal	Asia	Charles Smith	2020-07-06	1	1	1151.930633	5.69	7	1151.930633
6ab5c8f7-0c73-4b94-b3e3-072cc167da4b	Cancelled	PayPal	Australia	Crystal Williams	2023-01-04	1	1	67.287296	21.54	8	67.287296
6ac6af4c-3a38-49c6-b5ad-7785d70d338f	Cancelled	Gift Card	Asia	Michelle Garza	2021-08-07	1	1	753.317904	20.68	2	753.317904
6adac2cd-be54-46d9-89da-fea569958751	Pending	Amazon Pay	Australia	Adam Smith	2021-03-27	1	1	795.91868	9.15	4	795.91868
6ae6c006-396c-49db-9b25-88cca4419bf1	Pending	Debit Card	Australia	Mary Scott	2020-11-27	1	1	1611.5869979999998	19.91	6	1611.5869979999998
6af3c0be-1971-4801-8517-2f85e8e2a4cf	Pending	Debit Card	Australia	Michelle Garza	2019-07-19	1	1	553.9843470000001	14.93	3	553.9843470000001
6b1f2180-7d1f-4710-9295-0e5373376cdc	Cancelled	Amazon Pay	Australia	Crystal Williams	2024-12-10	1	1	271.730172	23.48	3	271.730172
6b40b377-b349-4022-9c93-e708858dc735	Returned	Debit Card	Asia	Sandra Luna	2021-09-23	1	1	323.718094	8.66	1	323.718094
6b44eed7-284b-456e-a0fd-ffc166c79bf4	Pending	Credit Card	North America	Bradley Howe	2020-11-09	1	1	427.558684	25.82	2	427.558684
6b695743-39fe-44e6-9c2a-fc1baa559817	Cancelled	PayPal	South America	Crystal Williams	2024-12-02	1	1	1170.015896	18.68	7	1170.015896
6b9fa55c-483d-4bf7-9dac-2ac2a6d2b7b9	Cancelled	Amazon Pay	Asia	Bradley Howe	2024-05-07	1	1	2554.126344	18.64	9	2554.126344
6bb4559e-c00c-4b72-893f-be2752fad5a4	Pending	Credit Card	Asia	Caitlyn Boyd	2020-10-04	1	1	828.665838	10.46	9	828.665838
6bc1bc48-a066-46be-b6f5-b59c99bc7478	Cancelled	PayPal	Australia	Susan Edwards	2024-08-06	1	1	1124.17722	6.49	5	1124.17722
6c09c2ed-0875-4ded-8472-bcbea0c994db	Returned	PayPal	Europe	Johnny Marshall	2020-10-19	1	1	1604.705805	21.45	9	1604.705805
6c0cbcd2-a6c3-4184-9da9-2627421df1a4	Cancelled	Credit Card	North America	Roger Brown	2024-01-16	1	1	1893.448596	27.71	6	1893.448596
6c192c2b-6155-4916-a04c-ab87804072ff	Returned	Amazon Pay	Asia	Caleb Camacho	2021-07-04	1	1	2140.79822	12.44	5	2140.79822
6c284490-c289-425a-8e1e-fdb3408b920d	Returned	PayPal	Asia	Mary Scott	2019-03-10	1	1	1516.147465	25.71	7	1516.147465
6c359f70-33e1-46d8-905d-5a5b04f59e58	Cancelled	PayPal	North America	Adam Smith	2022-09-18	1	1	1930.00082	17.72	5	1930.00082
6c515fca-1c13-4212-aa00-7650107b4773	Cancelled	Amazon Pay	Asia	Charles Smith	2020-10-25	1	1	2577.26292	20.07	10	2577.26292
6c528494-4501-4f4e-a51e-d679e921d942	Cancelled	Debit Card	Australia	Caleb Camacho	2021-04-02	1	1	113.094756	5.09	2	113.094756
6c6422b3-7e45-42bd-a80e-a69134f07357	Returned	Debit Card	Australia	Roger Brown	2019-08-26	1	1	1546.723975	7.65	5	1546.723975
6c652079-afde-4172-99ea-94893bda03b0	Cancelled	PayPal	South America	Michelle Garza	2024-01-02	1	1	327.590862	4.23	6	327.590862
6c6a4162-ea9b-40c7-9746-ad7829a062ca	Cancelled	Debit Card	South America	Caleb Camacho	2024-06-15	1	1	909.362152	5.33	8	909.362152
6c7eb84f-2d1c-4f2c-8358-2a3822c965ab	Cancelled	PayPal	Asia	Christina Thompson	2021-06-21	1	1	409.75359	23.71	2	409.75359
6c8d1405-eb83-4e46-a1f4-46d9469facd8	Cancelled	Amazon Pay	Australia	Adam Smith	2024-07-07	1	1	914.917944	4.91	2	914.917944
6c8fa5c7-4bc8-4ee1-90a4-b43c5ef72ac9	Pending	PayPal	North America	Jason Nelson	2022-04-09	1	1	362.028075	27.15	1	362.028075
6c981e75-dad9-4894-9e1f-7415a204ad5f	Returned	Gift Card	South America	Joseph Brooks	2020-04-09	1	1	204.971172	15.42	7	204.971172
6c9e4c9e-9850-4cbf-9d8b-183d38d2cf40	Cancelled	Gift Card	South America	Caitlyn Boyd	2021-04-17	1	1	390.233211	3.81	1	390.233211
6ca4e991-6458-41d3-8d5b-3ba7d9159eb4	Cancelled	Gift Card	Europe	Caleb Camacho	2024-01-14	1	1	1112.0087500000002	22.5	5	1112.0087500000002
6ce75fe2-952c-41f1-b85a-c162d2f6ffa0	Returned	PayPal	Europe	Sandra Luna	2021-01-03	1	1	631.415496	27.58	4	631.415496
6cec57f9-34c0-4f39-ab41-ddf198afb0df	Cancelled	Gift Card	South America	Charles Smith	2020-08-15	1	1	124.771944	28.84	2	124.771944
6cf1bea4-182e-40bd-955a-9cc6e236c752	Pending	Amazon Pay	North America	Kristen Ramos	2022-01-08	1	1	699.7557240000001	19.18	2	699.7557240000001
6cf5cfb8-b69a-44cb-9fee-aaa77f211bc9	Returned	Credit Card	Europe	Susan Edwards	2023-08-03	1	1	473.03136	4.6	4	473.03136
6d0def03-16a9-4c6b-b7b3-edded41fe6b4	Pending	Debit Card	North America	Adam Smith	2022-01-25	1	1	1532.626912	1.08	4	1532.626912
6d3194cb-e7d8-4e9a-9ea0-263e5a46a550	Pending	Amazon Pay	Australia	Caleb Camacho	2021-10-13	1	1	1579.3845359999998	14.19	8	1579.3845359999998
6d5add6f-f31c-4405-9df2-4fa65e024433	Returned	Amazon Pay	South America	Steven Coleman	2019-02-15	1	1	312.067035	3.19	5	312.067035
6d5c1431-a20b-46e9-ba35-f8b75c941e3b	Pending	Credit Card	Asia	Christina Thompson	2021-03-31	1	1	2026.991004	6.09	6	2026.991004
6d69a6fa-a7d1-4922-b454-1f554af79c3e	Cancelled	Debit Card	Asia	Michelle Andersen	2024-12-15	1	1	2034.132	15.75	6	2034.132
6d981421-12ba-4c67-bd41-3863d95c41f0	Pending	Gift Card	North America	Michelle Andersen	2020-07-04	1	1	1038.35406	23.9	3	1038.35406
6db06ebc-73c8-4076-8737-c8987a1f9e32	Pending	PayPal	North America	Joseph Brooks	2020-08-21	1	1	847.715004	29.74	9	847.715004
6dc79bb8-b03a-4acd-8a03-5a0460d85cc8	Pending	Amazon Pay	Asia	Johnny Marshall	2019-10-05	1	1	482.578	4.44	4	482.578
6dcfdb56-f64c-454d-96eb-b5e5254702a1	Pending	Credit Card	North America	Caitlyn Boyd	2023-11-28	1	1	404.9424	2.4	6	404.9424
6dd61f67-4338-41fd-a55f-242e590d5936	Cancelled	Credit Card	Australia	Diane Andrews	2023-10-27	1	1	1182.267216	23.04	9	1182.267216
6dd6ae8c-b824-4121-947a-dab60420516b	Returned	Debit Card	Europe	Jason Nelson	2021-03-20	1	1	1782.40502	18.93	10	1782.40502
6de91233-c724-4dc5-be1d-f4c4086b6456	Returned	PayPal	North America	Michelle Garza	2023-09-22	1	1	2457.3048500000004	17.06	7	2457.3048500000004
6de958b9-7876-47e2-a4fc-f2ef224dffdf	Cancelled	Debit Card	South America	Johnny Marshall	2020-09-29	1	1	1623.33524	23.85	8	1623.33524
6df37a02-d2f9-4b34-bafb-727bdbbc409f	Pending	Gift Card	Australia	Caitlyn Boyd	2024-04-15	1	1	986.145248	1.88	4	986.145248
6e02672b-2249-4e0f-bccd-77dc1df7fe6e	Returned	Debit Card	Europe	Joseph Brooks	2022-11-07	1	1	306.72864	26.83	10	306.72864
6e20ee38-f56c-4ca2-a1c7-4e8bdcf9ec0e	Cancelled	Amazon Pay	North America	Charles Smith	2023-09-27	1	1	459.543425	7.49	1	459.543425
6e284e17-e2c1-47bf-8dfe-af6e6873d75d	Cancelled	Debit Card	Asia	Caleb Camacho	2024-12-28	1	1	1081.734144	18.11	3	1081.734144
6e328ce8-afe2-4955-a5fd-29768dccea39	Returned	Debit Card	North America	Sandra Luna	2024-07-06	1	1	437.29588	10.61	2	437.29588
6e32bb25-acc6-49b9-a27e-6a0c39bdcdd4	Returned	Gift Card	North America	Michelle Andersen	2019-09-16	1	1	1509.59068	22.17	5	1509.59068
6e40f1e8-a535-43c8-906a-23eac04b0160	Pending	Debit Card	North America	Mary Scott	2021-05-03	1	1	2845.369071	10.11	9	2845.369071
6e4d0e33-5c09-421a-84c3-7a560c523059	Returned	Amazon Pay	South America	Joseph Brooks	2021-04-04	1	1	4040.45793	10.23	10	4040.45793
6e5da27a-744b-4cf3-9d14-66f50258e2bb	Cancelled	Credit Card	North America	Caleb Camacho	2024-07-31	1	1	1641.3426000000002	14.48	5	1641.3426000000002
6e5fd704-dbd4-417b-bf1b-2ec1563b1034	Cancelled	Amazon Pay	North America	Joseph Brooks	2024-07-22	1	1	492.10212	7.43	5	492.10212
6e6dd04a-29c2-4b81-9de9-e99a22e06d37	Pending	Debit Card	South America	Susan Edwards	2024-06-02	1	1	196.29027	29.05	2	196.29027
6e70cabb-37b2-42f2-a190-28c2274db9bc	Returned	Debit Card	Australia	Adam Smith	2023-09-25	1	1	97.779456	17.86	3	97.779456
6e7b4b56-70ed-4e35-afb7-bc92573b012d	Pending	Debit Card	Europe	Caleb Camacho	2024-10-12	1	1	1107.35688	19.78	4	1107.35688
6e7c7fad-bc4f-4fe3-9c88-e52045e53eec	Cancelled	Debit Card	Europe	Charles Smith	2019-07-11	1	1	1317.6624000000002	10.8	10	1317.6624000000002
6e7e1c94-a340-4c46-a83d-60eb9626081b	Cancelled	Amazon Pay	Europe	Susan Edwards	2022-08-04	1	1	598.287744	21.28	2	598.287744
6e82f16f-8276-4025-8c69-8e03be0c534d	Cancelled	Debit Card	Australia	Mary Scott	2019-07-31	1	1	126.844608	11.84	2	126.844608
6e8caf45-bcc2-4bfe-9c78-94887cb40931	Cancelled	Amazon Pay	Asia	Christina Thompson	2024-05-06	1	1	1396.8603360000002	29.26	4	1396.8603360000002
6eba34f0-1479-4633-97c6-ede4296a8ca3	Returned	Credit Card	Australia	Adam Smith	2020-06-29	1	1	2630.445516	0.76	9	2630.445516
6ebca311-fdc9-4c45-a8cb-a2fd491cbfc2	Returned	Debit Card	North America	Caitlyn Boyd	2024-09-07	1	1	676.4508519999999	20.69	4	676.4508519999999
6ec9c2d5-a875-4724-947f-3d7dd338289e	Pending	PayPal	Asia	Caitlyn Boyd	2023-04-13	1	1	1901.908008	28.03	6	1901.908008
6ede11cd-b4fe-45b5-ac35-877a33541e9f	Cancelled	Gift Card	Europe	Caleb Camacho	2020-05-07	1	1	390.304301	2.27	1	390.304301
6ef97957-e730-45f4-9c12-82f53af2c6be	Pending	Amazon Pay	North America	Michelle Garza	2021-07-30	1	1	168.8868	14	9	168.8868
6ef97dfa-b90b-4b17-9d3d-c17892621e6d	Cancelled	PayPal	Asia	Roger Brown	2019-05-01	1	1	349.784628	24.23	1	349.784628
6f03524b-4fce-4771-aa9e-5056011c45b6	Pending	Amazon Pay	Asia	Emily Matthews	2019-09-19	1	1	274.751892	10.58	1	274.751892
6f1d2a5e-7245-4940-952e-ee33c9fc490b	Returned	Credit Card	South America	Susan Edwards	2022-05-21	1	1	1457.557568	4.44	4	1457.557568
6f4f0362-8129-47e5-ae21-e0f1c1b3547f	Returned	Credit Card	Europe	Charles Smith	2019-02-11	1	1	258.951	10.32	7	258.951
6f558c30-5d80-43ad-b91f-b09b413bd0ea	Pending	Debit Card	Australia	Johnny Marshall	2020-03-30	1	1	1256.508414	12.19	3	1256.508414
6f67bedc-7587-4d60-bf4c-ed8acb28d765	Cancelled	Credit Card	North America	Joseph Brooks	2024-11-30	1	1	1590.814368	13.36	4	1590.814368
6f73a6d7-a6a9-409c-b634-e5801a775932	Returned	Gift Card	Asia	Michelle Garza	2023-10-19	1	1	2149.651314	1.13	9	2149.651314
6f868726-4d1d-4d88-a075-9b25a77cac75	Returned	Credit Card	Asia	Bradley Howe	2022-02-01	1	1	1930.88992	7.52	10	1930.88992
6f86e595-4257-49fa-8660-198d606c51ac	Pending	Amazon Pay	Asia	Adam Smith	2019-05-10	1	1	579.014985	9.05	3	579.014985
6f8cd323-6412-442f-8635-363204753a83	Cancelled	Amazon Pay	North America	Steven Coleman	2020-08-05	1	1	250.182912	3.12	4	250.182912
6f8f869f-3159-484a-a709-2f2734ac3b0b	Returned	Gift Card	South America	Michelle Garza	2021-04-13	1	1	154.209372	27.54	6	154.209372
6fb5a4bb-fbdc-449f-a4a0-d24f31c59923	Returned	Gift Card	Europe	Roger Brown	2020-02-02	1	1	1555.281918	25.22	9	1555.281918
6fb85e02-2d6f-4476-93c5-f95af3d078c1	Cancelled	Gift Card	Asia	Roger Brown	2020-10-20	1	1	1751.183784	4.03	8	1751.183784
6fe853de-6044-442f-9cb5-bd59548cbff1	Pending	Credit Card	Asia	Kristen Ramos	2021-09-01	1	1	224.725172	26.57	2	224.725172
6fecd076-4134-4ca1-b984-74bcb9dfd282	Pending	Gift Card	Australia	Steven Coleman	2022-06-18	1	1	3404.356677	7.59	9	3404.356677
6ffcb1ef-d537-45a8-8aec-262d11978000	Cancelled	Gift Card	South America	Crystal Williams	2020-07-20	1	1	1086.522255	15.37	3	1086.522255
700a8035-6124-481a-8b7d-e915377612c4	Cancelled	Credit Card	Europe	Kristen Ramos	2019-07-22	1	1	1894.54216	12.71	8	1894.54216
70203519-0473-474b-8e85-6f0754d73d53	Pending	PayPal	Australia	Joseph Brooks	2021-10-03	1	1	3663.4905	18.18	9	3663.4905
702f275c-dfd8-4ac7-9c46-529a46e90b44	Pending	Amazon Pay	Asia	Kristen Ramos	2024-01-09	1	1	871.48776	26.3	6	871.48776
7037594c-f157-4ef8-9872-3f93e04306a8	Cancelled	Credit Card	Asia	Roger Brown	2019-05-12	1	1	907.633344	10.32	8	907.633344
703eb9e1-b54d-47ae-92af-1e8a45304704	Pending	Amazon Pay	Australia	Caleb Camacho	2019-03-15	1	1	1731.469122	10.18	9	1731.469122
70409ad6-6a61-4417-bc06-df4ed7fdb2d4	Cancelled	Credit Card	Asia	Bradley Howe	2019-10-31	1	1	1753.8092760000002	20.46	6	1753.8092760000002
705e839c-89f7-4132-bed1-9e9c9c4e3a9a	Cancelled	PayPal	North America	Adam Smith	2019-06-22	1	1	503.793	29.5	6	503.793
70746705-a3eb-4cb7-b0c0-fb16690fc640	Cancelled	PayPal	Asia	Sandra Luna	2024-03-20	1	1	2153.854269	10.51	7	2153.854269
707aa42d-2efc-475a-be8b-8cc324753f34	Returned	Debit Card	Europe	Mary Scott	2021-03-20	1	1	392.38213200000007	16.34	3	392.38213200000007
708775a2-8a43-4cb1-937a-a5c629f47146	Cancelled	Debit Card	Europe	Mary Scott	2022-01-13	1	1	3229.61213	2.13	10	3229.61213
7088652e-c9df-44b5-8ef3-e27c506c441c	Cancelled	Gift Card	Europe	Diane Andrews	2022-10-16	1	1	2833.7256640000005	13.53	7	2833.7256640000005
708f9f18-80d6-4c04-a9d2-20ff2ba2ca7c	Returned	Gift Card	North America	Johnny Marshall	2019-03-20	1	1	1467.16672	19.28	8	1467.16672
70990452-bf3c-452f-a46d-c64f2119f449	Returned	Amazon Pay	Europe	Kristen Ramos	2022-12-21	1	1	127.39448400000002	11.74	7	127.39448400000002
70a024ee-ad77-40dc-ae49-1b3bf08bf4c6	Cancelled	PayPal	Europe	Caitlyn Boyd	2020-07-09	1	1	413.564316	9.71	4	413.564316
70d3774f-0393-4a6a-aabd-d18361134bb1	Cancelled	Amazon Pay	Asia	Christina Thompson	2019-06-09	1	1	4546.9492	3.65	10	4546.9492
70ecc016-fcc5-4c18-9a59-e5d0d089440c	Pending	Credit Card	South America	Adam Smith	2022-03-11	1	1	162.704668	24.26	2	162.704668
70f61f0b-cf8a-413a-b4b5-6b32f85e8ff8	Pending	Amazon Pay	Europe	Mary Scott	2023-03-15	1	1	706.34226	15.05	2	706.34226
70faac5b-fd78-4e84-a5d2-b53e90d77d26	Pending	Gift Card	North America	Mary Scott	2022-03-30	1	1	348.614491	2.51	1	348.614491
70fcbeee-9038-452d-af1b-2b966c5ffc19	Returned	PayPal	Asia	Charles Smith	2023-08-10	1	1	1561.1596	29.93	5	1561.1596
71172dfe-11b9-46b1-b370-08d583e66072	Pending	Gift Card	Europe	Kristen Ramos	2019-08-11	1	1	2128.6362240000003	27.88	6	2128.6362240000003
711b5cfa-8699-4b0e-80d8-133d1c5b62ce	Pending	PayPal	Australia	Kristen Ramos	2021-08-05	1	1	311.093838	28.42	3	311.093838
71306b79-cb06-4ec9-abfa-1383a722e825	Returned	Credit Card	Europe	Mary Scott	2020-06-10	1	1	3477.152214	16.34	9	3477.152214
7134113a-14e5-4585-adf7-b70eaff9da53	Returned	Gift Card	Asia	Charles Smith	2022-02-23	1	1	534.06886	3.02	10	534.06886
7134bf96-b15c-4958-847d-9bb4b9e3906a	Cancelled	Credit Card	Asia	Adam Smith	2022-05-11	1	1	586.9105829999999	13.27	9	586.9105829999999
7139a07f-cdf0-439f-a3a7-8ffccc7cfa44	Pending	Gift Card	Asia	Bradley Howe	2024-12-04	1	1	25.807104	22.08	2	25.807104
7142a965-909e-4dbe-bf36-a529d5aa1d90	Returned	PayPal	Asia	Joseph Brooks	2020-03-21	1	1	462.133	25.1	10	462.133
71561a87-d4ae-48d9-a6d2-0cc81a3de457	Cancelled	Debit Card	Europe	Charles Smith	2024-09-02	1	1	88.360848	11.07	1	88.360848
7159a48d-e822-4b6f-ab33-821c3a034c06	Returned	Debit Card	Europe	Michelle Andersen	2022-06-12	1	1	655.6872	24.46	8	655.6872
715a6c39-4e71-47af-93ff-1976a87f4b2f	Cancelled	Amazon Pay	South America	Kristen Ramos	2020-08-12	1	1	1522.502832	16.11	8	1522.502832
718094b4-b03a-466a-9f6a-e5f05e7eae3c	Cancelled	Amazon Pay	Europe	Roger Brown	2020-03-27	1	1	712.6894709999999	27.57	3	712.6894709999999
7181d559-f4b4-4652-a97a-88694c955056	Returned	Debit Card	Australia	Johnny Marshall	2022-01-30	1	1	938.866992	0.18	4	938.866992
719b5959-c31d-4312-b74d-a2746ebc5395	Returned	Amazon Pay	South America	Steven Coleman	2022-04-25	1	1	1411.7861280000002	1.73	4	1411.7861280000002
719c7bb7-f948-4d2c-84da-729dc54e34d5	Returned	PayPal	Australia	Diane Andrews	2020-01-02	1	1	1313.28768	18.7	4	1313.28768
71a218f6-9edc-4056-800c-ff414588d37d	Cancelled	Credit Card	Australia	Steven Coleman	2024-12-02	1	1	1019.7004	29.85	8	1019.7004
71b4ccfb-560e-4a94-b9cd-0e3a3b9e725d	Cancelled	Credit Card	Australia	Adam Smith	2024-01-22	1	1	1779.5133	27.64	9	1779.5133
71b9fe73-f807-4be8-bc24-5a246a67ada1	Returned	Amazon Pay	Europe	Caleb Camacho	2019-12-02	1	1	153.01319999999998	6	1	153.01319999999998
71bed179-9039-4fdf-b246-a799252050fe	Returned	Credit Card	North America	Charles Smith	2024-07-26	1	1	1268.494416	18.68	6	1268.494416
71c15f2e-2493-4ff3-b453-297d8585790d	Pending	Gift Card	South America	Jason Nelson	2024-07-19	1	1	114.412952	24.29	4	114.412952
71d7b5c1-51ba-4446-94b7-87cd380b3151	Returned	Amazon Pay	Asia	Steven Coleman	2021-01-05	1	1	78.05223000000001	22.22	5	78.05223000000001
71db312b-1a86-42f6-acad-198f05fba879	Pending	Debit Card	South America	Bradley Howe	2019-09-20	1	1	1249.781184	29.17	8	1249.781184
71fc5d7e-1c71-47e9-ba55-6e1506b376a4	Pending	PayPal	Australia	Jason Nelson	2023-10-26	1	1	1191.037608	24.13	6	1191.037608
72179f26-f5b9-4123-9d5e-7a734b833cb4	Cancelled	PayPal	Australia	Caleb Camacho	2023-03-21	1	1	1205.801904	2.67	4	1205.801904
722d0f7c-b5c3-472e-a0c0-d5ed40144897	Pending	Debit Card	Asia	Bradley Howe	2024-04-04	1	1	576.460152	7.66	2	576.460152
723d5795-0050-4859-9fbf-d4bcab84406d	Returned	Amazon Pay	Europe	Emily Matthews	2021-09-04	1	1	3315.015088	0.71	8	3315.015088
723ee71e-f287-47b2-9749-7d1ff82306f4	Returned	Debit Card	Asia	Jason Nelson	2021-02-11	1	1	666.7461000000001	14.5	2	666.7461000000001
72784a11-1afd-4162-8eb6-0ddd4fde6299	Pending	Debit Card	Europe	Caleb Camacho	2020-06-16	1	1	2067.904482	10.89	6	2067.904482
727a900c-40b7-4368-a71b-381148faec6f	Returned	Gift Card	Europe	Steven Coleman	2024-04-25	1	1	1375.7466520000005	14.36	7	1375.7466520000005
727eeb11-6450-45bb-92fe-94997089006f	Returned	Credit Card	South America	Diane Andrews	2022-12-12	1	1	1396.892432	2.81	4	1396.892432
729e2d66-dd74-46b1-aac7-9e8cf389cc56	Returned	Debit Card	Europe	Sandra Luna	2019-11-21	1	1	828.2311199999999	6.8	2	828.2311199999999
72f817ee-96e7-468f-99ec-1a7353aae509	Returned	Credit Card	Australia	Jason Nelson	2022-10-04	1	1	2249.10534	22.7	6	2249.10534
72fb0dd5-9cca-4645-9ad1-3a4b1de23892	Returned	Debit Card	Asia	Roger Brown	2020-08-11	1	1	1562.45232	29.96	8	1562.45232
72fdfbc4-556b-4828-ad7a-a8797f7a7b19	Pending	Gift Card	Europe	Steven Coleman	2020-02-25	1	1	239.234688	1.44	3	239.234688
7304d45f-52f8-4435-b09b-11b0aa55109c	Pending	Amazon Pay	Asia	Kristen Ramos	2021-05-22	1	1	2395.9642	1.7	5	2395.9642
73179ae6-a510-4f63-a988-5e4dc50a9086	Pending	Amazon Pay	Australia	Charles Smith	2023-11-03	1	1	2890.9232	26.96	10	2890.9232
7334c3d3-0401-4fa2-8e54-4097658004bd	Cancelled	Debit Card	South America	Diane Andrews	2019-06-29	1	1	2835.062592	23.38	8	2835.062592
73374b68-2013-4d56-8750-a3eaef509f13	Pending	Debit Card	Asia	Emily Matthews	2021-10-31	1	1	403.299092	6.12	7	403.299092
73470946-4137-4acf-88e9-62f6a460af15	Returned	Debit Card	North America	Steven Coleman	2021-10-17	1	1	345.410794	15.17	1	345.410794
7368589f-0c81-400b-bf2b-e1204cfe6b2d	Returned	Debit Card	North America	Michelle Andersen	2022-01-15	1	1	3340.333512	1.68	9	3340.333512
73689bc7-8408-47ea-a926-9831b5fa11bc	Cancelled	Gift Card	Australia	Diane Andrews	2021-01-21	1	1	3526.2672	18.07	10	3526.2672
73771dff-8546-4528-b324-1c2408679303	Cancelled	Debit Card	South America	Charles Smith	2023-04-02	1	1	332.50581	27.13	2	332.50581
737d4731-8aca-4e2c-9f6d-ee2f0f7ed9f7	Returned	Gift Card	Australia	Michelle Andersen	2024-02-14	1	1	381.458532	23.56	1	381.458532
737da183-1358-47f8-9970-030202786ea0	Pending	Debit Card	Asia	Jason Nelson	2020-06-06	1	1	539.054703	2.71	3	539.054703
7383f5a3-01bc-4c8e-82c3-5a620934cb44	Cancelled	Gift Card	Asia	Mary Scott	2021-01-07	1	1	626.006028	20.61	6	626.006028
738524f6-988f-48dc-a632-5883c3efd28f	Returned	Debit Card	South America	Mary Scott	2020-03-10	1	1	881.06598	2.9	2	881.06598
738546c8-1f0f-41d8-b0a0-b701e5c0388c	Pending	PayPal	Asia	Crystal Williams	2019-12-26	1	1	916.638126	22.98	3	916.638126
7389cd7a-8db1-4cfa-a9a4-8a40810efed7	Returned	Amazon Pay	Asia	Caitlyn Boyd	2023-05-19	1	1	245.60550000000003	20.9	5	245.60550000000003
739afcd2-c80f-44d1-8f05-85297e1e90a2	Returned	Gift Card	South America	Diane Andrews	2023-10-05	1	1	105.419664	11.62	4	105.419664
739b7a48-0ccb-4523-8868-f0471c8614e4	Cancelled	Debit Card	North America	Diane Andrews	2020-06-27	1	1	2218.362368	27.44	8	2218.362368
73a2c1c9-8b98-494a-b353-df72234c3135	Returned	Debit Card	North America	Diane Andrews	2020-05-08	1	1	834.166656	13.84	2	834.166656
73acce27-cae4-4282-81f5-f5619271b0b0	Pending	Debit Card	North America	Joseph Brooks	2019-01-24	1	1	357.537942	15.06	1	357.537942
73aede50-d4e8-4ad1-9e5c-8389ec26bcc4	Returned	PayPal	Australia	Michelle Garza	2022-06-11	1	1	3049.4100780000003	14.77	9	3049.4100780000003
73b97598-538a-4f8f-b8f7-a9cac536d67e	Returned	Gift Card	Asia	Roger Brown	2024-09-19	1	1	1319.085216	13.09	9	1319.085216
73bd86ea-bb6c-44a2-bf9b-34996569b411	Cancelled	Gift Card	South America	Diane Andrews	2021-04-29	1	1	412.717758	27.11	2	412.717758
73c7ad92-8743-4f9c-9050-9af734b60a57	Cancelled	Debit Card	Australia	Joseph Brooks	2021-04-04	1	1	778.4536759999999	15.47	4	778.4536759999999
73d23378-62a2-466a-928d-d02316807e67	Returned	Debit Card	Asia	Adam Smith	2021-09-23	1	1	187.67793	28.01	2	187.67793
73f5f755-fb57-42da-b409-c6c5abca5fc6	Cancelled	Credit Card	Australia	Johnny Marshall	2022-06-29	1	1	648.72928	29.4	8	648.72928
7471d22a-a69a-4e89-ad42-9e415179b617	Returned	Credit Card	Australia	Christina Thompson	2021-06-13	1	1	280.37568	26.68	2	280.37568
7480b420-2868-4c2c-acec-e0a89928af15	Returned	Amazon Pay	North America	Joseph Brooks	2019-07-31	1	1	202.02772500000003	25.05	1	202.02772500000003
7485da82-053b-46ea-9774-d1c3b28a8f05	Cancelled	Credit Card	North America	Christina Thompson	2019-02-05	1	1	1138.717176	25.83	4	1138.717176
749f7460-9462-4937-b213-95d32d404282	Pending	Credit Card	Australia	Michelle Garza	2019-07-06	1	1	1734.112548	19.64	9	1734.112548
74a6ae6f-3fe8-4a12-9a1f-c8f3afdd1a6c	Cancelled	Amazon Pay	Asia	Diane Andrews	2021-10-22	1	1	2394.96372	18.85	8	2394.96372
74d3c72c-9212-4472-8434-debfd5ba765c	Cancelled	Credit Card	South America	Susan Edwards	2023-08-15	1	1	461.33295	10.25	3	461.33295
74d56b23-0e75-4d5f-a3dd-2702ca725530	Returned	Gift Card	Europe	Susan Edwards	2020-08-03	1	1	1670.6940479999998	27.96	9	1670.6940479999998
74e4e594-8344-4c13-97a4-8cbde260fa89	Pending	Debit Card	Asia	Emily Matthews	2024-05-31	1	1	652.447992	11.13	3	652.447992
75040cce-6123-4cfa-8261-c9a22ead733f	Returned	Debit Card	North America	Susan Edwards	2024-04-20	1	1	1659.7620000000002	20.05	6	1659.7620000000002
75108239-d8e9-444a-8de4-7995c344a0b0	Pending	Debit Card	Asia	Caleb Camacho	2019-06-21	1	1	344.8049	8.15	2	344.8049
751d27b3-3ea4-492b-a38f-d52605052e58	Cancelled	Credit Card	Asia	Christina Thompson	2023-09-11	1	1	1510.1648250000003	8.71	5	1510.1648250000003
753e6d02-30b7-454c-8f1f-266457eed7a7	Pending	Credit Card	Europe	Kristen Ramos	2023-11-05	1	1	1853.15584	18.32	8	1853.15584
7559856b-46a3-4f24-b6f6-1e5c57342a5b	Cancelled	Debit Card	North America	Susan Edwards	2020-07-28	1	1	2023.50492	7.48	10	2023.50492
7567b681-55a3-4538-b993-407e55cd0a95	Returned	PayPal	North America	Adam Smith	2020-12-11	1	1	251.62368	1.44	2	251.62368
75708fce-66a5-41ed-8f6d-e2bf104312c1	Pending	Credit Card	Australia	Kristen Ramos	2023-10-30	1	1	111.28752	11.36	9	111.28752
7579b4b7-3085-43a0-b590-7827fedeac1e	Returned	Gift Card	Europe	Caleb Camacho	2021-06-28	1	1	559.33074	2.36	9	559.33074
758110bd-7bb8-4d6d-9048-59df6587d2c0	Returned	Gift Card	North America	Caitlyn Boyd	2020-02-09	1	1	771.387624	6.58	6	771.387624
75aec33c-43af-41ba-a0e0-7c8f51f2ad2e	Returned	Debit Card	Asia	Jason Nelson	2022-12-14	1	1	1355.8810199999998	17.42	6	1355.8810199999998
75b98722-cc0e-450a-aaf5-e5c682806dc0	Returned	Amazon Pay	Asia	Susan Edwards	2023-05-07	1	1	2099.907928	19.77	8	2099.907928
7609feac-219e-4d41-a0ca-ba8f73729ad8	Pending	Gift Card	Australia	Christina Thompson	2023-09-10	1	1	1020.35934	27.19	7	1020.35934
762ff307-788a-4f41-aad5-e8ff1b4cdfae	Pending	Debit Card	South America	Crystal Williams	2023-10-14	1	1	2575.955448	28.83	8	2575.955448
763fcf76-c7cd-4d61-96d9-dddb489f831a	Returned	Amazon Pay	Asia	Joseph Brooks	2023-06-05	1	1	1892.708253	20.99	9	1892.708253
76448b9e-6a11-463a-9e66-84c72f251538	Cancelled	Amazon Pay	Europe	Diane Andrews	2021-10-12	1	1	1429.14618	15.58	10	1429.14618
7648faca-b543-4b48-bdb5-a57fbc663dca	Pending	PayPal	Asia	Susan Edwards	2020-09-27	1	1	330.87420000000003	22.33	6	330.87420000000003
7659a939-3ae8-4444-a3da-587563d878a3	Pending	PayPal	North America	Christina Thompson	2020-03-02	1	1	1369.8290500000005	2.19	5	1369.8290500000005
765a6b74-d05f-4d0b-ad76-cf349fbda756	Cancelled	Credit Card	Europe	Susan Edwards	2022-06-26	1	1	237.475584	17.44	3	237.475584
76a73fe4-ca55-4fcb-b66d-30dfe7dadf42	Returned	Gift Card	South America	Kristen Ramos	2024-09-11	1	1	686.1481200000001	19.85	8	686.1481200000001
76bf38d5-a5d0-4a20-b94c-609c1022797e	Pending	Credit Card	Asia	Jason Nelson	2024-12-23	1	1	1598.51301	7.26	5	1598.51301
76d9b2a8-96cd-440c-a4ff-d18d7f4443ed	Cancelled	Debit Card	North America	Emily Matthews	2021-09-26	1	1	155.893416	16.42	4	155.893416
770f99c9-1561-41ea-a44d-c311b00d900f	Returned	Amazon Pay	South America	Jason Nelson	2021-01-20	1	1	565.701696	3.12	9	565.701696
77452d6e-400f-4fad-a035-c89c9b8a4aa4	Returned	PayPal	Australia	Charles Smith	2020-08-06	1	1	2307.437496	19.01	8	2307.437496
774636b3-8865-4f4d-817d-56ae07680940	Cancelled	Amazon Pay	Asia	Christina Thompson	2023-06-14	1	1	1285.126496	4.98	8	1285.126496
774f7fb3-d951-4b63-814e-c3bbce24f081	Returned	Gift Card	South America	Susan Edwards	2019-07-06	1	1	2454.57936	1.47	9	2454.57936
77512900-9e4d-46d7-af55-7280587982ab	Returned	Gift Card	South America	Diane Andrews	2024-06-14	1	1	1595.38175	20.75	5	1595.38175
7786b28b-115e-4e6c-88bb-9210aba8b492	Pending	Credit Card	Europe	Mary Scott	2023-12-30	1	1	663.85216	18.9	8	663.85216
7790d795-adf5-4b2c-9a20-15bb9240409c	Cancelled	PayPal	Asia	Johnny Marshall	2021-04-28	1	1	326.35848200000004	25.46	1	326.35848200000004
77949e2b-7c8a-434e-8020-0c08697bfa38	Returned	Debit Card	South America	Jason Nelson	2024-01-16	1	1	943.29702	13.57	5	943.29702
77bcfc8c-5c78-4045-b888-295c0332d0a3	Cancelled	PayPal	North America	Jason Nelson	2021-10-27	1	1	345.056948	29.39	4	345.056948
77c893df-ce5c-4542-916f-fc8c64fd6e12	Cancelled	Credit Card	Europe	Michelle Garza	2020-07-23	1	1	3449.3577480000004	11.91	9	3449.3577480000004
77cebd61-f756-4234-bba6-463cb93c142a	Cancelled	Gift Card	Europe	Adam Smith	2024-04-16	1	1	43.019136	16.24	8	43.019136
77e2016a-216b-4ccf-b0fb-46a2b218791f	Cancelled	Gift Card	Australia	Michelle Garza	2021-10-08	1	1	875.13401	21.59	10	875.13401
77ec6df2-2bc2-4b75-be65-3682d8d6f988	Returned	Debit Card	Europe	Steven Coleman	2021-09-05	1	1	542.0537600000001	3.36	5	542.0537600000001
77f410f5-2cc3-4148-b5e8-787e3d75bc59	Cancelled	Gift Card	South America	Caleb Camacho	2023-11-15	1	1	1856.104096	6.72	7	1856.104096
77fbb48e-58ff-476b-a660-4ab6b739962c	Cancelled	Gift Card	Asia	Diane Andrews	2020-04-10	1	1	1527.1243399999998	20.55	4	1527.1243399999998
7815746a-a9dd-491d-947a-12521d42f5b1	Pending	Credit Card	Asia	Roger Brown	2020-07-21	1	1	261.29112	7.36	5	261.29112
781a55db-069c-4288-b9cc-f89deda3b4f0	Pending	Amazon Pay	Asia	Kristen Ramos	2021-01-15	1	1	1243.186768	4.76	4	1243.186768
7832a439-5f6a-4c11-af53-9dfdf14bff4b	Pending	PayPal	North America	Jason Nelson	2023-06-05	1	1	1287.81354	7.72	5	1287.81354
78393eee-c7c8-42f3-99e5-59861f82faf9	Cancelled	Gift Card	North America	Jason Nelson	2022-02-16	1	1	856.862464	14.24	2	856.862464
7846f2ea-2bf2-4e24-98e2-f5ef66f73d41	Pending	Debit Card	North America	Roger Brown	2020-07-15	1	1	1158.237582	16.89	6	1158.237582
78488d59-608c-43b8-8f66-70273c3617c6	Returned	Credit Card	Australia	Adam Smith	2020-06-17	1	1	2415.4487	1.37	5	2415.4487
785a6d1a-fd2e-4aa2-bcb6-5b23c6e79b70	Pending	Debit Card	Australia	Adam Smith	2024-10-19	1	1	3375.2523	0.17	10	3375.2523
786a080f-c628-4388-863d-92e2006ae946	Cancelled	Credit Card	Asia	Michelle Garza	2019-07-31	1	1	49.85442	16.07	1	49.85442
7872504e-c800-421b-9d5b-5c038e1c447f	Cancelled	Gift Card	Asia	Sandra Luna	2020-09-18	1	1	422.29626	21.71	4	422.29626
7875dda0-6590-4098-9ba3-65d0926b38bf	Cancelled	Gift Card	South America	Sandra Luna	2020-11-24	1	1	376.22046	5.78	2	376.22046
78780f94-f0a0-48b1-9484-0da6475b5405	Pending	Amazon Pay	Europe	Roger Brown	2021-12-12	1	1	951.39408	4.32	3	951.39408
787b837e-de0e-4d48-8839-5415cc2ba14e	Pending	Credit Card	South America	Michelle Garza	2021-01-05	1	1	741.928752	2.68	6	741.928752
787f0c28-c398-4dde-bf17-b8e3b6cd60fa	Returned	Gift Card	Asia	Adam Smith	2019-11-25	1	1	108.338115	6.95	1	108.338115
7881edcf-7e25-44ed-93be-50724dc58110	Cancelled	Credit Card	South America	Kristen Ramos	2020-01-03	1	1	1965.82866	10.98	6	1965.82866
788783e5-baa5-400a-94af-160fbcff1a89	Cancelled	Credit Card	South America	Michelle Andersen	2024-09-22	1	1	2551.0128400000003	14.43	10	2551.0128400000003
7888bfeb-fde5-4a72-971d-2a89cf6bcf45	Cancelled	Amazon Pay	Europe	Mary Scott	2024-01-27	1	1	799.18377	4.74	3	799.18377
7897ed41-2553-4e1b-b7ff-7c0afa25c181	Pending	Amazon Pay	North America	Kristen Ramos	2023-03-14	1	1	1465.58852	14.64	5	1465.58852
7898c05c-bc8c-41c1-85d0-3f2364462335	Pending	Gift Card	South America	Susan Edwards	2022-12-16	1	1	336.40704	13.6	1	336.40704
789ae0e9-7d29-4d59-92fd-2a94c46c1650	Cancelled	Debit Card	North America	Sandra Luna	2020-11-14	1	1	1510.44229	5.34	7	1510.44229
789c9ead-0563-4d20-a05a-3f43770752e9	Returned	PayPal	Europe	Caitlyn Boyd	2021-05-20	1	1	367.657056	27.26	6	367.657056
78aba900-64fc-4d3c-a15b-742e87d76039	Pending	Credit Card	Europe	Caitlyn Boyd	2022-03-17	1	1	721.087794	13.83	3	721.087794
78bdcc41-ede8-444e-866c-d21a9015934b	Cancelled	Amazon Pay	Australia	Johnny Marshall	2023-04-08	1	1	541.486176	13.82	6	541.486176
78d62c79-4255-4e0a-89b6-57ca7248cd97	Cancelled	Gift Card	South America	Sandra Luna	2022-08-16	1	1	2905.0358400000005	9.28	10	2905.0358400000005
78f5fcb4-195d-478c-ac99-f0bfffe9dcae	Pending	PayPal	Europe	Adam Smith	2023-08-22	1	1	295.67124	23.8	1	295.67124
78fb4adb-37df-4d63-9a42-1d1ccad836b6	Returned	PayPal	Australia	Emily Matthews	2024-10-07	1	1	225.821466	25.19	9	225.821466
78fbfa53-d513-4f40-9c4b-df427b1f7a6c	Returned	Debit Card	Asia	Caleb Camacho	2021-08-23	1	1	551.4075	21.25	9	551.4075
78fda0fb-4009-4aeb-9286-f9c482075860	Pending	PayPal	South America	Johnny Marshall	2022-12-27	1	1	2150.286138	13.54	7	2150.286138
7919a06a-9661-4a13-9763-0492a98e1546	Pending	PayPal	Europe	Joseph Brooks	2023-10-02	1	1	1847.277636	12.23	6	1847.277636
792b2087-7a53-4e0a-82bd-fb760bb74e76	Returned	PayPal	North America	Michelle Andersen	2023-01-17	1	1	1126.7488379999998	12.06	3	1126.7488379999998
79309576-ac1a-4fcb-aa26-fb4193c54993	Cancelled	Amazon Pay	Asia	Caleb Camacho	2024-10-14	1	1	2727.15498	24.94	10	2727.15498
793a4f75-b2b6-4f4d-93a1-5169244b9c19	Cancelled	Amazon Pay	North America	Kristen Ramos	2022-09-21	1	1	1484.281664	20.84	8	1484.281664
794d31c4-71a8-4382-892e-677b670899e6	Returned	Amazon Pay	Asia	Emily Matthews	2024-10-19	1	1	732.52293	19.21	10	732.52293
795597fd-dd7f-4939-a58f-54fd7d8d3de7	Cancelled	Debit Card	Australia	Christina Thompson	2020-02-24	1	1	1089.899668	22.13	4	1089.899668
79708af8-7395-4a25-8c0a-b4a328941890	Cancelled	Debit Card	Asia	Susan Edwards	2020-03-16	1	1	1482.520284	27.86	6	1482.520284
7974d417-aa10-46fb-ae49-6411a2801b82	Returned	PayPal	Europe	Emily Matthews	2019-08-28	1	1	1439.25348	26.01	10	1439.25348
7980143b-c393-4bd1-82a9-6c5a7fc2a8ca	Cancelled	Credit Card	Asia	Joseph Brooks	2022-07-11	1	1	2296.869855	22.07	7	2296.869855
79881e1a-7dbc-48d0-9dfe-3d0b866a8846	Returned	Amazon Pay	North America	Mary Scott	2019-08-13	1	1	163.848987	23.41	9	163.848987
798e4102-66de-4d80-89e8-1714e6ea0539	Returned	Debit Card	South America	Caitlyn Boyd	2020-05-22	1	1	1012.632576	10.91	4	1012.632576
79957b72-b3c7-4c3e-9381-891b342a9026	Returned	PayPal	Australia	Caleb Camacho	2024-08-09	1	1	956.622576	18.31	4	956.622576
79c569e5-7957-40b8-a169-829aab2406c2	Pending	Amazon Pay	Australia	Diane Andrews	2020-10-15	1	1	1068.4665599999998	11.36	10	1068.4665599999998
79c593f0-6c0e-43e9-be91-be37fc33cd2a	Pending	Amazon Pay	North America	Bradley Howe	2023-02-03	1	1	2387.4318	29	9	2387.4318
79cca0c9-cd89-4253-b329-eeda075b0c49	Pending	PayPal	Europe	Caleb Camacho	2020-06-15	1	1	2261.462112	29.56	7	2261.462112
79d05582-7e19-4821-9a99-f7b5c98542d2	Returned	PayPal	North America	Michelle Andersen	2020-11-03	1	1	207.93479399999995	16.26	3	207.93479399999995
79ea3410-88db-42f3-b3a6-6dc6fd615a5c	Pending	PayPal	Europe	Charles Smith	2022-12-16	1	1	605.0714399999999	18.41	10	605.0714399999999
79f77b23-12a9-4c45-865e-c4b21e71a86f	Pending	Credit Card	South America	Bradley Howe	2019-05-23	1	1	314.131168	10.56	2	314.131168
7a0baabd-c5a5-445e-807a-a75c9b04c34f	Cancelled	Credit Card	Australia	Charles Smith	2020-08-07	1	1	397.211724	1.69	2	397.211724
7a3a6792-9f88-4220-9abb-c583fc179c9b	Pending	Amazon Pay	North America	Kristen Ramos	2023-04-26	1	1	523.33246	13.67	10	523.33246
7a40d7bd-9f11-498e-bb6c-47299931ce31	Returned	Debit Card	North America	Caitlyn Boyd	2023-01-12	1	1	804.77664	16.6	8	804.77664
7a4c7c34-6419-4c4f-b045-0b2eb8b04221	Cancelled	PayPal	Australia	Charles Smith	2021-08-28	1	1	772.515114	15.18	3	772.515114
7a4e9d4c-eb3c-4552-9e18-18ff027da9c8	Cancelled	Credit Card	North America	Joseph Brooks	2019-08-30	1	1	127.800507	9.79	1	127.800507
7a5a06bd-d3d9-4413-96b8-0508836c2d89	Returned	Amazon Pay	Asia	Charles Smith	2022-07-19	1	1	1522.5588000000002	22.04	4	1522.5588000000002
7aaaf271-7511-4ab1-9621-cd49dc24cfb9	Returned	Gift Card	Asia	Roger Brown	2022-06-12	1	1	770.613248	0.98	2	770.613248
7ab324c5-4414-4dba-854a-3295f3230efb	Returned	Credit Card	Asia	Charles Smith	2022-12-25	1	1	2690.2257199999995	16.67	10	2690.2257199999995
7ac2fcac-096f-479a-a6ad-335bc5fd9479	Cancelled	PayPal	North America	Michelle Andersen	2023-02-03	1	1	194.22234	14.59	5	194.22234
7ac6d52f-d031-46fc-9f38-208a39f02715	Pending	Amazon Pay	South America	Adam Smith	2019-07-30	1	1	367.730718	12.19	1	367.730718
7add8bac-9892-436a-a67d-c7b44095d594	Pending	Debit Card	Asia	Sandra Luna	2022-03-04	1	1	359.12775600000003	21.43	4	359.12775600000003
7aee6b40-7141-4a84-8725-e22d9c81d231	Pending	PayPal	South America	Crystal Williams	2022-05-08	1	1	1257.642414	9.98	3	1257.642414
7af1f96b-11e9-44b1-abc4-1df37afcb019	Cancelled	Credit Card	North America	Bradley Howe	2022-10-08	1	1	224.653473	29.89	3	224.653473
7b12842d-cf36-4adc-a15b-1d632d76dd15	Returned	Amazon Pay	North America	Mary Scott	2023-09-05	1	1	572.796096	6.82	8	572.796096
7b2acc06-6343-47e7-9b7a-838def45fecb	Returned	Credit Card	South America	Sandra Luna	2024-06-24	1	1	2527.973712	17.92	9	2527.973712
7b483589-371c-460b-a31f-621852676533	Cancelled	Gift Card	Australia	Susan Edwards	2020-09-28	1	1	201.356904	24.56	1	201.356904
7b5ac5cb-2cb0-4570-9de6-89460c26455a	Returned	Gift Card	Asia	Caitlyn Boyd	2019-06-05	1	1	659.88702	18.26	10	659.88702
7b694715-8e9e-40e9-ae35-b710128e45b6	Cancelled	Debit Card	Asia	Bradley Howe	2022-11-30	1	1	1941.710645	15.05	7	1941.710645
7ba50298-d875-4179-862c-ad1f613c7a47	Cancelled	Debit Card	Asia	Bradley Howe	2019-11-17	1	1	673.5241799999999	12.37	6	673.5241799999999
7bc2d219-30e0-45a3-bc39-c31fe296a738	Cancelled	Amazon Pay	Asia	Joseph Brooks	2021-08-12	1	1	2185.29792	27.04	10	2185.29792
7be2652d-6010-4e59-9d93-7ae85f109081	Returned	Credit Card	Europe	Adam Smith	2024-06-08	1	1	1219.99716	8.95	3	1219.99716
7c0ad6df-e356-48fd-b823-16f7e1589013	Cancelled	PayPal	Asia	Roger Brown	2022-04-12	1	1	267.856488	18.91	1	267.856488
7c3efdec-6d18-4e08-9425-6694f03f2896	Pending	Gift Card	South America	Michelle Andersen	2019-05-15	1	1	4329.07959	6.23	10	4329.07959
7c6632c1-d27a-49a4-b9ff-d1bd568c34d8	Pending	PayPal	North America	Jason Nelson	2022-04-06	1	1	1387.309	3.75	4	1387.309
7c6d4062-36fc-4c5d-944b-1ae6d9508814	Pending	Amazon Pay	Australia	Caleb Camacho	2023-04-06	1	1	278.906628	17.61	6	278.906628
7c782449-5b06-4b12-ae9c-2a9f6b8e0324	Cancelled	Amazon Pay	Australia	Adam Smith	2021-04-27	1	1	2562.272784	14.02	9	2562.272784
7c87d5b5-291e-46a8-9fcd-74c43bfb640f	Cancelled	PayPal	North America	Emily Matthews	2021-07-17	1	1	718.4130240000001	7.64	8	718.4130240000001
7c8b6ca3-1c6b-4736-b73b-817ff0279605	Returned	Credit Card	Europe	Caleb Camacho	2021-12-05	1	1	750.44608	15.2	8	750.44608
7cb87be2-68ec-48e9-bb30-ec431bd06bb9	Cancelled	Credit Card	Europe	Mary Scott	2023-02-13	1	1	2282.6900880000003	15.72	6	2282.6900880000003
7cd9cf3a-1d1d-4662-8920-f526986e6c05	Returned	Debit Card	Europe	Sandra Luna	2019-08-25	1	1	622.654776	11.62	6	622.654776
7cf67ebc-90c3-4c85-8753-54f1d41f09e4	Returned	Credit Card	Europe	Caitlyn Boyd	2023-04-13	1	1	444.938232	13.49	2	444.938232
7cfbf6c5-18f6-4d5a-874a-c7c13a01dac3	Returned	Debit Card	Asia	Caitlyn Boyd	2023-09-22	1	1	394.333912	4.26	4	394.333912
7d08df3c-09fb-4203-90a9-f1f6a8dc3cdc	Returned	Gift Card	Australia	Joseph Brooks	2024-09-07	1	1	3076.742242	4.37	7	3076.742242
7d22e8b6-55bb-410a-a26b-cd392cf467e5	Cancelled	Amazon Pay	Australia	Diane Andrews	2023-11-03	1	1	326.97894599999995	15.47	7	326.97894599999995
7d2fda49-432b-4a5f-a987-fef1306dc1e8	Pending	Debit Card	Australia	Caleb Camacho	2022-06-27	1	1	789.829656	28.39	4	789.829656
7d3594f5-d64b-4727-87aa-e9184f5c7a2c	Pending	Debit Card	South America	Mary Scott	2024-09-27	1	1	380.592576	28.76	8	380.592576
7d3629e9-e8e0-432d-81ce-75b5136592b1	Pending	Debit Card	South America	Emily Matthews	2022-11-15	1	1	2262.670624	14.66	8	2262.670624
7d430854-bdd3-4742-b981-4525e7e1d7a9	Returned	Debit Card	South America	Steven Coleman	2020-11-15	1	1	400.498816	6.18	1	400.498816
7d74e842-8ba0-46e6-89a1-30a32859f9bc	Returned	Debit Card	Australia	Steven Coleman	2023-03-04	1	1	2143.7088750000003	1.45	5	2143.7088750000003
7db8d786-da76-4fb4-9c64-3074322a4f4c	Cancelled	PayPal	South America	Emily Matthews	2020-11-25	1	1	4405.16853	1.3	9	4405.16853
7dc9612e-c0d9-4e5c-8e26-aa44d8ae9872	Returned	Gift Card	Asia	Caitlyn Boyd	2019-08-10	1	1	808.7150399999999	18.45	4	808.7150399999999
7de3c075-df05-4727-8e2c-c27e37d25f84	Pending	Gift Card	South America	Emily Matthews	2019-06-24	1	1	2237.935336	26.16	7	2237.935336
7e03c6ec-3387-416b-86ef-8a06241c1744	Returned	PayPal	South America	Charles Smith	2022-02-17	1	1	548.01472	8.42	5	548.01472
7e2f3f4e-1628-4074-bd26-07c814953a3e	Pending	Debit Card	South America	Caleb Camacho	2020-06-27	1	1	1259.80424	14.52	5	1259.80424
7e4ab057-440e-4ea5-a860-3d156ee355ba	Returned	Credit Card	North America	Caleb Camacho	2019-06-02	1	1	856.9837150000001	6.05	7	856.9837150000001
7e524a55-b28e-4660-afa6-3bd412d88cc7	Cancelled	PayPal	Asia	Diane Andrews	2021-06-13	1	1	4190.907279999999	9.84	10	4190.907279999999
7e537f9e-6896-4a32-afa4-36a90bef1149	Pending	Gift Card	North America	Emily Matthews	2022-03-25	1	1	587.179446	13.27	2	587.179446
7e5eb089-6209-4f8b-bade-bb2475939b49	Pending	Gift Card	Europe	Kristen Ramos	2022-04-25	1	1	2360.068746	13.19	6	2360.068746
7e62412e-6a29-4b6d-b0c3-16e9dd26ac3e	Pending	Gift Card	Australia	Adam Smith	2019-06-30	1	1	2707.302528	29.92	9	2707.302528
7e6de08f-d82a-4e69-ad92-9b86d6de3e55	Returned	PayPal	South America	Bradley Howe	2021-01-29	1	1	1623.1279679999998	18.38	6	1623.1279679999998
7e72d229-17e2-4e6e-bf68-4e09e7236eba	Returned	Credit Card	South America	Steven Coleman	2022-04-06	1	1	1732.3264	21.6	10	1732.3264
7e762d34-076f-49ac-862f-5ebefb9dda24	Returned	Credit Card	South America	Christina Thompson	2020-10-16	1	1	269.54767000000004	19.61	7	269.54767000000004
7e806b86-9e3e-4abe-a4fc-90d616563ca9	Cancelled	Gift Card	South America	Christina Thompson	2019-08-11	1	1	596.55941	0.59	2	596.55941
7e8f36eb-57e4-4e4c-9255-07ea04bad0d2	Returned	Credit Card	Europe	Crystal Williams	2019-07-19	1	1	972.144235	3.81	5	972.144235
7ea5be90-cdbc-432f-9c48-949b455a20d1	Pending	Credit Card	Australia	Sandra Luna	2020-03-09	1	1	213.9501	22.65	5	213.9501
7ee24b15-abbf-4f50-b15f-57778edcbb0c	Pending	Gift Card	South America	Mary Scott	2021-01-28	1	1	760.31681	26.19	10	760.31681
7ee5ef75-f507-4ffd-8dd9-1e596f9e215c	Pending	Debit Card	Asia	Sandra Luna	2020-01-06	1	1	1448.44744	26.19	4	1448.44744
7ef6496a-721b-4103-8bf2-44589d38bbb9	Returned	Amazon Pay	Asia	Jason Nelson	2022-06-22	1	1	1682.35487	27.83	5	1682.35487
7effe24f-efb0-4dfb-94ab-169d99a26409	Returned	PayPal	Australia	Crystal Williams	2021-05-09	1	1	824.0624399999999	2.6	6	824.0624399999999
7f0f1960-16ee-418a-b073-2b6cfa34a25f	Cancelled	Credit Card	South America	Kristen Ramos	2020-05-15	1	1	817.750728	21.86	4	817.750728
7f190a6f-3a54-4030-8e9c-464883bd1242	Cancelled	Debit Card	Australia	Michelle Andersen	2022-07-14	1	1	295.142121	17.79	3	295.142121
7f1ffc3b-809e-476c-b8d1-8b4efb8907e4	Returned	PayPal	South America	Caitlyn Boyd	2024-08-25	1	1	953.563221	20.59	3	953.563221
7f272a68-7c2f-4caa-a9f1-22a01f8cae90	Returned	Credit Card	Asia	Steven Coleman	2021-02-22	1	1	1264.563168	17.08	8	1264.563168
7f473c31-d60a-4ddd-b288-db98cab9f7f8	Cancelled	Debit Card	Europe	Roger Brown	2020-01-08	1	1	901.59771	8.35	2	901.59771
7f574e7a-1227-4545-a059-42482d02595c	Returned	Debit Card	Europe	Jason Nelson	2021-01-20	1	1	1122.007104	15.43	3	1122.007104
7f57a442-6aa8-42da-9ecd-c29ed3a6051f	Pending	PayPal	Asia	Charles Smith	2020-01-01	1	1	1453.3865	3.5	5	1453.3865
7f796b9f-ee2f-40dd-aa29-a2024bc30fcd	Returned	Debit Card	South America	Adam Smith	2022-10-15	1	1	410.882038	14.51	2	410.882038
7fb99ad9-bd95-44a1-9d08-b0e2edb9e26a	Cancelled	Credit Card	North America	Michelle Andersen	2020-07-23	1	1	232.868601	3.61	3	232.868601
7fbe3a6f-6c66-46b2-9098-b14a6f504681	Pending	Debit Card	Asia	Roger Brown	2023-02-23	1	1	1956.04448	7.52	10	1956.04448
7fc67566-4ac7-4da1-b32b-64736343d8f6	Cancelled	Credit Card	South America	Steven Coleman	2019-04-02	1	1	565.703908	25.53	7	565.703908
7fcbb3d1-4614-4c62-94e6-5673e4eb007d	Cancelled	Credit Card	Asia	Joseph Brooks	2019-01-24	1	1	136.839948	20.34	1	136.839948
7fcc1a57-f10a-4826-b6c6-d29f74e17c39	Returned	Debit Card	Europe	Adam Smith	2023-06-03	1	1	750.886872	16.44	2	750.886872
7ffd22ae-2076-4584-893e-26f03a63f3e1	Cancelled	Debit Card	Europe	Charles Smith	2020-10-21	1	1	901.8984	17.71	5	901.8984
80143100-04c5-40c3-8fa8-05f12e22c49e	Returned	Debit Card	Australia	Michelle Andersen	2022-01-07	1	1	866.289204	7.82	9	866.289204
80179c55-c6e6-45d0-85a5-a0f857d60c8b	Returned	Debit Card	South America	Diane Andrews	2020-07-12	1	1	2753.97696	18.2	9	2753.97696
8028fad7-a20b-4d2c-993b-ca89bdd7a106	Returned	Amazon Pay	Asia	Christina Thompson	2020-12-31	1	1	2315.80923	2.74	5	2315.80923
802a03a8-d397-4b05-952e-09fb3bbb523f	Cancelled	PayPal	South America	Sandra Luna	2023-11-29	1	1	1399.1238	8.2	10	1399.1238
802f6c99-7f8c-48fb-a24d-f6f97a6dd5ee	Pending	PayPal	Europe	Diane Andrews	2020-05-10	1	1	452.476248	4.83	8	452.476248
80347d7b-87ab-4009-9c5b-62339e641202	Pending	Debit Card	Asia	Kristen Ramos	2020-03-18	1	1	53.645328000000006	23.32	6	53.645328000000006
803ad8d8-fa9e-4bf4-b9b5-9d7e5ad9383b	Returned	Credit Card	Australia	Adam Smith	2022-10-08	1	1	2383.8299100000004	19.15	6	2383.8299100000004
803ea998-cdcb-43c1-b9f0-b3beb5328826	Returned	Credit Card	North America	Mary Scott	2023-07-04	1	1	1510.03062	3.74	5	1510.03062
8041ec9f-3021-4f2a-88ba-1e7aedb08777	Returned	Amazon Pay	Australia	Emily Matthews	2022-07-21	1	1	76.85506199999999	28.58	3	76.85506199999999
8055332f-4cc3-40fc-a2a0-07087fd74003	Returned	Credit Card	Asia	Diane Andrews	2019-02-16	1	1	1595.1520799999998	13.57	6	1595.1520799999998
8067d1e6-e950-4214-84b8-304adcd209d1	Returned	Debit Card	Australia	Sandra Luna	2019-05-29	1	1	2032.43838	23.31	6	2032.43838
8078da80-183a-4a07-8169-3eaa31f8e249	Returned	Debit Card	Europe	Diane Andrews	2021-02-05	1	1	33.355611	28.59	3	33.355611
807b186f-2463-4603-93fb-dab38b2513e4	Cancelled	Debit Card	Australia	Mary Scott	2020-11-09	1	1	355.291524	6.63	9	355.291524
8080e9b2-d0c2-4c50-885d-083cd77ba538	Cancelled	Gift Card	South America	Michelle Garza	2024-04-22	1	1	2786.2003300000006	5.69	10	2786.2003300000006
809b7903-f954-4618-bd83-d55697b8e601	Cancelled	Amazon Pay	Asia	Michelle Andersen	2020-01-16	1	1	170.498968	12.69	1	170.498968
80a10a31-7a45-4cd4-b0e9-ac7b673fe148	Returned	Credit Card	North America	Adam Smith	2022-01-30	1	1	1245.600207	4.51	3	1245.600207
80b9e452-5b23-4fa8-bd2f-d05b9447082b	Returned	Debit Card	North America	Jason Nelson	2020-04-27	1	1	278.283005	17.19	1	278.283005
80c316a3-eadc-4ba9-b1a0-76d20a38b09c	Cancelled	Amazon Pay	South America	Caitlyn Boyd	2020-07-27	1	1	225.803172	2.78	6	225.803172
80c59908-178b-4ca3-b0e2-1399330fe937	Pending	Gift Card	South America	Kristen Ramos	2023-11-09	1	1	587.7118620000001	9.73	3	587.7118620000001
80cfc0ba-4be9-49fb-a34f-94daacd1b079	Cancelled	PayPal	Australia	Susan Edwards	2024-07-06	1	1	35.979096	8.24	1	35.979096
80ef037b-a4ec-4669-8591-dc6b8f120e50	Cancelled	Credit Card	North America	Steven Coleman	2023-11-07	1	1	2244.554325	26.81	9	2244.554325
80fbe95d-3a8c-4b67-b2d9-4987117c0327	Returned	Gift Card	Australia	Roger Brown	2019-01-20	1	1	189.578298	6.27	3	189.578298
8104ff92-94d7-469c-b7d1-dcdcf697e76b	Cancelled	Debit Card	South America	Christina Thompson	2022-09-24	1	1	233.45295	18.7	1	233.45295
8107ccf4-1ade-4a05-a5be-ff5b97b8b206	Cancelled	PayPal	Asia	Michelle Garza	2024-05-23	1	1	2011.85832	6.46	5	2011.85832
8128a4a9-cc17-4cdf-a4e8-402bfad40e8f	Returned	Debit Card	Asia	Charles Smith	2019-07-01	1	1	2005.334784	13.36	6	2005.334784
814106df-d96d-444c-abca-d8ad12c4f90c	Pending	Debit Card	Asia	Emily Matthews	2019-01-31	1	1	1806.240975	10.05	5	1806.240975
8145e591-86f7-4e5b-8a41-9eab282ff4cf	Pending	PayPal	North America	Michelle Garza	2020-12-01	1	1	4139.078832	7.74	9	4139.078832
815d8b76-9078-4f56-a19d-de16ab0eb657	Cancelled	Gift Card	Europe	Kristen Ramos	2022-11-08	1	1	1070.690984	18.86	4	1070.690984
8168f34e-ab5c-4167-8e57-4aacd7501dc3	Pending	Amazon Pay	South America	Adam Smith	2022-05-13	1	1	1054.5312239999998	27.64	6	1054.5312239999998
81826695-cff0-4ff0-98fa-703582d5142d	Cancelled	Amazon Pay	South America	Johnny Marshall	2021-08-17	1	1	248.873648	18.69	4	248.873648
81b95ec3-d6f6-4955-b0bf-ecc3b3663a5a	Cancelled	PayPal	North America	Jason Nelson	2021-02-03	1	1	3240.150498	21.22	9	3240.150498
81b9ddbd-0ea0-4d79-afeb-e81792baa972	Pending	Debit Card	South America	Susan Edwards	2021-10-01	1	1	1018.38152	17.58	4	1018.38152
81c16d08-b457-4d31-8b74-b0e35885bddf	Returned	Debit Card	Asia	Steven Coleman	2019-04-11	1	1	3001.16737	17.01	10	3001.16737
81cfb8b0-96db-4eb0-8158-1b8b1a175a83	Returned	PayPal	Europe	Mary Scott	2024-12-13	1	1	1895.976816	17.46	8	1895.976816
81dda0fd-20e1-4c90-9a6e-f14eed20bfbf	Cancelled	Debit Card	North America	Johnny Marshall	2024-04-02	1	1	715.2095999999999	22.93	8	715.2095999999999
81ee3c83-c3df-41f8-8b3a-9cd19995346b	Cancelled	Debit Card	North America	Christina Thompson	2022-06-30	1	1	454.904136	9.87	9	454.904136
81f8de3f-2829-4673-8109-383b2f72ca8c	Pending	PayPal	South America	Joseph Brooks	2020-11-13	1	1	224.27394	10.79	1	224.27394
81fe481e-c84b-4816-abca-d9ace9513642	Pending	Credit Card	Europe	Roger Brown	2023-04-07	1	1	688.621717	21.47	7	688.621717
81fe59c6-e171-4b6f-a0a6-5d59e81e40dd	Cancelled	PayPal	South America	Joseph Brooks	2019-02-01	1	1	2975.896836	18.71	9	2975.896836
821b1a90-582c-43bb-a780-56dcf1aa7b44	Pending	Debit Card	Asia	Roger Brown	2024-07-15	1	1	637.205516	10.97	2	637.205516
821b4123-d80b-4392-89f0-191dbc556a3f	Pending	PayPal	Europe	Jason Nelson	2024-07-05	1	1	172.343484	12.28	1	172.343484
8224f6a9-0e12-479c-a88d-b3733991ad99	Cancelled	Debit Card	South America	Steven Coleman	2024-04-13	1	1	1692.9317440000002	23.64	7	1692.9317440000002
8279d803-ca9b-4c70-8398-2c7b4101e73d	Pending	Debit Card	Europe	Kristen Ramos	2024-05-10	1	1	2047.18059	18.55	7	2047.18059
82a0a3cc-31b7-44c5-b6b6-c6672373a791	Returned	Gift Card	Asia	Steven Coleman	2024-08-18	1	1	944.110758	12.81	3	944.110758
82bc5b5e-c492-406e-aaa1-90b9b7220fd2	Pending	Debit Card	North America	Michelle Andersen	2023-03-17	1	1	560.876904	23.28	9	560.876904
82c6284d-efb1-49a4-99f2-2452c56778a0	Returned	Debit Card	South America	Joseph Brooks	2023-12-11	1	1	536.9732280000001	18.82	2	536.9732280000001
82d01469-d261-47fb-91c5-675d5d144ddb	Pending	Debit Card	South America	Steven Coleman	2024-08-22	1	1	2203.180296	8.21	6	2203.180296
82e1c5f7-7e1e-4efc-a6bf-1813d374a5d8	Cancelled	Debit Card	South America	Susan Edwards	2023-12-24	1	1	385.727664	19.06	4	385.727664
83064e00-0a9a-4b90-8d78-50fb07da9c5b	Cancelled	PayPal	North America	Emily Matthews	2024-09-22	1	1	1171.126585	24.27	5	1171.126585
8318990a-57a5-4c9d-8231-27540dc0ad55	Returned	PayPal	North America	Steven Coleman	2024-12-19	1	1	2731.67433	2.1	7	2731.67433
8319da2d-9b33-46b3-9661-b68635114d44	Pending	Gift Card	North America	Caleb Camacho	2020-05-24	1	1	2173.4481	25.5	6	2173.4481
83311e53-2c84-4674-88f9-440c37e777c7	Pending	Amazon Pay	Australia	Emily Matthews	2019-03-01	1	1	560.4538	1.95	5	560.4538
83324013-e1af-4cbf-a92d-4949acd23659	Pending	Gift Card	South America	Steven Coleman	2021-07-01	1	1	378.911424	23.26	1	378.911424
83368f57-2c19-4606-8996-1219c6a7a5da	Pending	Credit Card	South America	Michelle Andersen	2020-11-21	1	1	415.154166	0.79	7	415.154166
8371d9ed-a1ae-4cad-a3cd-dd0cdffdb0c9	Cancelled	Amazon Pay	Asia	Caleb Camacho	2024-05-31	1	1	790.0926	18.84	5	790.0926
83837daf-0f32-4fd7-806b-cda295ee8d26	Returned	Credit Card	Australia	Michelle Andersen	2019-08-11	1	1	1080.46341	10.3	3	1080.46341
83b37260-f0ae-4859-a0cc-e1500691ff1d	Cancelled	Gift Card	North America	Steven Coleman	2021-01-25	1	1	92.232707	18.11	1	92.232707
83bd4a18-541c-4634-8b36-5d79e0c2d77d	Pending	Credit Card	Australia	Roger Brown	2023-02-03	1	1	2563.070352	29.42	8	2563.070352
83ebbcf0-6f9b-4062-bd69-81ad35101fd8	Cancelled	PayPal	Europe	Mary Scott	2021-06-06	1	1	1434.0552659999998	20.62	9	1434.0552659999998
84072f69-a4d0-4038-b51b-189218717d88	Cancelled	Gift Card	Australia	Emily Matthews	2022-06-09	1	1	347.952264	21.68	3	347.952264
841b9801-6ee7-43a2-a0f7-e6c8e5700116	Returned	PayPal	Australia	Susan Edwards	2020-05-28	1	1	472.837464	21.02	9	472.837464
8434f9d1-ca32-4b25-9675-4b1851a20288	Returned	Gift Card	Europe	Caitlyn Boyd	2021-09-13	1	1	406.677024	19.54	9	406.677024
845107b3-1d87-469c-875a-f02681ed6d1f	Pending	Amazon Pay	North America	Michelle Andersen	2022-09-08	1	1	1561.7772000000002	10.32	10	1561.7772000000002
84586ffc-b004-4a58-ae4f-cb6899123f75	Returned	Credit Card	Asia	Sandra Luna	2023-11-25	1	1	1100.121264	28.72	6	1100.121264
846be93a-5a04-4e8e-9b51-1ca5a1cb610e	Returned	PayPal	North America	Emily Matthews	2020-04-04	1	1	1213.95636	27.8	6	1213.95636
8484ddc5-306a-4274-8a7f-e1c38140e8f0	Pending	Debit Card	South America	Joseph Brooks	2024-03-07	1	1	350.74434	16.36	1	350.74434
84e7cac7-ced6-41a6-968d-5a289e5ecb25	Pending	PayPal	South America	Sandra Luna	2019-06-10	1	1	1619.443056	7.49	8	1619.443056
8500f871-1b7d-4948-be54-eb545cbd64d9	Returned	Gift Card	Europe	Sandra Luna	2020-05-11	1	1	898.877952	7.11	4	898.877952
85039349-d81f-4195-81dc-40a6822d7740	Cancelled	Credit Card	Europe	Jason Nelson	2024-01-06	1	1	1450.56768	11.68	8	1450.56768
8509c22e-cc4d-49a0-9f95-c25a358dcb46	Cancelled	Debit Card	Europe	Diane Andrews	2024-11-30	1	1	49.269044	3.09	4	49.269044
852d095c-cbdb-4328-8e50-f14806b94e13	Returned	Amazon Pay	Asia	Steven Coleman	2020-09-23	1	1	165.57303500000003	1.05	1	165.57303500000003
853e0fd3-f3fd-4288-af6c-25de074c60d5	Cancelled	Amazon Pay	Europe	Charles Smith	2022-03-18	1	1	2423.861352	8.78	9	2423.861352
85658d74-9aa0-4e47-9301-378df1ef26d9	Cancelled	Amazon Pay	South America	Emily Matthews	2019-07-12	1	1	339.983739	0.09	1	339.983739
856c4928-01b3-4860-b490-3afc44d0a63a	Cancelled	Amazon Pay	South America	Johnny Marshall	2020-12-29	1	1	454.3345520000001	29.09	2	454.3345520000001
85735776-ca1a-4202-973a-05292073a7f0	Returned	Debit Card	Europe	Emily Matthews	2022-09-06	1	1	1089.21813	3.86	5	1089.21813
8574d4ad-cf83-4531-b915-cc1b1c039c79	Pending	Debit Card	South America	Charles Smith	2020-03-11	1	1	237.66846	22.9	2	237.66846
857d707c-326e-457a-a383-5f443cb6f941	Pending	PayPal	Australia	Susan Edwards	2024-02-25	1	1	2341.02057	18.61	7	2341.02057
858b6fde-6486-40fb-8965-e42ccfb71f57	Returned	Debit Card	South America	Johnny Marshall	2020-05-29	1	1	1420.38728	24.08	10	1420.38728
85ab3781-0bd9-42cc-a572-05358fd801e5	Cancelled	PayPal	Europe	Michelle Garza	2021-06-28	1	1	182.643335	18.59	7	182.643335
85b5cc15-fb52-44e7-9bc9-83322cc035aa	Cancelled	Debit Card	South America	Diane Andrews	2022-09-28	1	1	1566.19528	15.24	5	1566.19528
85c87cbb-182a-48f8-988b-d6a7a793dd99	Pending	PayPal	Australia	Kristen Ramos	2024-01-09	1	1	792.274868	25.86	7	792.274868
85cd16ec-c640-46b0-b228-44d84503b28d	Cancelled	Credit Card	Asia	Mary Scott	2019-09-20	1	1	529.753392	19.84	7	529.753392
85dcdd1b-90cd-4b26-87e2-e998a17fe284	Cancelled	Debit Card	Asia	Steven Coleman	2019-11-13	1	1	1383.823328	17.36	4	1383.823328
85ebef2c-7132-4a59-ae9a-e6a5d6222308	Pending	PayPal	North America	Michelle Andersen	2023-09-25	1	1	322.041552	20.46	8	322.041552
85efae3e-b463-4b66-87ef-e6afa2a54bf7	Returned	Debit Card	South America	Steven Coleman	2024-05-31	1	1	781.5462660000001	21.47	6	781.5462660000001
85f06ea1-bea9-4c90-8ec4-eb1b5c70d778	Returned	PayPal	South America	Mary Scott	2022-10-07	1	1	877.178232	2.36	7	877.178232
85f9f5e7-014a-4e55-babd-d9436b2e5ba5	Pending	Credit Card	South America	Joseph Brooks	2022-06-18	1	1	183.788496	29.98	8	183.788496
861dfba4-2eb1-4d52-93d8-c16d6075470b	Pending	Gift Card	Australia	Christina Thompson	2024-04-14	1	1	658.4904449999999	12.05	3	658.4904449999999
864b3b54-4eef-4394-b8d7-2ef4454baa4e	Pending	Amazon Pay	Australia	Crystal Williams	2022-05-27	1	1	2764.761104	22.58	8	2764.761104
866841c9-97f1-4073-98a2-9fbf36cc2f71	Pending	Amazon Pay	Europe	Bradley Howe	2024-11-23	1	1	2199.231475	18.87	7	2199.231475
86686595-f771-4b80-97ae-76f123af2e2c	Cancelled	Credit Card	South America	Bradley Howe	2023-03-31	1	1	3178.88424	2.14	10	3178.88424
86747edb-1657-4839-bcc6-3eb165a39851	Pending	Debit Card	Asia	Sandra Luna	2022-11-03	1	1	750.931104	28.39	8	750.931104
867f9bea-c14c-48b5-805e-e99533c0ff34	Returned	Debit Card	North America	Michelle Garza	2021-11-23	1	1	1788.071495	0.65	7	1788.071495
8683b51a-19b9-49e2-ac88-28304f14dc48	Pending	Gift Card	South America	Crystal Williams	2023-12-12	1	1	1698.9752040000003	10.01	6	1698.9752040000003
8698f504-0efd-4bde-9d04-1ee1abc1b78d	Returned	Gift Card	Australia	Michelle Garza	2023-09-30	1	1	1797.958448	8.87	8	1797.958448
86a2a0df-91f1-45db-8961-00f303d8c239	Returned	Amazon Pay	Asia	Jason Nelson	2021-04-03	1	1	164.55124	28.2	2	164.55124
86b17a0a-e5e8-404b-823f-e4d220b7627c	Returned	PayPal	North America	Jason Nelson	2022-09-16	1	1	33.427905	15.65	3	33.427905
86d5a83b-71b3-4f00-9f13-4dbbff0fd153	Pending	PayPal	Europe	Christina Thompson	2020-02-07	1	1	1177.20801	3.95	6	1177.20801
86e78aa7-6359-45b0-a939-15e67d4550c2	Returned	PayPal	Asia	Steven Coleman	2024-10-22	1	1	147.130685	14.85	1	147.130685
8703cf7e-699a-4434-ab9f-75f03e70cd5e	Returned	Credit Card	Australia	Caitlyn Boyd	2020-08-02	1	1	2234.446851	6.03	7	2234.446851
87040188-2d22-4fbc-9ce4-2befe424ab08	Cancelled	Gift Card	South America	Joseph Brooks	2020-07-03	1	1	1947.381849	27.93	7	1947.381849
87119358-ea43-430c-9ece-ef7bcea85cc4	Returned	Gift Card	Europe	Johnny Marshall	2020-06-24	1	1	273.70944000000003	29.89	4	273.70944000000003
8769b9b4-d109-4c7d-911b-b8dfc2cec924	Returned	Amazon Pay	Asia	Crystal Williams	2022-01-19	1	1	1979.313372	25.14	6	1979.313372
8772e277-c1a7-490e-9a09-1af50c0079b0	Pending	Gift Card	Europe	Kristen Ramos	2019-02-03	1	1	4530.15123	5.91	10	4530.15123
878149a9-bfc3-42dc-a9d5-700cd77d78e1	Cancelled	Credit Card	North America	Susan Edwards	2023-02-03	1	1	3190.2012	6.85	8	3190.2012
878160ca-3a4b-4e4d-9f47-78648f713f22	Returned	Debit Card	Australia	Roger Brown	2024-03-03	1	1	44.015040000000006	28.08	2	44.015040000000006
878ed568-dab2-47fe-86bb-3202336a57ff	Returned	Debit Card	South America	Caleb Camacho	2023-04-09	1	1	1528.8764400000002	7.96	10	1528.8764400000002
87a66b09-f287-4405-b525-3597a2e780cf	Pending	Credit Card	North America	Adam Smith	2019-12-01	1	1	108.144528	14.82	2	108.144528
87a89012-a14d-4ac3-bb71-a33c6eddc357	Returned	PayPal	Asia	Michelle Andersen	2024-05-04	1	1	872.4067000000001	8.1	5	872.4067000000001
87b7e0b0-c3d2-4f84-bbc5-641037ee4fc2	Pending	Gift Card	North America	Crystal Williams	2019-12-20	1	1	604.726284	4.98	3	604.726284
87be2251-a435-479c-a10a-1065b971fd68	Cancelled	Gift Card	Australia	Bradley Howe	2020-08-29	1	1	1922.582982	12.41	6	1922.582982
87e5fc6c-63ee-4af8-b758-f0db3b8f7bf1	Returned	Gift Card	North America	Roger Brown	2020-11-22	1	1	766.97622	25.81	10	766.97622
87ef959b-f014-4b4d-89ed-db85d23e5ba0	Cancelled	Credit Card	South America	Kristen Ramos	2021-12-27	1	1	2394.44037	15.31	7	2394.44037
87f3f616-1f99-4b09-a2dc-76e80ead9b10	Pending	Debit Card	Europe	Caleb Camacho	2024-07-05	1	1	2199.050802	14.98	9	2199.050802
8817870c-5896-4b78-90e7-a9b446ef6dbd	Pending	Credit Card	South America	Charles Smith	2024-04-16	1	1	1023.217804	5.34	7	1023.217804
881acbbe-553f-440f-bce8-a0d4397b8db5	Cancelled	Amazon Pay	North America	Diane Andrews	2024-10-17	1	1	926.553912	0.13	8	926.553912
8828855d-33f6-4b47-9447-671bb4558060	Returned	PayPal	Asia	Jason Nelson	2022-09-02	1	1	3516.952635	6.97	9	3516.952635
8828cbb4-d466-4192-9e38-651cc28c768e	Returned	Debit Card	Australia	Diane Andrews	2021-05-30	1	1	303.79672600000004	24.59	2	303.79672600000004
883c634f-56ab-4c2f-be87-73bd240968a3	Pending	PayPal	Europe	Michelle Garza	2019-06-03	1	1	1797.409075	12.99	5	1797.409075
88618d4b-f428-4dd4-99a3-4ccfa0ae7887	Pending	PayPal	Australia	Christina Thompson	2019-01-11	1	1	185.597244	16.78	6	185.597244
886ebbca-d2e9-49e3-b29f-858d56a9b4c4	Pending	Debit Card	North America	Kristen Ramos	2023-10-23	1	1	91.90664	2.6	4	91.90664
88824de1-b501-4b54-8a67-fd02463ed1af	Returned	Credit Card	Europe	Bradley Howe	2024-02-19	1	1	2011.10897	10.11	5	2011.10897
89053b20-fc09-4147-be59-acf99d17a9f9	Returned	Gift Card	Asia	Caleb Camacho	2024-01-17	1	1	709.9818240000001	9.12	3	709.9818240000001
890c03ae-6e9c-4f6a-9ec1-b9914e073841	Pending	Gift Card	Australia	Adam Smith	2022-02-23	1	1	200.504538	16.81	6	200.504538
890e359d-4ead-4426-a13c-ddb8249070d9	Pending	Gift Card	South America	Steven Coleman	2019-05-31	1	1	548.613	22	9	548.613
89122dc3-64d2-40d9-a613-b9c71382f1d1	Cancelled	Debit Card	Europe	Bradley Howe	2022-08-13	1	1	714.6939120000001	22.38	3	714.6939120000001
891a1104-fe11-4ae5-a251-a0e0ee35f45a	Cancelled	Gift Card	North America	Steven Coleman	2021-04-01	1	1	2049.9172200000003	19.63	6	2049.9172200000003
892e5f14-0ab4-4a46-b675-ae16eee771c3	Returned	PayPal	South America	Roger Brown	2022-04-16	1	1	467.595904	18.56	2	467.595904
892fed8d-0400-423e-a7ba-f4b14b44d987	Returned	Gift Card	Europe	Emily Matthews	2020-07-05	1	1	385.394544	4.48	9	385.394544
8955e477-ac20-4f78-b1ce-bc290e13f0b0	Returned	Credit Card	Asia	Michelle Garza	2019-03-10	1	1	3775.562639999999	4.12	10	3775.562639999999
8987499c-1c04-45b1-a567-2c1eee116c95	Cancelled	PayPal	North America	Emily Matthews	2020-11-05	1	1	1789.571232	7.52	9	1789.571232
89986d5c-c8cb-4d09-b6d8-299852b887ab	Cancelled	Debit Card	Europe	Diane Andrews	2023-12-16	1	1	1270.887576	14.02	4	1270.887576
89ada508-1d1d-4b7d-aab5-20563bf233ab	Cancelled	Amazon Pay	Asia	Jason Nelson	2021-08-28	1	1	296.82408	22.48	5	296.82408
89c325ba-78a9-4bc6-aaaf-db0bfcd778d3	Returned	Amazon Pay	Australia	Diane Andrews	2021-11-18	1	1	2100.4617689999995	10.83	7	2100.4617689999995
89dccafd-6da2-4455-8c00-30523cd468a9	Pending	PayPal	South America	Roger Brown	2023-11-17	1	1	2674.67579	24.03	10	2674.67579
89e35901-4e17-4b7a-b0cb-64f24f64b1f6	Pending	Debit Card	South America	Mary Scott	2023-07-26	1	1	963.008475	7.05	5	963.008475
89e525d1-eeb5-4113-87aa-82ef1e72437a	Returned	PayPal	South America	Steven Coleman	2022-03-17	1	1	2196.035883	15.59	9	2196.035883
8a18cf47-e5ed-414f-84e8-9c3783b9a208	Returned	Credit Card	Europe	Caleb Camacho	2019-02-23	1	1	212.769172	3.72	1	212.769172
8a6565c4-6907-448a-8545-0e342edb8f63	Pending	PayPal	Australia	Susan Edwards	2019-10-17	1	1	490.8316	8.64	5	490.8316
8a666cbb-8320-4582-8271-3d88ccf06385	Cancelled	PayPal	Asia	Caleb Camacho	2021-07-20	1	1	1100.4213960000002	19.07	3	1100.4213960000002
8a822351-eab1-4db2-ae9a-261417e850fa	Cancelled	Debit Card	South America	Emily Matthews	2021-09-02	1	1	475.036248	12.69	3	475.036248
8a8559d3-10b7-4573-819e-958fcf58e5fe	Returned	PayPal	Europe	Adam Smith	2021-04-18	1	1	446.80896	29.28	2	446.80896
8a85e8be-f6a4-4623-8af6-9ea4b7e1f148	Cancelled	Amazon Pay	Australia	Kristen Ramos	2021-07-23	1	1	3593.3028000000004	16.59	10	3593.3028000000004
8a968316-849f-4801-a0b4-d0043c344be7	Cancelled	Gift Card	Europe	Kristen Ramos	2020-01-06	1	1	1904.78952	8.32	5	1904.78952
8a9c6e67-f35e-43de-904f-1d31326a2d05	Returned	PayPal	Europe	Jason Nelson	2023-01-31	1	1	764.164392	12.56	3	764.164392
8aaa3c95-2492-4368-85f7-910baa8812c1	Pending	Debit Card	Australia	Roger Brown	2024-04-04	1	1	793.784511	23.17	3	793.784511
8ab6572e-ae0b-4f56-b4f8-81cf1765fa3d	Returned	Debit Card	South America	Christina Thompson	2024-11-10	1	1	2543.02992	1.6	6	2543.02992
8ac7395a-ad7a-4302-a636-586252676aed	Pending	Debit Card	South America	Caitlyn Boyd	2023-04-18	1	1	2062.5949749999995	24.75	7	2062.5949749999995
8ad310c6-e8d0-43ba-9355-44bdad7524df	Cancelled	Debit Card	South America	Charles Smith	2023-10-05	1	1	1708.132797	9.29	9	1708.132797
8adce642-4dfe-468b-8e02-35edb50225dd	Returned	Amazon Pay	Asia	Emily Matthews	2023-08-12	1	1	2556.195276	2.79	6	2556.195276
8aeb48e0-70ff-456b-a2d7-6d460fd67307	Pending	Amazon Pay	Asia	Roger Brown	2020-05-09	1	1	1666.238792	7.02	4	1666.238792
8af8be90-e2a2-4578-9411-e7543c0c8e4e	Cancelled	Gift Card	South America	Bradley Howe	2022-03-23	1	1	1417.498992	12.08	9	1417.498992
8b12652b-6dff-4953-bea2-a3b79b20624e	Cancelled	Gift Card	North America	Roger Brown	2021-06-01	1	1	124.28974800000002	4.89	4	124.28974800000002
8b17c302-9bc9-46e7-acb0-2022f30fb269	Cancelled	Amazon Pay	Asia	Diane Andrews	2020-06-13	1	1	612.9149400000001	10.92	5	612.9149400000001
8b333562-e5f8-4a8a-9979-d84e3490b743	Cancelled	Credit Card	South America	Crystal Williams	2020-10-23	1	1	1392.412252	2.21	4	1392.412252
8b38433a-84fd-44ed-a1ca-ea3f68412ad6	Returned	PayPal	Australia	Diane Andrews	2021-07-08	1	1	2278.5054390000005	6.57	9	2278.5054390000005
8b406697-0219-4ba5-b06c-c00e8e44b15d	Pending	Credit Card	Europe	Diane Andrews	2019-10-09	1	1	1618.467102	23.13	6	1618.467102
8b7517c5-e044-4a5e-9d8b-f0a7c41a2791	Cancelled	PayPal	Asia	Emily Matthews	2019-11-10	1	1	368.88192	29.71	4	368.88192
8b7648b4-799c-4b0b-aa29-6b6eba1012a0	Returned	Amazon Pay	Australia	Johnny Marshall	2024-11-02	1	1	1399.534308	4.27	3	1399.534308
8b924e8a-ce77-40bb-9117-6fb2fc5469fa	Returned	PayPal	Asia	Caleb Camacho	2019-03-14	1	1	291.768246	2.98	1	291.768246
8bb62e96-888e-4164-8a61-0d9460e86118	Pending	PayPal	Europe	Joseph Brooks	2023-05-29	1	1	253.125702	29.74	9	253.125702
8bd73afd-5750-4e1a-bddf-c933846636dd	Cancelled	Credit Card	Asia	Caleb Camacho	2023-07-17	1	1	15.25296	26.1	4	15.25296
8bde0b3c-1a79-4471-92c9-3775b77864a2	Returned	Debit Card	Australia	Michelle Andersen	2024-12-08	1	1	728.5759199999999	5.2	2	728.5759199999999
8be0fbc0-f624-48ea-a3e6-0cbfcb0b9ed6	Returned	Debit Card	South America	Crystal Williams	2024-07-23	1	1	1868.989815	5.95	7	1868.989815
8be16380-1a10-4d7a-95c7-6bc6ffe5aa99	Cancelled	Amazon Pay	Australia	Kristen Ramos	2019-06-27	1	1	3810.2448	22.1	10	3810.2448
8bf6bc81-57a8-4ec2-b496-78f8ba2c094e	Returned	Credit Card	North America	Charles Smith	2020-08-16	1	1	184.69966599999995	29.78	1	184.69966599999995
8c08d942-cf44-4b67-ac15-797bb0eb86e8	Cancelled	Amazon Pay	Asia	Bradley Howe	2022-06-09	1	1	2446.240608	10.26	6	2446.240608
8c3eeec4-63fe-4e00-ad35-505228699bfe	Returned	Amazon Pay	Europe	Joseph Brooks	2022-08-23	1	1	550.8565919999999	10.83	6	550.8565919999999
8c498ab9-6738-438f-a9a2-fd2108c98290	Pending	Amazon Pay	Asia	Kristen Ramos	2020-12-12	1	1	624.0677519999999	8.73	2	624.0677519999999
8c6708df-aaac-4611-9fd0-d3df5c90d00e	Pending	Credit Card	Europe	Adam Smith	2021-07-16	1	1	958.9184	29.6	5	958.9184
8c6df30f-267e-4795-8259-0d2e9fcf20cd	Pending	PayPal	Australia	Johnny Marshall	2023-08-04	1	1	122.221984	1.94	2	122.221984
8c6fa233-8399-40a0-8682-4f42413ba323	Pending	Amazon Pay	Asia	Emily Matthews	2019-09-12	1	1	131.73008399999998	22.68	3	131.73008399999998
8c70a9a6-bb1f-491e-aa47-d1c5cf3a7f2f	Returned	Debit Card	Asia	Michelle Andersen	2020-07-25	1	1	2607.7401600000003	26.9	8	2607.7401600000003
8ca43a56-23b8-4f20-b300-8017360f16ca	Returned	PayPal	Australia	Michelle Garza	2020-11-07	1	1	2394.6475	0.74	5	2394.6475
932682e4-f572-409e-adb9-90438ceab60c	Returned	Gift Card	Asia	Kristen Ramos	2024-11-11	1	1	673.705017	7.23	9	673.705017
8cb75b25-547c-4b61-beb6-c6e260a4a0cb	Pending	Credit Card	Australia	Emily Matthews	2019-02-05	1	1	236.819232	11.74	4	236.819232
8ccfc290-14c0-4887-bd9c-c50fe52c43fa	Pending	Amazon Pay	South America	Michelle Andersen	2023-05-03	1	1	1082.500122	2.43	3	1082.500122
8cf25bef-c360-47f2-be41-b14f56720f51	Pending	Amazon Pay	Asia	Roger Brown	2022-08-16	1	1	1429.42596	1.31	3	1429.42596
8cf488a7-a75f-4d55-a4cf-ed1325cc4867	Cancelled	PayPal	South America	Michelle Andersen	2021-06-09	1	1	2279.966208	19.52	6	2279.966208
8cf8fe05-9576-4dc2-9891-3bc2d41628ca	Returned	Debit Card	Asia	Michelle Garza	2020-01-31	1	1	943.979288	18.29	4	943.979288
8cfea582-773c-4127-ae0f-e63bcdd98707	Cancelled	Debit Card	North America	Charles Smith	2024-12-31	1	1	169.6968	18.1	7	169.6968
8d1082e1-921b-42d8-9eca-50f508dff0a3	Returned	Credit Card	South America	Diane Andrews	2022-10-11	1	1	1205.937546	13.26	3	1205.937546
8d10fd01-320d-4a0c-b135-1f92644e1e82	Pending	Amazon Pay	Asia	Roger Brown	2019-11-26	1	1	105.903987	11.37	1	105.903987
8d15d9f6-3893-4303-b346-363dfdf30cb3	Cancelled	Amazon Pay	Asia	Jason Nelson	2022-05-15	1	1	906.889536	17.12	6	906.889536
8d1946df-51a1-4ade-969c-754da11be0ed	Pending	Credit Card	Australia	Joseph Brooks	2024-07-15	1	1	31.228869	26.71	1	31.228869
8d2a7be7-ef08-465e-b420-377b312cb3ac	Returned	Amazon Pay	South America	Adam Smith	2020-06-22	1	1	3138.7824	19	8	3138.7824
8d3333fc-0b79-4add-94b6-a7bf3c076ecb	Cancelled	Debit Card	Australia	Mary Scott	2020-01-02	1	1	378.31599000000006	18.14	5	378.31599000000006
8d6e8d97-4b03-4918-9607-4586295ebb40	Pending	Debit Card	Australia	Bradley Howe	2022-09-20	1	1	898.9594619999999	15.29	3	898.9594619999999
8d7540e9-6652-47f7-a5cc-9e54d5f57465	Returned	Debit Card	Asia	Caitlyn Boyd	2024-03-21	1	1	33.499906	5.18	1	33.499906
8d7898d1-4ebb-41df-b6f4-f32b0379aef2	Pending	Debit Card	North America	Bradley Howe	2020-03-08	1	1	368.232128	26.33	8	368.232128
8d7c5399-7a8b-4434-9bab-e68c9de793e7	Pending	Gift Card	North America	Michelle Garza	2019-09-01	1	1	9.72855	16.85	2	9.72855
8d885922-eb48-47f0-a634-a1387817f5b9	Cancelled	Gift Card	Asia	Caleb Camacho	2022-06-11	1	1	1011.560964	5.21	4	1011.560964
8dbe498a-6394-451f-ac70-314d0d2b90c1	Pending	Gift Card	Asia	Diane Andrews	2022-03-31	1	1	522.58752	19.36	5	522.58752
8dd31573-093e-4937-b108-8ae7ac818290	Returned	Gift Card	North America	Joseph Brooks	2021-01-22	1	1	1064.11776	18.72	6	1064.11776
8de3545c-78e6-4962-ace5-02e37fe1ce91	Pending	Gift Card	South America	Bradley Howe	2019-01-01	1	1	1677.52296	6.43	10	1677.52296
8de3b57d-4684-47c9-a7fa-413f13d4f006	Returned	Amazon Pay	Europe	Christina Thompson	2019-02-04	1	1	120.52860400000002	11.61	2	120.52860400000002
8de40de9-b607-45a7-98cb-042829d4f2dc	Pending	Debit Card	Europe	Diane Andrews	2019-09-20	1	1	1319.7446639999998	10.63	4	1319.7446639999998
8dfa931e-4e03-4c6f-9b82-93eea187c42c	Returned	Credit Card	South America	Susan Edwards	2023-06-29	1	1	903.47358	7.79	4	903.47358
8e2661a0-dd05-43b7-aeef-e59263a86d6d	Cancelled	Amazon Pay	Europe	Crystal Williams	2021-03-21	1	1	80.310784	27.36	8	80.310784
8e313c9f-ff9f-4fee-90d9-284d4d80e66f	Returned	Credit Card	South America	Michelle Garza	2019-03-10	1	1	933.218925	11.05	5	933.218925
8e554468-8114-4a31-9ab5-c5234d14d9da	Cancelled	Gift Card	Australia	Emily Matthews	2020-06-06	1	1	172.332251	3.87	1	172.332251
8e686b18-da14-4c24-af53-d413cb57f529	Returned	Gift Card	South America	Joseph Brooks	2024-09-05	1	1	1757.1045	4.5	5	1757.1045
8e6c6abd-2752-4b2b-bac9-ba3174611fb0	Pending	Debit Card	South America	Joseph Brooks	2022-08-17	1	1	1341.504128	2.12	4	1341.504128
8e6fdd3c-e90a-40ba-a39c-b9da284ca826	Returned	Credit Card	Europe	Joseph Brooks	2021-06-01	1	1	1154.357076	1.71	4	1154.357076
8e856afa-c0d9-40de-b798-97d53f9bacb4	Pending	Debit Card	Asia	Diane Andrews	2020-02-22	1	1	3276.07531	6.47	10	3276.07531
8e8da6ff-f116-4838-9e41-cb6030c1da99	Pending	Debit Card	Asia	Sandra Luna	2024-12-14	1	1	507.729964	7.46	2	507.729964
8ea71e79-10ea-4db2-a5a8-cd24e0b484c7	Pending	Amazon Pay	South America	Michelle Andersen	2019-06-29	1	1	1173.382572	19.91	3	1173.382572
8eadf523-0101-457a-8e8b-1ad3e2049ad3	Cancelled	Credit Card	Asia	Adam Smith	2022-11-24	1	1	601.213872	20.68	4	601.213872
8ec26044-e991-4d8b-9ac5-74138f681f03	Returned	PayPal	Asia	Caitlyn Boyd	2024-09-27	1	1	104.12639	19.1	1	104.12639
8ec85af7-bc11-46db-987a-ad9c670ad468	Pending	Debit Card	Asia	Crystal Williams	2020-03-07	1	1	2465.953938	8.58	9	2465.953938
8edae859-1ff3-4c63-a339-6972656caa9c	Returned	PayPal	Australia	Jason Nelson	2020-04-29	1	1	2810.902944	23.08	8	2810.902944
8eff6c26-1198-43ae-8e7b-1b6655a1a8a8	Cancelled	Amazon Pay	Europe	Johnny Marshall	2022-08-26	1	1	356.62848	28.56	8	356.62848
8f1e5a7c-c4b4-49f1-854b-1f4a27567ece	Returned	Debit Card	South America	Caleb Camacho	2024-03-09	1	1	359.895151	8.37	1	359.895151
8f254295-ec47-4795-b504-d93a7bcb5e51	Returned	Credit Card	Australia	Caitlyn Boyd	2019-02-11	1	1	43.805328	23.31	7	43.805328
8f2a1625-1e0b-4063-b2c0-46cd42d38ccc	Returned	Amazon Pay	Australia	Mary Scott	2020-12-07	1	1	31.899420000000006	21.7	7	31.899420000000006
8f2e282a-bd59-4f3f-bacf-27da1af22bec	Cancelled	PayPal	North America	Susan Edwards	2022-05-01	1	1	1803.798425	21.35	5	1803.798425
8f5336db-4374-4c7b-9c91-287c57da5d95	Returned	Credit Card	North America	Adam Smith	2022-05-09	1	1	348.274808	7.59	7	348.274808
8f71095f-bcf6-4207-9808-462d75ac6372	Cancelled	Amazon Pay	Europe	Caleb Camacho	2024-03-18	1	1	364.64534	23.81	4	364.64534
8f80ac73-59b2-4e7c-8677-56c8067e7dd5	Returned	Amazon Pay	North America	Michelle Andersen	2024-06-04	1	1	3351.959568	4.04	9	3351.959568
8f83494e-70a7-47a2-8c61-c75bd492d51e	Cancelled	Amazon Pay	Australia	Susan Edwards	2022-02-24	1	1	1849.202355	19.43	5	1849.202355
8fedee11-3798-4200-ab75-287e34bb3e6c	Returned	Debit Card	Asia	Bradley Howe	2019-08-14	1	1	2503.397484	13.56	7	2503.397484
8ff7e7ef-da9e-4f0e-b02b-7036935ceb84	Pending	Debit Card	South America	Susan Edwards	2023-04-14	1	1	1535.5425799999998	28.76	5	1535.5425799999998
8fff2005-2aea-42ac-9935-4321090a9510	Pending	Credit Card	Europe	Caleb Camacho	2020-09-22	1	1	408.237082	23.33	2	408.237082
900190da-a5eb-4eaf-b774-ef1d1d029b78	Returned	Amazon Pay	Australia	Roger Brown	2022-05-16	1	1	3857.66511	7.31	10	3857.66511
9027bc0c-378d-445a-8c2d-fd25b304a4bb	Returned	PayPal	Europe	Joseph Brooks	2023-07-04	1	1	665.1603359999999	15.04	9	665.1603359999999
904d1b1f-8fa8-4d32-be2f-28d010850457	Pending	PayPal	Asia	Bradley Howe	2022-08-28	1	1	3281.16096	4.96	8	3281.16096
9064d7ad-e1b2-43b1-afa9-ad79db015289	Pending	Gift Card	South America	Adam Smith	2019-09-29	1	1	675.4551299999999	22.7	3	675.4551299999999
909c793a-3e98-45da-9c6b-ed6e45ac79d1	Returned	Amazon Pay	Asia	Jason Nelson	2023-03-03	1	1	2128.1182860000004	28.82	7	2128.1182860000004
90b89761-b1ce-4fec-9de2-fb03cd53eb75	Cancelled	Amazon Pay	Asia	Roger Brown	2020-04-23	1	1	3303.5640000000003	13.7	10	3303.5640000000003
90c2b101-bc24-487d-8b4c-d9d770dc045e	Returned	Debit Card	Asia	Michelle Andersen	2023-06-07	1	1	1173.84764	6.63	4	1173.84764
90c89d46-3e0a-4567-b8c0-f95e013f3058	Pending	Amazon Pay	North America	Mary Scott	2023-08-25	1	1	3447.7818210000005	0.23	9	3447.7818210000005
90ceb4f3-fcf9-4706-8e03-4e3fdc3ae45d	Pending	Amazon Pay	South America	Charles Smith	2024-05-17	1	1	1374.601716	0.59	9	1374.601716
90ebbffe-fd59-4b14-bd51-f347f2a77f49	Cancelled	Amazon Pay	North America	Emily Matthews	2019-09-18	1	1	189.481636	17.43	4	189.481636
914bd6f3-bfc7-4172-a485-a79866fc857f	Cancelled	PayPal	Asia	Bradley Howe	2023-11-14	1	1	2415.194824	18.92	7	2415.194824
914e8eb9-830f-4acd-9b98-04d48f031dda	Pending	PayPal	Asia	Michelle Garza	2021-06-11	1	1	68.212704	0.04	1	68.212704
9159d1b1-4d8c-4c04-bca1-4782a6f68241	Pending	Amazon Pay	North America	Mary Scott	2022-09-27	1	1	2504.5722100000003	5.37	7	2504.5722100000003
9172b75b-68a6-4f1a-877d-2c91f52b7cbf	Returned	Gift Card	North America	Roger Brown	2019-04-11	1	1	2615.5203840000004	8.32	8	2615.5203840000004
9175a1cb-4b4e-4973-9b3b-b415049f27d9	Pending	PayPal	Asia	Christina Thompson	2020-05-28	1	1	431.469216	10.29	6	431.469216
918df578-7a69-48f9-8724-9798cf251bb4	Pending	PayPal	Europe	Caitlyn Boyd	2020-06-23	1	1	1381.5419699999998	12.58	5	1381.5419699999998
91a70bfe-0f9d-4118-b6c8-a80f970ef454	Cancelled	Credit Card	South America	Bradley Howe	2023-12-17	1	1	3721.893912	4.29	8	3721.893912
91b893d1-ea1e-40b5-b64c-6e11119da843	Pending	Debit Card	Asia	Joseph Brooks	2021-04-20	1	1	265.96632	19.11	8	265.96632
91bf1a65-9f61-4273-a8e0-d104eccaf0da	Cancelled	Gift Card	Australia	Adam Smith	2023-06-09	1	1	1814.5681	1.35	5	1814.5681
91ca77ec-f721-47e5-8f12-d333070d97ad	Returned	Gift Card	South America	Emily Matthews	2022-07-16	1	1	601.98068	23.49	2	601.98068
91cc10c0-df5d-4851-9942-acce6ffcc0cd	Cancelled	PayPal	South America	Caitlyn Boyd	2023-03-24	1	1	2220.878256	8.52	6	2220.878256
91de33da-cb29-454c-abe4-945d21fa714b	Pending	Gift Card	Europe	Michelle Andersen	2020-08-26	1	1	639.60652	24.92	10	639.60652
91e0925e-c99e-43c5-a516-d0095e521320	Pending	PayPal	South America	Steven Coleman	2020-10-22	1	1	1026.640736	16.43	8	1026.640736
91e424b0-263b-4efb-92bc-ae218f1d11c2	Returned	Credit Card	Australia	Caitlyn Boyd	2024-01-10	1	1	1343.604836	10.52	7	1343.604836
91e8c595-3d83-426d-8b28-2fafc4147e5a	Pending	Gift Card	South America	Mary Scott	2019-04-09	1	1	3482.9380600000004	16.98	10	3482.9380600000004
91f14198-e591-4611-b7e8-19279e0ef9e9	Returned	Amazon Pay	Australia	Crystal Williams	2024-03-12	1	1	990.462072	26.97	6	990.462072
91ffba00-5503-4723-b276-3a992ebb9afa	Cancelled	Gift Card	South America	Caitlyn Boyd	2023-08-09	1	1	324.975024	12.88	3	324.975024
920fd814-3cae-43b0-9d90-b2fa4c0c53e0	Returned	PayPal	South America	Johnny Marshall	2019-02-16	1	1	425.7088	12	8	425.7088
922546ae-91f2-4727-ad22-9fb3f0e20724	Cancelled	PayPal	South America	Diane Andrews	2022-02-23	1	1	2175.81424	29.43	10	2175.81424
923eeadf-f764-4307-969a-f854e7600275	Returned	PayPal	North America	Caitlyn Boyd	2021-03-23	1	1	689.634504	14.59	2	689.634504
9247321d-0620-4705-8a87-fe0f8819db76	Cancelled	Debit Card	North America	Kristen Ramos	2019-08-29	1	1	718.5155520000001	1.96	2	718.5155520000001
9257812b-a24b-4dd7-84c9-38ef539ac8c8	Returned	Debit Card	Europe	Bradley Howe	2022-04-07	1	1	1811.6934	20.47	8	1811.6934
92707d3a-ade5-4b40-8f7e-d32ef18cff34	Cancelled	Debit Card	South America	Caitlyn Boyd	2019-05-09	1	1	634.4814	7.51	4	634.4814
9275933c-86a8-4e5a-bf9e-d6a75d590112	Cancelled	Gift Card	South America	Joseph Brooks	2021-08-30	1	1	1108.5345	18.34	10	1108.5345
92878590-0dab-4125-96d1-16b730563501	Pending	Amazon Pay	Europe	Johnny Marshall	2024-05-23	1	1	70.14492	8.95	8	70.14492
928acd21-d426-40f3-afdb-f6014411d476	Returned	Debit Card	Europe	Jason Nelson	2020-11-15	1	1	2383.12746	22.51	10	2383.12746
928d2ab6-1295-4f25-a24b-20a7e8edd077	Returned	Debit Card	Europe	Steven Coleman	2023-08-29	1	1	228.29252	13.46	1	228.29252
92a118e3-9c7f-4504-9293-482b4ab043f3	Cancelled	PayPal	North America	Jason Nelson	2021-06-29	1	1	302.045214	12.89	6	302.045214
92a23b34-017c-4217-8f40-dd9ea02b9bd0	Returned	Credit Card	North America	Steven Coleman	2020-08-24	1	1	887.5774600000001	4.17	5	887.5774600000001
92ac8e79-90db-46f3-9ed1-2655b382873b	Returned	Debit Card	Asia	Christina Thompson	2019-12-08	1	1	2268.9117990000004	11.89	7	2268.9117990000004
92b29dea-df45-4c67-8d29-c5faf5ed6a25	Returned	Credit Card	Asia	Jason Nelson	2023-01-14	1	1	268.592688	16.42	3	268.592688
92b7de8c-b4e7-4f26-a86e-f7009e0f00dd	Cancelled	Debit Card	North America	Jason Nelson	2019-03-05	1	1	1382.33277	17.45	7	1382.33277
92bcc779-db0d-461e-b794-05a6d9828ca0	Cancelled	Debit Card	Asia	Crystal Williams	2020-11-20	1	1	31.86651	19.1	3	31.86651
92d91e67-6a98-406a-81f1-f4e8b5b5b25f	Pending	Gift Card	Europe	Michelle Andersen	2024-09-22	1	1	172.57653599999998	16.29	4	172.57653599999998
92ed5b03-97a2-423e-8409-87fc75cfe660	Returned	PayPal	Australia	Caitlyn Boyd	2023-03-20	1	1	65.4345	7.5	2	65.4345
931a76c9-cd4e-4b01-820c-8d1d6dd4cb9d	Returned	Credit Card	Australia	Christina Thompson	2020-08-23	1	1	197.17904	4.56	2	197.17904
932abe80-7d06-4360-b1cc-85c31d6788b0	Returned	Credit Card	Europe	Johnny Marshall	2021-01-23	1	1	44.103712	4.62	2	44.103712
932de547-4d03-42ab-94ac-eed9afb645fa	Pending	Credit Card	Europe	Caitlyn Boyd	2024-06-15	1	1	91.75	8.25	10	91.75
932fb25c-4117-421f-a964-ccfd401aa609	Cancelled	Amazon Pay	South America	Diane Andrews	2023-06-16	1	1	2700.8141920000003	8.66	8	2700.8141920000003
9330a381-e2f9-4173-8dce-46831b66c06c	Pending	Debit Card	Asia	Steven Coleman	2020-08-07	1	1	197.869476	25.16	7	197.869476
9338346b-ccf5-40b7-b667-7e1c8c7ac19f	Pending	Debit Card	Europe	Caitlyn Boyd	2024-10-29	1	1	1744.763016	6.44	6	1744.763016
937e00d7-81ac-4619-b53f-8e85963296d6	Cancelled	PayPal	Europe	Bradley Howe	2022-04-21	1	1	696.542115	18.69	5	696.542115
937fa463-1c41-4671-9cb4-3a554586c14c	Cancelled	Amazon Pay	North America	Michelle Garza	2019-03-27	1	1	1605.6762750000005	6.47	5	1605.6762750000005
93819055-cc13-473c-9747-58e6d8455970	Returned	Amazon Pay	Europe	Joseph Brooks	2021-09-09	1	1	2295.5500799999995	1.36	8	2295.5500799999995
939f27c4-2020-4141-9b3b-17b2cf514741	Returned	Debit Card	Europe	Bradley Howe	2020-09-01	1	1	1935.886134	2.46	7	1935.886134
93a97a69-2945-4aa0-a4b5-1bfe8a3e689c	Returned	Credit Card	Asia	Roger Brown	2023-12-31	1	1	1590.5296439999995	6.81	6	1590.5296439999995
93b3d6b3-bd07-4d76-ba09-b8ce0b6d102f	Cancelled	Amazon Pay	Australia	Caitlyn Boyd	2019-01-25	1	1	3061.609232	20.58	8	3061.609232
93bc6a62-20cb-4717-9591-b3b3be7675bb	Pending	PayPal	Europe	Caleb Camacho	2023-10-22	1	1	472.547286	12.13	3	472.547286
93c4d899-86ff-4d7a-ba1a-f6b58d00b3c7	Pending	Gift Card	Europe	Steven Coleman	2022-05-23	1	1	949.5617	14.99	4	949.5617
93e55d7b-9dbd-4530-945a-44f5a2dba3c6	Pending	PayPal	Australia	Jason Nelson	2022-05-24	1	1	1590.07744	10.4	8	1590.07744
93e844f4-2eba-453c-a24d-9f00c0509814	Pending	Amazon Pay	Europe	Sandra Luna	2019-07-13	1	1	944.162366	19.46	7	944.162366
93f73279-24cf-4868-8293-648c9f293a0b	Returned	Amazon Pay	Australia	Caitlyn Boyd	2023-10-10	1	1	732.315084	1.26	2	732.315084
93fc1ec8-4bae-4642-8951-7413654094ea	Cancelled	Amazon Pay	South America	Diane Andrews	2021-10-13	1	1	860.87442	2.77	2	860.87442
9401b3b0-aa0c-4e9d-a757-5b0155832ad0	Cancelled	PayPal	Asia	Adam Smith	2019-06-21	1	1	644.6112	2.92	4	644.6112
940bf0e4-a6f7-4b3a-80dd-ae673526d364	Returned	Amazon Pay	Australia	Joseph Brooks	2020-05-11	1	1	1422.879804	3.16	3	1422.879804
94232ea5-8132-48a7-b9c1-a3293c13247c	Returned	Credit Card	South America	Kristen Ramos	2021-06-20	1	1	1373.9572	4.52	10	1373.9572
94284d8e-b2b2-4212-8e84-e17d733277d7	Returned	Debit Card	North America	Kristen Ramos	2023-12-12	1	1	427.944782	5.94	1	427.944782
9439575e-44d8-4ab3-8bb8-7f95ec8d1d95	Pending	Gift Card	Europe	Caitlyn Boyd	2022-09-15	1	1	1646.56425	20.5	5	1646.56425
94405e90-c51f-4c91-9023-1b580b8778e7	Cancelled	Credit Card	Asia	Christina Thompson	2019-06-04	1	1	405.714552	6.64	1	405.714552
9441e5c6-59b6-48cb-9ad6-1d9b9059c325	Pending	PayPal	Europe	Kristen Ramos	2021-10-26	1	1	1583.312571	2.81	9	1583.312571
944654d8-4ecc-48dc-8a38-17a380647599	Cancelled	Debit Card	Europe	Roger Brown	2024-03-12	1	1	3175.50051	18.1	9	3175.50051
946476ea-3cc0-4358-ac2b-de4a0dfe221b	Cancelled	PayPal	Europe	Christina Thompson	2023-08-22	1	1	275.621873	23.03	1	275.621873
9468c9a3-f674-4531-a732-f5891bf02f4c	Returned	PayPal	Europe	Charles Smith	2024-10-25	1	1	115.409242	11.21	2	115.409242
947001c9-49e8-4a74-958d-96ae982c5638	Returned	Gift Card	Asia	Christina Thompson	2023-08-20	1	1	811.6564699999999	24.77	10	811.6564699999999
94702452-c490-4c9e-9f62-9cd793a64fbd	Returned	Gift Card	North America	Charles Smith	2020-06-27	1	1	1753.125888	21.28	8	1753.125888
947eb78e-bb92-4bc2-9989-2a47d8e5d215	Pending	Credit Card	Europe	Jason Nelson	2023-06-02	1	1	2746.846752	29.83	8	2746.846752
948342ee-3c6e-4fd8-be41-f4a39efd6534	Returned	Gift Card	Asia	Diane Andrews	2019-06-27	1	1	355.039605	20.45	9	355.039605
9489233b-aaeb-45b3-92c8-66f5b33e5309	Pending	PayPal	Asia	Crystal Williams	2020-07-24	1	1	230.77602	1.63	6	230.77602
94c2146a-e700-4faa-97dc-c2782c561ec3	Cancelled	PayPal	North America	Charles Smith	2021-04-14	1	1	559.172208	21.96	2	559.172208
94cced83-80c5-4ae0-8c41-64261c51e40f	Cancelled	Debit Card	South America	Johnny Marshall	2023-01-23	1	1	725.2381200000001	4.36	10	725.2381200000001
94d26d43-31d8-40c7-915e-81667f9c3e32	Cancelled	Debit Card	Europe	Johnny Marshall	2020-09-17	1	1	2416.62346	0.62	10	2416.62346
94ff015f-ef14-4183-9a8e-75600d9546e3	Returned	Credit Card	Europe	Caitlyn Boyd	2021-02-15	1	1	425.685	3.8	2	425.685
9501f878-da86-41fb-b930-5c7b7e70c751	Returned	Amazon Pay	South America	Sandra Luna	2020-02-15	1	1	1429.9361249999995	22.75	5	1429.9361249999995
9519d867-cc21-4677-ba3c-81bec5c5a191	Pending	Credit Card	Australia	Joseph Brooks	2024-02-15	1	1	1135.705868	9.03	4	1135.705868
9520c725-4102-4cbd-8c1c-cc67c035628d	Pending	Credit Card	Asia	Michelle Andersen	2020-04-27	1	1	620.507949	2.67	3	620.507949
95268b9b-4860-476d-97fd-ddee92550ed9	Returned	Debit Card	South America	Michelle Garza	2020-10-30	1	1	1198.1460000000002	20.6	10	1198.1460000000002
952eb99a-7370-47c3-aebe-02d52de9a3ed	Pending	PayPal	Australia	Michelle Garza	2023-07-06	1	1	1795.21353	19.81	10	1795.21353
953a4893-0b84-423c-9ebf-24efee47e1c8	Pending	Amazon Pay	South America	Susan Edwards	2024-04-24	1	1	644.0671299999999	8.63	2	644.0671299999999
9540edd7-3359-4393-82af-13e47aa14791	Returned	Amazon Pay	North America	Kristen Ramos	2024-08-12	1	1	57.544578	21.74	1	57.544578
9544e968-feee-4a20-b808-185cff7f0d0a	Cancelled	Gift Card	Australia	Susan Edwards	2023-01-25	1	1	116.111385	8.35	3	116.111385
95545a61-4ed6-4270-a33c-328db40e7f8d	Pending	PayPal	Australia	Sandra Luna	2023-02-16	1	1	2420.81316	28.52	9	2420.81316
95645f0b-2696-4465-97c3-e606a5cece8f	Pending	PayPal	Australia	Joseph Brooks	2021-02-05	1	1	2444.313672	7.12	9	2444.313672
9581c133-af5e-4fdc-861d-cd67bf6a72f4	Pending	Credit Card	Europe	Sandra Luna	2020-08-13	1	1	1138.065555	0.45	3	1138.065555
9582f082-b53b-4210-aee9-bcfdb1695660	Cancelled	Amazon Pay	Australia	Jason Nelson	2023-07-19	1	1	4011.0616	7.4	10	4011.0616
95adfc76-91d7-4719-b089-16e0b149a771	Returned	Debit Card	Asia	Steven Coleman	2022-12-16	1	1	312.555036	21.06	6	312.555036
95b44c4f-48bd-49f3-b375-3c70f634262f	Cancelled	Credit Card	North America	Mary Scott	2024-09-30	1	1	1402.4863300000002	2.49	5	1402.4863300000002
95d67d0a-25c2-4061-af56-0067f16ebe4b	Cancelled	Amazon Pay	Australia	Bradley Howe	2023-09-07	1	1	2420.123904	13.19	8	2420.123904
95e30dbd-f8e5-455b-9817-26fbe0435046	Pending	Amazon Pay	Asia	Charles Smith	2022-09-03	1	1	2743.67254	7.58	10	2743.67254
95feece2-d573-4a8f-8daf-d7b846f9bb13	Returned	Debit Card	South America	Susan Edwards	2023-02-27	1	1	663.253836	4.36	7	663.253836
96025061-8080-4a61-a5bd-6dfabfe7722a	Returned	Credit Card	Australia	Caitlyn Boyd	2020-04-28	1	1	1369.413744	11.22	6	1369.413744
960c2e2c-8cec-4300-abf2-53392925e082	Returned	Gift Card	South America	Caleb Camacho	2020-03-22	1	1	758.953104	5.49	2	758.953104
96155df7-bdeb-418a-aeaf-12694bd8dc67	Pending	Gift Card	Europe	Sandra Luna	2019-12-22	1	1	2030.460187	12.29	7	2030.460187
962e9c4a-b360-4f30-865a-e5c6f845b7df	Returned	Amazon Pay	Asia	Adam Smith	2024-05-19	1	1	32.821728	20.49	2	32.821728
9644c453-af21-4a17-a0a4-1ca9cdf90cd2	Returned	Credit Card	Europe	Michelle Garza	2020-09-25	1	1	369.445818	16.63	2	369.445818
964aa8a9-962e-41e8-8d64-d05ed6d08675	Pending	Debit Card	Australia	Charles Smith	2021-07-07	1	1	2488.8492720000004	27.28	7	2488.8492720000004
964f6815-98d9-49da-a0b9-ae2d1a515654	Pending	Credit Card	North America	Adam Smith	2022-02-03	1	1	82.06625000000001	20.9	5	82.06625000000001
9662dba9-d86b-4d5e-a646-629c59f80b0e	Pending	Gift Card	South America	Roger Brown	2020-05-11	1	1	391.440852	0.01	2	391.440852
9665eb2e-0b33-4448-ad8f-541addc1b403	Pending	Gift Card	North America	Kristen Ramos	2020-03-31	1	1	2246.325774	17.66	7	2246.325774
9675c671-e4e3-4901-a630-b1187330f246	Pending	Amazon Pay	South America	Jason Nelson	2021-06-29	1	1	989.809086	20.06	3	989.809086
967c0389-056e-4fcb-9a40-fa49108b3963	Cancelled	Amazon Pay	Asia	Roger Brown	2023-09-25	1	1	2022.552	19.74	10	2022.552
9689beea-b0e7-4bdd-a63d-dc44eb4bb87e	Returned	Credit Card	Australia	Christina Thompson	2020-12-27	1	1	232.95096	29.76	3	232.95096
968f00c8-c485-4ad0-a6c3-dfc961280ee6	Cancelled	Debit Card	Asia	Michelle Garza	2022-03-23	1	1	148.12972200000002	13.42	9	148.12972200000002
969d71b0-3559-411a-96fd-bb13fc98cfd6	Pending	Gift Card	North America	Diane Andrews	2022-02-08	1	1	647.8487849999999	0.69	3	647.8487849999999
96d0e25d-4ad0-4b7d-a26b-679b471358c4	Cancelled	Debit Card	South America	Caitlyn Boyd	2022-09-12	1	1	34.467212	1.07	4	34.467212
96dd8805-bb6b-44ee-aa2a-9c430c652960	Cancelled	Gift Card	Europe	Crystal Williams	2023-05-30	1	1	452.19816	27.81	8	452.19816
97037bcc-52e8-45e9-abdc-28af4ba56f3f	Returned	PayPal	Australia	Mary Scott	2023-04-11	1	1	1192.818884	14.01	4	1192.818884
97153ed4-ec9b-4c13-8e78-7244540a1601	Cancelled	PayPal	Europe	Jason Nelson	2020-12-08	1	1	3284.7493120000004	10.88	8	3284.7493120000004
9731e242-a124-4ada-9ff1-c17cab809583	Cancelled	PayPal	Asia	Michelle Andersen	2023-05-01	1	1	2286.51235	23.31	10	2286.51235
97475e5f-eb25-43ba-81cc-02b562f71e51	Returned	Amazon Pay	North America	Kristen Ramos	2024-04-02	1	1	740.648286	8.01	2	740.648286
9757facc-b693-42e8-abce-ed7a6edb88b0	Returned	Amazon Pay	North America	Steven Coleman	2019-09-07	1	1	1518.5247000000002	6.09	6	1518.5247000000002
9760773b-2eea-4468-8d62-75c8fb7a41d3	Cancelled	Credit Card	Asia	Michelle Andersen	2021-07-05	1	1	452.353	15	2	452.353
97639eaa-0af5-4f74-b936-028e12bab46e	Cancelled	Credit Card	Asia	Mary Scott	2024-12-04	1	1	1672.2937	20.25	7	1672.2937
9766507e-ff6c-48e4-99f2-98d74d6968e5	Returned	Debit Card	Asia	Crystal Williams	2024-12-06	1	1	318.265568	23.67	1	318.265568
97705b83-f036-4432-9dc2-57ff15f36649	Returned	Gift Card	Australia	Diane Andrews	2022-11-07	1	1	412.8820079999999	14.48	3	412.8820079999999
9781f7bc-7c39-4ff0-a507-40d415864100	Pending	Gift Card	Australia	Bradley Howe	2021-08-30	1	1	3206.18179	5.57	10	3206.18179
9798f0fb-12c5-4866-8b2a-016344a9fa7c	Pending	PayPal	Australia	Michelle Andersen	2024-02-25	1	1	1768.7714999999998	17	5	1768.7714999999998
979cc9bb-c193-4cb4-823d-3cf8f7403616	Cancelled	Debit Card	Europe	Diane Andrews	2022-05-14	1	1	3049.109875	1.95	7	3049.109875
979f4a87-6960-447c-8520-206f75403811	Returned	Debit Card	Australia	Susan Edwards	2022-12-15	1	1	1671.18105	15.55	5	1671.18105
97a04c27-d1e7-4990-b830-4e13580c22e3	Pending	PayPal	Asia	Michelle Andersen	2020-05-31	1	1	635.3836719999999	16.07	8	635.3836719999999
97c260a6-3c19-4d09-9015-9e21bac0fd5d	Returned	Gift Card	North America	Mary Scott	2022-08-08	1	1	396.695104	3.92	1	396.695104
97ca958b-30a3-41ea-ad05-6fc02d6f061c	Returned	Debit Card	Australia	Christina Thompson	2021-10-05	1	1	2429.726376	2.87	8	2429.726376
97e2c0d1-b174-4fb9-aad9-b78a4ffaa51a	Cancelled	Amazon Pay	North America	Bradley Howe	2023-04-02	1	1	1919.70206	11.51	5	1919.70206
97e7feed-4143-4632-896b-1132a7c811b2	Returned	Amazon Pay	Asia	Joseph Brooks	2019-09-15	1	1	1230.421698	15.91	3	1230.421698
97eb16a8-7038-4bfb-bc98-0b99dc3745d7	Returned	Amazon Pay	Europe	Bradley Howe	2021-04-27	1	1	8.997216000000002	28.48	1	8.997216000000002
97ed456c-59b6-48cd-9397-3346aef8825b	Pending	Amazon Pay	Europe	Emily Matthews	2024-04-10	1	1	988.436638	12.42	7	988.436638
97f1af5b-5db0-4706-b065-3e67dced998d	Cancelled	PayPal	Asia	Michelle Garza	2024-07-16	1	1	151.455969	18.03	9	151.455969
980f780c-f392-4c91-928e-83fee945f29d	Cancelled	PayPal	Europe	Michelle Garza	2019-07-25	1	1	1646.17425	28.75	6	1646.17425
983823df-effd-426f-bedc-cc4b6e3448ea	Returned	PayPal	South America	Susan Edwards	2024-04-20	1	1	9.374076	28.66	1	9.374076
98697a20-ad86-43ad-809b-2736e115189c	Cancelled	Amazon Pay	South America	Christina Thompson	2023-09-02	1	1	265.80287500000003	13.91	5	265.80287500000003
98cbf3eb-92d7-4072-a21d-f610e1e4e6d6	Cancelled	Gift Card	Asia	Bradley Howe	2022-12-08	1	1	1673.034419	15.87	7	1673.034419
98ed2ea9-2f99-476f-9f9b-a9dd8e952605	Pending	PayPal	North America	Jason Nelson	2021-10-20	1	1	369.2186400000001	5.85	1	369.2186400000001
9912d55b-9bbd-4f53-b19b-382ee7a4d8a6	Returned	PayPal	Australia	Sandra Luna	2019-10-07	1	1	235.314898	1.07	2	235.314898
9930338d-e3b0-4cdd-a6bd-fa3ded207ebe	Cancelled	Debit Card	North America	Crystal Williams	2024-09-10	1	1	1296.858174	19.73	6	1296.858174
993f8ab6-e33b-4739-9276-937b247ce06c	Cancelled	Amazon Pay	Europe	Caleb Camacho	2020-06-09	1	1	126.6265	9	5	126.6265
997f38e2-989d-4ec2-8d65-dba4b7156b69	Pending	Credit Card	Australia	Roger Brown	2024-10-14	1	1	1042.3357139999998	29.58	3	1042.3357139999998
99a9566d-5c78-4e77-985f-f3d2247add72	Returned	PayPal	Asia	Sandra Luna	2019-12-13	1	1	1478.39013	29.53	9	1478.39013
99b7312d-b034-40f7-a343-8dc25352880e	Pending	Debit Card	Europe	Caleb Camacho	2023-02-16	1	1	1326.8232	8.5	6	1326.8232
99c108f6-60af-4afa-abaf-b53a81e8ff2f	Returned	Amazon Pay	Asia	Steven Coleman	2021-06-06	1	1	272.26265	13.43	5	272.26265
99c174fe-48f2-47db-a188-91275061f3a5	Pending	PayPal	Australia	Emily Matthews	2020-04-28	1	1	365.977128	11.42	6	365.977128
99cf7b86-f563-43b5-a7e9-92f98d6cdcaf	Returned	Credit Card	Asia	Emily Matthews	2022-05-01	1	1	3881.583882	12.91	9	3881.583882
99d2c10f-f8ec-4347-99e5-327d76526ede	Cancelled	Amazon Pay	Australia	Michelle Andersen	2022-07-06	1	1	1064.415625	18.75	5	1064.415625
99e18286-c925-4a9d-b889-4c5e7ab9e430	Cancelled	PayPal	Asia	Kristen Ramos	2023-04-19	1	1	1768.0819499999998	5.74	5	1768.0819499999998
99e9da8a-43c4-4992-ac66-5353409e8f5e	Returned	Gift Card	South America	Diane Andrews	2020-10-30	1	1	1967.556624	23.66	6	1967.556624
99ea8a0c-d959-4b9f-90bb-d35175b7f142	Returned	Debit Card	South America	Johnny Marshall	2019-07-09	1	1	653.882068	16.44	7	653.882068
9a25edcf-4a53-4824-bdc9-8ec68c6db7a4	Pending	Amazon Pay	Asia	Sandra Luna	2020-08-15	1	1	1908.67724	3.92	5	1908.67724
9a3ec0d0-eef4-47a6-991d-963d9837ce9f	Cancelled	Amazon Pay	South America	Steven Coleman	2023-05-24	1	1	1388.738304	20.56	9	1388.738304
9a5af967-f732-4717-9c2e-f8f12c381187	Returned	Gift Card	Europe	Joseph Brooks	2019-05-19	1	1	3607.664769	8.19	9	3607.664769
9a6baaeb-13af-4427-a1e4-3e7551d5eeb1	Returned	Credit Card	Australia	Kristen Ramos	2023-02-28	1	1	3968.8378	0.63	8	3968.8378
9a6fe446-8d7f-4bdd-ade7-8bf27eec08c6	Returned	PayPal	Australia	Christina Thompson	2023-02-24	1	1	4200.03012	5.56	10	4200.03012
9a7bc63e-9035-431a-877f-97e4c92ea807	Pending	Debit Card	North America	Johnny Marshall	2023-07-31	1	1	53.30670200000001	25.11	2	53.30670200000001
9a944317-b5dd-402e-b568-d8f6d82f6222	Pending	Amazon Pay	Europe	Sandra Luna	2021-10-07	1	1	135.73862400000002	27.86	4	135.73862400000002
9a95cdef-4306-40c8-9a85-538f215cd1e2	Returned	Credit Card	North America	Johnny Marshall	2019-01-28	1	1	2263.5228420000003	9.59	9	2263.5228420000003
9a9859a5-54cc-4f0a-978b-39ec064e5cc0	Pending	Gift Card	South America	Charles Smith	2021-11-05	1	1	1378.2855659999998	22.07	7	1378.2855659999998
9a9beb24-e76c-45e2-a63d-ec02f6a191b6	Returned	Debit Card	South America	Michelle Garza	2023-06-24	1	1	1975.1312	5.6	10	1975.1312
9abc8a4b-c087-4849-931d-79b569594dc0	Pending	Gift Card	Australia	Bradley Howe	2020-04-18	1	1	1178.76987	10.23	6	1178.76987
9ac693f6-9586-45ac-8033-8fab621fd6e4	Cancelled	Debit Card	Australia	Bradley Howe	2020-12-07	1	1	1500.915008	3.56	4	1500.915008
9ae6ecfa-4388-4d33-85bc-866ffa2d22db	Returned	Gift Card	South America	Steven Coleman	2021-10-17	1	1	850.5798719999999	8.64	2	850.5798719999999
9af7670d-d0fc-40ee-b015-6fab767f8246	Returned	Amazon Pay	North America	Mary Scott	2019-08-20	1	1	858.8162719999999	6.21	2	858.8162719999999
9b08edaf-da09-4bca-a9c2-23122b2ab30c	Cancelled	Amazon Pay	Europe	Adam Smith	2024-10-05	1	1	952.083132	4.19	7	952.083132
9b1275c6-3e1e-485e-9dcd-db40cb4a9f32	Cancelled	Gift Card	South America	Charles Smith	2022-02-20	1	1	983.416185	12.69	5	983.416185
9b132b32-8772-4b3b-815b-f3227131efed	Pending	Gift Card	North America	Johnny Marshall	2022-02-10	1	1	1580.55479	28.73	5	1580.55479
9b238b92-f467-48e6-912e-164e0a52d505	Pending	PayPal	Europe	Michelle Andersen	2024-04-30	1	1	171.541224	5.32	1	171.541224
9b4d01eb-9f65-4656-a05a-77efbd004ff8	Returned	PayPal	Europe	Joseph Brooks	2024-03-10	1	1	91.09828	24.6	2	91.09828
9b508730-4376-417a-8314-caf7a9259c02	Pending	Gift Card	North America	Michelle Garza	2021-06-14	1	1	1758.54562	18.23	10	1758.54562
9b55ec6b-562e-472e-9368-7e2a1613e5d1	Cancelled	Gift Card	Asia	Joseph Brooks	2020-05-20	1	1	2021.381928	21.19	8	2021.381928
9b5bc559-5949-45e6-b272-ae5ae648c0dd	Cancelled	Amazon Pay	Asia	Michelle Andersen	2024-03-03	1	1	2024.17124	6.66	10	2024.17124
9b6593c1-2609-466f-8dd5-58a48e2dc602	Cancelled	PayPal	South America	Joseph Brooks	2019-09-11	1	1	776.3295539999999	0.57	6	776.3295539999999
9b7dbd43-5037-4d16-8006-1e6f9d74c45e	Returned	Amazon Pay	Australia	Sandra Luna	2019-07-23	1	1	67.25716800000001	16.18	8	67.25716800000001
9b919a81-2011-4c6d-be68-b2962b6648e0	Pending	PayPal	North America	Jason Nelson	2023-10-27	1	1	3258.1850490000006	10.61	9	3258.1850490000006
9b95bd8c-af9d-43a8-9f9b-9c7e2bfce64b	Pending	Debit Card	Australia	Michelle Garza	2021-03-26	1	1	1990.72464	16.6	8	1990.72464
9ba8ea26-1777-4039-82ef-3b36f04500ef	Cancelled	Gift Card	North America	Mary Scott	2020-05-26	1	1	226.37466	3.01	5	226.37466
9bb560ce-db83-4b77-a06b-782cbe0f9c59	Pending	Gift Card	Australia	Adam Smith	2022-09-01	1	1	2914.7628510000004	9.77	9	2914.7628510000004
9bc671e0-64e9-4667-9fa0-7b18a1fdf612	Pending	Amazon Pay	Asia	Susan Edwards	2021-02-04	1	1	150.932892	27.17	1	150.932892
9bca8032-d292-4696-9833-3acb6775f198	Pending	Amazon Pay	South America	Steven Coleman	2022-09-04	1	1	2696.565852	14.84	9	2696.565852
9bf032a8-d32a-403e-89f8-9e02815299d6	Pending	Amazon Pay	Asia	Caitlyn Boyd	2024-01-01	1	1	143.447598	20.62	1	143.447598
9bfc7b4a-198d-4129-addc-0a83173a4b3d	Cancelled	Credit Card	Europe	Roger Brown	2023-12-14	1	1	1511.77824	3.24	9	1511.77824
9c0536df-c375-42e7-81bf-692efdfb9c55	Cancelled	Credit Card	Australia	Charles Smith	2021-11-24	1	1	397.942461	1.37	9	397.942461
9c314dd3-5854-48ae-a116-64034621cc0b	Returned	PayPal	Australia	Sandra Luna	2023-02-11	1	1	33.031272	14.78	3	33.031272
9c35beed-7a11-4137-a95e-fbcdff86aca2	Pending	Credit Card	Asia	Sandra Luna	2020-04-21	1	1	3806.31416	16.88	10	3806.31416
9c3f28b3-63f0-4b6e-bbd3-2b27950c2146	Returned	Credit Card	Asia	Adam Smith	2023-11-21	1	1	2209.9636020000003	11.67	7	2209.9636020000003
9c574f35-af22-47be-8ee8-9119af44fa92	Pending	Debit Card	North America	Bradley Howe	2020-11-02	1	1	183.377753	5.49	1	183.377753
9c5ddff3-c835-4b83-b261-f685dfe31abc	Pending	Amazon Pay	North America	Michelle Garza	2020-12-09	1	1	2126.92272	26.94	10	2126.92272
9c62098c-9ea4-4248-bf64-18267566d56f	Returned	Credit Card	North America	Diane Andrews	2023-04-18	1	1	793.9045759999999	25.34	4	793.9045759999999
9c95a17f-ec41-4095-9c29-6b7f49dee960	Returned	Credit Card	Australia	Caleb Camacho	2019-10-24	1	1	1514.54016	20.92	4	1514.54016
9c9d5ad3-8760-420e-83f7-06a87944d485	Pending	PayPal	Europe	Caleb Camacho	2021-10-03	1	1	980.3934	3.4	10	980.3934
9c9fbdc8-f24b-47a5-ad34-1693557f028c	Pending	Gift Card	North America	Johnny Marshall	2019-07-28	1	1	233.63168	8.88	10	233.63168
9ca3d39b-4d78-4306-968b-fe3483472768	Pending	Gift Card	Australia	Michelle Andersen	2024-04-27	1	1	2654.07536	21.12	10	2654.07536
9cad1cd3-3ea0-4744-b802-acaa0fd37d31	Returned	Gift Card	North America	Emily Matthews	2024-12-12	1	1	457.306704	2.36	9	457.306704
9cadc028-3b3a-489a-bb6d-535c68a9aae8	Cancelled	Debit Card	Australia	Michelle Garza	2021-03-06	1	1	2488.740992	28.56	8	2488.740992
9cafae81-a99b-485c-819f-8aeae0c5be04	Returned	Amazon Pay	Australia	Christina Thompson	2022-05-14	1	1	1581.8896799999998	23.28	5	1581.8896799999998
9cb25f9b-9b15-42e4-95b8-8f0884e8ba13	Pending	Credit Card	North America	Kristen Ramos	2020-06-26	1	1	1976.86062	9.31	9	1976.86062
9cb8c773-b0f8-4d61-9652-f8d285c199c2	Returned	Credit Card	Asia	Susan Edwards	2021-01-12	1	1	1289.2428719999998	2.17	8	1289.2428719999998
9cbc111e-e27e-486e-bb8d-37b97269227b	Cancelled	Gift Card	South America	Roger Brown	2022-11-17	1	1	979.53345	6.13	10	979.53345
9cd6c4b0-cf91-4111-8141-35011e373be2	Cancelled	Debit Card	Asia	Michelle Andersen	2019-05-20	1	1	2244.6219740000006	2.73	7	2244.6219740000006
9d0828c8-41de-44f5-bffb-0f9c02bbd0c2	Cancelled	Debit Card	Australia	Diane Andrews	2022-12-27	1	1	445.998848	7.76	4	445.998848
9d0caa83-cb2a-4ea1-9d6e-6007b4e0f5a7	Pending	Debit Card	South America	Sandra Luna	2024-12-12	1	1	397.0092	27.52	5	397.0092
9d1642e0-0406-423b-ae8f-84233f39661f	Cancelled	Credit Card	Europe	Mary Scott	2023-09-06	1	1	2580.1536	2.4	6	2580.1536
9d210d08-86a0-466f-b006-48377d74db8c	Pending	Gift Card	Europe	Sandra Luna	2024-09-28	1	1	626.32768	5.4	8	626.32768
9d215667-8428-4112-b985-3130d71e64b0	Pending	Gift Card	Asia	Steven Coleman	2021-02-09	1	1	354.263992	10.98	1	354.263992
9d41547e-9e1c-4a7d-bef7-422f2fe01570	Pending	Credit Card	Asia	Michelle Andersen	2022-04-09	1	1	720.2542159999999	27.02	4	720.2542159999999
9d496678-9818-494a-83c5-2e0026f52712	Returned	Gift Card	Europe	Charles Smith	2020-07-16	1	1	1779.8327820000002	28.54	7	1779.8327820000002
9d4eb04e-d3fc-494a-b753-9224891e6671	Returned	Credit Card	Australia	Charles Smith	2023-05-31	1	1	267.255343	13.49	1	267.255343
9d617e16-8aa8-4ff3-8b3a-bf384a6f57af	Pending	PayPal	South America	Johnny Marshall	2024-06-12	1	1	322.577208	10.44	1	322.577208
9d809a2e-7eb6-4700-8130-2fd846231c71	Pending	PayPal	North America	Caitlyn Boyd	2024-10-15	1	1	1958.015865	6.79	5	1958.015865
9d86c257-b765-4666-bc8c-0e5a2d3598db	Cancelled	PayPal	North America	Steven Coleman	2021-02-05	1	1	250.80228	10.81	1	250.80228
9d94371d-7c89-4d89-815f-db52729e1d15	Pending	Credit Card	South America	Johnny Marshall	2021-07-08	1	1	220.25528	4.07	7	220.25528
9d952985-a734-41ca-8746-034a749b9f25	Pending	Amazon Pay	Australia	Christina Thompson	2023-10-12	1	1	104.735403	23.79	9	104.735403
9db24e75-030b-4dac-a981-4f5292c37e39	Returned	Amazon Pay	Australia	Roger Brown	2019-01-19	1	1	908.613096	18.39	8	908.613096
9dc09ff4-b363-4eb0-b5e5-05b22c92256a	Cancelled	PayPal	Australia	Mary Scott	2019-08-17	1	1	1784.7108480000002	22.08	6	1784.7108480000002
9dd1aa4f-67da-4ba3-96a2-d0ed5c26b80d	Pending	PayPal	Europe	Christina Thompson	2024-04-20	1	1	710.0830800000001	9.7	6	710.0830800000001
9df95022-920a-467e-a9c2-57f78ffaf660	Cancelled	Credit Card	Asia	Caleb Camacho	2023-03-14	1	1	281.061774	21.81	9	281.061774
9e0255fb-efe2-471e-abc3-f3818df388b7	Cancelled	Debit Card	Asia	Emily Matthews	2019-09-01	1	1	780.68097	3.78	9	780.68097
9e06e033-6027-4276-8b9b-fdd68a038f1b	Cancelled	PayPal	South America	Caleb Camacho	2021-08-15	1	1	1995.437808	24.73	6	1995.437808
9e08eff9-ea15-4d12-8660-effa8659be41	Cancelled	Debit Card	Asia	Johnny Marshall	2024-06-06	1	1	269.162862	27.21	2	269.162862
9e0d6687-1471-47c7-872c-f7c8d79f5bc6	Returned	Debit Card	Europe	Caitlyn Boyd	2020-10-12	1	1	3074.862322	4.47	7	3074.862322
9e283c31-a3f0-4658-9acb-f4b4bdbefddc	Returned	Amazon Pay	Europe	Steven Coleman	2023-06-14	1	1	254.526363	29.41	7	254.526363
9e5046a0-d860-4db9-b88b-0bb81a5f78e0	Pending	Debit Card	South America	Kristen Ramos	2023-05-19	1	1	539.262048	28.24	2	539.262048
9e8068aa-85f6-4832-a397-901ba0744e1f	Returned	PayPal	Europe	Diane Andrews	2022-05-02	1	1	3380.82484	21.78	10	3380.82484
9ecc874f-719c-4ba9-ba7a-a181f12e8695	Pending	Gift Card	North America	Diane Andrews	2022-12-06	1	1	7.389758	6.93	1	7.389758
9ee17d0e-95e7-4c7c-9c60-90be692331c5	Cancelled	PayPal	Asia	Mary Scott	2023-03-07	1	1	331.525661	20.07	1	331.525661
9ef683b4-b21d-4adc-8124-22b76953e3a7	Cancelled	PayPal	Asia	Michelle Garza	2023-07-07	1	1	1083.22101	6.1	3	1083.22101
9f0b9c23-a029-4903-96c2-389d769d5a7b	Returned	Debit Card	South America	Sandra Luna	2019-06-15	1	1	2547.53082	9.85	6	2547.53082
9f282b9f-f07a-4ec0-bcc9-ac9d5d397ef5	Pending	Amazon Pay	North America	Bradley Howe	2019-07-30	1	1	80.93471399999999	13.78	9	80.93471399999999
9f3b54a4-7aa9-4e7d-8b11-981c4f0b815e	Returned	Credit Card	Australia	Johnny Marshall	2021-08-16	1	1	171.13387200000005	20.83	1	171.13387200000005
9f47cb26-1911-4caf-911e-f92b096da94d	Cancelled	Debit Card	Asia	Caitlyn Boyd	2019-06-17	1	1	1642.8055049999998	11.67	9	1642.8055049999998
9f530471-0885-44f7-bad8-ac9002327a29	Cancelled	Amazon Pay	South America	Bradley Howe	2023-03-17	1	1	1883.9806160000005	17.88	7	1883.9806160000005
9f5f201b-97df-4337-95d8-04e4cc724433	Pending	Credit Card	South America	Sandra Luna	2022-03-02	1	1	3910.8096	8	9	3910.8096
9f8b8211-5dcc-425d-8672-8ad3876e71fc	Pending	Amazon Pay	North America	Susan Edwards	2020-09-03	1	1	904.727808	10.72	8	904.727808
9faa4f4c-fa2c-46c7-80d0-6e12bb2da14c	Pending	Debit Card	North America	Caitlyn Boyd	2020-08-27	1	1	4108.57326	15.82	10	4108.57326
9fbc5a64-171e-4fe7-9e83-6e2b52a77b26	Pending	Debit Card	Australia	Charles Smith	2023-08-27	1	1	496.541472	29.74	8	496.541472
9fe4e4b9-de2a-4957-85e6-c7f895d19466	Cancelled	Credit Card	Europe	Bradley Howe	2019-10-28	1	1	120.359288	10.26	1	120.359288
9fec0a69-d681-4cb0-8b79-d0e58e43247f	Pending	PayPal	Asia	Emily Matthews	2024-12-19	1	1	54.33002100000001	12.13	9	54.33002100000001
9ff50551-9880-4de6-974c-7e4b74cb779b	Cancelled	Gift Card	Asia	Caleb Camacho	2022-01-05	1	1	304.41584	22.2	1	304.41584
a0218b7c-0752-4125-af2d-7f674472684e	Cancelled	Gift Card	Australia	Joseph Brooks	2020-09-17	1	1	2071.082328	8.36	7	2071.082328
a0359982-bc78-4c3d-8bc4-9a8ec67b5b11	Returned	Amazon Pay	North America	Jason Nelson	2022-06-28	1	1	2854.2325950000004	15.17	9	2854.2325950000004
a042bc86-04c1-439d-a561-29c357129fe9	Returned	Credit Card	Australia	Michelle Garza	2019-07-26	1	1	610.5625109999999	13.17	3	610.5625109999999
a055618a-e51e-4e52-a8ce-6878f1502042	Pending	Debit Card	Asia	Crystal Williams	2020-12-02	1	1	578.5111079999999	12.49	7	578.5111079999999
a071d56b-2034-44aa-86b1-5ea86266a425	Cancelled	Credit Card	South America	Michelle Garza	2021-10-16	1	1	337.96592000000004	18.68	2	337.96592000000004
a085baf1-800d-432b-be19-3056789330b2	Cancelled	Debit Card	Asia	Crystal Williams	2020-07-05	1	1	612.269216	29.54	4	612.269216
a0894694-4de7-477c-b591-a273043c3127	Cancelled	Amazon Pay	North America	Mary Scott	2022-07-13	1	1	3575.6100799999995	18.24	10	3575.6100799999995
a0b61f2e-aa8c-4e1c-8787-abd109bf1075	Cancelled	PayPal	Europe	Michelle Andersen	2020-05-09	1	1	1373.5520299999998	29.63	5	1373.5520299999998
a0bc99a1-f7f4-4b1f-b0c0-42742161c02a	Returned	Amazon Pay	North America	Adam Smith	2023-01-06	1	1	407.690236	16.22	2	407.690236
a0c94290-d477-4560-955d-1aeec74dbe28	Cancelled	PayPal	Europe	Caleb Camacho	2021-09-22	1	1	29.763398	4.02	1	29.763398
a0e19962-d53a-46a2-a76a-ccb198b60a46	Cancelled	Debit Card	Asia	Diane Andrews	2022-02-05	1	1	2780.9829	23.41	10	2780.9829
a0e21195-e527-4ab9-b5d8-84182f0e88cc	Pending	Debit Card	South America	Caleb Camacho	2022-08-16	1	1	39.591648	4.09	1	39.591648
a0fbd625-07d1-462b-87d6-3b2bd2cff605	Returned	PayPal	South America	Emily Matthews	2022-11-27	1	1	2325.882112	17.16	8	2325.882112
a0fc227d-b775-482b-a611-4b0109f395c5	Returned	Debit Card	Asia	Bradley Howe	2020-03-16	1	1	382.387474	12.02	1	382.387474
a0fe90f6-bb8b-4f9d-a32d-3ecc2610e781	Pending	Amazon Pay	Australia	Caitlyn Boyd	2022-12-15	1	1	343.380096	16.72	4	343.380096
a103b8dd-953d-4029-94d7-fdbf7074c85d	Returned	PayPal	Europe	Michelle Andersen	2023-02-26	1	1	108.02715	6.47	1	108.02715
a10add01-cbca-4a7c-8954-3d0e3e2e6e41	Cancelled	Amazon Pay	Asia	Jason Nelson	2021-10-13	1	1	53.434892000000005	15.93	1	53.434892000000005
a1158856-fb65-4a43-9150-a7a084dd7f4c	Returned	Gift Card	Europe	Roger Brown	2022-07-03	1	1	1595.38278	7.72	5	1595.38278
a115cb0e-98a0-465a-84a4-2a386df941f3	Pending	Credit Card	Europe	Bradley Howe	2024-07-01	1	1	1895.29257	5.45	6	1895.29257
a1293984-7714-473d-bae2-e3e520e8875d	Cancelled	Debit Card	South America	Michelle Garza	2024-08-30	1	1	2650.483328	4.56	8	2650.483328
a1417428-7c3d-4ee1-b0a1-21bc7eb00675	Returned	Amazon Pay	Australia	Bradley Howe	2019-07-26	1	1	2606.212512	25.32	9	2606.212512
a151bd4d-05d5-4685-aa06-968ba0f8adbd	Cancelled	Debit Card	Asia	Adam Smith	2022-11-10	1	1	1370.2659180000005	18.97	7	1370.2659180000005
a15b276f-c82b-4196-9159-25e0c8154c47	Returned	Debit Card	South America	Caitlyn Boyd	2020-12-04	1	1	929.90952	21.52	5	929.90952
a1633d85-76f7-418e-a34c-b6224957cc97	Pending	Gift Card	Asia	Michelle Andersen	2021-05-18	1	1	1657.5254999999995	23.5	5	1657.5254999999995
a16942f5-3db4-4618-9922-03fcf9163f02	Pending	Debit Card	Europe	Crystal Williams	2024-06-16	1	1	123.144	26.7	6	123.144
a17023f0-e11f-48b0-913b-73f3bb0550de	Cancelled	Debit Card	Asia	Michelle Garza	2024-12-16	1	1	274.8666	9.5	2	274.8666
a182d0ce-2f83-421b-81c1-f46e64b4bb95	Pending	PayPal	Asia	Crystal Williams	2022-09-16	1	1	114.322296	29.01	2	114.322296
a1893c84-cff3-49e4-b02f-acf4f4b845c2	Cancelled	Amazon Pay	Asia	Bradley Howe	2023-04-21	1	1	68.536746	25.39	3	68.536746
a1956caf-59ec-4a96-b7de-13375ea1ba3b	Cancelled	Gift Card	North America	Emily Matthews	2022-07-14	1	1	2039.676675	14.47	5	2039.676675
a1a3b6bd-bb4e-4c25-90b8-b894fb500f9a	Cancelled	Gift Card	Australia	Sandra Luna	2021-10-13	1	1	2828.47432	2.88	7	2828.47432
a1ac4dcc-d4be-45ef-8b74-691b28ee62ed	Cancelled	Gift Card	Asia	Mary Scott	2019-06-27	1	1	52.201944	23.48	1	52.201944
a1ccef02-3c7a-49c5-857c-b8cc48b79fe4	Returned	Gift Card	South America	Susan Edwards	2023-08-21	1	1	781.1146979999999	25.38	3	781.1146979999999
a1cd01d3-94ad-44a5-9637-5fa2eaa2f5da	Pending	Amazon Pay	South America	Diane Andrews	2023-12-03	1	1	531.380412	26.04	9	531.380412
a1cefec6-f8e5-4dbd-adf9-2da16c241fc4	Returned	Credit Card	Asia	Diane Andrews	2023-04-30	1	1	81.38459999999999	2.65	2	81.38459999999999
a1d26c6d-eb33-455e-8a0f-eb62abd19085	Pending	PayPal	Europe	Crystal Williams	2019-12-22	1	1	3816.133902	12.39	9	3816.133902
a1d28e94-705e-420d-b1a3-b3daea0c4c03	Returned	Credit Card	Europe	Diane Andrews	2024-11-14	1	1	2248.477842	19.77	6	2248.477842
a1fb4716-a743-4d29-b3de-a284db36dcff	Pending	Credit Card	Australia	Christina Thompson	2024-11-09	1	1	2031.73225	17.3	5	2031.73225
a206c1e7-52b3-49b9-b0ee-3145a21c1a9f	Cancelled	Debit Card	Australia	Bradley Howe	2022-08-06	1	1	1788.010146	6.79	6	1788.010146
a213e655-6a2f-4ebb-8013-b9cd41b54d32	Pending	Debit Card	Europe	Susan Edwards	2019-08-11	1	1	808.930665	25.81	9	808.930665
a22f8335-2fbf-4a23-8e18-b99e4d15d533	Cancelled	Credit Card	Australia	Crystal Williams	2020-02-08	1	1	768.676896	25.68	3	768.676896
a23be0cf-4ef3-4f3a-abc2-2d2ab152a8f7	Pending	Debit Card	Asia	Michelle Garza	2024-11-08	1	1	2319.27552	29.77	10	2319.27552
a2662098-670e-457a-9995-be8864732001	Cancelled	Credit Card	Asia	Johnny Marshall	2023-06-05	1	1	667.0840049999999	29.55	3	667.0840049999999
a27064e3-70fc-4a0e-ba0e-2cdc1ffef273	Cancelled	PayPal	South America	Michelle Garza	2023-03-28	1	1	886.982924	2.79	2	886.982924
a290f84e-8034-4532-9688-4c95fbc447e6	Cancelled	PayPal	North America	Susan Edwards	2022-06-03	1	1	279.5142	14.6	2	279.5142
a293c646-775f-4d60-b771-259947f97632	Cancelled	Gift Card	South America	Diane Andrews	2023-11-06	1	1	805.910103	11.49	9	805.910103
a2b330d6-1013-495d-bdcb-2b54eadec4eb	Returned	Debit Card	Europe	Jason Nelson	2021-05-17	1	1	1729.243928	3.18	4	1729.243928
a2b37fb8-0c09-45e1-9094-89056d269d71	Cancelled	Credit Card	North America	Roger Brown	2020-06-07	1	1	949.08522	20.04	3	949.08522
a2bde03b-32e3-4656-b482-bf198ffcb8e2	Returned	Debit Card	South America	Sandra Luna	2020-10-09	1	1	1225.269808	3.92	7	1225.269808
a2c75c74-efd0-43f4-81b0-37e7c0a3983f	Pending	Gift Card	North America	Caitlyn Boyd	2022-09-07	1	1	274.612025	6.99	1	274.612025
a2f2fdb0-a3b0-4fa9-b00c-2c2d67a40295	Cancelled	Amazon Pay	North America	Michelle Garza	2019-04-19	1	1	2964.69624	17.88	10	2964.69624
a3004dc6-1119-4199-830d-655687efd20d	Pending	PayPal	South America	Michelle Garza	2022-12-26	1	1	945.126138	13.89	6	945.126138
a3034861-38dd-4fcf-81e9-bbbe356e374e	Cancelled	PayPal	Asia	Crystal Williams	2022-03-17	1	1	198.063626	10.11	2	198.063626
a30c9a15-3833-43c4-a01a-cf52001d3f4d	Returned	Amazon Pay	South America	Johnny Marshall	2020-04-26	1	1	1321.907796	0.01	3	1321.907796
a3173a93-bae6-4785-8e62-823bb0065e80	Pending	Amazon Pay	Europe	Christina Thompson	2023-08-01	1	1	2311.353888	4.54	8	2311.353888
a3427b43-481b-4183-8a82-447087f29712	Pending	Gift Card	South America	Kristen Ramos	2022-01-06	1	1	1891.9680080000005	16.08	7	1891.9680080000005
a37e3066-e8b4-48b8-9751-5afb0db80898	Returned	Debit Card	Australia	Caitlyn Boyd	2021-06-14	1	1	1425.432576	25.16	4	1425.432576
a387cda9-9ab2-41d3-80b9-47653eafcc87	Returned	Gift Card	Australia	Bradley Howe	2021-07-10	1	1	2821.0336	17.61	10	2821.0336
a3a3ade6-f9d4-458c-8d97-64914daa5569	Pending	Debit Card	Europe	Johnny Marshall	2019-06-07	1	1	354.06536400000005	15.56	1	354.06536400000005
a3b41c69-ffce-484a-88d6-733edfcf0118	Returned	Credit Card	Europe	Jason Nelson	2019-08-29	1	1	191.409946	1.71	2	191.409946
a3fbb8e6-3573-41cd-a559-f79d9a7b73ea	Pending	Debit Card	South America	Michelle Garza	2021-07-26	1	1	574.72353	3.45	2	574.72353
a402aded-483e-4b4c-8f15-2fb1e37806ac	Cancelled	Debit Card	Europe	Susan Edwards	2020-11-19	1	1	802.23976	29.43	7	802.23976
a40c1882-b06b-45fd-8ab0-b0f27baa415a	Cancelled	PayPal	South America	Kristen Ramos	2021-12-23	1	1	1734.5876849999995	20.71	5	1734.5876849999995
a410cdc7-66f6-4744-8bbd-708a55e81b23	Cancelled	PayPal	North America	Diane Andrews	2021-11-06	1	1	1059.726365	26.39	5	1059.726365
a4187d4e-2dfd-414e-b62f-8d215c415ab8	Cancelled	Amazon Pay	Australia	Caleb Camacho	2022-08-27	1	1	755.2343040000001	15.52	2	755.2343040000001
a41944a2-1d32-4778-80d7-1183104177d8	Returned	Amazon Pay	North America	Emily Matthews	2024-05-16	1	1	1183.222887	12.99	3	1183.222887
a4195458-9b2c-4908-8555-74712c2df126	Returned	Amazon Pay	Europe	Caleb Camacho	2019-09-12	1	1	895.2803040000001	1.34	6	895.2803040000001
a419c60b-19a4-44d4-8cbb-e87969db6268	Cancelled	Debit Card	Australia	Roger Brown	2020-01-13	1	1	3404.999	3.8	10	3404.999
a428c1d8-c187-42ea-9764-4435c45dba24	Cancelled	Debit Card	North America	Joseph Brooks	2021-12-19	1	1	370.27296	0.4	6	370.27296
a4333e05-df74-4ea5-8770-973fa6446810	Cancelled	PayPal	North America	Sandra Luna	2023-05-23	1	1	2004.2953280000004	28.08	7	2004.2953280000004
a43d5389-8c79-48ba-82cb-65a424426490	Pending	Amazon Pay	South America	Charles Smith	2023-03-23	1	1	1931.24731	9.06	5	1931.24731
a4654f80-8001-4fd2-9d05-59fcf00475de	Pending	Credit Card	South America	Christina Thompson	2020-01-16	1	1	1140.52801	11.46	5	1140.52801
a46bbbbe-8286-45ca-88f1-376deeb089f2	Cancelled	Credit Card	Asia	Emily Matthews	2021-01-12	1	1	187.468392	26.93	4	187.468392
a47933d3-952d-4e10-89ee-ff0a24a293d1	Cancelled	Gift Card	Asia	Christina Thompson	2024-11-23	1	1	54.436374	18.19	3	54.436374
a47963d8-77dd-4395-8aeb-ac45553ffe5c	Cancelled	Gift Card	Australia	Michelle Andersen	2019-04-22	1	1	1204.2795150000002	1.95	9	1204.2795150000002
a479882f-e7db-4e7f-8478-bbb3d33181b5	Cancelled	Amazon Pay	South America	Steven Coleman	2020-07-02	1	1	114.590824	1.01	4	114.590824
a4876e9f-2b76-495d-a62d-ca88ee9a55e5	Cancelled	Amazon Pay	Europe	Kristen Ramos	2021-02-12	1	1	231.75046	29.73	1	231.75046
a491bf83-b365-4f2b-b8cf-fa6d1b691fbf	Cancelled	Amazon Pay	Australia	Adam Smith	2023-07-29	1	1	211.171752	6.94	2	211.171752
a49a4bce-cdfd-4708-bf23-e46c083c7957	Cancelled	Credit Card	Australia	Bradley Howe	2019-11-25	1	1	496.93807	1.82	5	496.93807
a49c1c32-e128-4538-8b0e-4108dedb4246	Cancelled	Debit Card	Europe	Bradley Howe	2022-05-23	1	1	349.200467	19.37	7	349.200467
a4a130b0-f4d6-424f-aa93-40e8d85c882a	Cancelled	PayPal	North America	Jason Nelson	2020-01-13	1	1	1083.75921	1.27	5	1083.75921
a4ae4954-ad90-4458-bf2c-bb3b4a4f8f46	Cancelled	Amazon Pay	Europe	Christina Thompson	2019-09-17	1	1	90.176544	29.24	4	90.176544
a4b448ac-7dba-4619-a870-54cb1a4b3766	Pending	PayPal	South America	Johnny Marshall	2024-02-15	1	1	2101.41729	20.77	9	2101.41729
a4b55e3a-cc06-4909-9fea-846f80e25edb	Pending	Debit Card	Europe	Kristen Ramos	2024-04-16	1	1	611.495102	15.03	2	611.495102
a4d318e2-50bf-4373-8700-8ffa4e1939a6	Returned	Gift Card	Europe	Joseph Brooks	2024-12-15	1	1	192.312762	9.89	3	192.312762
a4e9c606-352e-49e2-9de8-04b3fa48aaae	Cancelled	Credit Card	Europe	Caleb Camacho	2023-04-14	1	1	1745.655525	29.35	5	1745.655525
a4eceb3a-781d-428e-9b52-39c764d6be7e	Pending	Debit Card	North America	Bradley Howe	2024-06-10	1	1	354.510448	10.88	1	354.510448
a4ffa380-3ef4-490e-a470-bb3d8af82e17	Returned	Amazon Pay	Europe	Joseph Brooks	2024-03-24	1	1	244.08314400000003	10.71	8	244.08314400000003
a50063f3-0fc3-42e9-8add-bb05177a39e5	Returned	PayPal	Europe	Michelle Andersen	2021-10-18	1	1	1169.589351	29.77	7	1169.589351
a502dc0c-c1de-486c-8670-c272f250b34c	Cancelled	Credit Card	Europe	Caitlyn Boyd	2020-04-29	1	1	601.64676	10.1	4	601.64676
a50a8256-ccf0-4574-bad8-4aeda1d04eca	Cancelled	Debit Card	South America	Steven Coleman	2023-04-02	1	1	21.866694000000003	15.54	1	21.866694000000003
a51488ff-5f6a-410f-a490-33abe72ff52f	Pending	Amazon Pay	North America	Diane Andrews	2019-01-23	1	1	331.951887	4.51	1	331.951887
a5186490-26a6-43d2-bd1c-4fce4275df43	Pending	Gift Card	Asia	Emily Matthews	2021-08-25	1	1	287.61705	23.5	1	287.61705
a51b16ed-010d-4e2f-997c-97f7f26fb50a	Cancelled	Gift Card	South America	Crystal Williams	2024-01-25	1	1	574.931784	29.22	3	574.931784
a53d332d-1bfe-46a1-94f6-1f2598ffb81b	Pending	Gift Card	Asia	Sandra Luna	2024-12-06	1	1	2131.759539	15.89	7	2131.759539
a54ce946-ddad-4b8a-ba3b-bb284c4d93ca	Pending	Debit Card	Australia	Steven Coleman	2020-02-08	1	1	1468.898496	14.71	6	1468.898496
a570cdff-10c6-4e18-94d5-fed6788e07d7	Pending	Credit Card	Europe	Kristen Ramos	2024-06-09	1	1	168.29614800000002	20.63	4	168.29614800000002
a57bdb85-bb0c-4abf-9c3b-be8f26597001	Returned	Debit Card	North America	Sandra Luna	2019-03-12	1	1	398.08859999999993	19.5	1	398.08859999999993
a588b701-59b2-48be-bdf3-a233f8fe8800	Returned	Amazon Pay	Asia	Sandra Luna	2022-07-17	1	1	163.415	9.84	5	163.415
a5953aa0-0c9d-4309-81ab-9504df10370e	Returned	Credit Card	North America	Bradley Howe	2023-01-15	1	1	77.674248	2.81	6	77.674248
a5afdc41-e69a-4f57-b17e-b10ab4febbeb	Returned	Amazon Pay	South America	Steven Coleman	2019-09-19	1	1	170.76994399999998	10.14	2	170.76994399999998
a5b394f5-535b-4cbe-b3c3-c039e2165da0	Pending	Debit Card	North America	Steven Coleman	2022-04-08	1	1	1306.398408	3.47	4	1306.398408
a5b45fa7-417c-4972-b339-99040b136a4e	Returned	PayPal	Australia	Steven Coleman	2023-10-23	1	1	883.824879	9.51	7	883.824879
a5b5b383-cd1f-4f54-86e9-8fa20a7e6ad6	Pending	Debit Card	North America	Adam Smith	2024-04-29	1	1	29.07586	2.43	4	29.07586
a5b75982-ae66-49d3-b643-7476d81768ff	Returned	Amazon Pay	South America	Christina Thompson	2022-06-17	1	1	3287.0085120000003	21.72	9	3287.0085120000003
a5b898d0-9510-47a5-9aa5-59a725a0fde5	Returned	Amazon Pay	Europe	Kristen Ramos	2021-06-18	1	1	2377.083303	26.57	9	2377.083303
a5c4d438-4faf-4ec6-8c2f-3770801fcce0	Returned	Debit Card	North America	Charles Smith	2024-10-26	1	1	1427.57424	16.34	6	1427.57424
a5cf7f4f-cd52-453c-823c-84f22e20f583	Pending	Credit Card	Asia	Roger Brown	2022-07-18	1	1	2133.8992980000003	18.61	6	2133.8992980000003
a5f9e175-51bc-4cf2-9c7a-fa75fd7adde8	Cancelled	Debit Card	North America	Michelle Garza	2021-06-20	1	1	2665.0624	19.92	10	2665.0624
a602d4a8-b50b-485c-abbc-c2f36c5c6042	Returned	Gift Card	Europe	Michelle Garza	2023-09-08	1	1	737.9818	11.75	2	737.9818
a606bfcd-7181-47b0-bc89-5d209bef81fe	Pending	Gift Card	Asia	Mary Scott	2020-12-05	1	1	712.372608	28.64	6	712.372608
a606e5a2-9d28-4430-8456-ce04b32c0c3d	Cancelled	Amazon Pay	Europe	Adam Smith	2022-06-06	1	1	612.63342	22.7	7	612.63342
a613cc00-7a20-4bd4-b5e2-ce34a4e9a49f	Returned	Amazon Pay	Europe	Charles Smith	2023-12-13	1	1	2594.019337	2.37	7	2594.019337
a61aee9f-9bec-4248-873d-31d408cc81b7	Cancelled	Credit Card	North America	Susan Edwards	2019-08-30	1	1	434.741608	2.64	7	434.741608
a61d004f-a848-4915-913d-ca746ccff513	Cancelled	Amazon Pay	Europe	Diane Andrews	2019-08-06	1	1	822.791296	25.88	8	822.791296
a61f483f-4faa-44c8-9af6-6420ce1ba1b7	Cancelled	PayPal	Asia	Sandra Luna	2019-03-08	1	1	2103.581394	9.22	9	2103.581394
a638fd20-009f-4132-8ace-9641deb752e0	Returned	Gift Card	Asia	Joseph Brooks	2019-02-16	1	1	297.407916	26.68	9	297.407916
a63cd58f-fc7f-4750-a3f5-1a120174032b	Pending	PayPal	Asia	Adam Smith	2019-10-03	1	1	3095.24328	15.4	9	3095.24328
a6479558-f028-4b6d-afd3-5afc5229f255	Returned	Gift Card	South America	Kristen Ramos	2021-11-04	1	1	1829.473716	12.02	7	1829.473716
a651c359-10b1-41f9-a2d1-ea0df067c211	Returned	Amazon Pay	Australia	Michelle Andersen	2024-10-29	1	1	157.221459	17.87	3	157.221459
a692fb17-ed61-4f6e-896d-f954e31c80e9	Pending	PayPal	South America	Steven Coleman	2023-09-11	1	1	2468.45313	17.71	9	2468.45313
a6aad149-8e39-4cd1-97ad-6e11e8d5f191	Returned	Gift Card	Australia	Mary Scott	2020-06-30	1	1	117.223636	27.24	1	117.223636
a6b4fe5e-352b-4fbd-bba6-995ab65acb4a	Cancelled	Credit Card	Australia	Caleb Camacho	2021-06-03	1	1	495.97431	22.55	3	495.97431
a6bdd6e0-9019-46a8-901b-47d12ff731bb	Cancelled	PayPal	South America	Diane Andrews	2023-11-06	1	1	2411.14749	0.69	6	2411.14749
a6c3f4b6-4925-4629-b938-90cfa2f1cb9f	Returned	PayPal	North America	Joseph Brooks	2024-10-12	1	1	2264.4779500000004	25.65	7	2264.4779500000004
a6c6a124-bf14-4d3a-88d8-198f0643e4b8	Pending	PayPal	Europe	Crystal Williams	2023-02-01	1	1	118.61581599999998	25.53	1	118.61581599999998
a6caa923-e612-4729-ac70-9e5793ac5d72	Returned	Amazon Pay	Asia	Michelle Andersen	2020-01-30	1	1	3019.2102	12.79	10	3019.2102
a6e8ddb4-c47b-415a-947c-3d710ef8fef0	Returned	Gift Card	Europe	Diane Andrews	2022-01-06	1	1	1424.192768	2.57	4	1424.192768
a6f1a703-2daa-43ae-b4d4-2aa51768197e	Pending	Amazon Pay	Europe	Charles Smith	2020-05-06	1	1	358.951228	22.04	1	358.951228
a70a5810-f442-41dc-a606-021a8353d761	Returned	PayPal	Europe	Sandra Luna	2019-08-19	1	1	532.11972	21.8	2	532.11972
a71a7d64-bec6-4743-8102-3a0e411d2a7a	Returned	Debit Card	South America	Roger Brown	2020-12-29	1	1	1265.790792	28.04	6	1265.790792
a71e6a8c-f436-49ab-b971-d905dd4dc63a	Returned	Credit Card	Australia	Joseph Brooks	2022-05-08	1	1	40.345844	10.68	1	40.345844
a726b30c-ef32-43f5-b435-b34bf059551b	Returned	Credit Card	Europe	Crystal Williams	2020-05-19	1	1	2455.61853	11.15	6	2455.61853
a7369fc7-cdf5-4ae0-a17c-f6b521e5df53	Cancelled	Amazon Pay	Asia	Bradley Howe	2021-12-22	1	1	304.567342	1.67	2	304.567342
a755f229-7c63-405b-88bd-58142f99b970	Returned	Amazon Pay	Europe	Emily Matthews	2020-03-29	1	1	241.893408	8.54	1	241.893408
a75c2916-7408-45e5-9ec1-bb83a5a851ed	Pending	PayPal	Australia	Mary Scott	2020-01-17	1	1	3222.5638500000005	1.55	10	3222.5638500000005
a767a439-ccd4-46e2-87d7-45ae3ee6aca7	Returned	Amazon Pay	South America	Emily Matthews	2022-04-29	1	1	3189.503655	24.59	9	3189.503655
aefd42f8-746a-48d5-a2e3-a35aa8fd63f6	Cancelled	PayPal	Europe	Jason Nelson	2019-03-31	1	1	507.6853279999999	20.12	4	507.6853279999999
a767c3a0-5153-4fe9-b75d-af189c915565	Pending	Debit Card	Australia	Caleb Camacho	2022-12-10	1	1	1851.88185	20.05	10	1851.88185
a7699f16-a894-4887-918f-30d1a15ba310	Cancelled	Debit Card	Asia	Mary Scott	2023-01-26	1	1	836.63253	9.19	5	836.63253
a76d1e94-330d-4c57-ae11-e3779cf38ea7	Returned	Debit Card	Australia	Steven Coleman	2024-12-09	1	1	678.05499	16.85	3	678.05499
a79685d6-909a-4715-9f35-fe6b75957ddc	Returned	Amazon Pay	North America	Charles Smith	2021-12-18	1	1	375.840855	13.03	3	375.840855
a7ba9020-cb2d-47ce-a2b4-a872c2894612	Cancelled	Debit Card	South America	Caleb Camacho	2020-04-26	1	1	1842.387162	20.69	6	1842.387162
a7c362ae-584a-4027-9347-02af77d8ce80	Pending	Debit Card	North America	Jason Nelson	2021-09-18	1	1	2943.5562	22.35	8	2943.5562
a7c8d9d2-8103-4d0d-80d5-fc90e5b908e6	Returned	Amazon Pay	South America	Joseph Brooks	2023-08-08	1	1	3922.342218	8.34	9	3922.342218
a7ff992e-ad08-4050-b972-fd2a8b398755	Returned	Gift Card	Europe	Caleb Camacho	2019-08-13	1	1	2975.31351	7.02	9	2975.31351
a80def41-2f90-4ac4-bc5d-8d1acfb3d6b5	Returned	PayPal	Australia	Bradley Howe	2024-02-21	1	1	283.7577	8.05	2	283.7577
a827ab62-199a-4e52-9b49-9e28bce6af24	Cancelled	Gift Card	Asia	Steven Coleman	2019-01-08	1	1	760.273371	1.99	9	760.273371
a8301344-d188-4f7d-8ef1-2e449c41b683	Pending	Credit Card	South America	Michelle Andersen	2021-08-18	1	1	879.943437	5.11	3	879.943437
a8347808-4157-40da-a835-0937a7280f26	Pending	PayPal	Australia	Caleb Camacho	2021-12-28	1	1	623.12004	27.1	2	623.12004
a8375fbe-b1c3-4eaa-977b-5b6bd53fb75d	Pending	Debit Card	Australia	Susan Edwards	2019-02-25	1	1	57.84174	13.54	3	57.84174
a8434456-4a5b-4347-90b4-98d26d16cf9b	Pending	PayPal	Australia	Sandra Luna	2024-12-12	1	1	2876.61648	9.79	10	2876.61648
a847c350-4e85-4f55-b590-d45ce1c55988	Cancelled	Credit Card	South America	Bradley Howe	2020-09-15	1	1	1677.9069000000002	11.5	6	1677.9069000000002
a855a22c-fbbe-44dc-8ffb-ab0fddcec69c	Returned	Gift Card	Australia	Johnny Marshall	2019-09-23	1	1	1902.985812	9.94	9	1902.985812
a897ee9d-3c37-4d57-ad88-7b4f372e90e7	Cancelled	Debit Card	South America	Bradley Howe	2022-04-14	1	1	357.203574	2.77	3	357.203574
a8c7bc59-2b5c-4b80-a99f-5dd73fb641bb	Pending	Amazon Pay	North America	Michelle Garza	2019-03-12	1	1	1036.05018	27.95	3	1036.05018
a8c9c1c7-8986-473a-b6da-cfc198efc5b5	Pending	PayPal	Australia	Bradley Howe	2020-04-17	1	1	144.58482600000002	21.19	1	144.58482600000002
a8d7a0eb-0d02-4dd2-bed2-b1da57771519	Cancelled	Gift Card	South America	Christina Thompson	2024-04-17	1	1	1363.849032	16.28	6	1363.849032
a8db15c8-6dc5-433e-ac86-ae2b4c313fb5	Returned	Gift Card	North America	Adam Smith	2024-05-17	1	1	224.71238	19.8	1	224.71238
a8e33436-c518-45cb-a2a5-aadc04bb9c8d	Pending	Debit Card	Europe	Michelle Garza	2021-12-11	1	1	660.6541299999999	24.38	5	660.6541299999999
a8ec6897-7e69-4bbf-afba-c33b7be1f8b1	Returned	Gift Card	South America	Jason Nelson	2020-01-29	1	1	196.921728	9.76	1	196.921728
a8ed5a18-d995-4e66-ab82-d2dcc908bcaf	Cancelled	Debit Card	North America	Kristen Ramos	2023-12-26	1	1	2515.516992	23.18	8	2515.516992
a8fdff8a-6c45-481c-9a3d-737a1c32f9da	Returned	Amazon Pay	Asia	Christina Thompson	2024-11-05	1	1	1388.4946020000002	0.78	3	1388.4946020000002
a916ab0e-8e8d-4685-a8a0-d7f640024e05	Cancelled	Credit Card	South America	Michelle Andersen	2019-02-25	1	1	22.610144	3.21	4	22.610144
a9340b0f-50a9-4a5f-8365-578822909e83	Cancelled	Credit Card	Europe	Crystal Williams	2019-08-04	1	1	3679.240448	4.32	8	3679.240448
a93d96d9-2dcd-449c-a794-2711918330ab	Cancelled	Gift Card	South America	Caitlyn Boyd	2022-03-19	1	1	758.4422500000001	2.25	2	758.4422500000001
a94e1e7c-29db-482a-b32c-780a285e4e2f	Pending	Amazon Pay	South America	Jason Nelson	2021-11-16	1	1	1206.363417	12.39	3	1206.363417
a960cf32-50d3-4fc9-be5b-fd14f5c439db	Pending	Gift Card	North America	Caitlyn Boyd	2019-05-24	1	1	175.525981	24.11	1	175.525981
a9618c97-233b-4c99-b11f-ad5cb13aab9b	Cancelled	Amazon Pay	North America	Michelle Andersen	2020-12-08	1	1	870.2144	6	4	870.2144
a96d0502-c2b2-416e-9696-87d7a3f6af34	Returned	Gift Card	Europe	Steven Coleman	2024-05-18	1	1	165.89736800000003	26.49	1	165.89736800000003
a96ee43b-5bf1-4fb3-9613-a1973040d781	Pending	Debit Card	Asia	Johnny Marshall	2024-01-14	1	1	16.651815	24.55	1	16.651815
a970c27a-b6b8-4f5c-9629-b82643d08744	Pending	Gift Card	South America	Johnny Marshall	2022-02-09	1	1	110.123316	25.33	3	110.123316
a9840026-e3ab-43b5-9664-8680827ea013	Returned	PayPal	Europe	Charles Smith	2022-08-26	1	1	332.607828	2.84	1	332.607828
a993efd5-d23b-4c9b-a7ad-6899837f8026	Pending	PayPal	Europe	Kristen Ramos	2020-10-10	1	1	1494.81913	11.9	7	1494.81913
a9d82f4c-3d47-4c7f-a87c-96a42f9f07d6	Pending	Debit Card	Asia	Joseph Brooks	2021-07-05	1	1	1223.62394	5.57	4	1223.62394
aa064a0e-da20-4b83-bb56-1f3759c7d602	Returned	Debit Card	Europe	Kristen Ramos	2019-06-13	1	1	1812.362472	19.88	6	1812.362472
aa0e123a-05c3-4c28-995b-2ea84ff8f412	Pending	Gift Card	Australia	Jason Nelson	2023-01-11	1	1	2432.601882	23.27	9	2432.601882
aa38a4ad-b985-4349-82e5-7c717fe732a1	Returned	Amazon Pay	Asia	Sandra Luna	2020-02-29	1	1	338.460408	29.71	4	338.460408
aa9d69df-6dd7-42b4-b0ae-1b322deff2bd	Returned	Debit Card	Europe	Crystal Williams	2019-07-06	1	1	322.98624	17.2	2	322.98624
aab23356-1716-41e8-a8f9-960e0a2bbbb0	Returned	PayPal	North America	Jason Nelson	2022-06-03	1	1	1060.45758	10.26	9	1060.45758
aacab9cc-a0b5-4b00-ba33-23a83fd8b92d	Returned	Credit Card	Europe	Susan Edwards	2021-09-01	1	1	1697.64	29.5	8	1697.64
aad2f453-6375-4a8d-8b94-a08f546c847e	Returned	PayPal	North America	Bradley Howe	2023-11-15	1	1	1583.45558	23.63	7	1583.45558
aadf760c-70a9-4581-8b21-2004c834e62a	Pending	Gift Card	South America	Mary Scott	2023-12-22	1	1	187.90002	16.84	1	187.90002
aae55b7d-60e7-4337-8e9c-f24b8a374286	Pending	Credit Card	South America	Adam Smith	2019-02-14	1	1	545.0155199999999	24.96	3	545.0155199999999
ab33d0c1-db0a-438d-bd33-463c204555ac	Returned	Gift Card	Australia	Diane Andrews	2022-09-21	1	1	2001.8868	3.57	8	2001.8868
ab37e165-7226-42c9-bb64-d8782ca6cd31	Pending	Amazon Pay	North America	Charles Smith	2019-07-05	1	1	668.15056	1.65	4	668.15056
ab4b8b36-131a-4e65-8070-c4dce5f05baf	Cancelled	PayPal	North America	Mary Scott	2020-08-17	1	1	2080.427928	12.59	6	2080.427928
ab677ed1-a7d0-44cf-afe3-e1b3f0836c1b	Pending	Gift Card	Europe	Christina Thompson	2022-02-12	1	1	1527.614352	3.64	4	1527.614352
ab76418c-e2fd-44f5-b3df-a21afb27a06f	Returned	Credit Card	North America	Adam Smith	2020-10-10	1	1	320.407029	13.19	9	320.407029
ab7efcbf-3624-4532-8841-1006a91cd0d9	Pending	Credit Card	Asia	Michelle Garza	2022-11-09	1	1	1540.096915	8.51	5	1540.096915
ab926e29-1fef-4aeb-9c89-5089f780bc80	Pending	Credit Card	Asia	Crystal Williams	2020-06-26	1	1	167.503237	23.99	1	167.503237
ab98a8d3-a2c6-42e8-be55-eb923d761135	Pending	PayPal	North America	Roger Brown	2019-11-30	1	1	1495.73996	21.9	4	1495.73996
abcc5143-90d4-4666-a1e6-c6a0e4214bed	Pending	PayPal	Europe	Kristen Ramos	2022-03-29	1	1	2730.0917280000003	29.09	8	2730.0917280000003
abe8bc70-3aec-4ae7-958d-308cc8e48ee6	Cancelled	PayPal	Australia	Caleb Camacho	2021-04-23	1	1	149.383608	16.62	3	149.383608
abfdb079-0629-4586-a3f2-c895811988d0	Cancelled	Debit Card	Asia	Steven Coleman	2024-10-31	1	1	3603.05253	1.37	10	3603.05253
ac502691-5be0-4328-889c-8bd1f068880c	Cancelled	Gift Card	Europe	Michelle Garza	2019-05-07	1	1	827.6123520000001	10.54	8	827.6123520000001
ac50d2ab-fb4c-4918-9f19-696c138e5ec3	Pending	Amazon Pay	Europe	Jason Nelson	2024-06-08	1	1	246.922068	0.93	4	246.922068
ac5557a6-180c-431d-94ff-d935365fb680	Returned	Gift Card	Asia	Caleb Camacho	2024-11-29	1	1	2783.2939200000005	5.02	10	2783.2939200000005
ac597e99-956f-4f36-a319-dd39748deac9	Returned	Credit Card	North America	Diane Andrews	2021-09-24	1	1	1485.48543	2.46	5	1485.48543
ac696c2a-5621-4214-8ca2-e8d64bb8ff07	Cancelled	Credit Card	Europe	Kristen Ramos	2020-10-24	1	1	160.452276	2.33	4	160.452276
ac8a697a-62f8-419f-8dd5-406264a6682a	Cancelled	Amazon Pay	Asia	Johnny Marshall	2020-11-24	1	1	2768.616	10	8	2768.616
aca5086a-14ea-49ae-8440-a50258e55112	Pending	PayPal	Asia	Bradley Howe	2019-08-06	1	1	745.350375	22.25	3	745.350375
acba4d82-86a5-400d-9a53-4e1b79fe78e5	Cancelled	Amazon Pay	South America	Adam Smith	2021-09-14	1	1	1512.3928260000002	25.81	7	1512.3928260000002
acd0ce5a-cca5-45d3-887d-35cee1045ce3	Returned	Gift Card	Asia	Michelle Garza	2019-02-07	1	1	411.207866	13.47	2	411.207866
acd4286c-4916-4373-ab78-c6377bec6b57	Pending	Amazon Pay	North America	Mary Scott	2023-07-11	1	1	797.37749	3.71	10	797.37749
acdffe26-1c5d-4a8d-a53b-bae3c9d49bdc	Cancelled	Debit Card	Europe	Steven Coleman	2019-03-15	1	1	579.650214	8.61	3	579.650214
ace4cfcc-aacf-43aa-a8d2-e355488b8738	Returned	PayPal	Asia	Caleb Camacho	2020-04-14	1	1	2092.65102	9.46	10	2092.65102
ad15a600-ce0b-46be-9215-ea54a2ff69ee	Returned	Gift Card	Australia	Sandra Luna	2024-05-12	1	1	123.728816	22.92	4	123.728816
ad16f2f8-2c41-47c7-9f5f-05e23387f5fa	Cancelled	Amazon Pay	South America	Caitlyn Boyd	2024-06-03	1	1	1039.0072	26.52	7	1039.0072
ad40a831-4db5-4d50-ae43-2cc61cce034c	Cancelled	Credit Card	North America	Emily Matthews	2023-07-13	1	1	210.58734	21.01	5	210.58734
ad4e2da6-f69e-472d-ab97-e2bb174f8fc8	Cancelled	PayPal	Australia	Kristen Ramos	2021-04-02	1	1	191.075388	29.86	2	191.075388
ad518b42-bcd4-4680-8c41-14c0c4772192	Cancelled	Debit Card	Europe	Adam Smith	2024-06-22	1	1	701.251875	26.25	3	701.251875
ad5bb832-9bcf-4b1c-b520-d894f567988d	Returned	PayPal	North America	Michelle Garza	2020-11-07	1	1	1691.74329	21.23	6	1691.74329
adb4f6ac-741d-42ce-9a52-8241af205be6	Pending	PayPal	Asia	Johnny Marshall	2020-08-25	1	1	1940.786176	25.82	7	1940.786176
adcecd48-9567-4f49-8d1b-6a872c3509b2	Returned	Debit Card	Asia	Jason Nelson	2022-12-13	1	1	185.245956	27.83	4	185.245956
adcf7e45-24a6-4d20-8c29-ec2a57a49539	Cancelled	Gift Card	Asia	Crystal Williams	2022-08-29	1	1	439.050108	12.36	3	439.050108
ade2de09-da96-4f6b-811e-aae31cfc996d	Cancelled	PayPal	Asia	Kristen Ramos	2020-07-29	1	1	496.674976	2.16	4	496.674976
ade4939b-2dba-41f7-a9bf-dc546b43fed5	Cancelled	Credit Card	Europe	Emily Matthews	2022-07-01	1	1	1084.147506	22.91	9	1084.147506
ae04279e-82c7-4a9d-8321-85a3f2a97ee5	Returned	PayPal	North America	Mary Scott	2024-05-31	1	1	3001.5150900000003	3.23	10	3001.5150900000003
ae207642-f9dd-43ed-9d44-215c738ed6f2	Cancelled	Credit Card	Australia	Diane Andrews	2023-10-10	1	1	188.521344	17.92	9	188.521344
ae3ac957-15c6-40d6-b8f0-1c9d54630638	Returned	Gift Card	Europe	Christina Thompson	2023-01-12	1	1	488.556432	16.28	6	488.556432
ae48a528-d9d5-4080-a178-3f554c1f413e	Cancelled	Gift Card	Australia	Joseph Brooks	2024-11-27	1	1	1401.386688	5.24	6	1401.386688
ae5a7207-b51f-4b9f-a915-4a598b4e6738	Cancelled	Amazon Pay	Asia	Crystal Williams	2023-06-03	1	1	806.653264	25.58	4	806.653264
ae701437-8489-4ec7-9d5f-123f17bd5086	Returned	PayPal	North America	Emily Matthews	2019-12-15	1	1	2537.84301	2.01	10	2537.84301
ae7e5c2f-44cb-4be6-aa94-b06e5b934520	Pending	Amazon Pay	Europe	Crystal Williams	2020-03-29	1	1	420.20444	11.48	2	420.20444
ae8ab012-ee43-4f13-a1ed-dbf503029f72	Returned	PayPal	Asia	Caitlyn Boyd	2022-07-08	1	1	839.661345	3.65	3	839.661345
ae913aa9-2f00-41b8-bbb2-72cabace34ea	Cancelled	PayPal	South America	Crystal Williams	2023-03-05	1	1	1490.039808	24.48	4	1490.039808
aea06c0a-eef9-4e68-b31e-b91aaf9def8d	Pending	Credit Card	Asia	Steven Coleman	2024-12-20	1	1	3403.491672	6.77	8	3403.491672
aea6ce02-b577-4d1c-ae51-1681dcbb282b	Pending	PayPal	South America	Susan Edwards	2019-08-22	1	1	1980.76998	22.02	10	1980.76998
aead444f-d0f2-41b2-8ff6-e6c04a6c8a82	Pending	Debit Card	Australia	Jason Nelson	2021-04-14	1	1	1374.153312	7.04	6	1374.153312
aec1dc74-1074-41a9-baf9-395d175106d3	Pending	Gift Card	Asia	Kristen Ramos	2019-10-17	1	1	403.396626	4.22	1	403.396626
aecd9074-6d7b-4d57-bd6c-47a7bf6638b8	Returned	Credit Card	Europe	Crystal Williams	2020-02-07	1	1	266.279376	3.48	3	266.279376
aef0e59a-ce5f-4881-8651-7bbdada46d8d	Pending	PayPal	Europe	Michelle Andersen	2021-06-20	1	1	449.57442	6.1	2	449.57442
af3b7f65-0739-462f-85fb-e07b77a36863	Returned	Amazon Pay	Australia	Crystal Williams	2021-11-05	1	1	206.963488	3.72	1	206.963488
af4853a1-b4a0-4ec1-8477-4de54bd81caf	Pending	Credit Card	Europe	Johnny Marshall	2024-08-27	1	1	10.972766	5.57	1	10.972766
af6d67fa-e265-43d4-87e7-1079cf1b0c80	Pending	Amazon Pay	Australia	Emily Matthews	2024-09-23	1	1	1493.190816	0.94	4	1493.190816
af7310b7-4f48-4a8f-8643-a226b0334666	Pending	Debit Card	Australia	Michelle Andersen	2023-04-13	1	1	2179.299915	3.93	5	2179.299915
af75450f-f184-4350-8de2-f0f872c3dbc7	Cancelled	Gift Card	Asia	Susan Edwards	2024-09-09	1	1	187.64001	12.03	6	187.64001
af86f5a0-b5e4-4f7d-b3c6-66243aa91916	Cancelled	Amazon Pay	Europe	Sandra Luna	2024-10-18	1	1	145.17915	27.75	6	145.17915
afa01050-51d9-48d3-b196-d830c43b4f25	Pending	Credit Card	Asia	Joseph Brooks	2024-05-28	1	1	243.86738	1.4	1	243.86738
afa63227-de6f-4588-9cad-9dc00e077977	Returned	Gift Card	Asia	Adam Smith	2024-10-05	1	1	736.66176	21.28	2	736.66176
afb379f5-c326-4a20-8bf5-5fe7a90e3b32	Cancelled	PayPal	North America	Mary Scott	2024-08-29	1	1	409.411552	0.96	1	409.411552
afd7125f-1347-48e1-b248-aa60cab88f1c	Pending	Gift Card	Europe	Jason Nelson	2024-05-29	1	1	1081.130544	19.14	4	1081.130544
afe44e82-db1f-40d3-943c-72af498a0160	Cancelled	PayPal	Europe	Sandra Luna	2022-11-06	1	1	2190.322806	13.13	6	2190.322806
affccb94-1496-4a52-87ad-fd498e1d119a	Returned	Gift Card	Australia	Sandra Luna	2019-10-12	1	1	597.918034	8.79	2	597.918034
b0427325-4621-4ce7-90eb-f11ac14e1578	Pending	Amazon Pay	North America	Michelle Andersen	2019-05-23	1	1	4707.49635	1.63	10	4707.49635
b049a4c3-61db-4cba-8134-3c096a01bea9	Returned	PayPal	Asia	Diane Andrews	2023-09-20	1	1	1741.413168	18.64	6	1741.413168
b04bdfa7-42c6-48a9-b80f-498a2bc27427	Returned	Amazon Pay	North America	Michelle Garza	2023-11-28	1	1	665.196264	28.09	4	665.196264
b076d493-4242-4274-a72b-a403533744da	Pending	Gift Card	North America	Sandra Luna	2019-10-11	1	1	1517.731056	3.57	9	1517.731056
b07d3c91-9a90-4d40-91ec-61ba563925b7	Cancelled	Gift Card	Europe	Bradley Howe	2021-08-16	1	1	1478.5166	13.1	10	1478.5166
b0a4d6b7-8499-47c7-bd6e-f0f3a67f3894	Pending	PayPal	Europe	Caitlyn Boyd	2020-10-02	1	1	792.085437	23.33	3	792.085437
b0e64c50-a88f-4764-a565-e20986b74887	Returned	PayPal	South America	Diane Andrews	2024-04-08	1	1	319.259538	12.26	9	319.259538
b0fcf9ea-439f-4700-b42d-efe4a8f85778	Pending	Gift Card	Australia	Bradley Howe	2022-10-07	1	1	345.556224	20.32	3	345.556224
b1145bc8-f868-42c6-844a-b39b7b714cdc	Cancelled	Credit Card	South America	Sandra Luna	2024-03-26	1	1	1014.558912	2.08	3	1014.558912
b133b57f-2444-45dd-894c-a8c8ede81138	Returned	PayPal	North America	Caleb Camacho	2019-10-04	1	1	2141.9028	6	9	2141.9028
b14f56d3-4930-4b0a-aec4-5515898c4ad9	Cancelled	PayPal	Australia	Diane Andrews	2023-09-27	1	1	70.18109700000001	3.69	7	70.18109700000001
b1583d71-b291-48b7-b663-030dfca6b0a2	Pending	Credit Card	Australia	Johnny Marshall	2021-12-07	1	1	1059.14816	24.26	4	1059.14816
b1604591-de9e-475b-87d7-8fcdef311cb1	Returned	PayPal	North America	Caitlyn Boyd	2020-01-03	1	1	694.7268300000001	4.03	5	694.7268300000001
b161f38d-1069-41b0-93fb-d85911a894a0	Returned	Credit Card	Europe	Roger Brown	2023-07-26	1	1	1147.240864	9.03	7	1147.240864
b1748d84-e55c-40d8-9cce-e01c9c3e4304	Returned	Credit Card	North America	Susan Edwards	2020-09-09	1	1	2090.918907	7.93	7	2090.918907
b17ac583-4b8f-4a60-a07c-5d2af6878d2e	Pending	PayPal	Asia	Joseph Brooks	2019-02-09	1	1	45.948032	16.64	1	45.948032
b192fd22-0f7f-44cc-a0ec-4e1e52c9c028	Pending	PayPal	Australia	Steven Coleman	2020-05-28	1	1	194.2794	18.37	4	194.2794
b1a25eef-654d-436e-8b9e-4d694e34c06d	Returned	Debit Card	Asia	Crystal Williams	2024-09-28	1	1	1432.933005	1.79	3	1432.933005
b1c0cb65-6fde-4805-bcb8-ccb7930195f4	Cancelled	Credit Card	South America	Jason Nelson	2022-08-08	1	1	189.7203	17.87	3	189.7203
b1dc5761-6dbc-4605-aa54-7d3a8ff96280	Cancelled	Gift Card	North America	Emily Matthews	2021-08-31	1	1	621.5048	18.8	5	621.5048
b1f54631-ddf1-475e-a17b-df86b3678a71	Returned	Credit Card	North America	Diane Andrews	2022-09-21	1	1	340.26959	29.85	1	340.26959
b201ee71-25c0-4f20-8236-cb6c668247b7	Cancelled	Credit Card	North America	Michelle Garza	2024-04-09	1	1	1204.939304	5.87	4	1204.939304
b2066a57-f1e9-4986-b96d-9440f68a143d	Pending	Gift Card	Australia	Christina Thompson	2021-06-23	1	1	792.44624	2.36	5	792.44624
b223d5b4-c003-48d8-896a-1f3b550a6ec8	Pending	Credit Card	North America	Roger Brown	2019-06-17	1	1	3218.0626700000003	14.57	10	3218.0626700000003
b229fb54-f21c-4d3c-9e17-6d9cd2baf665	Pending	Gift Card	Australia	Caitlyn Boyd	2019-11-21	1	1	1611.6543840000004	25.07	6	1611.6543840000004
b233a605-942c-4d7a-a228-f0378559dc70	Pending	Amazon Pay	Asia	Sandra Luna	2021-10-08	1	1	763.317464	29.63	8	763.317464
b24d55a3-c17e-4622-b58c-49806b681d35	Cancelled	Credit Card	North America	Sandra Luna	2021-11-11	1	1	3888.798192	4.04	9	3888.798192
b24d6b3e-ee92-4eec-9dbd-46b8703c1b09	Cancelled	Debit Card	South America	Crystal Williams	2020-11-15	1	1	466.11383	25.38	5	466.11383
b27184ee-ed77-4934-b11b-dac8b37e7b57	Returned	Amazon Pay	South America	Michelle Andersen	2021-01-20	1	1	2818.454776	6.77	8	2818.454776
b27a5f86-736c-4978-86b6-9af6c8f50b4b	Cancelled	Amazon Pay	Europe	Michelle Andersen	2022-07-25	1	1	1986.55216	16.64	5	1986.55216
b2822fa7-a402-413a-89fd-e503419075af	Cancelled	Amazon Pay	South America	Steven Coleman	2021-01-31	1	1	1662.1021889999995	28.77	9	1662.1021889999995
b2b58f09-bf65-4448-9cbc-13a40a6f4dd2	Cancelled	Gift Card	Europe	Bradley Howe	2022-01-27	1	1	116.97445	27.57	10	116.97445
b2cd2898-4cb7-4bb1-b724-c9c0193ba309	Cancelled	Debit Card	Europe	Jason Nelson	2022-06-22	1	1	381.81165	29.49	10	381.81165
b2e8de40-43d8-4478-a33a-3bedf760dbaf	Pending	Credit Card	North America	Roger Brown	2021-04-26	1	1	840.095088	21.18	6	840.095088
b34ab0e1-de04-41de-bfb0-8b9f59d0791b	Cancelled	Debit Card	Australia	Crystal Williams	2019-03-13	1	1	176.284764	27.58	6	176.284764
b350276a-594d-4545-86fa-9b91f455e084	Returned	Amazon Pay	South America	Susan Edwards	2021-02-01	1	1	2881.57371	20.99	10	2881.57371
b35fe91e-6e12-4e5f-83c8-69bd52123344	Pending	Gift Card	Australia	Caleb Camacho	2023-10-27	1	1	458.2206719999999	14.46	8	458.2206719999999
b3615e2d-ab52-4c4d-beea-bbaa62ddb7f5	Cancelled	PayPal	North America	Jason Nelson	2019-08-15	1	1	2931.5626299999994	23.81	10	2931.5626299999994
b37cfaeb-73bb-432c-b2e1-5261509c22a5	Cancelled	Debit Card	South America	Kristen Ramos	2022-10-05	1	1	798.249592	15.72	2	798.249592
b3a0761a-a11a-4818-a454-4d0f76007131	Pending	Debit Card	South America	Emily Matthews	2021-03-25	1	1	2017.44304	19.16	5	2017.44304
b3b32f65-2e86-4cd9-95ab-bb1d49e7ead9	Returned	PayPal	South America	Michelle Andersen	2022-09-05	1	1	1100.2640219999998	17.17	3	1100.2640219999998
b3e58824-018e-496b-9acd-c9b00f609ba0	Cancelled	Amazon Pay	South America	Diane Andrews	2020-02-21	1	1	2699.1200700000004	29.26	9	2699.1200700000004
b3ebd0ce-7717-4bae-940a-e1beef84ba30	Pending	Gift Card	South America	Susan Edwards	2020-11-20	1	1	2951.42582	11.31	7	2951.42582
b42ba400-dfde-402f-ba08-81d8aad5da83	Returned	PayPal	Asia	Emily Matthews	2023-05-24	1	1	899.3414	11.22	10	899.3414
b42f8b58-922e-46ca-9c12-ef1e39289b25	Returned	Credit Card	Asia	Adam Smith	2019-09-28	1	1	132.951667	12.87	1	132.951667
b43180e7-543a-4687-88fe-6e73e80c2fc1	Pending	PayPal	Asia	Roger Brown	2023-08-06	1	1	279.20718	16.38	3	279.20718
b4350fdf-0bcb-41e4-9ef0-732a62b4496e	Cancelled	Amazon Pay	South America	Michelle Garza	2024-10-30	1	1	1316.2974	6.28	10	1316.2974
b43bbe1f-285c-4993-9914-c40eafedb531	Pending	Gift Card	North America	Adam Smith	2022-08-06	1	1	591.8686200000001	10.89	4	591.8686200000001
b4402763-8982-4a17-b0e3-6b3cd061980a	Cancelled	Debit Card	North America	Steven Coleman	2021-07-15	1	1	578.9346	17.8	10	578.9346
b44865c9-f75f-4215-bf4b-b11591302d47	Cancelled	Debit Card	North America	Diane Andrews	2022-10-20	1	1	621.9260639999999	28.16	9	621.9260639999999
b4547b89-1f1d-4baa-8e10-ef8715ca036b	Cancelled	PayPal	Australia	Bradley Howe	2023-12-12	1	1	356.929824	12.62	8	356.929824
b46f58d5-0027-414f-bb1e-04ab42406d63	Returned	Credit Card	Asia	Christina Thompson	2024-03-08	1	1	599.70492	7.35	8	599.70492
b46f7049-ef32-492b-8be8-ceab42c82502	Returned	Credit Card	South America	Adam Smith	2019-05-31	1	1	225.91998	4.19	2	225.91998
b473bba0-4bd7-4466-9c61-ff90f522da4f	Pending	Amazon Pay	Europe	Bradley Howe	2024-08-01	1	1	2034.583952	6.23	8	2034.583952
b4818869-9e6e-4bfe-ae72-4562c10eb9fd	Returned	Debit Card	Australia	Johnny Marshall	2021-11-12	1	1	1519.784064	24.56	9	1519.784064
b48ab194-519c-42c3-8b1d-4270b06d307b	Pending	Amazon Pay	South America	Kristen Ramos	2019-05-18	1	1	3524.53425	6.05	10	3524.53425
b4a46029-c06a-44a6-bd89-e9e7cb1f2821	Cancelled	PayPal	Australia	Michelle Garza	2022-12-12	1	1	893.0554199999999	14.35	3	893.0554199999999
b4d84f1f-d7db-49f1-a03f-b02a1e081134	Pending	Amazon Pay	Europe	Susan Edwards	2019-10-10	1	1	349.007393	6.69	1	349.007393
b4df936e-6fed-4592-927f-8e3111bee457	Returned	PayPal	Asia	Roger Brown	2020-12-22	1	1	909.5335320000002	29.88	3	909.5335320000002
b4e47db8-8880-4238-82c7-76a4d7b42310	Pending	Debit Card	South America	Susan Edwards	2019-01-18	1	1	1641.2794199999998	22.53	9	1641.2794199999998
b4e836de-45e8-4d02-84b7-b1572ff225e2	Cancelled	Credit Card	North America	Christina Thompson	2023-02-01	1	1	196.055988	29.97	3	196.055988
b4f37fee-48e8-44f0-af2b-d0d8fc8928dc	Pending	Credit Card	Australia	Michelle Andersen	2023-06-16	1	1	394.044112	16.77	1	394.044112
b51a8e2f-b769-4963-9472-6baaa692db66	Pending	PayPal	North America	Crystal Williams	2020-08-13	1	1	1513.130706	7.43	6	1513.130706
b582aa33-fdc5-487f-8107-cbed40c446fc	Cancelled	PayPal	Australia	Crystal Williams	2023-10-23	1	1	1941.624795	6.61	5	1941.624795
b58e72cb-4e07-4e82-b387-e1dd9906f74a	Returned	Gift Card	South America	Roger Brown	2022-09-03	1	1	940.4112299999998	29.38	5	940.4112299999998
b5957bac-d3a5-4fcd-aad0-de64ec46b338	Returned	Credit Card	South America	Jason Nelson	2023-09-17	1	1	1659.99411	27.47	6	1659.99411
b598f081-1af7-4fb7-b981-38799cced565	Pending	Gift Card	Asia	Kristen Ramos	2021-01-04	1	1	171.84864000000002	13.12	2	171.84864000000002
b59b611c-cb20-427c-afdf-3ec2fdbc8ee7	Returned	Credit Card	Asia	Emily Matthews	2024-02-11	1	1	958.850456	15.17	4	958.850456
b5dfd2c8-591f-4872-89bc-c7a9a0a17765	Returned	Debit Card	Europe	Jason Nelson	2024-06-22	1	1	365.360866	16.38	1	365.360866
b5eb6a00-d4fc-4ba9-8ba2-c88367c66fb6	Cancelled	PayPal	Australia	Mary Scott	2021-02-07	1	1	1407.376088	27.54	4	1407.376088
b603e83f-caa4-4bdc-8441-d698aa36ba0f	Returned	Amazon Pay	Europe	Susan Edwards	2024-07-13	1	1	2286.373446	12.07	6	2286.373446
b60d8b55-ac60-487a-85f3-8a4e435b48d2	Returned	Amazon Pay	South America	Joseph Brooks	2020-01-21	1	1	2526.975353	7.01	7	2526.975353
b61ced55-9153-4040-b493-5dc49c61584e	Pending	PayPal	Australia	Charles Smith	2022-01-09	1	1	511.939584	14.54	4	511.939584
b62327a0-da08-4419-bc9a-3244bf241f52	Pending	Gift Card	Australia	Adam Smith	2023-08-18	1	1	2632.42896	13.27	8	2632.42896
b629571a-ea45-4e50-9ce9-255e708dc67b	Returned	PayPal	Europe	Johnny Marshall	2022-10-26	1	1	218.40294	25.94	2	218.40294
b62c62d0-479f-40a8-a6e9-0f9584dffcdd	Returned	Amazon Pay	Asia	Crystal Williams	2022-04-03	1	1	338.691276	19.88	9	338.691276
b646bc8f-8e87-47bf-9507-03b968449d2c	Pending	Credit Card	Australia	Emily Matthews	2019-10-26	1	1	2385.6768	23.2	9	2385.6768
b648f7de-7120-4c80-b556-8cd6daca03dc	Cancelled	Credit Card	South America	Charles Smith	2019-09-15	1	1	1010.488424	4.23	8	1010.488424
b6497fdc-47b5-4ded-b45d-1e99e89f0f43	Cancelled	Credit Card	Asia	Sandra Luna	2022-10-04	1	1	389.10356	7.55	1	389.10356
b6554a5b-84c8-4a1b-8d48-654671e0aef0	Pending	Credit Card	Asia	Michelle Garza	2019-05-25	1	1	2089.34568	20.93	10	2089.34568
b6554b60-76e6-43ce-a2f2-fd315ad3ced4	Cancelled	Amazon Pay	Australia	Sandra Luna	2024-11-12	1	1	528.269325	29.55	3	528.269325
b65aa2a9-cf54-448c-9c45-4b2576ba98b0	Pending	Debit Card	Australia	Bradley Howe	2020-06-27	1	1	232.406368	7.68	2	232.406368
b6723bd2-47f3-406f-81c8-224edd73273f	Cancelled	PayPal	North America	Jason Nelson	2019-01-29	1	1	1728.1455499999995	7.65	10	1728.1455499999995
b69cca31-e006-402b-b253-0ebaa493c40d	Returned	Amazon Pay	North America	Adam Smith	2020-05-15	1	1	3151.9125000000004	10.9	10	3151.9125000000004
b6a07894-b18d-4a18-a662-3c0236480ef8	Pending	Credit Card	Australia	Emily Matthews	2024-09-08	1	1	1712.223216	21.02	8	1712.223216
b6aa90e9-cf02-4f8d-bd9b-03851fc46df5	Cancelled	PayPal	Asia	Michelle Andersen	2023-10-16	1	1	287.622608	8.61	8	287.622608
b6ae67e3-b2e4-4481-9303-842bb33930a1	Cancelled	Debit Card	South America	Michelle Garza	2021-10-22	1	1	796.358112	8.08	4	796.358112
b6d98d72-cee3-45d2-a713-7b69a73059fb	Pending	PayPal	North America	Sandra Luna	2023-03-07	1	1	301.25916	11.29	6	301.25916
b6e7b076-5052-4070-b2f7-8d42779bdc8f	Cancelled	Debit Card	South America	Mary Scott	2019-06-24	1	1	3024.5046	4.71	10	3024.5046
b6ed6693-70b3-4974-a488-5b6a8ba008ad	Returned	Debit Card	Australia	Johnny Marshall	2020-10-17	1	1	1791.03748	24.74	10	1791.03748
b6ed7e63-4b72-45f4-ac9e-be93f750432c	Returned	PayPal	Asia	Christina Thompson	2019-02-08	1	1	1466.80692	16.1	4	1466.80692
b6f48f9d-22dd-45f9-964f-7d3012a2d209	Cancelled	Credit Card	South America	Caitlyn Boyd	2021-11-19	1	1	92.049525	16.75	1	92.049525
b6f8b1d1-f4c9-46eb-899c-c6a68d95324f	Pending	Debit Card	Europe	Christina Thompson	2022-11-21	1	1	3125.00454	5.9	7	3125.00454
b7040e61-5d8e-4558-9637-c1944e667c53	Cancelled	Debit Card	Asia	Christina Thompson	2019-03-03	1	1	1073.10528	11.6	9	1073.10528
b72c088d-d23b-494a-aaea-466e1e66d6ab	Pending	PayPal	South America	Christina Thompson	2020-10-24	1	1	930.378348	5.53	3	930.378348
b72c8480-0b07-4387-8fa2-40e78efb4257	Returned	PayPal	Europe	Crystal Williams	2020-04-30	1	1	1070.450256	4.54	4	1070.450256
b730b66d-220e-4192-892f-5c0c621a2e2a	Cancelled	Debit Card	Asia	Steven Coleman	2022-03-14	1	1	307.44732	13.4	1	307.44732
b7332140-017b-4585-8b03-112a304ccfd1	Cancelled	Gift Card	Australia	Diane Andrews	2024-07-02	1	1	4911.91756	1.47	10	4911.91756
b736c203-307b-43a4-881e-8bf778f31ac2	Pending	Credit Card	North America	Johnny Marshall	2021-02-10	1	1	1009.394904	3.47	6	1009.394904
b74900df-fbe7-4f4d-bd80-3c7236881b16	Returned	Debit Card	Europe	Steven Coleman	2023-04-13	1	1	746.41014	20.62	2	746.41014
b750836f-f4c2-436b-9b4c-66e7c1fa4682	Cancelled	PayPal	North America	Michelle Garza	2023-05-14	1	1	2530.281852	4.54	6	2530.281852
b7558c17-6ff1-4ec2-bd7b-314f07c98d8d	Returned	Debit Card	North America	Emily Matthews	2019-05-31	1	1	797.883268	9.98	2	797.883268
b75cbfc1-c5af-4aeb-ad42-0222d0846bc4	Cancelled	PayPal	Asia	Diane Andrews	2020-03-25	1	1	105.417708	26.62	1	105.417708
b762afde-e017-4d2c-859a-7ccf5f2d10f0	Cancelled	Amazon Pay	Asia	Susan Edwards	2019-08-03	1	1	1019.78976	21.02	8	1019.78976
b779f378-12b7-4513-b676-6067973a18cd	Returned	PayPal	North America	Johnny Marshall	2024-12-31	1	1	928.261872	10.51	4	928.261872
b78771b5-3874-466b-86a2-ffe603b78aae	Pending	Amazon Pay	North America	Sandra Luna	2021-02-06	1	1	1445.638224	0.13	4	1445.638224
b7bef844-fd9e-4f92-b217-70be1ffcd65b	Cancelled	Credit Card	Australia	Charles Smith	2022-10-06	1	1	412.497648	20.04	4	412.497648
b7bf5448-7b89-49f4-a703-f0cb685d28d9	Returned	Credit Card	Australia	Joseph Brooks	2022-05-19	1	1	1579.628472	19.41	8	1579.628472
b7c55023-198d-4323-9782-5c97892cf4bc	Pending	Debit Card	Australia	Charles Smith	2020-06-06	1	1	1945.17516	4.05	8	1945.17516
b7d44815-9f20-4b56-93cf-3a19dc4e9f75	Returned	Gift Card	South America	Johnny Marshall	2021-01-23	1	1	3685.49324	1.85	8	3685.49324
b7d45695-de1f-48f8-9f04-d76148b6519d	Returned	Amazon Pay	Australia	Crystal Williams	2021-02-02	1	1	2653.3556280000003	2.21	6	2653.3556280000003
b7d8666c-c76e-4b3b-8e7d-36904f8c6182	Returned	Debit Card	Europe	Emily Matthews	2020-10-31	1	1	2035.955733	1.51	7	2035.955733
b7deb11d-73e7-4401-baca-7f868c16f25b	Returned	PayPal	South America	Mary Scott	2021-04-08	1	1	2450.6442030000003	13.41	7	2450.6442030000003
b7ee3a50-c549-4069-a789-9f5f0244d9de	Cancelled	Debit Card	North America	Jason Nelson	2022-01-17	1	1	1468.956125	27.45	5	1468.956125
b7f7fd5a-457b-4c97-bac6-73a690a57170	Cancelled	Amazon Pay	Europe	Susan Edwards	2022-06-14	1	1	732.6901399999999	19.08	5	732.6901399999999
b7fa3f31-5b77-451e-90a3-0e9f7ecd5b12	Returned	PayPal	North America	Michelle Andersen	2022-08-22	1	1	267.245952	5.74	1	267.245952
b7fca3b0-4e9e-4822-bfb8-2fd33d7ea0d5	Cancelled	PayPal	Asia	Adam Smith	2022-03-12	1	1	938.306808	22.22	4	938.306808
b800b51b-8842-4bb6-ab02-ff6bb68fe0bd	Returned	Amazon Pay	Australia	Emily Matthews	2023-06-18	1	1	37.553324	23.61	2	37.553324
b827af94-066c-4c70-8094-c1338d6f38eb	Cancelled	Debit Card	Europe	Mary Scott	2023-10-28	1	1	284.965118	11.43	1	284.965118
b85b2555-f306-4197-8828-8dcbc00a9d42	Pending	Debit Card	North America	Diane Andrews	2024-02-23	1	1	232.123038	8.23	1	232.123038
b86f3901-aba1-4e20-8e6b-98d1334e820a	Returned	PayPal	Australia	Michelle Garza	2023-07-14	1	1	121.135104	10.72	4	121.135104
b86faf9a-56b5-4578-896b-fa298f71dfb4	Pending	Amazon Pay	Asia	Roger Brown	2020-05-05	1	1	210.42786	8.43	10	210.42786
b87104f7-435b-43ed-8077-87e1c923ed18	Cancelled	Debit Card	South America	Charles Smith	2019-08-15	1	1	3650.4906	1.71	10	3650.4906
b87bbc37-d14c-414f-9e2a-a5c4a758082f	Returned	Credit Card	Asia	Bradley Howe	2022-01-08	1	1	2919.94362	6.94	10	2919.94362
b87d3a33-8b60-4b83-8b8f-925b842a7239	Pending	Amazon Pay	Australia	Kristen Ramos	2020-01-04	1	1	173.807893	28.53	1	173.807893
b88336e8-2c77-46cd-9215-7168a5fc8149	Cancelled	Debit Card	South America	Charles Smith	2020-10-17	1	1	2434.565	5	10	2434.565
b8974857-53c9-4413-8b96-1d6b26e996d2	Returned	PayPal	Asia	Johnny Marshall	2020-02-04	1	1	230.510106	16.66	1	230.510106
b8af298b-93b6-4420-a326-676edfd557e4	Returned	Credit Card	Asia	Caitlyn Boyd	2023-04-13	1	1	1623.0243960000005	16.98	6	1623.0243960000005
b8bc87c0-cb7b-4ea5-a355-400fcb10bb1e	Returned	Credit Card	North America	Michelle Garza	2023-05-02	1	1	1389.187584	17.92	4	1389.187584
b8bf51b6-fbca-4217-8d0e-5ab9856cf4e1	Returned	Credit Card	North America	Sandra Luna	2024-08-13	1	1	906.73356	5.3	6	906.73356
b8c6d376-7288-45d4-b9d5-b4e363127773	Pending	PayPal	Australia	Caleb Camacho	2020-09-14	1	1	587.172	19.84	2	587.172
b8cb21b4-b316-4077-a873-0d00e9a8a80b	Returned	Gift Card	North America	Charles Smith	2022-10-16	1	1	1107.67656	11.05	4	1107.67656
b8cd65e0-23b5-4534-b3da-595044f7e6e7	Returned	Debit Card	South America	Caleb Camacho	2024-08-19	1	1	2920.132053	9.97	9	2920.132053
b9208756-a2f0-49bc-b6cc-9f8b62a07023	Pending	Debit Card	South America	Bradley Howe	2020-07-06	1	1	332.142	1.5	8	332.142
b950e33e-e6ca-46ea-b298-0854c7b97073	Returned	Amazon Pay	North America	Joseph Brooks	2022-12-31	1	1	456.592176	2.17	2	456.592176
b95d6f65-0520-4f37-a60c-0b8cff73128a	Pending	Debit Card	Australia	Adam Smith	2021-07-27	1	1	856.540608	22.72	4	856.540608
b99c6b5e-657a-4d64-866e-71446d2e9f84	Cancelled	Gift Card	Europe	Michelle Garza	2022-01-08	1	1	1916.265708	13.49	9	1916.265708
b9a28fbf-bae1-468a-a23e-2eb86dbcfa8c	Returned	PayPal	North America	Johnny Marshall	2021-01-05	1	1	2093.280714	19.47	7	2093.280714
b9ac142f-3248-49a7-b1b4-0885c89f1e49	Pending	Amazon Pay	North America	Crystal Williams	2023-02-20	1	1	611.675064	28.24	3	611.675064
b9badbe4-45c4-4a6c-a3e0-809430f9132f	Returned	Gift Card	South America	Jason Nelson	2020-09-17	1	1	477.861552	16.83	9	477.861552
b9daf08c-63eb-4482-b0d5-734d8fec8330	Returned	Amazon Pay	Europe	Michelle Garza	2023-12-09	1	1	893.5112159999999	6.64	6	893.5112159999999
b9ed78f2-bdf0-455c-9c5a-44e4077af697	Returned	Gift Card	North America	Kristen Ramos	2022-07-15	1	1	1565.975664	18.16	6	1565.975664
ba0b8640-d0f4-4a9e-89b3-0f4b286e693c	Returned	Amazon Pay	Europe	Sandra Luna	2020-01-28	1	1	227.735472	24.81	3	227.735472
ba272b17-a45e-43a4-8c14-ebc7a8ff35ea	Returned	Debit Card	Asia	Susan Edwards	2021-05-01	1	1	3011.012928	6.36	9	3011.012928
ba5352df-fd1e-4f5a-913f-6f03bc1c775d	Returned	Amazon Pay	Europe	Michelle Garza	2023-04-28	1	1	975.9238	22.8	5	975.9238
ba74113d-19b0-46e1-8a35-94e71183b5bc	Cancelled	Amazon Pay	Asia	Johnny Marshall	2020-05-07	1	1	2139.5945	24.5	10	2139.5945
ba8f1991-63bc-43cd-b030-321f7bb8ceb9	Cancelled	Amazon Pay	North America	Mary Scott	2020-10-18	1	1	49.85578	26.03	5	49.85578
ba983e84-4e79-45bc-b47e-480c0f2e1667	Pending	Credit Card	Asia	Charles Smith	2021-06-28	1	1	344.05246	20.78	5	344.05246
baa7da6c-c492-4632-9a2d-af10fe5a8f9e	Pending	Gift Card	South America	Steven Coleman	2024-02-22	1	1	1817.21856	21.65	8	1817.21856
baad5e5e-673a-4cff-b848-b57c8eb0edfb	Returned	Debit Card	North America	Caitlyn Boyd	2020-09-01	1	1	417.486726	8.77	6	417.486726
baeaa0e4-27e9-499b-a2f2-e55cc994d8d9	Pending	Gift Card	Asia	Michelle Garza	2022-06-21	1	1	1483.33003	29.67	5	1483.33003
bafebad8-bf66-4507-8e23-8850f77b499e	Returned	Credit Card	South America	Roger Brown	2019-04-11	1	1	309.130614	17.71	3	309.130614
bb15452b-d5c6-4420-85b1-666c0c59883a	Cancelled	Credit Card	South America	Jason Nelson	2020-06-23	1	1	2501.562609	4.71	7	2501.562609
bb17a9e9-6d06-41eb-b438-b60f5bde0e57	Returned	Amazon Pay	Europe	Kristen Ramos	2019-11-16	1	1	2441.92725	21.25	9	2441.92725
bb23a66a-5d6b-4f8d-a4f1-ca27e932d1d4	Pending	Credit Card	Australia	Crystal Williams	2021-05-11	1	1	104.07177	21.55	1	104.07177
bb2aa472-c9bf-41ce-beb7-401dc19c9cea	Pending	Debit Card	Asia	Sandra Luna	2024-09-11	1	1	2170.16289	2.17	5	2170.16289
bb3619e8-de5d-4220-9b82-3d9d4015d8d8	Returned	PayPal	Asia	Kristen Ramos	2023-05-09	1	1	1170.5905	16.25	4	1170.5905
bb4501df-8c80-4b7b-8271-ea8e10fbe6dd	Cancelled	Credit Card	South America	Bradley Howe	2023-03-08	1	1	255.069893	26.21	1	255.069893
bb600f42-ad4b-4c76-a0db-730621492938	Pending	Debit Card	South America	Crystal Williams	2021-04-06	1	1	199.5407	24.9	1	199.5407
bb772057-08d6-421d-b43f-4bb60e3b72f1	Pending	PayPal	North America	Kristen Ramos	2019-09-24	1	1	154.618772	10.79	1	154.618772
bb93397a-138f-498b-a8ed-11dc15bf7420	Returned	Credit Card	North America	Caleb Camacho	2024-05-02	1	1	1182.522096	14.74	6	1182.522096
bbc42009-3315-4bf2-a7e9-eec8b7f92fd1	Returned	Debit Card	Asia	Diane Andrews	2022-11-23	1	1	769.52572	5.7	2	769.52572
bbc98e2f-ce2c-4b43-8339-2c1301dd7ad3	Pending	Debit Card	Europe	Michelle Andersen	2020-07-06	1	1	504.736668	12.18	9	504.736668
bbdc04c7-ac2a-4e69-8e5e-e9705ca67095	Pending	Credit Card	Asia	Charles Smith	2021-01-09	1	1	521.201142	16.18	7	521.201142
bbe6f464-53f7-4467-a7c5-b37853e91d8e	Returned	Amazon Pay	Asia	Caitlyn Boyd	2024-08-23	1	1	1350.158112	16.06	9	1350.158112
bc065834-634a-42ff-a1a5-22dcae501a07	Pending	Debit Card	Australia	Joseph Brooks	2023-02-13	1	1	235.932888	11.41	1	235.932888
bc14fc40-3a52-483c-b28d-afa06aba18b7	Cancelled	Gift Card	Europe	Christina Thompson	2022-02-16	1	1	2326.1029	9.03	10	2326.1029
bc1e0ce0-10e0-4a59-a500-3eb12c88fbd2	Pending	Gift Card	Australia	Bradley Howe	2021-03-11	1	1	1608.342832	5.87	4	1608.342832
bc3e701c-1a80-4282-a5fe-3f9dc61c4501	Cancelled	Debit Card	Australia	Joseph Brooks	2024-04-21	1	1	1082.589948	11.89	3	1082.589948
bc4f3bed-f4b4-40ff-a4c3-8bcfa30307a2	Cancelled	PayPal	North America	Johnny Marshall	2019-05-05	1	1	3316.2294	19.7	10	3316.2294
bc5afddf-8864-4a92-8eec-3aa6996b82d9	Returned	Debit Card	South America	Kristen Ramos	2022-08-04	1	1	673.3945319999999	16.09	2	673.3945319999999
bc65755b-af96-407a-becb-c9b7d04a18ed	Cancelled	Amazon Pay	Asia	Christina Thompson	2019-06-23	1	1	291.33778	19.83	2	291.33778
bc88ec2b-9ade-4925-89df-3ba84310e655	Pending	Debit Card	Europe	Michelle Garza	2023-12-12	1	1	929.85512	3.6	2	929.85512
bc9d45e6-5e80-41e2-b6e8-c45416de835b	Returned	Credit Card	South America	Christina Thompson	2019-09-09	1	1	1184.424476	24.63	4	1184.424476
bcaf8959-403a-49cf-9aeb-065e61dbe04c	Pending	PayPal	Asia	Michelle Garza	2021-02-01	1	1	840.163947	15.23	3	840.163947
bcb13ab8-4285-4080-b812-5bfcb8f709ea	Pending	Gift Card	Asia	Susan Edwards	2021-01-02	1	1	1742.5509	3.03	4	1742.5509
bcd0bdf2-a8d1-4522-b2c6-2a67459eaf35	Pending	Gift Card	Asia	Jason Nelson	2020-06-15	1	1	2757.8547499999995	19.25	10	2757.8547499999995
bcd867ed-94d0-4fcc-8700-c10810052001	Pending	Debit Card	South America	Sandra Luna	2019-06-14	1	1	1504.6496	18.65	4	1504.6496
bce440e7-4efc-4588-a546-fe5b102d3628	Pending	Amazon Pay	North America	Christina Thompson	2022-11-04	1	1	63.30139200000001	16.96	9	63.30139200000001
bcfdaf4e-6485-4908-9738-a03b4c6b2dfd	Returned	PayPal	Asia	Adam Smith	2019-01-07	1	1	3730.893504	1.01	8	3730.893504
bd0a41ee-fd64-4b78-8e71-6dba351aec54	Returned	Debit Card	Asia	Adam Smith	2019-02-27	1	1	1335.0208	28.07	8	1335.0208
bd230787-ca0b-444a-b0b6-4b384e73ca86	Returned	Gift Card	South America	Bradley Howe	2019-02-22	1	1	2096.546256	25.96	7	2096.546256
bd3d05c7-94a2-43cd-b416-3d9493f16d3e	Cancelled	Credit Card	Asia	Diane Andrews	2022-01-07	1	1	3690.54504	11.52	9	3690.54504
bd42a26b-843c-49b7-a802-e92851ab9daa	Cancelled	PayPal	Europe	Crystal Williams	2019-06-15	1	1	1122.3098040000002	27.88	7	1122.3098040000002
bd4f06c2-0981-410c-a5d5-cf10d5557881	Cancelled	PayPal	South America	Emily Matthews	2021-02-07	1	1	1372.8959999999995	18.28	10	1372.8959999999995
bd94882b-1ab8-43d9-8857-3e7f8d8e19e4	Returned	Amazon Pay	Asia	Crystal Williams	2022-09-11	1	1	3243.584736	14.14	8	3243.584736
bdaa4377-a6c0-410a-b944-ad4c936bc207	Cancelled	Gift Card	Asia	Michelle Andersen	2020-02-18	1	1	661.68091	22.89	10	661.68091
bdb50b03-39eb-4c6d-9240-cb1b8c5c308d	Returned	Gift Card	Australia	Joseph Brooks	2020-12-16	1	1	2280.33585	3.7	5	2280.33585
bdd3f7c4-1928-402c-bf49-23d161dd5038	Returned	Amazon Pay	Europe	Bradley Howe	2020-12-21	1	1	2983.65977	6.66	7	2983.65977
bdf1dd2c-23b1-4a13-9fbf-1cfb0ac203a3	Returned	PayPal	Australia	Diane Andrews	2023-06-10	1	1	2113.65536	4.16	5	2113.65536
bdf7916d-f970-471c-8fb1-6e969a3b1598	Pending	Credit Card	Asia	Caleb Camacho	2020-07-27	1	1	360.805686	25.78	1	360.805686
be16122a-b3ef-4a0b-b1bb-9ae893241d60	Returned	Credit Card	Europe	Roger Brown	2020-05-26	1	1	639.71853	20.14	5	639.71853
be56f658-d764-4c49-bbb6-17bd892f4dc9	Returned	Gift Card	North America	Crystal Williams	2022-05-13	1	1	146.51273	10.17	2	146.51273
be5abe34-3b45-4349-a5c0-3d2b0223cedf	Cancelled	Amazon Pay	North America	Caitlyn Boyd	2022-03-01	1	1	4147.58739	16.09	10	4147.58739
be7df2c9-c521-4763-82c0-501d91a5625e	Returned	PayPal	Europe	Sandra Luna	2020-01-07	1	1	881.006855	17.07	5	881.006855
be95cd18-be2c-45c3-9bc3-a7502887d9fc	Cancelled	Credit Card	Australia	Charles Smith	2023-06-08	1	1	1137.507576	1.21	4	1137.507576
be9d8437-30d7-47b4-a2f8-ddf1d19ba0da	Returned	Debit Card	Australia	Johnny Marshall	2023-03-13	1	1	833.488998	11.46	3	833.488998
beb0dec4-fc6a-4105-817f-b526ac1e74b2	Cancelled	Debit Card	Asia	Roger Brown	2024-10-23	1	1	906.98298	8.33	2	906.98298
becbda36-a7d1-4480-a9b9-cc87b65fe28a	Cancelled	Gift Card	Asia	Diane Andrews	2022-08-14	1	1	596.08065	24.1	5	596.08065
bedb34f6-e54c-4614-8189-2cf2b1717433	Returned	Debit Card	North America	Mary Scott	2022-04-23	1	1	374.904224	28.16	2	374.904224
bedd1b18-216a-40c3-8d14-a5d63a79e499	Cancelled	Debit Card	Australia	Roger Brown	2020-12-16	1	1	87.371692	18.89	1	87.371692
beecb06f-bebf-4192-84a2-7ef795ebce0c	Returned	Gift Card	North America	Charles Smith	2022-11-17	1	1	238.71085	24.05	2	238.71085
bf068c95-1022-42b1-bda0-2044d1e69608	Returned	Debit Card	Europe	Adam Smith	2020-11-23	1	1	2156.385492	0.22	6	2156.385492
bf182b5a-241b-4d2d-bb73-1717d2cbbbb7	Returned	PayPal	South America	Sandra Luna	2019-06-18	1	1	930.77878	18.51	10	930.77878
bf25f69c-c11e-4f09-96b4-8548594a9ac9	Pending	Credit Card	Europe	Christina Thompson	2021-06-01	1	1	305.945185	6.35	7	305.945185
bf263517-fb85-404e-884e-54afd80ef6af	Returned	Credit Card	Australia	Caleb Camacho	2021-12-20	1	1	596.10771	29.05	2	596.10771
bf37acae-3e4b-4339-ac36-c75ecae53f46	Returned	Amazon Pay	North America	Bradley Howe	2024-01-25	1	1	303.456	12.8	2	303.456
bf5841eb-8f5d-4784-94f5-66e5f22a0525	Returned	Debit Card	Australia	Diane Andrews	2021-05-30	1	1	409.743264	15.16	8	409.743264
bf59586e-dc82-4b91-9726-59ecf1fa3bfd	Returned	PayPal	Asia	Michelle Garza	2019-08-23	1	1	464.25165	28.19	5	464.25165
bf6fe907-e695-4d96-b42a-3d5b932d55ab	Cancelled	Amazon Pay	Australia	Charles Smith	2022-01-09	1	1	410.61296	2.4	1	410.61296
bfab945e-9d27-4324-89f9-fa4384725566	Cancelled	Gift Card	Europe	Mary Scott	2020-12-26	1	1	37.602287	4.49	1	37.602287
bfbbad91-4bd6-45cb-802b-1e504249d874	Cancelled	Gift Card	Australia	Jason Nelson	2024-01-05	1	1	1714.8630550000005	27.47	5	1714.8630550000005
bfc0171f-644c-4763-82e9-37ff6ee4eccb	Cancelled	Credit Card	South America	Diane Andrews	2021-08-17	1	1	2475.052974	5.19	9	2475.052974
bfc6967e-ed90-4887-8226-0ba29d3b0ce4	Pending	PayPal	South America	Michelle Garza	2024-03-29	1	1	361.78174	19.05	1	361.78174
bfe5ebc5-6872-40ef-9f5b-5ccdde9023ea	Pending	Credit Card	Australia	Steven Coleman	2021-07-01	1	1	899.116701	10.87	7	899.116701
c01fb40b-c577-4c19-9a18-a2b44fb6a4c4	Returned	Credit Card	Asia	Susan Edwards	2019-07-09	1	1	1323.408438	9.86	3	1323.408438
c0274b5d-6da8-4e14-9eba-44a2ad3cd856	Cancelled	Amazon Pay	Asia	Diane Andrews	2021-12-19	1	1	628.869948	7.99	2	628.869948
c05fd6bb-6bab-43dd-93ce-8f7aa7a485ba	Cancelled	PayPal	South America	Emily Matthews	2022-04-15	1	1	1162.048044	11.91	4	1162.048044
c06bab49-993e-4c29-bd14-60def0322ec7	Returned	Credit Card	Australia	Susan Edwards	2022-06-02	1	1	497.817789	10.87	7	497.817789
c0761ae7-6a48-4e74-8835-23f3278d82aa	Pending	Gift Card	Australia	Michelle Andersen	2020-02-12	1	1	1159.80795	6.55	10	1159.80795
c08025c7-794b-4339-8e42-9840b02c286d	Returned	Debit Card	Europe	Charles Smith	2021-05-29	1	1	2388.39544	20.88	10	2388.39544
c0872a94-d42a-4aa9-af28-8bdb4db16fad	Returned	Credit Card	Asia	Sandra Luna	2020-05-29	1	1	4288.01232	5.44	10	4288.01232
c08bcaca-6d78-4330-8a31-bc9a54ef44f1	Cancelled	Amazon Pay	Asia	Christina Thompson	2023-04-06	1	1	1524.8529600000002	17.76	5	1524.8529600000002
c09ea594-d84a-4b9d-88b4-27e48b7f84e9	Cancelled	PayPal	North America	Caleb Camacho	2021-02-14	1	1	66.145101	20.47	1	66.145101
c0bbddbc-721f-4e0c-9da2-8c6f17c7ee17	Cancelled	PayPal	North America	Jason Nelson	2021-11-18	1	1	367.149705	1.85	3	367.149705
c0d60fff-e8d3-45bd-b73c-a66f9d57bf85	Cancelled	PayPal	Australia	Mary Scott	2022-10-20	1	1	1522.765728	17.56	8	1522.765728
c0e587d8-97c2-4209-8faf-c7f1a5c83483	Returned	Debit Card	Asia	Christina Thompson	2022-05-22	1	1	604.3839360000001	21.89	8	604.3839360000001
c0e5d119-eb6c-4666-8b2c-79a7fcbe924b	Pending	Amazon Pay	South America	Susan Edwards	2019-12-22	1	1	1190.04756	15.05	3	1190.04756
c0eb4c52-fd44-4c52-9042-e4226a063254	Cancelled	Debit Card	South America	Steven Coleman	2020-09-01	1	1	281.193528	9.14	4	281.193528
c0ffa8a9-c418-43d9-abe7-14c3e0dbf731	Returned	Debit Card	Australia	Christina Thompson	2023-06-06	1	1	485.027271	13.51	9	485.027271
c10de840-d178-4e78-8918-e15500141bea	Returned	Debit Card	South America	Jason Nelson	2020-12-24	1	1	864.7610399999999	27.85	6	864.7610399999999
c114b4a8-2e62-4f4a-af93-7f54e71c15c1	Returned	Debit Card	North America	Crystal Williams	2019-07-11	1	1	2020.165095	9.31	5	2020.165095
c12d8abb-1c8a-4c04-ad41-8129e8488b1e	Cancelled	Amazon Pay	Australia	Christina Thompson	2021-12-02	1	1	198.14792	9.9	1	198.14792
c13617fd-9c58-4c2b-89b2-934a55d03e81	Returned	Credit Card	South America	Caleb Camacho	2020-12-22	1	1	284.870624	26.61	4	284.870624
c13fe98e-3295-40be-96dd-f356959e22ad	Cancelled	Credit Card	South America	Michelle Andersen	2019-01-16	1	1	121.456854	17.41	2	121.456854
c1464567-d44c-4545-b2b2-88d2b7f74550	Pending	Credit Card	North America	Adam Smith	2024-03-26	1	1	35.89573	14.33	1	35.89573
c16c1093-27b3-440d-ba9f-cfe5cddb4c54	Pending	PayPal	North America	Steven Coleman	2022-11-04	1	1	594.79452	19.72	10	594.79452
c19b91ce-fd49-4543-a894-bc38a8b18d02	Cancelled	Amazon Pay	Europe	Roger Brown	2024-10-02	1	1	135.27151600000002	16.94	1	135.27151600000002
c19d5cdb-9492-47e3-85b2-5389c0b0265a	Returned	PayPal	South America	Adam Smith	2022-11-13	1	1	665.5642559999999	2.49	8	665.5642559999999
c1a551fa-60a4-493b-b2a0-e2e57b42e060	Returned	Gift Card	North America	Mary Scott	2024-10-04	1	1	286.22448	18.64	2	286.22448
c1ba8eee-5186-4c19-8063-c1c69e27e8cd	Cancelled	PayPal	Europe	Crystal Williams	2022-06-12	1	1	554.4108	9.41	8	554.4108
c1bfed9a-38a2-4aef-9d81-c1a5c0d36169	Returned	PayPal	South America	Caleb Camacho	2019-12-23	1	1	164.01396	26.91	1	164.01396
c1cc8672-1fe7-41e4-85ba-560753907b0f	Returned	PayPal	Asia	Mary Scott	2019-12-23	1	1	184.641696	6.52	1	184.641696
c1d18bfb-312e-4644-b570-21569de49f5c	Pending	PayPal	Europe	Emily Matthews	2021-03-21	1	1	45.37962	20.05	3	45.37962
c1da10d5-5071-4481-b5cd-b85d322d3317	Cancelled	Amazon Pay	Australia	Caleb Camacho	2021-07-08	1	1	1405.56319	27.99	5	1405.56319
c1dd399f-d136-4cc5-9956-081d30425ef8	Pending	Amazon Pay	Europe	Michelle Andersen	2020-11-13	1	1	781.7959799999999	9.42	7	781.7959799999999
c1f8fc8a-7c15-49ab-93b5-116214a6803a	Returned	PayPal	South America	Caitlyn Boyd	2020-06-11	1	1	241.80052	19.55	4	241.80052
c2293531-5cea-4253-86cd-41b5182a3d84	Cancelled	Credit Card	North America	Christina Thompson	2024-05-04	1	1	2050.678952	5.52	7	2050.678952
c268e4a2-6ccb-49ad-ad7f-90468a25675e	Returned	Amazon Pay	Europe	Diane Andrews	2023-04-18	1	1	593.68896	17.44	3	593.68896
c27494a3-e710-4689-8217-64a33a5ba855	Returned	Gift Card	Asia	Christina Thompson	2022-01-14	1	1	196.57185	26.35	10	196.57185
c27ea062-8c19-4eae-ab10-fc5e9ada87a9	Pending	Credit Card	South America	Crystal Williams	2019-10-24	1	1	3189.1167	23	9	3189.1167
c28ea88a-cc1c-4398-9fc5-00d5605545fc	Cancelled	PayPal	Australia	Sandra Luna	2022-05-08	1	1	1815.97194	22.81	6	1815.97194
c296576e-6aca-4094-a744-4685537c22e9	Pending	PayPal	Europe	Michelle Andersen	2022-09-10	1	1	368.046	16	3	368.046
c2bc36c1-15a6-4128-82da-474a7af475f9	Cancelled	Debit Card	Europe	Caitlyn Boyd	2022-05-20	1	1	2911.21056	1.06	10	2911.21056
c2c41624-32d3-42f5-81f2-62724d7a9a63	Pending	Amazon Pay	Asia	Joseph Brooks	2019-04-06	1	1	3636.562509	4.61	9	3636.562509
c2ddf54d-065d-4165-ae0b-a5eabad4cf65	Pending	Gift Card	North America	Caleb Camacho	2021-06-10	1	1	1860.782	14	10	1860.782
c2f4f95c-b743-4ed4-a1f0-a3597e9d51fc	Cancelled	PayPal	South America	Crystal Williams	2023-04-05	1	1	1521.51064	27.44	10	1521.51064
c2f67abc-02e8-40cc-a9f1-1d1d8cb86f47	Pending	PayPal	North America	Charles Smith	2024-03-16	1	1	450.660565	4.95	1	450.660565
c30d361c-a203-4fde-8be5-324c02f54bbf	Cancelled	Gift Card	Asia	Steven Coleman	2022-04-11	1	1	164.420082	14.87	9	164.420082
c3175230-461f-421b-9c20-a4b982124a1a	Pending	PayPal	Australia	Mary Scott	2020-11-27	1	1	2448.11322	28.6	9	2448.11322
c3287a89-fe6a-44bf-87ac-a864c9c98757	Cancelled	Gift Card	South America	Joseph Brooks	2020-06-10	1	1	2026.5672	15.05	10	2026.5672
c341dfb1-efab-4d7e-bc10-b49cd7aacb31	Returned	PayPal	Australia	Michelle Garza	2024-05-15	1	1	820.857604	6.36	7	820.857604
c3431e79-1018-447d-b0db-2925f2281b30	Cancelled	Gift Card	Asia	Adam Smith	2023-01-01	1	1	325.67652	23.95	2	325.67652
c34c98c4-bccb-4841-8cb1-521f8c2dc7ba	Cancelled	PayPal	South America	Emily Matthews	2022-11-11	1	1	3493.78128	19.26	9	3493.78128
c364947d-9a6c-4f8e-882c-bbc3ede6bfa8	Pending	Credit Card	Asia	Charles Smith	2021-01-30	1	1	1168.127649	12.19	9	1168.127649
c37dad99-49f7-490a-9674-d0f63fe1cb02	Pending	Gift Card	Asia	Steven Coleman	2019-03-05	1	1	460.545204	2.07	2	460.545204
c385ef5f-76bb-4cc2-973c-a4bc1617ae66	Pending	Credit Card	Europe	Sandra Luna	2022-06-20	1	1	246.338266	2.61	2	246.338266
c38f539f-c685-432d-a726-5657b5344879	Returned	Credit Card	South America	Crystal Williams	2024-11-21	1	1	987.099825	14.37	3	987.099825
c398df99-3a7a-454e-856f-bec46119750a	Pending	Gift Card	Australia	Caleb Camacho	2019-04-26	1	1	23.186280000000004	13.16	3	23.186280000000004
c399e1a8-ee7c-482d-a4a7-29a3ded69ac9	Pending	PayPal	Asia	Kristen Ramos	2022-01-28	1	1	336.127008	10.28	6	336.127008
c3de6620-f006-4444-9c1c-780bb795ddf6	Pending	Credit Card	North America	Susan Edwards	2023-03-23	1	1	682.50476	8.3	2	682.50476
c40255cd-7a76-48ff-b705-78199df4a06e	Pending	Gift Card	Asia	Caleb Camacho	2019-03-07	1	1	2513.3746	16.61	8	2513.3746
c40ed52c-16c2-4912-9500-bc3d78fb0e18	Returned	Debit Card	Asia	Sandra Luna	2023-10-16	1	1	373.637388	7.06	1	373.637388
c44346a8-4420-4760-a5e9-527636b9469c	Cancelled	PayPal	Australia	Caleb Camacho	2024-01-28	1	1	268.78554	0.05	3	268.78554
c449ac1a-01f2-40a3-92f6-6d70cda14513	Cancelled	Credit Card	Asia	Jason Nelson	2020-05-07	1	1	76.706832	27.88	2	76.706832
c44c0766-97a9-435f-9d3e-bfa9cda8e5ce	Cancelled	Debit Card	Europe	Michelle Andersen	2022-09-12	1	1	1015.977648	28.88	3	1015.977648
c47a9893-18b4-4f93-8690-5b9496800e67	Returned	Debit Card	South America	Susan Edwards	2022-01-22	1	1	4156.482	14.8	10	4156.482
c4dede28-e250-4d6f-a976-723977f2a3b4	Returned	PayPal	Europe	Sandra Luna	2022-05-07	1	1	2289.6468	24.75	9	2289.6468
c4ef52d9-9e71-4485-b685-955787142e85	Pending	Gift Card	Europe	Sandra Luna	2024-04-21	1	1	1726.79283	2.7	9	1726.79283
c50a7176-b2b5-48b1-95bf-bcba23d9f6e8	Returned	PayPal	South America	Sandra Luna	2024-05-01	1	1	428.450022	7.57	7	428.450022
c5124365-a974-4be3-aacf-53828c7486d7	Returned	PayPal	South America	Johnny Marshall	2019-04-23	1	1	280.74845	12.06	1	280.74845
c531462a-0a25-49d1-902d-101090ceacaf	Returned	Credit Card	Asia	Charles Smith	2023-12-07	1	1	56.35721	22.65	1	56.35721
c544549e-c42d-4a24-87ef-4a284641c163	Pending	PayPal	South America	Crystal Williams	2019-05-06	1	1	744.18768	4.65	4	744.18768
c58514da-b3ea-4fe7-b867-ad2aa412eae2	Cancelled	Gift Card	South America	Adam Smith	2024-03-11	1	1	1108.884036	18.39	6	1108.884036
c58f8904-859a-4c46-962c-51a3c80d3b7e	Cancelled	Debit Card	Europe	Crystal Williams	2022-11-07	1	1	1207.111095	17.29	5	1207.111095
c5b9529d-9fdf-4dda-ae1a-aff8dedfe59c	Returned	Gift Card	Europe	Crystal Williams	2023-02-16	1	1	1892.40642	8.12	5	1892.40642
c5c52354-bd86-4399-b777-6906e4725bdc	Returned	PayPal	Europe	Johnny Marshall	2023-11-19	1	1	43.17495	5.11	2	43.17495
c5f6460e-69d1-498c-a056-42fc4464df5d	Returned	Credit Card	Australia	Roger Brown	2023-07-14	1	1	821.6619360000002	5.79	6	821.6619360000002
c63e0031-9bd6-49d1-94f9-d38e2a6e4288	Returned	Debit Card	North America	Crystal Williams	2022-10-25	1	1	553.01538	15.95	4	553.01538
c6415fc3-2cb9-488c-8b9b-373252bc2d3c	Pending	PayPal	Asia	Christina Thompson	2024-10-23	1	1	697.19691	15.97	10	697.19691
c64c6161-e93e-44bc-a3bd-7e068e7cc942	Pending	Credit Card	North America	Michelle Andersen	2019-03-23	1	1	971.0809	0.9	2	971.0809
c64d931f-3ded-432c-ba22-82a1125ffbc0	Returned	PayPal	North America	Caleb Camacho	2024-06-05	1	1	310.87120000000004	25.7	10	310.87120000000004
c65fbfb2-0ce1-4f77-a07a-0efc264065cf	Pending	Amazon Pay	Europe	Adam Smith	2024-01-30	1	1	441.911165	9.45	1	441.911165
c66be1bc-a89e-4500-8dae-3777d9c815c4	Cancelled	PayPal	South America	Caitlyn Boyd	2022-02-14	1	1	215.02602	27.95	9	215.02602
c6750ab6-3783-47fd-943b-cd9deaf4a80d	Cancelled	Gift Card	Europe	Crystal Williams	2021-05-23	1	1	700.3449599999999	22.08	5	700.3449599999999
c68ca570-a62f-41fc-8603-d032cf97c32d	Cancelled	Amazon Pay	Europe	Steven Coleman	2019-06-17	1	1	721.6128640000001	9.92	4	721.6128640000001
c6937596-d250-492a-b60c-b87fe902ea96	Returned	Debit Card	Asia	Crystal Williams	2022-04-26	1	1	408.5572000000001	24.06	10	408.5572000000001
c69842c5-be20-4c35-a502-78ce7e57829b	Cancelled	Debit Card	Australia	Adam Smith	2020-04-18	1	1	565.18812	24.85	4	565.18812
c69b4bde-07aa-4c06-b11b-07c0e7a4f30b	Cancelled	Credit Card	South America	Charles Smith	2024-01-23	1	1	815.230128	29.14	4	815.230128
c69e8ae6-9789-4a8b-b7a8-2a1f8ac8f760	Returned	Amazon Pay	North America	Sandra Luna	2020-06-02	1	1	980.490112	27.53	4	980.490112
c69fd1c7-4d76-4b38-9c6f-61fdd88673c4	Returned	PayPal	Europe	Johnny Marshall	2024-01-05	1	1	2248.58648	23.28	7	2248.58648
c6a737e1-568b-4c78-85b3-9cc183d685fa	Returned	PayPal	Asia	Bradley Howe	2022-10-23	1	1	1534.42359	29.81	7	1534.42359
c6aafca6-28b1-464e-9839-961372ee9703	Pending	Debit Card	South America	Sandra Luna	2022-11-03	1	1	2118.241125	28.75	7	2118.241125
c6b59847-ceb5-4714-8e7d-470233986779	Pending	Amazon Pay	North America	Bradley Howe	2019-10-02	1	1	2692.198719	22.43	9	2692.198719
c6ba2744-5c5e-4f4a-abdc-ba2a6091ed74	Returned	Amazon Pay	Europe	Crystal Williams	2022-10-16	1	1	20.504808000000004	23.03	3	20.504808000000004
c6bd4eaf-8249-41c3-abd6-bd005014ec3d	Cancelled	Debit Card	Europe	Michelle Andersen	2022-02-15	1	1	259.036944	21.58	2	259.036944
c6c37d15-2851-4e4f-83a3-dc55ca794fde	Returned	PayPal	North America	Roger Brown	2023-07-09	1	1	1689.175488	14.46	8	1689.175488
c6cf09fd-8ea6-48be-8fe9-9878715c0dbc	Pending	PayPal	South America	Mary Scott	2022-03-27	1	1	1152.4415279999998	14.02	7	1152.4415279999998
c6e5351a-a31d-4ac0-ad67-5efc5dc5bc7f	Pending	Credit Card	South America	Adam Smith	2022-05-14	1	1	98.036892	5.77	6	98.036892
c6e77a4a-fc5e-41cb-85d6-d2dfa8ff2669	Pending	PayPal	Europe	Adam Smith	2020-04-09	1	1	816.65904	22.7	4	816.65904
c6e8d08b-63b7-4a74-a526-adcc423f2f91	Pending	Credit Card	Asia	Caleb Camacho	2021-03-22	1	1	21.945306	15.53	3	21.945306
c6fe4306-bec9-4916-b18c-e6990fbece9d	Cancelled	Gift Card	North America	Adam Smith	2022-03-10	1	1	1798.870575	5.35	5	1798.870575
c703e7ab-45c7-4acc-8277-ab2944471808	Returned	Gift Card	South America	Charles Smith	2019-04-16	1	1	2844.20519	5.19	10	2844.20519
c712f477-5937-47ab-bef4-2702b69f8409	Returned	Debit Card	Australia	Joseph Brooks	2024-06-07	1	1	2226.146304	10.88	8	2226.146304
c713c698-ad5c-4239-b139-ba8f119cc808	Returned	Gift Card	Europe	Johnny Marshall	2022-05-21	1	1	594.8864819999999	6.03	2	594.8864819999999
c72c6f55-2251-4d03-a122-4d5b49ff07c7	Pending	Gift Card	South America	Joseph Brooks	2022-03-12	1	1	1407.35805	24.06	5	1407.35805
c7482f0a-4b4c-48dd-990a-1ba75fcbaa6f	Pending	Gift Card	Europe	Crystal Williams	2021-09-16	1	1	194.794425	15.75	7	194.794425
c7545b2c-24c0-4aae-888c-56b96c943e2f	Returned	Debit Card	South America	Christina Thompson	2021-03-04	1	1	1911.19155	21.65	6	1911.19155
cd16a937-5c05-43ac-ad96-15307985182a	Pending	PayPal	Australia	Caitlyn Boyd	2024-02-14	1	1	2394.76321	29.9	7	2394.76321
c763ab2e-afbd-4fe1-b197-58d4db29b072	Cancelled	PayPal	Australia	Michelle Andersen	2023-11-24	1	1	681.123506	6.86	7	681.123506
c76c26ba-7370-4655-9c23-ff32e50daa77	Cancelled	Credit Card	Asia	Bradley Howe	2020-03-02	1	1	2653.718868	29.64	9	2653.718868
c76fcd20-3011-444e-a143-580902e5eac6	Returned	Debit Card	South America	Caitlyn Boyd	2024-02-21	1	1	105.9429	26.5	1	105.9429
c7742ba6-d82c-4680-b7a6-cdb5845efcec	Cancelled	Gift Card	Australia	Caitlyn Boyd	2023-08-20	1	1	1829.97556	4.38	4	1829.97556
c78b302a-62f6-48b7-9cdf-3ede8b1ecff7	Cancelled	Debit Card	South America	Johnny Marshall	2021-10-08	1	1	450.40626	1.27	5	450.40626
c7942f6d-85f6-4ef6-981b-9d4dd4d2baee	Cancelled	Amazon Pay	South America	Mary Scott	2021-11-22	1	1	2008.188027	21.99	9	2008.188027
c795e0f1-b134-4017-a89f-b8a340065529	Cancelled	Amazon Pay	Europe	Bradley Howe	2020-12-25	1	1	1276.404948	9.39	6	1276.404948
c7b9578b-499b-4542-9e96-8ca8d0e040c6	Pending	Debit Card	Europe	Kristen Ramos	2023-05-24	1	1	291.597915	1.17	7	291.597915
c7d35b0c-7c05-4865-bdbe-07d259e61972	Pending	Amazon Pay	South America	Charles Smith	2021-08-11	1	1	3103.8637499999995	18.75	9	3103.8637499999995
c7dccbd9-07c4-493a-b2e2-5ec9f0cf704d	Pending	Amazon Pay	Australia	Bradley Howe	2023-01-27	1	1	3060.211544	15.03	8	3060.211544
c7ee0c6a-1e7d-4ebb-8237-0ce98d226dda	Pending	Credit Card	Asia	Emily Matthews	2023-08-25	1	1	818.3373449999999	5.15	3	818.3373449999999
c80c8c47-5bf4-419f-91d1-304e60ad308e	Returned	Gift Card	North America	Christina Thompson	2022-05-28	1	1	693.016968	4.29	8	693.016968
c828b243-4212-4976-9f3d-d304c727e6db	Returned	PayPal	Australia	Emily Matthews	2021-09-11	1	1	2477.31525	19.45	10	2477.31525
c8327404-5d70-44f6-a048-53a23ddb91fb	Cancelled	Debit Card	North America	Diane Andrews	2022-07-30	1	1	3690.064440000001	0.73	10	3690.064440000001
c834a181-ae56-4698-b1f6-875d086f1692	Returned	Amazon Pay	South America	Crystal Williams	2023-06-18	1	1	1721.8655459999998	22.87	6	1721.8655459999998
c83be282-db49-4c01-9059-f5b7dbeacf67	Pending	Debit Card	Asia	Caleb Camacho	2019-06-08	1	1	2126.228292	13.31	9	2126.228292
c83ff228-272a-48c5-8417-7f69ba674cc3	Returned	Amazon Pay	Asia	Diane Andrews	2019-01-24	1	1	1416.9694399999998	20.52	8	1416.9694399999998
c8481b24-c502-4022-a25d-3339026c6113	Pending	Credit Card	Asia	Crystal Williams	2021-04-01	1	1	638.50732	21.24	5	638.50732
c8551149-38bb-4d3d-9257-af7c09e92bfb	Cancelled	Gift Card	South America	Susan Edwards	2019-04-02	1	1	3464.674776	0.24	9	3464.674776
c8675155-5ea4-44c7-820b-4434f4b73820	Cancelled	Credit Card	Asia	Adam Smith	2021-03-06	1	1	263.888758	24.27	7	263.888758
c87b101f-3f42-44bf-b45a-c3e5d67742e0	Returned	Debit Card	Australia	Emily Matthews	2023-07-19	1	1	938.70738	23.15	6	938.70738
c88b8c0b-5000-4981-8389-6cd94cc993b9	Pending	Debit Card	Australia	Adam Smith	2024-11-24	1	1	2405.1745920000003	1.28	6	2405.1745920000003
c8954770-6a9b-4da4-893f-eafc1f48d8d4	Pending	Credit Card	Asia	Charles Smith	2020-01-29	1	1	2691.3595	2.31	10	2691.3595
c89790b3-f219-40d3-8ebd-a89dfbcccd06	Returned	Amazon Pay	Australia	Sandra Luna	2024-07-31	1	1	1766.4011940000005	26.49	6	1766.4011940000005
c89f9531-4df8-4ad7-bd2f-59ae8282d88a	Pending	Credit Card	South America	Sandra Luna	2020-01-09	1	1	539.4426000000001	14.78	2	539.4426000000001
c8b2f5fb-bb0e-4729-b53d-d93be0c203af	Returned	Gift Card	Asia	Steven Coleman	2023-02-10	1	1	618.373611	20.59	3	618.373611
c8b79ec5-2962-4b2b-b893-7da926d71cff	Returned	Amazon Pay	North America	Christina Thompson	2023-07-22	1	1	786.00529	14.87	7	786.00529
c8cd9c6f-eb60-4c1a-966e-649984c444de	Pending	Credit Card	Asia	Steven Coleman	2023-07-10	1	1	290.938265	2.81	1	290.938265
c8deb4ab-3fa1-4012-9378-875ca86d2839	Returned	Credit Card	Australia	Sandra Luna	2024-10-15	1	1	1433.04984	4.95	6	1433.04984
c8ee3521-d7c2-439d-a786-afce3af66693	Pending	Debit Card	Australia	Bradley Howe	2020-05-20	1	1	1685.0128679999998	9.58	6	1685.0128679999998
c90d4914-bada-4ad5-abbc-44cdbca65735	Pending	Amazon Pay	Europe	Michelle Andersen	2022-07-05	1	1	1319.036928	19.24	8	1319.036928
c9157562-6cec-4b73-b8dc-dc1ffce24608	Pending	Amazon Pay	South America	Johnny Marshall	2024-05-04	1	1	1600.38861	0.43	10	1600.38861
c963d6b3-4ad1-4811-9bbc-4ef7839772f3	Returned	Debit Card	South America	Johnny Marshall	2021-09-04	1	1	481.61207999999993	26.35	8	481.61207999999993
c96dbd88-d99f-46b8-ba3e-403b20cdd2b6	Cancelled	Credit Card	Asia	Michelle Andersen	2022-11-11	1	1	390.193035	2.61	5	390.193035
c98724bb-9955-48c1-8757-a26ccda2c8c6	Returned	Amazon Pay	South America	Crystal Williams	2020-01-12	1	1	453.7774800000001	26.68	6	453.7774800000001
c9aa37fe-5dea-4fda-8068-ea3f5056fe40	Returned	Gift Card	Asia	Sandra Luna	2022-11-10	1	1	59.32585199999999	11.77	4	59.32585199999999
c9ac23da-5dbf-4fbc-b64a-6ab5f5eff21f	Returned	PayPal	Asia	Bradley Howe	2023-05-14	1	1	1605.0833999999998	25.15	5	1605.0833999999998
c9d76a4a-a02b-493f-88e1-c54b6af47c6e	Returned	PayPal	South America	Adam Smith	2021-01-31	1	1	2160.418086	0.47	9	2160.418086
c9d7fa86-3042-4bc9-a52d-88210094aafa	Pending	Debit Card	Australia	Jason Nelson	2022-09-01	1	1	2818.008152	28.71	8	2818.008152
c9daef2f-8eda-4742-9708-aa1d00226b2e	Cancelled	Gift Card	Australia	Adam Smith	2021-08-11	1	1	104.45868	6.7	9	104.45868
c9e460ea-724e-42cb-8f1e-c1e7aaf2437c	Returned	Credit Card	North America	Jason Nelson	2022-05-25	1	1	2940.82996	18.41	8	2940.82996
c9f0a5df-e601-4be7-92ec-1ce195ad069a	Cancelled	Debit Card	North America	Jason Nelson	2024-10-03	1	1	410.046063	5.43	1	410.046063
c9fc65b2-3075-4d8c-b7b8-b5dbd19c942c	Returned	Credit Card	Europe	Crystal Williams	2024-10-04	1	1	667.622172	9.99	4	667.622172
ca2c23dc-3190-4e9e-8bb2-ccbba66aa615	Cancelled	Debit Card	Europe	Crystal Williams	2024-04-05	1	1	698.941728	10.06	6	698.941728
ca49c39b-f374-460a-ab1f-36026092f32f	Cancelled	Credit Card	North America	Jason Nelson	2019-04-01	1	1	807.0882799999999	18.41	2	807.0882799999999
ca4b9327-b087-45a0-a5d4-e4cfdb515b66	Returned	Debit Card	North America	Charles Smith	2023-09-24	1	1	160.245298	6.02	1	160.245298
ca4ec624-7bfd-4996-9a9e-5ef29f8c7d0a	Pending	Amazon Pay	South America	Adam Smith	2019-06-10	1	1	140.769144	4.86	2	140.769144
ca7ef9e2-7c1c-459c-a131-462ddd08b15a	Returned	Credit Card	North America	Roger Brown	2022-11-26	1	1	681.733392	24.46	8	681.733392
ca8599e2-a384-4597-aca3-d2f4b5377a4f	Pending	Amazon Pay	North America	Adam Smith	2022-06-12	1	1	881.6153709999999	16.41	7	881.6153709999999
ca95906c-e67e-4d9f-a10c-cadac238c2ab	Cancelled	PayPal	Asia	Steven Coleman	2022-12-31	1	1	127.609548	14.31	3	127.609548
ca9b77f1-49f4-478a-a6e6-74e101009b16	Cancelled	Gift Card	North America	Michelle Andersen	2021-07-12	1	1	569.03232	18.43	4	569.03232
caa138ed-534a-444b-b40b-f4fc5529c4a0	Cancelled	Debit Card	Europe	Caleb Camacho	2021-06-28	1	1	208.376344	26.69	1	208.376344
cab337d8-9985-481c-8023-a63412ba649c	Returned	PayPal	North America	Michelle Garza	2021-03-05	1	1	351.693165	15.57	5	351.693165
cabe2c5e-15da-4d0c-94d5-30764022e578	Returned	Gift Card	North America	Adam Smith	2021-04-17	1	1	1667.3682300000005	6.05	6	1667.3682300000005
cabef750-cf8c-46ad-97b4-f8a04940e0b5	Pending	Debit Card	Asia	Joseph Brooks	2022-01-02	1	1	1278.606672	20.68	6	1278.606672
cabefc91-7b1d-4edc-bef4-2abdeb983f45	Cancelled	Amazon Pay	Asia	Crystal Williams	2022-08-13	1	1	435.552474	28.53	6	435.552474
caec33fa-58d0-41ea-b7da-5b7e3dcf4faf	Cancelled	PayPal	South America	Jason Nelson	2023-01-07	1	1	601.6653859999999	9.63	2	601.6653859999999
caeff0c2-b949-49c2-941f-e0da565c9b10	Pending	Gift Card	South America	Jason Nelson	2024-05-07	1	1	700.94871	25.99	10	700.94871
cb31599a-389a-425f-85c7-e4e0c91a9ea1	Returned	PayPal	Europe	Sandra Luna	2021-10-18	1	1	2072.45528	8.1	8	2072.45528
cb33a131-e28c-49b8-8711-47d9df684f3e	Returned	Credit Card	Asia	Sandra Luna	2024-10-27	1	1	2658.920256	4.69	8	2658.920256
cb529b6f-4995-4064-84e6-c75c29591d31	Returned	Debit Card	South America	Jason Nelson	2021-05-08	1	1	583.9408	3.5	4	583.9408
cb52dcfd-73aa-4f11-85ac-aecd7edc394e	Cancelled	Amazon Pay	Europe	Michelle Garza	2019-06-18	1	1	550.8666880000001	19.68	8	550.8666880000001
cb5ca2bc-49a0-4ad0-ab8b-62df002f4eb3	Pending	Debit Card	Asia	Christina Thompson	2019-06-19	1	1	1900.69464	25.9	8	1900.69464
cb79ce1c-2015-4dd6-9f88-1e312ba27439	Returned	Amazon Pay	Asia	Caleb Camacho	2023-09-02	1	1	1980.3340800000003	18.4	8	1980.3340800000003
cb83e545-0527-4c6a-ae22-c3804815a9f5	Returned	Debit Card	Europe	Crystal Williams	2024-07-19	1	1	1903.37472	27.85	8	1903.37472
cb904201-3cb2-49a9-be66-4d215b48f8bd	Returned	Debit Card	Asia	Crystal Williams	2021-08-29	1	1	801.80314	10.98	10	801.80314
cba1fd3f-7a16-4a7f-81a2-da0ad01db9a9	Cancelled	Amazon Pay	North America	Caitlyn Boyd	2019-12-12	1	1	1223.10288	14.05	4	1223.10288
cbb25600-ad53-41ed-9ab8-4a5b3ac202ca	Returned	Credit Card	Europe	Roger Brown	2024-12-04	1	1	232.445248	4.17	1	232.445248
cbb3ea23-a210-410e-8b6a-a5ebc14d176a	Returned	Credit Card	Europe	Christina Thompson	2021-11-09	1	1	2265.443424	15.69	8	2265.443424
cbcc24e0-07cf-4773-aea1-28c3bb0e7fab	Returned	Debit Card	Europe	Kristen Ramos	2023-07-16	1	1	2153.21952	22.03	8	2153.21952
cbd24a3a-8095-4ea8-8559-4db18163bd2a	Pending	PayPal	Asia	Caitlyn Boyd	2022-01-07	1	1	3894.3003	9.34	10	3894.3003
cbd70819-37e4-4748-8951-f870d654996d	Pending	Credit Card	Europe	Johnny Marshall	2023-03-28	1	1	1355.60079	5.06	9	1355.60079
cbeb09a7-3c49-4258-a041-aca01f9b1878	Returned	Credit Card	Europe	Joseph Brooks	2022-05-11	1	1	2236.109373	19.23	9	2236.109373
cbfd65b3-2163-43ca-a214-5c65a23d6bb4	Returned	Amazon Pay	South America	Jason Nelson	2022-10-29	1	1	906.926427	28.83	9	906.926427
cc07ccb5-95b1-433a-a7b5-784f387205e9	Cancelled	Debit Card	Asia	Michelle Garza	2020-01-30	1	1	1991.48352	11.68	5	1991.48352
cc0b2b6e-70d0-47eb-87d3-d82ddb9cefbd	Cancelled	Debit Card	North America	Sandra Luna	2021-01-27	1	1	1450.345088	25.28	8	1450.345088
cc15e39f-a3ad-4226-86f1-5e5d658572d6	Returned	Credit Card	Asia	Michelle Garza	2021-08-30	1	1	325.529955	14.35	3	325.529955
cc16725c-a69a-4968-9ed7-5cf411569b11	Cancelled	Amazon Pay	North America	Jason Nelson	2019-06-03	1	1	1282.65879	24.05	7	1282.65879
cc23d291-c596-4709-bd91-a9f830af8ad6	Returned	PayPal	North America	Roger Brown	2021-03-08	1	1	2005.8373080000003	22.22	9	2005.8373080000003
cc2d8b04-f1a3-4f6c-b50b-4d02ab98fa35	Returned	Amazon Pay	Asia	Charles Smith	2021-11-20	1	1	2982.103348	10.58	7	2982.103348
cc574cf1-f7f3-4204-919f-369104c5073c	Cancelled	Credit Card	Australia	Crystal Williams	2021-06-24	1	1	1697.5314119999998	11.07	4	1697.5314119999998
cc6233bd-bcb7-4b14-91f0-6f05d9e3f1fa	Cancelled	Credit Card	Europe	Crystal Williams	2022-04-18	1	1	2065.15413	14.73	5	2065.15413
cc81fc5c-10d2-4297-ae57-7fa8185544ed	Pending	PayPal	Asia	Diane Andrews	2021-06-07	1	1	95.822065	0.05	1	95.822065
cc8beefe-f836-42ee-9190-8ab795019b7c	Returned	Credit Card	Australia	Mary Scott	2020-04-08	1	1	38.06712	24.47	9	38.06712
cc90f0cc-3526-4ff5-8ec2-dfe1f3b39831	Pending	Credit Card	Europe	Roger Brown	2019-03-26	1	1	686.292552	21.64	2	686.292552
cc933f57-d633-494d-a8b1-40fb2cb2df2f	Pending	Debit Card	Australia	Bradley Howe	2020-03-11	1	1	184.733418	6.26	1	184.733418
cc96ee5d-32b7-4bb0-b818-5fbb3f21ee06	Returned	Debit Card	South America	Joseph Brooks	2022-12-24	1	1	3258.2097300000005	10.21	10	3258.2097300000005
cc9709c9-4f7a-4382-a01b-7e21b9515711	Returned	Credit Card	Asia	Caitlyn Boyd	2021-12-31	1	1	3378.48084	1.24	7	3378.48084
cc9a3429-7d9e-4588-9863-6c5676a65705	Cancelled	Amazon Pay	Europe	Emily Matthews	2024-10-01	1	1	822.940722	20.26	3	822.940722
ccc1e336-a7e3-48e4-b299-d02d617f54b9	Pending	PayPal	Australia	Charles Smith	2020-07-02	1	1	3598.62209	14.67	10	3598.62209
cccb84b8-bf07-4b72-af04-5dd3ff41f3e0	Cancelled	Amazon Pay	Europe	Susan Edwards	2020-03-05	1	1	573.45315	9.45	5	573.45315
ccde3643-6837-48bf-836a-b04c5ee6faf7	Returned	PayPal	Asia	Michelle Andersen	2020-09-17	1	1	351.195264	9.28	8	351.195264
cce06a4e-7dc7-4d9c-b2b5-a706fa43b7e6	Returned	PayPal	Australia	Emily Matthews	2023-03-27	1	1	34.104504	5.58	2	34.104504
cceed0a7-732f-4d59-b1c0-97889ce5d600	Cancelled	Credit Card	Asia	Roger Brown	2020-01-08	1	1	924.3643	13.53	10	924.3643
cd0bcd62-429c-44e8-a8da-f5332192d24c	Cancelled	Amazon Pay	North America	Sandra Luna	2024-04-10	1	1	1225.4589	18.79	5	1225.4589
cd27551f-5a2f-491f-8df8-1a41915d9340	Pending	Credit Card	Australia	Sandra Luna	2019-08-06	1	1	3427.9337920000003	13.56	8	3427.9337920000003
cd2ae914-7550-4f82-8a76-bcdced4bcf22	Returned	Debit Card	South America	Crystal Williams	2023-05-06	1	1	3085.61776	7.1	8	3085.61776
cd2b7504-0fb8-4aea-bcf7-5f4a6eafb41b	Pending	PayPal	South America	Jason Nelson	2022-07-10	1	1	43.156368	15.28	3	43.156368
cd469483-d21f-4b26-aa4a-9e62e449f0ea	Pending	Gift Card	Australia	Crystal Williams	2023-06-22	1	1	180.420681	16.83	7	180.420681
cd5153f8-ffd5-484e-a864-f38940c8fb61	Cancelled	PayPal	Europe	Steven Coleman	2023-07-18	1	1	2498.95932	18.34	10	2498.95932
cd6260b3-0d0d-4f68-98a5-6d236c043440	Returned	Debit Card	North America	Bradley Howe	2023-10-16	1	1	311.09157	25.15	6	311.09157
cd7b9cb4-1f08-4449-b510-5ad1c3b6d352	Pending	Amazon Pay	Europe	Steven Coleman	2019-05-30	1	1	2458.2784140000003	12.49	6	2458.2784140000003
cdba0283-b982-4eb2-ad8d-0e5fe3f51cb3	Pending	Amazon Pay	Asia	Susan Edwards	2021-01-24	1	1	1925.115504	27.33	6	1925.115504
cdce0833-51ac-4998-bc8c-fa60d62706df	Returned	PayPal	Asia	Bradley Howe	2020-05-12	1	1	1214.28024	1.7	8	1214.28024
cdd2043d-aef3-4d7b-b579-2b7835f86796	Pending	Debit Card	Europe	Diane Andrews	2021-08-10	1	1	1769.14439	20.57	5	1769.14439
cde4f893-2cfd-4856-bda1-ea3ee2852903	Returned	Debit Card	Asia	Caleb Camacho	2023-06-11	1	1	441.942774	28.37	7	441.942774
ce1da035-51fe-431a-abf6-a73731eacc9d	Pending	Amazon Pay	Asia	Crystal Williams	2022-10-13	1	1	93.687042	11.02	1	93.687042
ce2871f0-e0fc-433c-9dab-78c381ece8fe	Pending	Amazon Pay	South America	Sandra Luna	2019-10-26	1	1	1682.0070350000003	16.17	5	1682.0070350000003
ce49db83-ee5b-4909-b989-538b917981f7	Returned	Debit Card	South America	Crystal Williams	2020-12-25	1	1	1039.44061	15.21	5	1039.44061
ce4fb728-354d-4a3f-99ca-c575b8464468	Pending	Amazon Pay	Australia	Roger Brown	2023-08-08	1	1	3027.145284	2.53	9	3027.145284
ce52df3a-5f92-4af8-a7d6-4867531dc53e	Returned	Amazon Pay	Australia	Steven Coleman	2022-04-12	1	1	1562.3395	16.25	4	1562.3395
ce57e1e0-a8b1-4b7e-b65d-7d5ebea22811	Cancelled	Gift Card	Australia	Bradley Howe	2019-09-10	1	1	515.2914	20.7	2	515.2914
ce5d5536-a6a0-4513-93f5-059f9c095943	Returned	Amazon Pay	South America	Roger Brown	2023-02-23	1	1	340.505984	14.72	1	340.505984
ce6296ca-ed4a-4584-8b8f-1fc3fae9b011	Pending	Amazon Pay	Australia	Bradley Howe	2023-05-02	1	1	1789.63603	15.45	7	1789.63603
ce89305b-e93f-4fa5-9029-0a46733233d9	Returned	PayPal	Australia	Charles Smith	2024-09-19	1	1	400.533705	4.19	9	400.533705
ce8f3798-bc8a-402a-804b-0b5c7a52bd54	Returned	Gift Card	Asia	Adam Smith	2021-05-12	1	1	968.552478	5.77	6	968.552478
ce99dcfd-ae9d-45cc-84b0-f83b36157028	Cancelled	Amazon Pay	Asia	Caleb Camacho	2023-08-25	1	1	1291.548392	9.74	4	1291.548392
cea15a14-fa28-47d6-a54f-368b81ba522a	Cancelled	Debit Card	Australia	Diane Andrews	2019-06-18	1	1	976.076415	28.01	5	976.076415
cea7f454-3006-4ae6-a1bb-a5b003f7bcfd	Returned	Gift Card	Australia	Steven Coleman	2022-12-10	1	1	2748.344256	10.96	8	2748.344256
cec037dc-51de-421e-b2c3-df822e1d8e1a	Returned	PayPal	Australia	Michelle Garza	2022-12-17	1	1	1481.8526499999998	17.7	5	1481.8526499999998
cec0e708-9d53-4345-8418-b0b4205a0922	Pending	Debit Card	Europe	Emily Matthews	2024-08-10	1	1	630.93002	26.06	10	630.93002
cf075e97-ba23-40da-b603-1a48a4789aba	Cancelled	Credit Card	Europe	Steven Coleman	2021-09-02	1	1	1257.6379880000002	2.33	4	1257.6379880000002
cf14d9a0-2301-48ba-a1fe-fae825bde6f0	Cancelled	PayPal	Australia	Crystal Williams	2024-11-12	1	1	2322.018916	14.94	7	2322.018916
cf28e5f5-f641-4d96-b998-97ac4e1432fb	Pending	Credit Card	North America	Roger Brown	2024-10-10	1	1	80.89956	11.44	1	80.89956
cf4125f3-6f04-487d-8a87-90f5c59a4686	Pending	Debit Card	Europe	Roger Brown	2020-04-14	1	1	327.544464	15.28	1	327.544464
cf413921-7c1b-4556-9b8e-130193a7879a	Returned	Amazon Pay	South America	Caitlyn Boyd	2023-09-23	1	1	106.39594	14.61	1	106.39594
cf51b87e-16e9-441c-ba04-65675e7ba31d	Pending	Gift Card	Asia	Charles Smith	2024-08-27	1	1	409.932432	14.72	9	409.932432
cf7f1053-4fec-4e4d-b389-1f15fd0787c3	Cancelled	Gift Card	Australia	Charles Smith	2022-04-08	1	1	572.85782	29.1	2	572.85782
cfdc25e3-1c88-4619-a6d4-4636cac0b138	Cancelled	Debit Card	South America	Caleb Camacho	2023-02-04	1	1	230.839467	4.93	1	230.839467
cfe23063-feca-4958-906f-3b23a5874e13	Pending	Debit Card	Europe	Roger Brown	2020-09-20	1	1	1256.7873679999998	16.61	4	1256.7873679999998
cff61cb4-6bd8-4845-bbd8-8de3ada915c9	Pending	Amazon Pay	North America	Bradley Howe	2023-05-17	1	1	2859.29478	7.1	9	2859.29478
cff7152e-709b-4019-b698-ee2378b3597d	Returned	Credit Card	South America	Kristen Ramos	2022-10-03	1	1	742.009485	6.73	5	742.009485
cff9164d-8036-4a03-aed2-14c9b739b431	Pending	Amazon Pay	South America	Susan Edwards	2024-03-27	1	1	965.216628	3.72	9	965.216628
d05431b0-5ad5-406f-b05d-1765cbaa937e	Cancelled	Credit Card	Australia	Emily Matthews	2019-06-02	1	1	1376.9585000000002	3.5	5	1376.9585000000002
d059f9b4-6c36-476d-910b-9e5d9c5ba296	Pending	Amazon Pay	South America	Bradley Howe	2019-10-06	1	1	1406.029716	12.41	7	1406.029716
d05da3ff-4f8d-4d8a-a0eb-9a3414c6ea0b	Pending	Amazon Pay	North America	Bradley Howe	2023-04-12	1	1	1586.69572	28.34	10	1586.69572
d0733cd9-c508-4ae1-9372-05bd6094c147	Pending	PayPal	North America	Mary Scott	2019-02-07	1	1	364.92915	13.05	6	364.92915
d082ca7b-fe18-4a40-a1d9-9cc2f7c4a5ff	Pending	Gift Card	Europe	Emily Matthews	2019-02-19	1	1	638.5275	3.8	3	638.5275
d08ee78d-76e1-426d-94a5-d502ce4c4624	Cancelled	Debit Card	Europe	Roger Brown	2019-10-05	1	1	1134.789579	5.71	3	1134.789579
d09094e9-9953-45be-9229-fb0d8fb7f400	Cancelled	Debit Card	South America	Steven Coleman	2024-08-30	1	1	938.4904620000002	25.66	3	938.4904620000002
d0baf42d-b7f2-4cd8-a311-eaaf7033266a	Cancelled	Gift Card	Asia	Caitlyn Boyd	2022-10-28	1	1	982.784195	21.93	5	982.784195
d0cff4db-8cd9-460f-adc1-b7b1e06b9870	Returned	Gift Card	Australia	Mary Scott	2023-01-07	1	1	281.852856	19.96	3	281.852856
d0d33660-1739-4a12-a42b-4e8fef4c842a	Pending	PayPal	Asia	Caitlyn Boyd	2024-01-01	1	1	354.302668	13.61	2	354.302668
d0d4f2bb-bbbf-4fd8-8c6c-c8c2a3cbe9ce	Cancelled	Amazon Pay	North America	Kristen Ramos	2019-10-17	1	1	2561.24088	12.88	10	2561.24088
d0ef2158-fc5d-4782-bf01-d35bcd8bf321	Returned	Credit Card	Asia	Steven Coleman	2023-01-25	1	1	461.990775	21.65	3	461.990775
d1468065-2c0d-4bca-96d8-b08f9315d3b9	Cancelled	Credit Card	South America	Bradley Howe	2024-03-03	1	1	1714.789016	5.21	4	1714.789016
d14a96e6-d7d7-4051-b9e2-508251bcd1e6	Returned	Debit Card	South America	Mary Scott	2020-08-02	1	1	965.89584	11.8	3	965.89584
d14eaadf-30ae-4b40-b01a-cd4484a91a29	Returned	Debit Card	Australia	Crystal Williams	2023-11-13	1	1	3597.41194	20.21	10	3597.41194
d15cda80-60bf-4ac9-8bda-558b02d8221b	Pending	Gift Card	Europe	Jason Nelson	2021-09-21	1	1	3580.0440000000003	20.5	10	3580.0440000000003
d165c274-3060-44bf-9916-cec4f84d359f	Pending	Amazon Pay	Australia	Crystal Williams	2022-05-08	1	1	916.11438	18.12	3	916.11438
d171e4c2-726c-42ff-b62e-15bbc6aaebe2	Pending	Debit Card	South America	Diane Andrews	2024-04-17	1	1	351.747026	6.78	1	351.747026
d17356f7-2267-41a9-b9f1-03c65cae0c81	Cancelled	Gift Card	Europe	Joseph Brooks	2022-09-30	1	1	2747.649528	20.59	8	2747.649528
d18e7a2c-4539-43c2-a8ee-7fd533c3a3af	Cancelled	Amazon Pay	South America	Sandra Luna	2021-03-03	1	1	980.076051	5.79	9	980.076051
d19d1d0e-7d7c-4d29-bddb-39250fe9c63b	Pending	Gift Card	North America	Charles Smith	2022-05-29	1	1	238.75794	7.08	5	238.75794
d1c77e51-4d25-46eb-814e-0078163eef5c	Cancelled	Gift Card	Australia	Christina Thompson	2024-09-18	1	1	1000.631475	3.11	9	1000.631475
d1d52d3a-4e2d-4c3d-b673-e469d9e8c572	Cancelled	Credit Card	North America	Michelle Garza	2024-01-18	1	1	382.088056	19.08	1	382.088056
d1db7b36-106f-4413-bab3-df06c3d76c81	Returned	Gift Card	Asia	Diane Andrews	2022-04-07	1	1	214.731882	21.91	2	214.731882
d1dff6e1-f17c-42c3-8330-9c6bf30d0d27	Returned	Credit Card	South America	Diane Andrews	2024-08-17	1	1	649.122264	5.53	6	649.122264
d1e69798-5dcd-43b2-99eb-b9abaa7bcc1d	Cancelled	Gift Card	Europe	Jason Nelson	2020-01-24	1	1	1481.9381099999998	24.35	6	1481.9381099999998
d22661db-d1bb-4761-9339-e64f2ecb8fda	Returned	PayPal	North America	Sandra Luna	2019-01-30	1	1	477.378856	20.12	2	477.378856
d22f6c04-1a96-4c61-8e51-ad11238abb70	Returned	Gift Card	Asia	Michelle Andersen	2020-06-11	1	1	1200.1945199999998	28.02	6	1200.1945199999998
d237163b-3553-494b-9d28-fd47604ee3e3	Pending	PayPal	North America	Adam Smith	2021-07-05	1	1	102.46764	29.43	10	102.46764
d23a0056-96dd-4f79-adfd-22c9dc290e84	Cancelled	Debit Card	Australia	Kristen Ramos	2019-10-02	1	1	1739.777622	1.97	6	1739.777622
d2479c75-7521-4761-a6e7-8250e1ef6eb6	Cancelled	PayPal	Europe	Caitlyn Boyd	2020-10-25	1	1	338.60612100000003	9.77	7	338.60612100000003
d275dbd0-b235-43b1-b341-48994a14372b	Pending	Debit Card	Australia	Susan Edwards	2021-01-20	1	1	35.722866	24.46	1	35.722866
d27925a8-e1dd-44b4-afb5-0bf9e0d577cc	Returned	Debit Card	Australia	Charles Smith	2022-04-05	1	1	835.160052	27.08	3	835.160052
d2854a69-5f14-4ce8-b5b1-70daacee9c25	Returned	Gift Card	Europe	Susan Edwards	2022-11-27	1	1	2272.804794	19.14	9	2272.804794
d294b01d-45c8-4403-aedc-c95f8ae472d7	Cancelled	Gift Card	Australia	Michelle Garza	2019-06-02	1	1	2379.42067	8.81	10	2379.42067
d2a9720c-fbb9-41fc-b1f2-1c8902c1be36	Cancelled	Debit Card	South America	Susan Edwards	2023-05-31	1	1	1760.66048	6.3	8	1760.66048
d2ace62d-734a-4aff-90f0-b3392ce33e61	Pending	Amazon Pay	Australia	Emily Matthews	2020-09-27	1	1	400.086552	2.57	6	400.086552
d2b9af47-f130-453c-a13a-011db60afa94	Cancelled	PayPal	North America	Caitlyn Boyd	2020-01-26	1	1	2566.08	0	8	2566.08
d2bb7b0e-3828-4813-9027-7f7eea37e9b7	Pending	PayPal	Europe	Crystal Williams	2023-06-02	1	1	1013.853312	17.44	6	1013.853312
d2ca81e7-f2d7-4199-bd41-23072314793a	Returned	Credit Card	Europe	Diane Andrews	2021-06-10	1	1	1614.30486	15.88	5	1614.30486
d2ce9b65-82ff-4d7e-a487-19ee4f7a636d	Cancelled	Credit Card	Europe	Charles Smith	2019-01-17	1	1	881.9602040000001	9.11	4	881.9602040000001
d2de74b3-2457-4f75-b277-72e4ac65fd32	Returned	Gift Card	Europe	Charles Smith	2021-03-06	1	1	406.12572	10.82	10	406.12572
d31a3065-07e0-41a8-b64a-2fdb1e645817	Returned	Amazon Pay	Europe	Diane Andrews	2019-03-15	1	1	589.621032	27.28	7	589.621032
d32d090e-d464-4aa9-b64f-32ba62e9a78e	Returned	Debit Card	Australia	Crystal Williams	2023-07-08	1	1	2327.18447	0.02	5	2327.18447
d3631afd-a39c-4f3a-8c9c-b35109753bc7	Pending	Gift Card	North America	Jason Nelson	2023-06-19	1	1	1459.38352	27.06	8	1459.38352
d36aa387-cbca-4d4d-92c9-671643238eb2	Pending	PayPal	North America	Roger Brown	2019-07-16	1	1	123.45852	5.8	2	123.45852
d3884fde-6e91-4ed6-a338-a52c5c7cb8a6	Cancelled	PayPal	Australia	Emily Matthews	2021-12-06	1	1	1138.5419600000002	29.91	10	1138.5419600000002
d39a21c4-251a-4519-aa65-fc1cb4e53e0a	Pending	Debit Card	Europe	Caitlyn Boyd	2019-11-20	1	1	1206.9314399999998	5.62	8	1206.9314399999998
d3aa93ef-e87c-4574-8e0d-6bcfd2e53cf7	Cancelled	PayPal	Australia	Steven Coleman	2020-08-06	1	1	622.980774	27.46	3	622.980774
d3bff775-87b4-4301-bea6-1c651620791b	Cancelled	Debit Card	North America	Emily Matthews	2023-10-26	1	1	1232.391336	13.98	3	1232.391336
d3c405ee-6d49-45ab-ae03-44a3f39035d2	Cancelled	Debit Card	Asia	Jason Nelson	2020-06-10	1	1	110.12988	8.53	1	110.12988
d3c95544-b868-4475-8aa2-05e3d71458af	Pending	PayPal	Australia	Steven Coleman	2021-04-25	1	1	835.4817440000002	26.04	4	835.4817440000002
d3d41e06-257a-4a53-b413-df06afa0f68b	Returned	PayPal	Asia	Bradley Howe	2024-08-23	1	1	397.296	7	10	397.296
d3dd390d-f9ab-47ad-a7e4-d857a8e15c2b	Returned	Debit Card	South America	Emily Matthews	2024-03-29	1	1	3357.35244	1.2	9	3357.35244
d3e059dc-9e0f-47f5-b3b0-d58dc4c8e437	Cancelled	Gift Card	North America	Roger Brown	2023-01-29	1	1	67.16051999999999	8.65	8	67.16051999999999
d3ec359c-7d3d-43ff-8bee-a10bd165fe9c	Cancelled	PayPal	North America	Caleb Camacho	2022-04-30	1	1	810.342162	24.01	3	810.342162
d3f6be4f-d06a-4ddb-a569-9115bfd06321	Pending	Credit Card	Europe	Susan Edwards	2019-07-02	1	1	278.201292	4.26	6	278.201292
d402099c-49ad-42e9-a3d1-f969f3ddcf9b	Pending	Amazon Pay	Asia	Kristen Ramos	2022-04-24	1	1	1444.145625	5.75	9	1444.145625
d40556ba-c0fe-4546-ac12-8417b992f893	Returned	Debit Card	Europe	Sandra Luna	2022-06-26	1	1	2315.26981	1.86	5	2315.26981
d41c8d49-f426-4bc0-ae72-f022bd2abb20	Returned	PayPal	North America	Susan Edwards	2024-01-15	1	1	201.123472	19.37	1	201.123472
d42b9866-d660-4640-85c7-d66fe7b1105a	Cancelled	PayPal	South America	Roger Brown	2023-01-18	1	1	157.869404	29.51	1	157.869404
d44c660b-ea88-43cf-8590-5f8b9478ce60	Pending	Debit Card	Europe	Crystal Williams	2024-02-16	1	1	807.34907	1.55	2	807.34907
d49a7119-9b79-4d8a-b75e-bf7c995f4c83	Pending	PayPal	North America	Emily Matthews	2020-12-04	1	1	710.196032	0.96	7	710.196032
d4afc6e0-1074-45ee-b729-6e478df93870	Pending	Credit Card	Australia	Sandra Luna	2024-02-15	1	1	389.77104	24.11	2	389.77104
d4c30e3d-e7c1-4405-8d63-971298a37088	Returned	Amazon Pay	South America	Caitlyn Boyd	2020-10-14	1	1	1772.0082660000005	27.27	7	1772.0082660000005
d4c83b52-ecdf-4de7-bff2-b6144ccd18ca	Pending	Credit Card	Asia	Michelle Garza	2022-02-24	1	1	888.062676	24.14	3	888.062676
d4d14e2a-f72d-4fe1-a5e1-be351a6b893b	Cancelled	Debit Card	Australia	Susan Edwards	2020-03-26	1	1	704.61314	20.13	4	704.61314
d4e2b5db-a917-4a8c-8c42-8013071b1d49	Cancelled	Gift Card	Asia	Charles Smith	2022-08-08	1	1	942.850608	19.94	7	942.850608
d4f95a85-0a53-4a1d-9d91-d207fb3ab08d	Cancelled	PayPal	South America	Caitlyn Boyd	2021-11-18	1	1	1568.283372	23.47	6	1568.283372
d4fccf19-12ef-4333-a72c-47f32dfd1afd	Cancelled	Debit Card	Asia	Bradley Howe	2023-11-12	1	1	288.906546	25.91	2	288.906546
d4ff1f6e-e522-4588-9005-6c72b5cbb922	Returned	PayPal	Europe	Caitlyn Boyd	2021-03-04	1	1	2770.17	2.5	8	2770.17
d51451f1-5ee2-4716-87d3-118bca63ac5e	Pending	Amazon Pay	South America	Johnny Marshall	2021-08-13	1	1	905.872977	22.33	3	905.872977
d51c84eb-2c1f-40c7-9dce-3baa76067350	Cancelled	Gift Card	South America	Caleb Camacho	2024-12-11	1	1	3066.5412	2.09	10	3066.5412
d51f67e6-5b29-499b-9767-3a899d8b2b3a	Returned	Credit Card	Europe	Caleb Camacho	2023-11-11	1	1	855.686874	13.13	2	855.686874
d5457829-1cd5-4fa9-8f72-ba40ddb027bf	Returned	Amazon Pay	Asia	Adam Smith	2024-11-05	1	1	921.260928	12.68	4	921.260928
d5491a03-cfbb-4e5a-b5d5-b7234ef14a5a	Pending	Credit Card	North America	Joseph Brooks	2021-09-26	1	1	169.020618	3.67	1	169.020618
d5568197-dfdb-4be3-aace-d5a931dad3c3	Returned	Gift Card	Australia	Charles Smith	2020-11-13	1	1	291.170209	16.73	1	291.170209
d56da032-962e-408d-a2af-cedfd7307b1d	Cancelled	PayPal	Australia	Caleb Camacho	2019-06-08	1	1	280.546344	6.82	1	280.546344
d570706b-4143-40ae-8fc1-d3e5260ea955	Cancelled	PayPal	Europe	Crystal Williams	2024-06-07	1	1	3638.51824	7.28	10	3638.51824
d5761ae7-c84d-4938-a4a5-4d8e36a00915	Returned	Amazon Pay	Asia	Kristen Ramos	2024-03-20	1	1	851.6078600000001	0.21	5	851.6078600000001
d57895ab-bb73-454f-ba9f-3412154e3466	Cancelled	PayPal	Europe	Susan Edwards	2021-02-05	1	1	1894.331124	12.54	6	1894.331124
d58676af-f0d4-451b-bba9-22e31c001b95	Pending	Debit Card	South America	Charles Smith	2021-04-03	1	1	3470.97636	28.66	10	3470.97636
d597add3-accf-4ea0-8ca2-5b6f47653cc0	Cancelled	Amazon Pay	Asia	Joseph Brooks	2021-12-28	1	1	730.8590519999999	16.52	3	730.8590519999999
d59f72d0-abce-4307-afcf-c377885b55ec	Cancelled	Amazon Pay	Europe	Susan Edwards	2024-04-08	1	1	3845.697975	9.23	9	3845.697975
d5b1f0ad-4699-4c6d-93a7-1fa1a8476092	Returned	PayPal	Asia	Caitlyn Boyd	2022-05-05	1	1	337.49109	29.1	3	337.49109
d5bc0d49-7bf6-486e-a76a-69b7320d4973	Pending	Credit Card	Australia	Joseph Brooks	2021-04-17	1	1	382.0925160000001	26.68	3	382.0925160000001
d5ccf6cf-a796-4d4e-a6d6-7592770ea7e7	Returned	Amazon Pay	Asia	Sandra Luna	2022-07-13	1	1	637.70448	25.8	2	637.70448
d5e0bc24-b7e9-4198-85ba-04afd1049b29	Returned	Amazon Pay	Asia	Diane Andrews	2024-11-08	1	1	1377.89302	16.55	7	1377.89302
d5f7bff0-fcf8-4635-bddc-f8a2463ede71	Cancelled	PayPal	Australia	Emily Matthews	2024-07-25	1	1	2309.763786	15.41	6	2309.763786
d5fb68c2-3116-4773-ad71-22b87cad4704	Cancelled	Credit Card	Asia	Johnny Marshall	2024-09-27	1	1	44.442713000000005	16.13	1	44.442713000000005
d6131765-b932-46bd-99ed-e4b04747ee4d	Pending	Debit Card	Asia	Steven Coleman	2021-05-10	1	1	544.5378800000001	21.8	2	544.5378800000001
d61d2211-c7c3-4ee7-bf18-202c79c96388	Pending	Amazon Pay	North America	Christina Thompson	2021-12-06	1	1	3516.059862	2.82	9	3516.059862
d6319988-78b5-44e2-9331-25f8e80c61a5	Cancelled	Gift Card	South America	Caleb Camacho	2022-09-13	1	1	91.077196	24.53	7	91.077196
d64740c3-cd9f-4c59-ba1f-e7d1ae7be907	Cancelled	Amazon Pay	South America	Caleb Camacho	2024-10-03	1	1	2654.45112	27.7	8	2654.45112
d650bed9-46d1-473c-bd38-0456da5864ed	Pending	Amazon Pay	South America	Michelle Andersen	2023-06-20	1	1	465.8195280000001	9.08	2	465.8195280000001
d65d4573-1d7b-48fb-992d-0533cbdf68ac	Pending	Amazon Pay	South America	Steven Coleman	2022-05-03	1	1	841.8696300000001	1.38	3	841.8696300000001
d676aa33-8604-404c-9616-ba3e2e62ba8f	Pending	Amazon Pay	South America	Roger Brown	2022-10-16	1	1	329.285254	19.17	2	329.285254
d69e4880-accb-4d57-b51f-babc13835976	Pending	Credit Card	Asia	Michelle Garza	2024-07-28	1	1	394.40910600000007	16.97	9	394.40910600000007
d6b03c6c-8055-4c07-9e5b-19e9e90546e3	Cancelled	Debit Card	Europe	Michelle Andersen	2020-06-21	1	1	2388.0315	2.33	5	2388.0315
d6b84194-46fc-463f-abcb-5b69e481ae3d	Pending	Credit Card	North America	Steven Coleman	2021-08-24	1	1	4113.21775	0.75	10	4113.21775
d6dd566a-9b5b-4b48-b9f1-88815b547675	Returned	Amazon Pay	Asia	Michelle Garza	2019-05-25	1	1	2482.16716	18.05	8	2482.16716
d703eb90-b579-4ac6-b66f-b3c0cc106519	Pending	Amazon Pay	North America	Bradley Howe	2021-11-21	1	1	1611.300325	6.95	5	1611.300325
d70e8f6f-e2a5-44dc-a4d5-f6100c5bdfb6	Cancelled	PayPal	South America	Mary Scott	2020-08-17	1	1	343.687998	3.29	6	343.687998
d7127160-4061-493c-9991-821bdc5bf3b6	Pending	Gift Card	South America	Caleb Camacho	2022-06-27	1	1	147.77380799999997	23.56	6	147.77380799999997
df7566ab-caae-4aca-a904-d9e1f27057a4	Returned	Debit Card	Europe	Bradley Howe	2021-10-23	1	1	183.690309	27.99	3	183.690309
d71fabd5-6126-4f48-8a00-31a7bc531bc5	Cancelled	Credit Card	Australia	Crystal Williams	2022-07-28	1	1	3316.931728	11.81	8	3316.931728
d7263a34-c13a-4e59-9101-64d8badbc124	Pending	Debit Card	Asia	Bradley Howe	2021-02-26	1	1	494.592498	25.69	2	494.592498
d7310272-f11d-435a-8ac0-c6f707aad3d3	Cancelled	PayPal	Asia	Joseph Brooks	2023-05-11	1	1	2329.6615679999995	10.56	8	2329.6615679999995
d73f6f3d-14fa-41a7-968b-f617ceffacf3	Returned	Amazon Pay	North America	Michelle Garza	2019-10-20	1	1	1386.680688	28.84	6	1386.680688
d74d1f2b-d34d-4c7a-91b9-07c586b3896f	Returned	Gift Card	Australia	Joseph Brooks	2023-12-13	1	1	380.57976	4.3	3	380.57976
d75fdd57-e187-4f15-ac8a-c255cfb2ec0f	Returned	Credit Card	Europe	Diane Andrews	2019-04-27	1	1	142.420818	7.26	3	142.420818
d767e785-a667-4847-81fe-3fd08504466e	Cancelled	Amazon Pay	North America	Adam Smith	2019-06-11	1	1	361.47012000000007	17.17	10	361.47012000000007
d76cbd44-176e-449d-89f7-31322ac4490c	Cancelled	Gift Card	South America	Susan Edwards	2020-05-01	1	1	149.44566	21.22	2	149.44566
d77c4c04-a9d5-488f-9d6a-693ee910ade3	Pending	Debit Card	North America	Adam Smith	2021-01-11	1	1	411.9208	26.6	10	411.9208
d77d0769-08b7-4955-98f5-c15d218fdb03	Pending	Amazon Pay	South America	Joseph Brooks	2020-04-07	1	1	2631.51988	18.71	8	2631.51988
d7891442-5c06-4a72-a4a4-e05cdd77e206	Returned	Amazon Pay	Australia	Caitlyn Boyd	2022-06-08	1	1	1688.3255759999995	15.28	7	1688.3255759999995
d79e6af1-f2b4-4f8c-ae26-d804e7561dd3	Pending	Gift Card	Australia	Joseph Brooks	2024-08-10	1	1	121.5941	8.85	10	121.5941
d7b261ba-4c73-43be-9bbf-18dc9c8458d3	Returned	Gift Card	South America	Bradley Howe	2020-06-18	1	1	1113.0420599999998	19.72	3	1113.0420599999998
d7ba1994-741c-43d6-9806-7f5467c4f2af	Returned	Amazon Pay	South America	Roger Brown	2022-02-28	1	1	3466.912608	5.86	8	3466.912608
d7c57e86-78df-4382-b898-240d18683314	Pending	Amazon Pay	Australia	Charles Smith	2021-10-02	1	1	632.7212480000001	8.28	8	632.7212480000001
d7e2b5c2-7684-45d0-b10b-7d2e12fddaad	Pending	Gift Card	Asia	Mary Scott	2024-05-07	1	1	172.595775	20.15	5	172.595775
d7e5c543-a70f-4531-9eb8-026f30365524	Returned	Credit Card	South America	Roger Brown	2022-12-06	1	1	89.02385999999998	19.45	9	89.02385999999998
d7e89f0e-8bb2-4d1e-8fb0-0dc4e31af536	Returned	Gift Card	Europe	Crystal Williams	2019-07-01	1	1	2151.294817	26.51	7	2151.294817
d7fe3bf2-e90c-4aa8-9dba-96e27b00b067	Cancelled	Amazon Pay	North America	Charles Smith	2022-12-28	1	1	206.038535	2.55	1	206.038535
d81722b8-7f90-43e7-9331-7e95e56e2883	Cancelled	PayPal	Asia	Susan Edwards	2019-04-13	1	1	465.162304	26.51	2	465.162304
d81a0b24-0e66-484b-8e87-99dbe01ecbf1	Returned	Credit Card	Europe	Caitlyn Boyd	2023-07-23	1	1	1892.39452	21.86	10	1892.39452
d82eaccc-1da3-445e-bb54-0ef93876ee3f	Cancelled	Gift Card	North America	Caitlyn Boyd	2019-12-27	1	1	3314.86722	20.89	10	3314.86722
d82f729c-de9e-4850-9c48-e7272439d543	Returned	Amazon Pay	Asia	Michelle Andersen	2019-07-22	1	1	2507.718906	1.13	9	2507.718906
d832fe65-1cf9-4f93-81ec-46353e16f1e2	Pending	Gift Card	Australia	Caleb Camacho	2024-02-11	1	1	150.559695	7.83	5	150.559695
d8471fa5-c8f4-4af9-97c0-3c8dc0906c8e	Returned	Credit Card	Europe	Kristen Ramos	2022-06-28	1	1	664.9262299999999	9.54	5	664.9262299999999
d88768d9-dd4d-4e00-b4db-2f86e43d7ff5	Pending	Gift Card	Europe	Crystal Williams	2024-02-13	1	1	344.316882	29.54	1	344.316882
d88deaf8-8951-456f-931e-b2d132c3f427	Cancelled	Amazon Pay	Europe	Kristen Ramos	2021-05-05	1	1	3330.02124	1.72	10	3330.02124
d8a0ab29-2a36-4e1c-81b4-731633140e81	Cancelled	PayPal	Asia	Mary Scott	2021-08-30	1	1	1135.21108	4.56	5	1135.21108
d8c369ab-a9f0-456b-a1d2-97c32078b2e7	Cancelled	Gift Card	South America	Jason Nelson	2024-06-21	1	1	444.170511	3.59	1	444.170511
d8da8c3f-cb4b-4c75-9e23-7e5cb35cd924	Returned	Credit Card	Europe	Michelle Andersen	2023-06-03	1	1	979.180956	4.58	9	979.180956
d8de0259-a341-412c-a03f-de9605ad780d	Pending	PayPal	Asia	Charles Smith	2020-01-21	1	1	2070.245935	11.07	5	2070.245935
d8ff10f0-4a8e-4714-a4c3-ba37d4f5304e	Pending	Debit Card	Europe	Sandra Luna	2022-09-11	1	1	604.0840189999999	8.67	7	604.0840189999999
d912fe37-d6e5-469e-a190-e2f25bfc8c47	Pending	Credit Card	North America	Johnny Marshall	2021-07-16	1	1	351.10575	3.25	1	351.10575
d926f9f1-051f-40df-bd37-98f898c78fa0	Returned	Gift Card	Asia	Christina Thompson	2020-01-04	1	1	438.4167	6.7	1	438.4167
d939c1be-eded-4e25-b491-995dad429521	Pending	Amazon Pay	South America	Crystal Williams	2019-05-18	1	1	165.33770800000002	16.74	2	165.33770800000002
d941a011-a970-4dc4-943b-8db00f57bde6	Pending	Debit Card	Asia	Charles Smith	2019-07-24	1	1	198.166944	14.48	6	198.166944
d9539586-e5b1-46c5-aaa0-4ec4adb7d4f2	Pending	Amazon Pay	North America	Bradley Howe	2024-07-26	1	1	870.257774	4.07	2	870.257774
d95f6e30-ce61-4b1d-a551-b11f964a8fd8	Cancelled	Gift Card	North America	Kristen Ramos	2024-07-12	1	1	1584.60561	1.51	6	1584.60561
d95fdb20-33ca-4f7c-a320-6ebd1e4f16ac	Returned	PayPal	South America	Sandra Luna	2021-06-29	1	1	842.8247	18.41	4	842.8247
d968d246-f276-4df0-9daa-dda9eca4121a	Pending	Debit Card	Australia	Michelle Garza	2021-04-17	1	1	604.4714550000001	3.57	9	604.4714550000001
d9722469-7210-42cf-a3e9-1a74d1bbc639	Pending	Credit Card	North America	Emily Matthews	2024-02-18	1	1	60.910773000000006	10.57	7	60.910773000000006
d97a26c9-fc09-45a0-877f-1f88abccaed5	Returned	PayPal	North America	Jason Nelson	2022-09-18	1	1	447.480904	1.98	1	447.480904
d98b6b59-7e69-401a-aa03-6f033d00df01	Cancelled	Debit Card	Asia	Charles Smith	2020-03-27	1	1	1033.64622	15.82	5	1033.64622
d98d0891-39c7-4ccf-a118-db6ed6aadfea	Cancelled	Gift Card	North America	Sandra Luna	2022-06-16	1	1	864.807	17.95	5	864.807
d9a90e67-de0d-4ec8-b774-efcb2f5b011d	Returned	PayPal	Europe	Michelle Garza	2024-08-18	1	1	1741.6476000000002	6.06	6	1741.6476000000002
d9ad6909-e2a8-4155-95c3-09603fd11c5e	Returned	PayPal	South America	Michelle Garza	2020-12-02	1	1	2008.031556	0.33	6	2008.031556
d9add42b-acd1-4333-974a-295007232488	Returned	Amazon Pay	North America	Steven Coleman	2021-06-30	1	1	164.51180599999998	17.67	2	164.51180599999998
d9bded4d-84e8-4921-9273-398eb9e93348	Returned	Amazon Pay	Europe	Susan Edwards	2024-09-10	1	1	653.2227720000001	12.61	3	653.2227720000001
d9bfee10-96d0-4add-9c9f-777e99de5b81	Pending	PayPal	Australia	Adam Smith	2020-01-23	1	1	974.342936	27.44	7	974.342936
d9df8b63-4d70-4fd2-9515-d65cc8b39f66	Cancelled	Gift Card	Europe	Steven Coleman	2023-08-14	1	1	470.3821019999999	3.01	6	470.3821019999999
d9ec8934-c4fb-4aea-96ce-5612f6f3865f	Returned	PayPal	Asia	Roger Brown	2024-10-31	1	1	2500.770924	22.82	9	2500.770924
d9fd1fb6-087f-4c10-aec9-bc683ed24584	Pending	Debit Card	Asia	Johnny Marshall	2019-06-21	1	1	1802.91825	21.25	6	1802.91825
da0cfb90-a3f2-4fc7-94ac-295740faa0b1	Returned	Amazon Pay	Europe	Michelle Garza	2021-02-13	1	1	584.2952579999999	21.51	6	584.2952579999999
da394ff8-3ada-4e66-824c-1d5083293192	Pending	Gift Card	South America	Steven Coleman	2019-08-02	1	1	857.9323339999999	16.22	7	857.9323339999999
da56aaa0-a6f8-4c5d-bcb1-463af125f408	Pending	Credit Card	Europe	Mary Scott	2022-08-24	1	1	171.912	22	1	171.912
da67565b-0608-4ea1-bfec-296c47933d2c	Pending	Debit Card	Australia	Susan Edwards	2022-12-14	1	1	193.758176	11.36	1	193.758176
da85a6cb-69ba-49fe-b3b0-aaa976602d6b	Pending	Amazon Pay	Australia	Steven Coleman	2024-10-22	1	1	768.8232419999999	13.09	2	768.8232419999999
da8b05b4-7fd7-44fa-95fb-4a28382971ea	Pending	PayPal	Asia	Susan Edwards	2022-04-19	1	1	2452.038464	3.92	8	2452.038464
da8cc896-3021-417d-a45b-18b87fde6989	Cancelled	Debit Card	Europe	Crystal Williams	2022-05-20	1	1	148.01424	7.52	5	148.01424
da90ce9e-586d-4d91-8a53-4a1e45e0817b	Pending	Amazon Pay	Asia	Crystal Williams	2024-02-05	1	1	448.86474	23.05	2	448.86474
da9e2abb-efec-4cdf-9ea5-0994fbc86752	Pending	Amazon Pay	South America	Sandra Luna	2021-04-20	1	1	1279.510218	12.13	7	1279.510218
da9eebfd-c331-4305-a31d-32e31acc636b	Cancelled	Amazon Pay	South America	Joseph Brooks	2023-01-06	1	1	130.489464	13.48	2	130.489464
daa8e1e0-e390-48c7-a720-560632263d1c	Cancelled	PayPal	Europe	Charles Smith	2021-02-04	1	1	1320.775614	7.94	3	1320.775614
daaee8d9-bcc7-4e1b-9aec-78950e16a967	Returned	Debit Card	Europe	Diane Andrews	2024-04-11	1	1	1426.750336	25.44	4	1426.750336
dace0fac-bc2b-4eea-98cc-a29d8f920b4d	Returned	Debit Card	Asia	Kristen Ramos	2021-01-15	1	1	821.50038	21.38	9	821.50038
dad73143-542a-4290-8ef4-fbb9e39b21dc	Pending	PayPal	Asia	Caitlyn Boyd	2024-03-11	1	1	310.074408	6.96	7	310.074408
daf92686-4f0f-4da0-8c9b-39e139810658	Returned	PayPal	South America	Joseph Brooks	2024-06-30	1	1	1279.07208	9.8	9	1279.07208
db1ef549-9841-4311-88d8-3d00c0ffe74b	Returned	Amazon Pay	South America	Caitlyn Boyd	2022-11-05	1	1	3520.844847	1.69	9	3520.844847
db259f7c-3d27-4e7e-9604-0f4a0f22d2d4	Pending	Credit Card	Asia	Michelle Andersen	2022-08-06	1	1	897.32888	7.53	10	897.32888
db26c260-3832-45c0-8b07-4d19d1df2be5	Cancelled	Amazon Pay	Australia	Charles Smith	2022-04-16	1	1	359.904616	11.48	2	359.904616
db2b202a-7a19-4edf-ac3d-26243ba05b79	Pending	Amazon Pay	South America	Diane Andrews	2024-09-04	1	1	1519.789656	10.47	4	1519.789656
db329ef2-0962-47a0-a8de-481cf51fd848	Cancelled	Amazon Pay	Asia	Joseph Brooks	2021-03-16	1	1	523.620324	25.62	6	523.620324
db32e189-a06d-49eb-82f5-08b9b2f1de91	Returned	PayPal	Australia	Kristen Ramos	2020-06-07	1	1	2674.51558	25.53	10	2674.51558
db3326f2-0488-4374-915e-6c31f12cbc94	Returned	Debit Card	Europe	Diane Andrews	2022-05-03	1	1	939.2075	2.42	7	939.2075
db5e912a-f5ed-4b43-bcb8-c38e5f5f0740	Cancelled	PayPal	Australia	Michelle Andersen	2020-08-17	1	1	2872.587528	8.43	8	2872.587528
db66fae5-4ee6-4dfe-8657-ea82a1d65cbd	Pending	Credit Card	Australia	Mary Scott	2024-12-08	1	1	421.233912	6.28	1	421.233912
db6731be-b60b-4cab-b021-fcfc68ac2948	Cancelled	Debit Card	Asia	Emily Matthews	2019-02-11	1	1	2833.41177	0.13	10	2833.41177
dba1349c-c66f-4f6e-a4a2-365c9d41ad8b	Returned	Debit Card	Asia	Mary Scott	2019-05-17	1	1	1240.921171	19.97	7	1240.921171
dba973bb-08d4-4172-bab8-53091f0c6c1a	Returned	Debit Card	Europe	Roger Brown	2024-03-13	1	1	1887.35022	10.6	7	1887.35022
dbb6c885-212f-47d9-8795-36d750769541	Pending	Amazon Pay	Asia	Bradley Howe	2022-07-21	1	1	1515.777024	24.48	8	1515.777024
dbc09fc6-2695-475c-b427-d51800340671	Pending	Gift Card	Europe	Bradley Howe	2020-10-17	1	1	903.971484	5.47	6	903.971484
dbc3c157-7e9b-411a-9777-e9d758b01c91	Pending	Gift Card	South America	Jason Nelson	2022-01-11	1	1	1629.2140110000005	23.93	9	1629.2140110000005
dbc83233-7c5f-459d-a905-2bb980a9dcea	Returned	Credit Card	Europe	Crystal Williams	2019-02-10	1	1	217.125504	8.06	3	217.125504
dbf0aed0-1c92-4d1a-8489-a84822d4849f	Pending	Amazon Pay	Europe	Charles Smith	2024-12-29	1	1	2656.16224	23.48	10	2656.16224
dbfeb60e-4c38-4c7a-9228-d943577b89b3	Cancelled	PayPal	Europe	Michelle Garza	2019-12-06	1	1	1543.9591440000002	26.29	8	1543.9591440000002
dc09d409-30b5-4b3f-8fe5-cf8d7d3007bb	Pending	Debit Card	Europe	Kristen Ramos	2024-08-17	1	1	823.6780470000001	12.83	3	823.6780470000001
dc1447e4-f45e-4636-bd5c-bbceb5bd3d7a	Pending	Gift Card	North America	Michelle Garza	2024-02-04	1	1	2491.045962	2.13	6	2491.045962
dc209210-6962-4395-b925-f572269d0fea	Pending	Amazon Pay	Europe	Caleb Camacho	2021-03-10	1	1	810.0853460000001	10.47	2	810.0853460000001
dc2cc02b-1dcd-4457-81d1-89ac114fd855	Cancelled	Debit Card	Europe	Steven Coleman	2020-01-09	1	1	2658.50505	5.05	6	2658.50505
dc33555f-f5e5-4718-91b8-de9087888bcb	Pending	PayPal	Asia	Kristen Ramos	2024-09-09	1	1	1232.0962020000002	9.31	6	1232.0962020000002
dc4d1362-a823-478b-83e2-fea6c584bb2d	Returned	Debit Card	North America	Steven Coleman	2022-06-28	1	1	3160.4348440000003	4.26	7	3160.4348440000003
dc5ffa2d-b810-4965-81ad-404944f4d8bb	Returned	Debit Card	Europe	Diane Andrews	2022-01-13	1	1	1277.1571199999998	28.8	8	1277.1571199999998
dc72fbcc-7429-484e-990e-d2fff073e547	Returned	PayPal	North America	Michelle Garza	2021-03-14	1	1	2275.28244	29.56	9	2275.28244
dc855515-a2fb-406c-812c-09ef4e479754	Cancelled	PayPal	Australia	Charles Smith	2024-10-25	1	1	958.7214	12.25	4	958.7214
dc98d050-017f-4601-8432-b98779daa323	Cancelled	Debit Card	Australia	Diane Andrews	2023-08-20	1	1	1359.55155	15.15	7	1359.55155
dc9b1c89-b90e-4924-9283-e223c41d2886	Returned	Amazon Pay	Europe	Johnny Marshall	2020-01-20	1	1	127.08704	0.48	10	127.08704
dca0db03-be43-4c9e-9eac-cbfbdbc1960c	Returned	Gift Card	South America	Jason Nelson	2022-05-25	1	1	4024.894752	9.31	9	4024.894752
dca5b5df-f67f-46be-9cdd-20f9dc1ada75	Returned	PayPal	Europe	Jason Nelson	2020-03-28	1	1	3039.380838	27.98	9	3039.380838
dcaaab68-47fb-493a-8de4-02574e13c5b7	Returned	Gift Card	Asia	Michelle Andersen	2019-12-29	1	1	606.376224	7.68	6	606.376224
dcaeeeb2-5588-44a4-a4e5-b14665a6d93a	Returned	Amazon Pay	South America	Emily Matthews	2019-11-21	1	1	740.311416	0.68	6	740.311416
dcb2ab1b-fd34-47f6-9745-f32d144c38d9	Cancelled	Amazon Pay	Europe	Bradley Howe	2024-05-29	1	1	84.77847000000001	27.26	3	84.77847000000001
dcbce5d6-44a5-4845-852d-253bed1b354b	Returned	PayPal	Asia	Caleb Camacho	2024-03-06	1	1	47.040912000000006	10.09	3	47.040912000000006
dcf116d4-fc3b-45da-a3ab-b2378ec72c33	Pending	PayPal	Europe	Michelle Andersen	2022-03-01	1	1	62.548312	20.28	2	62.548312
dcfbe039-474e-4220-bd48-77d658df2c14	Cancelled	Amazon Pay	South America	Caitlyn Boyd	2023-08-08	1	1	707.059665	8.85	9	707.059665
dd0304e7-324f-46ca-b073-249e38e3f422	Cancelled	Debit Card	North America	Susan Edwards	2022-09-15	1	1	673.46478	19.9	9	673.46478
dd039e46-6347-43f6-804d-5fd156f3abdf	Returned	Amazon Pay	Asia	Caleb Camacho	2024-06-14	1	1	195.939495	4.05	9	195.939495
dd2a234b-7d60-4060-a21d-bd3a7096b1e3	Pending	Debit Card	North America	Caleb Camacho	2019-03-20	1	1	494.041086	13.54	3	494.041086
dd4e067b-6874-4cdc-aeab-79aaa447514e	Returned	PayPal	Europe	Kristen Ramos	2022-11-29	1	1	541.87056	23.98	6	541.87056
dd5d5a96-ebb4-4dd5-be2f-4d405c91a5cd	Cancelled	Credit Card	Asia	Susan Edwards	2022-04-04	1	1	132.90038400000003	22.84	4	132.90038400000003
dd66f4c1-e98c-4a0d-a521-e353f53b5ebb	Cancelled	Amazon Pay	North America	Jason Nelson	2022-06-06	1	1	3847.13216	9.12	10	3847.13216
dd74f995-98cc-48b6-a9af-4a37cb964c56	Cancelled	Gift Card	Asia	Joseph Brooks	2019-12-14	1	1	1811.678265	1.83	5	1811.678265
dda46e57-46ab-4bd9-8190-dfbd1e374e48	Pending	Debit Card	Australia	Roger Brown	2020-06-21	1	1	167.180896	23.48	1	167.180896
dda677f2-1e0c-4e72-8e3a-e1cb61b5b15c	Returned	PayPal	Australia	Joseph Brooks	2023-03-28	1	1	2933.06265	17.11	10	2933.06265
dda88c3d-b0b6-4992-9b0e-30aeb308d41f	Cancelled	Amazon Pay	Asia	Roger Brown	2021-02-16	1	1	312.03970200000003	11.98	9	312.03970200000003
ddac6035-94e8-4f5e-a741-0e99e4a731e5	Pending	Credit Card	North America	Michelle Andersen	2024-11-23	1	1	1275.023475	29.43	9	1275.023475
ddb178b9-2ddd-47e6-9275-fdde0fcc3055	Pending	Amazon Pay	South America	Emily Matthews	2019-03-02	1	1	1503.012672	18.52	4	1503.012672
ddc81843-a16a-45b7-ae36-c3f01d00612a	Returned	Credit Card	Europe	Sandra Luna	2021-11-05	1	1	1293.20932	18.86	4	1293.20932
ddd98a30-647c-4e0b-b530-316e8b6a1308	Pending	PayPal	North America	Christina Thompson	2022-07-19	1	1	1818.504935	24.99	5	1818.504935
dddc321c-303d-45b4-b921-ec2b4c832705	Returned	PayPal	Australia	Crystal Williams	2022-04-25	1	1	629.983368	29.48	9	629.983368
dde067f6-047b-4b93-9e2b-87f64e9648b3	Returned	Amazon Pay	Europe	Diane Andrews	2020-02-22	1	1	2785.2011999999995	4.42	10	2785.2011999999995
ddf2cc0d-959b-497c-a387-05ca94cd87f7	Pending	Gift Card	Australia	Caitlyn Boyd	2022-09-01	1	1	866.5436999999998	22.45	5	866.5436999999998
ddfd06cc-dec0-435a-adaf-cea20bd57f0f	Returned	Amazon Pay	South America	Michelle Andersen	2023-08-13	1	1	2322.774432	7.19	8	2322.774432
de08ffaa-f3de-47cc-b6eb-ac0e07bf92f1	Cancelled	Credit Card	Australia	Susan Edwards	2019-10-24	1	1	577.520622	0.19	2	577.520622
de0ec269-17b1-4869-b550-e4f6418eaf64	Cancelled	Amazon Pay	Europe	Caitlyn Boyd	2023-08-01	1	1	1204.852032	14.36	9	1204.852032
de20c799-08da-40b7-b972-186bc72e963d	Pending	Amazon Pay	Australia	Charles Smith	2021-04-19	1	1	1015.63437	22.83	3	1015.63437
de2a59d6-9331-4a0b-b8ae-2c60c5607753	Pending	Amazon Pay	Europe	Christina Thompson	2020-12-30	1	1	281.661672	13.77	8	281.661672
de2ddcd3-3e6d-4221-8aae-f96921b6aaee	Cancelled	Amazon Pay	South America	Sandra Luna	2022-12-31	1	1	1089.56016	24.6	8	1089.56016
de2ebee4-966d-4e3c-8d02-0caebff3183d	Returned	Credit Card	South America	Michelle Andersen	2019-08-21	1	1	209.98872	27.45	6	209.98872
de2fd0f2-810d-4442-a2de-432e423edfa9	Returned	Credit Card	North America	Mary Scott	2023-01-15	1	1	150.911512	22.76	2	150.911512
de465f20-163f-4c9d-8e95-3fd027d86f0b	Cancelled	PayPal	Europe	Crystal Williams	2020-03-28	1	1	3497.67636	20.52	10	3497.67636
de6cdcd8-7893-4c74-9697-54b507b5292d	Cancelled	Credit Card	Asia	Emily Matthews	2020-10-22	1	1	1322.700416	0.48	4	1322.700416
de8b59b4-595a-4c75-bc57-d7fa27a7e60c	Pending	Gift Card	Europe	Caitlyn Boyd	2019-10-09	1	1	1979.978847	14.31	7	1979.978847
de952a1d-f604-44d1-a06a-8e94a123bec1	Pending	Amazon Pay	North America	Jason Nelson	2022-07-15	1	1	496.7126150000001	28.07	7	496.7126150000001
deb530d2-6025-4699-85a6-53b1051f62d6	Pending	PayPal	Europe	Mary Scott	2021-08-29	1	1	27.213536	21.62	4	27.213536
debcb990-1ba7-43fd-8f88-e371918ab9ef	Returned	Credit Card	Australia	Roger Brown	2023-03-06	1	1	1169.980056	27.82	4	1169.980056
debf988e-c738-4f38-a709-94d9140ef26f	Cancelled	Credit Card	Australia	Jason Nelson	2020-04-11	1	1	909.09	0	3	909.09
dec93253-c073-4632-a2a8-b0730039e805	Cancelled	PayPal	North America	Christina Thompson	2021-04-04	1	1	311.83866	22.9	1	311.83866
deec484b-fbfb-449c-9dee-51d25e9ecfb0	Returned	PayPal	Europe	Mary Scott	2021-09-05	1	1	568.042278	21.91	2	568.042278
df12ed60-ebe8-4ac3-b76c-b74585db743a	Returned	PayPal	South America	Kristen Ramos	2021-04-25	1	1	230.73792	14.16	5	230.73792
df4894e9-9af6-4195-b39e-775fb492e6ab	Returned	Amazon Pay	South America	Joseph Brooks	2023-07-20	1	1	2066.2369	2.49	5	2066.2369
df496727-4b7f-4951-a36f-8c2b00403b9d	Cancelled	Amazon Pay	South America	Michelle Andersen	2024-04-30	1	1	269.739342	5.86	1	269.739342
df62bb4b-7917-45ee-a3aa-66127526ddbf	Pending	Amazon Pay	North America	Diane Andrews	2020-01-01	1	1	160.711074	6.46	1	160.711074
df7c5d5c-59a4-4d91-b209-0617b0e50616	Cancelled	Gift Card	Asia	Michelle Andersen	2019-11-27	1	1	1152.274626	22.69	3	1152.274626
df8ac29b-14a6-48d5-addb-cc438890b4c7	Returned	PayPal	Europe	Christina Thompson	2022-01-22	1	1	54.053898	21.91	2	54.053898
df8accc4-3a46-4f3e-a9f4-4f4eba644832	Pending	PayPal	Europe	Johnny Marshall	2020-12-26	1	1	9.161040000000002	25.52	2	9.161040000000002
dfa1d4a8-ca41-43f0-9589-f843e20a393a	Returned	Gift Card	Australia	Adam Smith	2020-06-03	1	1	48.20035500000001	9.99	3	48.20035500000001
dfb272eb-ed8a-4133-9379-c1eb3a1c310c	Cancelled	PayPal	Asia	Mary Scott	2021-04-04	1	1	1385.0864069999998	4.29	3	1385.0864069999998
dfb5be49-0749-4e15-abc7-0a19a60e94ba	Cancelled	Debit Card	North America	Michelle Garza	2024-10-24	1	1	997.54596	18.14	5	997.54596
dfd0dacc-3b17-4b30-a51a-f861680374e1	Pending	Debit Card	Asia	Mary Scott	2023-03-25	1	1	2334.50541	0.3	9	2334.50541
dfe383da-e07c-428f-8956-21434c950677	Cancelled	PayPal	Europe	Michelle Garza	2024-06-01	1	1	225.837738	23.14	1	225.837738
dff19b10-b560-4599-b342-d6ec55d77375	Pending	Gift Card	South America	Jason Nelson	2020-10-23	1	1	4098.05514	6.58	10	4098.05514
e01cac15-f923-4e51-a3fb-58ed3fa263d3	Returned	Credit Card	South America	Sandra Luna	2021-01-23	1	1	2875.228104	11.37	7	2875.228104
e02aba8b-45a9-44f8-8935-4310859380d4	Pending	Gift Card	South America	Charles Smith	2022-08-07	1	1	342.537334	10.14	1	342.537334
e03a0232-3a67-4581-bf2f-1864b00d9afb	Returned	PayPal	South America	Adam Smith	2022-03-27	1	1	3142.458305	3.03	7	3142.458305
e06255bd-5532-473f-8e3f-273c8ff606b9	Cancelled	PayPal	Asia	Bradley Howe	2024-01-05	1	1	428.694378	8.23	2	428.694378
e067b8f5-f5be-437e-9995-63567d9095db	Returned	Credit Card	South America	Crystal Williams	2019-07-21	1	1	3443.336	26.55	10	3443.336
e06e2713-1b5f-4673-b550-04008f58ac4a	Pending	Gift Card	South America	Bradley Howe	2022-06-25	1	1	3717.534528	12.48	9	3717.534528
e08150fb-bb93-4e0c-b393-f03baf348ccb	Cancelled	Debit Card	Asia	Susan Edwards	2020-11-16	1	1	448.66824	18.32	10	448.66824
e084246e-0130-4911-82f4-bd2402b38827	Pending	Debit Card	Asia	Susan Edwards	2024-10-09	1	1	2446.61016	2.92	10	2446.61016
e0972004-f757-438c-a6be-29cd5778c3e9	Pending	PayPal	Asia	Michelle Garza	2022-01-19	1	1	2481.17562	10.68	9	2481.17562
e09a2680-1d15-408c-b79a-96af8e991419	Returned	Gift Card	North America	Michelle Andersen	2021-08-06	1	1	1740.163656	8.37	4	1740.163656
e09e1b53-dd31-4ba4-8f44-f6e72e1e4f51	Pending	Debit Card	Asia	Michelle Andersen	2020-04-21	1	1	502.8305399999999	7.1	6	502.8305399999999
e0baca6b-05a6-4293-9cde-0d92830b09c7	Cancelled	Debit Card	South America	Adam Smith	2019-04-17	1	1	1083.59952	28.48	10	1083.59952
e0c20941-6aa6-45c8-9ea7-c0f8d0527e21	Pending	Debit Card	Australia	Steven Coleman	2019-06-25	1	1	1952.05038	0.11	5	1952.05038
e0dd4c6b-19a7-4ea2-bce7-0758615855b4	Returned	Gift Card	North America	Crystal Williams	2020-11-12	1	1	1548.231615	21.67	5	1548.231615
e0e212a7-2064-49b8-b938-ea387cb68b7c	Pending	Gift Card	North America	Michelle Andersen	2019-04-02	1	1	258.996444	26.53	7	258.996444
e0e3b6b5-a3d6-48e4-9a2a-6f94820a4f5f	Returned	Credit Card	North America	Roger Brown	2024-10-26	1	1	2140.357335	7.51	5	2140.357335
e0f2dbae-6ac9-47a6-90f0-4cdef46f5297	Cancelled	PayPal	Europe	Bradley Howe	2022-02-28	1	1	988.41348	23.76	5	988.41348
e1110577-a7e0-4f9b-acca-c8d48aab4229	Pending	Gift Card	Australia	Johnny Marshall	2022-07-06	1	1	1389.10863	28.3	7	1389.10863
e1214dd4-8e2d-4f2a-8c69-d1ae71b07304	Returned	PayPal	Europe	Michelle Garza	2021-02-11	1	1	1810.689345	12.47	5	1810.689345
e125dc9c-44d6-4a35-8436-20a96222ace7	Returned	PayPal	Australia	Diane Andrews	2024-03-31	1	1	3310.29504	0.16	10	3310.29504
e126a900-c875-459e-ae7e-93a30dbad435	Cancelled	Credit Card	Australia	Caleb Camacho	2021-08-14	1	1	2371.03083	20.17	10	2371.03083
e1303a6f-1617-4094-b7fc-bf7ba297e587	Returned	Credit Card	Australia	Emily Matthews	2024-07-10	1	1	589.99224	10.39	10	589.99224
e17509f2-418b-4984-a6fc-233cf3efdc5f	Pending	Debit Card	Asia	Christina Thompson	2019-04-06	1	1	133.89744000000002	13.92	5	133.89744000000002
e184d5c1-602e-4f3d-ba2f-9d8edfd416a0	Cancelled	Gift Card	Asia	Emily Matthews	2019-12-21	1	1	108.784272	5.52	6	108.784272
e193ac68-c126-445d-83e9-07d81cee37c6	Cancelled	Amazon Pay	Europe	Johnny Marshall	2022-06-16	1	1	735.536256	5.92	2	735.536256
e197e884-9661-469b-8497-52e65ffdb74b	Pending	Gift Card	Asia	Adam Smith	2019-01-26	1	1	254.589975	5.55	5	254.589975
e1bdf5bb-ac39-4448-b7a6-603399bec17b	Returned	Gift Card	South America	Emily Matthews	2022-11-13	1	1	3113.6275500000006	16.95	10	3113.6275500000006
e1c613e5-5aec-461f-a134-f3687bb7705c	Pending	Amazon Pay	North America	Steven Coleman	2023-09-25	1	1	830.2721279999998	0.96	6	830.2721279999998
e1d6eff0-cb7c-45ac-99ae-2ea4774b33e0	Pending	Credit Card	Europe	Diane Andrews	2019-08-27	1	1	2072.97532	14.07	10	2072.97532
e1edb2e8-e233-43e7-ad1d-6cf171a0a23f	Pending	Credit Card	Asia	Caitlyn Boyd	2023-06-23	1	1	839.8119559999999	29.99	4	839.8119559999999
e2047fe5-80d9-418c-9e34-4afeb87a0de1	Pending	Gift Card	North America	Jason Nelson	2019-01-31	1	1	1592.7166919999995	15.46	7	1592.7166919999995
e20b7c74-d943-406f-bb4f-f2311d0b1a14	Cancelled	Credit Card	Asia	Roger Brown	2023-12-08	1	1	478.020924	8.99	9	478.020924
e22d219d-cb41-495e-8a8f-618ce5e854b3	Returned	Amazon Pay	North America	Emily Matthews	2020-01-10	1	1	1436.065076	10.53	4	1436.065076
e248b84a-33b3-4ed9-9ce0-197c1b53fb71	Pending	Debit Card	Australia	Joseph Brooks	2024-05-19	1	1	1335.680004	18.57	4	1335.680004
e2531238-a65e-4783-83f5-1115c250aa81	Pending	Debit Card	Asia	Roger Brown	2020-05-15	1	1	2781.7482	26.85	10	2781.7482
e26fb8e6-b562-474f-bbe0-5ab7d54c9e6e	Pending	Credit Card	North America	Christina Thompson	2019-03-13	1	1	1031.606136	13.54	6	1031.606136
e275cfa1-4513-43e7-b07e-7431ad39052e	Cancelled	Credit Card	Australia	Charles Smith	2023-09-07	1	1	457.588176	25.26	4	457.588176
e27a5f8b-d4dd-4b6f-ae56-ef1019b880ad	Returned	Gift Card	North America	Crystal Williams	2022-07-23	1	1	284.49678600000004	28.66	1	284.49678600000004
e27eb5d7-878d-4557-80bf-7e1e33ab412e	Pending	Credit Card	Europe	Roger Brown	2023-10-18	1	1	1359.801396	8.77	3	1359.801396
e28b143e-47be-40b4-b9aa-f8c751feba14	Pending	Debit Card	Europe	Christina Thompson	2023-01-22	1	1	436.5984	28.8	4	436.5984
e28dcefb-b665-4408-94c8-7f934d679fc3	Cancelled	Credit Card	Asia	Kristen Ramos	2019-05-12	1	1	3302.470962	13.01	9	3302.470962
e291fdfb-89e8-462b-819d-173a6646452f	Pending	Debit Card	North America	Kristen Ramos	2024-11-22	1	1	182.959411	19.73	1	182.959411
e292c7cb-34d7-43ea-82ee-ca6e8a972547	Cancelled	PayPal	North America	Diane Andrews	2019-12-03	1	1	1093.450295	11.15	7	1093.450295
e2ad593d-8a0c-46fc-8be4-4b85faba0614	Returned	Gift Card	Asia	Caleb Camacho	2020-07-06	1	1	754.39532	14.39	8	754.39532
e2b85fef-428d-4858-98a4-62055b1230a2	Cancelled	Gift Card	North America	Roger Brown	2022-10-01	1	1	2205.44896	8.48	10	2205.44896
e2c5be87-2921-4cc8-8b16-0b0e9b667ecf	Cancelled	Debit Card	South America	Kristen Ramos	2022-09-29	1	1	1506.585792	10.48	8	1506.585792
e2d6ffb9-7379-45ca-ad5a-a7a1c2b1a57b	Pending	Credit Card	Europe	Sandra Luna	2020-02-18	1	1	1541.2095359999998	17.48	8	1541.2095359999998
e2dc431f-5864-4b52-95ce-2c2cef01eb91	Pending	Debit Card	Asia	Sandra Luna	2021-11-24	1	1	2409.48348	23.62	10	2409.48348
e2eed8c3-f283-48fc-813b-58e782a04cef	Cancelled	PayPal	South America	Caleb Camacho	2024-04-10	1	1	35.203248	5.52	3	35.203248
e2f16160-c9b7-495c-997d-99c20d3bfdc4	Cancelled	PayPal	South America	Sandra Luna	2020-08-29	1	1	366.625116	15.08	1	366.625116
e313e740-f9b6-4986-aae8-751393ed6850	Pending	Gift Card	Asia	Jason Nelson	2020-02-14	1	1	927.488295	17.55	3	927.488295
e324ff60-cbf2-4856-b41a-b596eb074668	Cancelled	Gift Card	Asia	Kristen Ramos	2022-08-07	1	1	1748.022888	10.49	6	1748.022888
e359edd6-e455-45e0-ae13-075f0e31ec82	Cancelled	Credit Card	Europe	Emily Matthews	2023-07-19	1	1	370.16190000000006	19	3	370.16190000000006
e3ad47be-b75c-444d-b6c7-c3d71723a51a	Cancelled	Gift Card	Asia	Charles Smith	2024-03-04	1	1	227.809407	28.49	1	227.809407
e3c96b5d-a095-4a09-a5fe-727d5d434226	Returned	Debit Card	Australia	Charles Smith	2019-05-08	1	1	859.2130999999999	9.27	4	859.2130999999999
e3d34d35-25fd-4f24-bafe-d7197e9cf0c3	Returned	Credit Card	North America	Michelle Andersen	2023-09-30	1	1	2103.464064	17.71	8	2103.464064
e3dcc96b-7f57-4e5e-b86c-58b7c4cacdad	Returned	Debit Card	North America	Jason Nelson	2022-09-12	1	1	1620.87723	12.34	5	1620.87723
e3f1d045-3b01-48b5-87da-0c347c90d23b	Pending	PayPal	South America	Diane Andrews	2021-02-05	1	1	2811.322332	21.27	9	2811.322332
e3f96937-bbc2-4a27-b60a-1b79c53abfbb	Returned	Credit Card	Asia	Diane Andrews	2020-11-06	1	1	325.30683600000003	23.83	2	325.30683600000003
e4015b69-a4b5-4d1f-b8de-aeafb1682658	Cancelled	Gift Card	Australia	Diane Andrews	2023-10-29	1	1	1101.41694	5.23	5	1101.41694
e40e4259-466a-4046-97c8-6bb24bd4cd79	Returned	PayPal	Europe	Charles Smith	2022-07-16	1	1	1378.66395	6.75	6	1378.66395
e41a61b3-7b5a-41a1-8695-8570bd6b0670	Returned	Amazon Pay	Europe	Michelle Andersen	2019-10-09	1	1	11.542824	23.86	1	11.542824
e42a43da-a101-4d8c-8bcb-7474fd5463d9	Returned	Amazon Pay	Asia	Emily Matthews	2020-02-25	1	1	1283.239176	4.39	4	1283.239176
e42f31b1-7cfa-42e1-87cb-439f09e4b14b	Returned	Amazon Pay	Australia	Kristen Ramos	2022-02-10	1	1	712.713984	24.16	8	712.713984
e45eb083-64a3-41ec-9f68-1621ba0f6b2e	Returned	Debit Card	Australia	Sandra Luna	2024-11-03	1	1	403.980046	8.49	1	403.980046
e4646d10-f2ca-45c2-a1ac-459b9fba2a43	Pending	Credit Card	Asia	Steven Coleman	2022-08-31	1	1	2582.74026	15.91	10	2582.74026
e4691913-96e6-493e-b31e-4acbf937a289	Cancelled	Amazon Pay	South America	Caleb Camacho	2022-04-23	1	1	2179.7544	1.68	10	2179.7544
e46cd11e-028b-4c9c-8089-28c035a95dda	Returned	Debit Card	South America	Steven Coleman	2019-06-02	1	1	742.2265439999999	1.36	6	742.2265439999999
e48db5de-1b9d-4061-9efd-4f946c2e1a2c	Returned	Credit Card	Australia	Michelle Garza	2021-01-25	1	1	2509.4683680000003	29.82	8	2509.4683680000003
e4a41ebc-2eda-403c-b54d-bec02a769429	Returned	Gift Card	Australia	Jason Nelson	2022-03-17	1	1	254.88288000000003	5.85	2	254.88288000000003
e4a420eb-b056-4b85-93af-1da39ca282aa	Returned	Debit Card	Asia	Kristen Ramos	2020-06-16	1	1	70.525404	10.09	4	70.525404
e4b2882b-7b28-448a-bced-611b74c3211d	Cancelled	Credit Card	North America	Roger Brown	2023-11-06	1	1	269.70632	23.04	5	269.70632
e4c06da9-c24f-4d09-a777-33ddeae2bfc1	Returned	Debit Card	North America	Kristen Ramos	2022-02-26	1	1	589.16484	1.18	4	589.16484
e4c31bc5-47e7-42fb-9950-e0666ba5e41e	Cancelled	Credit Card	Asia	Kristen Ramos	2024-07-15	1	1	242.825778	18.29	9	242.825778
e4d28199-ac5b-4e0d-80e4-029171adce03	Cancelled	Gift Card	Asia	Johnny Marshall	2021-05-08	1	1	523.6623	22.75	2	523.6623
e4e3c227-6438-470b-b03f-31d974b08613	Returned	Debit Card	South America	Crystal Williams	2024-09-15	1	1	1076.0298240000002	8.32	4	1076.0298240000002
e4fa991d-b1a8-4a8a-8093-84dbb2b03536	Pending	PayPal	North America	Johnny Marshall	2023-09-18	1	1	676.4649000000001	18.25	2	676.4649000000001
e5197616-c102-4e8d-9673-3c35a0c9f212	Pending	Gift Card	Australia	Kristen Ramos	2022-09-07	1	1	1594.85964	24.87	6	1594.85964
e524082c-23f4-498f-b05a-4324736762ae	Pending	Credit Card	Asia	Caitlyn Boyd	2021-11-04	1	1	1783.376298	16.37	9	1783.376298
e53a9993-0e39-472c-a946-d9732235b888	Returned	Amazon Pay	Europe	Jason Nelson	2022-01-25	1	1	75.743808	4.94	1	75.743808
e53d3195-ce1e-4f94-8d65-eefc341a4281	Returned	Debit Card	South America	Roger Brown	2020-01-20	1	1	1604.7061730000005	28.13	7	1604.7061730000005
e545d98a-fe9c-4e71-a870-ca74a1a1aba2	Returned	Gift Card	South America	Adam Smith	2021-04-25	1	1	150.83494900000002	4.89	1	150.83494900000002
e557f09e-5edc-492f-8350-a3ddd6adb352	Cancelled	Credit Card	Australia	Crystal Williams	2021-09-28	1	1	272.740272	23.96	6	272.740272
e5641379-6990-4185-8d35-6d03aa98b111	Cancelled	Credit Card	South America	Caleb Camacho	2019-03-29	1	1	1824.30846	22.81	5	1824.30846
e5925dc8-d66a-4c39-9327-7da3a617199a	Cancelled	PayPal	Asia	Roger Brown	2022-12-23	1	1	2263.909725	3.53	5	2263.909725
e5a6ebc1-3dbe-4f27-9532-97737d2b958a	Cancelled	Gift Card	Europe	Roger Brown	2022-01-08	1	1	2212.94025	1.45	6	2212.94025
e5a9735d-dbe6-4d52-8d95-74b48249be6e	Returned	PayPal	Europe	Sandra Luna	2024-10-02	1	1	795.9168	24.4	4	795.9168
e5c2d846-fae8-4ce3-b3b6-a382c3e08899	Returned	Gift Card	South America	Mary Scott	2019-07-04	1	1	374.957835	5.11	7	374.957835
e5e52a4f-5abc-43d4-8d3f-5b633d92cf6a	Pending	Gift Card	South America	Michelle Garza	2023-01-16	1	1	302.926632	11.16	1	302.926632
e5ed3773-ca43-4132-ae08-5bc95524ad2f	Returned	Gift Card	North America	Kristen Ramos	2022-06-16	1	1	1635.4843600000002	8.24	5	1635.4843600000002
e5f3f85d-61ef-4464-8ac4-f9d35e16c06a	Pending	Credit Card	Australia	Michelle Garza	2021-02-12	1	1	1321.99371	3.14	3	1321.99371
e5f58fb1-d8ab-4b6b-a0ef-0f9f07bdf4e9	Pending	Debit Card	Europe	Caleb Camacho	2024-08-24	1	1	81.75936	6.88	1	81.75936
e5f5bd53-a799-49ac-8a1f-6d1c4237841e	Pending	Credit Card	South America	Adam Smith	2021-09-07	1	1	1861.999872	5.44	8	1861.999872
e5f766c6-ea78-4242-802c-1b85c0f88b90	Pending	PayPal	South America	Susan Edwards	2023-10-17	1	1	1238.68251	17.93	10	1238.68251
e6051525-7304-4d40-a0ed-d9ea87b118c7	Cancelled	Credit Card	Australia	Jason Nelson	2021-10-09	1	1	1984.9099200000005	10.12	8	1984.9099200000005
e6098818-3c07-4a25-b739-e6b0f40ee9a6	Returned	Amazon Pay	South America	Kristen Ramos	2021-02-20	1	1	370.542336	4.46	8	370.542336
e613ebe7-7412-4d5b-8ab0-786ac0c36b75	Cancelled	Credit Card	Asia	Michelle Andersen	2019-04-16	1	1	53.443735	28.35	1	53.443735
e61e43b1-640a-48a7-a113-df85b6870d08	Returned	Debit Card	North America	Adam Smith	2020-10-21	1	1	348.75775	22.5	1	348.75775
e63aa5a2-a66c-4eee-8109-bd37706d675a	Returned	Debit Card	North America	Christina Thompson	2020-12-04	1	1	1071.055872	20.08	4	1071.055872
e63de9cd-97b5-4769-8995-999988416c4a	Returned	PayPal	Europe	Christina Thompson	2023-08-05	1	1	2931.378912	19.48	8	2931.378912
e643d178-5655-4bc2-a778-ce43c75c5f88	Returned	Amazon Pay	Europe	Steven Coleman	2023-05-12	1	1	3295.54955	20.33	10	3295.54955
e65ae2fd-b857-469f-a511-a857acdff482	Cancelled	PayPal	South America	Mary Scott	2021-01-05	1	1	1380.94663	17.9	7	1380.94663
e661030c-f440-4461-8142-a15935efb60a	Cancelled	Gift Card	North America	Susan Edwards	2019-09-27	1	1	275.446128	3.23	3	275.446128
e66881ae-ed4f-43ac-80c1-6f165e6210aa	Returned	Credit Card	South America	Michelle Andersen	2021-02-04	1	1	1807.7624100000005	5.38	5	1807.7624100000005
e67ce8fb-f932-4a69-a779-6d24a83cf178	Returned	Amazon Pay	Asia	Diane Andrews	2024-12-03	1	1	2182.41258	7.47	6	2182.41258
e680ea51-545d-42a3-aee0-a2e79cdd8970	Cancelled	Gift Card	North America	Crystal Williams	2024-12-10	1	1	1064.709776	11.99	8	1064.709776
e68d2576-8dae-49cf-879a-bbb9063440aa	Cancelled	Credit Card	Asia	Susan Edwards	2024-02-20	1	1	489.867446	11.49	2	489.867446
e69dbc00-c74a-4e40-b123-654fed2cea29	Pending	PayPal	North America	Kristen Ramos	2024-01-04	1	1	108.78336	19.06	4	108.78336
e6a56e70-d24f-4459-a3d5-8deff3ee9c7b	Cancelled	PayPal	Europe	Caitlyn Boyd	2022-07-03	1	1	1395.8195360000002	25.08	4	1395.8195360000002
e6a82f04-3e07-45c4-b02b-89dc0919e03a	Pending	Credit Card	Europe	Diane Andrews	2024-07-30	1	1	2234.174229	20.23	7	2234.174229
e6ab94be-b5f1-4350-ab7f-805438cf27cb	Returned	PayPal	Australia	Roger Brown	2020-08-28	1	1	328.799125	26.73	5	328.799125
e6f34c64-9a6d-4258-a077-86d4448fcbf5	Returned	Credit Card	South America	Michelle Garza	2019-03-28	1	1	226.18008	11.8	2	226.18008
e6f91c5d-a0f0-4bbe-b1dc-8517b7ff218e	Returned	PayPal	Australia	Charles Smith	2021-06-15	1	1	1742.535746	5.37	7	1742.535746
e736a0f3-23d1-456b-bb73-c3e0897c3507	Cancelled	Gift Card	Australia	Joseph Brooks	2022-02-03	1	1	568.78875	11.3	9	568.78875
e7471d7d-8a54-4c14-a70d-8a16a011e63b	Returned	PayPal	Asia	Diane Andrews	2023-11-24	1	1	539.1684	3.25	6	539.1684
e76bf026-5008-4c8a-8869-c76cde7a662c	Returned	Gift Card	Asia	Emily Matthews	2019-02-02	1	1	107.151408	24.52	3	107.151408
e76d3f87-b075-4a6c-97ea-4de5a229091a	Returned	PayPal	Europe	Michelle Garza	2021-07-25	1	1	1514.847411	0.79	7	1514.847411
e76e22a8-b95d-4824-9f4e-df20fbe6dc72	Returned	Debit Card	South America	Adam Smith	2021-02-27	1	1	156.00476600000002	25.46	1	156.00476600000002
e7792eac-4f50-4511-9b5a-24dc5e495ad9	Pending	Debit Card	North America	Sandra Luna	2019-03-23	1	1	1012.314204	23.66	6	1012.314204
e77c8f9e-9986-4f4b-bca4-e7ad486f136f	Pending	Amazon Pay	Europe	Susan Edwards	2019-10-03	1	1	1561.5608799999998	6.08	5	1561.5608799999998
e79e3bf6-2cc0-4246-874d-e0d7a35fe703	Pending	Credit Card	South America	Bradley Howe	2020-11-12	1	1	373.41696	11.68	10	373.41696
e7a4efef-373b-42f3-958a-afc0d6e04262	Pending	Credit Card	South America	Steven Coleman	2022-01-19	1	1	1632.575835	8.13	9	1632.575835
e7c8e6b0-77d2-417a-a2ac-9ea4b64dda61	Returned	PayPal	Asia	Sandra Luna	2020-10-09	1	1	85.917696	11.68	2	85.917696
e7c908e6-3d81-4150-b69a-e9c723b6b877	Cancelled	PayPal	Europe	Sandra Luna	2019-05-31	1	1	3185.6594640000003	2.23	8	3185.6594640000003
e7cadd42-2901-4ccc-9390-b175f012d9de	Returned	Amazon Pay	Europe	Joseph Brooks	2022-12-16	1	1	1676.11068	27.6	9	1676.11068
e7e74f89-d925-4bd6-a920-5cb8c863dd37	Returned	Credit Card	North America	Johnny Marshall	2020-03-08	1	1	185.689098	7.81	9	185.689098
e7fc0d90-6f2d-4e46-aeea-add09288a8f2	Returned	Gift Card	Australia	Crystal Williams	2024-06-06	1	1	1736.344128	5.83	8	1736.344128
e817ae78-5ed7-42d8-822b-21ce84662207	Cancelled	Gift Card	Europe	Christina Thompson	2023-04-25	1	1	1561.54985	4.17	5	1561.54985
e831b2b4-9960-4e8e-a85c-b9e68736b762	Cancelled	Credit Card	Australia	Sandra Luna	2024-11-27	1	1	2364.9295380000003	20.49	6	2364.9295380000003
e83472e3-d0ad-4d23-9dd3-0850b312d21c	Returned	Amazon Pay	Australia	Sandra Luna	2023-06-18	1	1	29.404264	27.86	1	29.404264
e84c6516-d86b-4a97-a68c-a81e34fc76f6	Cancelled	Debit Card	Asia	Roger Brown	2021-07-21	1	1	367.59373	4.26	1	367.59373
e888dfb4-6de5-4bac-9777-00abd6282472	Cancelled	Credit Card	South America	Kristen Ramos	2024-05-23	1	1	2367.98562	6.97	10	2367.98562
e88c8d02-c346-4242-af93-cd47f246548d	Pending	Debit Card	North America	Michelle Andersen	2021-04-02	1	1	191.69878000000003	26.6	7	191.69878000000003
e89d3da8-e5d8-47a8-803b-aba5479b646c	Cancelled	Gift Card	North America	Charles Smith	2024-10-05	1	1	1180.746959	4.61	7	1180.746959
e8a04d5e-e97f-4928-b9f9-ff070c140024	Pending	Debit Card	North America	Charles Smith	2020-07-16	1	1	193.482198	25.38	1	193.482198
e8b9b30d-100c-4fbf-9544-fd8e31d792a9	Pending	Amazon Pay	Australia	Caleb Camacho	2021-07-09	1	1	2618.106848	18.66	8	2618.106848
e8c0de10-f541-4666-8a0f-71b57e67d6c2	Cancelled	Debit Card	Europe	Caleb Camacho	2020-09-15	1	1	737.9707559999999	11.06	3	737.9707559999999
e8d499d3-d37a-4082-92b2-cf0494984505	Cancelled	Debit Card	Europe	Michelle Garza	2021-05-09	1	1	315.458781	10.91	1	315.458781
e90b7673-58df-4b6c-8972-7bcc288cb24a	Cancelled	PayPal	Europe	Johnny Marshall	2021-02-08	1	1	2301.499984	27.92	7	2301.499984
e90fc8e7-2f87-418d-b352-55c8321b3347	Returned	Amazon Pay	South America	Diane Andrews	2023-04-01	1	1	3079.266273	1.63	9	3079.266273
e929cb68-2a1d-4e0f-a576-4a4c9079ae8f	Cancelled	PayPal	South America	Crystal Williams	2022-08-05	1	1	1622.27172	29.99	10	1622.27172
e93a99d4-69fc-4dbe-b3e1-13763896006e	Cancelled	Gift Card	Europe	Sandra Luna	2024-11-02	1	1	445.952	12.9	4	445.952
e94ee7c2-46d8-4b18-bfc5-017d32b9a45e	Returned	PayPal	Europe	Kristen Ramos	2024-02-25	1	1	210.268375	15.47	1	210.268375
e95b9c2d-46eb-4f71-9c70-8fba2f827a5d	Returned	Amazon Pay	Europe	Joseph Brooks	2020-11-16	1	1	2778.8845920000003	3.46	8	2778.8845920000003
e95ed1e3-96d5-4e4a-9338-720715faf48e	Cancelled	Debit Card	Europe	Sandra Luna	2020-08-13	1	1	447.51787	17.18	5	447.51787
e95ed929-e779-49d2-a86d-1784b0e2437d	Returned	Amazon Pay	Australia	Jason Nelson	2024-03-20	1	1	299.97909000000004	18.85	6	299.97909000000004
e96e6545-113c-42d7-aeaf-2f8d72d671dc	Returned	Gift Card	Europe	Charles Smith	2023-03-17	1	1	294.082216	21.77	8	294.082216
e9707f06-11cf-48e0-b3be-7fa61afed870	Returned	Gift Card	South America	Adam Smith	2022-09-24	1	1	1585.93442	27.06	10	1585.93442
e97422a2-d252-48ba-93be-2064debe918a	Returned	Amazon Pay	Australia	Susan Edwards	2022-07-22	1	1	1400.378112	10.08	8	1400.378112
e97c91dc-5fdd-4ab8-a267-18d994e7b3aa	Pending	Amazon Pay	Australia	Steven Coleman	2019-03-17	1	1	2177.700594	4.77	6	2177.700594
e98fe9cf-f3f2-4412-a342-197c51da0e6a	Cancelled	PayPal	North America	Caitlyn Boyd	2020-11-21	1	1	268.52571	0.38	1	268.52571
e9b6d487-2af4-4be7-8c21-843585720c82	Cancelled	Amazon Pay	Europe	Joseph Brooks	2022-05-17	1	1	1041.608106	16.63	9	1041.608106
e9ce5801-6ce1-471c-8afc-782a9d9177c3	Pending	Amazon Pay	South America	Kristen Ramos	2021-12-20	1	1	18.817596	17.03	4	18.817596
e9d57e58-5c14-4d8a-9bb2-2edab458193f	Returned	Amazon Pay	Australia	Kristen Ramos	2024-12-03	1	1	575.41978	26.81	5	575.41978
e9e44515-5d56-490c-993a-29ae52e31dc4	Cancelled	PayPal	South America	Roger Brown	2024-02-20	1	1	109.187616	29.52	3	109.187616
e9f82db2-0513-4a79-b833-6c9cab4f7325	Returned	Gift Card	Australia	Susan Edwards	2022-02-02	1	1	276.541884	6.58	1	276.541884
e9fb59a7-9160-459d-a45c-67fe0463052a	Cancelled	Amazon Pay	Asia	Crystal Williams	2021-01-12	1	1	24.280235999999995	26.02	6	24.280235999999995
e9fe45fa-0ea4-4c40-b24b-b7c9c79c59cd	Cancelled	PayPal	Australia	Diane Andrews	2021-07-05	1	1	1395.37912	29.12	5	1395.37912
ea1bdafa-2a71-480d-a718-0bb336772d64	Pending	PayPal	Australia	Roger Brown	2024-05-08	1	1	536.158392	4.52	6	536.158392
ea27d4a8-b132-4857-971a-ca04a8c26373	Returned	Gift Card	South America	Sandra Luna	2022-02-14	1	1	754.9146	1.55	2	754.9146
ea3f2f3e-3538-4e4f-bc4c-cf44b3d5fedd	Pending	Amazon Pay	North America	Diane Andrews	2021-05-11	1	1	1574.851955	27.23	5	1574.851955
ea6d5a68-2c18-4313-b15a-096bbe5804a0	Pending	Credit Card	Australia	Caleb Camacho	2022-11-01	1	1	4141.063314	2.82	9	4141.063314
ea753d5f-30f1-4371-9daa-1e07864ec3e1	Returned	Gift Card	North America	Roger Brown	2020-02-29	1	1	50.672187	22.27	1	50.672187
ea7dd3f2-9aeb-45f2-b3f4-448ec46a19ea	Returned	Debit Card	North America	Kristen Ramos	2022-05-23	1	1	1210.27724	1.05	8	1210.27724
ea8b9914-7f23-4c37-821e-81cd53d9cf6b	Pending	PayPal	North America	Crystal Williams	2019-03-03	1	1	1851.40704	17.8	7	1851.40704
ea95b5a4-fd5b-425c-86c5-851285ff7712	Returned	Debit Card	South America	Christina Thompson	2022-11-05	1	1	1006.34835	9.7	5	1006.34835
eabab167-0b75-44c0-8030-17503fb8c76c	Cancelled	Debit Card	Europe	Mary Scott	2019-07-01	1	1	163.541007	20.29	7	163.541007
eac374af-1e3c-4f26-ab11-1e895b08356c	Pending	Debit Card	South America	Johnny Marshall	2023-06-21	1	1	1297.0551	18.27	6	1297.0551
eaced5b6-0bf9-4b53-aa2a-edafbf20cf6c	Returned	Debit Card	Europe	Charles Smith	2024-07-17	1	1	1239.24508	12.72	5	1239.24508
eade76ab-fadd-41e3-a982-09d2ac9c762c	Returned	Amazon Pay	South America	Mary Scott	2021-06-20	1	1	85.250718	16.47	6	85.250718
eaed2b70-0b68-4148-8cc1-f66a5aa164a5	Returned	Debit Card	Australia	Mary Scott	2024-07-05	1	1	294.248604	12.12	1	294.248604
eaef327f-7d75-424b-af00-9826d511967d	Returned	Amazon Pay	Europe	Caleb Camacho	2023-08-01	1	1	1706.1295999999998	12.2	10	1706.1295999999998
eb10d101-4cfa-406d-a31b-7032eb7ebfb3	Pending	Debit Card	Australia	Charles Smith	2022-04-29	1	1	2957.8402	28.26	10	2957.8402
eb1af299-2d83-4815-8607-d1d0fee549f1	Pending	Amazon Pay	North America	Crystal Williams	2021-03-08	1	1	483.9087899999999	25.34	5	483.9087899999999
eb1ced31-45a3-407c-9cab-817ce358d20a	Returned	Gift Card	Asia	Bradley Howe	2024-09-24	1	1	605.54325	10.25	5	605.54325
eb2321bb-0991-4baa-81d6-13be3d3d3468	Cancelled	PayPal	Europe	Adam Smith	2020-05-14	1	1	303.592476	23.11	4	303.592476
eb4c9b33-7735-4c07-b9bd-5e0ab42a908c	Returned	Gift Card	South America	Joseph Brooks	2024-11-16	1	1	2812.10735	29.15	10	2812.10735
eb6f0b4a-8a63-47ae-9aae-7b16463fcf8e	Pending	Credit Card	South America	Charles Smith	2020-05-01	1	1	2730.675	5.02	10	2730.675
eb780b15-fce1-46c2-ba81-a2d98df6a54b	Returned	Debit Card	Australia	Kristen Ramos	2023-04-12	1	1	550.18926	8.21	3	550.18926
eb7888ae-5f4a-4e01-bfe8-91cf29adfc77	Cancelled	PayPal	Europe	Michelle Andersen	2022-01-07	1	1	674.569944	26.17	6	674.569944
eb7a103b-4691-4078-a81f-8d591f6ff2a4	Returned	PayPal	South America	Caitlyn Boyd	2022-03-26	1	1	3517.61553	8.7	9	3517.61553
eb840a02-880d-4e94-879f-b4a988828954	Cancelled	Amazon Pay	Asia	Diane Andrews	2022-01-23	1	1	482.807556	20.69	9	482.807556
eba36eb7-c6d0-476d-b93a-dc19ec5c877f	Returned	Gift Card	South America	Michelle Andersen	2023-11-25	1	1	702.099008	27.72	2	702.099008
ebacdfb0-a7ab-4e2d-9988-af1d0ca9707f	Cancelled	Amazon Pay	Asia	Christina Thompson	2022-07-29	1	1	2896.6032	14.5	8	2896.6032
ebacf01b-5bc4-4534-9da9-c51650da8af5	Cancelled	PayPal	Europe	Crystal Williams	2022-08-30	1	1	287.880888	21.78	2	287.880888
ebb62cb2-c5ee-459c-b76f-77cbef73d027	Returned	Credit Card	Asia	Caitlyn Boyd	2021-03-03	1	1	180.250704	5.41	4	180.250704
ebdc9753-1b17-47cb-ae96-77b536cbed33	Cancelled	Amazon Pay	Europe	Adam Smith	2023-07-23	1	1	819.461544	0.83	3	819.461544
ebff7ae5-c5d1-4fcd-89ce-52048ca2dd11	Returned	Gift Card	Asia	Joseph Brooks	2021-11-04	1	1	2232.644224	23.64	8	2232.644224
ec1d5ebf-ab77-423a-a152-de5d5c6df6ec	Returned	PayPal	Asia	Caitlyn Boyd	2021-09-17	1	1	123.852498	24.54	1	123.852498
ec253e3f-d024-4e6c-83a8-945743ff5622	Pending	Gift Card	South America	Jason Nelson	2019-08-03	1	1	1687.4052639999998	13.26	4	1687.4052639999998
ec27abe5-7a2d-4f37-8355-f0a5fa128a75	Returned	Debit Card	Asia	Michelle Andersen	2021-05-23	1	1	676.823378	23.22	7	676.823378
ec3c89c7-f28d-4154-ab09-e29d43607b86	Returned	Amazon Pay	Europe	Adam Smith	2024-03-22	1	1	496.7991600000001	14.85	2	496.7991600000001
ec7e4f8f-2e87-4b21-9855-6cde534dccf0	Pending	Credit Card	Asia	Caitlyn Boyd	2023-12-12	1	1	1409.268861	25.51	7	1409.268861
eca7fefe-0c4d-45f3-b32d-5f36b8499c19	Returned	Gift Card	North America	Michelle Andersen	2021-05-22	1	1	3543.8785800000005	1.66	10	3543.8785800000005
ecc75bde-fb9f-47d2-be3b-0b007d4ef27a	Cancelled	Credit Card	North America	Bradley Howe	2023-08-25	1	1	395.686284	18.94	1	395.686284
ece049ee-92d6-4851-bd46-fb735a4fc8b5	Cancelled	Credit Card	Australia	Susan Edwards	2024-11-05	1	1	305.045214	29.14	1	305.045214
ecfd0ac1-696b-440d-8ee7-21f2cc5227a5	Returned	Credit Card	Asia	Jason Nelson	2023-07-13	1	1	489.847688	29.27	4	489.847688
ed067737-2e92-4a62-a72b-069201f3ae40	Cancelled	Amazon Pay	North America	Joseph Brooks	2021-11-10	1	1	872.2635250000001	25.85	5	872.2635250000001
ed0bf8f5-504d-4dca-ae12-3f8c4ef2f557	Returned	Credit Card	Europe	Bradley Howe	2024-03-06	1	1	924.95547	11.05	6	924.95547
ed0dd415-d781-45b0-be48-406e965ddc9c	Returned	Amazon Pay	Australia	Michelle Garza	2024-11-23	1	1	1421.27832	19.15	4	1421.27832
ed21b3e8-8e02-464b-9ec9-239cafccf774	Pending	Amazon Pay	Europe	Christina Thompson	2022-04-15	1	1	1860.8637900000003	17.81	5	1860.8637900000003
ed32fe9c-50ef-425e-87fc-645a8a077b49	Pending	Credit Card	Asia	Caitlyn Boyd	2020-08-23	1	1	495.502812	10.42	7	495.502812
ed49fa69-a5c2-4650-951f-5e210717b720	Cancelled	Amazon Pay	North America	Sandra Luna	2021-07-18	1	1	3008.821382	12.29	7	3008.821382
ed69521d-9940-4032-a4ad-0f160cf92c3d	Cancelled	Credit Card	Asia	Johnny Marshall	2024-07-19	1	1	424.10034	28.44	3	424.10034
ed81cb93-42b7-4de8-9cf5-87eb4a215ad6	Pending	Amazon Pay	Asia	Michelle Andersen	2023-03-04	1	1	2181.331152	9.91	8	2181.331152
ed9818e8-52df-458b-9d40-25f699c6e824	Returned	PayPal	North America	Susan Edwards	2024-12-12	1	1	277.83792	5.11	4	277.83792
eda19647-b4e6-44af-bada-6b4454e17a69	Returned	Credit Card	Europe	Johnny Marshall	2024-04-14	1	1	840.615328	26.36	4	840.615328
edae7b32-22c1-4851-9f76-ae59be45f914	Cancelled	Debit Card	South America	Kristen Ramos	2020-12-03	1	1	3139.4890800000003	8.35	7	3139.4890800000003
edaff22b-98b9-4d75-a436-a550b0b1a50e	Returned	Gift Card	Australia	Diane Andrews	2019-05-19	1	1	2398.806366	13.73	6	2398.806366
edce86aa-d466-4e2b-80aa-9741bf6d1db4	Cancelled	PayPal	Australia	Michelle Andersen	2020-11-20	1	1	270.83042	18.65	1	270.83042
edd0990c-18d3-407a-8f1d-e94706148a0c	Pending	PayPal	North America	Caleb Camacho	2019-07-13	1	1	31.152896	6.56	2	31.152896
edd65353-d77b-42b5-9c93-5080425cc191	Pending	Gift Card	Europe	Michelle Garza	2019-10-18	1	1	337.08655	25.67	1	337.08655
edef4afc-e787-477c-8c25-23e3ac14b180	Cancelled	Debit Card	Europe	Crystal Williams	2020-03-29	1	1	890.144682	26.69	7	890.144682
ee0c02fc-0f44-4624-889a-a6848403fef4	Cancelled	Credit Card	North America	Johnny Marshall	2022-03-22	1	1	1279.75218	22.99	4	1279.75218
ee14734c-d192-4c79-85f8-b3cc429ddb3e	Cancelled	Gift Card	Australia	Adam Smith	2019-06-11	1	1	887.61474	23.23	3	887.61474
ee1b7af0-9516-44d3-9747-8efa7012b2cf	Pending	PayPal	Europe	Charles Smith	2021-04-08	1	1	2128.08006	21.8	9	2128.08006
ee2e7c95-11fe-45f7-b0cd-a21840dd27a6	Cancelled	Debit Card	Australia	Charles Smith	2023-05-10	1	1	4298.98448	2.42	10	4298.98448
ee47059b-deef-452e-b1a1-be0efd9d8aa1	Cancelled	PayPal	Asia	Diane Andrews	2020-05-26	1	1	1124.588304	1.93	6	1124.588304
ee6065f8-e610-4f10-a6ee-4f136aa69748	Cancelled	Gift Card	Australia	Roger Brown	2021-12-15	1	1	2934.025092	3.01	9	2934.025092
ee636531-7931-41a1-acac-f9196b8d533d	Cancelled	PayPal	Asia	Diane Andrews	2021-11-09	1	1	730.578464	13.34	4	730.578464
ee761ae5-ddfc-42e6-95ed-2b5224933dfb	Returned	Gift Card	Asia	Steven Coleman	2021-10-11	1	1	550.8851040000001	16.84	2	550.8851040000001
ee7c0661-d512-45af-905f-92861a97b27c	Cancelled	Amazon Pay	Asia	Jason Nelson	2021-09-26	1	1	769.762782	24.97	6	769.762782
ee7f9b24-5196-45fd-941a-c17e59f474a4	Returned	Credit Card	South America	Roger Brown	2019-03-24	1	1	2829.11778	1.18	9	2829.11778
ee8ebfa0-9200-4440-9334-071e1ff27a7a	Pending	Gift Card	Asia	Caleb Camacho	2019-03-24	1	1	749.73123	10.99	2	749.73123
ee98c295-dad0-4ebc-9c5a-1413d745d5c2	Pending	PayPal	Asia	Caleb Camacho	2022-03-19	1	1	1655.8031099999998	0.03	5	1655.8031099999998
ee9d4dd7-f5b5-4cbc-a656-6a931860245a	Cancelled	Gift Card	North America	Steven Coleman	2019-11-10	1	1	772.041024	21.76	2	772.041024
f2d39f57-7f9f-411a-b757-82f03f2524f9	Cancelled	Amazon Pay	Asia	Joseph Brooks	2021-06-23	1	1	1850.411432	9.29	8	1850.411432
eeb159e4-b819-41ff-81f6-135b358d7aca	Cancelled	Debit Card	Australia	Johnny Marshall	2023-02-13	1	1	153.37664	26.6	2	153.37664
eec906c2-8650-4dd4-8dd6-3ac356b9093b	Cancelled	Gift Card	Europe	Roger Brown	2020-06-15	1	1	507.32273	20.37	10	507.32273
eecbda05-48a0-40e6-a378-2d474a7cd89d	Pending	Credit Card	Europe	Steven Coleman	2019-11-28	1	1	2094.42186	5.7	9	2094.42186
eed1c365-a34f-4219-ba6a-f63d438823d4	Returned	PayPal	Australia	Michelle Andersen	2023-04-27	1	1	967.615632	20.29	8	967.615632
eed73f28-7c36-4ce5-8fe0-4f8cdc5a0737	Cancelled	PayPal	Europe	Bradley Howe	2022-06-18	1	1	1012.9638	22.75	4	1012.9638
ef2f0754-fd42-408e-a005-4a2473bcd5ad	Cancelled	Gift Card	South America	Jason Nelson	2022-01-03	1	1	1245.23498	21.24	5	1245.23498
ef310fb3-cd32-46ae-adb5-f5959163ad1e	Cancelled	Credit Card	Australia	Sandra Luna	2019-07-26	1	1	278.788692	3.66	2	278.788692
ef31a196-2b1f-4760-b160-b3d33f430867	Cancelled	Credit Card	South America	Michelle Andersen	2020-03-03	1	1	2251.5788	14.7	8	2251.5788
ef7bd592-d7e6-4bcc-b810-434c348c000b	Cancelled	Amazon Pay	South America	Charles Smith	2019-06-09	1	1	1102.470336	18.01	4	1102.470336
efa34d30-3684-45bd-9f1f-0346e1170b00	Cancelled	PayPal	South America	Kristen Ramos	2021-01-12	1	1	1120.0270140000002	8.38	9	1120.0270140000002
efaa6321-e953-472c-8994-12867eda309b	Pending	Credit Card	Asia	Crystal Williams	2022-04-03	1	1	521.34033	17.85	7	521.34033
efd6d52c-37d2-4fc5-af08-2bc910dbea0b	Cancelled	Gift Card	Europe	Joseph Brooks	2021-10-04	1	1	497.5865749999999	25.55	5	497.5865749999999
eff6bc13-4117-47d4-a074-9d12e839bff1	Cancelled	Credit Card	Australia	Caitlyn Boyd	2020-01-19	1	1	1843.01892	23.8	9	1843.01892
f00d98d9-0c6f-4ef7-8fd4-31c2e3b6660e	Cancelled	Gift Card	Australia	Susan Edwards	2019-01-18	1	1	1325.633361	9.39	3	1325.633361
f017f479-065b-47e5-9a22-b575953ad784	Pending	PayPal	Asia	Caitlyn Boyd	2022-04-17	1	1	1432.65411	22.06	5	1432.65411
f01c2cc2-59bd-4661-af90-da49bab5601e	Returned	Amazon Pay	South America	Susan Edwards	2023-06-26	1	1	234.677593	23.19	1	234.677593
f04234a3-305d-4635-b894-0f735bc21ec9	Returned	Debit Card	Europe	Johnny Marshall	2023-07-17	1	1	2096.475885	3.05	9	2096.475885
f066019e-0329-4b62-a52a-a572204d96c2	Pending	PayPal	Europe	Michelle Andersen	2020-09-04	1	1	2492.9069400000003	11.42	9	2492.9069400000003
f0707d10-39a4-4ca3-a043-e45babed8362	Returned	PayPal	Australia	Jason Nelson	2021-10-11	1	1	811.401416	0.86	4	811.401416
f07b4cc9-e15f-4bab-bbce-89319ce6092b	Pending	Amazon Pay	Europe	Joseph Brooks	2022-12-01	1	1	799.153326	10.27	2	799.153326
f085eeef-8b8b-42fe-91b8-1c8c2d8f7c79	Returned	Debit Card	Europe	Bradley Howe	2024-11-22	1	1	1666.639135	16.77	5	1666.639135
f08bffbc-7c72-4c04-84bb-8ed9f3f528aa	Returned	Amazon Pay	South America	Christina Thompson	2024-12-13	1	1	462.605136	13.48	4	462.605136
f0984908-eac1-4bdf-96a0-cadcb295132b	Cancelled	PayPal	Europe	Joseph Brooks	2020-12-23	1	1	331.051856	20.24	1	331.051856
f0a0b687-147b-49e4-ac0e-3fcb866efda6	Returned	PayPal	South America	Susan Edwards	2024-01-17	1	1	2394.9244	20.54	10	2394.9244
f122e160-92fc-41d4-96cb-a84bfc5700b4	Returned	Gift Card	Australia	Caitlyn Boyd	2020-11-24	1	1	1376.7376	7.04	10	1376.7376
f13cf9d0-4722-455e-b35c-8227d3983ff2	Pending	PayPal	North America	Diane Andrews	2024-01-02	1	1	187.95402	3.85	4	187.95402
f14e2955-fad4-48c3-bc57-8e1174c50ea8	Returned	Amazon Pay	Europe	Diane Andrews	2019-10-03	1	1	1569.80673	3.34	9	1569.80673
f15ef515-af30-4ebc-b847-f80a18f70f80	Cancelled	Credit Card	Europe	Bradley Howe	2019-06-25	1	1	1103.669036	21.63	4	1103.669036
f16105f4-6fd4-4a84-b320-c68d59416573	Pending	Gift Card	North America	Jason Nelson	2020-02-20	1	1	2818.6459199999995	15.67	10	2818.6459199999995
f16f1e23-aba3-48d5-adab-2c54484d8395	Pending	Gift Card	Asia	Jason Nelson	2022-04-15	1	1	244.38745800000004	15.58	1	244.38745800000004
f174a1d4-77bb-4601-8d70-c42973205377	Cancelled	Debit Card	South America	Christina Thompson	2019-11-03	1	1	1591.9550639999998	3.01	8	1591.9550639999998
f17d85ae-5ded-4cdc-a25c-176c73d0b71d	Cancelled	Amazon Pay	Asia	Steven Coleman	2024-01-09	1	1	3275.695368	10.67	8	3275.695368
f1a86148-b467-4808-ac6b-ad39c030b741	Returned	Gift Card	North America	Christina Thompson	2020-06-01	1	1	215.7894	3.88	1	215.7894
f1ec5033-c7ea-4975-8aa9-5f41cf9c0ced	Cancelled	Debit Card	Europe	Michelle Garza	2023-12-03	1	1	2064.15744	19.77	6	2064.15744
f1f1668b-856d-42cd-ac66-9923362a05cb	Pending	Debit Card	Europe	Jason Nelson	2024-07-21	1	1	371.88974	24.81	10	371.88974
f1f56589-e93f-407e-a87d-b9ee04040194	Pending	Amazon Pay	Australia	Bradley Howe	2022-07-19	1	1	1910.879991	20.53	9	1910.879991
f21d91c5-059d-4991-b0ab-2b4cb24c1702	Returned	Debit Card	North America	Jason Nelson	2022-07-06	1	1	2591.859424	1.88	8	2591.859424
f22bf617-0266-4a8a-ba2b-6e4240991543	Returned	Credit Card	Asia	Michelle Garza	2024-08-24	1	1	394.057796	11.67	2	394.057796
f2302779-5aa1-43cd-91a4-062185c61aa6	Cancelled	Gift Card	South America	Joseph Brooks	2024-09-04	1	1	37.854648	28.63	2	37.854648
f2329cde-d6bd-4356-93a0-b7bf03d2dc53	Cancelled	Amazon Pay	Australia	Caleb Camacho	2020-05-08	1	1	1140.075992	18.71	8	1140.075992
f28005f9-acd1-4155-a563-7f004b334f53	Cancelled	PayPal	Australia	Michelle Andersen	2019-04-03	1	1	2394.951728	22.26	8	2394.951728
f2811211-fd78-4635-8111-09ca44fcb48a	Returned	Amazon Pay	North America	Caleb Camacho	2023-03-05	1	1	1234.549647	10.21	3	1234.549647
f28c3eb8-4e2b-4d83-9113-18fe121bcc21	Pending	Amazon Pay	Asia	Johnny Marshall	2022-06-08	1	1	50.257298	22.13	1	50.257298
f29cb21d-3bd7-4786-84f2-2a8d311c2c70	Returned	PayPal	Europe	Caleb Camacho	2023-02-12	1	1	3413.80035	13.5	9	3413.80035
f29f490f-a908-406d-a9d3-1c6422d4bff1	Cancelled	PayPal	Europe	Bradley Howe	2024-03-06	1	1	83.36435999999999	5.16	10	83.36435999999999
f2b542fc-4b91-4101-bea6-8e3ef1bc6871	Returned	PayPal	North America	Kristen Ramos	2023-03-19	1	1	1160.667864	3.49	3	1160.667864
f2b793cb-36e9-4b9b-82cf-45de85b55a73	Cancelled	Gift Card	Europe	Jason Nelson	2024-06-28	1	1	1049.0485440000002	21.89	6	1049.0485440000002
f2d3f000-8235-4c05-9f3c-2f2a9822471c	Cancelled	Debit Card	Europe	Caleb Camacho	2023-05-10	1	1	467.874738	8.62	9	467.874738
f2d4a7ea-2136-4b69-9753-87d730861a8e	Pending	Debit Card	North America	Kristen Ramos	2023-09-02	1	1	1145.583642	4.73	6	1145.583642
f2d8cd54-f0d7-4b4f-b276-6fab73b181ed	Returned	Gift Card	North America	Sandra Luna	2024-09-01	1	1	604.8935200000001	10.73	2	604.8935200000001
f3064ff9-ad53-471a-9389-fef98c07f21d	Pending	Amazon Pay	Asia	Susan Edwards	2019-07-15	1	1	1550.87336	19.28	10	1550.87336
f30e9a50-4e61-4fa9-8315-b50ed967e7d9	Cancelled	Gift Card	Europe	Mary Scott	2022-12-21	1	1	965.003058	3.22	3	965.003058
f32c6a56-e3ee-4356-9e47-013960645554	Cancelled	Gift Card	South America	Kristen Ramos	2024-07-01	1	1	1297.518608	21.29	8	1297.518608
f345467a-1fcf-41bd-b0d5-ca8c44f8ddc8	Cancelled	Amazon Pay	South America	Kristen Ramos	2020-02-16	1	1	2135.667996	5.73	9	2135.667996
f35321d9-fd91-4f58-97f3-06b865ca2653	Pending	Amazon Pay	North America	Steven Coleman	2020-12-05	1	1	1521.783552	23.74	4	1521.783552
f36e57f6-fc2e-4b33-bafa-ad2e2c7ddb81	Returned	Debit Card	Australia	Diane Andrews	2020-08-12	1	1	356.575318	29.13	2	356.575318
f37233ff-fcef-46fc-9b14-b9762e919387	Pending	Debit Card	South America	Caitlyn Boyd	2020-10-10	1	1	1619.912592	23.72	9	1619.912592
f383b327-79e9-4f70-be82-ce72f7e0134f	Pending	Amazon Pay	South America	Christina Thompson	2023-03-01	1	1	1148.31651	9.05	6	1148.31651
f3969e60-5679-4969-8717-45698d6032e5	Pending	Credit Card	South America	Sandra Luna	2020-02-25	1	1	173.38233599999998	13.92	9	173.38233599999998
f3a87555-6913-4c54-bb8a-461e10110e79	Cancelled	Amazon Pay	Australia	Jason Nelson	2020-01-01	1	1	546.074694	10.81	2	546.074694
f3ad7ab8-3231-497a-8d46-3a529d7a863f	Returned	Debit Card	North America	Christina Thompson	2022-08-06	1	1	14.168663000000002	24.11	1	14.168663000000002
f3b9e3ee-141e-4fe1-8c3e-d8b90dabeef0	Pending	Credit Card	South America	Crystal Williams	2023-02-21	1	1	1354.90765	27.38	5	1354.90765
f3d469b5-ed21-4234-9002-02e406131df5	Returned	Amazon Pay	Asia	Caleb Camacho	2023-04-20	1	1	42.127365	11.59	5	42.127365
f3d77694-3a52-42a3-9182-45ba33fcc6e0	Pending	Gift Card	Europe	Emily Matthews	2019-08-10	1	1	2113.8944	19.44	10	2113.8944
f3f90028-13f1-4fec-a9c0-fbeadaf10aff	Returned	Gift Card	Asia	Crystal Williams	2020-07-02	1	1	2496.96783	14.05	7	2496.96783
f3f9fd7b-43ff-48a7-a4ac-bd037c17e9dc	Returned	PayPal	South America	Diane Andrews	2024-08-10	1	1	2564.16307	16.85	7	2564.16307
f3ffae37-1e1a-41f4-a657-bb9843bbd957	Pending	Amazon Pay	Asia	Jason Nelson	2019-03-24	1	1	381.734424	19.54	2	381.734424
f4134f67-295b-47c9-8230-5e5562b33027	Cancelled	PayPal	North America	Bradley Howe	2023-01-02	1	1	4477.4685	1.54	10	4477.4685
f41559d2-5b0e-4767-83dd-954f9bc002f1	Cancelled	Debit Card	Asia	Johnny Marshall	2021-11-12	1	1	770.640408	9.04	3	770.640408
f427e007-7533-47c7-9a80-4c51204bfdb7	Returned	Credit Card	Asia	Michelle Garza	2019-01-23	1	1	1051.06518	11.56	3	1051.06518
f42c0ed8-9559-4671-a627-a8d8b86f5012	Pending	Gift Card	North America	Susan Edwards	2021-03-11	1	1	2722.144848	8.13	6	2722.144848
f4304058-4da0-48a7-8008-1fa54bba3b63	Pending	Amazon Pay	Europe	Adam Smith	2023-05-21	1	1	1958.0451000000005	21.9	6	1958.0451000000005
f44dacc5-7745-4ef2-a009-2cbe24daf5d1	Returned	Credit Card	Asia	Charles Smith	2022-04-12	1	1	150.493564	3.02	1	150.493564
f46c8111-05c9-499f-ad0c-8497fd13c4ae	Cancelled	Amazon Pay	Asia	Steven Coleman	2024-06-30	1	1	687.4078200000001	25.07	10	687.4078200000001
f4864e31-345b-40b8-a3ea-8f07fb1ffbe8	Cancelled	PayPal	Australia	Emily Matthews	2021-05-08	1	1	1988.495691	17.51	7	1988.495691
f49477f8-e773-4f8d-9c4e-d45793b834b9	Cancelled	Amazon Pay	North America	Steven Coleman	2024-04-20	1	1	343.507878	19.54	7	343.507878
f4b17fed-8fee-437a-b94d-a0fdb20f8b8a	Pending	Credit Card	South America	Sandra Luna	2020-02-28	1	1	1128.727796	16.91	4	1128.727796
f4b31d7c-7e9d-446f-ad66-dffdc8deead2	Cancelled	PayPal	North America	Caitlyn Boyd	2019-08-09	1	1	331.95315	2.75	6	331.95315
f4c081c1-927d-467e-811e-90199711d57f	Pending	Amazon Pay	Asia	Bradley Howe	2019-10-08	1	1	1164.9814	13.1	5	1164.9814
f4c66379-bde2-4f26-a803-8b1bbfaaf12e	Returned	Amazon Pay	Europe	Steven Coleman	2023-08-30	1	1	274.373368	8.84	1	274.373368
f4df519f-c69d-416b-b61f-316f7ec17084	Returned	Debit Card	South America	Caitlyn Boyd	2022-03-24	1	1	2048.924745	15.51	9	2048.924745
f4fdc5eb-16d0-4d0a-a9c2-b3f145cdbeae	Cancelled	Amazon Pay	Australia	Crystal Williams	2023-08-20	1	1	604.6431300000002	17.97	9	604.6431300000002
f4fedd60-632c-408d-be4f-dc07d3389fb8	Pending	Amazon Pay	North America	Kristen Ramos	2022-02-22	1	1	330.475416	9.23	6	330.475416
f53cbf31-3885-4336-b35c-9fa4b8b12154	Returned	Amazon Pay	South America	Christina Thompson	2023-10-06	1	1	1147.988328	18.96	3	1147.988328
f53f9b4a-c8c2-45e2-995d-ed8f6ea456f1	Returned	PayPal	South America	Johnny Marshall	2023-09-08	1	1	1455.460737	2.73	3	1455.460737
f549b9d1-fc20-4e50-a9e8-dbf3d9d1693f	Pending	Credit Card	Australia	Steven Coleman	2020-11-06	1	1	111.539872	24.39	2	111.539872
f555e487-9798-427b-ac59-d0e6d4f61e8e	Returned	PayPal	Australia	Michelle Garza	2020-07-08	1	1	3278.1772100000003	1.7	7	3278.1772100000003
f55a04a6-dcb8-4ae8-8091-c6e7540e11bc	Returned	Debit Card	Australia	Diane Andrews	2020-04-21	1	1	301.35301	5.22	1	301.35301
f55a2147-7fc2-43e2-a578-59c585c415dd	Pending	Amazon Pay	South America	Sandra Luna	2021-09-11	1	1	1302.581376	15.88	6	1302.581376
f5685859-ea13-4a0a-a749-1855fc094d08	Cancelled	Gift Card	North America	Adam Smith	2022-09-14	1	1	417.332482	15.53	1	417.332482
f582cfe6-74d2-401d-9348-714bffd0647c	Cancelled	Debit Card	Europe	Joseph Brooks	2020-01-06	1	1	528.69552	20.04	6	528.69552
f585a3a2-765a-44a9-9427-7aed0f32357f	Pending	Amazon Pay	South America	Emily Matthews	2021-11-05	1	1	689.8425	10.7	5	689.8425
f587b0db-95cd-4f7c-93de-f2ccecd760e3	Returned	PayPal	Asia	Johnny Marshall	2019-12-02	1	1	1465.648128	28.32	9	1465.648128
f5914f63-2f50-4233-bd19-c3d14ec0bbd3	Returned	Credit Card	North America	Crystal Williams	2023-02-14	1	1	1135.3325760000002	27.49	7	1135.3325760000002
f59258cf-4782-4bd0-885a-f1c2adac6580	Pending	Credit Card	North America	Christina Thompson	2021-05-31	1	1	500.58432	5.6	9	500.58432
f59a9f88-05f1-4cec-b1d8-db2881f39abe	Returned	Gift Card	Australia	Michelle Garza	2020-02-19	1	1	955.172988	2.17	2	955.172988
f5a18539-367f-4f85-8ae5-c0a6ad7ba12c	Pending	Gift Card	Asia	Jason Nelson	2022-04-09	1	1	2358.569017	3.63	7	2358.569017
f5a1c9ff-3fbd-429f-9421-b4b51e391b97	Cancelled	Debit Card	South America	Susan Edwards	2019-10-06	1	1	843.70716	1.39	8	843.70716
f5b271a6-bfa5-4919-bb8e-490d5d9b57af	Returned	Gift Card	North America	Diane Andrews	2019-02-15	1	1	285.079672	9.99	4	285.079672
f5b2a369-1e3d-481d-b2c1-6ba9dceb80aa	Cancelled	Credit Card	South America	Crystal Williams	2023-10-20	1	1	187.256752	9.66	2	187.256752
f5d48a7a-059c-437a-9b28-b8e1c4b2f7aa	Cancelled	Amazon Pay	South America	Johnny Marshall	2019-10-25	1	1	135.14022	19.3	1	135.14022
f5e7f92f-313d-4bde-aafe-809087297980	Pending	Amazon Pay	North America	Michelle Garza	2024-12-29	1	1	669.073512	12.94	4	669.073512
f5eecab4-e409-4556-b436-e3a2142172d8	Pending	Credit Card	Asia	Charles Smith	2023-01-28	1	1	3108.85575	8.09	10	3108.85575
f5f178a2-ddfd-4400-8cd6-54286aebb48b	Pending	Amazon Pay	Europe	Caleb Camacho	2023-07-01	1	1	1652.7357000000002	11.8	5	1652.7357000000002
f5fdcdaa-05e9-451f-9af3-70980db56f2a	Returned	Credit Card	North America	Kristen Ramos	2019-11-28	1	1	623.438592	25.24	8	623.438592
f629cfc3-7594-4f8d-a6cc-c91e9cb045a9	Returned	Amazon Pay	Australia	Caitlyn Boyd	2021-07-21	1	1	766.053952	14.48	2	766.053952
f643230d-c521-4a96-85a2-add4fcd491c1	Pending	PayPal	Europe	Jason Nelson	2019-09-05	1	1	2322.641295	6.05	9	2322.641295
f6511263-703b-49fe-a63f-6680cf8a1d06	Pending	Credit Card	Asia	Caleb Camacho	2019-04-03	1	1	4598.549	1.53	10	4598.549
f687428a-a74b-4a3c-9c32-2d1f0031cb0b	Returned	PayPal	Australia	Johnny Marshall	2020-01-04	1	1	689.9312500000001	6.45	5	689.9312500000001
f6887063-b9c1-4873-bd46-82e7b030a2f7	Pending	Amazon Pay	Australia	Kristen Ramos	2021-03-28	1	1	1559.1792	2.6	5	1559.1792
f69bc4e9-62a4-49bb-b5b2-f2ea609701a5	Pending	Debit Card	South America	Caleb Camacho	2022-02-16	1	1	1303.5204	3.4	3	1303.5204
f6bc298e-749c-4dfa-8f64-ec9e02aeb021	Cancelled	Amazon Pay	Asia	Steven Coleman	2019-01-05	1	1	1973.97661	10.53	10	1973.97661
f6c9c8e9-fcab-4b61-850a-385d74abee16	Returned	PayPal	South America	Bradley Howe	2021-06-13	1	1	506.1422	19.8	10	506.1422
f6d7aaab-4bfa-458d-a449-024a741137a3	Pending	PayPal	South America	Kristen Ramos	2019-09-19	1	1	408.784305	2.95	1	408.784305
f6d9f00c-869b-44e5-a30a-d89c333c2170	Returned	Credit Card	South America	Kristen Ramos	2022-12-16	1	1	114.360339	2.73	1	114.360339
f6dfe60a-8bb8-476c-a1c9-c4d9cf3aebd2	Returned	Debit Card	Asia	Kristen Ramos	2024-07-03	1	1	837.90819	15.86	5	837.90819
f6e075d2-1ed9-4737-9d95-1a7699c1b60f	Pending	Debit Card	South America	Steven Coleman	2021-11-16	1	1	108.646656	29.56	2	108.646656
f6fa5dd3-b314-403e-bd5c-efc00829146d	Returned	Debit Card	Asia	Michelle Andersen	2020-05-03	1	1	2761.37589	10.69	10	2761.37589
f7036fe5-b7c2-4292-a618-c69434534d00	Pending	PayPal	Asia	Michelle Andersen	2021-05-17	1	1	3752.21915	17.27	10	3752.21915
f7087033-7ced-439c-abff-fe208af515ee	Cancelled	Debit Card	Europe	Christina Thompson	2022-08-23	1	1	4179.749	13.4	10	4179.749
f72fa5eb-6184-4adb-ad5b-c13b461aeba9	Pending	Amazon Pay	Australia	Michelle Andersen	2022-01-01	1	1	480.664304	28.82	8	480.664304
f734f45b-eb18-4de4-93e1-f1476fe2a052	Pending	Debit Card	Australia	Charles Smith	2020-06-14	1	1	3032.30292	22.38	10	3032.30292
f7439f9f-15f9-4646-af0b-db123fb5dd1e	Returned	PayPal	Australia	Crystal Williams	2022-04-05	1	1	202.481664	10.12	2	202.481664
f760993b-5a97-420b-ad7a-83afb176f93d	Pending	Gift Card	South America	Adam Smith	2023-01-13	1	1	410.39922	26.15	6	410.39922
f76dac86-9ac1-481b-b6ab-cb6e52e20f79	Returned	Amazon Pay	Asia	Susan Edwards	2022-10-21	1	1	374.900922	5.17	2	374.900922
f7796b66-512e-43d8-b00a-ee5155b2ce1a	Returned	Amazon Pay	North America	Emily Matthews	2024-07-12	1	1	918.7887589999998	4.59	7	918.7887589999998
f77be726-0526-46fe-b42c-85ebe58c4af8	Cancelled	PayPal	Asia	Caleb Camacho	2024-11-19	1	1	2987.894864	24.77	8	2987.894864
f7832615-5960-4c7c-863a-268448f7abd4	Returned	Credit Card	Australia	Christina Thompson	2019-01-29	1	1	17.610736	10.56	1	17.610736
f79579bb-2ca1-4368-9891-580016b7b7e5	Cancelled	Amazon Pay	Asia	Susan Edwards	2023-02-18	1	1	936.39392	14.6	7	936.39392
f796711c-562b-4a24-90bb-c2b8921993ad	Returned	PayPal	South America	Roger Brown	2019-06-22	1	1	2759.120028	25.34	9	2759.120028
f7a27480-e35a-4a59-bf5b-f809dd39c7ba	Cancelled	Credit Card	Asia	Christina Thompson	2023-02-22	1	1	1701.9624299999998	28.51	5	1701.9624299999998
f7bc8f79-e95d-4302-86a5-a37f372ed9d9	Cancelled	PayPal	South America	Susan Edwards	2022-01-07	1	1	3639.26025	26.65	10	3639.26025
f7c5b798-e3f6-442a-8db0-cb692ae221a1	Cancelled	Amazon Pay	North America	Crystal Williams	2019-10-24	1	1	2388.11888	7.88	8	2388.11888
f7e84ea5-0693-4401-ad27-f1f33790b6c4	Returned	PayPal	South America	Johnny Marshall	2024-08-22	1	1	1601.15273	15.66	5	1601.15273
f7eea10e-7b86-4ab3-9e1f-b7f722548f0c	Returned	Credit Card	Europe	Caleb Camacho	2020-03-16	1	1	1301.59323	1.1	7	1301.59323
f7fc8e7e-3292-4a07-b80e-69446470789b	Cancelled	Credit Card	Australia	Caitlyn Boyd	2024-08-29	1	1	1321.48254	9.4	7	1321.48254
f8215c33-b7ed-410e-9beb-7eb74537ff45	Returned	Gift Card	South America	Caitlyn Boyd	2024-08-26	1	1	4.612724999999999	21.15	1	4.612724999999999
f8345790-9238-42d5-9cef-1bdf748f6bd8	Returned	Credit Card	Europe	Bradley Howe	2024-09-02	1	1	2076.034224	7.63	8	2076.034224
f839e9a8-54b7-4578-990d-db541f761f2c	Pending	Amazon Pay	Asia	Emily Matthews	2021-04-13	1	1	2118.9235200000003	18.4	7	2118.9235200000003
f83eb825-3774-4f7a-96c7-cc387e081a1d	Returned	PayPal	North America	Caitlyn Boyd	2019-05-16	1	1	1612.573312	8.96	8	1612.573312
f84d0ca4-472f-46cd-8939-2b9beaf170e8	Returned	PayPal	Europe	Mary Scott	2023-12-06	1	1	525.8027599999999	12.86	2	525.8027599999999
f85014b3-34e1-45d1-9e08-62140ef022d5	Cancelled	Gift Card	Europe	Joseph Brooks	2023-01-02	1	1	454.74912000000006	18.24	6	454.74912000000006
f86dc72a-fc5a-4cee-8463-00f1a5c52976	Pending	PayPal	North America	Christina Thompson	2023-08-12	1	1	332.46876	26.51	2	332.46876
f87247c5-b5e8-4be2-b2f5-5ded019eb80b	Pending	Amazon Pay	South America	Sandra Luna	2021-06-15	1	1	780.28248	26.61	6	780.28248
f87eb032-ea36-461b-9735-63d22d06b090	Cancelled	Amazon Pay	Australia	Michelle Garza	2022-01-28	1	1	1254.475152	9.56	4	1254.475152
f884381a-dc38-4adf-bd7c-2fd38e90449d	Cancelled	Gift Card	Australia	Bradley Howe	2022-12-02	1	1	683.1441000000001	13.4	5	683.1441000000001
f8878cdb-87a8-4a45-b766-abd73d7eba47	Cancelled	Debit Card	Europe	Adam Smith	2024-10-19	1	1	840.954855	25.51	5	840.954855
f89315fe-afba-416d-b918-9c1e8c185f02	Returned	Amazon Pay	Asia	Susan Edwards	2019-11-28	1	1	1150.786728	13.42	7	1150.786728
f8e36ffd-be58-4ab3-8a85-294fa8a2efa9	Pending	PayPal	North America	Steven Coleman	2019-05-06	1	1	1896.379716	26.63	7	1896.379716
f8f7421e-baf4-4b70-92c1-439a56319a3b	Cancelled	Credit Card	Asia	Steven Coleman	2020-05-03	1	1	983.25	25	10	983.25
f8f8c555-3219-4268-967d-042259aed212	Pending	Gift Card	South America	Caleb Camacho	2021-10-21	1	1	2731.35252	29.15	8	2731.35252
f8fd3209-b0cc-43f6-84c8-192e51979af0	Returned	Debit Card	Australia	Adam Smith	2024-02-15	1	1	1650.8406	21.85	10	1650.8406
f94f3faf-be2a-4226-add4-807ae04d2f4e	Returned	Debit Card	Asia	Johnny Marshall	2023-07-28	1	1	413.69072	23.6	2	413.69072
f95db57f-89e9-45ca-a0f4-98d3cca614d6	Cancelled	Debit Card	Asia	Charles Smith	2019-05-26	1	1	1273.78224	14.56	3	1273.78224
f97306bd-f6fb-4598-a177-559848516ab2	Returned	Debit Card	Australia	Bradley Howe	2019-07-03	1	1	345.32146199999994	12.89	6	345.32146199999994
f9866c69-7513-4f73-bdad-df165c17385f	Returned	Amazon Pay	South America	Jason Nelson	2023-01-22	1	1	723.38994	15.88	5	723.38994
f9938f34-14fd-4788-b04c-70b3d9769e21	Pending	Amazon Pay	North America	Jason Nelson	2020-06-29	1	1	239.6436	15.02	1	239.6436
f9bd5f48-6474-40b4-b862-63a0a9039389	Pending	Gift Card	Europe	Sandra Luna	2021-08-02	1	1	3138.39344	1.8	8	3138.39344
f9c5b642-5f0b-4350-a4d4-49843bcac13d	Pending	Debit Card	South America	Michelle Garza	2021-12-24	1	1	448.1653500000001	26.47	10	448.1653500000001
f9cc90cd-be4c-4941-962a-e5de87046c59	Returned	Credit Card	Europe	Crystal Williams	2024-10-25	1	1	1352.74	9.44	5	1352.74
f9e09ec5-e6dd-46ee-bb95-8c61693dc634	Cancelled	Credit Card	Asia	Kristen Ramos	2022-09-13	1	1	105.503125	7.25	7	105.503125
f9f73267-624d-4cf0-b69f-fee3c1f53314	Pending	Credit Card	South America	Michelle Garza	2020-04-24	1	1	663.50221	28.85	2	663.50221
fa0fe1af-ed2f-423c-a198-d1d6a23cae9d	Pending	Amazon Pay	Europe	Bradley Howe	2019-04-15	1	1	667.9706880000001	1.44	3	667.9706880000001
fa122d74-29dd-427d-999b-14912a2da601	Pending	Credit Card	South America	Crystal Williams	2021-12-25	1	1	402.506702	4.82	1	402.506702
fa24fb18-ad7c-4977-8600-0886d540f642	Cancelled	Credit Card	South America	Caitlyn Boyd	2023-04-21	1	1	232.106748	14.92	1	232.106748
fa264e04-1f45-4710-8096-38945d886efb	Pending	PayPal	Australia	Emily Matthews	2020-12-13	1	1	288.776664	1.99	4	288.776664
fa367e92-bb59-4cdd-b1cf-c3b495109e74	Pending	PayPal	Australia	Diane Andrews	2021-06-16	1	1	472.74726	1.94	2	472.74726
fa5c60d3-e84b-4ec8-a008-97927986d295	Cancelled	Debit Card	South America	Michelle Andersen	2022-06-10	1	1	779.8111859999999	27.97	7	779.8111859999999
fa6bfcea-10db-4fdd-b5bd-cc5723cf5994	Returned	PayPal	South America	Roger Brown	2024-10-15	1	1	1731.954	23.28	7	1731.954
fa6e5692-0a82-44f3-882c-72c08fc26c9e	Pending	Debit Card	Europe	Joseph Brooks	2021-04-24	1	1	526.9477919999999	19.84	7	526.9477919999999
faa0f7f5-a71a-4591-992a-257bd621037f	Pending	Gift Card	Europe	Bradley Howe	2022-04-05	1	1	1560.292839	9.49	7	1560.292839
faa8ba23-932c-4309-8b43-eb5d72b4aca5	Returned	Gift Card	Australia	Michelle Andersen	2021-01-21	1	1	782.848665	25.15	3	782.848665
fabaa726-2840-4e33-b11a-06711cb2171f	Cancelled	Debit Card	North America	Sandra Luna	2019-05-21	1	1	1530.3054080000002	4.68	8	1530.3054080000002
fac889f5-cb8c-4563-80bd-727a427edd5a	Pending	Amazon Pay	South America	Crystal Williams	2021-09-22	1	1	320.344908	28.76	1	320.344908
fad3282e-36cc-4b2f-987a-a85d0bd4dca5	Returned	PayPal	Australia	Roger Brown	2020-10-07	1	1	337.049664	23.62	4	337.049664
fae07da7-883c-4e02-b746-bfc7b0e8e45c	Returned	Amazon Pay	Europe	Caleb Camacho	2019-10-25	1	1	511.80336	7.08	8	511.80336
fae3d62c-0c06-46b8-a67a-b98d0c173df1	Pending	Gift Card	Europe	Roger Brown	2022-08-18	1	1	173.318799	1.73	3	173.318799
fae5763d-c682-4e79-a63d-0025062beb67	Returned	Credit Card	North America	Caleb Camacho	2020-07-12	1	1	748.356472	2.73	8	748.356472
fae6a0e0-914a-4a6a-b5c7-d0103c9ed78e	Returned	Amazon Pay	South America	Christina Thompson	2019-06-29	1	1	3272.235354	26.93	9	3272.235354
faeccd10-dbcb-455e-9fb6-061f85c4a3ab	Returned	Credit Card	Europe	Adam Smith	2022-12-09	1	1	581.790846	24.07	7	581.790846
faeeca80-bd56-468d-808f-2375ed8958b9	Pending	Gift Card	North America	Caleb Camacho	2021-05-30	1	1	474.064052	12.66	2	474.064052
fb23e956-31e6-4b68-8d1a-7ad9d09a89b1	Cancelled	Credit Card	Australia	Susan Edwards	2021-09-20	1	1	826.8144	8.05	10	826.8144
fb4c5a73-60b1-45ec-b8de-03a32f8d360b	Returned	Amazon Pay	South America	Caitlyn Boyd	2019-02-19	1	1	631.937016	14.87	8	631.937016
fb4cbe76-8e0e-448a-a840-3dc8d6a0c746	Pending	Amazon Pay	Australia	Crystal Williams	2020-11-07	1	1	1147.8432	28.08	10	1147.8432
fb553404-b448-4ed9-bd36-37a2ee43072d	Cancelled	Debit Card	North America	Kristen Ramos	2022-11-06	1	1	237.0816	4	7	237.0816
fb5e8145-4623-4188-a68d-ed2631e380a0	Returned	Amazon Pay	North America	Johnny Marshall	2019-05-20	1	1	1629.787248	16.38	4	1629.787248
fb601a7b-915b-4068-9566-71b7e9231372	Returned	Gift Card	Europe	Mary Scott	2021-05-05	1	1	2292.341296	9.98	8	2292.341296
fb6c48e7-2082-41a2-a812-726bfa879686	Pending	Gift Card	Europe	Susan Edwards	2023-07-06	1	1	1553.2783559999998	17.98	9	1553.2783559999998
fb7b780b-6cbf-4ffc-8b4e-6d05fa371898	Pending	PayPal	Europe	Caleb Camacho	2019-01-05	1	1	176.71332	0.6	1	176.71332
fb80e005-d9f1-4dad-872c-8ed2f890e359	Cancelled	PayPal	Australia	Crystal Williams	2019-11-26	1	1	2106.31534	3.83	5	2106.31534
fb89c99e-8a00-4954-a6b1-fd70c753766d	Cancelled	Gift Card	Australia	Susan Edwards	2020-09-18	1	1	830.1393800000001	6.2	7	830.1393800000001
fba8d8b8-09af-49c1-86b7-78b5907604f1	Pending	Debit Card	North America	Johnny Marshall	2024-09-02	1	1	832.6258379999999	3.42	3	832.6258379999999
fbb1e50a-0e46-4274-bae7-4f852e0a4ff4	Pending	Credit Card	South America	Caitlyn Boyd	2023-10-16	1	1	1398.55367	6.57	5	1398.55367
fbbcc665-7764-4865-9d30-ca90a785380f	Cancelled	Debit Card	North America	Steven Coleman	2022-06-04	1	1	1524.1067099999998	18.7	7	1524.1067099999998
fbd6a925-1aa4-4d61-8eb1-be8ab2f144e5	Returned	Gift Card	North America	Kristen Ramos	2019-04-03	1	1	916.828308	0.01	6	916.828308
fbe2ad06-6670-44a3-bbc8-3c95e091f7cf	Pending	Debit Card	Europe	Johnny Marshall	2023-05-12	1	1	577.047744	0.81	9	577.047744
fbe2dcb0-fc5f-4633-b50b-38b5e04c98ad	Cancelled	PayPal	Asia	Charles Smith	2023-12-13	1	1	810.034281	29.37	9	810.034281
fbf20ff8-e345-49dc-8ee7-684560d170ca	Pending	Gift Card	North America	Caleb Camacho	2022-05-11	1	1	992.39682	15.9	6	992.39682
fbfe5a47-be86-4116-8aae-7a7c238f2d29	Cancelled	Credit Card	Australia	Caleb Camacho	2020-04-10	1	1	559.6906769999999	28.63	7	559.6906769999999
fc1bbe0c-2982-4ae2-909a-f63a00ec6b14	Cancelled	PayPal	South America	Sandra Luna	2022-09-22	1	1	879.181134	17.97	6	879.181134
fc2010ed-7a1d-408e-baeb-4ce830ff15ef	Returned	Credit Card	South America	Emily Matthews	2020-10-17	1	1	533.0110800000001	17.26	4	533.0110800000001
fc41d90e-78cd-4ec3-9576-45a22d4c0d97	Cancelled	PayPal	South America	Christina Thompson	2022-07-05	1	1	219.336425	20.25	7	219.336425
fc538151-ffd3-4297-bf65-96b010ca8b49	Returned	Gift Card	Europe	Michelle Andersen	2022-06-06	1	1	3747.08376	5.89	8	3747.08376
fc7900e4-80cc-43d6-aebe-3c2d0f37c80d	Pending	PayPal	Asia	Emily Matthews	2019-07-16	1	1	2904.84745	0.57	10	2904.84745
fc834d4a-b651-4545-bacb-d9b323cb7ff6	Cancelled	PayPal	North America	Caitlyn Boyd	2024-09-16	1	1	2448.4636	7.64	10	2448.4636
fc851cbe-55bd-4ec5-85c0-8f80302777dd	Cancelled	PayPal	Asia	Sandra Luna	2022-10-23	1	1	216.8898	2.74	4	216.8898
fc9e37e9-443e-4cee-a064-7409a9bd5656	Returned	Amazon Pay	South America	Charles Smith	2022-07-31	1	1	863.4201839999998	13.82	6	863.4201839999998
fca01e62-927c-4cb3-a872-911d85364a96	Cancelled	Debit Card	North America	Christina Thompson	2023-09-05	1	1	1892.4912	14.5	8	1892.4912
fcc4d61a-e887-406e-96fe-2dc49b513196	Pending	Amazon Pay	South America	Charles Smith	2024-06-17	1	1	1684.335224	15.14	4	1684.335224
fcd23ea3-ed53-48be-814d-ae13284729ec	Cancelled	Gift Card	North America	Kristen Ramos	2023-02-07	1	1	3180.877938	3.22	7	3180.877938
fcd51d34-799d-4117-b6db-1cf0c8fd547a	Pending	Credit Card	Australia	Michelle Garza	2019-07-09	1	1	1238.167368	9.16	3	1238.167368
fcde56a9-733f-41ee-94e4-889a5f596bef	Cancelled	Gift Card	Asia	Crystal Williams	2024-01-11	1	1	22.436588	9.09	4	22.436588
fd1054b2-0619-4b9b-9ecc-444af69e22d2	Pending	Debit Card	Australia	Michelle Garza	2022-09-03	1	1	223.83216	4.05	4	223.83216
fd128cfb-6499-4212-bffa-0f88a56ffec3	Cancelled	Debit Card	Australia	Roger Brown	2021-10-14	1	1	3478.1266	24.6	10	3478.1266
fd20c75d-5d1f-46b1-bea3-870bcfda67bd	Returned	Gift Card	North America	Emily Matthews	2019-01-25	1	1	1261.118664	14.98	3	1261.118664
fd250815-ff1d-4cc2-86f7-e1da3a923e24	Cancelled	PayPal	Europe	Caitlyn Boyd	2020-01-12	1	1	947.631384	25.52	3	947.631384
fd283d5c-d831-42b1-9041-61c995a603c1	Pending	Debit Card	Europe	Adam Smith	2021-12-12	1	1	86.700472	29.42	2	86.700472
fd2965ac-e5b5-40cb-95de-37091ff64065	Pending	Credit Card	North America	Johnny Marshall	2020-02-26	1	1	280.744912	23.81	1	280.744912
fd2d76cc-3f8b-4cda-8aa8-11e426143b4c	Cancelled	Gift Card	Australia	Caitlyn Boyd	2024-12-18	1	1	1677.85348	3.98	5	1677.85348
fd36a415-2c42-4cfa-88a5-a99bf8d3941e	Cancelled	Debit Card	North America	Jason Nelson	2019-07-08	1	1	1986.068784	25.52	7	1986.068784
fd3c3bbb-fdba-4fd5-96e6-8c100bbc204c	Pending	Amazon Pay	Europe	Christina Thompson	2023-08-29	1	1	183.1199	19.86	1	183.1199
fd6160d1-306c-4ea9-b2bd-23151c98053b	Cancelled	Credit Card	South America	Sandra Luna	2019-12-01	1	1	4037.42412	4.65	9	4037.42412
fd7b3d32-7307-469d-8e00-2c8e26827f50	Pending	Credit Card	Australia	Christina Thompson	2023-12-23	1	1	939.944528	5.87	8	939.944528
fd7bbfc4-ad52-49b4-968f-3cdc3629ce81	Pending	Amazon Pay	Europe	Bradley Howe	2024-09-15	1	1	648.783882	17.69	9	648.783882
fd84784f-265c-4b8c-9bd3-5216b7a67d42	Returned	Debit Card	Europe	Jason Nelson	2020-11-27	1	1	802.648014	16.49	2	802.648014
fd90ef4e-e617-48b8-91a0-068c6761f778	Pending	Amazon Pay	Asia	Joseph Brooks	2021-07-20	1	1	1471.6245750000005	17.35	5	1471.6245750000005
fdd73516-8ad9-4943-8192-dfd554a5be43	Cancelled	Amazon Pay	Asia	Steven Coleman	2023-07-10	1	1	962.41629	21.05	6	962.41629
fdde0859-7237-4349-ac7f-f2389e1c972d	Pending	Credit Card	South America	Charles Smith	2021-10-06	1	1	2680.09812	11.28	7	2680.09812
fddecdcd-cf81-4492-9395-da0972c30081	Cancelled	Credit Card	Australia	Joseph Brooks	2024-04-10	1	1	292.95552	22.56	5	292.95552
fde28c53-3d18-4288-b2f0-a4654efe4147	Pending	Debit Card	South America	Steven Coleman	2020-02-15	1	1	3730.757	24.5	10	3730.757
fdf30d19-59ac-4ebb-b4c8-ee6f63ec5087	Pending	Credit Card	Asia	Michelle Andersen	2022-05-23	1	1	318.21558	21.3	1	318.21558
fe072c9c-4d86-4758-b1f7-fc42ce3e05cf	Returned	Debit Card	Australia	Susan Edwards	2024-05-19	1	1	1692.3492299999998	12.77	6	1692.3492299999998
fe16bb24-e4ca-480e-89a4-e2a2b9e0f412	Cancelled	Gift Card	North America	Sandra Luna	2023-09-28	1	1	3693.758355	9.49	9	3693.758355
fe317154-aee0-428a-9cdc-ddb0c0977a52	Cancelled	Debit Card	Europe	Caitlyn Boyd	2024-09-11	1	1	3882.738	2.05	10	3882.738
fe3b4818-f80a-4e10-8a96-ee69734d7aff	Cancelled	Debit Card	Australia	Christina Thompson	2022-11-19	1	1	749.3785439999999	25.14	3	749.3785439999999
fe7b77eb-fd17-40f7-84eb-93305c47ab89	Cancelled	Credit Card	South America	Mary Scott	2021-06-20	1	1	365.550784	22.71	1	365.550784
fe7e0db2-57ca-4c38-b191-0180411edb03	Cancelled	Gift Card	North America	Caitlyn Boyd	2021-02-25	1	1	428.544688	18.36	4	428.544688
fe7ec083-95b9-4d4b-8e4c-3384955b0407	Cancelled	Credit Card	Australia	Adam Smith	2022-02-01	1	1	831.188448	10.44	4	831.188448
fe995f73-5de3-4719-ab8a-649867fa4ad7	Pending	Amazon Pay	Asia	Steven Coleman	2024-08-08	1	1	814.597336	25.67	8	814.597336
feab7514-e7a5-4af6-aa15-35c1f0b2e625	Returned	PayPal	South America	Sandra Luna	2023-05-23	1	1	4218.890463	6.23	9	4218.890463
feadfb6f-3175-442c-801a-3958756f2890	Pending	Amazon Pay	Australia	Mary Scott	2023-04-17	1	1	214.779838	6.14	1	214.779838
fec38b03-0433-48e0-8a34-b5ec8ad6668e	Cancelled	Debit Card	South America	Michelle Garza	2021-09-04	1	1	1254.567615	25.37	7	1254.567615
fec399d2-4f31-423e-a1ef-bd9743805209	Cancelled	Debit Card	North America	Steven Coleman	2023-11-10	1	1	313.665408	3.76	1	313.665408
fec521c7-d7c9-4b2a-bff1-482e6259d25d	Pending	PayPal	South America	Steven Coleman	2021-12-14	1	1	131.240316	10.52	3	131.240316
fecc5a38-c381-4991-9e8e-6cce6bdd334b	Returned	Amazon Pay	Australia	Emily Matthews	2021-11-16	1	1	743.1341700000002	20.02	5	743.1341700000002
fecc70c4-8da0-4204-83cf-cb047da2462c	Returned	Debit Card	South America	Kristen Ramos	2024-05-18	1	1	1807.286784	1.28	4	1807.286784
fed2002c-f5e1-413c-b035-4bf27c52625a	Cancelled	PayPal	North America	Joseph Brooks	2020-08-30	1	1	1422.033525	5.81	9	1422.033525
fee54e16-8e7d-4487-bf76-dfd794e00db9	Cancelled	Amazon Pay	Europe	Steven Coleman	2019-07-11	1	1	235.52358	11.64	1	235.52358
fee63b7e-ff6b-42e3-bb0f-9fc3f5c0bb05	Cancelled	Gift Card	South America	Bradley Howe	2022-10-30	1	1	1047.053808	21.07	8	1047.053808
ff0b763d-1adc-4947-b6be-9bb74d7f34f2	Pending	Debit Card	Europe	Caitlyn Boyd	2019-02-02	1	1	68.23139400000001	22.27	3	68.23139400000001
ff55def3-364d-429e-ad8a-70f947a7a935	Pending	Amazon Pay	South America	Roger Brown	2024-09-12	1	1	1766.205	25	6	1766.205
ff5937bf-9399-4865-9821-00acf6e08b4b	Pending	Amazon Pay	Australia	Diane Andrews	2020-10-01	1	1	335.196225	0.55	3	335.196225
ff69e664-7742-4ba2-b994-bde3c6bf4bd8	Returned	Amazon Pay	North America	Roger Brown	2019-01-13	1	1	2199.284105	0.77	5	2199.284105
ff6ae4f6-a32f-4c04-ac02-2cecedfc57d8	Pending	Debit Card	Australia	Adam Smith	2019-11-20	1	1	92.654268	13.48	1	92.654268
ff6ed04c-b607-4995-9a2f-14fb7189afd1	Cancelled	Amazon Pay	North America	Johnny Marshall	2022-05-02	1	1	2522.986656	22.18	8	2522.986656
ff7c99b4-cbaf-402e-b4d8-f9d7c0647dac	Cancelled	Debit Card	Europe	Roger Brown	2023-10-17	1	1	1007.83517	24.78	5	1007.83517
ff8ad8a7-62ee-4764-ae61-15d35e17735c	Pending	Gift Card	Asia	Emily Matthews	2023-10-06	1	1	164.72015000000002	0.95	2	164.72015000000002
ff8bd6e9-e584-4ca0-afb7-b14b8f95d63f	Cancelled	Debit Card	South America	Diane Andrews	2020-05-16	1	1	1119.51864	10.2	6	1119.51864
ffa45fa4-6660-4073-8a18-5f0924088d3a	Cancelled	PayPal	South America	Roger Brown	2021-07-05	1	1	474.67868	2.49	4	474.67868
ffc3ed95-c571-48c8-91ae-098aa3756817	Pending	Gift Card	Europe	Kristen Ramos	2022-11-30	1	1	606.837868	28.11	4	606.837868
ffe2446d-db24-4673-b22b-b7495fea3ce0	Cancelled	PayPal	Europe	Emily Matthews	2021-10-05	1	1	188.340086	16.73	1	188.340086
ffe7221f-abb4-495f-b472-4e681780143e	Returned	Amazon Pay	North America	Crystal Williams	2022-06-22	1	1	510.944334	18.89	2	510.944334
fffdb301-abf3-4428-add1-adf1fd67588c	Returned	Credit Card	Asia	Michelle Andersen	2024-04-25	1	1	1085.1461759999995	0.48	3	1085.1461759999995
\.


--
-- Data for Name: salesperson_cluster_summary; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.salesperson_cluster_summary (avg_order_value, avg_profit_per_order, discount_rate, profit_margin, num_completed_orders, loss_rate) FROM stdin;
1694.7	1473.39	0.18	0.87	9.47	2.75
1006.15	815.52	0.18	0.81	12.14	2.95
849.08	670.53	0.21	0.78	7.33	6.83
1313.89	1109.35	0.17	0.84	10.16	3.01
\.


--
-- Data for Name: salesperson_growth_yoy; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.salesperson_growth_yoy (year, salesperson, num_completed_orders, total_sales, total_profit, avg_order_value, avg_profit_per_order, total_discounted_revenue, total_discount_given, total_revenue_lost, units_lost, customers_lost, discount_rate, loss_rate, profit_margin, cluster, total_sales_yoy, total_profit_yoy, avg_order_value_yoy, avg_profit_per_order_yoy, num_completed_orders_yoy) FROM stdin;
2019	Adam Smith	6	7700.412061	6476.046901925843	1283.4	1079.34	7700.412061	1301.277939	29048.322476	155	34	0.16898809163610032	3.7723075396341446	0.8410000465721627	3	0	0	0	0	0
2020	Adam Smith	14	15248.316574999997	12570.717778019867	1089.17	897.91	15248.316574999997	2402.2834249999996	29721.954969000006	128	25	0.15754417303603235	1.949195822555908	0.8244003668332726	1	98	94.1	-15.1	-16.8	133.29999999999998
2021	Adam Smith	8	12052.41181	10239.301545152586	1506.55	1279.91	12052.41181	1367.10819	27663.047363	171	27	0.1134302587359069	2.2952291872443085	0.8495645275460088	3	-21	-18.5	38.3	42.5	-42.9
2022	Adam Smith	13	14740.822705	12117.429404935025	1133.91	932.11	14740.822705	3159.4672949999995	37808.863847	193	34	0.21433452923413338	2.5649086624029103	0.8220320973553846	1	22.3	18.3	-24.7	-27.200000000000003	62.5
2023	Adam Smith	10	8060.67974	6345.259499982809	806.07	634.53	8060.67974	1067.45026	21813.970544000003	79	17	0.13242682930360414	2.7062197293053605	0.7871866523235432	1	-45.300000000000004	-47.599999999999994	-28.9	-31.900000000000002	-23.1
2024	Adam Smith	4	4569.470333	3752.9404402916934	1142.37	938.24	4569.470333000001	655.1296669999999	32311.802131999997	156	34	0.14337102973811996	7.071235783860815	0.8213075404360424	2	-43.3	-40.9	41.699999999999996	47.9	-60
2019	Bradley Howe	10	13102.462313	10997.349108027	1310.25	1099.73	13102.462313	1532.0776870000002	38746.93386599999	176	28	0.11693051660067769	2.9572253627133933	0.8393345346329026	3	0	0	0	0	0
2020	Bradley Howe	9	6963.938849000001	5351.826448442503	773.77	594.65	6963.938849000001	1492.4611510000002	43105.91600100001	179	32	0.21431278811621282	6.189875720575847	0.7685056638903438	2	-46.9	-51.300000000000004	-40.9	-45.9	-10
2021	Bradley Howe	10	9748.268382	7721.623720457448	974.83	772.16	9748.268382	1779.911618	21355.341498	111	22	0.18258746561456746	2.190680504594257	0.7921020860192243	1	40	44.3	26	29.9	11.1
2022	Bradley Howe	12	12866.525684	10532.363018056263	1072.21	877.7	12866.525684	3220.2043160000003	53007.64452	247	40	0.25027768918259286	4.119810259728231	0.8185864060531621	1	32	36.4	10	13.700000000000001	20
2023	Bradley Howe	9	13323.262195999998	11647.81164727973	1480.36	1294.2	13323.262195999998	2680.277804	50018.652009000005	198	34	0.2011727882083332	3.754234606597846	0.8742462225787853	0	3.5000000000000004	10.6	38.1	47.5	-25
2024	Bradley Howe	6	8181.939134000001	7041.880218608849	1363.66	1173.65	8181.939134000002	1395.6408659999993	30325.602293999997	139	29	0.17057580643693884	3.706407710610084	0.8606615257434947	3	-38.6	-39.5	-7.9	-9.3	-33.300000000000004
2019	Caitlyn Boyd	9	11747.390995000003	9900.168228521057	1305.27	1100.02	11747.390995000002	1718.8090049999998	30917.483693	169	27	0.14631410546661552	2.631859593858695	0.8427546365601373	3	0	0	0	0	0
2020	Caitlyn Boyd	7	11307.96387	9656.268796477398	1615.42	1379.47	11307.96387	2009.2261299999993	41351.901707000005	213	34	0.1776823973881338	3.65688307659936	0.8539352360415172	0	-3.6999999999999997	-2.5	23.799999999999997	25.4	-22.2
2021	Caitlyn Boyd	5	6225.7649329999995	5357.973484287469	1245.15	1071.59	6225.7649329999995	1564.9750669999994	41001.127448	189	35	0.2513707285517263	6.585717239446567	0.8606128792121983	3	-44.9	-44.5	-22.900000000000002	-22.3	-28.599999999999998
2022	Caitlyn Boyd	14	13917.410157	11183.394140005355	994.1	798.81	13917.410157	2514.5598429999995	44753.212659000004	188	31	0.18067728224099644	3.215627918854616	0.8035542542647904	1	123.50000000000001	108.7	-20.200000000000003	-25.5	180
2023	Caitlyn Boyd	13	17740.064766000003	15141.993137343436	1364.62	1164.77	17740.064766000003	3520.9652340000002	31003.998095000003	178	34	0.19847533142878718	1.7476823508796426	0.8535477934874318	3	27.500000000000004	35.4	37.3	45.800000000000004	-7.1
2024	Caitlyn Boyd	10	10771.237579	8824.181428904194	1077.12	882.42	10771.237579	3031.332421000001	30004.398153000002	150	31	0.28142842442821964	2.785603597816622	0.819235613752327	1	-39.300000000000004	-41.699999999999996	-21.099999999999998	-24.2	-23.1
2019	Caleb Camacho	15	18142.85026	15022.664692230923	1209.52	1001.51	18142.85026	4422.05974	35366.93199600001	150	28	0.24373566868649227	1.949359196000993	0.82802120267463	1	0	0	0	0	0
2020	Caleb Camacho	16	26117.186758	22545.973508547584	1632.32	1409.12	26117.186757999996	4194.073242	40809.811221	190	35	0.16058671559314505	1.5625653558762214	0.8632619476767148	0	44	50.1	35	40.699999999999996	6.7
2021	Caleb Camacho	5	8211.371074	7115.362972168829	1642.27	1423.07	8211.371074	2700.0089259999995	36466.89397000001	180	34	0.3288134102901704	4.441023751254724	0.8665255665644552	0	-68.60000000000001	-68.4	0.6	1	-68.8
2022	Caleb Camacho	9	12318.341596000002	10403.61269961008	1368.7	1155.96	12318.341596	1793.9384040000004	28608.280649	154	30	0.14563148700004602	2.3224133237455966	0.8445627699582815	3	50	46.2	-16.7	-18.8	80
2023	Caleb Camacho	5	11240.868669000001	10001.763400619133	2248.17	2000.35	11240.868669	1583.631331	36294.385609	177	34	0.14088157931844972	3.22878833279962	0.8897678369112109	0	-8.7	-3.9	64.3	73	-44.4
2024	Caleb Camacho	16	15513.624373999999	12632.49206019046	969.6	789.53	15513.624373999999	3333.7456260000004	52597.670179	246	42	0.2148914751079818	3.3904179262681433	0.81428373896701	1	38	26.3	-56.89999999999999	-60.5	220.00000000000003
2019	Charles Smith	14	20252.237109	17156.825827161854	1446.59	1225.49	20252.237109	2787.262891	34175.799867	160	28	0.13762740757964723	1.687507394025741	0.8471570688621575	3	0	0	0	0	0
2020	Charles Smith	11	14299.828864	11935.1906057317	1299.98	1085.02	14299.828864	2306.9211359999986	45287.131901	187	34	0.16132508703007642	3.166970201651219	0.8346387022699756	3	-29.4	-30.4	-10.100000000000001	-11.5	-21.4
2021	Charles Smith	8	14674.107327000002	12767.293978425747	1834.26	1595.91	14674.107327000002	3339.612673	39704.532777000015	190	28	0.22758540595210133	2.705754557481302	0.8700559218981747	0	2.6	7.000000000000001	41.099999999999994	47.099999999999994	-27.3
2022	Charles Smith	8	6220.0218079999995	4685.576535302926	777.5	585.7	6220.0218079999995	1779.7981920000002	33377.064683	174	34	0.28614018518566586	5.3660687555904465	0.7533054834753926	2	-57.599999999999994	-63.3	-57.599999999999994	-63.3	0
2023	Charles Smith	14	23684.463746	20504.275422368777	1691.75	1464.59	23684.463746	3733.6062539999994	38685.857114000006	166	30	0.1576394675446497	1.6333853925881494	0.8657268174725588	0	280.79999999999995	337.59999999999997	117.6	150.1	75
2024	Charles Smith	15	16256.430489	13411.467955164058	1083.76	894.1	16256.430489	2462.8195109999997	27295.965086	152	29	0.1514981725334156	1.6790872451655336	0.8249946360757978	1	-31.4	-34.599999999999994	-35.9	-39	7.1
2019	Christina Thompson	11	16313.06565	14102.505466785991	1483.01	1282.05	16313.06565	1671.8543499999994	36677.169906	161	31	0.10248560177896417	2.248330920313559	0.864491430939959	3	0	0	0	0	0
2020	Christina Thompson	7	5833.874030000001	4558.611368184523	833.41	651.23	5833.874030000001	1031.85597	30935.837629	134	28	0.1768732003285988	5.302794930078392	0.7814038055574063	2	-64.2	-67.7	-43.8	-49.2	-36.4
2021	Christina Thompson	12	17262.772141999998	15005.390485709195	1438.56	1250.45	17262.772142	3349.707857999999	26578.651972	119	22	0.19404229114802615	1.539651439141379	0.8692341161823809	3	195.9	229.2	72.6	92	71.39999999999999
2022	Christina Thompson	9	8801.793045	7027.3141654991905	977.98	780.81	8801.793045	1173.526955	38224.13267499999	182	32	0.13332816949912732	4.342766579443017	0.7983957506807285	1	-49	-53.2	-32	-37.6	-25
2023	Christina Thompson	7	11717.323083	10097.676442578057	1673.9	1442.53	11717.323083	1997.6069170000003	47379.652368999996	227	38	0.17048321556467236	4.043556026695248	0.8617733223749888	0	33.1	43.7	71.2	84.7	-22.2
2024	Christina Thompson	7	4562.354664	3359.9873790627307	651.76	480	4562.354664	1143.145336	24238.902167999997	120	22	0.2505603838781263	5.312805328191819	0.7364590494411266	2	-61.1	-66.7	-61.1	-66.7	0
2019	Crystal Williams	9	7367.351228999999	5784.79132809442	818.59	642.75	7367.351229	2204.0787709999995	41777.844416	166	28	0.29916841243079545	5.670673640690628	0.7851928255196833	2	0	0	0	0	0
2020	Crystal Williams	10	13446.911206	11371.182992648854	1344.69	1137.12	13446.911206	2377.2287940000006	35852.559376000005	183	34	0.17678623422004028	2.6662300975113618	0.8456353149394666	3	82.5	96.6	64.3	76.9	11.1
2021	Crystal Williams	12	15112.983126	12664.055196059322	1259.42	1055.34	15112.983126	2286.6868740000004	26553.082682000004	164	37	0.15130612235423208	1.756971635620948	0.8379586670928255	3	12.4	11.4	-6.3	-7.199999999999999	20
2022	Crystal Williams	9	13103.739157000002	11200.102389733645	1455.97	1244.46	13103.739157	1960.8208429999993	42039.328451	208	41	0.14963826885645318	3.208193321563688	0.8547256821539037	3	-13.3	-11.600000000000001	15.6	17.9	-25
2023	Crystal Williams	15	13891.938659	11287.219697748129	926.13	752.48	13891.938659	2311.4513410000004	42886.397354	177	29	0.16638796050992558	3.0871427240441864	0.8125014063775481	1	6	0.8	-36.4	-39.5	66.7
2024	Crystal Williams	10	9632.977536	7953.074514727736	963.3	795.31	9632.977536	2078.1924639999997	36536.538907	162	36	0.2157372895590649	3.792860387191502	0.8256091623805626	1	-30.7	-29.5	4	5.7	-33.300000000000004
2019	Diane Andrews	6	5220.950683	4216.3672133719165	870.16	702.73	5220.950683	802.7093169999998	40653.546947999996	198	32	0.15374773020049992	7.786617690217319	0.8075861024891272	2	0	0	0	0	0
2020	Diane Andrews	8	6325.308165	4975.984847360576	790.66	622	6325.308165	1174.311835	45003.033252999994	202	36	0.18565290486522878	7.114757428265156	0.7866786435630644	2	21.2	18	-9.1	-11.5	33.300000000000004
2021	Diane Andrews	10	9429.686382	7581.173258126693	942.97	758.12	9429.686382	996.7536180000002	45643.726362999994	203	35	0.10570379306597816	4.84042888744717	0.803968758982073	1	49.1	52.400000000000006	19.3	21.9	25
2022	Diane Andrews	11	15475.661251000001	13196.743421811785	1406.88	1199.7	15475.661251000001	3070.328749	54320.988623	229	40	0.19839725742262562	3.5100916039687737	0.8527418123060196	3	64.1	74.1	49.2	58.199999999999996	10
2023	Diane Andrews	12	17102.984082000003	14596.157987290073	1425.25	1216.35	17102.984082000003	4265.415918	30143.706105999994	160	27	0.24939600584023972	1.762482264000039	0.8534275607875802	3	10.5	10.6	1.3	1.4000000000000001	9.1
2024	Diane Andrews	11	12834.503824000001	10535.550002566602	1166.77	957.78	12834.503824000001	2642.526176	46076.083327	188	30	0.20589235176030593	3.5900167204625077	0.8208770784629439	1	-25	-27.800000000000004	-18.099999999999998	-21.3	-8.3
2019	Emily Matthews	9	11015.858378000003	9152.039833064875	1223.98	1016.89	11015.858378000003	2329.7516219999998	40197.34970199999	176	34	0.2114907020457702	3.6490437987364603	0.8308058726810252	3	0	0	0	0	0
2020	Emily Matthews	14	15020.977174000001	12292.365381380801	1072.93	878.03	15020.977174000001	3416.312826	35696.896991999994	154	27	0.22743612392363785	2.376469691584926	0.8183465855109487	1	36.4	34.300000000000004	-12.3	-13.700000000000001	55.60000000000001
2021	Emily Matthews	11	11367.198237999999	9077.814398954994	1033.38	825.26	11367.198237999999	1123.0417619999998	38500.61083499999	178	32	0.09879670772747896	3.386992117925268	0.7985973508061375	1	-24.3	-26.200000000000003	-3.6999999999999997	-6	-21.4
2022	Emily Matthews	20	24703.742782	20880.627950146714	1235.19	1044.03	24703.742782	4120.497218	46373.924283	173	29	0.1667964751075022	1.877202361287118	0.8452414735050212	1	117.30000000000001	130	19.5	26.5	81.8
2023	Emily Matthews	9	10826.886503	8851.000110039413	1202.99	983.44	10826.886503	2138.753497	26141.440311	124	26	0.19754095477101172	2.414492874175463	0.8175018836289554	3	-56.2	-57.599999999999994	-2.6	-5.800000000000001	-55.00000000000001
2024	Emily Matthews	9	7635.524284000001	5970.746591213221	848.39	663.42	7635.524284000001	675.5957159999998	48501.99981300001	257	37	0.08848059293265417	6.352150554302396	0.7819694325018036	2	-29.5	-32.5	-29.5	-32.5	0
2019	Jason Nelson	15	19691.938863999996	16586.59425491439	1312.8	1105.77	19691.938864	3939.0911359999996	30647.405667	148	28	0.20003571833148873	1.5563427186455643	0.8423037654883913	3	0	0	0	0	0
2020	Jason Nelson	11	10626.781292000001	8543.502076094734	966.07	776.68	10626.781292	1600.368708	37101.53717	137	29	0.15059768936853732	3.4913240566953787	0.8039595284158533	1	-46	-48.5	-26.400000000000002	-29.799999999999997	-26.700000000000003
2021	Jason Nelson	11	17492.484053	15060.096750500112	1590.23	1369.1	17492.484053	3058.8459469999993	38298.729825999995	159	32	0.1748662990191722	2.1894391734164067	0.8609467188805167	0	64.60000000000001	76.3	64.60000000000001	76.3	0
2022	Jason Nelson	14	17785.192706	14767.685555383023	1270.37	1054.83	17785.192706	3356.127294	68429.17601800001	275	48	0.1887034540181158	3.8475363831686114	0.8303359878918267	3	1.7000000000000002	-1.9	-20.1	-23	27.3
2023	Jason Nelson	8	10423.333943	8805.047782392481	1302.92	1100.63	10423.333943	1733.7760569999996	40948.52906200001	170	29	0.16633603667321356	3.9285442916754882	0.8447439015715014	3	-41.4	-40.400000000000006	2.6	4.3	-42.9
2024	Jason Nelson	11	11913.552534	9678.4825274209	1083.05	879.86	11913.552533999999	2854.6874660000003	22734.701804000004	146	27	0.23961681101023632	1.9083058339750134	0.8123926511256444	1	14.299999999999999	9.9	-16.900000000000002	-20.1	37.5
2019	Johnny Marshall	9	13521.328930000001	11562.989805147601	1502.37	1284.78	13521.328930000001	2619.18107	31777.636568	161	28	0.19370737030062027	2.3501858975928336	0.8551666677890366	0	0	0	0	0	0
2020	Johnny Marshall	9	11919.210699000001	10004.167299591092	1324.36	1111.57	11919.210699000001	2269.649301	46075.379243	209	33	0.19041942946695448	3.865640133944913	0.8393313577744224	3	-11.799999999999999	-13.5	-11.799999999999999	-13.5	0
2021	Johnny Marshall	7	8399.362871	7129.833104324611	1199.91	1018.55	8399.362871	1657.2771289999998	40109.632958	176	33	0.19730986200417486	4.775318506179111	0.8488540397440595	3	-29.5	-28.7	-9.4	-8.4	-22.2
2022	Johnny Marshall	11	9416.474250000001	7423.633446484864	856.04	674.88	9416.474250000001	1109.2157499999994	26202.751559999993	112	24	0.11779522999279686	2.782649945652428	0.7883665636833089	1	12.1	4.1000000000000005	-28.7	-33.7	57.099999999999994
2023	Johnny Marshall	13	12591.666913000003	10149.430105195172	968.59	780.73	12591.666913000003	1832.0530869999993	25035.308199	126	26	0.1454972641555928	1.9882441595681681	0.8060434075425396	1	33.7	36.7	13.100000000000001	15.7	18.2
2024	Johnny Marshall	12	11956.755303	9446.342933266891	996.4	787.2	11956.755303	2250.824697	26433.855888000006	120	26	0.1882471155393854	2.210788396862788	0.7900423395715696	1	-5	-6.9	2.9000000000000004	0.8	-7.7
2019	Joseph Brooks	6	4123.801833	3229.100582037042	687.3	538.18	4123.801833	734.6281669999997	22111.586980999997	94	20	0.1781434212287474	5.361942177738975	0.7830397077271588	2	0	0	0	0	0
2020	Joseph Brooks	11	12946.078647999999	10669.96715112271	1176.92	970	12946.078647999999	2579.111352	39910.265833000005	188	31	0.1992195028413827	3.0828073054511855	0.8241852564962658	1	213.89999999999998	230.39999999999998	71.2	80.2	83.3
2021	Joseph Brooks	9	10336.134031	8697.11594120483	1148.46	966.35	10336.134031	2394.755969	44063.34887500002	207	37	0.23168778208735283	4.263039618376251	0.8414283246638009	3	-20.200000000000003	-18.5	-2.4	-0.4	-18.2
2022	Joseph Brooks	11	9487.522812000001	7471.624444530189	862.5	679.24	9487.522812000001	2208.5071879999996	37039.920466999996	201	31	0.23278017157509623	3.904066551508176	0.7875211045690383	1	-8.200000000000001	-14.099999999999998	-24.9	-29.7	22.2
2023	Joseph Brooks	11	11146.672073000002	9032.507180462331	1013.33	821.14	11146.672073000002	2319.987926999999	31730.548146999998	137	22	0.2081327872396627	2.846638704287286	0.8103321889536249	1	17.5	20.9	17.5	20.9	0
2024	Joseph Brooks	12	12617.644997000001	10390.98685670164	1051.47	865.92	12617.644997000001	1648.0650030000002	32034.937839000002	163	35	0.13061589570730892	2.5388999172679765	0.8235282304401672	1	13.200000000000001	15	3.8	5.5	9.1
2019	Kristen Ramos	10	13516.507361000002	11390.635711833844	1351.65	1139.06	13516.507361	1882.3826390000002	63942.51903499999	228	35	0.13926546175910448	4.730698347377609	0.8427203424384568	3	0	0	0	0	0
2020	Kristen Ramos	8	8435.070731000002	7004.102677124334	1054.38	875.51	8435.070731000002	2133.459269	32390.694724999998	140	28	0.2529272530174827	3.840002740695452	0.8303549431284944	1	-37.6	-38.5	-22	-23.1	-20
2021	Kristen Ramos	10	8826.594604	6912.429642071215	882.66	691.24	8826.594604	874.355396	37771.40735799999	190	33	0.0990591995245554	4.279272930568591	0.7831366401419035	1	4.6	-1.3	-16.3	-21	25
2022	Kristen Ramos	14	12954.476804000002	10540.84170440954	925.32	752.92	12954.476804000002	3208.143195999999	36254.48921800001	190	37	0.24764745381375872	2.798606980932304	0.8136833207462926	1	46.800000000000004	52.5	4.8	8.9	40
2023	Kristen Ramos	9	16750.812447	14647.099740402022	1861.2	1627.46	16750.812447	1862.9775530000002	31672.017471999996	164	31	0.11121714596796477	1.8907750040310625	0.8744113031380311	0	29.299999999999997	39	101.1	116.19999999999999	-35.699999999999996
2024	Kristen Ramos	11	12978.157025999999	10813.046645097906	1179.83	983	12978.157025999999	1619.812974	35488.410961	197	36	0.12481070854320236	2.7344723052667437	0.8331727396606017	3	-22.5	-26.200000000000003	-36.6	-39.6	22.2
2019	Mary Scott	12	8964.718249	7065.045688486369	747.06	588.75	8964.718249	642.5017510000004	19271.882885	125	21	0.07167004396057516	2.149747749980848	0.7880945605038355	1	0	0	0	0	0
2020	Mary Scott	9	10981.466228000001	9004.164440104678	1220.16	1000.46	10981.466228000001	2131.243772	32032.605858000006	166	30	0.19407643093832586	2.9169698465515332	0.8199419142360337	3	22.5	27.400000000000002	63.3	69.89999999999999	-25
2021	Mary Scott	11	14009.606784	11790.411073428102	1273.6	1071.86	14009.606783999998	2403.6332160000006	37786.152514	179	33	0.17157035547529617	2.6971601056750973	0.8415947181967747	3	27.6	30.9	4.3999999999999995	7.1	22.2
2022	Mary Scott	16	28872.830466000003	25422.809645045993	1804.55	1588.93	28872.830466000003	5787.139533999999	27804.95810099999	109	20	0.2004354765569245	0.9630146283628993	0.8805097815049108	0	106.1	115.6	41.699999999999996	48.199999999999996	45.5
2023	Mary Scott	10	10403.410899999999	8385.02275456819	1040.34	838.5	10403.410899999999	1648.9890999999998	26094.468725	116	25	0.1585046592747769	2.5082608940304376	0.8059878471750251	1	-64	-67	-42.3	-47.199999999999996	-37.5
2024	Mary Scott	5	4330.202544	3421.179083512961	866.04	684.24	4330.202544	1141.3174560000002	30251.319013999997	135	26	0.2635713790297012	6.98612102011642	0.7900736856416574	2	-58.4	-59.199999999999996	-16.8	-18.4	-50
2019	Michelle Andersen	13	17734.740449999998	15054.65219053664	1364.21	1158.05	17734.740449999998	3654.6695499999987	40101.006766	168	32	0.2060740364542521	2.261155548289967	0.8488791946507818	3	0	0	0	0	0
2020	Michelle Andersen	12	14075.346918	11502.299775222562	1172.95	958.52	14075.346917999997	3573.413082	36499.509185	220	36	0.25387744279540325	2.593151657123511	0.8171947620355315	1	-20.599999999999998	-23.599999999999998	-14.000000000000002	-17.2	-7.7
2021	Michelle Andersen	8	8678.129229	7169.897914383779	1084.77	896.24	8678.129229	1326.9507709999996	33395.229289999996	149	27	0.15290746841677386	3.848206037126299	0.8262031741154403	3	-38.3	-37.7	-7.5	-6.5	-33.300000000000004
2022	Michelle Andersen	14	8842.380387000001	6554.646218662504	631.6	468.19	8842.380387000001	1874.0596130000001	33154.703225	161	31	0.2119406235627714	3.749522388082714	0.7412762097748129	1	1.9	-8.6	-41.8	-47.8	75
2023	Michelle Andersen	6	7028.615924000001	5802.063507379996	1171.44	967.01	7028.615924	1427.1840759999995	29186.397270000005	144	26	0.20305335949951667	4.152509908862677	0.8254916145820682	3	-20.5	-11.5	85.5	106.5	-57.099999999999994
2024	Michelle Andersen	7	10619.055494	9181.393227717468	1517.01	1311.63	10619.055494	2432.3645060000003	35049.382325	139	29	0.22905657733631204	3.3006120313434346	0.8646148645616512	0	51.1	58.199999999999996	29.5	35.6	16.7
2019	Michelle Garza	9	12527.992849	10549.43389822239	1392	1172.16	12527.992849000002	1773.787150999999	42933.16194299999	180	33	0.14158590066098137	3.4269784841413737	0.8420689591201722	3	0	0	0	0	0
2020	Michelle Garza	9	12367.170897	10469.29842687641	1374.13	1163.26	12367.170897	3232.149103	52683.990268	202	34	0.261349109664527	4.259987244195029	0.8465394805384333	3	-1.3	-0.8	-1.3	-0.8	0
2021	Michelle Garza	14	18897.426944	16008.121777538165	1349.82	1143.44	18897.426944	3224.3030560000007	37491.618357	222	39	0.17062127376149103	1.9839536074462096	0.8471058956849573	3	52.800000000000004	52.900000000000006	-1.7999999999999998	-1.7000000000000002	55.60000000000001
2022	Michelle Garza	13	12719.107227	10214.31280171551	978.39	785.72	12719.107227000002	2077.172773	28703.664295000006	126	20	0.1633112085564148	2.256735774195546	0.8030683773176048	1	-32.7	-36.199999999999996	-27.500000000000004	-31.3	-7.1
2023	Michelle Garza	6	2872.6054140000006	1918.55344671004	478.77	319.76	2872.6054140000006	446.07458599999984	54345.49492700002	213	40	0.1552857151302437	18.9185380846741	0.6678792142351785	2	-77.4	-81.2	-51.1	-59.3	-53.800000000000004
2024	Michelle Garza	14	17414.187677	14569.267660526386	1243.87	1040.66	17414.187677	3309.4523229999995	34697.784973999995	163	30	0.19004345102878376	1.9925009203746846	0.836632057191443	3	506.20000000000005	659.4	159.8	225.5	133.29999999999998
2019	Roger Brown	7	7194.614586	6174.244834795498	1027.8	882.03	7194.614586	589.1654140000004	37141.50447100001	144	25	0.08188978116304622	5.162403632193677	0.8581758982350438	3	0	0	0	0	0
2020	Roger Brown	8	13814.920015999998	12133.240750402689	1726.87	1516.66	13814.920015999998	1345.0599840000002	47674.28673099999	247	48	0.09736284990736065	3.4509274520435267	0.8782707924729465	0	92	96.5	68	72	14.299999999999999
2021	Roger Brown	9	12858.645201	10925.989079345947	1428.74	1214	12858.645201	1754.804799	24239.702732	120	20	0.1364688714533885	1.8850899416771305	0.8496998640647032	3	-6.9	-9.9	-17.299999999999997	-20	12.5
2022	Roger Brown	11	17597.96488	15323.32831831057	1599.81	1393.03	17597.96488	3061.905120000001	36999.089372999995	160	29	0.17399200082958688	2.1024640988486842	0.8707443402006931	0	36.9	40.2	12	14.7	22.2
2023	Roger Brown	9	8911.539233	7069.051203638762	990.17	785.45	8911.539233	1706.430767	45322.84743499999	217	36	0.19148552482168038	5.085860730676759	0.7932469373485573	2	-49.4	-53.900000000000006	-38.1	-43.6	-18.2
2024	Roger Brown	10	8217.983247	6484.691133657403	821.8	648.47	8217.983247	1924.9167529999995	37448.195526	179	37	0.23423225566962505	4.556859560363619	0.7890854652234366	2	-7.8	-8.3	-17	-17.4	11.1
2019	Sandra Luna	8	7917.462184	6404.879512337446	989.68	800.61	7917.462183999999	1791.8378159999995	52138.29376000001	258	44	0.22631466679070905	6.585228012249134	0.8089561229961721	2	0	0	0	0	0
2020	Sandra Luna	8	10396.831396999998	8674.58846900574	1299.6	1084.32	10396.831397	2655.2686029999995	41477.822467000005	183	37	0.25539209992057543	3.9894676448219037	0.8343492490903324	3	31.3	35.4	31.3	35.4	0
2021	Sandra Luna	9	11799.070423000001	9977.967639026298	1311.01	1108.66	11799.070423000001	1698.2695769999993	43550.66132000001	181	30	0.14393248926538754	3.6910247806561465	0.8456570968146935	3	13.5	15	0.8999999999999999	2.1999999999999997	12.5
2022	Sandra Luna	11	14930.333099999998	12611.22019817362	1357.3	1146.47	14930.333099999998	2390.4869000000003	38398.529227	186	34	0.1601094151074232	2.57184678799966	0.8446710541356657	3	26.5	26.400000000000002	3.5000000000000004	3.4000000000000004	22.2
2023	Sandra Luna	9	12232.789119000001	10329.494212447857	1359.2	1147.72	12232.789119	1439.1108810000003	31510.07766800001	127	21	0.11764372515543241	2.575870258325509	0.8444103885028197	3	-18.099999999999998	-18.099999999999998	0.1	0.1	-18.2
2024	Sandra Luna	11	15411.712085	13095.480825558081	1401.06	1190.5	15411.712085	2919.8279149999985	44124.18548399998	202	38	0.1894551298970752	2.863029444142382	0.8497096723149744	3	26	26.8	3.1	3.6999999999999997	22.2
2019	Steven Coleman	9	7416.232588999999	6085.814404553208	824.03	676.2	7416.232588999999	1519.3374109999995	38711.97337600001	218	35	0.20486647266882255	5.219897422502482	0.8206072735070215	2	0	0	0	0	0
2020	Steven Coleman	9	11010.670876	9324.294964719475	1223.41	1036.03	11010.670876	1617.9991239999995	28790.96013	149	29	0.14694827792253407	2.6148234248610374	0.8468416747469653	3	48.5	53.2	48.5	53.2	0
2021	Steven Coleman	10	13806.845253000001	11790.937905706443	1380.68	1179.09	13806.845253000001	1620.844747	36786.528089	182	39	0.11739428647886214	2.664368826832972	0.8539921821130331	3	25.4	26.5	12.9	13.8	11.1
2022	Steven Coleman	6	7715.43215	6478.478687992974	1285.91	1079.75	7715.43215	2471.0978500000006	53520.204996	229	36	0.3202799016254716	6.936773463298488	0.8396780066289579	2	-44.1	-45.1	-6.9	-8.4	-40
2023	Steven Coleman	12	15222.731961	12616.409313079426	1268.56	1051.37	15222.731961	2396.608039	35956.16944500001	156	33	0.15743613203858606	2.36200502886855	0.8287874571661734	3	97.3	94.69999999999999	-1.3	-2.6	100
2024	Steven Coleman	13	13184.010116000001	10631.103493859424	1014.15	817.78	13184.010116000001	2801.3698839999993	42345.026587	185	33	0.21248238277671533	3.2118472463556773	0.806363420561822	1	-13.4	-15.7	-20.1	-22.2	8.3
2019	Susan Edwards	11	13438.076176	11392.619049758487	1221.64	1035.69	13438.076176	2181.4538240000006	39113.307655	207	37	0.16233378911008195	2.910632976233249	0.8477864614360023	3	0	0	0	0	0
2020	Susan Edwards	13	17008.409904	14337.497571437492	1308.34	1102.88	17008.409904	3900.7700959999993	36892.227052999995	198	33	0.22934360813368126	2.1690579696297045	0.842965195004245	3	26.6	25.8	7.1	6.5	18.2
2021	Susan Edwards	6	4999.320403	3936.95638239836	833.22	656.16	4999.320403	781.2595969999998	35855.356027999995	147	26	0.15627315995413704	7.172046025792597	0.7874983127778458	2	-70.6	-72.5	-36.3	-40.5	-53.800000000000004
2022	Susan Edwards	17	25942.894598	22118.299045516284	1526.05	1301.08	25942.894598	4592.295402	39011.081286	180	35	0.1770155363601574	1.5037289358222756	0.8525763754681961	3	418.9	461.8	83.2	98.3	183.29999999999998
2023	Susan Edwards	10	12819.654411	10732.529920475807	1281.97	1073.25	12819.654411	2587.9255890000004	32920.158363	162	29	0.20187171245267047	2.5679442914430375	0.8371933888691009	3	-50.6	-51.5	-16	-17.5	-41.199999999999996
2024	Susan Edwards	11	11850.631875000001	9776.953999449823	1077.33	888.81	11850.631875	2347.778125	39036.074625	172	36	0.19811417228754308	3.2940078669855737	0.82501541711672	1	-7.6	-8.9	-16	-17.2	10
\.


--
-- Data for Name: sensitivity_ranked; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.sensitivity_ranked (product_category, region, sensitivity_coef, sensitivity_tier) FROM stdin;
Beauty	Asia	99.68759110172506	Very High
Toys	North America	26.11799899817534	Very High
Toys	Europe	23.250479906012156	Very High
Clothing	Asia	17.646850204942528	Very High
Books	Australia	15.473349214464935	Very High
Sports	Australia	14.26152208594307	Very High
Electronics	Europe	9.610121792403925	Very High
Home & Kitchen	North America	8.508209187024478	Very High
Sports	South America	7.907827678844124	Very High
Toys	South America	7.145231370847373	High
Beauty	South America	6.641744872782683	High
Home & Kitchen	Australia	4.741454540243703	High
Clothing	North America	4.525148075947415	High
Sports	North America	4.455436593896447	High
Electronics	North America	4.281145649003752	High
Books	South America	3.3580062477814123	High
Books	Europe	1.9978110746682605	High
Sports	Asia	1.4950616707728714	Medium
Home & Kitchen	South America	0.605145593346522	Medium
Beauty	Europe	0.23021640109557306	Medium
Electronics	South America	-0.29972345597356115	Medium
Electronics	Australia	-0.7681883415825925	Medium
Toys	Asia	-1.2966695702864388	Medium
Electronics	Asia	-2.119831905866414	Medium
Beauty	Australia	-2.773881211692215	Medium
Sports	Europe	-3.876523500390405	Medium
Books	North America	-7.827767651270334	Low
Clothing	Europe	-10.615927245838476	Low
Books	Asia	-10.925159439061106	Low
Home & Kitchen	Europe	-11.661742223243884	Low
Toys	Australia	-16.513535278290007	Low
Beauty	North America	-16.85103723732836	Low
Clothing	South America	-19.052907332527315	Low
Clothing	Australia	-23.136320181930305	Low
Home & Kitchen	Asia	-30.534158149556397	Low
\.


--
-- Data for Name: sensitivity_with_volatility; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.sensitivity_with_volatility (product_category, region, sensitivity_coef, sensitivity_tier, volatility_score, total_units) FROM stdin;
Beauty	Asia	99.68759110172506	Very High	0.6701765855002106	214
Toys	North America	26.11799899817534	Very High	0.3540226842719647	203
Toys	Europe	23.250479906012156	Very High	0.530869333047081	201
Clothing	Asia	17.646850204942528	Very High	0.3900241271353079	216
Books	Australia	15.473349214464935	Very High	0.27889469652284915	154
Sports	Australia	14.26152208594307	Very High	0.3330510096695641	210
Electronics	Europe	9.610121792403925	Very High	0.5188705007644298	195
Home & Kitchen	North America	8.508209187024478	Very High	1.0723460935140532	151
Sports	South America	7.907827678844124	Very High	0.2244726450819028	204
Toys	South America	7.145231370847373	High	0.21037931860400894	258
Beauty	South America	6.641744872782683	High	0.5744371468670836	209
Home & Kitchen	Australia	4.741454540243703	High	0.20291125155906142	222
Clothing	North America	4.525148075947415	High	0.2120453310529135	203
Sports	North America	4.455436593896447	High	0.24250564491252086	151
Electronics	North America	4.281145649003752	High	0.21597971440693015	209
Books	South America	3.3580062477814123	High	0.5099134666834997	193
Books	Europe	1.9978110746682605	High	1.2138031449675224	148
Sports	Asia	1.4950616707728714	Medium	0.2430631562856328	236
Home & Kitchen	South America	0.605145593346522	Medium	0.2774931160594	145
Beauty	Europe	0.23021640109557306	Medium	0.7229452050690578	161
Electronics	South America	-0.29972345597356115	Medium	1.6153991762453825	196
Electronics	Australia	-0.7681883415825925	Medium	0.20059802173647012	240
Toys	Asia	-1.2966695702864388	Medium	0.17186871387166255	181
Electronics	Asia	-2.119831905866414	Medium	0.09526528918271793	251
Beauty	Australia	-2.773881211692215	Medium	0.1383173241298922	177
Sports	Europe	-3.876523500390405	Medium	0.2060649290416042	160
Books	North America	-7.827767651270334	Low	0.33723010165500644	192
Clothing	Europe	-10.615927245838476	Low	0.2740324476570514	272
Books	Asia	-10.925159439061106	Low	0.16674422129030872	214
Home & Kitchen	Europe	-11.661742223243884	Low	0.23833779620529108	206
Toys	Australia	-16.513535278290007	Low	0.2826936494158866	191
Beauty	North America	-16.85103723732836	Low	0.35957474415031854	114
Clothing	South America	-19.052907332527315	Low	0.38661702914333707	159
Clothing	Australia	-23.136320181930305	Low	0.4646635669083008	257
Home & Kitchen	Asia	-30.534158149556397	Low	0.6218346146539765	157
\.


--
-- Data for Name: what_if_simulation_value_results; Type: TABLE DATA; Schema: public; Owner: juma
--

COPY public.what_if_simulation_value_results (region, scenario, predicted_profit) FROM stdin;
Asia	-10% Value	832.5892545056715
Australia	-10% Value	925.7669382708917
Europe	-10% Value	728.5031485248296
North America	-10% Value	858.1989796784445
South America	-10% Value	1130.9619057963885
Asia	-10% Value	787.397868537455
Australia	-10% Value	896.6255980010978
Europe	-10% Value	831.2486203856226
North America	-10% Value	970.0099491750091
South America	-10% Value	1031.712265428269
Asia	-10% Value	917.3740848702184
Australia	-10% Value	1124.414694894413
Europe	-10% Value	732.438989670835
North America	-10% Value	992.6353289835727
South America	-10% Value	970.8911815496583
Asia	-10% Value	897.76112002933
Australia	-10% Value	989.2282770335505
Europe	-10% Value	863.9848281021746
North America	-10% Value	930.7201153751334
South America	-10% Value	703.5803302806735
Asia	-10% Value	920.2667492879403
Australia	-10% Value	832.9657740598753
Europe	-10% Value	1171.0990568391553
North America	-10% Value	786.845971621552
South America	-10% Value	1020.2424653682071
Asia	-10% Value	919.3046252653703
Australia	-10% Value	742.4844017781952
Europe	-10% Value	650.9042818601822
North America	-10% Value	888.0314658492126
South America	-10% Value	726.5809993491542
Asia	0% Change	939.2374635693578
Australia	0% Change	1042.5190939672952
Europe	0% Change	823.4456610315184
North America	0% Change	967.3421371591213
South America	0% Change	1270.6547186582563
Asia	0% Change	888.9655767116433
Australia	0% Change	1010.1032535725534
Europe	0% Change	937.6315143136969
North America	0% Change	1091.6243580542703
South America	0% Change	1160.3897305153264
Asia	0% Change	1033.3917624534085
Australia	0% Change	1263.1712525807666
Europe	0% Change	827.7804681570319
North America	0% Change	1116.8685878986469
South America	0% Change	1092.8085052292458
Asia	0% Change	1011.6088235925106
Australia	0% Change	1112.970615914227
Europe	0% Change	973.9695368863078
North America	0% Change	1047.9852245913607
South America	0% Change	795.8924751274968
Asia	0% Change	1036.6533758391147
Australia	0% Change	939.4175725667919
Europe	0% Change	1315.1457946940725
North America	0% Change	888.0478944383901
South America	0% Change	1147.6860691865888
Asia	0% Change	1035.5697460940978
Australia	0% Change	838.8347972935511
Europe	0% Change	737.2668338399792
North America	0% Change	1000.5693274846641
South America	0% Change	821.3970339699245
Asia	+10% Value	1045.8856726330441
Australia	+10% Value	1159.2712496636987
Europe	+10% Value	918.3881735382073
North America	+10% Value	1076.4852946397982
South America	+10% Value	1410.347531520124
Asia	+10% Value	990.5332848858317
Australia	+10% Value	1123.580909144009
Europe	+10% Value	1044.0144082417712
North America	+10% Value	1213.2387669335317
South America	+10% Value	1289.0671956023843
Asia	+10% Value	1149.4094400365984
Australia	+10% Value	1401.9278102671205
Europe	+10% Value	923.1219466432289
North America	+10% Value	1241.1018468137213
South America	+10% Value	1214.725828908834
Asia	+10% Value	1125.4565271556912
Australia	+10% Value	1236.7129547949035
Europe	+10% Value	1083.9542456704412
North America	+10% Value	1165.2503338075885
South America	+10% Value	888.2046199743202
Asia	+10% Value	1153.0400023902894
Australia	+10% Value	1045.8693710737086
Europe	+10% Value	1459.1925325489897
North America	+10% Value	989.2498172552284
South America	+10% Value	1275.1296730049708
Asia	+10% Value	1151.834866922826
Australia	+10% Value	935.1851928089072
Europe	+10% Value	823.6293858197761
North America	+10% Value	1113.1071891201154
South America	+10% Value	916.2130685906948
\.


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT ALL ON SCHEMA public TO juma;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO juma;


--
-- PostgreSQL database dump complete
--

