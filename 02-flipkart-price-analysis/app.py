"""Flipkart Product Pricing Dashboard — Streamlit app.

Run with:
    streamlit run app.py

Every chart here is backed by the exact same named SQL queries used in
analysis.ipynb (see queries.sql / db.py).
"""
import duckdb
import plotly.express as px
import streamlit as st

import db

st.set_page_config(page_title="Flipkart Pricing Dashboard", page_icon="🛒", layout="wide")


@st.cache_resource
def get_con() -> duckdb.DuckDBPyConnection:
    return db.get_connection()


con = get_con()

st.title("🛒 Flipkart Product Pricing Dashboard")
st.caption(
    "Category profitability, price distributions, and discount patterns over 20,000 Flipkart "
    "product listings (Kaggle: PromptCloudHQ/flipkart-products), all computed in DuckDB."
)

# ---- Sidebar filters -> feed the parameterized `filtered_products` query ----
category_options_df = db.run_query("category_options", con)
with st.sidebar:
    st.header("Filters")
    selected_category = st.selectbox(
        "Category", options=["All categories"] + category_options_df["category"].tolist()
    )
    max_price = st.slider("Max retail price (₹)", min_value=0, max_value=50000, value=50000, step=500)

category_param = None if selected_category == "All categories" else selected_category
max_price_param = None if max_price == 50000 else max_price

# ---- Top-line KPIs ----
corr_df = db.run_query("discount_vs_rating_correlation", con)
col1, col2, col3 = st.columns(3)
col1.metric("Products in dataset", "20,000")
col2.metric("Discount vs. rating correlation", f"{corr_df['discount_vs_rating_corr'][0]:.3f}")
col3.metric("Products with a numeric rating", f"{corr_df['rated_product_count'][0]:,} (~9%)")

st.divider()

# ---- Category profitability ----
st.subheader("Category profitability")
cat_col1, cat_col2 = st.columns(2)
with cat_col1:
    overview_df = db.run_query("category_overview", con)
    fig = px.bar(
        overview_df, x="product_count", y="category", orientation="h",
        title="Top 20 categories by listing count",
        labels={"product_count": "products", "category": ""},
        height=600,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)
with cat_col2:
    fig = px.bar(
        overview_df, x="avg_discount_pct", y="category", orientation="h",
        title="Average discount % by category",
        labels={"avg_discount_pct": "avg discount %", "category": ""},
        height=600,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Price distribution ----
st.subheader("Price distribution by category")
percentile_df = db.run_query("category_price_percentiles", con)
fig = px.bar(
    percentile_df, x="category", y=["q1", "median_price", "q3"], barmode="group",
    title="Price quartiles by category (top 15 by listing count)",
    labels={"value": "price (₹)", "category": "", "variable": ""},
)
st.plotly_chart(fig, use_container_width=True)
st.dataframe(percentile_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Price tiers ----
st.subheader("Price tier breakdown")
tier_col1, tier_col2 = st.columns([1, 1])
with tier_col1:
    tier_df = db.run_query("price_tier_binning", con)
    fig = px.pie(tier_df, names="price_tier", values="product_count", title="Listings by price tier")
    st.plotly_chart(fig, use_container_width=True)
with tier_col2:
    st.dataframe(tier_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Top brands ----
st.subheader("Top brands by listing volume")
brand_df = db.run_query("brand_pricing", con)
st.dataframe(brand_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Price outliers ----
st.subheader("Price outliers (10x+ their category's median price)")
outlier_df = db.run_query("price_outliers", con)
st.dataframe(outlier_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Filtered product explorer ----
st.subheader(f"Explore products — {selected_category}, up to ₹{max_price:,}")
filtered_df = db.run_query(
    "filtered_products", con, category=category_param, max_price=max_price_param
)
st.dataframe(filtered_df, hide_index=True, use_container_width=True)
