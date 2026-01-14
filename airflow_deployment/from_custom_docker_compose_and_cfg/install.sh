#!/bin/bash

# This script will be used to deploy the airflow docker operator

# steps:
# 0. create the temporary dir
# 1. Copy the docker compose file and the airflow.cfg file to the host airflow home dir
# 2. Change to the host airflow home dir
# 3. Deploy airflow with the docker compose file
# 4. Running Airflow
# 5. Access the Airflow UI

# ---

# 0. create the temporary dir

HOST_AIRFLOW_HOME="/opt/airflow"

if [ ! -d "$HOST_AIRFLOW_HOME" ]; then
    # if mkdir doesn't work, try with sudo
    if ! mkdir -p $HOST_AIRFLOW_HOME; then
        echo "Creating $HOST_AIRFLOW_HOME with sudo"
        sudo mkdir -p $HOST_AIRFLOW_HOME
        sudo chown -R $(id -u):$(id -g) $HOST_AIRFLOW_HOME
        sudo chmod -R 755 $HOST_AIRFLOW_HOME
        mkdir -p $HOST_AIRFLOW_HOME/{config,dags,logs,plugins,config}
    fi
fi

# ---

# 1. Copy the docker compose file and the airflow.cfg file to the host airflow home dir

cp docker-compose.yaml $HOST_AIRFLOW_HOME/
cp airflow.cfg $HOST_AIRFLOW_HOME/config/
chmod a+r $HOST_AIRFLOW_HOME/config/airflow.cfg
cp ../../dags/* $HOST_AIRFLOW_HOME/dags/

# ---

# 2. Change to the host airflow home dir

cd $HOST_AIRFLOW_HOME

# ---

# 3. Deploy airflow with the docker compose file

# 3.1. Initialize the environment

# Set the right Airflow user
if [ ! -f ".env" ]; then
    touch .env
fi
echo -e "AIRFLOW_UID=$(id -u)" >> .env

# 3.2. Initialize the database

# On all operating systems, you need to run database migrations and create the first
# user account. To do this, run.

docker compose up "airflow-init"

# After initialization is complete, you should see output related to files, folders,
# and plug-ins and finally a message like this:
# airflow-init-1 exited with code 0

# The account created has the login airflow and the password airflow

# ---

# 4. Running Airflow

docker compose up -d

# ---

# 4. Access the Airflow UI

# Open http://<host_or_airflow_server_container_ip>:8080 in your web browser.
# Log in with the username airflow and the password airflow.

# ---

# 5. Running CLI commands

# You can run CLI commands in the airflow container by running:

bash airflow_cli.sh info
