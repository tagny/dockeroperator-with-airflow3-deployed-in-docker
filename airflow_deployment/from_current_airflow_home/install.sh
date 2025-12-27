#!/bin/bash

# This script will be used to deploy the airflow docker operator

# steps:
# 0. create the temporary dir
# 1. Download the docker compose file
# 2. Deploy airflow with the docker compose file
# 3. Running Airflow

# ---

# 0. create the temporary dir

HOST_AIRFLOW_HOME="$HOME/airflow"

# create the airflow home dir if it does not exist
if [ ! -d "$HOST_AIRFLOW_HOME" ]; then
    mkdir -p "$HOST_AIRFLOW_HOME"
fi

# change to the airflow home dir
cd $HOST_AIRFLOW_HOME

# ---

# 1. Download the docker compose file

curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/docker-compose.yaml'

# ---

# 2. Deploy airflow with the docker compose file

# 2.1. Initialize the environment

# Setting the right Airflow user

# Create the necessary directories for Airflow to store its data if they do not exist
if [ ! -d "./dags" ]; then
    mkdir -p ./dags
fi
if [ ! -d "./logs" ]; then
    mkdir -p ./logs
fi
if [ ! -d "./plugins" ]; then
    mkdir -p ./plugins
fi
if [ ! -d "./config" ]; then
    mkdir -p ./config

    # Initialize airflow.cfg (Optional)
    # to initialize airflow.cfg with default values
    docker compose run airflow-cli airflow config list
fi

# Set the right Airflow user
if [ ! -f ".env" ]; then
touch .env
fi
echo -e "AIRFLOW_UID=$(id -u)" >> .env

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

# 4. Access the Airflow UI

# Open http://localhost:8080 in your web browser.
# Log in with the username airflow and the password airflow.

# ---

# 5. Running CLI commands

# You can run CLI commands in the airflow container by running:

# 5.1. download the wrapper script

curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/airflow.sh'

# 5.2. make the wrapper script executable

chmod +x airflow.sh

# 5.3. move the wrapper script to the PATH

export PATH=$PATH:$(pwds)

# 5.4. test the wrapper script
./airflow.sh info
