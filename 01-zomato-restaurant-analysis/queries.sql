-- Zomato Restaurant Data Analysis — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`,
-- so both analysis.ipynb and app.py call these exact same queries — no
-- SQL logic ever gets duplicated between the notebook and the dashboard.
--
-- Table available: `restaurants` (loaded straight from data/zomato.csv)
-- Lookup table:     `country_codes` (loaded from data/Country-Code.xlsx)

-- name: restaurants_per_country
-- Geographic distribution at the country level. The raw dataset only has a
-- numeric Country Code, so this is a straightforward join against the
-- lookup table Kaggle ships alongside it.
SELECT
    cc.Country AS country,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(r."Aggregate rating") FILTER (WHERE r."Aggregate rating" > 0), 2) AS avg_rating,
    ROUND(AVG(r."Average Cost for two"), 2) AS avg_cost_for_two
FROM restaurants r
JOIN country_codes cc ON r."Country Code" = cc."Country Code"
GROUP BY cc.Country
ORDER BY restaurant_count DESC;

-- name: top_cities_by_count
-- Restaurant density by city — most of the dataset is actually Indian
-- cities, so this doubles as "where is this dataset really concentrated".
SELECT
    City AS city,
    COUNT(*) AS restaurant_count,
    ROUND(AVG("Aggregate rating") FILTER (WHERE "Aggregate rating" > 0), 2) AS avg_rating,
    ROUND(AVG("Average Cost for two"), 2) AS avg_cost_for_two
FROM restaurants
GROUP BY City
ORDER BY restaurant_count DESC
LIMIT 20;

-- name: top_cuisines_by_count
-- Cuisines are stored as a comma-separated string in one column
-- (e.g. "French, Japanese, Desserts"), so a restaurant serving 3 cuisines
-- needs to count toward all 3. UNNEST(string_split(...)) explodes that
-- single row into one row per cuisine before we aggregate — a pattern
-- worth knowing any time a column secretly holds a list.
WITH exploded AS (
    SELECT TRIM(cuisine) AS cuisine
    FROM restaurants, UNNEST(string_split(Cuisines, ',')) AS t(cuisine)
    WHERE Cuisines IS NOT NULL
)
SELECT
    cuisine,
    COUNT(*) AS restaurant_count
FROM exploded
GROUP BY cuisine
ORDER BY restaurant_count DESC
LIMIT 20;

-- name: top_cuisines_by_rating
-- Same explode technique, but ranked by average rating instead of count.
-- HAVING COUNT(*) >= 20 filters out cuisines with only 1-2 restaurants,
-- where a single 5-star review would otherwise dominate the ranking.
WITH exploded AS (
    SELECT TRIM(cuisine) AS cuisine, "Aggregate rating" AS rating
    FROM restaurants, UNNEST(string_split(Cuisines, ',')) AS t(cuisine)
    WHERE Cuisines IS NOT NULL AND "Aggregate rating" > 0
)
SELECT
    cuisine,
    COUNT(*) AS restaurant_count,
    ROUND(AVG(rating), 2) AS avg_rating
FROM exploded
GROUP BY cuisine
HAVING COUNT(*) >= 20
ORDER BY avg_rating DESC
LIMIT 20;

-- name: cost_rating_correlation
-- DuckDB's built-in CORR() aggregate gives the Pearson correlation
-- coefficient directly in SQL — no need to pull data into pandas just to
-- call .corr(). Unrated restaurants (rating == 0, meaning "not yet rated",
-- not "rated zero") are excluded so they don't distort the correlation.
SELECT
    ROUND(CORR("Average Cost for two", "Aggregate rating"), 3) AS cost_vs_rating,
    ROUND(CORR("Price range", "Aggregate rating"), 3) AS price_range_vs_rating
FROM restaurants
WHERE "Aggregate rating" > 0;

-- name: rating_by_price_range
-- Price range is already bucketed 1-4 in the source data (cheap -> expensive).
SELECT
    "Price range" AS price_range,
    COUNT(*) AS restaurant_count,
    ROUND(AVG("Aggregate rating") FILTER (WHERE "Aggregate rating" > 0), 2) AS avg_rating,
    ROUND(AVG("Average Cost for two"), 2) AS avg_cost_for_two
FROM restaurants
GROUP BY "Price range"
ORDER BY price_range;

-- name: rating_distribution
-- Rating text ("Excellent", "Very Good", ...) is Zomato's own bucketing of
-- the numeric rating — useful for a distribution chart on the dashboard.
SELECT
    "Rating text" AS rating_text,
    COUNT(*) AS restaurant_count,
    ROUND(AVG("Aggregate rating"), 2) AS avg_rating
FROM restaurants
WHERE "Aggregate rating" > 0
GROUP BY "Rating text"
ORDER BY avg_rating DESC;

-- name: best_value_restaurants
-- "Value" here = rating per rupee/dollar spent. NULLIF guards the division
-- against the handful of rows with Average Cost for two == 0.
SELECT
    "Restaurant Name" AS restaurant_name,
    City AS city,
    Cuisines AS cuisines,
    "Average Cost for two" AS cost_for_two,
    "Aggregate rating" AS rating,
    ROUND("Aggregate rating" / NULLIF("Average Cost for two", 0) * 1000, 3) AS value_score
FROM restaurants
WHERE "Aggregate rating" >= 4.0 AND "Average Cost for two" > 0
ORDER BY value_score DESC
LIMIT 20;

-- name: online_delivery_impact
-- Does offering online delivery correlate with higher ratings / more votes?
SELECT
    "Has Online delivery" AS has_online_delivery,
    COUNT(*) AS restaurant_count,
    ROUND(AVG("Aggregate rating") FILTER (WHERE "Aggregate rating" > 0), 2) AS avg_rating,
    ROUND(AVG(Votes), 1) AS avg_votes
FROM restaurants
GROUP BY "Has Online delivery";

-- name: table_booking_impact
SELECT
    "Has Table booking" AS has_table_booking,
    COUNT(*) AS restaurant_count,
    ROUND(AVG("Aggregate rating") FILTER (WHERE "Aggregate rating" > 0), 2) AS avg_rating,
    ROUND(AVG("Average Cost for two"), 2) AS avg_cost_for_two
FROM restaurants
GROUP BY "Has Table booking";

-- name: city_options
-- Powers the city dropdown filter in the Streamlit dashboard.
SELECT DISTINCT City AS city
FROM restaurants
ORDER BY city;

-- name: filtered_restaurants
-- Parameterized query behind the dashboard's main table: $city and
-- $min_rating are bound from Streamlit widgets. Passing NULL for a
-- parameter means "don't filter on this".
SELECT
    "Restaurant Name" AS restaurant_name,
    City AS city,
    Cuisines AS cuisines,
    "Average Cost for two" AS cost_for_two,
    "Price range" AS price_range,
    "Aggregate rating" AS rating,
    Votes AS votes
FROM restaurants
WHERE ($city IS NULL OR City = $city)
  AND ($min_rating IS NULL OR "Aggregate rating" >= $min_rating)
ORDER BY rating DESC, votes DESC
LIMIT 200;
