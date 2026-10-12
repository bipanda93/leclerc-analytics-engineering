"""Pipeline quotidien Leclerc : INSEE -> dbt Silver -> dbt Gold -> export CSV."""
from datetime import timedelta

import pendulum
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG
from alertes import alerte_slack

VENV = "/opt/leclerc_venv/bin"
PROJET = "/opt/leclerc"
DBT = (
    f"cd {PROJET}/dbt/leclerc_dbt && {VENV}/dbt build "
    f"--target prod --profiles-dir {PROJET}/dbt_profiles --indirect-selection cautious"
)

with DAG(
    dag_id="leclerc_daily",
    description="INSEE, dbt Silver et Gold, export CSV",
    schedule="0 6 * * *",
    start_date=pendulum.datetime(2026, 10, 1, tz="Europe/Paris"),
    catchup=False,
    default_args={"retries": 1, "retry_delay": timedelta(minutes=5), "on_failure_callback": alerte_slack},
    tags=["leclerc", "dbt", "snowflake"],
) as dag:

    extract_insee = BashOperator(
        task_id="extract_insee",
        bash_command=f"{VENV}/python {PROJET}/ingestion/insee_conjoncture_extract.py",
    )

    dbt_build_silver = BashOperator(
        task_id="dbt_build_silver",
        bash_command=f"{DBT} --select path:models/staging",
    )

    dbt_build_gold = BashOperator(
        task_id="dbt_build_gold",
        bash_command=f"{DBT} --select path:models/marts",
    )

    export_gold = BashOperator(
        task_id="export_gold",
        bash_command=f"{VENV}/python {PROJET}/ingestion/export_gold.py",
    )

    extract_insee >> dbt_build_silver >> dbt_build_gold >> export_gold
