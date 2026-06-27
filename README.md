# DockerOperator with Airflow 3 — Deployed in Docker

A hands-on demo showing how to **deploy Apache Airflow 3** via **Docker Compose** and execute a DAG that uses the [`DockerOperator`](https://airflow.apache.org/docs/apache-airflow-providers-docker/stable/operators/docker.html) — all running inside Docker containers.

---

## Why This Project?

Running `DockerOperator` tasks from an Airflow instance that is *itself* containerised requires a specific setup:
the Airflow containers need access to the host's Docker daemon (`/var/run/docker.sock`) so they can spawn sibling containers.
This repo automates the entire process — from downloading the official Compose file to patching it with the right socket mount and group permissions — so you can focus on writing DAGs.

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| **Docker Engine** | ≥ 20.10 |
| **Docker Compose** (v2 plugin) | `docker compose` must be available |
| **curl** | any recent version |
| **jq** | any recent version (used by `run_dag.sh`) |
| **bash** | ≥ 4 |

> **Note:** The scripts use `getent`, `id`, and other standard Linux utilities. They are designed for **Linux** hosts. macOS / WSL2 users may need minor adjustments.

---

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/tagny/dockeroperator-with-airflow3-deployed-in-docker.git
cd dockeroperator-with-airflow3-deployed-in-docker

# 2. Deploy Airflow (defaults to version 3.2.2)
./deploy_airflow.sh

# 3. Open the Airflow UI
#    http://localhost:8080
#    Login: airflow / airflow

# 4. Run the example DAG
./run_dag.sh docker_helloworld
```

---

## What `deploy_airflow.sh` Does

The script performs five automated steps:

| Step | Description |
|------|-------------|
| **0** | Creates `/opt/airflow` with `dags/`, `logs/`, `plugins/`, `config/` sub-directories and copies the local `dags/` folder into it |
| **1** | Downloads the official Docker Compose file for the requested Airflow version, then patches it to mount `/var/run/docker.sock` and add the host's `docker` GID to `group_add` |
| **2** | Writes the `.env` file (`AIRFLOW_UID`, etc.) and runs `airflow-init` to bootstrap the metadata database |
| **3** | Starts all services in detached mode (`docker compose up -d`) |
| **4** | Downloads the official Airflow CLI wrapper script |
| **5** | Waits for the webserver health endpoint and lists discovered DAGs |

### Usage

```bash
./deploy_airflow.sh              # deploy default version (3.2.2)
./deploy_airflow.sh 3.2.1        # deploy a specific version
./deploy_airflow.sh --status     # show container status
./deploy_airflow.sh --uninstall  # tear down containers & optionally remove /opt/airflow
./deploy_airflow.sh --help       # print help
```

---

## Example DAG — `docker_helloworld`

Located in [`dags/docker_helloworld.py`](dags/docker_helloworld.py):

```python
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG
from datetime import datetime

with DAG(
    'docker_helloworld',
    schedule=None,
    tags=["tagny", "docker_operator", "test"],
    doc_md="This is a simple DAG that runs a Docker container",
    catchup=False,
    start_date=datetime(2021, 1, 1),
) as dag:

    task = DockerOperator(
        task_id='step1',
        image='alpine',
        command='sleep 3600',
        auto_remove='force'
    )
```

The DAG spins up an **Alpine** container via `DockerOperator` and runs `sleep 3600`. Because `auto_remove='force'` is set, the container is cleaned up automatically after the task finishes (or is stopped).

---

## Running & Monitoring a DAG — `run_dag.sh`

An idempotent runner that triggers a DAG, monitors it until completion, and handles retries of failed tasks automatically.

```bash
./run_dag.sh <DAG_ID> [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-f`, `--force` | Trigger a new run even if today's run already succeeded |
| `-n`, `--dry-run` | Preview what would happen without executing |
| `-w`, `--wait-time` | Max seconds to wait for completion (default: 1200) |
| `-p`, `--poll-interval` | Seconds between status polls (default: 15) |

The script follows this decision logic each time it runs:

```
Today's run exists?
├── No  → trigger a new run and monitor it
├── Running  → attach and monitor the existing run
├── Failed  → clear failed tasks, re-trigger downstream, and monitor
└── Succeeded  → skip (nothing to do)
```

---

## Health Check — `check_airflow.sh`

Performs a comprehensive health check of the running deployment:

```bash
./check_airflow.sh
```

Checks include:
- Docker Compose availability
- Compose file presence & YAML validity
- Host directory structure (`/opt/airflow/{dags,logs,plugins,config}`)
- Container status (running / healthy)
- Airflow version & binary path
- Database connectivity (`airflow db check`)
- Webserver HTTP response
- Installed Airflow Python packages
- Recent scheduler & webserver logs

Results are summarised at the end with a pass/fail count.

---

## Project Structure

```
.
├── dags/
│   └── docker_helloworld.py      # Example DAG using DockerOperator
├── deploy_airflow.sh             # One-command Airflow deployment
├── check_airflow.sh              # Post-deployment health check
├── run_dag.sh                    # Idempotent DAG runner with monitoring
├── .pre-commit-config.yaml       # Linting & formatting hooks
├── .gitignore
├── LICENSE                       # The Unlicense (public domain)
└── README.md
```

---

## Customisation

- **Airflow version** — pass a version argument: `./deploy_airflow.sh 3.1.0`
- **Adding your own DAGs** — drop `.py` files into `dags/`; they are copied to `/opt/airflow/dags/` on deploy and auto-discovered by the scheduler.
- **Extra Python packages** — exec into a running container (`docker compose exec airflow-scheduler pip install ...`) or extend the base image.
- **Airflow configuration** — edit `/opt/airflow/config/airflow.cfg` after initial deploy, then restart services.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `DockerOperator` task fails with *Permission denied* on `/var/run/docker.sock` | Airflow container user is not in the `docker` group | Re-run `deploy_airflow.sh` — it patches `group_add` automatically |
| Webserver unreachable on port 8080 | Services still initialising | Run `./check_airflow.sh` and wait; check logs with `docker compose -f /opt/airflow/docker-compose.yaml logs -f` |
| DAG not visible in the UI | File not in `/opt/airflow/dags/` or syntax error | Verify the file was copied and run `python -c "import py_compile; py_compile.compile('dags/your_dag.py')"` |
| `getent: command not found` | Running on macOS without coreutils | Install GNU coreutils (`brew install coreutils`) or run inside a Linux VM / WSL2 |

---

## License

This project is released into the **public domain** under [The Unlicense](https://unlicense.org). See the [LICENSE](LICENSE) file.

---

## Contributing

Contributions, issues, and feature requests are welcome. Feel free to open an issue or submit a pull request.
