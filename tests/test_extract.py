import pytest
import pandas as pd
from pipeline.extract import extract_data

def test_extract_success():
    df = extract_data("/home/juma/pricing_analysis/pricing-analytics-pipeline/data/raw/amazon_sales_dataset_2019_2024_corrected.xlsx")
    assert isinstance(df, pd.DataFrame)
    assert not df.empty
    assert 'order_id' in df.columns

def test_extract_file_not_found():
    df = extract_data("/data/raw/amazon_sales_dataset_2019_2024_corrected.xlsx")
    assert df.empty
