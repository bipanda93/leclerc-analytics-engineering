FROM apache/airflow:3.3.2

USER root
RUN mkdir -p /opt/leclerc_venv && chown airflow:0 /opt/leclerc_venv
USER airflow

RUN python -m venv /opt/leclerc_venv \
 && /opt/leclerc_venv/bin/pip install --no-cache-dir \
      "dbt-snowflake~=1.12.0" \
      "snowflake-connector-python[pandas]" \
      python-dotenv \
      requests \
      pandas