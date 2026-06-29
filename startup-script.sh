#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# GCE VM Airflow Setup Script (Root User)
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════
# Utility Functions
# ═══════════════════════════════════════════════════════════════

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📌 $*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ═══════════════════════════════════════════════════════════════
# Step 1: Install dependencies
# ═══════════════════════════════════════════════════════════════

install_dependencies() {
    log_info "Checking and installing dependencies..."
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
    else
        log_info "Docker already installed: $(docker --version)"
    fi
    
    # Install Docker Compose if not present
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_info "Installing Docker Compose..."
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    else
        log_info "Docker Compose already installed"
    fi
    
    # Install jq if not present
    if ! command -v jq &> /dev/null; then
        log_info "Installing jq..."
        apt-get update -qq && apt-get install -y -qq jq
    else
        log_info "jq already installed: $(jq --version)"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Step 2: Copy root-user from helloworld image
# ═══════════════════════════════════════════════════════════════

copy_airflow_setup() {
    local DEST_DIR="/root/airflow-setup"
    
    log_info "Extracting root-user directory from helloworld:latest image..."
    
    # Pull the image if not present locally
    docker pull helloworld:latest 2>/dev/null || {
        log_warn "Could not pull helloworld:latest, checking if it exists locally..."
    }
    
    # Remove existing directory if present
    if [ -d "$DEST_DIR" ]; then
        log_warn "Removing existing $DEST_DIR"
        rm -rf "$DEST_DIR"
    fi
    
    # Create a temporary container and copy the directory
    local CONTAINER_ID
    CONTAINER_ID=$(docker create helloworld:latest)
    
    docker cp "${CONTAINER_ID}:/airflow-setup" "$DEST_DIR"
    docker rm "$CONTAINER_ID" > /dev/null
    
    # Make scripts executable
    chmod +x "$DEST_DIR"/*.sh
    
    log_info "Successfully copied airflow-setup to $DEST_DIR"
    
    # Display contents
    log_info "Contents of $DEST_DIR:"
    find "$DEST_DIR" -type f | sort | while read -r f; do
        echo "  ${f#$DEST_DIR/}"
    done
}

# ═══════════════════════════════════════════════════════════════
# Step 3: Deploy Airflow if not already running
# ═══════════════════════════════════════════════════════════════

deploy_airflow_if_needed() {
    local SETUP_DIR="/root/airflow-setup"
    
    # Check if Airflow is already running
    if docker ps --format '{{.Names}}' | grep -q 'airflow'; then
        log_info "Airflow containers appear to be running. Checking status..."
        docker ps --filter "name=airflow" --format "table {{.Names}}\t{{.Status}}"
        
        # # Ask if we should re-deploy
        # read -p "Airflow is already running. Re-deploy? [y/N]: " -n 1 -r
        # echo
        # if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        #     log_info "Skipping Airflow deployment."
        #     return 0
        # fi
        return 0
    fi
    
    log_info "Deploying Airflow 3 using deploy_airflow.sh..."
    
    cd "$SETUP_DIR"
    
    # Run deploy script with auto-approve and specific version
    bash deploy_airflow.sh -y -v 3.2.2
    
    log_info "Airflow deployment completed."
}

# ═══════════════════════════════════════════════════════════════
# Step 4: Run the docker_helloworld DAG
# ═══════════════════════════════════════════════════════════════

run_helloworld_dag() {
    local SETUP_DIR="/root/airflow-setup"
    
    log_info "Triggering docker_helloworld DAG..."
    
    cd "$SETUP_DIR"
    bash run_dag.sh docker_helloworld
    
    log_info "DAG execution initiated."
}

# ═══════════════════════════════════════════════════════════════
# Main orchestration
# ═══════════════════════════════════════════════════════════════

main() {
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     GCE VM Airflow + Helloworld DAG Setup (Root Mode)        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Verify running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root!"
        exit 1
    fi
    
    # Execute steps
    install_dependencies
    echo ""
    
    copy_airflow_setup
    echo ""
    
    deploy_airflow_if_needed
    echo ""
    
    run_helloworld_dag
    echo ""
    
    # Final summary
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Setup Complete!                           ║"
    echo "║  Airflow UI: http://localhost:8080                           ║"
    echo "║  Username:   airflow                                         ║"
    echo "║  Password:   airflow                                         ║"
    echo "║  DAG:        docker_helloworld                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

main "$@"