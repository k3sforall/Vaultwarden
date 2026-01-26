#!/bin/bash
#
# Vaultwarden Backup Script
# Backs up SQLite database, attachments, and sends directories
#

set -euo pipefail

# Configuration
DATA_DIR="/var/lib/vaultwarden/data"
BACKUP_DIR="/backup/vaultwarden"
DATE=$(date +%Y%m%d)
TIME=$(date +%H%M%S)
RETENTION_DAYS=30

# Create backup directory for today
BACKUP_PATH="${BACKUP_DIR}/${DATE}"
mkdir -p "${BACKUP_PATH}"

# Backup SQLite database
if [ -f "${DATA_DIR}/db.sqlite3" ]; then
    echo "[$(date)] Backing up SQLite database..."
    sqlite3 "${DATA_DIR}/db.sqlite3" ".backup '${BACKUP_PATH}/db_${TIME}.sqlite3'"
    gzip -f "${BACKUP_PATH}/db_${TIME}.sqlite3"
    echo "[$(date)] Database backup completed: db_${TIME}.sqlite3.gz"
else
    echo "[$(date)] WARNING: Database file not found at ${DATA_DIR}/db.sqlite3"
fi

# Backup attachments directory
if [ -d "${DATA_DIR}/attachments" ]; then
    echo "[$(date)] Backing up attachments..."
    tar -czf "${BACKUP_PATH}/attachments_${TIME}.tar.gz" -C "${DATA_DIR}" attachments
    echo "[$(date)] Attachments backup completed: attachments_${TIME}.tar.gz"
else
    echo "[$(date)] INFO: No attachments directory found"
fi

# Backup sends directory
if [ -d "${DATA_DIR}/sends" ]; then
    echo "[$(date)] Backing up sends..."
    tar -czf "${BACKUP_PATH}/sends_${TIME}.tar.gz" -C "${DATA_DIR}" sends
    echo "[$(date)] Sends backup completed: sends_${TIME}.tar.gz"
else
    echo "[$(date)] INFO: No sends directory found"
fi

# Backup RSA keys if they exist
if [ -f "${DATA_DIR}/rsa_key.pem" ] || [ -f "${DATA_DIR}/rsa_key.pub.pem" ]; then
    echo "[$(date)] Backing up RSA keys..."
    tar -czf "${BACKUP_PATH}/rsa_keys_${TIME}.tar.gz" -C "${DATA_DIR}" rsa_key.pem rsa_key.pub.pem 2>/dev/null || true
    echo "[$(date)] RSA keys backup completed"
fi

# Clean up old backups
echo "[$(date)] Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -exec rm -rf {} \;

echo "[$(date)] Backup completed successfully"
echo "[$(date)] Backup location: ${BACKUP_PATH}"
