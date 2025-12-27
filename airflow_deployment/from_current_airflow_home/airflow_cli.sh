# 5. Running CLI commands

HOST_AIRFLOW_HOME="$HOME/airflow"

# change to the airflow home dir
cd $HOST_AIRFLOW_HOME

# You can run CLI commands in the airflow container by running:

# 5.1. download the wrapper script

curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/airflow.sh'

# 5.4. test the wrapper script
bash ./airflow.sh "${@}"