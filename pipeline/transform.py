import pandas as pd
import logging
import os
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def transform_data(file_path: str) -> pd.DataFrame:
    """
    Transform sales data: clean, feature engineer, and enrich with analytics-ready columns.

    Args:
        file_path (str): Path to cleaned data file (CSV).

    Returns:
        pd.DataFrame: Final transformed DataFrame with engineered features.
    """

    if not os.path.exists(file_path):
        logging.error(f"File not found: {file_path}")
        return pd.DataFrame()

    try:
        logging.info("Reading cleaned data file...")
        df = pd.read_csv(file_path)
        logging.info(f"Initial data shape: {df.shape}")
    except Exception as e:
        logging.error(f"Error reading file: {e}")
        return pd.DataFrame()

    # BASIC CLEANING
    df = df[(df['quantity_sold'] > 0) & (df['unit_price'] > 0)]
    df = df[df['order_status'].str.lower() == 'completed']
    df['order_date'] = pd.to_datetime(df['order_date'])

    # FEATURE ENGINEERING
    df['discounted_price'] = df['unit_price'] * (1 - df['discount_%'] / 100)
    df['total_price'] = df['discounted_price'] * df['quantity_sold']
    df['profit'] = df['total_price'] * df['profit_margin'] / 100

    # CUSTOMER INSIGHTS
    latest_date = df['order_date'].max()
    customer_summary = df.groupby('customer_id').agg({
        'order_id': 'nunique',
        'total_price': 'sum',
        'order_date': ['min', 'max']
    })
    customer_summary.columns = ['num_orders', 'total_spent', 'first_order', 'last_order']
    customer_summary['recency_days'] = (latest_date - customer_summary['last_order']).dt.days
    customer_summary['avg_order_value'] = customer_summary['total_spent'] / customer_summary['num_orders']
    customer_summary = customer_summary.reset_index()

    # Merge back to main data
    df = df.merge(customer_summary[['customer_id', 'num_orders', 'total_spent', 'recency_days', 'avg_order_value']],
                  on='customer_id', how='left')

    # ========== FINAL COLUMN SELECTION ==========
    selected_columns = [
        'order_id', 'order_date', 'customer_id', 'customer_name', 'region',
        'product_category', 'product_name', 'quantity_sold', 'unit_price',
        'discount_%', 'discounted_price', 'total_price', 'profit_margin', 'profit',
        'salesperson', 'payment_method', 'num_orders', 'total_spent', 'recency_days', 'avg_order_value'
    ]

    final_df = df[selected_columns]

    # ========== SAVE ==========
    output_path = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/transformed.csv"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    final_df.to_csv(output_path, index=False)
    logging.info(f"Transformed dataset saved to {output_path}")
    logging.info(f"Final data shape: {final_df.shape}")

    return final_df


if __name__ == "__main__":
     transform_data("/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/cleaned_raw.csv")
      