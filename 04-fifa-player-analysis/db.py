"""Tiny DuckDB helper shared by analysis.ipynb and app.py.

This is the single place that knows how the FIFA 21 player data gets loaded
and how queries.sql gets parsed. Both the notebook and the Streamlit
dashboard call `run_query()` against the exact same SQL. The one exception
is the KMeans player-archetype clustering, which lives in pandas/sklearn in
the notebook (and is re-run, cached, in app.py) — SQL isn't the right tool
for that step.
"""
from pathlib import Path

import duckdb
import pandas as pd

DATA_DIR = Path(__file__).parent / "data"
QUERIES_FILE = Path(__file__).parent / "queries.sql"
CSV_FILE = DATA_DIR / "players_21.csv"


def _load_queries() -> dict[str, str]:
    """Parse queries.sql into {name: sql} using `-- name: <name>` markers."""
    queries: dict[str, str] = {}
    name = None
    buf: list[str] = []
    for line in QUERIES_FILE.read_text().splitlines():
        if line.strip().startswith("-- name:"):
            if name:
                queries[name] = "\n".join(buf).strip()
            name = line.split("-- name:", 1)[1].strip()
            buf = []
        elif name is not None:
            buf.append(line)
    if name:
        queries[name] = "\n".join(buf).strip()
    return queries


_QUERIES = _load_queries()


def get_connection() -> duckdb.DuckDBPyConnection:
    """Open an in-memory DuckDB connection with the players table loaded.

    Callers should hold onto the returned connection and reuse it across
    multiple run_query() calls rather than reopening it each time.
    """
    con = duckdb.connect(database=":memory:")
    con.execute(f"""
        CREATE TABLE players AS
        SELECT *
        FROM read_csv_auto('{CSV_FILE.as_posix()}')
    """)
    return con


def run_query(
    name: str,
    con: duckdb.DuckDBPyConnection | None = None,
    **params,
) -> pd.DataFrame:
    """Run a named query from queries.sql and return the result as a DataFrame."""
    owns_connection = con is None
    con = con or get_connection()
    sql = _QUERIES[name]
    try:
        if params:
            return con.execute(sql, params).df()
        return con.execute(sql).df()
    finally:
        if owns_connection:
            con.close()


def list_query_names() -> list[str]:
    return list(_QUERIES.keys())
