# Docker Compose Deployment

**Version:** 2.0  
**Last Updated:** December 2025

---

## Overview

This guide provides instructions for deploying HealthFlow RC on a single server using Docker Compose. This is the recommended deployment method for development, testing, and small-scale production environments.

---

## Prerequisites

- A Linux server with Docker and Docker Compose installed.
- Minimum 8GB RAM and 4 CPU cores.
- A domain name pointed to the server's IP address.

---

## Deployment Steps

### 1. Clone the Repository

Clone the HealthFlow RC repository from GitHub:

```bash
git clone https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core.git
cd Healthflow-HCP-rc-core
```

### 2. Configure Environment Variables

Create a `.env` file in the `docker` directory and configure the required environment variables. You can use the `.env.example` file as a template.

```bash
cp docker/.env.example docker/.env
nano docker/.env
```

**Key Variables to Configure:**

| Variable | Description |
|----------|-------------|
| `DOMAIN_NAME` | Your domain name (e.g., `healthflow.tech`) |
| `POSTGRES_PASSWORD` | Password for the PostgreSQL database |
| `KEYCLOAK_ADMIN_PASSWORD` | Password for the Keycloak admin user |
| `VAULT_TOKEN` | Token for HashiCorp Vault |

### 3. Start the Services

Use Docker Compose to start all the services in detached mode:

```bash
docker-compose -f docker/docker-compose.production.yml up -d
```

This will pull the required Docker images and start all the containers. The initial startup may take several minutes.

### 4. Configure SSL Certificates

Once the services are running, configure SSL certificates using Let's Encrypt. The Nginx container is pre-configured to handle the certificate challenge.

```bash
docker-compose -f docker/docker-compose.production.yml exec nginx certbot --nginx -d registry.yourdomain.com -d keycloak.yourdomain.com
```

Replace `yourdomain.com` with your actual domain name.

### 5. Verify the Deployment

After the SSL certificates are installed, you should be able to access the following endpoints:

- **Registry API:** `https://registry.yourdomain.com/health`
- **Keycloak Admin:** `https://keycloak.yourdomain.com/admin`

---

## Managing the Deployment

### View Service Logs

To view the logs for a specific service:

```bash
docker-compose -f docker/docker-compose.production.yml logs -f <service_name>
```

Example: `docker-compose logs -f registry`

### Stop the Services

To stop all services:

```bash
docker-compose -f docker/docker-compose.production.yml down
```

### Restart a Service

To restart a specific service:

```bash
docker-compose -f docker/docker-compose.production.yml restart <service_name>
```

---

## Next Steps

- [Authentication Configuration](./authentication-configuration.md) - Configure Keycloak and SSO.
- [Schema Configuration](./schema-configuration.md) - Define your registry schemas.

---

**Copyright © 2025 HealthFlow Medical. All rights reserved.**
