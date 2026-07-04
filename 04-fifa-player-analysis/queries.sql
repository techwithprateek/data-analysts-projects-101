-- FIFA 21 Player Performance Analysis — DuckDB queries
--
-- Convention: each query is a named block delimited by `-- name: <name>`.
-- db.py parses this file and exposes each block as `run_query("<name>")`.
--
-- Table available: `players` (loaded from data/players_21.csv)
--
-- Goalkeepers don't have pace/shooting/passing/dribbling/defending/physic
-- (they have gk_* stats instead), so every outfield-attribute query filters
-- WHERE pace IS NOT NULL to exclude them.
--
-- `player_positions` is comma-separated (e.g. "RW, ST, CF"), same pattern
-- as the Cuisines column in the Zomato project — UNNEST(string_split(...))
-- explodes it into one row per position.

-- name: attribute_value_correlations
-- How strongly does each outfield attribute correlate with market value?
SELECT
    ROUND(CORR(pace, value_eur), 3) AS pace_corr,
    ROUND(CORR(shooting, value_eur), 3) AS shooting_corr,
    ROUND(CORR(passing, value_eur), 3) AS passing_corr,
    ROUND(CORR(dribbling, value_eur), 3) AS dribbling_corr,
    ROUND(CORR(defending, value_eur), 3) AS defending_corr,
    ROUND(CORR(physic, value_eur), 3) AS physic_corr,
    ROUND(CORR(overall, value_eur), 3) AS overall_corr,
    ROUND(CORR(potential, value_eur), 3) AS potential_corr,
    ROUND(CORR(age, value_eur), 3) AS age_corr
FROM players
WHERE pace IS NOT NULL;

-- name: value_by_position
-- Explodes player_positions (a player listed as "RW, ST, CF" counts toward
-- all 3) and aggregates value/wage/overall per position.
WITH exploded AS (
    SELECT
        TRIM(pos) AS position,
        overall,
        value_eur,
        wage_eur
    FROM players, UNNEST(string_split(player_positions, ',')) AS t(pos)
    WHERE value_eur IS NOT NULL
)
SELECT
    position,
    COUNT(*) AS player_count,
    ROUND(AVG(overall), 1) AS avg_overall,
    ROUND(AVG(value_eur), 0) AS avg_value_eur,
    ROUND(AVG(wage_eur), 0) AS avg_wage_eur
FROM exploded
GROUP BY position
ORDER BY avg_value_eur DESC;

-- name: roi_by_position
-- A simple "value per overall point" metric — which positions carry the
-- highest market value relative to their skill rating (a rough proxy for
-- where transfer-market ROI concentrates).
WITH exploded AS (
    SELECT
        TRIM(pos) AS position,
        overall,
        value_eur
    FROM players, UNNEST(string_split(player_positions, ',')) AS t(pos)
    WHERE value_eur IS NOT NULL AND overall > 0
)
SELECT
    position,
    COUNT(*) AS player_count,
    ROUND(AVG(value_eur / overall), 0) AS avg_value_per_overall_point
FROM exploded
GROUP BY position
HAVING COUNT(*) >= 30
ORDER BY avg_value_per_overall_point DESC;

-- name: league_pay_vs_performance
-- Which leagues pay the most relative to the talent level they field?
SELECT
    league_name,
    COUNT(*) AS player_count,
    ROUND(AVG(overall), 1) AS avg_overall,
    ROUND(AVG(wage_eur), 0) AS avg_wage_eur,
    ROUND(AVG(wage_eur) / NULLIF(AVG(overall), 0), 0) AS wage_per_overall_point
FROM players
WHERE league_name IS NOT NULL AND wage_eur IS NOT NULL
GROUP BY league_name
HAVING COUNT(*) >= 100
ORDER BY wage_per_overall_point DESC
LIMIT 20;

-- name: age_curve
-- Average overall rating and market value by age — the classic
-- rise-then-decline shape of a footballer's career.
SELECT
    age,
    COUNT(*) AS player_count,
    ROUND(AVG(overall), 1) AS avg_overall,
    ROUND(AVG(potential), 1) AS avg_potential,
    ROUND(AVG(value_eur), 0) AS avg_value_eur
FROM players
WHERE age BETWEEN 16 AND 40
GROUP BY age
ORDER BY age;

-- name: top_valuable_by_position
-- Parameterized: top players by market value for a given primary position
-- ($position), used by the scouting dashboard.
SELECT
    short_name,
    age,
    club_name,
    league_name,
    overall,
    potential,
    value_eur,
    wage_eur
FROM players
WHERE team_position = $position
ORDER BY value_eur DESC
LIMIT 20;

-- name: position_options
-- Powers the position dropdown filter — team_position is a single value
-- per player (unlike the multi-valued player_positions), so it's a clean
-- filter without needing to explode anything.
SELECT DISTINCT team_position AS position
FROM players
WHERE team_position IS NOT NULL AND team_position != ''
ORDER BY position;

-- name: filtered_scouting
-- Parameterized query behind the dashboard's scouting explorer: filter by
-- position, minimum potential, and maximum value.
SELECT
    short_name,
    age,
    club_name,
    league_name,
    team_position,
    overall,
    potential,
    value_eur,
    wage_eur
FROM players
WHERE ($position IS NULL OR team_position = $position)
  AND ($min_potential IS NULL OR potential >= $min_potential)
  AND ($max_value IS NULL OR value_eur <= $max_value)
ORDER BY potential DESC, value_eur ASC
LIMIT 200;
