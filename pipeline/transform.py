import pandas as pd
import logging
import os
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def transform_data(file_path: str) -> pd.DataFrame:
    """
    Transform sales data: clean, feature engineer, and enrich with analytics-ready columns.
    Also analyzes pending and returned orders separately.

    Args:
        file_path (str): Path to cleaned data file (CSV).

    Returns:
        pd.DataFrame: Final transformed DataFrame with engineered features (only for completed orders).
    """

    if not os.path.exists(file_path):
        logging.error(f"File not found: {file_path}")
        return pd.DataFrame()

    try:
        logging.info("Reading cleaned data file...")
        df_raw = pd.read_csv(file_path)
        logging.info(f"Initial data shape: {df_raw.shape}")
    except Exception as e:
        logging.error(f"Error reading file: {e}")
        return pd.DataFrame()

    # Clean data basics
    df_raw = df_raw[(df_raw['quantity_sold'] > 0) & (df_raw['unit_price'] > 0)]
    df_raw['order_date'] = pd.to_datetime(df_raw['order_date'])


    # ========= ANALYZE NON-COMPLETED ORDERS =========
    # Normalize the order status
    df_raw['order_status_clean'] = df_raw['order_status'].str.strip().str.lower()

    # Flexible match for returned, pending, or cancelled (any variation)
    df_non_completed = df_raw[
        df_raw['order_status_clean'].str.contains(r'return|pending|cancel', regex=True)
    ].copy()
    logging.info(f" Non-completed entries: {df_non_completed.shape[0]}")
    logging.info(f" Unique statuses in non-completed:\n{df_non_completed['order_status'].value_counts()}")


    if not df_non_completed.empty:
        df_non_completed['discounted_price'] = df_non_completed['unit_price'] * (1 - df_non_completed['discount_%'] / 100)
        df_non_completed['total_price'] = df_non_completed['discounted_price'] * df_non_completed['quantity_sold']

        # --- Aggregate data by customer_id ---
        enriched_loss_summary = df_non_completed.groupby(
            ['customer_id', 'order_status', 'payment_method', 'region']
        ).agg(
            num_orders=('order_id', 'nunique'),
            num_customers=('customer_id', 'nunique'),
            total_value_lost=('total_price', 'sum'),
            avg_discount_applied=('discount_%', 'mean'),
            units_affected=('quantity_sold', 'sum'),
            avg_order_value_lost=('total_price', 'mean')
        ).reset_index()

        logging.info("Enriched Loss Summary (Non-completed orders):")
        logging.info(f"\n{enriched_loss_summary}")

        # Save enriched loss summary for DBT
        enriched_path = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/order_loss_summary.csv"
        os.makedirs(os.path.dirname(enriched_path), exist_ok=True)
        enriched_loss_summary.to_csv(enriched_path, index=False)
        logging.info(f"Enriched order loss summary saved to {enriched_path}")

    # ========= FILTER ONLY COMPLETED ORDERS =========
    df = df_raw[df_raw['order_status'].str.lower() == 'completed'].copy()

    # --- Feature Engineering ---
    df['discounted_price'] = df['unit_price'] * (1 - df['discount_%'] / 100)
    df['total_price'] = df['discounted_price'] * df['quantity_sold']
    df['cost_price'] = df['total_price'] / (1 + df['profit_margin'] / 100)
    df['profit'] = df['total_price'] - df['cost_price']
    df['computed_margin_pct'] = (df['profit'] / df['cost_price']) * 100

    # --- Customer Insights ---
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

    df = df.merge(
        customer_summary[['customer_id', 'num_orders', 'total_spent', 'recency_days', 'avg_order_value']],
        on='customer_id',
        how='left'
    )

    # --- Salesperson Insights ---
    salesperson_summary = df.groupby('salesperson').agg({
        'order_id': 'nunique',
        'customer_id': 'nunique',
        'total_price': 'sum',
        'profit': 'sum'
    }).reset_index()

    salesperson_summary.columns = ['salesperson', 'num_orders_by_sp', 'num_customers_by_sp', 'total_sales_by_sp', 'total_profit_by_sp']
    salesperson_summary['avg_order_value_by_sp'] = salesperson_summary['total_sales_by_sp'] / salesperson_summary['num_orders_by_sp']
    salesperson_summary['avg_profit_per_order_by_sp'] = salesperson_summary['total_profit_by_sp'] / salesperson_summary['num_orders_by_sp']

    df = df.merge(
        salesperson_summary,
        on='salesperson',
        how='left'
    )

    # --- Final Column Selection (Cleaned Up) ---
    selected_columns = [
        'order_id', 'order_date', 'customer_id', 'region',
        'product_category', 'quantity_sold', 'unit_price',
        'discounted_price', 'total_price', 'profit',
        'salesperson', 'num_orders', 'total_spent', 'recency_days', 'avg_order_value',
        'num_orders_by_sp', 'total_sales_by_sp', 'avg_profit_per_order_by_sp'
    ]

    final_df = df[selected_columns]

    # --- Save Transformed Dataset ---
    output_path = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/transformed.csv"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    final_df.to_csv(output_path, index=False)
    logging.info(f"Transformed dataset saved to {output_path}")
    logging.info(f"Final data shape: {final_df.shape}")

    return final_df



if __name__ == "__main__":
     transform_data("/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/cleaned_raw.csv")
      