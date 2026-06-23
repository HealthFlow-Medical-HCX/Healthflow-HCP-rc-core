# =============================================================================
# HealthFlow Sunbird RC v2 - Digital Ocean Infrastructure
# Egyptian Healthcare Registry Platform
# =============================================================================

terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# =============================================================================
# Provider Configuration
# =============================================================================

provider "digitalocean" {
  token = var.do_token
}

# =============================================================================
# Variables
# =============================================================================

variable "do_token" {
  description = "Digital Ocean API Token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "Name of the SSH key in Digital Ocean"
  type        = string
  default     = "AmrSurface"
}

variable "region" {
  description = "Digital Ocean region"
  type        = string
  default     = "fra1"  # Frankfurt - closest to Egypt
}

variable "droplet_size" {
  description = "Droplet size for Sunbird RC"
  type        = string
  default     = "s-4vcpu-8gb"  # 4 vCPU, 8GB RAM - recommended for Sunbird RC
}

variable "domain_name" {
  description = "Domain name for the registry"
  type        = string
  default     = "sunbird.healthflow.eg"
}

variable "environment" {
  description = "Environment (production, staging, development)"
  type        = string
  default     = "production"
}

# =============================================================================
# Data Sources
# =============================================================================

data "digitalocean_ssh_key" "main" {
  name = var.ssh_key_name
}

# =============================================================================
# Droplet - Sunbird RC Server
# =============================================================================

resource "digitalocean_droplet" "sunbird_rc" {
  name     = "healthflow-sunbird-rc-${var.environment}"
  size     = var.droplet_size
  image    = "ubuntu-22-04-x64"
  region   = var.region
  ssh_keys = [data.digitalocean_ssh_key.main.id]
  
  tags = [
    "healthflow",
    "sunbird-rc",
    var.environment,
    "managed-by-terraform"
  ]

  # Enable monitoring and backups
  monitoring = true
  backups    = true

  # User data script for initial setup.
  # The compose file, DB init script and provisioning script are baked in as
  # base64 so the droplet never needs to clone this (private) repository.
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    environment   = var.environment
    compose_b64   = base64encode(file("${path.module}/../docker/docker-compose.production.yml"))
    initdb_b64    = base64encode(file("${path.module}/../docker/scripts/init-db.sql"))
    provision_b64 = base64encode(file("${path.module}/../scripts/provision-droplet.sh"))
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Firewall Configuration
# =============================================================================

resource "digitalocean_firewall" "sunbird_rc" {
  name = "healthflow-sunbird-rc-firewall"

  droplet_ids = [digitalocean_droplet.sunbird_rc.id]

  # SSH Access
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTP
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Registry API (internal - consider restricting in production)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8081"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Keycloak
  inbound_rule {
    protocol         = "tcp"
    port_range       = "8080"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# =============================================================================
# Reserved IP (Floating IP)
# =============================================================================

resource "digitalocean_reserved_ip" "sunbird_rc" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "sunbird_rc" {
  ip_address = digitalocean_reserved_ip.sunbird_rc.ip_address
  droplet_id = digitalocean_droplet.sunbird_rc.id
}

# =============================================================================
# Volume for Persistent Data
# =============================================================================

resource "digitalocean_volume" "sunbird_data" {
  region                  = var.region
  name                    = "healthflow-sunbird-data-${var.environment}"
  size                    = 100  # 100GB for database and file storage
  initial_filesystem_type = "ext4"
  description             = "Persistent storage for HealthFlow Sunbird RC"
  
  tags = [
    "healthflow",
    "sunbird-rc",
    var.environment
  ]
}

resource "digitalocean_volume_attachment" "sunbird_data" {
  droplet_id = digitalocean_droplet.sunbird_rc.id
  volume_id  = digitalocean_volume.sunbird_data.id
}

# =============================================================================
# DNS Records (if domain is managed in DO)
# =============================================================================

# Uncomment if you want to manage DNS in Digital Ocean
# resource "digitalocean_domain" "healthflow" {
#   name = var.domain_name
# }

# resource "digitalocean_record" "sunbird" {
#   domain = digitalocean_domain.healthflow.id
#   type   = "A"
#   name   = "sunbird"
#   value  = digitalocean_reserved_ip.sunbird_rc.ip_address
#   ttl    = 300
# }

# resource "digitalocean_record" "api" {
#   domain = digitalocean_domain.healthflow.id
#   type   = "A"
#   name   = "api"
#   value  = digitalocean_reserved_ip.sunbird_rc.ip_address
#   ttl    = 300
# }

# =============================================================================
# Outputs
# =============================================================================

output "droplet_ip" {
  description = "Public IP address of the Sunbird RC droplet"
  value       = digitalocean_droplet.sunbird_rc.ipv4_address
}

output "reserved_ip" {
  description = "Reserved (floating) IP address"
  value       = digitalocean_reserved_ip.sunbird_rc.ip_address
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.sunbird_rc.id
}

output "volume_id" {
  description = "Volume ID for persistent storage"
  value       = digitalocean_volume.sunbird_data.id
}

output "ssh_command" {
  description = "SSH command to connect to the droplet"
  value       = "ssh root@${digitalocean_reserved_ip.sunbird_rc.ip_address}"
}

output "registry_url" {
  description = "Registry API URL"
  value       = "http://${digitalocean_reserved_ip.sunbird_rc.ip_address}:8081"
}

output "keycloak_url" {
  description = "Keycloak Admin URL"
  value       = "http://${digitalocean_reserved_ip.sunbird_rc.ip_address}:8080"
}
