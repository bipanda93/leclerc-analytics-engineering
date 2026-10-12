"""Alerte Slack en cas d'échec d'une tâche Airflow."""
import logging
import os

import requests

log = logging.getLogger(__name__)


def alerte_slack(context):
    ti = context["ti"]
    lien = (
        f"http://localhost:8080/dags/{ti.dag_id}/runs/{ti.run_id}"
        f"/tasks/{ti.task_id}"
    )
    message = (
        f":red_circle: *Échec Airflow*\n"
        f"*DAG* : {ti.dag_id}\n"
        f"*Tâche* : {ti.task_id}\n"
        f"*Run* : {ti.run_id}\n"
        f"*Tentative* : {ti.try_number}\n"
        f"*Logs* : {lien}"
    )
    url = os.getenv("SLACK_WEBHOOK_URL")
    if not url:
        log.warning("SLACK_WEBHOOK_URL absente, alerte non envoyée : %s", message)
        return
    try:
        requests.post(url, json={"text": message}, timeout=10).raise_for_status()
    except requests.RequestException as erreur:
        log.error("Envoi de l'alerte Slack impossible : %s", erreur)
