# The docker-compose environment we have prepared is a “quick-start” one. It was not
# designed to be used in production and it has a number of caveats - one of them being
# that the best way to recover from any problem is to clean it up and restart from
#  scratch.

# The best way to do this is to:

HOST_AIRFLOW_HOME="/opt/airflow"
cd $HOST_AIRFLOW_HOME

# - Run docker compose down --volumes --remove-orphans command in the directory you
#   downloaded the docker-compose.yaml file

docker compose down --volumes --remove-orphans
