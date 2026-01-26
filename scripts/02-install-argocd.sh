#!/bin/bash
#
# ArgoCD Installation Script
# Installs ArgoCD using Helm with Gateway API support
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "ArgoCD Installation"
echo "=========================================="

# Check if ArgoCD is already installed
echo "[1/4] Checking existing ArgoCD installation..."
if kubectl get namespace argocd &>/dev/null; then
    echo "  ⚠️  ArgoCD namespace already exists"

    # Check if pods are running
    READY=$(kubectl -n argocd get deploy argocd-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$READY" -ge 1 ]]; then
        echo "  ✅ ArgoCD is already running, skipping installation"
        kubectl -n argocd get pods
        exit 0
    fi
fi

# Create namespace
echo "[2/4] Creating argocd namespace..."
kubectl create namespace argocd 2>/dev/null || true

# Add Helm repo
echo "[3/4] Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
echo "[4/4] Installing ArgoCD via Helm..."
helm upgrade --install argocd argo/argo-cd \
    -n argocd \
    --set server.service.type=ClusterIP \
    --set configs.params."server\.insecure"=true \
    --wait

echo ""
echo "=========================================="
echo "✅ ArgoCD installation completed"
echo "=========================================="
kubectl -n argocd get pods

echo ""
echo "To get initial admin password:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
