#!/bin/bash

# =============================================================================
# HealthFlow Sunbird RC v2 - Deployment Script
# Egyptian Healthcare Registry Platform
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$PROJECT_DIR/docker"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

# Header
log_header "HealthFlow Sunbird RC v2 - Deployment"

# Parse arguments
ENVIRONMENT=${1:-production}
ACTION=${2:-deploy}

log_info "Environment: $ENVIRONMENT"
log_info "Action: $ACTION"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ] && ! groups | grep -q docker; then
        log_warning "You may need to run this script with sudo or add your user to the docker group."
    fi
    
    log_success "Prerequisites check passed"
}

# Setup environment
setup_environment() {
    log_info "Setting up environment..."
    
    cd "$DOCKER_DIR"
    
    # Check environment file
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            cp .env.example .env
            log_warning ".env file created from .env.example"
            log_warning "Please edit .env file with your actual configuration values!"
            log_warning ""
            log_warning "Critical variables to update:"
            log_warning "  - POSTGRES_PASSWORD"
            log_warning "  - KEYCLOAK_ADMIN_PASSWORD"
            log_warning "  - VAULT_TOKEN"
            log_warning "  - ENCRYPTION_KEY (32 characters)"
            log_warning "  - CEQUENS_* credentials"
            log_warning "  - MINIO_SECRET_KEY"
            log_warning ""
            read -p "Press Enter after updating .env file to continue..."
        else
            log_error ".env.example file not found. Cannot proceed."
            exit 1
        fi
    fi
    
    # Source environment variables
    set -a
    source .env
    set +a
    
    log_success "Environment setup complete"
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."
    
    cd "$DOCKER_DIR"
    
    # Required variables
    REQUIRED_VARS=(
        "POSTGRES_PASSWORD"
        "KEYCLOAK_ADMIN_PASSWORD"
        "VAULT_TOKEN"
        "ENCRYPTION_KEY"
    )
    
    MISSING_VARS=()
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ] || [[ "${!var}" == *"CHANGE_ME"* ]]; then
            MISSING_VARS+=("$var")
        fi
    done
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        log_error "Missing or unconfigured environment variables:"
        for var in "${MISSING_VARS[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    # Validate encryption key length
    if [ ${#ENCRYPTION_KEY} -ne 32 ]; then
        log_error "ENCRYPTION_KEY must be exactly 32 characters (current: ${#ENCRYPTION_KEY})"
        exit 1
    fi
    
    # Validate Docker Compose file
    docker compose config --quiet || {
        log_error "Docker Compose configuration is invalid"
        exit 1
    }
    
    log_success "Configuration validated"
}

# Create directories
create_directories() {
    log_info "Creating directory structure..."
    
    mkdir -p "$DOCKER_DIR/configs/ssl"
    mkdir -p "$DOCKER_DIR/configs/templates"
    mkdir -p "$DOCKER_DIR/configs/keycloak"
    mkdir -p "$DOCKER_DIR/configs/notification-templates"
    mkdir -p "$DOCKER_DIR/bulk-issuance/templates"
    mkdir -p "$DOCKER_DIR/logs"
    
    log_success "Directory structure created"
}

# Generate SSL certificates
generate_ssl() {
    log_info "Checking SSL certificates..."
    
    if [ ! -f "$DOCKER_DIR/configs/ssl/cert.pem" ]; then
        log_info "Generating self-signed SSL certificates for development..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$DOCKER_DIR/configs/ssl/key.pem" \
            -out "$DOCKER_DIR/configs/ssl/cert.pem" \
            -subj "/C=EG/ST=Cairo/L=Cairo/O=HealthFlow/CN=healthflow.local" \
            2>/dev/null
        log_success "SSL certificates generated"
    else
        log_info "SSL certificates already exist"
    fi
}

# Pull Docker images
pull_images() {
    log_info "Pulling Docker images (this may take a while)..."
    
    cd "$DOCKER_DIR"
    docker compose pull
    
    log_success "Docker images pulled"
}

# Start infrastructure services
start_infrastructure() {
    log_info "Starting infrastructure services..."
    
    cd "$DOCKER_DIR"
    
    # Start core infrastructure first
    docker compose up -d db redis elasticsearch zookeeper kafka vault
    
    log_info "Waiting for infrastructure services to be healthy..."
    sleep 30
    
    # Check database health
    log_info "Checking database health..."
    until docker exec healthflow-db pg_isready -U ${POSTGRES_USER:-healthflow} -d registry 2>/dev/null; do
        log_warning "Waiting for database..."
        sleep 5
    done
    log_success "Database is ready"
    
    # Initialize Vault
    log_info "Initializing Vault..."
    sleep 10
    docker exec healthflow-vault vault secrets enable -path=kv kv-v2 2>/dev/null || true
    log_success "Vault initialized"
}

# Start Keycloak
start_keycloak() {
    log_info "Starting Keycloak..."
    
    cd "$DOCKER_DIR"
    docker compose up -d keycloak
    
    log_info "Waiting for Keycloak to be ready (this may take 1-2 minutes)..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf http://localhost:8080/health/ready &>/dev/null; then
            log_success "Keycloak is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 5
    done
    
    log_warning "Keycloak may not be fully ready, continuing..."
}

# Start all services
start_all_services() {
    log_info "Starting all HealthFlow services..."
    
    cd "$DOCKER_DIR"
    docker compose up -d
    
    log_info "Waiting for all services to be healthy..."
    sleep 60
}

# Health check
health_check() {
    log_header "Running Health Checks"
    
    check_service() {
        local service=$1
        local url=$2
        if curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -q "200\|301\|302"; then
            log_success "$service is healthy"
            return 0
        else
            log_warning "$service may not be fully ready"
            return 1
        fi
    }
    
    check_service "Registry API" "http://localhost:8081/health" || true
    check_service "Keycloak" "http://localhost:8080/health/ready" || true
    check_service "Credentials Service" "http://localhost:3000/health" || true
    check_service "Identity Service" "http://localhost:3332/health" || true
    check_service "Elasticsearch" "http://localhost:9200/_cluster/health" || true
}

# Deploy
deploy() {
    check_prerequisites
    setup_environment
    validate_config
    create_directories
    generate_ssl
    pull_images
    start_infrastructure
    start_keycloak
    start_all_services
    health_check
    
    log_header "Deployment Complete!"
    
    echo "Service URLs:"
    echo "  - Registry API:     http://localhost:8081"
    echo "  - Keycloak Admin:   http://localhost:8080 (admin/********)"
    echo "  - Credentials API:  http://localhost:3000"
    echo "  - Identity Service: http://localhost:3332"
    echo "  - Bulk Issuance:    http://localhost:8085"
    echo "  - Vault UI:         http://localhost:8200"
    echo "  - MinIO Console:    http://localhost:9001"
    echo "  - Elasticsearch:    http://localhost:9200"
    echo ""
    echo "Next Steps:"
    echo "  1. Access Keycloak and configure realms/clients"
    echo "  2. Upload schemas via Registry API"
    echo "  3. Configure Cequens SMS credentials"
    echo "  4. Run bulk issuance for EMS data migration"
    echo ""
    echo "For logs: docker compose logs -f [service_name]"
    echo "To stop:  docker compose down"
    echo ""
    
    log_success "Setup completed successfully!"
}

# Stop services
stop() {
    log_info "Stopping all services..."
    cd "$DOCKER_DIR"
    docker compose down
    log_success "All services stopped"
}

# Restart services
restart() {
    stop
    deploy
}

# Show status
status() {
    log_header "Service Status"
    cd "$DOCKER_DIR"
    docker compose ps
    echo ""
    health_check
}

# Show logs
logs() {
    local service=${1:-}
    cd "$DOCKER_DIR"
    if [ -n "$service" ]; then
        docker compose logs -f "$service"
    else
        docker compose logs -f
    fi
}

# Backup
backup() {
    log_header "Creating Backup"
    
    local backup_dir="/opt/healthflow/backups"
    local date=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    
    log_info "Backing up PostgreSQL..."
    docker exec healthflow-db pg_dumpall -U ${POSTGRES_USER:-healthflow} > "$backup_dir/postgres_$date.sql"
    
    log_info "Backing up volumes..."
    tar -czf "$backup_dir/volumes_$date.tar.gz" /var/lib/docker/volumes/healthflow* 2>/dev/null || true
    
    log_success "Backup completed: $backup_dir"
    ls -la "$backup_dir"
}

# Main
case "$ACTION" in
    deploy)
        deploy
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs "$3"
        ;;
    backup)
        backup
        ;;
    health)
        health_check
        ;;
    *)
        echo "Usage: $0 [environment] [action]"
        echo ""
        echo "Environments: production, staging, development"
        echo ""
        echo "Actions:"
        echo "  deploy   - Deploy all services (default)"
        echo "  stop     - Stop all services"
        echo "  restart  - Restart all services"
        echo "  status   - Show service status"
        echo "  logs     - Show logs (optionally specify service)"
        echo "  backup   - Create backup"
        echo "  health   - Run health checks"
        echo ""
        echo "Examples:"
        echo "  $0 production deploy"
        echo "  $0 staging stop"
        echo "  $0 production logs registry"
        ;;
esac
