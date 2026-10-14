"""Vérifie que le DAG leclerc_daily se charge et garde sa structure."""
import runpy
import sys
from datetime import timedelta
from pathlib import Path

DAG_FILE = Path(__file__).resolve().parent.parent / "dags" / "leclerc_daily.py"
sys.path.insert(0, str(DAG_FILE.parent))


def charger_dag():
    return runpy.run_path(str(DAG_FILE))["dag"]


def test_le_dag_se_charge():
    dag = charger_dag()
    assert dag.dag_id == "leclerc_daily"


def test_les_quatre_taches_existent():
    dag = charger_dag()
    assert set(dag.task_ids) == {
        "extract_insee", "dbt_build_silver", "dbt_build_gold", "export_gold",
    }


def test_l_ordre_des_taches():
    dag = charger_dag()
    assert dag.get_task("dbt_build_silver").upstream_task_ids == {"extract_insee"}
    assert dag.get_task("dbt_build_gold").upstream_task_ids == {"dbt_build_silver"}
    assert dag.get_task("export_gold").upstream_task_ids == {"dbt_build_gold"}


def test_pas_de_rattrapage_et_relances():
    dag = charger_dag()
    assert dag.catchup is False
    assert dag.default_args["retries"] >= 1


def test_insee_non_bloquant():
    dag = charger_dag()
    extract_insee = dag.get_task("extract_insee")
    assert extract_insee.retries == 3
    assert extract_insee.retry_exponential_backoff
    assert extract_insee.retry_delay == timedelta(minutes=5)
    assert dag.get_task("dbt_build_silver").trigger_rule == "all_done"
