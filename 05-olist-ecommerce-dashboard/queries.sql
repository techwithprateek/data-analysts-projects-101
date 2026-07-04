-- Olist E-Commerce Sales Dashboard — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`.
--
-- Tables available (see load_to_duckdb.py): orders, customers, order_items,
-- order_payments, order_reviews, products, sellers, geolocation,
-- category_translation.
--
-- Important schema note: `customer_id` is generated per-order in this
-- dataset (a customer gets a new one every time they order); the stable,
-- repeat-purchase-tracking identifier is `customer_unique_id` on the
-- customers table. Every retention/CLV/repeat-purchase query below joins
-- through `customer_unique_id`, not `customer_id`.

-- name: kpi_summary
-- Headline KPIs: total revenue, orders, customers, average order value.
SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS total_customers,
    ROUND(SUM(op.payment_value), 2) AS total_revenue,
    ROUND(SUM(op.payment_value) / COUNT(DISTINCT o.order_id), 2) AS avg_order_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered';

-- name: monthly_revenue_growth
-- The doc's headline query: month-over-month revenue growth via LAG().
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS month,
        SUM(op.payment_value) AS revenue,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT o.customer_id) AS unique_customers
    FROM orders o
    JOIN order_payments op ON o.order_id = op.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    order_count,
    unique_customers,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month) * 100, 1
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month;

-- name: top_categories
-- Best-selling categories by revenue, joined through the English category
-- name translation table (the raw category names are Portuguese).
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(DISTINCT oi.order_id) AS orders,
    COUNT(oi.order_item_id) AS items_sold,
    ROUND(SUM(oi.price), 2) AS revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(AVG(r.review_score), 2) AS avg_rating
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN order_reviews r ON oi.order_id = r.order_id
GROUP BY 1
ORDER BY revenue DESC
LIMIT 20;

-- name: order_fulfillment_summary
-- Overall delivery performance: average delivery time, and how it compares
-- to Olist's own estimated delivery date.
SELECT
    ROUND(AVG(DATE_DIFF('day', order_purchase_timestamp, order_delivered_customer_date)), 2) AS avg_delivery_days,
    ROUND(AVG(DATE_DIFF('day', order_delivered_customer_date, order_estimated_delivery_date)), 2) AS avg_days_before_estimate,
    ROUND(
        SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2
    ) AS late_pct
FROM orders
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- name: regional_fulfillment
-- Delivery time and late-delivery rate by customer state.
SELECT
    c.customer_state AS state,
    COUNT(*) AS order_count,
    ROUND(AVG(DATE_DIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date)), 2) AS avg_delivery_days,
    ROUND(
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0
        / COUNT(*), 2
    ) AS late_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 30
ORDER BY late_pct DESC;

-- name: repeat_purchase_rate
-- What fraction of customers (by customer_unique_id, the stable identifier)
-- ever placed more than one order?
WITH customer_order_counts AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS repeat_purchase_rate_pct
FROM customer_order_counts;

-- name: monthly_cohort_retention
-- Classic cohort-retention table: group customers by the month of their
-- first order (cohort_month), then for every subsequent order compute
-- month_index = months since that first order. Pivoting this in pandas
-- gives the familiar cohort-retention triangle.
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohorts AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    co.cohort_month,
    DATE_DIFF('month', co.cohort_month, cust.order_month) AS month_index,
    COUNT(DISTINCT cust.customer_unique_id) AS active_customers
FROM cohorts co
JOIN customer_orders cust ON co.customer_unique_id = cust.customer_unique_id
GROUP BY co.cohort_month, month_index
ORDER BY co.cohort_month, month_index;

-- name: top_customers_by_ltv
-- Highest lifetime-value customers (by customer_unique_id).
SELECT
    c.customer_unique_id,
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS order_count,
    ROUND(SUM(op.payment_value), 2) AS lifetime_value
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN order_payments op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id, c.customer_state
ORDER BY lifetime_value DESC
LIMIT 20;

-- name: payment_type_breakdown
SELECT
    payment_type,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(payment_value), 2) AS total_revenue,
    ROUND(AVG(payment_installments), 2) AS avg_installments
FROM order_payments
GROUP BY payment_type
ORDER BY total_revenue DESC;

-- name: category_options
-- Powers the category dropdown filter in the Streamlit dashboard.
SELECT DISTINCT COALESCE(t.product_category_name_english, p.product_category_name) AS category
FROM products p
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
ORDER BY category;

-- name: filtered_products
-- Parameterized query behind the dashboard's category explorer.
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name) AS category,
    COUNT(oi.order_item_id) AS items_sold,
    ROUND(SUM(oi.price), 2) AS revenue,
    ROUND(AVG(r.review_score), 2) AS avg_rating
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN category_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN order_reviews r ON oi.order_id = r.order_id
WHERE ($category IS NULL OR COALESCE(t.product_category_name_english, p.product_category_name) = $category)
GROUP BY 1, 2
ORDER BY revenue DESC
LIMIT 200;
