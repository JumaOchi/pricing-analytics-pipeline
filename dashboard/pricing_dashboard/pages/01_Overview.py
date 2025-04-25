import streamlit as st
from utils import load_table

st.set_page_config(page_title="Executive Summary", layout="wide")
st.header("Executive Summary (2019–2024)")

# Load base tables
sales = load_table("amazon_sales")
loss = load_table("order_loss_summary")

# KPIs
total_revenue = sales["total_price"].sum()
total_orders = len(sales)
total_loss = loss["total_value_lost"].sum()
total_lost_orders = len(loss)

col1, col2, col3 = st.columns(3)
col1.metric(" Total Revenue", f"${total_revenue:,.2f}")
col2.metric(" Orders Fulfilled", total_orders)
col3.metric(" Lost Revenue (Uncompleted)", f"${total_loss:,.2f}")

# Business Context
st.markdown("""
Welcome to the **Amazon Pricing Analytics Dashboard**.  
This project investigates pricing sensitivity, discount profitability, sales performance, and pricing simulation strategies using historical order data from 2019 to 2024.
""")

# Business Questions
st.markdown("###  Core Business Questions Addressed")
st.markdown("""
- **Which categories and regions show high price sensitivity?**
- **Are discount strategies actually profitable?**
- **Which salespeople consistently outperform, and why?**
- **What happens to revenue under simulated price and value changes?**
""")

# Data Footprint
st.markdown("###  Dataset Footprint")
st.markdown(f"""
- `amazon_sales` : {len(sales):,} completed orders
- `order_loss_summary` : {len(loss):,} lost/pending/returned orders
- Other derived insights come from views like `product_pricing_metric`, `region_behaviour_matrix`, and simulation outputs.
""")

#key insights
st.markdown("###  Key Insights")
st.markdown("""
            1.Beauty products in Asia and Toys in Europe, discounts work really well — customers respond a lot to price drops\n
            2.The low discount group achieves the highest margin and absolute profit per order, despite slightly lower completion
              than high-discount orders.\n
            3.The best salesperson archetype was the value Optimizer :- Low loss_rate, low discount_rate
            decent order_value. This is the ideal profile—profitable, doesn’t over-discount, and has low churn. 
            Probably great at understanding customer needs and targeting value.\n
""")
st.info("Explore detailed insights in the sections listed in the sidebar →")
