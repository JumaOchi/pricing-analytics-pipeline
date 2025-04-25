import os
import pandas as pd
from sqlalchemy import create_engine

# Check if we're in Streamlit Cloud (secrets available) or local (load .env)
def get_connection():
    try:
        # Use Streamlit Cloud secrets if available
        import streamlit as st
        url = st.secrets["connections"]["postgres"]["url"]
    except Exception:
        # Fallback to local .env
        from dotenv import load_dotenv

        # Navigate up to project root to find .env in config/
        root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        dotenv_path = os.path.join(root_dir, "config", ".env")
        load_dotenv(dotenv_path)

        user = os.getenv("DB_USER")
        password = os.getenv("DB_PASSWORD")
        host = os.getenv("DB_HOST")
        port = os.getenv("DB_PORT")
        db = os.getenv("DB_NAME")

        url = f"postgresql://{user}:{password}@{host}:{port}/{db}"

    return create_engine(url)

def load_table(table_name):
    engine = get_connection()
    query = f"SELECT * FROM {table_name}"
    return pd.read_sql(query, engine)

