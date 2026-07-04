"""Tiny DuckDB helper shared by analysis.ipynb and app.py.

Unlike the other projects in this repo, this one connects to a *persisted*
DuckDB file (data/olist.duckdb) built ahead of time by load_to_duckdb.py,
rather than loading CSVs into an in-memory database on every run — this is
the doc's suggested ETL pattern for this project specifically ("load all
CSVs into DuckDB using a short Python script").
"""
from pathlib import Path

import duckdb
import pandas as pd

DATA_DIR = Path(__file__).parent / "data"
QUERIES_FILE = Path(__file__).parent / "queries.sql"
DB_FILE = DATA_DIR / "olist.duckdb"


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
    """Open a read-only connection to the pre-built olist.duckdb file.

    Run `python download_data.py` then `python load_to_duckdb.py` once
    before this will find a file to connect to.
    """
    if not DB_FILE.exists():
        raise FileNotFoundError(
            f"{DB_FILE} not found. Run `python download_data.py` and then "
            "`python load_to_duckdb.py` first."
        )
    return duckdb.connect(str(DB_FILE), read_only=True)


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
