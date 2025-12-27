# The docker-compose environment we have prepared is a “quick-start” one. It was not
# designed to be used in production and it has a number of caveats - one of them being
# that the best way to recover from any problem is to clean it up and restart from
#  scratch.

# The best way to do this is to:

TEMP_DIR=".tmp/airflow-services"
cd $TEMP_DIR

# - Run docker compose down --volumes --remove-orphans command in the directory you
#   downloaded the docker-compose.yaml file

docker compose down --volumes --remove-orphans

# - Remove the entire directory where you downloaded the docker-compose.yaml file rm
#   -rf '<DIRECTORY>'

if [ -d "$TEMP_DIR" ]; then
    rm -r "$TEMP_DIR"
fi
