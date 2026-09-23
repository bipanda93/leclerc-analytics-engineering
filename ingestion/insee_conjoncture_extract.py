import requests
import xml.etree.ElementTree as ET
import pandas as pd
from snowflake.connector.pandas_tools import write_pandas
from snowflake_utils import get_connection, SNOWFLAKE_DATABASE, SNOWFLAKE_SCHEMA

INSEE_URL = "https://bdm.insee.fr/series/sdmx/data/SERIES_BDM/011813717"
INSEE_TABLE = "INSEE_CONJONCTURE"


def fetch_insee_series():
    response = requests.get(INSEE_URL)
    response.raise_for_status()

    root = ET.fromstring(response.text)
    observations = []

    for obs in root.findall('.//{*}Obs'):
        period = obs.get("TIME_PERIOD")
        value = obs.get("OBS_VALUE")

        try:
            value = float(value)
        except (ValueError, TypeError):
            continue

        observations.append({
            "period": period,
            "value": value,
        })

    return observations


def build_insee_dataframe(observations: list[dict], indicator_name: str) -> pd.DataFrame:
    df = pd.DataFrame(observations)
    df["indicator"] = indicator_name
    return df


def create_insee_table(conn):
    with conn.cursor() as cur:
        cur.execute(f"""
            CREATE OR REPLACE TABLE {SNOWFLAKE_DATABASE}.{SNOWFLAKE_SCHEMA}.{INSEE_TABLE} (
                period VARCHAR,
                value FLOAT,
                indicator VARCHAR
            )
        """)


def write_insee_to_bronze(conn, df: pd.DataFrame):
    df.columns = [c.upper() for c in df.columns]
    success, nchunks, nrows, _ = write_pandas(
        conn,
        df,
        table_name=INSEE_TABLE,
        database=SNOWFLAKE_DATABASE,
        schema=SNOWFLAKE_SCHEMA,
    )
    return success, nrows


if __name__ == "__main__":
    print("Récupération de la série INSEE...")
    observations = fetch_insee_series()
    print(f"{len(observations)} observations récupérées")

    df = build_insee_dataframe(observations, "IPC_ALIMENTATION")

    with get_connection() as conn:
        print("Création de la table cible...")
        create_insee_table(conn)

        print("Écriture vers Bronze...")
        success, nrows = write_insee_to_bronze(conn, df)
        print(f"Écriture {'réussie' if success else 'échouée'} — {nrows} lignes chargées")