"""Download the FIFA 21 Complete Player Dataset from Kaggle into ./data/.

The Kaggle dataset actually ships player data for FIFA 15-21 (7 CSVs) plus a
large multi-year Excel workbook. This project only needs FIFA 21, so this
script downloads the full archive and then deletes everything except
`players_21.csv` to keep the local `data/` folder small.

One-time setup: get a Kaggle API token from https://www.kaggle.com/settings
(API -> Create New Token) and save it to ~/.kaggle/kaggle.json.

Usage:
    python download_data.py
"""
from pathlib import Path

DATASET = "stefanoleone992/fifa-21-complete-player-dataset"
DATA_DIR = Path(__file__).parent / "data"
KEEP_FILE = "players_21.csv"


def main() -> None:
    from kaggle.api.kaggle_api_extended import KaggleApi

    DATA_DIR.mkdir(exist_ok=True)
    api = KaggleApi()
    api.authenticate()

    print(f"Downloading '{DATASET}' into {DATA_DIR}/ ...")
    api.dataset_download_files(DATASET, path=str(DATA_DIR), unzip=True)

    for f in DATA_DIR.iterdir():
        if f.name != KEEP_FILE:
            f.unlink()

    print(f"Done. Kept only {KEEP_FILE}:")
    for f in sorted(DATA_DIR.iterdir()):
        print(f"  - {f.name}")


if __name__ == "__main__":
    main()
