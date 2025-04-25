import streamlit as st
import plotly.express as px
from utils import load_table

st.header("Price Sensitivity by Region & Product")

# Load sensitivity data
sensitivity = load_table("sensitivity_ranked")  # Regions and categories with price sensitivity
volatility = load_table("sensitivity_with_volatility")  # Adds volatility classification

st.markdown("### Top Regions by Price Sensitivity")
st.markdown("These regions show the strongest response in sales volume when price changes.")

# Sort and display top 10
avg_by_reg = sensitivity.groupby(["region", "product_category"])["sensitivity_coef"].mean().reset_index()
top_sensitive = avg_by_reg.sort_values("sensitivity_coef", ascending=False).head(10)
fig = px.bar(top_sensitive, x="region", y="sensitivity_coef", color="product_category",
             title="Top Sensitive Regions (by Category)",
             labels={"sensitivity_coef": "Price sensitivity", "region": "region"},
             height=400)
st.plotly_chart(fig, use_container_width=True)

st.markdown("---")
st.markdown("### Volatility Tier Analysis(Risky Tiers)")
st.markdown("Identifies regions grouped by their Standard deviation of quantity sold relative to price change.")
st.markdown("some segments may seem sensitive just because of outliers,\n but true price-sensitive segments show consistent quantity swings when prices move.")
st.markdown("** pick a region and product category to determine its volatility and sensitivity tier**")
# Create filters for region and product category
selected_region = st.selectbox("Select Region", volatility["region"].unique())
selected_product = st.selectbox("Select Product Category", 
                               volatility[volatility["region"] == selected_region]["product_category"].unique())
# Filter the dataframe based on selections
filtered = volatility[(volatility["region"] == selected_region) & 
                     (volatility["product_category"] == selected_product)]
# Display the filtered results
st.dataframe(filtered[["region", "product_category", "sensitivity_tier", "volatility_score"]].reset_index(drop=True),
             use_container_width=True)

# Sensitivity score by category
st.markdown("### Average Sensitivity by Product Category")
avg_by_cat = sensitivity.groupby("product_category")["sensitivity_coef"].mean().reset_index()
fig2 = px.bar(avg_by_cat.sort_values("sensitivity_coef", ascending=False),
              x="product_category", y="sensitivity_coef",
              title="Average Sensitivity Score by Category",
              labels={"sensitivity_coef": "Avg Sensitivity Score"},
              height=400)
st.plotly_chart(fig2, use_container_width=True)
st.markdown("The above chart shows the average sensitivity score for each product category. \n" \
"This helps identify which categories are more sensitive to price changes.")


#  Bubble Chart Explanation
st.markdown("### Price Sensitivity vs. Volatility Analysis")
st.markdown("""
This chart visualizes the relationship between **price sensitivity** and **volatility** across different regions and product categories.

- **X-axis**: Price Sensitivity (left = insensitive, right = highly sensitive)  
- **Y-axis**: Volatility (bottom = stable, top = unpredictable)  
- **Bubble size**: Total Units Sold (market impact)  
- **Color**: Region  
""")

#  Bubble Chart
fig3 = px.scatter(
    volatility,
    x="sensitivity_coef",
    y="volatility_score",
    size="total_units",
    color="region",
    hover_name="product_category",
    title="Price Sensitivity vs. Volatility Matrix",
    labels={
        "sensitivity_coef": "Price Sensitivity",
        "volatility_score": "Volatility Score"
    },
    height=500
)
st.plotly_chart(fig3, use_container_width=True)

#  Quadrant-Based Insights
st.markdown("###  Strategic Interpretation by Quadrant")
col1, col2 = st.columns(2)

with col1:
    st.markdown("####  Top-Right: Highly Sensitive + Volatile")
    st.warning("""
   **Risky Promo Targets**  
Price influences demand, but unpredictably.  
Test cautiously — may backfire.
""")

    st.markdown("####  Top-Left: Low Sensitivity + High Volatility")
    st.info("""
   **Noise-Driven Segments**  
Price has little influence.  
Volatility suggests external/non-price factors at play.
""")

with col2:
    st.markdown("####  Bottom-Right: Sensitive + Stable")
    st.success("""
   **Promo-Friendly Segments**  
Price affects demand consistently.  
Good candidates for targeted discounts.
""")

    st.markdown("####  Bottom-Left: Insensitive + Stable")
    st.info("""
   **Stable Core Segments**  
Price doesn't drive demand.  
Consider premium pricing and loyalty retention.
""")

# 🔍 Top 5 High-Impact Segments
st.markdown("###  High-Impact Segments (by Volume)")
top_segments = volatility.sort_values("total_units", ascending=False).head(5)
st.dataframe(top_segments[["region", "product_category", "total_units", "sensitivity_coef", "volatility_score"]])

#  Dynamic Strategy Generator
st.markdown("---")
st.markdown("###  Strategic Insight Generator")
st.markdown("Select a sensitivity and volatility range to get targeted strategic advice:")
st.markdown("**Note:** Input the sensitivity and volatility scores derived from the volatility analysis obtained initially for insights.")

# Create sliders
sensitivity_input = st.selectbox("Select Region", volatility["sensitivity_tier"].unique())
volatility_input = st.selectbox("Select Volatility Score", sorted(volatility["volatility_score"].unique()))

#Define volatility level based on score
def classify_volatility(score):
    if score < 0.3:
        return "Very Low"
    elif score < 0.6:
        return "Low"
    elif score < 0.9:
        return "Medium"
    elif score < 1.2:
        return "High"
    else:
        return "Very High"

volatility_tier = classify_volatility(volatility_input)

#  Insight logic based on tiers
def get_insight(sens, vol):
    if sens in ["Very High", "High"] and vol in ["High", "Very High"]:
        return " **High sensitivity & high volatility** — demand is price-driven but unpredictable. A/B test discount strategies with caution."
    elif sens in ["Low", "Medium"] and vol in ["High", "Very High"]:
        return " **Low sensitivity, high volatility** — pricing doesn’t drive demand. Look into external or seasonal influences."
    elif sens in ["Very High", "High"] and vol in ["Low", "Very Low", "Medium"]:
        return " **High sensitivity, low volatility** — ideal promo targets. Price changes predictably drive demand."
    elif sens in ["Low", "Medium"] and vol in ["Low", "Very Low"]:
        return " **Stable and insensitive** — safe revenue base. Consider premium pricing or bundling strategies."
    else:
        return " Mixed signals. Consider segment-specific testing or additional research."

#  Show final insight
st.markdown(f"**Selected Tiers:** `{sensitivity_input}` sensitivity | `{volatility_tier}` volatility")
st.markdown(f"**Strategic Insight:** {get_insight(sensitivity_input, volatility_tier)}")

