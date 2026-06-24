# HealthFlow HCP Registry — DigitalOcean Deployment Handoff

**Prepared for:** DevOps / Platform team
**Date:** 2026-06-24
**Environment:** Production (DigitalOcean, project **NDP**)
**Repo:** `HealthFlow-Medical-HCX/Healthflow-HCP-rc-core`
**Branch with all deploy changes:** `claude/eager-davinci-ecn4bw` (not yet merged to `main`)

---

## 1. Executive summary

The HealthFlow HCP (Health Care Provider) Registry — a Sunbird-RC v2 based stack —
has been provisioned on DigitalOcean under a new project called **NDP**. All
infrastructure (droplet, reserved IP, block volume, cloud firewall, DNS zone) is
created and grouped in the NDP project. The application is deployed via Docker
Compose (`docker/docker-compose.production.yml`) using a **self-contained
cloud-config** (no in-droplet git clone — see §5).

> ⚠️ **Verification status:** infrastructure is confirmed via the DO API. The
> running application stack itself has **NOT been independently verified** end to
> end, because it was deployed from a sandboxed environment whose egress is
> limited to ports 80/443 and cannot SSH (port 22) or reach the app ports
> (8080/8081). **First DevOps action = run the verification in §6 from a normal
> network.**

---

## 2. Architecture / services

Single droplet running the full stack via Docker Compose. Services and host ports:

| Service | Image | Host port | Purpose |
|---|---|---|---|
| registry | `ghcr.io/sunbird-rc/sunbird-rc-core:v2.0.0` | 8081 | Core registry API (HCP registry) |
| keycloak | `quay.io/keycloak/keycloak:22.0` | 8080 | AuthN/AuthZ (realm `healthflow`) |
| db | `postgres:14` | (internal) | Primary datastore (multiple DBs, see §5) |
| elasticsearch | `elasticsearch:7.17.13` | (internal) | Registry search index |
| redis | `redis:7-alpine` | (internal) | Cache |
| zookeeper / kafka | `confluentinc/cp-*:7.4.0` | (internal) | Async/eventing |
| vault | `hashicorp/vault:1.13.3` (dev mode) | 8200 | Key management |
| identity | `ghcr.io/sunbird-rc/sunbird-rc-identity-service:v2.0.0` | 3332 | DID/identity |
| credential-schema | `ghcr.io/sunbird-rc/sunbird-rc-credential-schema:v2.0.0` | 3333 | VC schemas |
| credentials | `ghcr.io/sunbird-rc/sunbird-rc-credentials-service:v2.0.0` | 3334 | VC issuance |

All images are pulled from **public** registries (ghcr.io / quay.io / docker.io).
Data persists on Docker **named volumes** on the droplet root disk (see §7 — block
volume is attached but not yet used).

---

## 3. Infrastructure inventory (DigitalOcean)

| Resource | Value |
|---|---|
| Project | **NDP** — id `321cd191-ce29-4dc9-8033-3140bdcc47e3` |
| Droplet | `healthflow-hcp-registry` — id **`579721869`** |
| Size / region | `s-4vcpu-8gb` (4 vCPU, 8 GB RAM, 160 GB SSD) / `fra1` (Frankfurt) |
| OS | Ubuntu 22.04 LTS |
| **Reserved IP** (stable public entry) | **`146.190.204.129`** |
| Droplet ephemeral public IP | `207.154.244.220` |
| Private IP (VPC) | `10.135.0.10` |
| Block volume | `ndp-healthflow-data` — id `265ce241-6f03-11f1-8feb-0a58ac12eff0`, 100 GB, attached |
| Cloud firewall | `ndp-healthflow-fw` — id `c4e67028-9a47-4b30-8f4a-72b643c8350a` |
| Firewall inbound | tcp 22, 80, 443, 8080, 8081, **8090** (8090 = temporary diag, see §7) |
| Backups | DO droplet backups **enabled** + nightly `pg_dumpall` cron on host |
| Monitoring | DO monitoring agent enabled |

**DNS — zone `healthflow.eg` hosted in DigitalOcean** (records → `146.190.204.129`):
`@`, `registry`, `keycloak`, `sunbird`, `api.sunbird`, `admin`.
DO nameservers: `ns1/ns2/ns3.digitalocean.com`.

> ⚠️ DNS will **not resolve publicly** until the `healthflow.eg` registrar is set to
> delegate to the three DigitalOcean nameservers above. Until then, use the
> reserved IP `146.190.204.129`.

---

## 4. Access & credentials

- **SSH:** all 19 SSH keys currently on the DO account were installed on the droplet.
  Connect: `ssh root@146.190.204.129`
- **App credentials** (Postgres, Keycloak admin, Vault token) are auto-generated on
  the droplet at **`/opt/healthflow/credentials.txt`** (mode 600). Retrieve with:
  `ssh root@146.190.204.129 'cat /opt/healthflow/credentials.txt'`
- Keycloak admin user: `admin` (password in credentials file).

### 🔐 Security action items (do these first)
1. **Rotate the DigitalOcean API token** used for this deployment
   (`dop_v1_2a1ef67b…`) — it was shared in an assistant chat and should be treated
   as burned. Create a scoped/expiring token for ongoing automation.
2. **Revoke the previously leaked token** `dop_v1_71bcc96a…` (was committed in the
   repo; now scrubbed, but still live until revoked).
   → https://cloud.digitalocean.com/account/api/tokens
3. Move app secrets out of the plaintext on-droplet file into a managed secret
   store before this is treated as real production.

---

## 5. Deployment method (how it works / reproducibility)

The droplet is provisioned by a **`#cloud-config`** passed as user-data. Rather than
cloning this private repo on the droplet (the original approach, which failed
silently because anonymous clone of a private repo is rejected), the tooling now
**bakes the three required files into the cloud-config as base64**:

- `docker/docker-compose.production.yml`
- `docker/scripts/init-db.sql`
- `scripts/provision-droplet.sh` (installs Docker, sets ES `vm.max_map_count`,
  generates `.env`, `docker compose up -d`)

Two reproducible entry points (both updated to this method):

```bash
# Option A — DO API script (recommended, one command)
export DO_API_TOKEN="<new scoped token>"
./scripts/deploy-digitalocean-api.sh create     # status | destroy | ssh

# Option B — Terraform (IaC)
cd terraform
cp terraform.tfvars.example terraform.tfvars     # set do_token, ssh_key_name
terraform init && terraform apply
```

`docker-compose.production.yml` expects these env vars (auto-generated into `.env`
by `provision-droplet.sh`): `DB_USER`, `DB_PASSWORD`, `KEYCLOAK_ADMIN`,
`KEYCLOAK_ADMIN_PASSWORD`, `VAULT_TOKEN`. The DB init script creates the per-service
databases (`registry`, `keycloak`, `identity`, `credential_schema`, `credentials`,
`claims`, `idgen`, `bulk_issuance`).

---

## 6. Verification runbook (RUN THIS FIRST)

From any normal network (not the deployment sandbox):

```bash
ssh root@146.190.204.129 '
  echo "== provisioning ==";  tail -n 20 /var/log/healthflow-provision.log
  echo "== done marker ==";   ls -l /opt/healthflow/PROVISION_DONE 2>/dev/null || echo "NOT DONE YET"
  echo "== containers ==";    cd /opt/healthflow/docker && docker compose -f docker-compose.production.yml ps
  echo "== registry ==";      curl -s -o /dev/null -w "registry :8081 -> %{http_code}\n" localhost:8081/health
  echo "== keycloak ==";      curl -s -o /dev/null -w "keycloak :8080 -> %{http_code}\n" localhost:8080/
'
```

Expected: all containers `Up`/`healthy`; `:8081/health` returns 200. External smoke
test: `curl http://146.190.204.129:8081/health` and open
`http://146.190.204.129:8080/` (Keycloak).

If containers are restarting, capture logs:
`docker compose -f docker-compose.production.yml logs --tail=100 <service>`.

---

## 7. Known issues / open items

| # | Item | Impact | Recommended action |
|---|---|---|---|
| 1 | **App not independently verified** (see §1/§6) | Unknown runtime health | Run §6 verification first |
| 2 | **Block volume not mounted** — 100 GB `ndp-healthflow-data` is attached but compose uses Docker named volumes on root disk | Data on 160 GB root disk, not the dedicated volume; no data isolation | Mount volume and point `postgres_data`/`es_data` at it, or switch compose volumes to a bind mount under the volume mountpoint |
| 3 | **DNS delegation pending** | `healthflow.eg` won't resolve | Delegate registrar NS → DigitalOcean (§3) |
| 4 | **No TLS** | Plain HTTP on 8080/8081 | Add nginx reverse proxy + Let's Encrypt (certbot) once DNS resolves; terminate 443 → 8081/8080 |
| 5 | **Vault in dev mode**, **Keycloak `start-dev`** | Not production-grade (in-memory/no persistence guarantees) | Move Vault to server mode + unseal; run Keycloak in production mode with proper hostname/TLS |
| 6 | **Diagnostics port 8090 open** in firewall (added for remote debugging) | Minor exposure | Remove the 8090 inbound rule; no service should bind it in normal operation |
| 7 | **Secrets in plaintext** on droplet | Security | See §4 action items |
| 8 | **Duplicate `@` A record** in DNS zone | Cosmetic | Delete one of the two `@ → 146.190.204.129` records |
| 9 | App-level realm/clients in Keycloak not configured; registry runs with `authentication_enabled=false` | Open API | Configure `healthflow` realm, clients, and enable auth before exposing publicly |

---

## 8. Operations cheatsheet

```bash
# SSH
ssh root@146.190.204.129

cd /opt/healthflow/docker
COMPOSE="docker compose -f docker-compose.production.yml"

$COMPOSE ps                      # status
$COMPOSE logs -f registry        # follow a service
$COMPOSE restart registry        # restart a service
$COMPOSE pull && $COMPOSE up -d   # update images
$COMPOSE down                    # stop all (keeps named volumes)

# Provisioning log
tail -f /var/log/healthflow-provision.log

# Manual DB backup (nightly cron also writes to /opt/healthflow/backups)
docker exec healthflow-db pg_dumpall -U healthflow > /opt/healthflow/backups/manual_$(date +%F).sql
```

Infra lifecycle via the API script (needs `DO_API_TOKEN`):
`./scripts/deploy-digitalocean-api.sh {status|ssh|destroy}`.

---

## 9. Recommended next steps (priority order)

1. **Verify the stack** (§6). Fix anything that's crash-looping.
2. **Security:** rotate/revoke tokens (§4), move secrets to a vault/secret manager.
3. **DNS + TLS:** delegate `healthflow.eg`, then add nginx + Let's Encrypt.
4. **Persistence:** mount the 100 GB block volume and relocate Postgres/ES data onto it.
5. **Production hardening:** Keycloak prod mode, Vault server mode, remove port 8090,
   restrict firewall sources (e.g. limit 8080/8081 to a load balancer / office ranges).
6. **CI/CD:** decide whether to keep the baked-in cloud-config approach or move to a
   managed images / registry pull with an authenticated deploy key.
7. **Merge** branch `claude/eager-davinci-ecn4bw` → `main` after review.

---

## 10. Appendix — repo changes on `claude/eager-davinci-ecn4bw`

| Commit | Summary |
|---|---|
| `b160544` | Scrubbed leaked DO token from `deploy-digitalocean-api.sh`; fixed stale `Healthflow-sunbird-rc-core` repo-name refs |
| `21bda15` | Fixed `docker-compose.production.yml` to boot cleanly: valid Postgres multi-DB `init-db.sql` (mounted), `DB_USER`/`DB_PASSWORD` reconciliation |
| `16cb3f1` | Hardened all deploy paths to bake files into cloud-config instead of cloning the private repo; added shared `scripts/provision-droplet.sh` |

Key files: `scripts/deploy-digitalocean-api.sh`, `scripts/provision-droplet.sh`,
`terraform/main.tf`, `terraform/cloud-init.yaml`, `docker/docker-compose.production.yml`,
`docker/scripts/init-db.sql`, `docker/.env.example`.

---

*Generated as a deployment handoff. Infrastructure facts pulled live from the
DigitalOcean API on 2026-06-24; application runtime health pending DevOps
verification per §6.*
