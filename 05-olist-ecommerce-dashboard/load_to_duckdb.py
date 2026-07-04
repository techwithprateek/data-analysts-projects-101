"""Load the 9 raw Olist CSVs into a single DuckDB file (data/olist.duckdb).

This is the ETL step the doc calls for: "Load all CSVs into DuckDB using a
short Python script." Everything downstream (analysis.ipynb, app.py, and
every query in queries.sql) reads from this one file instead of re-parsing
CSVs on every run.

Usage:
    python download_data.py   # first, to populate ./data/ with the raw CSVs
    python load_to_duckdb.py  # then, to build data/olist.duckdb
"""
from pathlib import Path

import duckdb

DATA_DIR = Path(__file__).parent / "data"
DB_FILE = DATA_DIR / "olist.duckdb"

# table_name -> source CSV
TABLES = {
    "orders": "olist_orders_dataset.csv",
    "customers": "olist_customers_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "order_payments": "olist_order_payments_dataset.csv",
    "order_reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}


def main() -> None:
    if DB_FILE.exists():
        DB_FILE.unlink()

    con = duckdb.connect(str(DB_FILE))
    for table, csv_name in TABLES.items():
        csv_path = DATA_DIR / csv_name
        print(f"Loading {csv_name} -> {table}")
        con.execute(f"""
            CREATE TABLE {table} AS
            SELECT * FROM read_csv_auto('{csv_path.as_posix()}')
        """)
        count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {count:,} rows")
    con.close()
    print(f"\nDone. {DB_FILE} is ready.")


if __name__ == "__main__":
    main()
