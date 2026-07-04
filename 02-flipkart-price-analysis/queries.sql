-- Flipkart Product Price Analysis — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`,
-- so both analysis.ipynb and app.py call these exact same queries.
--
-- Table available: `products` (loaded from data/flipkart_com-ecommerce_sample.csv)
--
-- `product_category_tree` arrives as a single string like
-- '["Clothing >> Women\'s Clothing >> Lingerie ... "]' — every query that
-- needs a category pulls out just the top-level segment with
-- TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)).

-- name: category_overview
-- Category profitability at a glance: how many products, average list
-- price, average discounted price, average discount %.
WITH categorized AS (
    SELECT
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category,
        retail_price,
        discounted_price,
        CASE WHEN retail_price > 0
             THEN ROUND((retail_price - discounted_price) / retail_price * 100, 1)
        END AS discount_pct
    FROM products
    WHERE retail_price IS NOT NULL AND discounted_price IS NOT NULL
)
SELECT
    category,
    COUNT(*) AS product_count,
    ROUND(AVG(retail_price), 2) AS avg_retail_price,
    ROUND(AVG(discounted_price), 2) AS avg_discounted_price,
    ROUND(AVG(discount_pct), 2) AS avg_discount_pct
FROM categorized
GROUP BY category
ORDER BY product_count DESC
LIMIT 20;

-- name: category_price_percentiles
-- The doc's headline SQL concept: PERCENTILE_CONT for price distributions,
-- restricted to categories with at least 50 products so percentiles are
-- meaningful rather than noise from a handful of listings.
WITH categorized AS (
    SELECT
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category,
        retail_price
    FROM products
    WHERE retail_price IS NOT NULL AND retail_price > 0
)
SELECT
    category,
    COUNT(*) AS product_count,
    ROUND(AVG(retail_price), 2) AS avg_price,
    ROUND(MEDIAN(retail_price), 2) AS median_price,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY retail_price), 2) AS q1,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY retail_price), 2) AS q3,
    ROUND(MAX(retail_price) - MIN(retail_price), 2) AS price_range
FROM categorized
GROUP BY category
HAVING COUNT(*) >= 50
ORDER BY product_count DESC
LIMIT 15;

-- name: price_tier_binning
-- CASE WHEN for price binning/tiering, one of the doc's named SQL concepts.
WITH tiered AS (
    SELECT
        CASE
            WHEN retail_price < 500 THEN '1. Budget (<500)'
            WHEN retail_price < 2000 THEN '2. Mid (500-2000)'
            WHEN retail_price < 10000 THEN '3. Premium (2000-10000)'
            ELSE '4. Luxury (10000+)'
        END AS price_tier,
        retail_price,
        CASE WHEN retail_price > 0
             THEN (retail_price - discounted_price) / retail_price * 100
        END AS discount_pct
    FROM products
    WHERE retail_price IS NOT NULL AND discounted_price IS NOT NULL
)
SELECT
    price_tier,
    COUNT(*) AS product_count,
    ROUND(AVG(retail_price), 2) AS avg_retail_price,
    ROUND(AVG(discount_pct), 2) AS avg_discount_pct
FROM tiered
GROUP BY price_tier
ORDER BY price_tier;

-- name: top_discounted_products
-- Window function for ranking products within category — RANK() OVER
-- (PARTITION BY category ...) surfaces the 3 deepest discounts per
-- category, which a plain ORDER BY + LIMIT can't do per-group.
WITH categorized AS (
    SELECT
        product_name,
        brand,
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category,
        retail_price,
        discounted_price,
        CASE WHEN retail_price > 0
             THEN ROUND((retail_price - discounted_price) / retail_price * 100, 1)
        END AS discount_pct
    FROM products
    WHERE retail_price > 0 AND discounted_price IS NOT NULL
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY category ORDER BY discount_pct DESC) AS rank_in_category
    FROM categorized
)
SELECT category, product_name, brand, retail_price, discounted_price, discount_pct
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, discount_pct DESC;

-- name: brand_pricing
-- Competitor-style analysis: which brands have the most listings, and how
-- are they priced relative to each other?
SELECT
    brand,
    COUNT(*) AS product_count,
    ROUND(AVG(retail_price), 2) AS avg_retail_price,
    ROUND(AVG(discounted_price), 2) AS avg_discounted_price
FROM products
WHERE brand IS NOT NULL AND retail_price IS NOT NULL
GROUP BY brand
HAVING COUNT(*) >= 30
ORDER BY product_count DESC
LIMIT 20;

-- name: discount_vs_rating_correlation
-- Only ~9% of listings have a numeric product_rating (the rest are
-- "No rating available"), so TRY_CAST silently drops the non-numeric ones
-- rather than erroring — this correlation is directional, not definitive,
-- given the small rated sample.
WITH rated AS (
    SELECT
        TRY_CAST(product_rating AS DOUBLE) AS rating,
        CASE WHEN retail_price > 0
             THEN (retail_price - discounted_price) / retail_price * 100
        END AS discount_pct
    FROM products
    WHERE TRY_CAST(product_rating AS DOUBLE) IS NOT NULL AND retail_price > 0
)
SELECT
    ROUND(CORR(discount_pct, rating), 3) AS discount_vs_rating_corr,
    COUNT(*) AS rated_product_count
FROM rated;

-- name: price_outliers
-- Market-gap / outlier detection: products priced at 10x+ their category's
-- median — either a data-entry error or a genuine premium-tier gap.
WITH categorized AS (
    SELECT
        product_name,
        brand,
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category,
        retail_price
    FROM products
    WHERE retail_price > 0
),
cat_stats AS (
    SELECT category, MEDIAN(retail_price) AS median_price
    FROM categorized
    GROUP BY category
    HAVING COUNT(*) >= 20
)
SELECT
    c.category,
    c.product_name,
    c.brand,
    c.retail_price,
    s.median_price,
    ROUND(c.retail_price / s.median_price, 1) AS x_median
FROM categorized c
JOIN cat_stats s USING (category)
WHERE c.retail_price > s.median_price * 10
ORDER BY x_median DESC
LIMIT 20;

-- name: category_options
-- Powers the category dropdown filter in the Streamlit dashboard.
WITH categorized AS (
    SELECT
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category
    FROM products
)
SELECT category, COUNT(*) AS product_count
FROM categorized
WHERE category IS NOT NULL AND category != ''
GROUP BY category
HAVING COUNT(*) >= 20
ORDER BY product_count DESC;

-- name: filtered_products
-- Parameterized query behind the dashboard's product explorer table.
WITH categorized AS (
    SELECT
        product_name,
        brand,
        TRIM(SPLIT_PART(TRIM(product_category_tree, '["]'), '>>', 1)) AS category,
        retail_price,
        discounted_price,
        CASE WHEN retail_price > 0
             THEN ROUND((retail_price - discounted_price) / retail_price * 100, 1)
        END AS discount_pct
    FROM products
    WHERE retail_price IS NOT NULL
)
SELECT *
FROM categorized
WHERE ($category IS NULL OR category = $category)
  AND ($max_price IS NULL OR retail_price <= $max_price)
ORDER BY discount_pct DESC NULLS LAST
LIMIT 200;
