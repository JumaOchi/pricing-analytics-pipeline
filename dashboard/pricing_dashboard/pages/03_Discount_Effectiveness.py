import streamlit as st
import plotly.express as px
from utils import load_table

# Load data
summary = load_table("discount_impact_analysis_summary")

st.header("Discount Effectiveness & Profitability")

# KPI Highlights
col1, col2, col3, col4 = st.columns(4)
col1.metric("Top Profit Band", summary.loc[summary['profit_uplift_vs_low'].idxmax()]['discount_band'])
col2.metric("Max Revenue Uplift (%)", f"{summary['revenue_uplift_vs_low'].max():.2f}%")
col3.metric("Avg Profit Margin", f"{summary['profit_margin'].mean():.2%}")
col4.metric("Best ROI/Discount %", f"${summary['profit_per_discount_pct'].max():.2f} per %")

# ---- Visualization Section ----

# 1. Revenue by Discount Band
st.markdown("###  Revenue by Discount Band")
fig1 = px.bar(summary, x="discount_band", y="total_revenue", color="discount_band",
              labels={"total_revenue": "Revenue ($)"})
st.plotly_chart(fig1, use_container_width=True)

# 2. Revenue & Profit Uplift
st.markdown("###  Revenue vs Profit Uplift Compared to 0% Discount")
fig2 = px.line(summary, x="discount_band", 
               y=["revenue_uplift_vs_low", "profit_uplift_vs_low"],
               markers=True, labels={
                   "value": "Uplift (%)",
                   "variable": "Uplift Type",
                   "discount_band": "Discount Band"
               })
st.plotly_chart(fig2, use_container_width=True)

# 3. Bubble Chart: Discount Rate vs Orders/Profit
st.markdown("###  Discount Band Effectiveness")
fig3 = px.scatter(summary,
                  x="avg_discount",
                  y="avg_profit_per_order",
                  size="num_orders",
                  color="discount_band",
                  hover_data=["total_revenue", "total_profit"],
                  labels={
                      "avg_discount": "Average Discount (%)",
                      "avg_profit_per_order": "Profit per Order ($)",
                      "num_orders": "Orders"
                  })
st.plotly_chart(fig3, use_container_width=True)

# ---- Insights Section ----
st.markdown("### 💡 Key Insights")

top_band = summary.loc[summary["profit_uplift_vs_low"].idxmax()]
low_band = summary.loc[summary["profit_uplift_vs_low"].idxmin()]

with st.expander("Summary Insights"):
    st.markdown(f"""
    -  **Best-performing Band**: `{top_band['discount_band']}` led to the highest profit uplift.
    -  **Underperforming Band**: `{low_band['discount_band']}` shows low or negative profit impact.
    -  **Avg Profit per Discount %**: `${summary['profit_per_discount_pct'].mean():.2f}` per 1% discount.
    -  Consider focusing promotions around **{top_band['discount_band']}** for maximum ROI.
    """)

# ---- Optional: Show Raw Table ----
with st.expander("🔍 View Raw Summary Table"):
    st.dataframe(summary.style.format({
        "avg_discount": "{:.2f}%",
        "avg_profit_per_order": "${:.2f}",
        "avg_order_value": "${:.2f}",
        "profit_margin": "{:.2%}",
        "total_revenue": "${:,.0f}",
        "total_profit": "${:,.0f}",
        "revenue_uplift_vs_low": "{:.2f}%",
        "profit_uplift_vs_low": "{:.2f}%",
        "profit_per_discount_pct": "${:.2f}"
    }))

