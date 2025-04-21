import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), 'config/.env'))

db_host = os.getenv("DB_HOST")
db_port = os.getenv("DB_PORT")
db_name = os.getenv("DB_NAME")
db_user = os.getenv("DB_USER")
db_pass = os.getenv("DB_PASSWORD")

DATABASE_URL = f"postgresql://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}"
engine = create_engine(DATABASE_URL)

MODELS_DIR = "models"

for filename in os.listdir(MODELS_DIR):
    if filename.endswith(".sql"):
        view_name = filename.replace(".sql", "")
        filepath = os.path.join(MODELS_DIR, filename)

        with open(filepath, "r") as f:
            sql_body = f.read().strip().rstrip(";")

        full_sql = f"CREATE OR REPLACE VIEW {view_name} AS {sql_body};"

        try:
            with engine.begin() as conn:
                conn.execute(text(full_sql))  #WRAPPED WITH text()
                print(f"Created view: {view_name}")
        except Exception as e:
            print(f"Failed to create view: {view_name}")
            print(str(e))

