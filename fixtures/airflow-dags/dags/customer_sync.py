from airflow.decorators import dag, task
import pendulum

@dag(dag_id="customer_sync", schedule="@hourly", start_date=pendulum.datetime(2026, 1, 1))
def customer_sync():
    @task
    def sync():
        return 1
    sync()

customer_sync()
