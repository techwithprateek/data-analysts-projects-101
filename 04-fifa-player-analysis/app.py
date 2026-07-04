"""FIFA 21 Player Scouting Dashboard — Streamlit app.

Run with:
    streamlit run app.py

Most charts here are backed by the named SQL queries in queries.sql (via
db.py) — the one exception is the player-archetype clustering section,
which runs scikit-learn's KMeans directly (SQL isn't the right tool for that).
"""
import duckdb
import plotly.express as px
import streamlit as st
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

import db

st.set_page_config(page_title="FIFA 21 Scouting Dashboard", page_icon="⚽", layout="wide")

CLUSTER_FEATURES = ["pace", "shooting", "passing", "dribbling", "defending", "physic"]


@st.cache_resource
def get_con() -> duckdb.DuckDBPyConnection:
    return db.get_connection()


@st.cache_data
def get_clusters(_con: duckdb.DuckDBPyConnection, k: int) -> "pd.DataFrame":
    outfield = _con.execute(f"""
        SELECT short_name, team_position, overall, value_eur, {", ".join(CLUSTER_FEATURES)}
        FROM players
        WHERE pace IS NOT NULL
    """).df()
    X = StandardScaler().fit_transform(outfield[CLUSTER_FEATURES])
    outfield["cluster"] = KMeans(n_clusters=k, random_state=42, n_init=10).fit_predict(X)
    return outfield


con = get_con()

st.title("⚽ FIFA 21 Player Scouting Dashboard")
st.caption(
    "Player valuation, position economics, and archetype clustering over 18,944 FIFA 21 players "
    "(Kaggle: stefanoleone992/fifa-21-complete-player-dataset)."
)

# ---- Sidebar filters -> feed the parameterized `filtered_scouting` query ----
position_options_df = db.run_query("position_options", con)
with st.sidebar:
    st.header("Scouting filters")
    selected_position = st.selectbox("Position", options=["All positions"] + position_options_df["position"].tolist())
    min_potential = st.slider("Minimum potential", min_value=0, max_value=99, value=0)
    max_value = st.number_input("Max value (€)", min_value=0, value=0, step=1_000_000, help="0 = no limit")
    st.divider()
    n_clusters = st.slider("Player archetype clusters (KMeans k)", min_value=2, max_value=8, value=4)

position_param = None if selected_position == "All positions" else selected_position
min_potential_param = None if min_potential == 0 else min_potential
max_value_param = None if max_value == 0 else max_value

# ---- Top-line KPIs ----
corr_df = db.run_query("attribute_value_correlations", con)
col1, col2, col3 = st.columns(3)
col1.metric("Players in dataset", "18,944")
col2.metric("Potential vs. value correlation", f"{corr_df['potential_corr'][0]:.3f}")
col3.metric("Overall vs. value correlation", f"{corr_df['overall_corr'][0]:.3f}")

st.divider()

# ---- Attribute correlations ----
st.subheader("Which attributes predict market value?")
corr_long = corr_df.T.reset_index()
corr_long.columns = ["attribute", "correlation"]
corr_long["attribute"] = corr_long["attribute"].str.replace("_corr", "")
fig = px.bar(
    corr_long.sort_values("correlation"), x="correlation", y="attribute", orientation="h",
    title="Correlation with market value (value_eur)",
)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Position economics ----
st.subheader("Position economics")
pos_col1, pos_col2 = st.columns(2)
with pos_col1:
    value_pos_df = db.run_query("value_by_position", con)
    fig = px.bar(
        value_pos_df, x="avg_value_eur", y="position", orientation="h",
        title="Average market value by position", labels={"avg_value_eur": "avg value (€)", "position": ""},
        height=500,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)
with pos_col2:
    roi_df = db.run_query("roi_by_position", con)
    fig = px.bar(
        roi_df, x="avg_value_per_overall_point", y="position", orientation="h",
        title="Value per overall-rating point by position",
        labels={"avg_value_per_overall_point": "€ per overall point", "position": ""},
        height=500,
    )
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    st.plotly_chart(fig, use_container_width=True)

st.subheader("Which leagues pay most relative to talent level?")
league_df = db.run_query("league_pay_vs_performance", con)
fig = px.bar(
    league_df, x="wage_per_overall_point", y="league_name", orientation="h",
    title="Wage per overall-rating point by league (min. 100 players)",
    labels={"wage_per_overall_point": "€ wage per overall point", "league_name": ""},
    height=600,
)
fig.update_layout(yaxis={"categoryorder": "total ascending"})
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Age curve ----
st.subheader("Career arc: rating and value by age")
age_df = db.run_query("age_curve", con)
fig = px.line(
    age_df, x="age", y=["avg_overall", "avg_potential"], title="Average overall & potential by age",
    labels={"value": "rating", "age": "age", "variable": ""},
)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Player archetype clustering ----
st.subheader(f"Player archetypes (KMeans, k={n_clusters})")
st.caption("Clustered on pace/shooting/passing/dribbling/defending/physic — outfield players only.")
clustered = get_clusters(con, n_clusters)
cluster_summary = (
    clustered.groupby("cluster")[CLUSTER_FEATURES + ["overall", "value_eur"]].mean().round(1).reset_index()
)
st.dataframe(cluster_summary, hide_index=True, use_container_width=True)
fig = px.scatter(
    clustered, x="defending", y="shooting", color=clustered["cluster"].astype(str),
    hover_data=["short_name", "team_position", "overall"],
    title="Player archetypes: defending vs. shooting", labels={"color": "cluster"},
    opacity=0.5,
)
st.plotly_chart(fig, use_container_width=True)

st.divider()

# ---- Scouting explorer ----
st.subheader(f"Scouting explorer — {selected_position}, potential >= {min_potential}")
filtered_df = db.run_query(
    "filtered_scouting", con,
    position=position_param, min_potential=min_potential_param, max_value=max_value_param,
)
st.dataframe(filtered_df, hide_index=True, use_container_width=True)
