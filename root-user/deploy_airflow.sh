#!/bin/bash

# ═══════════════════════════════════════════════════════════════
# Helps
# ═══════════════════════════════════════════════════════════════

# Airflow Docker Deployment Script — ROOT USER VERSION
# Version: 1.0
# Description: Automated deployment of Apache Airflow using Docker Compose
#              This version requires root/sudo privileges and installs to /opt/airflow.

# ## Usage Examples:
#  
# ```bash
# # Install default version (run as root or with sudo)
# sudo ./deploy_airflow.sh
# 
# # Install specific version
# sudo ./deploy_airflow.sh 3.2.1

# # Check status
# ./deploy_airflow.sh --status

# # Uninstall
# sudo ./deploy_airflow.sh --uninstall
# 
# # Show help
# ./deploy_airflow.sh --help
# ```

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════
# 1. Define defaults
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/.logs"
readonly LOGFILE="${LOG_DIR}/deploy_airflow_$(date +%Y%m%d).log"
AUTO_APPROVE=false
AIRFLOW_VERSION="3.2.2"
HOST_AIRFLOW_HOME="/opt/airflow"
# COMPOSE_URL="https://airflow.apache.org/docs/apache-airflow/${AIRFLOW_VERSION}/docker-compose.yaml"
# COMPOSE_FILE="${HOST_AIRFLOW_HOME}/docker-compose.yaml"
# ENV_FILE="${HOST_AIRFLOW_HOME}/.env"
# CLI_SCRIPT="${HOST_AIRFLOW_HOME}/airflow_cli.sh"
CPU_CORES=$(nproc)

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════

log_echo() {
    echo "$@" | tee -a "$LOGFILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $@" | tee -a "$LOGFILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $@" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $@" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" | tee -a "$LOGFILE"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOGFILE"
    echo -e "${BLUE}📌 $1${NC}" | tee -a "$LOGFILE"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOGFILE"
}

# 3. Create a reusable function for y|N questions
ask_yn() {
  local prompt="$1"
  
  # If -y was passed, automatically approve and print the action
  if [ "$AUTO_APPROVE" = true ]; then
    log_warning "$prompt y (auto)"
    return 0  # 0 means "yes/success" in bash
  fi

  # Otherwise, ask the user
  log_warning "$prompt [y|N] "
  read -r answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    return 0
  else
    return 1  # 1 means "no/failure"
  fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_warning "This script is designed to run as root (or with sudo)."
        log_warning "Some operations (creating /opt/airflow, setting ownership) may fail."
        log_info "Re-run with: sudo $0 $*"
        log_echo ""
        if ! ask_yn "Continue anyway?" ; then
            exit 1
        fi
    fi
}

check_prerequisites() {
    local missing_tools=()
    
    for tool in docker curl getent id; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install them before running this script."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check Docker Compose availability
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose plugin is not available. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

dockercompose() {
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

airflow_cmd() {
    if [ -f "$CLI_SCRIPT" ]; then
        bash "$CLI_SCRIPT" "$@"
    else
        log_error "Airflow CLI script not found at $CLI_SCRIPT"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Step 0: Setup Host Directory Structure
# ═══════════════════════════════════════════════════════════════

setup_host_directory() {
    log_step "Step 0: Setting up Airflow host directory"
    
    # Create main directory if it doesn't exist
    if [ ! -d "$HOST_AIRFLOW_HOME" ]; then
        log_info "Creating $HOST_AIRFLOW_HOME"
        if ! mkdir -p "$HOST_AIRFLOW_HOME" 2>/dev/null; then
            log_info "Using sudo to create directory"
            sudo mkdir -p "$HOST_AIRFLOW_HOME"
        fi
    fi

    # Create Airflow subdirectories
    log_info "Creating Airflow subdirectories"
    mkdir -p "$HOST_AIRFLOW_HOME"/{dags,logs,plugins,config}
    
    # Set proper ownership
    log_info "Setting ownership to $(id -u):$(id -g)"
    if [[ "$(stat -c '%u:%g' "$HOST_AIRFLOW_HOME")" != "$(id -u):$(id -g)" ]]; then
        log_info "Using sudo to change ownership of $HOST_AIRFLOW_HOME"
        if ! chown -R "$(id -u):$(id -g)" "$HOST_AIRFLOW_HOME"; then
            sudo chown -R "$(id -u):$(id -g)" "$HOST_AIRFLOW_HOME"
        fi
    fi
    
    # Set write permissions for all users (required for Docker containers)
    log_info "Setting write permissions on subdirectories"
    chmod -R a+w $HOST_AIRFLOW_HOME
    
    # Copy project DAGs if they exist
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -d "$script_dir/dags" ] && [ "$(ls -A "$script_dir/dags" 2>/dev/null)" ]; then
        log_info "Copying project DAGs from $script_dir/dags/ to $HOST_AIRFLOW_HOME/dags/"
        cp -r "$script_dir/dags/"* "$HOST_AIRFLOW_HOME/dags/" 2>/dev/null || true
        log_success "DAGs copied successfully"
    else
        log_warning "No local 'dags' directory found or it's empty"
    fi
    
    log_success "Host directory structure created"
}

# ═══════════════════════════════════════════════════════════════
# Step 1: Download and Configure Docker Compose File
# ═══════════════════════════════════════════════════════════════

get_docker_gid() {
    local docker_gid
    
    if ! docker_gid=$(getent group docker | cut -d: -f3); then
        log_error "Docker group not found on this system"
        log_error "Please ensure Docker is properly installed and the 'docker' group exists"
        exit 1
    fi
    
    echo "$docker_gid"
}

download_compose_file() {
    log_info "Downloading Docker Compose file for Airflow ${AIRFLOW_VERSION}"

    log_echo "curl -fsSL -o $COMPOSE_FILE $COMPOSE_URL"

    if ! curl -fsSL -o "$COMPOSE_FILE" "$COMPOSE_URL"; then
        log_error "Failed to download compose file from $COMPOSE_URL"
        exit 1
    fi
    
    log_success "Compose file downloaded"
}

modify_compose_file() {
    local docker_gid="$1"
    
    log_info "Modifying compose file with Docker GID: $docker_gid"
    
    awk -v gid="$docker_gid" '
    BEGIN { in_ac = 0; in_vol = 0 }

    /^x-airflow-common:/ { in_ac = 1; print; next }

    !in_ac { print; next }

    /^  volumes:/ { in_vol = 1; print; next }

    in_vol {
        if (/^    - /) { print; next }
        print "    - /var/run/docker.sock:/var/run/docker.sock"
        print "    - $HOME/.docker:/home/airflow/.docker"
        in_vol = 0
        print
        next
    }

    /^[a-zA-Z]/ {
        print "  # command: [\"chown\", \"-R\", \"airflow:airflow\", \"/opt/airflow\"]"
        print "  group_add:"
        print "    # add docker group id for permission on /var/run/docker.sock"
        print "    - " gid
        in_ac = 0
        print
        next
    }

    { print }

    END {
        if (in_ac) {
            print "  # command: [\"chown\", \"-R\", \"airflow:airflow\", \"/opt/airflow\"]"
            print "  group_add:"
            print "    # add docker group id for permission on /var/run/docker.sock"
            print "    - " gid
        }
        if (in_vol) {
            print "    - /var/run/docker.sock:/var/run/docker.sock"
            print "    - $HOME/.docker:/home/airflow/.docker"
        }
    }
    ' "$COMPOSE_FILE" > "${COMPOSE_FILE}.tmp" && mv "${COMPOSE_FILE}.tmp" "$COMPOSE_FILE"
    
    log_success "Compose file modified successfully"
}

setup_compose_file() {
    log_step "Step 1: Downloading and configuring Docker Compose file"
    
    download_compose_file
    local docker_gid=$(get_docker_gid)
    modify_compose_file "$docker_gid"
    
    log_success "Compose file setup complete"
}

# ═══════════════════════════════════════════════════════════════
# Step 2: Initialize Airflow Environment
# ═══════════════════════════════════════════════════════════════

setup_environment() {
    log_step "Step 2: Initializing Airflow environment"
    
    cd "$HOST_AIRFLOW_HOME"
    
    # Set Airflow user ID
    log_info "Setting AIRFLOW_UID=$(id -u) in .env file"
    log_echo "AIRFLOW_UID=$(id -u)" > "$ENV_FILE"
    
    # Optional: Add other environment variables
    cat >> "$ENV_FILE" <<EOF
# Airflow Configuration
AIRFLOW_VERSION=${AIRFLOW_VERSION}
AIRFLOW_HOME=${HOST_AIRFLOW_HOME}
AIRFLOW_PROJ_DIR=${HOST_AIRFLOW_HOME}
#_AIRFLOW_WWW_USER_USERNAME=${USER}
#_AIRFLOW_WWW_USER_PASSWORD=${USER}
AIRFLOW__CORE__PARALLELISM=$(( CPU_CORES > 0 ? CPU_CORES : 1 ))
AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG=1
EOF
    
    log_success "Environment file created"
}

initialize_airflow_config() {
    log_info "Initializing Airflow configuration"
    
    if dockercompose run --rm airflow-cli airflow config list --show-values &>/dev/null; then
        log_success "Airflow configuration initialized"
    else
        log_warning "Could not initialize airflow.cfg (non-critical, will use defaults)"
    fi
}

initialize_database() {
    log_info "Initializing Airflow database"
    
    if dockercompose up "airflow-init" --remove-orphans; then
        log_success "Database initialization complete"
        # log_info "Default credentials: username='airflow', password='airflow'"
    else
        log_error "Database initialization failed"
        log_info "Check logs with: docker compose -f $COMPOSE_FILE logs airflow-init"
        exit 1
    fi
}

initialize_airflow() {
    setup_environment
    initialize_airflow_config
    initialize_database
}

# ═══════════════════════════════════════════════════════════════
# Step 3: Start Airflow Services
# ═══════════════════════════════════════════════════════════════

start_airflow() {
    log_step "Step 3: Starting Airflow services"
    
    log_info "Starting Airflow containers in detached mode"
    if dockercompose up -d --remove-orphans; then
        log_success "Airflow services started"
    else
        log_error "Failed to start Airflow services"
        log_info "Check logs with: docker compose -f $COMPOSE_FILE logs"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Step 4: Setup Airflow CLI
# ═══════════════════════════════════════════════════════════════

setup_airflow_cli() {
    log_step "Step 4: Setting up Airflow CLI"
    
    local cli_url="https://airflow.apache.org/docs/apache-airflow/${AIRFLOW_VERSION}/airflow.sh"
    
    log_info "Downloading Airflow CLI script"
    if curl -fsSL -o "$CLI_SCRIPT" "$cli_url"; then
        chmod +x "$CLI_SCRIPT"
        log_success "Airflow CLI script installed at $CLI_SCRIPT"
    else
        log_error "Failed to download CLI script"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Step 5: Verify Installation
# ═══════════════════════════════════════════════════════════════

wait_for_airflow() {
    local max_attempts=30
    local attempt=0
    local delay=2
    
    log_info "Waiting for Airflow webserver to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "http://localhost:8080/api/v2/monitor/health" &>/dev/null; then
            log_success "Airflow webserver is ready"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_echo -n "."
        sleep $delay
    done
    
    log_echo ""
    log_warning "Airflow webserver might still be starting up"
    return 1
}

verify_installation() {
    log_step "Step 5: Verifying installation"
    
    # Wait for services to be ready
    wait_for_airflow
    
    # Check version
    log_info "Checking Airflow version"
    if airflow_cmd version 2>/dev/null; then
        log_success "Airflow CLI is working"
    else
        log_warning "Could not verify version via CLI (might still be initializing)"
    fi
    
    # List DAGs
    log_info "Listing DAGs in dags-folder"
    if airflow_cmd dags list -B dags-folder 2>/dev/null | sed -n '/dag_id/,$p'; then
        log_success "DAGs listed successfully"
    else
        log_warning "Could not list DAGs (might still be initializing)"
    fi
    
    # Show container status
    log_info "Container status:"
    dockercompose ps
}

# ═══════════════════════════════════════════════════════════════
# Cleanup Function
# ═══════════════════════════════════════════════════════════════

cleanup() {
    log_step "Cleaning up"
    
    # Return to original directory
    cd - >/dev/null 2>&1 || true
    
    log_info "Cleanup complete"
}

# ═══════════════════════════════════════════════════════════════
# Help Function
# ═══════════════════════════════════════════════════════════════

show_help() {
    cat <<EOF
🚀 Airflow Docker Deployment Script (Root User Version)

Usage: sudo $0 [OPTIONS]

Arguments:
    

Options:
    -h, --help         Show this help message
    --uninstall        Remove Airflow deployment
    --status           Show deployment status
    -v, --version      Airflow version to deploy (default: 3.2.2)
    -d, --host-dir.    Airflow home on host to be mounted to the services (default: $HOST_AIRFLOW_HOME)

Examples:
    ./$0                          # Deploy default version
    ./$0 -v 3.2.1                 # Deploy specific version
    ./$0 -d ./airflow3            # Deploy to a specific host directory
    ./$0 --status                 # Check deployment status
    ./$0 --uninstall              # Remove deployment
EOF
}

# ═══════════════════════════════════════════════════════════════
# Uninstall Function
# ═══════════════════════════════════════════════════════════════

uninstall_airflow() {
    log_step "Uninstalling Airflow"
    
    if [ -f "$COMPOSE_FILE" ]; then
        log_info "Stopping and removing containers"
        dockercompose down -v --remove-orphans || true
        
        if ask_yn "Do you want to remove the Airflow directory ($HOST_AIRFLOW_HOME)?"; then
            if ! rm -rf "$HOST_AIRFLOW_HOME"; then
                sudo rm -rf "$HOST_AIRFLOW_HOME"
            fi
            log_success "Airflow directory removed"
        else
            log_info "Keeping directory: $HOST_AIRFLOW_HOME"
        fi
    else
        log_warning "No compose file found. Nothing to uninstall."
    fi
    
    log_success "Uninstall complete"
}

# ═══════════════════════════════════════════════════════════════
# Status Function
# ═══════════════════════════════════════════════════════════════

show_status() {
    log_step "Airflow Deployment Status"
    
    if [ -f "$COMPOSE_FILE" ]; then
        log_echo "📄 Compose file: $COMPOSE_FILE"
        log_echo "📁 Installation directory: $HOST_AIRFLOW_HOME"
        log_echo ""
        log_echo "📦 Container status:"
        dockercompose ps 2>/dev/null || log_echo "   No containers found"
        log_echo ""
        log_echo "🌐 Access Airflow at: http://localhost:8080"
        log_echo "👤 Default login: airflow / airflow"
    else
        log_warning "Airflow is not installed. Run without --status to install."
    fi
}

# ═══════════════════════════════════════════════════════════════
# Main Function
# ═══════════════════════════════════════════════════════════════

main() {
    log_echo "╔═══════════════════════════════╗"
    log_echo "║     Airflow deployment        ║"
    log_echo "╚═══════════════════════════════╝"
    log_echo ""
    # Parse command line arguments
    # 1. Define the auto-approve variable (default to false)
    AUTO_APPROVE=false
    DO_UNINSTALL=false
    DO_SHOW_STATUS=false

    # 2. Parse command-line options manually
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --uninstall)
                DO_UNINSTALL=true
                shift
                ;;
            --status)
                DO_SHOW_STATUS=true
                shift # Move to the next argument
                ;;
            -y)
                AUTO_APPROVE=true
                shift # Move to the next argument
                ;;
            -v|--version)
                shift
                AIRFLOW_VERSION="$1"
                shift
                ;;
            -d|--host-dir)
                shift
                HOST_AIRFLOW_HOME=$(realpath $1)
                shift
                ;;
            *)
                log_error "Invalid option: $1" >&2
                show_help
                exit 1
                ;;
        esac

    done

    declare -g COMPOSE_URL="https://airflow.apache.org/docs/apache-airflow/${AIRFLOW_VERSION}/docker-compose.yaml"
    declare -g COMPOSE_FILE="${HOST_AIRFLOW_HOME}/docker-compose.yaml"
    declare -g ENV_FILE="${HOST_AIRFLOW_HOME}/.env"
    declare -g CLI_SCRIPT="${HOST_AIRFLOW_HOME}/airflow_cli.sh"
    
    # Check root privileges for deployment
    check_root

    if [ "$DO_SHOW_STATUS" = true ]; then
        show_status
        exit 0
    fi

    if [ "$DO_UNINSTALL" = true ]; then
        uninstall_airflow
        exit 0
    fi
    
    log_echo "🚀 Apache Airflow Deployment Script (Root User Version)"
    log_echo "Version: ${AIRFLOW_VERSION}"
    log_echo "Target: ${HOST_AIRFLOW_HOME}"
    log_echo ""
    
    # Run deployment steps
    check_prerequisites
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    # Execute deployment steps
    setup_host_directory
    setup_compose_file
    initialize_airflow
    start_airflow
    setup_airflow_cli
    verify_installation
    
    log_echo ""
    log_echo "════════════════════════════════════════════"
    log_success "🎉 Airflow ${AIRFLOW_VERSION} deployment complete!"
    log_echo "════════════════════════════════════════════"
    log_echo ""
    log_echo "📊 Access Airflow UI: http://localhost:8080"
    log_echo "👤 Username: airflow"
    log_echo "🔑 Password: airflow"
    log_echo ""
    log_echo "💡 Useful commands:"
    log_echo "   $0 --status              # Check deployment status"
    log_echo "   $0 --uninstall           # Remove deployment"
    log_echo ""
}

# Run main function
main "$@"
