#!/bin/bash
# =============================================================================
# HealthFlow HCP Registry - On-droplet provisioning
# =============================================================================
# This script runs ON a freshly created droplet (via cloud-config user_data).
# It does NOT clone this repository: the deployment tooling bakes the required
# files (docker-compose.production.yml + init-db.sql) into the droplet before
# running this script, so private-repo access is never required.
#
# Expects these files to already exist on the droplet:
#   /opt/healthflow/docker/docker-compose.production.yml
#   /opt/healthflow/docker/scripts/init-db.sql
# =============================================================================
set -x
exec > /var/log/healthflow-provision.log 2>&1
echo "=== HealthFlow provisioning started: $(date -u) ==="
export DEBIAN_FRONTEND=noninteractive

# --- Docker install (official repo) ------------------------------------------
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

# --- Kernel tuning required by Elasticsearch ---------------------------------
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elasticsearch.conf

# --- Generate .env (only the vars docker-compose.production.yml consumes) -----
cd /opt/healthflow/docker
if [ ! -f .env ]; then
    DB_PASS=$(openssl rand -hex 16)
    KC_PASS=$(openssl rand -hex 16)
    VT_TOKEN=$(openssl rand -hex 16)
    cat > .env <<EOF
DB_USER=healthflow
DB_PASSWORD=$DB_PASS
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$KC_PASS
VAULT_TOKEN=$VT_TOKEN
EOF
    cat > /opt/healthflow/credentials.txt <<EOF
=== HealthFlow HCP Registry credentials ($(date -u)) ===
Postgres / DB user:       healthflow
DB_PASSWORD:              $DB_PASS
Keycloak admin user:      admin
KEYCLOAK_ADMIN_PASSWORD:  $KC_PASS
VAULT_TOKEN:              $VT_TOKEN
EOF
    chmod 600 /opt/healthflow/credentials.txt
fi

# --- Bring up the stack -------------------------------------------------------
docker compose -f docker-compose.production.yml pull
docker compose -f docker-compose.production.yml up -d

echo "=== HealthFlow provisioning complete: $(date -u) ==="
docker compose -f docker-compose.production.yml ps
touch /opt/healthflow/PROVISION_DONE
