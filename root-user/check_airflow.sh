#!/bin/bash

# Airflow Status Check Script — ROOT USER VERSION
# Usage: ./check_airflow.sh [optional: compose-file-path]

set -e

# Colors for better visibility
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AIRFLOW_HOST_DIR="/opt/airflow"
COMPOSE_FILE="${1:-$AIRFLOW_HOST_DIR/docker-compose.yaml}"
WEBSERVER_PORT="${AIRFLOW_WEBSERVER_PORT:-8080}"

# Required items in the host directory
REQUIRED_DIRECTORIES=(
    "$AIRFLOW_HOST_DIR/config"
    "$AIRFLOW_HOST_DIR/dags"
    "$AIRFLOW_HOST_DIR/plugins"
    "$AIRFLOW_HOST_DIR/logs"
)

REQUIRED_FILES=(
    "$AIRFLOW_HOST_DIR/.env"
    "$AIRFLOW_HOST_DIR/airflow_cli.sh"
    "$AIRFLOW_HOST_DIR/docker-compose.yaml"
    "$AIRFLOW_HOST_DIR/config/airflow.cfg"
)

echo "🔍 Starting Airflow Health Check (Root User Version)..."
echo "📅 $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Function to check if docker compose is available
check_docker_compose() {
    echo -e "\n🐳 Checking Docker Compose..."
    if docker compose version &>/dev/null; then
        echo -e "${GREEN}✅ Docker Compose is available${NC}"
        return 0
    else
        echo -e "${RED}❌ Docker Compose not found!${NC}"
        return 1
    fi
}

# Function to check if compose file exists
check_compose_file() {
    echo -e "\n📄 Checking Compose File..."
    if [ -f "$COMPOSE_FILE" ]; then
        echo -e "${GREEN}✅ Compose file found: $COMPOSE_FILE${NC}"
        return 0
    else
        echo -e "${RED}❌ Compose file not found: $COMPOSE_FILE${NC}"
        return 1
    fi
}

# Function to check host directory structure
check_host_directory() {
    echo -e "\n📁 Checking Host Directory Structure..."
    local all_ok=true
    
    # Check if base directory exists
    if [ ! -d "$AIRFLOW_HOST_DIR" ]; then
        echo -e "${RED}❌ Host directory not found: $AIRFLOW_HOST_DIR${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ Host directory exists: $AIRFLOW_HOST_DIR${NC}"
    
    # Check required subdirectories
    echo -e "\n   📂 Checking required directories:"
    for dir in "${REQUIRED_DIRECTORIES[@]}"; do
        if [ -d "$dir" ]; then
            # Count files in directory
            FILE_COUNT=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
            DIR_COUNT=$(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            echo -e "   ${GREEN}✅ $dir/ exists${NC} (${FILE_COUNT} files, ${DIR_COUNT} subdirs)"
        else
            echo -e "   ${RED}❌ $dir/ missing${NC}"
            all_ok=false
        fi
    done
    
    # Check required files
    echo -e "\n   📄 Checking required files:"
    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$file" ]; then
            # Get file size
            SIZE=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            if [ ! -z "$SIZE" ] && [ "$SIZE" -gt 0 ]; then
                echo -e "   ${GREEN}✅ $$file exists${NC} (${SIZE} bytes)"
            else
                echo -e "   ${YELLOW}⚠️  $file exists but is empty${NC}"
            fi
        else
            echo -e "   ${RED}❌ $file missing${NC}"
            all_ok=false
        fi
    done
    
    # Additional checks for important files
    echo -e "\n   🔍 Additional checks:"
    
    # Check .env file permissions (should not be world-readable)
    if [ -f "$AIRFLOW_HOST_DIR/.env" ]; then
        ENV_PERMS=$(stat -c "%a" "$AIRFLOW_HOST_DIR/.env" 2>/dev/null || stat -f "%Lp" "$AIRFLOW_HOST_DIR/.env" 2>/dev/null)
        if [ ! -z "$ENV_PERMS" ] && [ "$ENV_PERMS" -le "644" ]; then
            echo -e "   ${GREEN}✅ .env permissions are secure ($ENV_PERMS)${NC}"
        else
            echo -e "   ${YELLOW}⚠️  .env permissions might be too permissive ($ENV_PERMS)${NC}"
        fi
    fi
    
    # Check airflow_cli.sh is executable
    if [ -f "$AIRFLOW_HOST_DIR/airflow_cli.sh" ]; then
        if [ -x "$AIRFLOW_HOST_DIR/airflow_cli.sh" ]; then
            echo -e "   ${GREEN}✅ airflow_cli.sh is executable${NC}"
        else
            echo -e "   ${YELLOW}⚠️  airflow_cli.sh is not executable${NC}"
        fi
    fi
    
    # Check docker-compose.yaml is valid YAML
    if [ -f "$AIRFLOW_HOST_DIR/docker-compose.yaml" ]; then
        if command -v python3 &>/dev/null; then
            if python3 -c "import yaml; yaml.safe_load(open('$AIRFLOW_HOST_DIR/docker-compose.yaml'))" 2>/dev/null; then
                echo -e "   ${GREEN}✅ docker-compose.yaml is valid YAML${NC}"
            else
                echo -e "   ${YELLOW}⚠️  docker-compose.yaml might have syntax errors${NC}"
            fi
        fi
    fi
    
    # Summary
    if [ "$all_ok" = true ]; then
        echo -e "\n   ${GREEN}🎯 All required directories and files are present!${NC}"
        return 0
    else
        echo -e "\n   ${RED}💥 Some required items are missing!${NC}"
        return 1
    fi
}

# Function to check containers status
check_containers() {
    echo -e "\n📦 Checking Container Status..."
    CONTAINERS=$(docker compose ps --format json 2>/dev/null)
    
    if [ -z "$CONTAINERS" ]; then
        echo -e "${RED}❌ No containers running!${NC}"
        return 1
    fi
    
    echo "$CONTAINERS" | while IFS= read -r line; do
        NAME=$(echo "$line" | jq -r '.Name' 2>/dev/null || echo "unknown")
        STATE=$(echo "$line" | jq -r '.State' 2>/dev/null || echo "unknown")
        HEALTH=$(echo "$line" | jq -r '.Health' 2>/dev/null || echo "N/A")
        
        if [ "$STATE" = "running" ]; then
            if [ "$HEALTH" = "healthy" ]; then
                echo -e "${GREEN}✅ $NAME: $STATE ($HEALTH)${NC}"
            else
                echo -e "${YELLOW}⚠️  $NAME: $STATE (Health: $HEALTH)${NC}"
            fi
        else
            echo -e "${RED}❌ $NAME: $STATE${NC}"
        fi
    done
    
    return 0
}

# Function to check Airflow version
check_airflow_version() {
    echo -e "\n🔧 Checking Airflow Installation..."
    
    # Try webserver first, then scheduler
    for SERVICE in "airflow-webserver" "airflow-scheduler"; do
        if docker compose ps "$SERVICE" 2>/dev/null | grep -q "Up"; then
            VERSION=$(docker compose exec "$SERVICE" airflow version 2>/dev/null)
            if [ $? -eq 0 ] && [ ! -z "$VERSION" ]; then
                echo -e "${GREEN}✅ Airflow is installed${NC}"
                echo -e "   🏷️  Version: ${BLUE}$VERSION${NC}"
                
                # Check binary location
                BIN_PATH=$(docker compose exec "$SERVICE" which airflow 2>/dev/null)
                echo -e "   📍 Binary: $BIN_PATH"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}❌ Could not determine Airflow version${NC}"
    return 1
}

# Function to check database connection
check_database() {
    echo -e "\n🗄️  Checking Database Connection..."
    
    for SERVICE in "airflow-webserver" "airflow-scheduler"; do
        if docker compose ps "$SERVICE" 2>/dev/null | grep -q "Up"; then
            if docker compose exec "$SERVICE" airflow db check 2>/dev/null; then
                echo -e "${GREEN}✅ Database connection successful${NC}"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}❌ Database connection failed${NC}"
    return 1
}

# Function to check webserver health
check_webserver() {
    echo -e "\n🌐 Checking Webserver Health..."
    
    # Try multiple endpoints
    ENDPOINTS=(
        "http://localhost:${WEBSERVER_PORT}/health"
        "http://localhost:${WEBSERVER_PORT}/api/v1/health"
        "http://localhost:${WEBSERVER_PORT}"
    )
    
    for ENDPOINT in "${ENDPOINTS[@]}"; do
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT" 2>/dev/null)
        if [ "$RESPONSE" = "200" ]; then
            HEALTH_DATA=$(curl -s "$ENDPOINT" 2>/dev/null)
            echo -e "${GREEN}✅ Webserver is responding${NC}"
            echo -e "   🔗 URL: $ENDPOINT"
            echo -e "   📊 Response: $HEALTH_DATA"
            return 0
        fi
    done
    
    echo -e "${RED}❌ Webserver is not responding on port $WEBSERVER_PORT${NC}"
    return 1
}

# Function to check recent logs
check_logs() {
    echo -e "\n📋 Checking Recent Logs..."
    
    echo -e "${BLUE}   📝 Scheduler logs (last 5 lines):${NC}"
    docker compose logs --tail=5 airflow-scheduler 2>/dev/null | tail -5
    
    echo -e "\n${BLUE}   📝 Webserver errors (if any):${NC}"
    docker compose logs --tail=10 airflow-webserver 2>/dev/null | grep -i "error\|exception\|fail" | tail -3 || echo "   ✅ No recent errors"
}

# Function to check installed Python packages (FIXED)
check_python_packages() {
    echo -e "\n📦 Checking Installed Airflow Packages..."
    
    # Try to find a running container
    for SERVICE in "airflow-apiserver" "airflow-scheduler" "airflow-worker" "airflow-triggerer"; do
        if docker compose ps "$SERVICE" 2>/dev/null | grep -q "Up"; then
            
            # Method 1: Try pip via python -m pip (avoids PATH issues)
            echo -e "   🔍 Checking packages in $SERVICE container..."
            PACKAGES=$(docker compose exec -T "$SERVICE" python3 -m pip list 2>/dev/null | grep -i airflow || \
                      docker compose exec -T "$SERVICE" python -m pip list 2>/dev/null | grep -i airflow)
            
            if [ ! -z "$PACKAGES" ]; then
                echo -e "${GREEN}✅ Airflow Python packages found:${NC}"
                echo "$PACKAGES" | while read -r line; do
                    echo -e "   📌 $line"
                done
                return 0
            fi
            
            # Method 2: Try to locate pip inside container
            echo -e "   🔄 Trying alternative pip location..."
            PIP_PATHS=(
                "/home/airflow/.local/bin/pip"
                "/usr/local/bin/pip"
                "/usr/bin/pip"
                "/opt/airflow/.local/bin/pip"
            )
            
            for PIP_PATH in "${PIP_PATHS[@]}"; do
                PACKAGES=$(docker compose exec -T "$SERVICE" "$PIP_PATH" list 2>/dev/null | grep -i airflow)
                if [ ! -z "$PACKAGES" ]; then
                    echo -e "${GREEN}✅ Airflow Python packages found (using $PIP_PATH):${NC}"
                    echo "$PACKAGES" | while read -r line; do
                        echo -e "   📌 $line"
                    done
                    return 0
                fi
            done
            
            # Method 3: Use Python directly to list packages
            echo -e "   🔄 Using Python to query packages..."
            PACKAGES=$(docker compose exec -T "$SERVICE" python3 -c "import pkg_resources; [print(f'{p.project_name}=={p.version}') for p in pkg_resources.working_set if 'airflow' in p.project_name.lower()]" 2>/dev/null || \
                      docker compose exec -T "$SERVICE" python -c "import pkg_resources; [print(f'{p.project_name}=={p.version}') for p in pkg_resources.working_set if 'airflow' in p.project_name.lower()]" 2>/dev/null)
            
            if [ ! -z "$PACKAGES" ]; then
                echo -e "${GREEN}✅ Airflow Python packages found:${NC}"
                echo "$PACKAGES" | while read -r line; do
                    echo -e "   📌 $line"
                done
                return 0
            fi
            
            # If we get here, we found a container but couldn't get packages
            echo -e "${YELLOW}⚠️  Found running container ($SERVICE) but couldn't list packages${NC}"
            echo -e "   💡 Try manually: docker compose exec $SERVICE python3 -m pip list | grep airflow"
            return 1
        fi
    done
    
    echo -e "${YELLOW}⚠️  No running Airflow containers found to check packages${NC}"
    return 1
}

# Main execution
main() {
    SUCCESS_COUNT=0
    TOTAL_CHECKS=0
    
    # Run all checks
    check_docker_compose && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_compose_file && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_host_directory  && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true

    cd $AIRFLOW_HOST_DIR
    
    check_containers && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_airflow_version && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_database && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_webserver && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_python_packages && ((SUCCESS_COUNT++)) || true
    ((TOTAL_CHECKS++)) || true
    
    check_logs

    cd -

    
    # Summary
    echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Summary:"
    echo -e "   ✅ Successful checks: ${GREEN}$SUCCESS_COUNT${NC}/${TOTAL_CHECKS}"
    echo -e "   ❌ Failed checks: ${RED}$((TOTAL_CHECKS - SUCCESS_COUNT))${NC}/${TOTAL_CHECKS}"
    
    if [ $SUCCESS_COUNT -eq $TOTAL_CHECKS ]; then
        echo -e "\n🎉 ${GREEN}All checks passed! Airflow is healthy and running!${NC}"
        return 0
    elif [ $SUCCESS_COUNT -gt $((TOTAL_CHECKS / 2)) ]; then
        echo -e "\n⚠️  ${YELLOW}Some checks failed. Review the issues above.${NC}"
        return 1
    else
        echo -e "\n💥 ${RED}Multiple checks failed. Airflow may not be running properly.${NC}"
        return 2
    fi
}

# Run main function
main
exit $?
