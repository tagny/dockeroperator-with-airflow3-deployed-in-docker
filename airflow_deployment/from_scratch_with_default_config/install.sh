#!/bin/bash

# This script will be used to deploy the airflow docker operator

# steps:
# 0. create the temporary dir
# 1. Download the docker compose file
# 2. Deploy airflow with the docker compose file
# 3. Running Airflow

# ---

# 0. create the temporary dir

HOST_AIRFLOW_HOME=".tmp/airflow-services"

mkdir -p $HOST_AIRFLOW_HOME

cd $HOST_AIRFLOW_HOME

# ---

# 1. Download the docker compose file

curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/docker-compose.yaml'

# ---

# 2. Deploy airflow with the docker compose file

# 2.1. Initialize the environment

# Setting the right Airflow user

mkdir -p ./dags ./logs ./plugins ./config
echo -e "AIRFLOW_UID=$(id -u)" > .env

# Initialize airflow.cfg (Optional)
# to initialize airflow.cfg with default values

docker compose run airflow-cli airflow config list

# 2.2. Initialize the database

# On all operating systems, you need to run database migrations and create the first user account. To do this, run.

docker compose up "airflow-init"

# After initialization is complete, you should see output related to files, folders, and plug-ins and finally a message like this:
# airflow-init-1 exited with code 0

# The account created has the login airflow and the password airflow

# ---

# 3. Running Airflow

docker compose up -d

# ---
