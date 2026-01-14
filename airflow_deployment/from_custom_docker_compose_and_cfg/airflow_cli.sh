# 5. Running CLI commands

HOST_AIRFLOW_HOME="/opt/airflow"

# change to the airflow home dir
cd $HOST_AIRFLOW_HOME

# You can run CLI commands in the airflow container by running:

if [ $# -gt 0 ]; then
    docker compose run --rm airflow-cli "${@}"
else
    docker compose run --rm airflow-cli
fi
