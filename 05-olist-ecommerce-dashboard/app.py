"""Olist E-Commerce Sales Dashboard — Streamlit app.

Run with:
    streamlit run app.py

Every chart here is backed by the exact same named SQL queries used in
analysis.ipynb (see queries.sql / db.py), run against the pre-built
data/olist.duckdb file (see load_to_duckdb.py).
"""
import duckdb
import plotly.express as px
import streamlit as st

import db

st.set_page_config(page_title="Olist E-Commerce Dashboard", page_icon="🇧🇷", layout="wide")


@st.cache_resource
def get_con() -> duckdb.DuckDBPyConnection:
    return db.get_connection()


con = get_con()

st.title("🇧🇷 Olist E-Commerce Sales Dashboard")
st.caption(
    "End-to-end KPIs, cohort retention, and logistics performance over 96k delivered orders "
    "(Kaggle: olistbr/brazilian-ecommerce), all computed in DuckDB from a pre-loaded olist.duckdb file."
)

# ---- Sidebar filters -> feed the parameterized `filtered_products` query ----
category_options_df = db.run_query("category_options", con)
with st.sidebar:
    st.header("Filters")
    selected_category = st.selectbox("Category", options=["All categories"] + category_options_df["category"].tolist())

category_param = None if selected_category == "All categories" else selected_category

# ---- Top-line KPIs ----
kpi_df = db.run_query("kpi_summary", con)
repeat_df = db.run_query("repeat_purchase_rate", con)
col1, col2, col3, col4 = st.columns(4)
col1.metric("Total revenue", f"R$ {kpi_df['total_revenue'][0]:,.0f}")
col2.metric("Delivered orders", f"{kpi_df['total_orders'][0]:,}")
col3.metric("Avg order value", f"R$ {kpi_df['avg_order_value'][0]:,.2f}")
col4.metric("Repeat purchase rate", f"{repeat_df['repeat_purchase_rate_pct'][0]}%")

st.divider()

# ---- Monthly revenue & growth ----
st.subheader("Monthly revenue & MoM growth")
st.caption(
    "2016 excluded below — only a handful of seed orders exist before 2017. Jan 2017 is also "
    "excluded from the growth-% chart specifically, since it's a % change against that near-zero "
    "Dec 2016 baseline and would otherwise dwarf every real month-over-month move."
)
monthly_df = db.run_query("monthly_revenue_growth", con)
monthly_df = monthly_df[monthly_df["month"] >= "2017-01-01"]
fig = px.bar(monthly_df, x="month", y="revenue", title="Monthly revenue")
st.plotly_chart(fig, use_container_width=True)
growth_df = monthly_df[monthly_df["month"] >= "2017-02-01"]
fig = px.line(growth_df, x="month", y="mom_growth_pct", title="Month-over-month growth % (from Feb 2017)", markers=True)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Top categories ----
st.subheader("Top 20 categories by revenue")
cat_df = db.run_query("top_categories", con)
fig = px.bar(
    cat_df, x="revenue", y="category", orientation="h",
    title="Revenue by category", labels={"revenue": "revenue (R$)", "category": ""},
    height=600,
)
fig.update_layout(yaxis={"categoryorder": "total ascending"})
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Logistics ----
st.subheader("Delivery performance")
log_col1, log_col2 = st.columns(2)
fulfillment_df = db.run_query("order_fulfillment_summary", con)
with log_col1:
    st.metric("Avg delivery time", f"{fulfillment_df['avg_delivery_days'][0]:.1f} days")
    st.metric("Avg days before estimate", f"{fulfillment_df['avg_days_before_estimate'][0]:.1f} days")
    st.metric("Late-delivery rate", f"{fulfillment_df['late_pct'][0]}%")
with log_col2:
    regional_df = db.run_query("regional_fulfillment", con)
    fig = px.bar(
        regional_df, x="late_pct", y="state", orientation="h",
        title="Late-delivery % by state (worst first)", labels={"late_pct": "late %", "state": ""},
        height=500,
    )
    fig.update_layout(yaxis={"categoryorder": "total descending"})
    st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Cohort retention ----
st.subheader("Monthly cohort retention")
st.caption(
    "Olist customer_id is generated per-order — this uses customer_unique_id, the stable "
    "identifier, to track whether customers ever return."
)
cohort_df = db.run_query("monthly_cohort_retention", con)
cohort_df["cohort_month"] = cohort_df["cohort_month"].astype(str)
pivot = cohort_df.pivot(index="cohort_month", columns="month_index", values="active_customers")
cohort_size = pivot[0]
retention_pct = pivot.div(cohort_size, axis=0).round(3) * 100
fig = px.imshow(
    retention_pct, text_auto=".0f", aspect="auto", color_continuous_scale="Blues",
    labels={"color": "retention %"}, title="Retention % by cohort month x months since first order",
)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Payment types & top customers ----
pay_col1, pay_col2 = st.columns(2)
with pay_col1:
    st.subheader("Payment methods")
    pay_df = db.run_query("payment_type_breakdown", con)
    fig = px.pie(pay_df, names="payment_type", values="total_revenue", title="Revenue by payment type")
    st.plotly_chart(fig, use_container_width=True)
with pay_col2:
    st.subheader("Top customers by lifetime value")
    ltv_df = db.run_query("top_customers_by_ltv", con)
    st.dataframe(ltv_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Filtered product explorer ----
st.subheader(f"Explore products — {selected_category}")
filtered_df = db.run_query("filtered_products", con, category=category_param)
st.dataframe(filtered_df, hide_index=True, use_container_width=True)
