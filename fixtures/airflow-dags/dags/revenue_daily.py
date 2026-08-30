from airflow import DAG
from airflow.operators.empty import EmptyOperator
import pendulum

with DAG(
    dag_id="revenue_daily",
    schedule="0 6 * * *",
    start_date=pendulum.datetime(2026, 1, 1),
    catchup=False,
) as dag:
    EmptyOperator(task_id="extract") >> EmptyOperator(task_id="load")
