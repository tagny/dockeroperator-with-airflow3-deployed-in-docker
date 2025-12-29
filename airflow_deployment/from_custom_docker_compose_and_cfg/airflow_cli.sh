# 5. Running CLI commands

HOST_AIRFLOW_HOME="/opt/airflow"

# change to the airflow home dir
cd $HOST_AIRFLOW_HOME

# You can run CLI commands in the airflow container by running:

# 5.1. download the wrapper script
if [ ! -f "airflow.sh" ]; then
    curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/airflow.sh'
fi

# 5.3. test the wrapper script
bash ./airflow.sh "${@}"
