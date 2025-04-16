import pandas as pd
from pipeline.transform import transform_data

def test_transform_creates_total_price(tmp_path):
    # All required columns for transform_data()
    data = {
        'order_id': [1, 2],
        'order_date': ['2024-01-01', '2024-01-02'],
        'quantity_sold': [2, 3],
        'unit_price': [100.0, 150.0],
        'profit_margin': [20.0, 25.0],
        'discount_%': [10.0, 20.0],
        'order_status': ['Completed', 'Completed'],
        'customer_id': ['C1', 'C2'],
        'customer_name': ['Alice', 'Bob'],
        'region': ['East', 'West'],
        'product_category': ['Electronics', 'Books'],
        'product_name': ['Laptop', 'Novel'],
        'salesperson': ['John', 'Jane'],
        'payment_method': ['Card', 'Cash']
    }

    df = pd.DataFrame(data)
    test_file = tmp_path / "cleaned_raw.csv"
    df.to_csv(test_file, index=False)

    # Call transformation
    transformed = transform_data(str(test_file))

    # Assertions
    assert 'total_price' in transformed.columns
    assert 'profit' in transformed.columns
    assert 'avg_order_value' in transformed.columns
    assert transformed.shape[0] == 2
    assert transformed.loc[0, 'total_price'] == 100 * (1 - 0.1) * 2  # discounted * quantity
    assert transformed.loc[0, 'profit'] == transformed.loc[0, 'total_price'] * 0.2  # profit margin

