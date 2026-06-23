# HealthFlow Registry & Credentials Platform

**Version:** 2.0  
**Last Updated:** December 2025

[![Build Status](https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/actions/workflows/maven.yml/badge.svg)](https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/actions/workflows/maven.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Introduction

HealthFlow Registry & Credentials (HealthFlow RC) is an enterprise-grade platform for building and managing electronic healthcare registries and verifiable credentials. Built on the open-source Sunbird RC framework, HealthFlow RC provides healthcare organizations with the tools to create trusted, interoperable, and privacy-preserving digital registries.

This repository contains the core source code, deployment configurations, and documentation for the HealthFlow RC platform.

---

## Platform Capabilities

HealthFlow RC provides a comprehensive set of capabilities for healthcare registry management:

| Capability | Description |
|------------|-------------|
| **Schema-Driven Registries** | Define custom data models for any healthcare entity using JSON Schema, with automatic API generation |
| **Verifiable Credentials** | Issue W3C-compliant digital credentials with cryptographic signatures for tamper-proof verification |
| **Identity Management** | Integrated authentication and authorization with support for SSO, SAML, and OpenID Connect |
| **Attestation Workflows** | Configurable approval processes for credential verification and data validation |
| **Privacy Controls** | Field-level encryption, consent management, and data masking for sensitive information |
| **Discovery Services** | Searchable public registries with configurable visibility controls |
| **Bulk Operations** | CSV-based bulk issuance and updates for large-scale credential management |
| **Multi-Database Support** | Flexible storage options including PostgreSQL, MySQL, and Cassandra |

---

## Repository Structure

This repository is organized into the following directories:

| Directory | Description |
|-----------|-------------|
| `docs/` | Comprehensive documentation for the platform |
| `docker/` | Docker Compose configurations for development and production |
| `terraform/` | Terraform scripts for deploying on Digital Ocean |
| `java/` | Core Java source code for the platform services |
| `services/` | Service-specific configurations and scripts |
| `scripts/` | Deployment and management scripts |
| `.github/` | GitHub Actions workflows for CI/CD |

---

## Getting Started

To deploy HealthFlow RC, follow the instructions in the [Docker Compose Deployment Guide](./docs/guides/docker-compose-deployment.md).

### Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core.git
   cd Healthflow-HCP-rc-core
   ```

2. **Configure environment variables:**
   ```bash
   cp docker/.env.example docker/.env
   nano docker/.env
   ```

3. **Start the services:**
   ```bash
   docker-compose -f docker/docker-compose.production.yml up -d
   ```

---

## Documentation

Comprehensive documentation is available in the `docs/` directory.

- [**Introduction**](./docs/README.md) - Platform overview and capabilities
- [**Technical Architecture**](./docs/learn/technical-overview.md) - Detailed architecture and component descriptions
- [**API Reference**](./docs/api-reference/README.md) - Complete API documentation
- [**Deployment Guides**](./docs/guides/README.md) - Docker Compose and cloud deployment guides
- [**User Guides**](./docs/use/README.md) - Guides for administrators and developers

---

## Contributing

We welcome contributions to the HealthFlow RC platform. Please refer to the [Contribution Guide](./docs/CONTRIBUTING.md) for more information.

---

## Support

For technical support and questions about HealthFlow RC:

- **Documentation:** [https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/tree/main/docs](https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/tree/main/docs)
- **Issues:** [https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/issues](https://github.com/HealthFlow-Medical-HCX/Healthflow-HCP-rc-core/issues)
- **Email:** support@healthflow.tech

---

## License

HealthFlow RC is built on Sunbird RC, which is open-sourced under the MIT License. You are free to use, modify, and distribute this software in accordance with the license terms.

**Copyright © 2025 HealthFlow Medical. All rights reserved.**
