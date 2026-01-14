#!/bin/bash

# ==============================================================================
# Airflow VM Startup Script for Daily, Idempotent DAG Execution
#
# This script performs the following actions:
# 1. Authenticates the Airflow CLI.
# 2. Checks the state of the target DAG for the current day.
# 3. If no run exists today, triggers a full, blocking run.
# 4. If a failed run exists today, triggers a blocking re-run of only the failed tasks.
#
# Prerequisites:
# - Airflow (3.x or compatible) must be installed and configured.
# - The 'jq' utility must be installed (for parsing JSON output).
# - The Airflow database and scheduler/webserver (if needed) are accessible.
#
# Usage:
#   bash -x ./scripts/run_etl_dag.sh <project_home>
# Example: bash -x ./scripts/run_etl_dag.sh .
# ==============================================================================

# --- Configuration ---

# MANDATORY: Replace with your specific DAG ID
DAG_ID=$1

airflow(){
    bash -x airflow_cli.sh ${@}
}

# init logging directory
LOG_DIR="./.logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/run_dag.log"

# Function to log messages with a timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}


wait_for_running_completion() {
    DAG_ID_ARG=$1
    RUN_ID_ARG=$2
    WAITING_TIME=30  # in seconds

    if [ -z "$RUN_ID_ARG" ] || [ "$RUN_ID_ARG" == "null" ]; then
        echo "Failed to trigger DAG."
        exit 1
    fi

    log "Triggered DAG: $DAG_ID_ARG (Run ID: $RUN_ID_ARG)"
    log "Waiting for completion..."

    # 2. Poll for status
    while true; do
        # Get the state of this specific run
        STATE=$(airflow dags state "$DAG_ID_ARG" "$RUN_ID_ARG")

        log "Current state: $STATE"

        if [[ "$STATE" == "success" ]]; then
            log "DAG finished successfully!"
            exit 0
        elif [[ "$STATE" == "failed" ]]; then
            log "DAG failed!"
            exit 1
            elif [[ "$STATE" == "None" ]]; then
            log "DAG run ID = $RUN_ID_ARG doesn't exist !"
            exit 1
        fi
        log "DAG still running. Waiting for $WAITING_TIME seconds before checking again..."
        sleep $WAITING_TIME  # Wait before checking again
    done
}

# --- Initial Setup ---

# Check wether the dag exist
log "Checking wether the dag exists ...."
DOES_DAG_EXIST=$(bash -x airflow_cli.sh dags details $DAG_ID)
if [ -z "$DOES_DAG_EXIST" ]; then
    log "Error: there is no dag with id=$DAG_ID"
    exit 1
fi

# Project home directory check
PROJECT_HOME=$1
if [ -z "$PROJECT_HOME" ]; then
    log "Error: PROJECT_HOME is not set. Please provide the path to the project home directory."
    exit 1
fi
source $PROJECT_HOME/.venv/bin/activate

# --- Environment Setup ---
log "Starting Airflow DAG $DAG_ID execution script."

TODAY=$(date +%Y-%m-%d)

# Prune docker to free up space
log "Pruning docker..."
docker system prune -f

# --- Core Logic: Check Existing Runs ---

# 1. Query Airflow for the latest run today (successful or failed)
#    Note: This assumes the Airflow database is accessible.
log "Checking for existing runs of DAG '$DAG_ID' for execution date $TODAY..."

# Get all runs starting today in JSON format
# Filter for runs that started today and grab the first one (most recent)
# The output is parsed to check state and get the execution date.
RUN_INFO=$(
    airflow dags list-runs "$DAG_ID" --output json 2>/dev/null |
    jq -r '.[] | select(.start_date | startswith("'$TODAY'")) | {state: .state, execution_date: .execution_date, run_id: .run_id} | @json' |
    head -n 1
)

log "RUN_INFO: $RUN_INFO"

if [ -z "$RUN_INFO" ]; then
    # --- SCENARIO 1: No run found today. Trigger a full run. ---
    log "Scenario 1: No completed or active run found for $TODAY. Triggering a NEW full run."

    log "Executing full DAG run synchronously..."
    airflow dags unpause "$DAG_ID"
    RUN_ID=$(airflow dags trigger --logical-date "$TODAY" -v "$DAG_ID" -o json | jq -r '.[0].dag_run_id')

    # Check the exit code of the backfill command
    if [ $? -eq 0 ]; then
        wait_for_running_completion "$DAG_ID" "$RUN_ID"
        log "Full DAG run completed successfully."
    else
        log "Full DAG run failed. (Exit Code: $?)"
    fi

elif [ "$(echo "$RUN_INFO" | jq -r '.state')" == "failed" ]; then
    # --- SCENARIO 2: Failed run found today. Re-run failed tasks. ---

    RUN_STATE=$(echo "$RUN_INFO" | jq -r '.state')
    EXEC_DATE=$(echo "$RUN_INFO" | jq -r '.execution_date')
    RUN_ID=$(echo "$RUN_INFO" | jq -r '.run_id')


    log "Scenario 2: Found a run for $TODAY in state: $RUN_STATE (Execution Date: $EXEC_DATE)."
    log "Re-running ONLY failed tasks for execution date $EXEC_DATE with run_id = $RUN_ID."

    airflow tasks clear --start-date "$TODAY" --end-date "$TODAY" --only-failed --downstream --yes "$DAG_ID"

    if [ $? -eq 0 ]; then
        wait_for_running_completion "$DAG_ID" "$RUN_ID"
        log "Re-run of failed tasks completed successfully."
    else
        log "Re-run of failed tasks also failed. (Exit Code: $?)"
    fi

elif [ "$(echo "$RUN_INFO" | jq -r '.state')" == "success" ]; then
    # --- SCENARIO 3: Successful run found today. Do nothing. ---
    log "Scenario 3: Found a run for $TODAY in state: success. The daily run is complete."

elif [ "$(echo "$RUN_INFO" | jq -r '.state')" == "running" ]; then
    # --- SCENARIO 4: Running run found today. Wait or skip (We choose to skip/wait a short time). ---
    log "Scenario 4: Found a run for $TODAY in state: running. Assuming another process is managing this. Skipping execution."

else
    # --- SCENARIO 5: Catch-all ---
    log "No action taken. Run found in unexpected state or error in parsing."
fi

log "Airflow DAG execution script completed."