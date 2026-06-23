# HealthFlow Sunbird RC v2 - Docker Deployment

Egyptian Healthcare Registry Platform built on Sunbird RC v2.

## Overview

This deployment package provides a complete, production-ready setup for HealthFlow's Sunbird RC v2 registry service, designed specifically for the Egyptian healthcare ecosystem.

### Features

- **Healthcare Professional Registry**: Doctors, Pharmacists, Nurses
- **Healthcare Facility Registry**: Hospitals, Clinics, Pharmacies
- **Medical License Management**: License issuance and verification
- **Verifiable Credentials**: W3C-compliant digital credentials
- **Cequens SMS Integration**: Egyptian SMS provider for OTP and notifications
- **Bulk Issuance**: Mass credential issuance for EMS data migration

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         NGINX (Load Balancer)                        │
│                    Ports: 80, 443 (SSL Termination)                  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│   Registry    │         │   Keycloak    │         │  Credentials  │
│   (8081)      │         │   (8080)      │         │   (3000)      │
└───────────────┘         └───────────────┘         └───────────────┘
        │                           │                           │
        └───────────────────────────┼───────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│  PostgreSQL   │         │ Elasticsearch │         │    Redis      │
│   (5432)      │         │   (9200)      │         │   (6379)      │
└───────────────┘         └───────────────┘         └───────────────┘
```

## Quick Start

### Prerequisites

- Docker Engine 24.0+
- Docker Compose v2.20+
- 8GB RAM minimum (16GB recommended)
- 50GB disk space

### 1. Clone Repository

```bash
git clone https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core.git
cd Healthflow-HCP-rc-core/docker
```

### 2. Configure Environment

```bash
cp .env.example .env
nano .env
```

**Critical variables to configure:**

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | Database password | `secure_password_123` |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password | `admin_password_456` |
| `VAULT_TOKEN` | Vault root token | `hvs.xxxxxxxxxxxxx` |
| `ENCRYPTION_KEY` | 32-character encryption key | `abcdefghijklmnopqrstuvwxyz123456` |
| `CEQUENS_ACCESS_TOKEN` | Cequens API token | `your_cequens_token` |

### 3. Deploy Services

```bash
# Using deployment script
../scripts/deploy.sh production deploy

# Or using Docker Compose directly
docker compose up -d
```

### 4. Verify Deployment

```bash
# Check service status
docker compose ps

# Run health checks
../scripts/deploy.sh production health

# View logs
docker compose logs -f registry
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Registry | 8081 | Main Sunbird RC API |
| Keycloak | 8080 | Identity & Access Management |
| Credentials | 3000 | Verifiable Credentials Service |
| Identity | 3332 | DID Management |
| Credential Schema | 3333 | Schema Management |
| Bulk Issuance | 8085 | Bulk Credential Issuance |
| Notification | 8765 | SMS/Email Notifications |
| Certificate API | 8078 | Certificate Generation |
| PostgreSQL | 5432 | Primary Database |
| Elasticsearch | 9200 | Search Engine |
| Redis | 6379 | Cache |
| Vault | 8200 | Key Management |
| MinIO | 9001 | File Storage |

## Configuration

### Schemas

Healthcare entity schemas are located in `./schemas/`:

- `Doctor.json` - Doctor registration schema
- `Pharmacist.json` - Pharmacist registration schema
- `Nurse.json` - Nurse registration schema
- `HealthcareFacility.json` - Facility registration schema
- `MedicalLicense.json` - License/certification schema

### Cequens SMS Integration

Configure Cequens SMS in `.env`:

```env
CEQUENS_ACCESS_TOKEN=your_bearer_token
CEQUENS_SENDER_ID=HealthFlow
CEQUENS_API_URL=https://apis.cequens.com/sms/v1
```

### SSL/TLS Configuration

For production, replace self-signed certificates:

```bash
# Using Let's Encrypt
certbot certonly --nginx -d sunbird.healthflow.eg

# Copy certificates
cp /etc/letsencrypt/live/sunbird.healthflow.eg/fullchain.pem configs/ssl/cert.pem
cp /etc/letsencrypt/live/sunbird.healthflow.eg/privkey.pem configs/ssl/key.pem
```

## Operations

### Start Services

```bash
docker compose up -d
```

### Stop Services

```bash
docker compose down
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f registry
```

### Backup

```bash
# Database backup
docker exec healthflow-db pg_dumpall -U healthflow > backup.sql

# Full backup using script
../scripts/deploy.sh production backup
```

### Restore

```bash
# Stop services
docker compose down

# Restore database
cat backup.sql | docker exec -i healthflow-db psql -U healthflow

# Start services
docker compose up -d
```

### Scale Services

```bash
# Scale registry service
docker compose up -d --scale registry=3
```

## API Examples

### Create Doctor Registration

```bash
curl -X POST http://localhost:8081/api/v1/Doctor \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "fullNameEn": "Ahmed Mohamed",
    "fullNameAr": "أحمد محمد",
    "nationalId": "29001011234567",
    "syndicateNumber": "EMS-2024-001234",
    "specialization": "Internal Medicine",
    "mobile": "+201234567890"
  }'
```

### Verify Credential

```bash
curl -X POST http://localhost:3000/credentials/verify \
  -H "Content-Type: application/json" \
  -d '{
    "credential": { ... }
  }'
```

### Bulk Issuance

```bash
curl -X POST http://localhost:8085/bulk/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@doctors.csv" \
  -F "schema=Doctor"
```

## Troubleshooting

### Common Issues

**Services not starting:**
```bash
# Check Docker resources
docker system df
docker system prune -a

# Check logs
docker compose logs --tail=100
```

**Database connection issues:**
```bash
# Check database health
docker exec healthflow-db pg_isready -U healthflow

# Check database logs
docker compose logs db
```

**Elasticsearch memory issues:**
```bash
# Increase vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Make permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

**Keycloak not starting:**
```bash
# Check if database is ready
docker compose logs keycloak

# Restart Keycloak
docker compose restart keycloak
```

### Health Checks

```bash
# Registry
curl http://localhost:8081/health

# Keycloak
curl http://localhost:8080/health/ready

# Elasticsearch
curl http://localhost:9200/_cluster/health

# Credentials
curl http://localhost:3000/health
```

## Security Considerations

1. **Change default passwords** in `.env` before deployment
2. **Use SSL/TLS** in production with valid certificates
3. **Configure firewall** to restrict access to internal services
4. **Enable audit logging** for compliance
5. **Regular backups** with off-site storage
6. **Keep images updated** for security patches

## Support

- **Documentation**: [Sunbird RC Docs](https://docs.sunbirdrc.dev/)
- **Issues**: [GitHub Issues](https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/issues)
- **Email**: support@healthflow.eg

## License

This project is licensed under the MIT License - see the LICENSE file for details.
