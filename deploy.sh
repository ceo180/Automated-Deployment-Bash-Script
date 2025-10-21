#!/bin/bash

###############################################################################
# Automated Deployment Script for Dockerized Applications
# Author: DevOps Stage 1
# Description: Production-grade deployment automation with error handling
###############################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR=""
CLEANUP_MODE=false

# Check for cleanup flag
if [[ "${1:-}" == "--cleanup" ]]; then
    CLEANUP_MODE=true
fi

###############################################################################
# Logging Functions
###############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

###############################################################################
# Error Handling
###############################################################################

cleanup() {
    local exit_code=$?
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
    
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script failed with exit code ${exit_code}"
        log_error "Check log file: ${LOG_FILE}"
    fi
    
    exit ${exit_code}
}

trap cleanup EXIT INT TERM

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

###############################################################################
# Input Validation Functions
###############################################################################

validate_url() {
    local url=$1
    if [[ ! ${url} =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip=$1
    if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port=$1
    if [[ ${port} =~ ^[0-9]+$ ]] && [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
        return 0
    fi
    return 1
}

###############################################################################
# User Input Collection
###############################################################################

collect_parameters() {
    log_info "===== Parameter Collection ====="
    
    # Git Repository URL
    while true; do
        read -p "Enter Git Repository URL: " GIT_REPO_URL
        if validate_url "${GIT_REPO_URL}"; then
            break
        else
            log_error "Invalid URL format. Please use http:// or https://"
        fi
    done
    
    # Personal Access Token
    read -sp "Enter Personal Access Token (PAT): " GIT_PAT
    echo
    if [[ -z "${GIT_PAT}" ]]; then
        error_exit "PAT cannot be empty" 2
    fi
    
    # Branch name
    read -p "Enter branch name (default: main): " GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
    
    # SSH Username
    read -p "Enter SSH username: " SSH_USER
    if [[ -z "${SSH_USER}" ]]; then
        error_exit "SSH username cannot be empty" 3
    fi
    
    # Server IP
    while true; do
        read -p "Enter server IP address: " SERVER_IP
        if validate_ip "${SERVER_IP}"; then
            break
        else
            log_error "Invalid IP address format"
        fi
    done
    
    # SSH Key Path
    while true; do
        read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY_PATH
        SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_rsa}
        SSH_KEY_PATH="${SSH_KEY_PATH/#\~/$HOME}"
        
        if [[ -f "${SSH_KEY_PATH}" ]]; then
            break
        else
            log_error "SSH key not found at ${SSH_KEY_PATH}"
        fi
    done
    
    # Application Port
    while true; do
        read -p "Enter application port: " APP_PORT
        if validate_port "${APP_PORT}"; then
            break
        else
            log_error "Invalid port number (1-65535)"
        fi
    done
    
    log_success "All parameters collected successfully"
}

###############################################################################
# Repository Management
###############################################################################

clone_repository() {
    log_info "===== Repository Cloning ====="
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: ${TEMP_DIR}"
    
    # Extract repo name from URL
    REPO_NAME=$(basename "${GIT_REPO_URL}" .git)
    REPO_PATH="${TEMP_DIR}/${REPO_NAME}"
    
    # Prepare authenticated URL
    local auth_url
    if [[ ${GIT_REPO_URL} =~ github.com ]]; then
        auth_url=$(echo "${GIT_REPO_URL}" | sed "s|https://|https://${GIT_PAT}@|")
    else
        auth_url="${GIT_REPO_URL}"
    fi
    
    # Clone or pull repository
    if [[ -d "${REPO_PATH}" ]]; then
        log_info "Repository already exists, pulling latest changes..."
        cd "${REPO_PATH}"
        git pull origin "${GIT_BRANCH}" || error_exit "Failed to pull repository" 4
    else
        log_info "Cloning repository..."
        git clone -b "${GIT_BRANCH}" "${auth_url}" "${REPO_PATH}" || error_exit "Failed to clone repository" 4
    fi
    
    cd "${REPO_PATH}" || error_exit "Failed to navigate to repository" 5
    log_success "Repository ready at: ${REPO_PATH}"
}

###############################################################################
# Dockerfile Validation
###############################################################################

validate_docker_files() {
    log_info "===== Validating Docker Files ====="
    
    if [[ -f "Dockerfile" ]]; then
        log_success "Dockerfile found"
        USE_COMPOSE=false
    elif [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log_success "docker-compose.yml found"
        USE_COMPOSE=true
    else
        error_exit "No Dockerfile or docker-compose.yml found in repository" 6
    fi
}

###############################################################################
# SSH Connectivity Check
###############################################################################

test_ssh_connection() {
    log_info "===== Testing SSH Connection ====="
    
    if ssh -i "${SSH_KEY_PATH}" -o ConnectTimeout=10 -o BatchMode=yes "${SSH_USER}@${SERVER_IP}" "echo 'SSH connection successful'" &>/dev/null; then
        log_success "SSH connection to ${SSH_USER}@${SERVER_IP} successful"
    else
        error_exit "Failed to establish SSH connection to ${SSH_USER}@${SERVER_IP}" 7
    fi
}

###############################################################################
# Remote Command Execution
###############################################################################

remote_exec() {
    ssh -i "${SSH_KEY_PATH}" -o StrictHostKeyChecking=no "${SSH_USER}@${SERVER_IP}" "$@"
}

###############################################################################
# Remote Environment Setup
###############################################################################

setup_remote_environment() {
    log_info "===== Setting Up Remote Environment ====="
    
    log_info "Updating system packages..."
    remote_exec "sudo apt-get update -y" || log_warning "Package update failed"
    
    log_info "Installing Docker..."
    remote_exec "
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker ${SSH_USER}
            rm get-docker.sh
        else
            echo 'Docker already installed'
        fi
    " || error_exit "Failed to install Docker" 8
    
    log_info "Installing Docker Compose..."
    remote_exec "
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo 'Docker Compose already installed'
        fi
    " || error_exit "Failed to install Docker Compose" 9
    
    log_info "Installing Nginx..."
    remote_exec "
        if ! command -v nginx &> /dev/null; then
            sudo apt-get install -y nginx
            sudo systemctl enable nginx
            sudo systemctl start nginx
        else
            echo 'Nginx already installed'
        fi
    " || error_exit "Failed to install Nginx" 10
    
    log_info "Verifying installations..."
    remote_exec "
        echo 'Docker version:'
        docker --version
        echo 'Docker Compose version:'
        docker-compose --version
        echo 'Nginx version:'
        nginx -v
    "
    
    log_success "Remote environment setup complete"
}

###############################################################################
# Application Deployment
###############################################################################

deploy_application() {
    log_info "===== Deploying Application ====="
    
    local remote_deploy_dir="/home/${SSH_USER}/deployments/${REPO_NAME}"
    
    log_info "Creating remote deployment directory..."
    remote_exec "mkdir -p ${remote_deploy_dir}"
    
    log_info "Transferring project files..."
    rsync -avz --delete -e "ssh -i ${SSH_KEY_PATH}" "${REPO_PATH}/" "${SSH_USER}@${SERVER_IP}:${remote_deploy_dir}/" || error_exit "Failed to transfer files" 11
    
    log_info "Stopping existing containers..."
    remote_exec "
        cd ${remote_deploy_dir}
        docker-compose down 2>/dev/null || docker stop ${REPO_NAME} 2>/dev/null || true
        docker rm ${REPO_NAME} 2>/dev/null || true
    "
    
    if [[ ${USE_COMPOSE} == true ]]; then
        log_info "Building and starting with Docker Compose..."
        remote_exec "
            cd ${remote_deploy_dir}
            docker-compose up -d --build
        " || error_exit "Failed to deploy with Docker Compose" 12
    else
        log_info "Building Docker image..."
        remote_exec "
            cd ${remote_deploy_dir}
            docker build -t ${REPO_NAME}:latest .
        " || error_exit "Failed to build Docker image" 13
        
        log_info "Running Docker container..."
        remote_exec "
            docker run -d --name ${REPO_NAME} -p ${APP_PORT}:${APP_PORT} ${REPO_NAME}:latest
        " || error_exit "Failed to run Docker container" 14
    fi
    
    sleep 5  # Allow container to start
    
    log_info "Checking container status..."
    remote_exec "docker ps | grep ${REPO_NAME}" || error_exit "Container not running" 15
    
    log_success "Application deployed successfully"
}

###############################################################################
# Nginx Configuration
###############################################################################

configure_nginx() {
    log_info "===== Configuring Nginx Reverse Proxy ====="
    
    local nginx_config="/etc/nginx/sites-available/${REPO_NAME}"
    
    log_info "Creating Nginx configuration..."
    remote_exec "
        sudo tee ${nginx_config} > /dev/null <<EOF
server {
    listen 80;
    server_name ${SERVER_IP};

    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \\\$host;
        proxy_cache_bypass \\\$http_upgrade;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
EOF
    " || error_exit "Failed to create Nginx config" 16
    
    log_info "Enabling Nginx site..."
    remote_exec "
        sudo ln -sf ${nginx_config} /etc/nginx/sites-enabled/${REPO_NAME}
        sudo rm -f /etc/nginx/sites-enabled/default
    "
    
    log_info "Testing Nginx configuration..."
    remote_exec "sudo nginx -t" || error_exit "Nginx configuration test failed" 17
    
    log_info "Reloading Nginx..."
    remote_exec "sudo systemctl reload nginx" || error_exit "Failed to reload Nginx" 18
    
    log_success "Nginx configured successfully"
}

###############################################################################
# Deployment Validation
###############################################################################

validate_deployment() {
    log_info "===== Validating Deployment ====="
    
    log_info "Checking Docker service..."
    remote_exec "sudo systemctl is-active docker" || error_exit "Docker service not running" 19
    
    log_info "Checking container health..."
    remote_exec "docker ps | grep ${REPO_NAME}" || error_exit "Container not found" 20
    
    log_info "Checking Nginx status..."
    remote_exec "sudo systemctl is-active nginx" || error_exit "Nginx not running" 21
    
    log_info "Testing local endpoint..."
    remote_exec "curl -f http://localhost:${APP_PORT} || curl -f http://localhost" || log_warning "Local endpoint test failed"
    
    log_info "Testing external endpoint..."
    sleep 3
    if curl -f -s "http://${SERVER_IP}" > /dev/null; then
        log_success "External endpoint accessible at http://${SERVER_IP}"
    else
        log_warning "External endpoint may not be accessible yet. Check firewall rules."
    fi
    
    log_success "Deployment validation complete"
}

###############################################################################
# Cleanup Function
###############################################################################

perform_cleanup() {
    log_info "===== Cleanup Mode ====="
    
    if [[ ${CLEANUP_MODE} == true ]]; then
        log_warning "Removing deployed resources..."
        
        remote_exec "
            docker-compose down 2>/dev/null || true
            docker stop ${REPO_NAME} 2>/dev/null || true
            docker rm ${REPO_NAME} 2>/dev/null || true
            docker rmi ${REPO_NAME}:latest 2>/dev/null || true
            sudo rm -f /etc/nginx/sites-enabled/${REPO_NAME}
            sudo rm -f /etc/nginx/sites-available/${REPO_NAME}
            sudo systemctl reload nginx
            rm -rf /home/${SSH_USER}/deployments/${REPO_NAME}
        "
        
        log_success "Cleanup complete"
        exit 0
    fi
}

###############################################################################
# Main Execution
###############################################################################

main() {
    log_info "========================================="
    log_info "  Automated Deployment Script Started"
    log_info "========================================="
    log_info "Log file: ${LOG_FILE}"
    
    if [[ ${CLEANUP_MODE} == true ]]; then
        collect_parameters
        perform_cleanup
        exit 0
    fi
    
    collect_parameters
    clone_repository
    validate_docker_files
    test_ssh_connection
    setup_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    
    log_success "========================================="
    log_success "  Deployment Completed Successfully!"
    log_success "========================================="
    log_success "Application URL: http://${SERVER_IP}"
    log_success "Log file: ${LOG_FILE}"
}

# Execute main function
main "$@"
