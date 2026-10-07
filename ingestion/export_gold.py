import os
from pathlib import Path

from dotenv import load_dotenv
import snowflake.connector

load_dotenv()

TABLES = [
    "MART_RFM_CUSTOMERS",
    "MART_KPIS_MOIS_RAYON",
    "MART_KPIS_MOIS",
    "MART_TENDANCES_JOUR",
    "MART_MBA_PANIERS",
    "MART_MBA_REGLES",
]
OUT_DIR = Path(__file__).resolve().parent.parent / "data" / "gold"


def main():
    user = os.getenv("SNOWFLAKE_DBT_USER")
    password = os.getenv("SNOWFLAKE_DBT_PASSWORD")
    if not user or not password:
        raise EnvironmentError("SNOWFLAKE_DBT_USER ou SNOWFLAKE_DBT_PASSWORD manquant dans .env")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    conn = snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=user,
        password=password,
        role="LECLERC_DBT_TRANSFORMER",
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
    )
    try:
        for table in TABLES:
            cur = conn.cursor()
            cur.execute(f"select * from LECLERC.GOLD.{table}")
            df = cur.fetch_pandas_all()
            path = OUT_DIR / f"{table.lower()}.csv"
            df.to_csv(path, index=False)
            print(f"{table} : {len(df)} lignes -> {path.name}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
