#!/bin/bash

# ==============================================================================
# Airflow DAG Execution Script — ROOT USER VERSION
# Daily Idempotent Runner
#
# This script ensures a DAG runs successfully today by:
# 1. Checking for existing runs today
# 2. Triggering a new full run if none exists
# 3. Re-running only failed tasks if a run failed
# 4. Skipping if a successful run already exists
#
# Usage:
#   # Basic usage
# ./run_dag.sh my_dag_id
#
# # Force a new run
# ./run_dag.sh my_dag_id --force
#
# # Preview what would happen
# ./run_dag.sh my_dag_id --dry-run
# 
# # Custom wait time and poll interval
# ./run_dag.sh my_dag_id -w 7200 -p 60
# 
# # Show help
# ./run_dag.sh --help
# ==============================================================================

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOST_AIRFLOW_HOME="${AIRFLOW_HOME:-/opt/airflow}"
readonly AIRFLOW_CLI="${HOST_AIRFLOW_HOME}/airflow_cli.sh"
readonly LOG_DIR="${SCRIPT_DIR}/.logs"
readonly LOG_FILE="${LOG_DIR}/run_dag_$(date +%Y%m%d).log"
readonly TODAY=$(date +%Y-%m-%d)
POLL_INTERVAL=30  # Seconds between status checks
MAX_WAIT_TIME=360  # Maximum wait time in seconds (1 hour)

mkdir -p $LOG_DIR

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
}

log_step() {
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}📌 $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

airflow_cmd() {
    if [ ! -f "$AIRFLOW_CLI" ]; then
        log_error "Airflow CLI script not found at: $AIRFLOW_CLI"
        return 1
    fi
    
    if [ ! -x "$AIRFLOW_CLI" ]; then
        log_error "Airflow CLI script is not executable: $AIRFLOW_CLI"
        return 1
    fi
    
    bash "$AIRFLOW_CLI" "$@" 2>&1
}

cleanup() {
    log_info "Cleaning up temporary files..."
    # Add any cleanup logic here
}

show_help() {
    cat <<EOF
🚀 Airflow DAG Execution Script (Root User Version)

Usage: $0 <DAG_ID> [OPTIONS]

Arguments:
    DAG_ID              The ID of the DAG to execute

Options:
    -f, --force         Force a new run even if one succeeded today
    -w, --wait-time     Maximum wait time in seconds (default: 3600)
    -p, --poll-interval Poll interval in seconds (default: 30)
    -n, --dry-run       Show what would be done without executing
    -h, --help          Show this help message

Examples:
    $0 my_dag_id                    # Run DAG if needed
    $0 my_dag_id --force            # Force new run
    $0 my_dag_id --dry-run          # Preview actions
    $0 my_dag_id -w 7200 -p 60      # Custom wait/poll times

Note:
    This version expects Airflow installed at /opt/airflow.
    Override with AIRFLOW_HOME environment variable.
EOF
}

# ═══════════════════════════════════════════════════════════════
# Prerequisites Check
# ═══════════════════════════════════════════════════════════════

check_prerequisites() {
    log_step "🔍 Checking prerequisites"
    
    local missing_tools=()
    local errors=0
    
    # Check required tools
    for tool in jq curl docker date; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
            ((errors++))
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before running this script."
        exit 1
    fi
    
    # Check Airflow CLI
    if [ ! -f "$AIRFLOW_CLI" ]; then
        log_error "Airflow CLI not found at $AIRFLOW_CLI"
        exit 1
    fi
    
    # Check Docker availability
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# ═══════════════════════════════════════════════════════════════
# Setup Functions
# ═══════════════════════════════════════════════════════════════

setup_environment() {
    log_step "⚙️  Setting up environment"
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    
    # Rotate logs if they get too large (keep last 7 days)
    find "$LOG_DIR" -name "run_dag_*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_info "Log file: $LOG_FILE"
    log_info "DAG ID: $DAG_ID"
    log_info "Today's date: $TODAY"
}

# ═══════════════════════════════════════════════════════════════
# DAG Validation
# ═══════════════════════════════════════════════════════════════

validate_dag() {
    log_step "🔍 Validating DAG: $DAG_ID"
    
    local dag_info
    
    if ! dag_info=$(airflow_cmd dags details "$DAG_ID" 2>/dev/null); then
        log_error "Failed to query DAG details"
        return 1
    fi
    
    if [ -z "$dag_info" ]; then
        log_error "DAG '$DAG_ID' does not exist!"
        log_info "Available DAGs:"
        airflow_cmd dags list 2>/dev/null || true
        return 1
    fi
    
    # Check if DAG is paused
    local is_paused
    is_paused=$(airflow_cmd dags list --output json 2>/dev/null | \
        jq -r ".[] | select(.dag_id == \"$DAG_ID\") | .is_paused" 2>/dev/null || echo "unknown")
    
    if [ "$is_paused" = "true" ]; then
        log_warning "DAG '$DAG_ID' is currently paused"
    fi
    
    log_success "DAG '$DAG_ID' validated successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# System Maintenance
# ═══════════════════════════════════════════════════════════════

prune_docker_system() {
    log_step "🧹 Pruning Docker system"
    
    local before_space after_space freed_space
    
    before_space=$(df -h / | awk 'NR==2 {print $4}')
    
    if docker system prune -f &>/dev/null; then
        after_space=$(df -h / | awk 'NR==2 {print $4}')
        log_success "Docker system pruned (Before: $before_space, After: $after_space)"
    else
        log_warning "Docker system prune failed (non-critical)"
    fi
}

# ═══════════════════════════════════════════════════════════════
# DAG Run Query Functions
# ═══════════════════════════════════════════════════════════════

get_today_runs() {
    # Get all runs for today
    airflow_cmd dags list-runs "$DAG_ID" --output json 2>/dev/null | \
        tail -n 1 | \
        jq -r ".[] | select(.start_date | startswith(\"$TODAY\")) | {state: .state, execution_date: .start_date, run_id: .run_id} | @json" 2>/dev/null | \
        head -n 1
}

get_run_state() {
    local run_id="$1"
    airflow_cmd dags state "$DAG_ID" "$run_id" 2>/dev/null | tail -n 1
}

# ═══════════════════════════════════════════════════════════════
# DAG Execution Functions
# ═══════════════════════════════════════════════════════════════

trigger_new_run() {
    # " >&2" is added to logs to avoid returning them along with the run id
    log_info "Triggering new full DAG run for date: $TODAY" >&2
    
    # Unpause the DAG if needed
    airflow_cmd dags unpause "$DAG_ID" >/dev/null 2>&1 || true
    
    # Trigger the DAG
    local run_id
    runs_infos=$()
    run_id=$(airflow_cmd dags trigger \
        --logical-date "$TODAY" \
        -v "$DAG_ID" \
        -o json 2>/dev/null | \
        tail -n 1 | \
        jq -r '.[0].dag_run_id' 2>/dev/null)
    
    if [ -z "$run_id" ] || [ "$run_id" = "null" ]; then
        log_error "Failed to trigger DAG" >&2
        return 1
    fi
    
    log_success "DAG triggered (Run ID: $run_id)" >&2
    echo "$run_id"
}

clear_failed_tasks() {
    local exec_date="$1"
    
    log_info "Clearing failed tasks for execution date: $exec_date"
    
    if airflow_cmd tasks clear \
        --start-date "$TODAY" \
        --end-date "$TODAY" \
        --only-failed \
        --downstream \
        --yes "$DAG_ID" 2>/dev/null; then
        log_success "Failed tasks cleared successfully"
        return 0
    else
        log_error "Failed to clear tasks"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# DAG Monitoring
# ═══════════════════════════════════════════════════════════════

monitor_dag_run() {
    local run_id="$1"
    local start_time=$(date +%s)
    local elapsed_time=0
    
    log_step "📊 Monitoring DAG run $run_id"
    # a counter to print the running tasks after each 4 iterations
    counter=0
    while [ $elapsed_time -lt $MAX_WAIT_TIME ]; do
        ((counter++))
        # wait a bit before checking state
        sleep "$POLL_INTERVAL"
        local state
        state=$(get_run_state "$run_id")
        elapsed_time=$(($(date +%s) - start_time))
        log_info "Current state: $state (Elapsed: ${elapsed_time}s)"
        
        case "$state" in
            "success")
                log_success "🎉 DAG completed successfully!"
                return 0
                ;;
            "failed")
                log_error "💥 DAG failed!"
                # Get task-level details on failure
                log_info "Failed tasks:"
                airflow_cmd tasks states-for-dag-run $DAG_ID $run_id -o plain 2>/dev/null | grep -i "fail" | awk '{print $3}' || true
                return 1
                ;;
            "None"|"")
                log_error "DAG run ID '$run_id' no longer exists!"
                return 1
                ;;
            *)
                # Still running - show progress
                if (( counter == 4 )); then
                    log_info "DAG still running... (${elapsed_time}s elapsed)"
                    # Get task-level details on running
                    log_info "Running tasks:"
                    airflow_cmd tasks states-for-dag-run $DAG_ID $run_id -o plain 2>/dev/null | grep -i "running" | awk '{print $3}' || true
                    counter=0
                fi
                ;;
        esac
        
    done
    
    log_error "Timeout! DAG did not complete within ${MAX_WAIT_TIME}s"
    return 1
}

# ═══════════════════════════════════════════════════════════════
# Main Logic - Scenario Handlers
# ═══════════════════════════════════════════════════════════════

handle_no_run() {
    log_step "📋 Scenario: No run found for today"
    log_info "Triggering a new full run..."
    
    local run_id
    if ! run_id=$(trigger_new_run | tail -n 1); then
        log_error "Failed to trigger new run"
        return 1
    fi
    
    if ! monitor_dag_run "$run_id"; then
        log_error "DAG run failed"
        return 1
    fi
    
    log_success "Full DAG run completed successfully"
    return 0
}

handle_failed_run() {
    local run_info="$1"
    local exec_date run_id state
    
    exec_date=$(echo "$run_info" | jq -r '.execution_date')
    run_id=$(echo "$run_info" | jq -r '.run_id')
    state=$(echo "$run_info" | jq -r '.state')
    
    log_step "📋 Scenario: Failed run found ($state)"
    log_info "Execution date: $exec_date"
    log_info "Run ID: $run_id"
    
    # Clear only failed tasks
    if ! clear_failed_tasks "$exec_date"; then
        log_error "Failed to clear failed tasks"
        return 1
    fi
    
    # Monitor the re-run
    if ! monitor_dag_run "$run_id"; then
        log_error "Re-run of failed tasks failed"
        return 1
    fi
    
    log_success "Re-run of failed tasks completed successfully"
    return 0
}

handle_successful_run() {
    log_step "📋 Scenario: Successful run found"
    log_success "✅ DAG already completed successfully today - nothing to do"
    return 0
}

handle_running_dag() {
    local run_info="$1"
    local run_id
    
    run_id=$(echo "$run_info" | jq -r '.run_id')
    
    log_step "📋 Scenario: DAG is currently running"
    log_info "Run ID: $run_id"
    log_info "Monitoring existing run..."
    
    if ! monitor_dag_run "$run_id"; then
        log_error "Existing run failed"
        return 1
    fi
    
    log_success "Existing run completed successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════
# Main Execution Flow
# ═══════════════════════════════════════════════════════════════

execute_dag_strategy() {
    log_step "🎯 Determining execution strategy"
    
    # Get today's runs
    local run_info
    run_info=$(get_today_runs)
    
    log_info "Run info: ${run_info:-none}"
    
    # If forced, trigger new run regardless
    if [ "$FORCE_RUN" = true ]; then
        log_warning "Force flag set - triggering new run regardless of existing runs"
        handle_no_run
        return $?
    fi
    
    # Determine scenario based on run state
    if [ -z "$run_info" ]; then
        handle_no_run
        
    else
        local state
        state=$(echo "$run_info" | jq -r '.state')
        
        case "$state" in
            "failed")
                handle_failed_run "$run_info"
                ;;
            "success")
                handle_successful_run
                ;;
            "running")
                handle_running_dag "$run_info"
                ;;
            *)
                log_warning "Unknown state: $state"
                log_warning "Run info: $run_info"
                log_warning "Triggering new run as fallback..."
                handle_no_run
                ;;
        esac
    fi
}

# ═══════════════════════════════════════════════════════════════
# Argument Parsing
# ═══════════════════════════════════════════════════════════════

parse_arguments() {
    # Default values
    FORCE_RUN=false
    DRY_RUN=false
    MAX_WAIT_TIME=1200  # 20 min
    POLL_INTERVAL=15    # 15 sec
    
    # Check if DAG_ID is provided
    if [ $# -eq 0 ]; then
        log_error "DAG_ID is required"
        show_help
        exit 1
    else
        case "${1:-}" in
            -h|--help)
                show_help
                exit 0
                ;;
        esac
    fi
    
    # First argument is DAG_ID
    DAG_ID="$1"
    shift
    
    # Parse options
    while [ $# -gt 0 ]; do
        case "${1:-}" in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE_RUN=true
                ;;
            -w|--wait-time)
                MAX_WAIT_TIME="$2"
                shift
                ;;
            -p|--poll-interval)
                POLL_INTERVAL="$2"
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # Validate wait time
    if [ "$MAX_WAIT_TIME" -lt "$POLL_INTERVAL" ]; then
        log_error "Max wait time ($MAX_WAIT_TIME) must be >= poll interval ($POLL_INTERVAL)"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Main Function
# ═══════════════════════════════════════════════════════════════

main() {
    # set -x
    local exit_code=0
    
    # Parse arguments
    parse_arguments "$@"
    
    # Show banner
    echo "🚀 Airflow DAG Execution Script (Root User Version)" | tee -a "$LOG_FILE"
    echo "   DAG: $DAG_ID" | tee -a "$LOG_FILE"
    echo "   Date: $TODAY" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Dry run mode
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No actions will be taken"
        log_info "Would check for existing runs of '$DAG_ID' for $TODAY"
        
        local run_info
        if run_info=$(get_today_runs); then
            local state=$(echo "$run_info" | jq -r '.state')
            log_info "Found existing run in state: $state"
            log_info "Would handle scenario for state: $state"
        else
            log_info "No existing run found - would trigger new run"
        fi
        
        exit 0
    fi
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Execute steps
    check_prerequisites || exit 1
    setup_environment || exit 1
    validate_dag || exit 1
    prune_docker_system || true  # Non-critical
    
    # Execute the main strategy
    if ! execute_dag_strategy; then
        exit_code=1
    fi
    
    # Final summary
    log_step "📊 Execution Summary"
    if [ $exit_code -eq 0 ]; then
        log_success "✅ DAG '$DAG_ID' execution completed successfully"
    else
        log_error "❌ DAG '$DAG_ID' execution failed"
        log_info "Check Airflow UI for details: http://localhost:8080"
    fi
    
    exit $exit_code
}

# ═══════════════════════════════════════════════════════════════
# Script Entry Point
# ═══════════════════════════════════════════════════════════════

main "$@"
