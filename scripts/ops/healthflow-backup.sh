#!/bin/bash
# HealthFlow nightly backup: dump all Postgres DBs + key compose/env files
set -euo pipefail
BACKUP_DIR="/opt/healthflow/backups"
STAMP="$(date +%F_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Postgres logical dump of all databases
docker exec healthflow-db pg_dumpall -U healthflow > "$BACKUP_DIR/pg_all_${STAMP}.sql" 2>/dev/null

# Compress
gzip -f "$BACKUP_DIR/pg_all_${STAMP}.sql"

# Snapshot critical config (compose + env + credentials) into a tarball
tar -czf "$BACKUP_DIR/config_${STAMP}.tgz" \
  -C /opt/healthflow/docker docker-compose.production.yml .env 2>/dev/null || true

# Retention: keep last 14 days
find "$BACKUP_DIR" -name 'pg_all_*.sql.gz' -mtime +14 -delete 2>/dev/null || true
find "$BACKUP_DIR" -name 'config_*.tgz'    -mtime +14 -delete 2>/dev/null || true

echo "[$(date)] backup complete: pg_all_${STAMP}.sql.gz" >> "$BACKUP_DIR/backup.log"
