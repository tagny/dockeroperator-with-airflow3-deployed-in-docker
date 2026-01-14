# This is a simple DAG that runs a Docker container
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG
from datetime import datetime

with DAG(
    'docker_helloworld',
    schedule=None,
    tags=["tagny", "docker_operator", "example"],
    doc_md="This is a simple DAG that runs a Docker container",
    catchup=False,
    start_date=datetime(2021, 1, 1),
) as dag:
    
    task = DockerOperator(
        task_id='docker_helloworld',
        image='alpine',
        command='echo "Hello World!"',
    )
