# Data Analyst Projects 101

Five resume-building data analyst projects, each built on a real Kaggle dataset with a fully
working, heavily-commented reference implementation — not a starter template with blanks to fill
in. Read the code, run it yourself, and use it as a portfolio piece or interview talking point.

This is free learner content from Uplevel Academy for anyone starting out in data analytics or
looking for solid projects to add to a resume.

## Who this is for
Anyone learning data analysis who wants to see what a complete, professional-quality project looks
like end to end — not just a Jupyter notebook with a few `df.groupby()` calls, but SQL, a real
dataset, a documented analysis with actual findings, and a live interactive dashboard.

## How every project is built
All 5 projects share one architecture, so once you understand one, you understand all of them:

- **SQL-first.** The actual analysis lives in each project's `queries.sql` as named, commented
  DuckDB queries — window functions, CTEs, percentiles, RFM, cohort analysis. This is the part
  worth reading closely.
- **A thin Python wrapper (`db.py`).** ~70 lines per project: loads the data into DuckDB, parses
  `queries.sql`, and exposes `run_query(name, **params)`.
- **One notebook (`analysis.ipynb`).** Runs each named query, charts it, and explains the finding
  in plain language — including the honest, sometimes counterintuitive ones (see below).
  Fully executed, so you can read the outputs on GitHub without running anything.
- **One dashboard (`app.py`).** A Streamlit app calling the *exact same* named queries as the
  notebook — nothing is duplicated between "the analysis" and "the live app."
- **A project README** with the problem statement, dataset info, how to run it, the real findings,
  and a screenshot of the dashboard.

Machine learning (clustering, regression) only shows up in project 4, where SQL genuinely isn't the
right tool — everywhere else, the aggregation/ranking/filtering logic stays in SQL on purpose,
since that's the skill most DA portfolios under-demonstrate.

## One-time setup
```bash
git clone <this-repo>
cd data-analysts-projects-101

python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Kaggle API token (used by every project's download_data.py):
# 1. Go to https://www.kaggle.com/settings -> API -> Create New Token
# 2. Save the downloaded kaggle.json to ~/.kaggle/kaggle.json
```

Then, inside any project folder:
```bash
python download_data.py         # pulls that project's dataset via the Kaggle API
jupyter notebook analysis.ipynb # read the analysis
streamlit run app.py            # or launch the interactive dashboard
```
(Project 5 has one extra ETL step — see its own README.)

## The 5 projects

| # | Project | Difficulty | Est. time | Best for |
|---|---------|-----------|-----------|---------|
| 1 | [Zomato Restaurant Analysis](./01-zomato-restaurant-analysis) | ⭐⭐ Beginner | 2-3 weeks | First portfolio project, EDA fundamentals |
| 2 | [Flipkart Price Analysis](./02-flipkart-price-analysis) | ⭐⭐⭐ Intermediate | 2-3 weeks | Pricing strategy, business acumen |
| 3 | [Supply Chain & Inventory Analysis](./03-supply-chain-analysis) | ⭐⭐⭐ Intermediate | 3-4 weeks | Operations focus, supply chain optimization |
| 4 | [FIFA Player Performance Analysis](./04-fifa-player-analysis) | ⭐⭐⭐⭐ Intermediate-Advanced | 3-4 weeks | Clustering, multivariate analysis, ML intro |
| 5 | [Olist E-Commerce Dashboard](./05-olist-ecommerce-dashboard) | ⭐⭐⭐⭐ Advanced | 4-6 weeks | Complete DA workflow, capstone / interview showcase |

## Suggested learning path
**Zomato** (EDA fundamentals) → **Flipkart** (pricing, SQL percentiles/window functions) →
**Supply Chain** (operations, a differentiator most DA portfolios skip) → **FIFA** (your first
clustering/ML project) → **Olist** (capstone: multi-table ETL, cohort retention, full dashboard).

Each project's difficulty and time estimate assumes you've completed the ones before it.

## A findings, not just a chart tour
Every project's README states its *actual* findings, including the ones that complicate a tidy
narrative — e.g. Zomato's raw price barely predicting rating, the supply-chain dataset's "First
Class" shipping being the *least* reliable mode, or Olist's ~3% repeat-purchase rate reframing
"growth" as acquisition-driven rather than retention-driven. That's deliberate: a portfolio project
that surfaces a real, slightly inconvenient finding and explains it is far more interview-worthy
than one that just confirms the obvious.
