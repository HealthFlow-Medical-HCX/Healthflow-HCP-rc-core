#!/bin/bash

# =============================================================================
# HealthFlow - One-Click DigitalOcean Deployment
# Just run: bash deploy-now.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                        ║${NC}"
echo -e "${CYAN}║   HealthFlow - DigitalOcean One-Click Deployment       ║${NC}"
echo -e "${CYAN}║   Egyptian Healthcare Registry Platform                ║${NC}"
echo -e "${CYAN}║                                                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Check dependencies ------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing required tools: ${missing[*]}${NC}"
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq "${missing[@]}"
        elif command -v brew &> /dev/null; then
            brew install "${missing[@]}"
        else
            echo -e "${RED}Please install: ${missing[*]}${NC}"
            exit 1
        fi
    fi
}

check_deps

# --- Step 1: Get API Token ----------------------------------------------------
echo -e "${BLUE}STEP 1: DigitalOcean API Token${NC}"
echo ""
echo "You need a DigitalOcean API token. Here's how to get one:"
echo ""
echo "  1. Go to: https://cloud.digitalocean.com/account/api/tokens"
echo "  2. Click 'Generate New Token'"
echo "  3. Name it: HealthFlow"
echo "  4. Select: Read + Write scope"
echo "  5. Click 'Generate Token'"
echo "  6. Copy the token (it starts with 'dop_v1_')"
echo ""

if [ -z "${DO_API_TOKEN:-}" ]; then
    read -sp "Paste your token here (hidden for security): " DO_API_TOKEN
    echo ""
    echo ""
fi

if [ -z "$DO_API_TOKEN" ]; then
    echo -e "${RED}No token provided. Exiting.${NC}"
    exit 1
fi

# Verify token
echo -n "Verifying token... "
ACCOUNT=$(curl -sS -X GET "https://api.digitalocean.com/v2/account" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json")

EMAIL=$(echo "$ACCOUNT" | jq -r '.account.email // empty')
if [ -z "$EMAIL" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "Invalid token. Please check and try again."
    exit 1
fi
echo -e "${GREEN}OK${NC} (Account: $EMAIL)"
echo ""

# --- Step 2: Choose Server Size -----------------------------------------------
echo -e "${BLUE}STEP 2: Choose Server Size${NC}"
echo ""
echo "  1) Small   - 2 CPU, 4GB RAM  (~\$24/month)  - Testing/Dev"
echo "  2) Medium  - 4 CPU, 8GB RAM  (~\$48/month)  - Recommended"
echo "  3) Large   - 8 CPU, 16GB RAM (~\$96/month)  - Production"
echo ""
read -p "Choose [1/2/3] (default: 2): " size_choice

case "${size_choice:-2}" in
    1) SIZE="s-2vcpu-4gb"; SIZE_LABEL="Small (2 CPU, 4GB)" ;;
    3) SIZE="s-8vcpu-16gb"; SIZE_LABEL="Large (8 CPU, 16GB)" ;;
    *) SIZE="s-4vcpu-8gb"; SIZE_LABEL="Medium (4 CPU, 8GB)" ;;
esac
echo -e "  Selected: ${GREEN}$SIZE_LABEL${NC}"
echo ""

# --- Step 3: Choose Region ----------------------------------------------------
echo -e "${BLUE}STEP 3: Choose Server Location${NC}"
echo ""
echo "  1) Frankfurt, Germany  - Closest to Egypt (recommended)"
echo "  2) Amsterdam, Netherlands"
echo "  3) London, UK"
echo "  4) New York, USA"
echo ""
read -p "Choose [1/2/3/4] (default: 1): " region_choice

case "${region_choice:-1}" in
    2) REGION="ams3"; REGION_LABEL="Amsterdam" ;;
    3) REGION="lon1"; REGION_LABEL="London" ;;
    4) REGION="nyc1"; REGION_LABEL="New York" ;;
    *) REGION="fra1"; REGION_LABEL="Frankfurt (closest to Egypt)" ;;
esac
echo -e "  Selected: ${GREEN}$REGION_LABEL${NC}"
echo ""

# --- Step 4: SSH Key ----------------------------------------------------------
echo -e "${BLUE}STEP 4: SSH Key${NC}"
echo ""

SSH_KEYS_RESP=$(curl -sS -X GET "https://api.digitalocean.com/v2/account/keys?per_page=200" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json")

KEY_COUNT=$(echo "$SSH_KEYS_RESP" | jq '.ssh_keys | length')

SSH_KEY_IDS="[]"
if [ "$KEY_COUNT" -gt 0 ]; then
    echo "  Found SSH keys in your account:"
    echo "$SSH_KEYS_RESP" | jq -r '.ssh_keys[] | "    - \(.name) (ID: \(.id))"'
    echo ""
    read -p "Use all SSH keys? (Y/n): " use_keys
    if [[ ! "${use_keys:-y}" =~ ^[Nn]$ ]]; then
        SSH_KEY_IDS=$(echo "$SSH_KEYS_RESP" | jq '[.ssh_keys[].id]')
        echo -e "  ${GREEN}All SSH keys will be added${NC}"
    fi
else
    echo -e "  ${YELLOW}No SSH keys found. A root password will be emailed to you.${NC}"
fi
echo ""

# --- Confirm ------------------------------------------------------------------
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Deployment Summary${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Server:    $SIZE_LABEL"
echo "  Location:  $REGION_LABEL"
echo "  OS:        Ubuntu 22.04 LTS"
echo "  Storage:   100GB attached volume"
echo "  Backups:   Enabled (daily)"
echo ""
echo "  Will install:"
echo "    - Docker & Docker Compose"
echo "    - PostgreSQL, Elasticsearch, Redis, Kafka"
echo "    - Keycloak (authentication)"
echo "    - HealthFlow Registry API"
echo "    - Vault, Identity, Credentials services"
echo "    - Nginx, Fail2ban, UFW firewall"
echo ""
read -p "Deploy now? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""

# --- Deploy! ------------------------------------------------------------------
API="https://api.digitalocean.com/v2"
DROPLET_NAME="healthflow-sunbird-rc-production"

# Check if already exists
EXISTING=$(curl -sS -X GET "$API/droplets?tag_name=healthflow&per_page=200" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json")

EXISTING_ID=$(echo "$EXISTING" | jq -r --arg name "$DROPLET_NAME" '.droplets[] | select(.name == $name) | .id' 2>/dev/null)

if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
    EXISTING_IP=$(echo "$EXISTING" | jq -r --arg name "$DROPLET_NAME" '.droplets[] | select(.name == $name) | .networks.v4[] | select(.type == "public") | .ip_address' | head -1)
    echo -e "${YELLOW}A HealthFlow droplet already exists!${NC}"
    echo "  ID: $EXISTING_ID"
    echo "  IP: $EXISTING_IP"
    echo ""
    echo "  Registry: http://$EXISTING_IP:8081"
    echo "  Keycloak: http://$EXISTING_IP:8080"
    echo ""
    echo "  SSH: ssh root@$EXISTING_IP"
    exit 0
fi

# Generate cloud-init user data
USERDATA=$(cat << 'USERDATA_EOF'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get upgrade -y

apt-get install -y \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git htop vim ufw fail2ban unzip jq nginx certbot python3-certbot-nginx

# Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl start docker && systemctl enable docker

cat > /etc/docker/daemon.json << 'DEOF'
{"log-driver":"json-file","log-opts":{"max-size":"100m","max-file":"3"},"storage-driver":"overlay2"}
DEOF
systemctl restart docker

# User
useradd -m -s /bin/bash healthflow || true
usermod -aG docker healthflow
usermod -aG sudo healthflow

# System tuning
cat > /etc/sysctl.d/99-elasticsearch.conf << 'SEOF'
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=65535
SEOF
sysctl -p /etc/sysctl.d/99-elasticsearch.conf

# Firewall
ufw default deny incoming && ufw default allow outgoing
ufw allow ssh && ufw allow http && ufw allow https
ufw allow 8080/tcp && ufw allow 8081/tcp
ufw --force enable

# Fail2ban
cat > /etc/fail2ban/jail.local << 'FEOF'
[DEFAULT]
bantime=3600
findtime=600
maxretry=5
[sshd]
enabled=true
port=ssh
maxretry=3
FEOF
systemctl enable fail2ban && systemctl restart fail2ban

# Clone & deploy
mkdir -p /opt/healthflow/backups
cd /opt/healthflow
git clone https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core.git 2>/dev/null || true
cd Healthflow-HCP-rc-core/docker

if [ -f .env.example ] && [ ! -f .env ]; then
    cp .env.example .env
    PG=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    KC=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    VT=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    EK=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
    MK=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    CH=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    JW=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

    sed -i "s/CHANGE_ME_secure_postgres_password_2024/$PG/g" .env
    sed -i "s/CHANGE_ME_secure_keycloak_password/$KC/g" .env
    sed -i "s/CHANGE_ME_vault_root_token/$VT/g" .env
    sed -i "s/CHANGE_ME_32_character_key_here!/$EK/g" .env
    sed -i "s/CHANGE_ME_minio_secret_key_2024/$MK/g" .env
    sed -i "s/CHANGE_ME_clickhouse_password/$CH/g" .env
    sed -i "s/CHANGE_ME_jwt_secret_minimum_32_characters/$JW/g" .env
    sed -i "s/CHANGE_ME_bulk_issuance_secret/$(openssl rand -hex 16)/g" .env
    sed -i "s/CHANGE_ME_generate_uuid/$(cat /proc/sys/kernel/random/uuid)/g" .env

    cat > /opt/healthflow/credentials.txt << CEOF
===== HealthFlow Credentials =====
Generated: $(date -u)

PostgreSQL Password: $PG
Keycloak Admin Password: $KC
Vault Token: $VT
Encryption Key: $EK
MinIO Secret: $MK
ClickHouse Password: $CH
JWT Secret: $JW

Keycloak Admin URL: http://YOUR_IP:8080
  Username: admin
  Password: $KC

Registry API: http://YOUR_IP:8081
===================================
CEOF
    chmod 600 /opt/healthflow/credentials.txt
fi

docker compose -f docker-compose.production.yml up -d
chown -R healthflow:healthflow /opt/healthflow

echo "0 2 * * * root cd /opt/healthflow/Healthflow-HCP-rc-core/docker && docker exec healthflow-db pg_dumpall -U healthflow > /opt/healthflow/backups/postgres_\$(date +\%Y\%m\%d).sql 2>/dev/null" \
    > /etc/cron.d/healthflow-backup

echo "===== HealthFlow provisioning complete ====="
USERDATA_EOF
)

# --- Create droplet ---
echo -ne "Creating server... "

CREATE_PAYLOAD=$(jq -n \
    --arg name "$DROPLET_NAME" \
    --arg region "$REGION" \
    --arg size "$SIZE" \
    --arg image "ubuntu-22-04-x64" \
    --argjson ssh_keys "$SSH_KEY_IDS" \
    --arg userdata "$USERDATA" \
    '{
        name: $name,
        region: $region,
        size: $size,
        image: $image,
        ssh_keys: $ssh_keys,
        backups: true,
        monitoring: true,
        tags: ["healthflow", "sunbird-rc", "production"],
        user_data: $userdata
    }')

CREATE_RESP=$(curl -sS -X POST "$API/droplets" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREATE_PAYLOAD")

DROPLET_ID=$(echo "$CREATE_RESP" | jq -r '.droplet.id')

if [ -z "$DROPLET_ID" ] || [ "$DROPLET_ID" = "null" ]; then
    echo -e "${RED}FAILED${NC}"
    echo "$CREATE_RESP" | jq -r '.message // .id // .'
    exit 1
fi
echo -e "${GREEN}OK${NC} (ID: $DROPLET_ID)"

# --- Wait for active ---
echo -n "Waiting for server to start "
STATUS="new"
ATTEMPTS=0
while [ "$STATUS" != "active" ] && [ $ATTEMPTS -lt 60 ]; do
    sleep 10
    STATUS_RESP=$(curl -sS -X GET "$API/droplets/$DROPLET_ID" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json")
    STATUS=$(echo "$STATUS_RESP" | jq -r '.droplet.status')
    ATTEMPTS=$((ATTEMPTS + 1))
    echo -n "."
done
echo ""

if [ "$STATUS" != "active" ]; then
    echo -e "${RED}Server did not start within 10 minutes.${NC}"
    exit 1
fi

DROPLET_IP=$(curl -sS -X GET "$API/droplets/$DROPLET_ID" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" | \
    jq -r '.droplet.networks.v4[] | select(.type == "public") | .ip_address' | head -1)

echo -e "Server IP: ${GREEN}$DROPLET_IP${NC}"

# --- Create firewall ---
echo -ne "Creating firewall... "
FW_RESP=$(curl -sS -X POST "$API/firewalls" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"healthflow-firewall\",
        \"droplet_ids\": [$DROPLET_ID],
        \"inbound_rules\": [
            {\"protocol\":\"tcp\",\"ports\":\"22\",\"sources\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"tcp\",\"ports\":\"80\",\"sources\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"tcp\",\"ports\":\"443\",\"sources\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"tcp\",\"ports\":\"8080\",\"sources\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"tcp\",\"ports\":\"8081\",\"sources\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}}
        ],
        \"outbound_rules\": [
            {\"protocol\":\"tcp\",\"ports\":\"1-65535\",\"destinations\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"udp\",\"ports\":\"1-65535\",\"destinations\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}},
            {\"protocol\":\"icmp\",\"destinations\":{\"addresses\":[\"0.0.0.0/0\",\"::/0\"]}}
        ]
    }")
echo -e "${GREEN}OK${NC}"

# --- Create volume ---
echo -ne "Creating 100GB storage volume... "
VOL_RESP=$(curl -sS -X POST "$API/volumes" \
    -H "Authorization: Bearer $DO_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"size_gigabytes\": 100,
        \"name\": \"healthflow-data\",
        \"region\": \"$REGION\",
        \"filesystem_type\": \"ext4\",
        \"description\": \"HealthFlow persistent data\"
    }")
VOL_ID=$(echo "$VOL_RESP" | jq -r '.volume.id // empty')
if [ -n "$VOL_ID" ]; then
    curl -sS -X POST "$API/volumes/$VOL_ID/actions" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"attach\",\"droplet_id\":$DROPLET_ID,\"region\":\"$REGION\"}" > /dev/null 2>&1
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}Skipped (non-critical)${NC}"
fi

# --- Done! --------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              DEPLOYMENT SUCCESSFUL!                     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Server IP:     ${GREEN}$DROPLET_IP${NC}"
echo -e "  Droplet ID:    $DROPLET_ID"
echo ""
echo -e "  ${YELLOW}The server is now installing software (5-10 minutes).${NC}"
echo ""
echo "  When ready, your services will be at:"
echo -e "    Registry API:  ${GREEN}http://$DROPLET_IP:8081${NC}"
echo -e "    Keycloak:      ${GREEN}http://$DROPLET_IP:8080${NC}"
echo ""
echo "  To check progress:"
echo -e "    ${BLUE}ssh root@$DROPLET_IP 'tail -f /var/log/cloud-init-output.log'${NC}"
echo ""
echo "  To see your auto-generated passwords:"
echo -e "    ${BLUE}ssh root@$DROPLET_IP 'cat /opt/healthflow/credentials.txt'${NC}"
echo ""
echo "  To check if services are running:"
echo -e "    ${BLUE}ssh root@$DROPLET_IP 'docker ps'${NC}"
echo ""
echo -e "${GREEN}Done! Bookmark this IP: $DROPLET_IP${NC}"
echo ""
