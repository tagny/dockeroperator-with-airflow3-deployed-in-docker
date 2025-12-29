# Deploying Airflow in Docker with custom docker compose and config file

## Prerequisites

- Docker and Docker Compose (better Docker Desktop)
- a customized docker compose file: download a default one with `curl -LfO 'https://airflow.apache.org/docs/apache-airflow/3.1.5/docker-compose.yaml'` and modify it
- a customized airflow.cfg file:
    - one from your standalone airflow deployment used for development
    - or a new one with default values: `docker compose run airflow-cli airflow config list`

## What I customized

### docker-compose.yaml

To use restart policies, Docker provides the following options:

no: Containers won’t restart automatically.
on-failure[:max-retries]: Restart the container if it exits with a non-zero exit code, and provide a maximum number of attempts for the Docker daemon to restart the container.
always: Always restart the container if it stops.
unless-stopped: Always restart the container unless it was stopped arbitrarily, or by the Docker daemon.

```yaml
x-airflow-common:
  &airflow-common
  environment:
    &airflow-common-env
    AIRFLOW__CORE__LOAD_EXAMPLES: 'false'
    AIRFLOW__DAG_PROCESSOR__REFRESH_INTERVAL: '30'
    AIRFLOW__CORE__DEFAULT_TIMEZONE: 'Europe/Paris'

  volumes:
    - ${AIRFLOW_PROJ_DIR:-.}/dags:/opt/airflow/dags
    - ${AIRFLOW_PROJ_DIR:-.}/logs:/opt/airflow/logs
    - ${AIRFLOW_PROJ_DIR:-.}/config:/opt/airflow/config
    - ${AIRFLOW_PROJ_DIR:-.}/plugins:/opt/airflow/plugins
    - /var/run/docker.sock:/var/run/docker.sock
    - $HOME/.docker:/home/airflow/.docker
    - /tmp:/tmp
  command: ["chown", "-R", "airflow:airflow", "/opt/airflow"]
```

### airflow.cfg

```ini
[core]
default_timezone = Europe/Paris
simple_auth_manager_all_admins = False
parallelism = 16
max_active_tasks_per_dag = 10
max_active_runs_per_dag = 2
load_examples = False

```

### Docker Desktop (macOs)

This error might occur if you are using Docker Desktop (macOs):

```
The path /opt/airflow/dags is not shared from the host and is not known to Docker.
You can configure shared paths from Docker -> Preferences... -> Resources -> File Sharing.
See https://docs.docker.com/go/mac-file-sharing/ for more info.
```

To fix it:
- Open Docker Desktop
- Go to Preferences
- Go to Resources
- Go to File Sharing
- Add /opt

## Installation

Run the install.sh script:
```bash
bash -e -x ./install.sh
```