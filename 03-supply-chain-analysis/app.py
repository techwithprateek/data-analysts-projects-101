"""Supply Chain & Delivery Performance Dashboard — Streamlit app.

Run with:
    streamlit run app.py

Every chart here is backed by the exact same named SQL queries used in
analysis.ipynb (see queries.sql / db.py).
"""
import duckdb
import plotly.express as px
import streamlit as st

import db

st.set_page_config(page_title="Supply Chain Dashboard", page_icon="📦", layout="wide")


@st.cache_resource
def get_con() -> duckdb.DuckDBPyConnection:
    return db.get_connection()


con = get_con()

st.title("📦 Supply Chain & Delivery Performance Dashboard")
st.caption(
    "Delivery performance, reorder risk, supplier-market reliability, and RFM segmentation over "
    "180k orders (Kaggle: shashwatwork/dataco-smart-supply-chain-for-big-data-analysis), "
    "all computed in DuckDB."
)

# ---- Sidebar filters ----
category_options_df = db.run_query("category_options", con)
with st.sidebar:
    st.header("Filters")
    selected_category = st.selectbox(
        "Category (late shipments table)", options=["All categories"] + category_options_df["category"].tolist()
    )

category_param = None if selected_category == "All categories" else selected_category

# ---- Top-line KPIs ----
mode_df = db.run_query("late_shipment_by_mode", con)
overall_late_pct = round(mode_df["late_orders"].sum() / mode_df["total_orders"].sum() * 100, 1)
col1, col2, col3 = st.columns(3)
col1.metric("Orders in dataset", "180,519")
col2.metric("Overall late-delivery rate", f"{overall_late_pct}%")
col3.metric("Shipping modes", f"{len(mode_df)}")

st.divider()

# ---- Delivery performance ----
st.subheader("Delivery performance by shipping mode")
mode_col1, mode_col2 = st.columns(2)
with mode_col1:
    fig = px.bar(
        mode_df, x="shipping_mode", y="late_pct", title="Late-delivery rate by shipping mode",
        labels={"late_pct": "late %", "shipping_mode": ""},
    )
    st.plotly_chart(fig, use_container_width=True)
with mode_col2:
    st.dataframe(mode_df, hide_index=True, use_container_width=True)

st.subheader("Late-delivery rate by region x shipping mode")
region_df = db.run_query("late_shipment_by_region", con)
heatmap_df = region_df.pivot(index="region", columns="shipping_mode", values="late_pct")
fig = px.imshow(
    heatmap_df, text_auto=".0f", aspect="auto", color_continuous_scale="Reds",
    labels={"color": "late %"}, title="Late % heatmap (region x shipping mode)",
)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Reorder risk ----
st.subheader("Reorder risk (replenishment burden = avg order qty x avg lead time)")
st.caption(
    "This dataset has no on-hand stock column, so risk is approximated by demand x lead time "
    "rather than compared against real inventory — see the README for the full caveat."
)
risk_df = db.run_query("reorder_risk_by_product", con)
fig = px.bar(
    risk_df.head(15), x="replenishment_burden", y="product_name", orientation="h",
    color="risk_quartile", title="Top 15 products by replenishment burden",
    labels={"replenishment_burden": "burden score", "product_name": ""},
)
fig.update_layout(yaxis={"categoryorder": "total ascending"})
st.plotly_chart(fig, use_container_width=True)
st.dataframe(risk_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Market reliability ----
st.subheader("Fulfillment market reliability")
st.caption("No distinct supplier field exists in this dataset — Market stands in as the 'supplier' entity.")
market_df = db.run_query("market_reliability", con)
st.dataframe(market_df, hide_index=True, use_container_width=True)

st.divider()

# ---- RFM segmentation ----
st.subheader("Customer RFM segmentation")
seg_col1, seg_col2 = st.columns([1, 1])
with seg_col1:
    seg_summary_df = db.run_query("rfm_segment_summary", con)
    fig = px.pie(seg_summary_df, names="segment", values="customer_count", title="Customers by RFM segment")
    st.plotly_chart(fig, use_container_width=True)
with seg_col2:
    fig = px.bar(
        seg_summary_df, x="segment", y="total_revenue", title="Revenue by RFM segment",
        labels={"total_revenue": "total revenue ($)", "segment": ""},
    )
    st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Filtered late shipments explorer ----
st.subheader(f"Explore late shipments — {selected_category}")
filtered_df = db.run_query("filtered_late_shipments", con, category=category_param)
st.dataframe(filtered_df, hide_index=True, use_container_width=True)
