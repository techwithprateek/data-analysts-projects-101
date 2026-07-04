"""Zomato Restaurant Analytics — Streamlit dashboard.

Run with:
    streamlit run app.py

Every chart here is backed by the exact same named SQL queries used in
analysis.ipynb (see queries.sql / db.py) — this file is just the
presentation layer on top of them.
"""
import duckdb
import plotly.express as px
import streamlit as st

import db

st.set_page_config(page_title="Zomato Restaurant Analytics", page_icon="🍽️", layout="wide")


@st.cache_resource
def get_con() -> duckdb.DuckDBPyConnection:
    # Cached so the CSV/Excel load only happens once per Streamlit session,
    # not on every widget interaction.
    return db.get_connection()


con = get_con()

st.title("🍽️ Zomato Restaurant Analytics")
st.caption(
    "EDA over the Zomato Restaurants dataset (Kaggle: shrutimehta/zomato-restaurants-data) — "
    "cuisine popularity, price-vs-rating, and geographic distribution, all computed in DuckDB."
)

# ---- Sidebar filters -> feed the parameterized `filtered_restaurants` query ----
city_options = db.run_query("city_options", con)["city"].tolist()
with st.sidebar:
    st.header("Filters")
    selected_city = st.selectbox("City", options=["All cities"] + city_options)
    min_rating = st.slider("Minimum rating", min_value=0.0, max_value=5.0, value=0.0, step=0.1)

city_param = None if selected_city == "All cities" else selected_city
rating_param = None if min_rating == 0.0 else min_rating

# ---- Top-line KPIs ----
corr_df = db.run_query("cost_rating_correlation", con)
col1, col2, col3 = st.columns(3)
col1.metric("Restaurants in dataset", "9,551")
col2.metric("Cost vs. rating correlation", f"{corr_df['cost_vs_rating'][0]:.3f}")
col3.metric("Price-tier vs. rating correlation", f"{corr_df['price_range_vs_rating'][0]:.3f}")

st.divider()

# ---- Geographic distribution ----
st.subheader("Geographic distribution")
geo_col1, geo_col2 = st.columns(2)
with geo_col1:
    country_df = db.run_query("restaurants_per_country", con)
    fig = px.bar(
        country_df, x="country", y="restaurant_count",
        title="Restaurants by country", labels={"restaurant_count": "restaurants", "country": ""},
    )
    st.plotly_chart(fig, use_container_width=True)
with geo_col2:
    city_df = db.run_query("top_cities_by_count", con)
    fig = px.bar(
        city_df, x="restaurant_count", y="city", orientation="h",
        title="Top 20 cities by restaurant count",
        labels={"restaurant_count": "restaurants", "city": ""},
        height=600,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Cuisine analysis ----
st.subheader("Cuisine popularity & quality")
cui_col1, cui_col2 = st.columns(2)
with cui_col1:
    cuisine_count_df = db.run_query("top_cuisines_by_count", con)
    fig = px.bar(
        cuisine_count_df, x="restaurant_count", y="cuisine", orientation="h",
        title="Most common cuisines", labels={"restaurant_count": "restaurants", "cuisine": ""},
        height=600,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)
with cui_col2:
    cuisine_rating_df = db.run_query("top_cuisines_by_rating", con)
    fig = px.bar(
        cuisine_rating_df, x="avg_rating", y="cuisine", orientation="h",
        title="Highest-rated cuisines (min. 20 restaurants)",
        labels={"avg_rating": "avg rating", "cuisine": ""},
        height=600,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Price vs rating ----
st.subheader("Price vs. rating")
price_col1, price_col2 = st.columns(2)
with price_col1:
    price_df = db.run_query("rating_by_price_range", con)
    fig = px.bar(
        price_df, x="price_range", y="avg_rating",
        title="Average rating by price tier (1=cheap, 4=expensive)",
        labels={"price_range": "price tier", "avg_rating": "avg rating"},
    )
    st.plotly_chart(fig, use_container_width=True)
with price_col2:
    delivery_df = db.run_query("online_delivery_impact", con)
    booking_df = db.run_query("table_booking_impact", con)
    st.markdown("**Online delivery vs. avg rating**")
    st.dataframe(delivery_df, hide_index=True, use_container_width=True)
    st.markdown("**Table booking vs. avg rating**")
    st.dataframe(booking_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Best value restaurants ----
st.subheader("Best value restaurants (rating >= 4.0, ranked by rating per dollar spent)")
value_df = db.run_query("best_value_restaurants", con)
st.dataframe(value_df, hide_index=True, use_container_width=True)

st.divider()

# ---- Filtered restaurant explorer ----
st.subheader(f"Explore restaurants — {selected_city}, rating >= {min_rating}")
filtered_df = db.run_query("filtered_restaurants", con, city=city_param, min_rating=rating_param)
st.dataframe(filtered_df, hide_index=True, use_container_width=True)
