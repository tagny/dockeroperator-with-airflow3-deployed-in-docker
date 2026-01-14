# dockeroperator-with-airflow3-deployed-in-docker
A demo of how to deploy Airflow 3 as a docker container while running a DockerOperator based dag. A startup script is provided for deployment in a cloud virtual machine to stop the VM once the dag is done running.

I recommend to use this setup with customized airflow config and docker compose files: `airflow_deployment/from_custom_docker_compose_and_cfg`

## Potential issues

### `ERROR: Invalid interpolation format for "image" option in service "x-airflow-common": "${AIRFLOW_IMAGE_NAME:-apache/airflow:3.1.6}"`
- triggered when running the `airflow.sh` script for CLI with `docker-compose` 
- Solution: 
- remove the `docker-compose` option in `airflow.sh` and only use `docker compose` (i.e. without the dash `-`)

### `Failed to establish connection to Docker host unix://var/run/docker.sock`

- triggered when running a dockeroperator task from the airflow web console
  - Solution: add the `docker` group ID to the docker user in the docker-compose.yaml file
  ```yaml
  x-airflow-common:
    ...
    user: ...
    group_add:
        # add docker group id for permission on /var/run/docker.sock
        - 996
  ```
### Permission on the airflow host home dir (e.g.`/opt/airflow` )
  - Solution: change the owner of the container dir
  ```yaml
  x-airflow-common:
    ...
    command: ["chown", "-R", "airflow:airflow", "/opt/airflow"]
  ```