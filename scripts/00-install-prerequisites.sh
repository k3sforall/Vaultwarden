#!/bin/bash
#
# Vaultwarden Prerequisites Installation Script
# Creates directories and admin token secret
#

set -euo pipefail

echo "=========================================="
echo "Vaultwarden Prerequisites Installation"
echo "=========================================="

# Configuration
DATA_DIR="/var/lib/vaultwarden/data"
BACKUP_DIR="/backup/vaultwarden"

# 1. Create data directory
echo "[1/3] Creating data directory: ${DATA_DIR}"
mkdir -p "${DATA_DIR}"
echo "  ✅ Data directory ready"

# 2. Create backup directory
echo "[2/3] Creating backup directory: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"
echo "  ✅ Backup directory ready"

# 3. Create admin token secret
echo "[3/3] Creating admin token secret..."
if kubectl get secret vaultwarden-admin-token &>/dev/null; then
    echo "  ⚠️  Secret 'vaultwarden-admin-token' already exists, skipping"
else
    kubectl create secret generic vaultwarden-admin-token \
        --from-literal=ADMIN_TOKEN=$(openssl rand -base64 48)
    echo "  ✅ Secret 'vaultwarden-admin-token' created"
fi

echo ""
echo "=========================================="
echo "✅ Prerequisites installation completed"
echo "=========================================="
