from sqlalchemy import create_engine
import pandas as pd
import os

# Optional: Only import dotenv if running locally
try:
    from dotenv import load_dotenv
    is_local = True
except ImportError:
    is_local = False

# Load .env if local
if is_local:
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    dotenv_path = os.path.join(root_dir, "config", ".env")
    if os.path.exists(dotenv_path):
        load_dotenv(dotenv_path)

# Set up connection to PostgreSQL
def get_connection():
    # Streamlit Cloud (secrets.toml)
    if "connections.postgres.url" in os.environ:
        return create_engine(os.environ["connections.postgres.url"])

    # Local development (.env)
    user = os.getenv("DB_USER")
    password = os.getenv("DB_PASSWORD")
    host = os.getenv("DB_HOST")
    port = os.getenv("DB_PORT")
    db = os.getenv("DB_NAME")
    return create_engine(f"postgresql://{user}:{password}@{host}:{port}/{db}")

# Load table into DataFrame
def load_table(table_name):
    engine = get_connection()
    query = f"SELECT * FROM {table_name}"
    return pd.read_sql(query, engine)
