-- Supply Chain & Inventory Analysis (DataCo dataset) — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`,
-- so both analysis.ipynb and app.py call these exact same queries.
--
-- Table available: `orders` (loaded from data/DataCoSupplyChainDataset.csv,
-- with customer PII columns like email/password/name deliberately excluded
-- at load time in db.py — good practice even on a synthetic Kaggle dataset).
--
-- Note: this dataset has no on-hand-inventory / stock-level column, so the
-- "reorder alert" query approximates reorder risk with a demand x lead-time
-- "replenishment burden" score rather than comparing against real stock —
-- see the query comment below for the full reasoning.

-- name: late_shipment_by_mode
-- The doc's headline query: late-delivery rate and average delay by
-- shipping mode.
SELECT
    "Shipping Mode" AS shipping_mode,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) AS late_orders,
    ROUND(SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS late_pct,
    ROUND(AVG("Days for shipping (real)" - "Days for shipment (scheduled)"), 2) AS avg_delay_days
FROM orders
GROUP BY 1
ORDER BY late_pct DESC;

-- name: late_shipment_by_region
-- Regional x shipping-mode late-delivery heatmap data.
SELECT
    "Order Region" AS region,
    "Shipping Mode" AS shipping_mode,
    COUNT(*) AS total_orders,
    ROUND(SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS late_pct
FROM orders
GROUP BY 1, 2
HAVING COUNT(*) >= 50
ORDER BY late_pct DESC;

-- name: reorder_risk_by_product
-- This dataset doesn't include an on-hand stock column, so a literal
-- "(avg daily demand x lead time) > current stock" alert isn't computable.
-- Instead this approximates *reorder risk* with a replenishment-burden
-- score (avg order quantity x avg lead time in days) and ranks products
-- into risk quartiles with NTILE — the highest-burden quartile is the one
-- that would need the tightest reorder-point monitoring in a real system.
WITH product_demand AS (
    SELECT
        "Product Name" AS product_name,
        "Category Name" AS category_name,
        COUNT(*) AS order_count,
        ROUND(AVG("Order Item Quantity"), 2) AS avg_order_quantity,
        ROUND(AVG("Days for shipping (real)"), 2) AS avg_lead_time_days,
        ROUND(AVG("Order Item Quantity") * AVG("Days for shipping (real)"), 2) AS replenishment_burden
    FROM orders
    GROUP BY 1, 2
    HAVING COUNT(*) >= 30
)
SELECT
    *,
    NTILE(4) OVER (ORDER BY replenishment_burden DESC) AS risk_quartile
FROM product_demand
ORDER BY replenishment_burden DESC
LIMIT 25;

-- name: market_reliability
-- The dataset has no distinct "supplier" entity, so this uses Market
-- (DataCo's fulfillment region: LATAM, Europe, Pacific Asia, USCA, Africa)
-- as the stand-in "supplier" for a reliability-scoring exercise: on-time
-- rate, average profit margin, and order-volume consistency.
WITH market_orders AS (
    SELECT
        Market AS market,
        "Order Region" AS region,
        Late_delivery_risk,
        "Order Item Profit Ratio" AS profit_ratio
    FROM orders
)
SELECT
    market,
    COUNT(*) AS total_orders,
    ROUND(100.0 - SUM(CASE WHEN Late_delivery_risk = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS on_time_pct,
    ROUND(AVG(profit_ratio), 3) AS avg_profit_ratio,
    COUNT(DISTINCT region) AS regions_served
FROM market_orders
GROUP BY market
ORDER BY on_time_pct DESC;

-- name: rfm_analysis
-- Recency (days since last order), Frequency (distinct order dates),
-- Monetary (total spend) per customer, each scored into quartiles with
-- NTILE — quartile 4 is always "best" for that dimension (most recent,
-- most frequent, highest spend) so the three scores are directly
-- comparable and summable into a combined RFM score.
WITH customer_orders AS (
    SELECT
        "Order Customer Id" AS customer_id,
        CAST(strptime("order date (DateOrders)", '%-m/%-d/%Y %H:%M') AS DATE) AS order_date,
        "Order Item Total" AS order_total
    FROM orders
),
max_date AS (SELECT MAX(order_date) AS d FROM customer_orders),
customer_agg AS (
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_date) AS frequency,
        ROUND(SUM(order_total), 2) AS monetary
    FROM customer_orders
    GROUP BY customer_id
),
scored AS (
    SELECT
        c.customer_id,
        DATE_DIFF('day', c.last_order_date, m.d) AS recency_days,
        c.frequency,
        c.monetary,
        NTILE(4) OVER (ORDER BY DATE_DIFF('day', c.last_order_date, m.d) DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY c.frequency ASC) AS frequency_score,
        NTILE(4) OVER (ORDER BY c.monetary ASC) AS monetary_score
    FROM customer_agg c
    CROSS JOIN max_date m
)
SELECT
    *,
    recency_score + frequency_score + monetary_score AS rfm_score,
    CASE
        WHEN recency_score + frequency_score + monetary_score >= 10 THEN 'Champions'
        WHEN recency_score + frequency_score + monetary_score >= 7 THEN 'Loyal'
        WHEN recency_score + frequency_score + monetary_score >= 4 THEN 'At Risk'
        ELSE 'Lost'
    END AS segment
FROM scored
ORDER BY rfm_score DESC;

-- name: rfm_segment_summary
-- Rollup of the RFM segmentation above — how many customers per segment,
-- and how much revenue each segment represents.
WITH customer_orders AS (
    SELECT
        "Order Customer Id" AS customer_id,
        CAST(strptime("order date (DateOrders)", '%-m/%-d/%Y %H:%M') AS DATE) AS order_date,
        "Order Item Total" AS order_total
    FROM orders
),
max_date AS (SELECT MAX(order_date) AS d FROM customer_orders),
customer_agg AS (
    SELECT
        customer_id,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_date) AS frequency,
        ROUND(SUM(order_total), 2) AS monetary
    FROM customer_orders
    GROUP BY customer_id
),
scored AS (
    SELECT
        c.customer_id,
        c.monetary,
        NTILE(4) OVER (ORDER BY DATE_DIFF('day', c.last_order_date, m.d) DESC) AS recency_score,
        NTILE(4) OVER (ORDER BY c.frequency ASC) AS frequency_score,
        NTILE(4) OVER (ORDER BY c.monetary ASC) AS monetary_score
    FROM customer_agg c
    CROSS JOIN max_date m
),
segmented AS (
    SELECT
        *,
        CASE
            WHEN recency_score + frequency_score + monetary_score >= 10 THEN 'Champions'
            WHEN recency_score + frequency_score + monetary_score >= 7 THEN 'Loyal'
            WHEN recency_score + frequency_score + monetary_score >= 4 THEN 'At Risk'
            ELSE 'Lost'
        END AS segment
    FROM scored
)
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(AVG(monetary), 2) AS avg_revenue_per_customer
FROM segmented
GROUP BY segment
ORDER BY total_revenue DESC;

-- name: category_options
-- Powers the category dropdown filter in the Streamlit dashboard.
SELECT DISTINCT "Category Name" AS category
FROM orders
ORDER BY category;

-- name: filtered_late_shipments
-- Parameterized query behind the dashboard's shipment explorer.
SELECT
    "Order Id" AS order_id,
    "Category Name" AS category,
    "Order Region" AS region,
    "Shipping Mode" AS shipping_mode,
    "Days for shipping (real)" AS days_actual,
    "Days for shipment (scheduled)" AS days_scheduled,
    Late_delivery_risk AS late_delivery_risk,
    Sales AS sales
FROM orders
WHERE Late_delivery_risk = 1
  AND ($category IS NULL OR "Category Name" = $category)
ORDER BY "Days for shipping (real)" - "Days for shipment (scheduled)" DESC
LIMIT 200;
