#!/bin/bash
#
# Vaultwarden Backup Script
# Backs up SQLite database, attachments, and sends directories
# Creates both compressed archives and uncompressed copies
#

set -euo pipefail

# Configuration
DATA_DIR="/var/lib/vaultwarden/data"
BACKUP_DIR="/backup/vaultwarden"
DATE=$(date +%Y%m%d)
TIME=$(date +%H%M%S)
RETENTION_DAYS=30

# Create backup directories
BACKUP_PATH="${BACKUP_DIR}/${DATE}"
LATEST_PATH="${BACKUP_DIR}/latest"
mkdir -p "${BACKUP_PATH}"
mkdir -p "${LATEST_PATH}"

# Clean latest directory
rm -rf "${LATEST_PATH:?}"/*

echo "[$(date)] Starting Vaultwarden backup..."
echo "[$(date)] Compressed backup: ${BACKUP_PATH}"
echo "[$(date)] Latest (uncompressed): ${LATEST_PATH}"

# Backup SQLite database
if [ -f "${DATA_DIR}/db.sqlite3" ]; then
    echo "[$(date)] Backing up SQLite database..."

    # Compressed backup
    sqlite3 "${DATA_DIR}/db.sqlite3" ".backup '${BACKUP_PATH}/db_${TIME}.sqlite3'"
    gzip -f "${BACKUP_PATH}/db_${TIME}.sqlite3"
    echo "[$(date)] Compressed: db_${TIME}.sqlite3.gz"

    # Uncompressed copy to latest
    sqlite3 "${DATA_DIR}/db.sqlite3" ".backup '${LATEST_PATH}/db.sqlite3'"
    echo "[$(date)] Latest: db.sqlite3"
else
    echo "[$(date)] WARNING: Database file not found at ${DATA_DIR}/db.sqlite3"
fi

# Backup attachments directory
if [ -d "${DATA_DIR}/attachments" ]; then
    echo "[$(date)] Backing up attachments..."

    # Compressed backup
    tar -czf "${BACKUP_PATH}/attachments_${TIME}.tar.gz" -C "${DATA_DIR}" attachments
    echo "[$(date)] Compressed: attachments_${TIME}.tar.gz"

    # Uncompressed copy to latest
    cp -a "${DATA_DIR}/attachments" "${LATEST_PATH}/"
    echo "[$(date)] Latest: attachments/"
else
    echo "[$(date)] INFO: No attachments directory found"
    mkdir -p "${LATEST_PATH}/attachments"
fi

# Backup sends directory
if [ -d "${DATA_DIR}/sends" ]; then
    echo "[$(date)] Backing up sends..."

    # Compressed backup
    tar -czf "${BACKUP_PATH}/sends_${TIME}.tar.gz" -C "${DATA_DIR}" sends
    echo "[$(date)] Compressed: sends_${TIME}.tar.gz"

    # Uncompressed copy to latest
    cp -a "${DATA_DIR}/sends" "${LATEST_PATH}/"
    echo "[$(date)] Latest: sends/"
else
    echo "[$(date)] INFO: No sends directory found"
    mkdir -p "${LATEST_PATH}/sends"
fi

# Backup RSA keys if they exist
if [ -f "${DATA_DIR}/rsa_key.pem" ]; then
    echo "[$(date)] Backing up RSA keys..."

    # Compressed backup
    tar -czf "${BACKUP_PATH}/rsa_keys_${TIME}.tar.gz" -C "${DATA_DIR}" rsa_key.pem rsa_key.pub.pem 2>/dev/null || \
    tar -czf "${BACKUP_PATH}/rsa_keys_${TIME}.tar.gz" -C "${DATA_DIR}" rsa_key.pem
    echo "[$(date)] Compressed: rsa_keys_${TIME}.tar.gz"

    # Uncompressed copy to latest
    cp -a "${DATA_DIR}/rsa_key.pem" "${LATEST_PATH}/"
    [ -f "${DATA_DIR}/rsa_key.pub.pem" ] && cp -a "${DATA_DIR}/rsa_key.pub.pem" "${LATEST_PATH}/"
    echo "[$(date)] Latest: rsa_key.pem"
fi

# Clean up old backups
echo "[$(date)] Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -name "20*" -mtime +${RETENTION_DAYS} -exec rm -rf {} \;

echo ""
echo "[$(date)] Backup completed successfully"
echo "[$(date)] Compressed backup: ${BACKUP_PATH}"
echo "[$(date)] Latest backup (for quick restore): ${LATEST_PATH}"
echo ""
echo "Quick restore command:"
echo "  cp -a ${LATEST_PATH}/* /var/lib/vaultwarden/data/"
