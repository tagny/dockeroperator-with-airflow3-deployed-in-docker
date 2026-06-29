# DockerOperator with Airflow 3 — Deployed in Docker

A hands-on demo showing how to deploy **Apache Airflow 3** inside Docker and run a DAG that uses the Airflow `DockerOperator`.

This repository includes a root-user deployment path under `root-user/`, with scripts that install Airflow to `/opt/airflow`, configure Docker socket access, and execute the example DAG.

---

## What this project demonstrates

- Deploying Apache Airflow 3 using `docker compose`
- Running Airflow inside Docker while allowing the scheduler to launch sibling containers via `/var/run/docker.sock`
- Automating deployment, DAG execution, and health checks with shell scripts
- Using `DockerOperator` to run a local `helloworld` container image from a DAG

---

## Prerequisites

- Linux host
- Docker Engine ≥ 20.10
- Docker Compose plugin available as `docker compose`
- `curl`
- `jq`
- `bash` ≥ 4

> The `root-user` scripts expect a Linux host and may require `sudo` or root privileges because they deploy to `/opt/airflow`.

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/tagny/dockeroperator-with-airflow3-deployed-in-docker.git
cd dockeroperator-with-airflow3-deployed-in-docker

# Build the local image used by the example DAG
docker build -t helloworld .

# Run the root-user Airflow deployment scripts
sudo bash root-user/deploy_airflow.sh

# Trigger the example DAG
sudo bash root-user/run_dag.sh docker_helloworld
```

Once deployed, the Airflow UI is available at:

- http://localhost:8080
- username: `airflow`
- password: `airflow`

---

## Root-user scripts

The root-user deployment scripts are stored in `root-user/`:

- `root-user/deploy_airflow.sh` — deploys Airflow to `/opt/airflow`, downloads the official Airflow compose file, patches it for Docker socket access, creates the host directories, initializes the database, and starts the containers.
- `root-user/run_dag.sh` — triggers the example DAG, monitors its progress, and retries failed tasks if needed.
- `root-user/check_airflow.sh` — performs a health check of the deployed Airflow environment.
- `root-user/dags/docker_helloworld.py` — example DAG using `DockerOperator`.

---

## Example DAG

The example DAG is located at `root-user/dags/docker_helloworld.py`:

```python
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG
from datetime import datetime

with DAG(
    "docker_helloworld",
    schedule=None,
    tags=["tagny", "docker_operator", "test"],
    doc_md="This is a simple DAG that runs a Docker container",
    catchup=False,
    start_date=datetime(2021, 1, 1),
) as dag:

    task = DockerOperator(
        task_id="step1",
        image="helloworld",
        command="echo Hello World!",
        auto_remove="force",
    )
```

This DAG launches a short-running container named `helloworld` and executes `echo Hello World!`.

---

## Deploying Airflow with `root-user/deploy_airflow.sh`

Basic usage:

```bash
sudo bash root-user/deploy_airflow.sh
```

Optional flags:

```bash
sudo bash root-user/deploy_airflow.sh --status
sudo bash root-user/deploy_airflow.sh --uninstall
sudo bash root-user/deploy_airflow.sh -v 3.2.1
sudo bash root-user/deploy_airflow.sh -d /custom/airflow/home
```

The script will:

- create `/opt/airflow` with `dags/`, `logs/`, `plugins/`, and `config/`
- copy local DAG files into `/opt/airflow/dags/`
- download the Airflow Docker Compose YAML for the chosen version
- patch the compose file with `/var/run/docker.sock` and Docker GID support
- write a `.env` file for Airflow
- run `airflow-init`
- start the Airflow containers in detached mode
- download the official Airflow CLI wrapper script
- verify the webserver and list DAGs

---

## Running the example DAG

```bash
sudo bash root-user/run_dag.sh docker_helloworld
```

Optional options:

- `-f`, `--force` — force a new run even if one already succeeded today
- `-n`, `--dry-run` — show what would happen without executing
- `-w`, `--wait-time` — custom wait timeout
- `-p`, `--poll-interval` — custom polling interval

---

## Health check

Use the root-user health check script:

```bash
sudo bash root-user/check_airflow.sh
```

It verifies:

- Docker Compose availability
- required host directory structure
- required files (`.env`, `docker-compose.yaml`, `airflow_cli.sh`, `config/airflow.cfg`)
- container status and health
- Airflow version and database connectivity
- webserver responsiveness
- recent webserver and scheduler logs

---

## Repository structure

```text
.
├── Dockerfile
├── LICENSE
├── README.md
├── startup-script.sh
├── root-user/
│   ├── check_airflow.sh
│   ├── dags/
│   │   └── docker_helloworld.py
│   ├── deploy_airflow.sh
│   └── run_dag.sh
└── .pre-commit-config.yaml
```

---

## Notes

- The DAG uses a local Docker image named `helloworld`. Build it before triggering the DAG:

```bash
docker build -t helloworld .
```

- The root-user deployment assumes the current host user can access Docker and that the Docker daemon is running.

- If Airflow cannot access `/var/run/docker.sock`, the script adds the host Docker group ID to the container configuration.

---

## License

This project is released into the public domain under [The Unlicense](https://unlicense.org). See `LICENSE`.

---

## Contributing

Contributions, issues, and improvements are welcome. Open an issue or submit a pull request.
