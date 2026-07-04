"""Tiny DuckDB helper shared by analysis.ipynb and app.py.

This is the single place that knows how the DataCo supply chain data gets
loaded and how queries.sql gets parsed. Both the notebook and the Streamlit
dashboard call `run_query()` against the exact same SQL.
"""
from pathlib import Path

import duckdb
import pandas as pd

DATA_DIR = Path(__file__).parent / "data"
QUERIES_FILE = Path(__file__).parent / "queries.sql"
CSV_FILE = DATA_DIR / "DataCoSupplyChainDataset.csv"

# Columns deliberately left out of the loaded table: this dataset ships
# fabricated but PII-shaped customer fields (email, name, password, street
# address). None of the analysis needs them, so they're excluded at load
# time rather than trusted-and-ignored — worth doing even on a synthetic
# teaching dataset, as the habit matters more than this particular file.
_EXCLUDED_COLUMNS = [
    "Customer Email",
    "Customer Fname",
    "Customer Lname",
    "Customer Password",
    "Customer Street",
    "Customer Zipcode",
    "Order Zipcode",
    "Product Image",
    "Product Description",
]


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
    """Open an in-memory DuckDB connection with the orders table loaded.

    Callers should hold onto the returned connection and reuse it across
    multiple run_query() calls — the CSV load (180k rows) is the expensive
    part, not the queries.
    """
    con = duckdb.connect(database=":memory:")

    # DuckDB's own CSV reader rejects this file's encoding (it's
    # Windows-1252, not clean latin-1/UTF-8), so pandas reads it and
    # DuckDB registers the resulting DataFrame as a table instead.
    orders = pd.read_csv(CSV_FILE, encoding="latin-1")
    orders = orders.drop(columns=_EXCLUDED_COLUMNS)
    con.register("orders", orders)
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
