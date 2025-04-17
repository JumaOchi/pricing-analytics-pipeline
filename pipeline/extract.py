import pandas as pd
import logging
import os

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

REQUIRED_COLUMNS = {'product_name', 'unit_price', 'order_date', 'customer_id', 'region', 'quantity_sold', 'discount_%', 'order_status', 'product_category',}

def extract_data(file_path: str) -> pd.DataFrame:
    """
    Extract and clean data from an Excel file.

    Args:
        file_path (str): Path to the Excel file.

    Returns:
        pd.DataFrame: Cleaned DataFrame.
    """
    if not os.path.exists(file_path):
        logging.error(f"File not found: {file_path}")
        return pd.DataFrame()

    try:
        logging.info("Reading Excel file...")
        df = pd.read_excel(file_path)
        logging.info(f"Initial data shape: {df.shape}")
    except Exception as e:
        logging.error(f"Error reading file: {e}")
        return pd.DataFrame()

    # Clean the data
    df = df.dropna()
    df = df.drop_duplicates()
    df = df.reset_index(drop=True)

    # Clean column names
    df.columns = df.columns.str.strip()
    df.columns = df.columns.str.replace(' ', '_', regex=False)
    df.columns = df.columns.str.lower()
    df.columns = df.columns.str.replace('(', '', regex=False)
    df.columns = df.columns.str.replace(')', '', regex=False)

    # Validate schema
    if not REQUIRED_COLUMNS.issubset(df.columns):
        missing = REQUIRED_COLUMNS - set(df.columns)
        logging.warning(f"Missing expected columns: {missing}")

    logging.info(f"Final cleaned shape: {df.shape}")
    
    # Save cleaned raw file (optional)
    output_path = "/home/juma/pricing_analysis/pricing-analytics-pipeline/data/staged/cleaned_raw.csv"
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    df.to_csv(output_path, index=False)
    logging.info(f"Cleaned data saved to {output_path}")

    return df


if __name__ == "__main__":
    data = extract_data("/home/juma/pricing_analysis/pricing-analytics-pipeline/data/raw/amazon_sales_dataset_2019_2024_corrected.xlsx")
    logging.info("Sample of extracted data:")
    print(data.head(3))
