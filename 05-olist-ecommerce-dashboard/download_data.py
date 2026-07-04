"""Download the Olist Brazilian E-Commerce dataset from Kaggle into ./data/.

One-time setup: get a Kaggle API token from https://www.kaggle.com/settings
(API -> Create New Token) and save it to ~/.kaggle/kaggle.json.

Usage:
    python download_data.py
    python load_to_duckdb.py   # then build the DuckDB file (see that script)
"""
from pathlib import Path

DATASET = "olistbr/brazilian-ecommerce"
DATA_DIR = Path(__file__).parent / "data"


def main() -> None:
    from kaggle.api.kaggle_api_extended import KaggleApi

    DATA_DIR.mkdir(exist_ok=True)
    api = KaggleApi()
    api.authenticate()

    print(f"Downloading '{DATASET}' into {DATA_DIR}/ ...")
    api.dataset_download_files(DATASET, path=str(DATA_DIR), unzip=True)

    print("Done. Files:")
    for f in sorted(DATA_DIR.iterdir()):
        print(f"  - {f.name}")


if __name__ == "__main__":
    main()
