import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
import pandas as pd
from utils import load_table
from sklearn.preprocessing import MinMaxScaler

# Load data
sales_yoy = load_table("salesperson_growth_yoy")
cluster_summary = load_table("salesperson_cluster_summary")

st.header("📊 Salespeople Performance Analysis")

# ---- Global KPI Summary ----
st.markdown("###  Top KPIs Across All Salespeople")
latest_year = sales_yoy["year"].max()
latest_data = sales_yoy[sales_yoy["year"] == latest_year]

# Get top performers
top_sales = latest_data.loc[latest_data["total_sales"].idxmax()]
top_profit = latest_data.loc[latest_data["total_profit"].idxmax()]
top_efficiency = latest_data.loc[(latest_data["loss_rate"] + latest_data["discount_rate"]).idxmin()]

col1, col2, col3 = st.columns(3)
col1.metric(" Top Salesperson (Total Sales)", top_sales["salesperson"], f"${top_sales['total_sales']:,.0f}")
col2.metric(" Top by Profit", top_profit["salesperson"], f"${top_profit['total_profit']:,.0f}")
col3.metric(" Most Efficient (Low Loss+Discount)", top_efficiency["salesperson"], 
             f"{(top_efficiency['loss_rate'] + top_efficiency['discount_rate']):.2%}")

# ---- Year Filter ----
all_years = sorted(sales_yoy["year"].unique())
selected_year = st.selectbox("Select Year to Analyze", all_years[::-1], index=0)

# ---- Salesperson Filter ----
salespeople_list = sales_yoy[sales_yoy["year"] == selected_year]["salesperson"].unique().tolist()
selected_salesperson = st.selectbox("Select a Salesperson to View Performance Trends", salespeople_list)
filtered_sales = sales_yoy[sales_yoy["salesperson"] == selected_salesperson]

# ---- Time Series: YoY KPI Trends ----
st.markdown("###  YoY Performance Trends")
kpi_option = st.selectbox("Choose Metric to Plot", [
    "total_sales_yoy", "total_profit_yoy", "avg_order_value_yoy", 
    "avg_profit_per_order_yoy", "num_completed_orders_yoy"])

fig1 = px.line(filtered_sales, x="year", y=kpi_option, markers=True,
               title=f"{kpi_option.replace('_', ' ').title()} Over Time for {selected_salesperson}",
               labels={"year": "Year", kpi_option: kpi_option.replace('_', ' ').title()})
st.plotly_chart(fig1, use_container_width=True)

# ---- Cluster Radar Visual ----
st.markdown("###  Cluster Profiles via Radar Chart")
st.markdown("Each cluster represents a group of salespeople with similar performance & behavior patterns. Use this to understand strategic strengths and weaknesses.")

radar_metrics = ["avg_order_value", "avg_profit_per_order", "discount_rate", "profit_margin", "loss_rate"]
scaler = MinMaxScaler()
normalized = pd.DataFrame(scaler.fit_transform(cluster_summary[radar_metrics]), columns=radar_metrics)

fig_radar = go.Figure()
for i, row in normalized.iterrows():
    fig_radar.add_trace(go.Scatterpolar(
        r=row.values,
        theta=radar_metrics,
        fill='toself',
        name=f"Cluster {i+1}"
    ))

fig_radar.update_layout(
    polar=dict(radialaxis=dict(visible=True, range=[0, 1])),
    title="Radar Chart of Cluster Behavioral Profiles"
)
st.plotly_chart(fig_radar, use_container_width=True)

st.markdown("""
** Cluster Category Breakdown**

-  **At-Risk Seller**
    - High AOV, profit margin
    - Very high loss rate 
    - Low order count & discounting
    -  High value deals, but risk of churn or poor follow-up

-  **Premium Closer**
    - High number of completed orders 
    - Lower margin per order, aggressive on discounts
    -  Hustle-heavy, good for volume but needs margin coaching

-  **Steady Performer**
    - Balanced across all metrics
    -  Reliable, not flashy, easy to coach into higher tiers

-  **Value Optimizer**
    - High avg_order_value, strong margins, low discount & loss rates
    -  Ideal profile—understands customer value, targets well
""")

# ---- Cluster Strategy Insight Box ----
st.markdown("### Cluster Strategy Recommendations")
selected_cluster = st.selectbox("Choose a Cluster to Get Strategic Insight", cluster_summary.index + 1)
cluster_row = cluster_summary.iloc[selected_cluster - 1]

with st.expander("💡 Strategy Advice for Selected Cluster"):
    st.markdown(f"""
    - **Avg Order Value**: ${cluster_row['avg_order_value']:,.2f}
    - **Avg Profit/Order**: ${cluster_row['avg_profit_per_order']:,.2f}
    - **Discount Rate**: {cluster_row['discount_rate']:.2%}
    - **Profit Margin**: {cluster_row['profit_margin']:.2%}
    - **Loss Rate**: {cluster_row['loss_rate']:.2%}

    **Insights:**
    - {'High AOV and profit margin' if cluster_row['avg_order_value'] > 500 and cluster_row['profit_margin'] > 0.25 else 'Moderate order value or margin'} → {'Position for premium clients' if cluster_row['avg_order_value'] > 500 else 'Optimize pricing mix'}
    - {'High loss rate' if cluster_row['loss_rate'] > 0.20 else 'Low revenue leakage'} → {'Focus on conversion recovery' if cluster_row['loss_rate'] > 0.20 else 'Stable sales processes'}
    - {'High discount usage' if cluster_row['discount_rate'] > 0.15 else 'Efficient discounting'} → {'Evaluate promo ROI closely' if cluster_row['discount_rate'] > 0.15 else 'Discounts well-targeted'}
    """)

# ---- Raw Data Expanders ----
with st.expander(" View Raw Yearly Salesperson Performance"):
    st.dataframe(sales_yoy.style.format({
        "total_sales": "${:,.0f}",
        "total_profit": "${:,.0f}",
        "avg_order_value": "${:,.2f}",
        "avg_profit_per_order": "${:,.2f}",
        "discount_rate": "{:.2%}",
        "loss_rate": "{:.2%}",
        "profit_margin": "{:.2%}"
    }))

with st.expander(" View Cluster Summary"):
    st.dataframe(cluster_summary.style.format({
        "avg_order_value": "${:,.2f}",
        "avg_profit_per_order": "${:,.2f}",
        "discount_rate": "{:.2%}",
        "profit_margin": "{:.2%}",
        "loss_rate": "{:.2%}"
    }))
