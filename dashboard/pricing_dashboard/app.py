import streamlit as st

# Set up page config
st.set_page_config(
    page_title="Pricing Analytics Dashboard",
    page_icon="📊",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Landing Page
st.title("Amazon Pricing Analytics Dashboard")
st.markdown("""
Welcome to the **Pricing Analytics Dashboard** — a powerful tool for analyzing revenue performance, pricing sensitivity, discount effectiveness, and salesperson impact across different Amazon regions.

Use the **sidebar** to navigate through each analysis section:

1.  **Executive Summary** – KPIs, revenue trends, and lost sales insights  
2.  **Price Sensitivity** – Explore how regions and categories react to price changes  
3.  **Discount Profitability** – See if your discounts are worth it or killing your margins  
4.  **Salespeople Performance** – Uncover high-performers and strategic pricing behavior  
5.  **What-If Simulations** – Model the impact of changing price and discount scenarios

---

This project was built with:
- **python scripts** for data processing and cleaning(ETL)
- **PostgreSQL** for structured data storage  
- **Python notebooks** for modeling and simulations  
- **Streamlit** for interactive business storytelling
- **Bash scripts** for automating processes

Explore each page to dive into the data and uncover insights that can drive your pricing strategy forward.  
""")
