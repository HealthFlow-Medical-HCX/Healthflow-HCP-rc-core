#!/bin/bash

# =============================================================================
# HealthFlow Sunbird RC v2 - Digital Ocean Quick Setup
# One-click deployment script for Digital Ocean droplets
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  HealthFlow Sunbird RC v2 - Digital Ocean Setup${NC}"
echo -e "${CYAN}  Egyptian Healthcare Registry Platform${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run this script as root or with sudo"
    exit 1
fi

# Update system
log_info "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install prerequisites
log_info "Installing prerequisites..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    htop \
    vim \
    ufw \
    fail2ban \
    unzip \
    jq \
    nginx \
    certbot \
    python3-certbot-nginx

# Install Docker
log_info "Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker
    log_success "Docker installed"
else
    log_info "Docker already installed"
fi

# Configure Docker
log_info "Configuring Docker..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl restart docker

# Create healthflow user
log_info "Creating healthflow user..."
if ! id "healthflow" &>/dev/null; then
    useradd -m -s /bin/bash healthflow
    usermod -aG docker healthflow
    usermod -aG sudo healthflow
    log_success "User healthflow created"
else
    log_info "User healthflow already exists"
fi

# Configure system limits for Elasticsearch
log_info "Configuring system limits..."
cat > /etc/sysctl.d/99-elasticsearch.conf << 'EOF'
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=65535
EOF
sysctl -p /etc/sysctl.d/99-elasticsearch.conf

# Configure firewall
log_info "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 8080/tcp  # Keycloak
ufw allow 8081/tcp  # Registry
ufw --force enable
log_success "Firewall configured"

# Configure fail2ban
log_info "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log_success "Fail2ban configured"

# Create deployment directory
log_info "Setting up deployment directory..."
mkdir -p /opt/healthflow/sunbird-rc
mkdir -p /opt/healthflow/backups
chown -R healthflow:healthflow /opt/healthflow

# Clone repository
log_info "Cloning repository..."
cd /opt/healthflow
if [ -d "Healthflow-HCP-rc-core" ]; then
    cd Healthflow-HCP-rc-core
    git pull origin main
else
    git clone https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core.git
    cd Healthflow-HCP-rc-core
fi

# Copy docker configuration
log_info "Setting up Docker configuration..."
cp -r docker/* /opt/healthflow/sunbird-rc/
chown -R healthflow:healthflow /opt/healthflow

# Create environment file
cd /opt/healthflow/sunbird-rc
if [ ! -f .env ]; then
    cp .env.example .env
    
    # Generate secure passwords
    POSTGRES_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    KEYCLOAK_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    VAULT_TOKEN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    MINIO_SECRET=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    CLICKHOUSE_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    
    # Update .env file with generated passwords
    sed -i "s/CHANGE_ME_secure_postgres_password_2024/$POSTGRES_PASS/g" .env
    sed -i "s/CHANGE_ME_secure_keycloak_password/$KEYCLOAK_PASS/g" .env
    sed -i "s/CHANGE_ME_vault_root_token/$VAULT_TOKEN/g" .env
    sed -i "s/CHANGE_ME_32_character_key_here!/$ENCRYPTION_KEY/g" .env
    sed -i "s/CHANGE_ME_minio_secret_key_2024/$MINIO_SECRET/g" .env
    sed -i "s/CHANGE_ME_clickhouse_password/$CLICKHOUSE_PASS/g" .env
    
    log_success "Environment file created with secure passwords"
    log_warning ""
    log_warning "Generated Credentials (save these securely!):"
    log_warning "  PostgreSQL Password: $POSTGRES_PASS"
    log_warning "  Keycloak Admin Password: $KEYCLOAK_PASS"
    log_warning "  Vault Token: $VAULT_TOKEN"
    log_warning ""
fi

# Generate SSL certificates
log_info "Generating SSL certificates..."
mkdir -p configs/ssl
if [ ! -f configs/ssl/cert.pem ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout configs/ssl/key.pem \
        -out configs/ssl/cert.pem \
        -subj "/C=EG/ST=Cairo/L=Cairo/O=HealthFlow/CN=healthflow.local" \
        2>/dev/null
    log_success "SSL certificates generated"
fi

# Create backup cron job
log_info "Setting up backup cron job..."
cat > /etc/cron.d/healthflow-backup << 'EOF'
0 2 * * * healthflow /opt/healthflow/Healthflow-HCP-rc-core/scripts/deploy.sh production backup >> /var/log/healthflow-backup.log 2>&1
EOF

# Set permissions
chown -R healthflow:healthflow /opt/healthflow
chmod +x /opt/healthflow/Healthflow-HCP-rc-core/scripts/*.sh

# Print summary
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Setup Complete!${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "Server is ready for HealthFlow Sunbird RC deployment."
echo ""
echo "Next Steps:"
echo "  1. Review and update configuration:"
echo "     nano /opt/healthflow/sunbird-rc/.env"
echo ""
echo "  2. Update Cequens SMS credentials in .env file"
echo ""
echo "  3. Deploy services:"
echo "     cd /opt/healthflow/sunbird-rc"
echo "     sudo -u healthflow docker compose up -d"
echo ""
echo "  4. Check service status:"
echo "     docker compose ps"
echo ""
echo "  5. View logs:"
echo "     docker compose logs -f"
echo ""
echo "Service URLs (after deployment):"
echo "  - Registry API:   http://$(hostname -I | awk '{print $1}'):8081"
echo "  - Keycloak:       http://$(hostname -I | awk '{print $1}'):8080"
echo ""
log_success "Digital Ocean setup completed!"
