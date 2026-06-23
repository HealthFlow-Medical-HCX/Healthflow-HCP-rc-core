#!/bin/bash

# =============================================================================
# HealthFlow Sunbird RC v2 - DigitalOcean Direct API Deployment
# Creates and provisions a droplet using the DO API (no Terraform needed)
# =============================================================================
# Usage:
#   export DO_API_TOKEN="dop_v1_xxxxxxxxxxxxxxxx"
#   ./deploy-digitalocean-api.sh [create|destroy|status|ssh]
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
DROPLET_NAME="${DROPLET_NAME:-healthflow-sunbird-rc-production}"
REGION="${REGION:-fra1}"                    # Frankfurt - closest to Egypt
SIZE="${SIZE:-s-4vcpu-8gb}"                 # 4 vCPU, 8GB RAM
IMAGE="${IMAGE:-ubuntu-22-04-x64}"
VOLUME_SIZE="${VOLUME_SIZE:-100}"            # GB for persistent storage
SSH_KEY_NAME="${SSH_KEY_NAME:-AmrSurface}"
TAGS="healthflow,sunbird-rc,production,api-deployed"

# --- API Base -----------------------------------------------------------------
API="https://api.digitalocean.com/v2"

# --- Colors -------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_header()  { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# --- Helpers ------------------------------------------------------------------
api_get() {
    curl -sS -X GET "$API/$1" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json"
}

api_post() {
    curl -sS -X POST "$API/$1" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$2"
}

api_delete() {
    curl -sS -X DELETE "$API/$1" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json"
}

retry_push() {
    local cmd="$1"
    local delays=(2 4 8 16)
    for delay in "${delays[@]}"; do
        if eval "$cmd"; then return 0; fi
        log_warn "Retrying in ${delay}s..."
        sleep "$delay"
    done
    log_error "All retries failed"
    return 1
}

check_token() {
    if [ -z "${DO_API_TOKEN:-}" ]; then
        log_error "DO_API_TOKEN is not set."
        echo ""
        echo "Please export your DigitalOcean API token:"
        echo "  export DO_API_TOKEN=\"dop_v1_xxxxxxxxxxxxxxxx\""
        echo ""
        echo "Get one at: https://cloud.digitalocean.com/account/api/tokens"
        exit 1
    fi

    # Verify token works
    local resp
    resp=$(api_get "account")
    if echo "$resp" | jq -e '.account.email' > /dev/null 2>&1; then
        local email
        email=$(echo "$resp" | jq -r '.account.email')
        log_success "Authenticated as: $email"
    else
        log_error "Invalid API token. Response: $resp"
        exit 1
    fi
}

# --- Cloud-init user data ----------------------------------------------------
# Builds a self-contained #cloud-config. Rather than cloning this (private)
# repository on the droplet, it bakes the runtime files in directly:
#   - docker/docker-compose.production.yml
#   - docker/scripts/init-db.sql
#   - scripts/provision-droplet.sh
# All container images are pulled from public registries, so the droplet needs
# no GitHub access at all.
generate_userdata() {
    local root compose_b64 initdb_b64 provision_b64
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    local compose_file="$root/docker/docker-compose.production.yml"
    local initdb_file="$root/docker/scripts/init-db.sql"
    local provision_file="$root/scripts/provision-droplet.sh"

    for f in "$compose_file" "$initdb_file" "$provision_file"; do
        if [ ! -f "$f" ]; then
            log_error "Required file not found: $f" >&2
            exit 1
        fi
    done

    # base64 without newlines (portable across GNU/BSD base64)
    compose_b64=$(base64 < "$compose_file" | tr -d '\n')
    initdb_b64=$(base64 < "$initdb_file" | tr -d '\n')
    provision_b64=$(base64 < "$provision_file" | tr -d '\n')

    cat <<CLOUD_CFG
#cloud-config
write_files:
  - path: /opt/healthflow/docker/docker-compose.production.yml
    encoding: b64
    content: ${compose_b64}
  - path: /opt/healthflow/docker/scripts/init-db.sql
    encoding: b64
    content: ${initdb_b64}
  - path: /opt/healthflow/provision-droplet.sh
    encoding: b64
    permissions: '0755'
    content: ${provision_b64}
runcmd:
  - [ bash, /opt/healthflow/provision-droplet.sh ]
CLOUD_CFG
}

# --- Get SSH key ID -----------------------------------------------------------
get_ssh_key_id() {
    local resp
    resp=$(api_get "account/keys?per_page=200")
    local key_id
    key_id=$(echo "$resp" | jq -r --arg name "$SSH_KEY_NAME" '.ssh_keys[] | select(.name == $name) | .id')

    if [ -z "$key_id" ] || [ "$key_id" = "null" ]; then
        log_warn "SSH key '$SSH_KEY_NAME' not found in your DO account."
        log_info "Available SSH keys:"
        echo "$resp" | jq -r '.ssh_keys[] | "  - \(.name) (id: \(.id))"'
        echo ""
        log_info "Proceeding without SSH key (root password will be emailed)."
        echo ""
        return 1
    fi

    echo "$key_id"
}

# --- Create Droplet -----------------------------------------------------------
create_droplet() {
    log_header "Creating DigitalOcean Droplet"

    # Check if droplet already exists
    local existing
    existing=$(api_get "droplets?tag_name=healthflow&per_page=200")
    local existing_id
    existing_id=$(echo "$existing" | jq -r --arg name "$DROPLET_NAME" '.droplets[] | select(.name == $name) | .id')

    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        local existing_ip
        existing_ip=$(echo "$existing" | jq -r --arg name "$DROPLET_NAME" '.droplets[] | select(.name == $name) | .networks.v4[] | select(.type == "public") | .ip_address' | head -1)
        log_warn "Droplet '$DROPLET_NAME' already exists (ID: $existing_id, IP: $existing_ip)"
        echo ""
        read -p "Do you want to skip creation and use the existing droplet? (y/N): " skip
        if [[ "$skip" =~ ^[Yy]$ ]]; then
            DROPLET_ID="$existing_id"
            DROPLET_IP="$existing_ip"
            return 0
        fi
        log_error "Please destroy the existing droplet first or use a different name."
        exit 1
    fi

    # Get SSH key
    local ssh_key_id
    ssh_key_id=$(get_ssh_key_id) || ssh_key_id=""

    # Build SSH keys array
    local ssh_keys_json="[]"
    if [ -n "$ssh_key_id" ]; then
        ssh_keys_json="[$ssh_key_id]"
    fi

    # Generate user data
    local userdata
    userdata=$(generate_userdata)

    # Prepare tags
    IFS=',' read -ra TAG_ARRAY <<< "$TAGS"
    local tags_json
    tags_json=$(printf '%s\n' "${TAG_ARRAY[@]}" | jq -R . | jq -s .)

    # Create the droplet
    log_info "Creating droplet: $DROPLET_NAME"
    log_info "  Region: $REGION"
    log_info "  Size:   $SIZE"
    log_info "  Image:  $IMAGE"

    local create_payload
    create_payload=$(jq -n \
        --arg name "$DROPLET_NAME" \
        --arg region "$REGION" \
        --arg size "$SIZE" \
        --arg image "$IMAGE" \
        --argjson ssh_keys "$ssh_keys_json" \
        --argjson tags "$tags_json" \
        --arg userdata "$userdata" \
        '{
            name: $name,
            region: $region,
            size: $size,
            image: $image,
            ssh_keys: $ssh_keys,
            backups: true,
            monitoring: true,
            tags: $tags,
            user_data: $userdata
        }')

    local create_resp
    create_resp=$(api_post "droplets" "$create_payload")

    DROPLET_ID=$(echo "$create_resp" | jq -r '.droplet.id')

    if [ -z "$DROPLET_ID" ] || [ "$DROPLET_ID" = "null" ]; then
        log_error "Failed to create droplet."
        echo "$create_resp" | jq .
        exit 1
    fi

    log_success "Droplet created (ID: $DROPLET_ID)"

    # Wait for droplet to become active
    log_info "Waiting for droplet to become active..."
    local status="new"
    local attempts=0
    while [ "$status" != "active" ] && [ $attempts -lt 60 ]; do
        sleep 10
        local status_resp
        status_resp=$(api_get "droplets/$DROPLET_ID")
        status=$(echo "$status_resp" | jq -r '.droplet.status')
        attempts=$((attempts + 1))
        echo -n "."
    done
    echo ""

    if [ "$status" != "active" ]; then
        log_error "Droplet did not become active within 10 minutes."
        exit 1
    fi

    # Get public IP
    local ip_resp
    ip_resp=$(api_get "droplets/$DROPLET_ID")
    DROPLET_IP=$(echo "$ip_resp" | jq -r '.droplet.networks.v4[] | select(.type == "public") | .ip_address' | head -1)

    log_success "Droplet is active!"
    log_success "Public IP: $DROPLET_IP"
}

# --- Create Firewall ----------------------------------------------------------
create_firewall() {
    log_header "Creating Firewall Rules"

    local fw_name="healthflow-api-firewall"

    # Check if firewall already exists
    local existing_fw
    existing_fw=$(api_get "firewalls?per_page=200")
    local existing_fw_id
    existing_fw_id=$(echo "$existing_fw" | jq -r --arg name "$fw_name" '.firewalls[] | select(.name == $name) | .id')

    if [ -n "$existing_fw_id" ] && [ "$existing_fw_id" != "null" ]; then
        log_info "Firewall '$fw_name' already exists. Updating droplet assignment..."
        # Add droplet to existing firewall
        api_post "firewalls/$existing_fw_id/droplets" "{\"droplet_ids\": [$DROPLET_ID]}" > /dev/null
        log_success "Droplet added to existing firewall"
        return 0
    fi

    local fw_payload
    fw_payload=$(cat << FWEOF
{
    "name": "$fw_name",
    "droplet_ids": [$DROPLET_ID],
    "inbound_rules": [
        {"protocol": "tcp", "ports": "22",   "sources": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "tcp", "ports": "80",   "sources": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "tcp", "ports": "443",  "sources": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "tcp", "ports": "8080", "sources": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "tcp", "ports": "8081", "sources": {"addresses": ["0.0.0.0/0", "::/0"]}}
    ],
    "outbound_rules": [
        {"protocol": "tcp",  "ports": "1-65535", "destinations": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "udp",  "ports": "1-65535", "destinations": {"addresses": ["0.0.0.0/0", "::/0"]}},
        {"protocol": "icmp", "destinations": {"addresses": ["0.0.0.0/0", "::/0"]}}
    ]
}
FWEOF
    )

    local fw_resp
    fw_resp=$(api_post "firewalls" "$fw_payload")
    local fw_id
    fw_id=$(echo "$fw_resp" | jq -r '.firewall.id')

    if [ -n "$fw_id" ] && [ "$fw_id" != "null" ]; then
        log_success "Firewall created (ID: $fw_id)"
    else
        log_warn "Firewall creation returned unexpected response (UFW on droplet is still active)."
    fi
}

# --- Create Volume ------------------------------------------------------------
create_volume() {
    log_header "Creating Persistent Storage Volume"

    local vol_name="healthflow-data-production"

    # Check existing
    local existing_vol
    existing_vol=$(api_get "volumes?name=$vol_name&region=$REGION")
    local existing_vol_id
    existing_vol_id=$(echo "$existing_vol" | jq -r '.volumes[0].id // empty')

    if [ -n "$existing_vol_id" ]; then
        log_info "Volume '$vol_name' already exists (ID: $existing_vol_id). Attaching..."
        api_post "volumes/$existing_vol_id/actions" \
            "{\"type\": \"attach\", \"droplet_id\": $DROPLET_ID, \"region\": \"$REGION\"}" > /dev/null 2>&1 || true
        log_success "Volume attached"
        return 0
    fi

    local vol_payload
    vol_payload=$(jq -n \
        --arg name "$vol_name" \
        --arg region "$REGION" \
        --argjson size "$VOLUME_SIZE" \
        '{
            size_gigabytes: $size,
            name: $name,
            region: $region,
            filesystem_type: "ext4",
            description: "HealthFlow Sunbird RC persistent data"
        }')

    local vol_resp
    vol_resp=$(api_post "volumes" "$vol_payload")
    local vol_id
    vol_id=$(echo "$vol_resp" | jq -r '.volume.id')

    if [ -n "$vol_id" ] && [ "$vol_id" != "null" ]; then
        log_success "Volume created (ID: $vol_id, Size: ${VOLUME_SIZE}GB)"

        # Attach to droplet
        log_info "Attaching volume to droplet..."
        api_post "volumes/$vol_id/actions" \
            "{\"type\": \"attach\", \"droplet_id\": $DROPLET_ID, \"region\": \"$REGION\"}" > /dev/null
        log_success "Volume attached"
    else
        log_warn "Volume creation failed (non-critical - local storage will be used)."
    fi
}

# --- Create Reserved IP ------------------------------------------------------
create_reserved_ip() {
    log_header "Creating Reserved (Floating) IP"

    local rip_payload="{\"region\": \"$REGION\"}"
    local rip_resp
    rip_resp=$(api_post "reserved_ips" "$rip_payload")
    local reserved_ip
    reserved_ip=$(echo "$rip_resp" | jq -r '.reserved_ip.ip // empty')

    if [ -n "$reserved_ip" ]; then
        # Assign to droplet
        api_post "reserved_ips/$reserved_ip/actions" \
            "{\"type\": \"assign\", \"droplet_id\": $DROPLET_ID}" > /dev/null 2>&1
        log_success "Reserved IP: $reserved_ip (assigned to droplet)"
        RESERVED_IP="$reserved_ip"
    else
        log_warn "Could not create reserved IP. Using droplet IP directly."
        RESERVED_IP="$DROPLET_IP"
    fi
}

# --- Show Status --------------------------------------------------------------
show_status() {
    log_header "HealthFlow Droplet Status"

    check_token

    local resp
    resp=$(api_get "droplets?tag_name=healthflow&per_page=200")
    local count
    count=$(echo "$resp" | jq '.droplets | length')

    if [ "$count" = "0" ]; then
        log_info "No HealthFlow droplets found."
        return
    fi

    echo "$resp" | jq -r '.droplets[] | "Name:   \(.name)\nID:     \(.id)\nStatus: \(.status)\nIP:     \(.networks.v4[] | select(.type == "public") | .ip_address)\nRegion: \(.region.slug)\nSize:   \(.size.slug)\nCreated: \(.created_at)\n---"'
}

# --- Destroy Droplet ----------------------------------------------------------
destroy_droplet() {
    log_header "Destroying HealthFlow Droplet"

    check_token

    local resp
    resp=$(api_get "droplets?tag_name=healthflow&per_page=200")
    local droplets
    droplets=$(echo "$resp" | jq -r '.droplets[] | "\(.id) \(.name) \(.networks.v4[] | select(.type == "public") | .ip_address)"')

    if [ -z "$droplets" ]; then
        log_info "No HealthFlow droplets found."
        return
    fi

    echo "Found droplets:"
    echo "$droplets" | while read -r id name ip; do
        echo "  ID: $id | Name: $name | IP: $ip"
    done
    echo ""

    read -p "Are you sure you want to destroy ALL HealthFlow droplets? (type 'yes' to confirm): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled."
        return
    fi

    echo "$droplets" | while read -r id name ip; do
        log_info "Destroying droplet $name ($id)..."
        api_delete "droplets/$id"
        log_success "Droplet $name destroyed."
    done
}

# --- Print SSH Command --------------------------------------------------------
ssh_command() {
    check_token

    local resp
    resp=$(api_get "droplets?tag_name=healthflow&per_page=200")
    local ip
    ip=$(echo "$resp" | jq -r '.droplets[0].networks.v4[] | select(.type == "public") | .ip_address' 2>/dev/null | head -1)

    if [ -n "$ip" ] && [ "$ip" != "null" ]; then
        echo ""
        echo "SSH into your droplet:"
        echo "  ssh root@$ip"
        echo "  ssh healthflow@$ip"
        echo ""
        echo "Check provisioning logs:"
        echo "  ssh root@$ip 'tail -f /var/log/cloud-init-output.log'"
        echo ""
        echo "Check services:"
        echo "  ssh root@$ip 'docker ps'"
        echo ""
        echo "View generated credentials:"
        echo "  ssh root@$ip 'cat /opt/healthflow/credentials.txt'"
        echo ""
        echo "Service URLs:"
        echo "  Registry API:  http://$ip:8081"
        echo "  Keycloak:      http://$ip:8080"
        echo ""
    else
        log_error "No HealthFlow droplet found."
    fi
}

# --- Full Deploy --------------------------------------------------------------
full_deploy() {
    log_header "HealthFlow DigitalOcean API Deployment"
    echo "This will create:"
    echo "  - 1x Droplet ($SIZE in $REGION)"
    echo "  - 1x ${VOLUME_SIZE}GB Storage Volume"
    echo "  - 1x Firewall (SSH, HTTP, HTTPS, 8080, 8081)"
    echo "  - 1x Reserved IP"
    echo "  - Auto-provisioning: Docker, app clone, services start"
    echo ""
    read -p "Continue? (y/N): " proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        log_info "Cancelled."
        exit 0
    fi

    check_token
    create_droplet
    create_firewall
    create_volume
    create_reserved_ip

    log_header "Deployment Complete!"
    echo ""
    echo "  Droplet ID:    $DROPLET_ID"
    echo "  Droplet IP:    $DROPLET_IP"
    echo "  Reserved IP:   ${RESERVED_IP:-N/A}"
    echo ""
    echo "  The droplet is now provisioning (installing Docker, cloning repo,"
    echo "  starting services). This takes ~5-10 minutes."
    echo ""
    echo "  Monitor progress:"
    echo "    ssh root@$DROPLET_IP 'tail -f /var/log/cloud-init-output.log'"
    echo ""
    echo "  Once ready, your services will be at:"
    echo "    Registry API:  http://${RESERVED_IP:-$DROPLET_IP}:8081"
    echo "    Keycloak:      http://${RESERVED_IP:-$DROPLET_IP}:8080"
    echo ""
    echo "  View auto-generated credentials:"
    echo "    ssh root@$DROPLET_IP 'cat /opt/healthflow/credentials.txt'"
    echo ""
    log_success "Done! Your HealthFlow platform is deploying."
}

# --- Main ---------------------------------------------------------------------
ACTION="${1:-create}"

case "$ACTION" in
    create|deploy)
        full_deploy
        ;;
    status)
        check_token
        show_status
        ;;
    destroy)
        destroy_droplet
        ;;
    ssh|info)
        ssh_command
        ;;
    *)
        echo "Usage: $0 [create|destroy|status|ssh]"
        echo ""
        echo "Commands:"
        echo "  create   - Create droplet and deploy (default)"
        echo "  status   - Show HealthFlow droplet status"
        echo "  destroy  - Destroy all HealthFlow droplets"
        echo "  ssh      - Show SSH and service connection info"
        echo ""
        echo "Environment variables:"
        echo "  DO_API_TOKEN   - DigitalOcean API token (required)"
        echo "  DROPLET_NAME   - Droplet name (default: healthflow-sunbird-rc-production)"
        echo "  REGION         - Region (default: fra1)"
        echo "  SIZE           - Droplet size (default: s-4vcpu-8gb)"
        echo "  VOLUME_SIZE    - Storage volume in GB (default: 100)"
        echo "  SSH_KEY_NAME   - DO SSH key name (default: AmrSurface)"
        ;;
esac
