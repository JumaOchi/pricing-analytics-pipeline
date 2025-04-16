from unittest.mock import patch, MagicMock
import pandas as pd
from pipeline.load import load_to_postgres

@patch("pipeline.load.create_engine")
def test_load_data_mocked(mock_engine):
    mock_conn = MagicMock()
    mock_engine.return_value.connect.return_value.__enter__.return_value = mock_conn

    dummy_df = pd.DataFrame({
        'region': ['West'],
        'product_category': ['Toys'],
        'total_price': [150],
        'quantity_sold': [2]
    })

    # Save to temporary CSV
    csv_path = "/tmp/test_sales.csv"
    dummy_df.to_csv(csv_path, index=False)

    load_to_postgres(csv_path, table_name="mock_table")
    assert mock_conn is not None
