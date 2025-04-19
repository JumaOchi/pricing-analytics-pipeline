import pandas as pd
from sqlalchemy import create_engine
import logging
import os
from config.db_config import DB_CONFIG

# Logging setup
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

def get_connection_string(config: dict) -> str:
    return f"postgresql+psycopg2://{config['user']}:{config['password']}@{config['host']}:{config['port']}/{config['database']}"

def load_to_postgres(csv_path: str, table_name: str):
    """
    Load CSV data into a PostgreSQL table.

    Args:
        csv_path (str): Path to the CSV file.
        table_name (str): Target table name in PostgreSQL.
    """
    if not os.path.exists(csv_path):
        logging.error(f"CSV file not found at {csv_path}")
        return

    try:
        df = pd.read_csv(csv_path)
        logging.info(f"Read {len(df)} records from {csv_path}")
    except Exception as e:
        logging.error(f"Failed to read CSV: {e}")
        return

    try:
        engine = create_engine(get_connection_string(DB_CONFIG))
        with engine.connect() as conn:
            df.to_sql(table_name, con=conn, if_exists='replace', index=False)
            logging.info(f"Successfully loaded data into '{table_name}' table in PostgreSQL.")
    except Exception as e:
        logging.error(f"Database load failed: {e}")


if __name__ == "__main__":
    transformed_csv = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/transformed.csv"
    order_loss_csv = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/order_loss_summary.csv"

    # Load both
    load_to_postgres(transformed_csv, table_name="amazon_sales")
    load_to_postgres(order_loss_csv, table_name="order_loss_summary")
