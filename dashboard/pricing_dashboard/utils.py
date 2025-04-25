from sqlalchemy import create_engine
import pandas as pd
from dotenv import load_dotenv
import os

# Find and load .env from the root 'config' directory
root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
dotenv_path = os.path.join(root_dir, "config", ".env")
load_dotenv(dotenv_path)

# Set up connection to PostgreSQL
def get_connection():
    return create_engine(f"postgresql://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}")

def load_table(table_name):
    engine = get_connection()
    query = f"SELECT * FROM {table_name}"
    return pd.read_sql(query, engine)
