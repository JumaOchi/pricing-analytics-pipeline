import streamlit as st
import plotly.express as px
import pandas as pd
from utils import load_table

# Load simulation data
discount_sim = load_table("discount_simulation_results")
value_sim = load_table("what_if_simulation_value_results")

st.header(" What-If Simulations: Pricing Impact Analysis")

st.markdown("""
###  What is this?
These simulations use a regression model to predict the impact of **discount rate** and **average order value (AOV)** changes on `avg_profit_per_order` across regions.

The model was trained using historical data and key features, yielding:
- **R² Score**: `0.9976` (excellent predictive power)
- **MSE**: `49.04`

---
Use the controls below to explore how different pricing strategies could impact profitability.
""")

# ---- Sim Toggle ----
sim_type = st.radio("Choose Simulation Type", ["AOV Change (+10, 0, -10)", "Discount Rate Change (+5%, 0%, -5%)"])

# ---- Value Simulation ----
if sim_type == "AOV Change (+10, 0, -10)":
    st.markdown("###  Impact of Changing Average Order Value")
    fig = px.bar(value_sim, x="scenario", y="predicted_profit", color="region",
                 barmode="group", title="Predicted Profit by Region - AOV Simulation",
                 labels={"predicted_profit": "Predicted Avg Profit/Order", "scenario": "AOV Change Scenario"},
                 hover_data={"predicted_profit": ":.2f"})
    st.plotly_chart(fig, use_container_width=True)

# ---- Discount Simulation ----
else:
    st.markdown("###  Impact of Changing Discount Rate")
    fig = px.bar(discount_sim, x="scenario", y="predicted_profit", color="region",
                 barmode="group", title="Predicted Profit by Region - Discount Simulation",
                 labels={"predicted_profit": "Predicted Avg Profit/Order", "scenario": "Discount Rate Scenario"},
                 hover_data={"predicted_profit": ":.2f"})
    st.plotly_chart(fig, use_container_width=True)

# ---- Summary Insight ----
st.markdown("""
### 📈 Strategic Summary

- The regression model enables us to simulate profitability under hypothetical pricing strategies.
- **Increasing AOV by $10** consistently shows uplift in avg profit per order across most regions.
- **Reducing discount rate by 5%** is beneficial in high-discount regions, but may reduce conversions elsewhere.
- Managers can test pricing levers before rollout, using this predictive tool to minimize risk.

>  *Model trained on historical sales, pricing, and loss data from keggle(Amazon data 2019 -2024) credits:rahuljangir78.*

---
Want to go deeper? Re-run the regression with more features (e.g. region type, seasonality) or deploy A/B tests guided by these simulations.
            - **Caution**: These are predictions, not guarantees. Real-world factors can lead to different outcomes. Always validate with 
            real data before making decisions.**
            - **Dataset may be bias and not a true adaptation of amazon data**
            - **Data from Keggle: https://www.kaggle.com/datasets/rahuljangir78/amazon-sales-dataset-for-performance-analysis**
""")
