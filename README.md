# Vaultwarden k3s Deployment

GitOps-based Vaultwarden deployment for k3s cluster using ArgoCD, Gateway API, and cert-manager.

## Configuration

| Item | Value |
|------|-------|
| Domain | `svault.speedycdn.net` |
| Git URL | `https://github.com/k3sforall/Vaultwarden/` |
| Node Name | `laptop-nofan` |
| cert-manager Email | `hanlim@speedykorea.com` |
| Data Path | `/var/lib/vaultwarden/data` |
| Backup Path | `/backup/vaultwarden/` |

## Directory Structure

```
/root/Vaultwarden/
├── Application/
│   ├── vaultwarden/                    # Core resources (GitOps)
│   │   ├── 2110-storageclass-vaultwarden.yaml
│   │   ├── 2210-pv-vaultwarden.yaml
│   │   ├── 2220-pvc-vaultwarden.yaml
│   │   ├── 2410-service-clusterip-vaultwarden.yaml
│   │   └── 2510-deployment-vaultwarden.yaml
│   │
│   ├── vaultwarden-gateway/            # Gateway API resources (GitOps)
│   │   ├── 1016-gateway-vaultwarden.yaml
│   │   ├── 3201-httproute-https-vaultwarden.yaml
│   │   └── 3211-httproute-http-redirect-vaultwarden.yaml
│   │
│   ├── vaultwarden-cert/               # cert-manager resources (GitOps)
│   │   ├── 3100-clusterissuer-vaultwarden.yaml
│   │   └── 4150-certificate-vaultwarden.yaml
│   │
│   └── vaultwarden-argocd/             # ArgoCD Applications
│       ├── cert-manager-app.yaml       # cert-manager Helm chart
│       ├── vaultwarden-gateway-app.yaml
│       ├── vaultwarden-cert-app.yaml
│       └── vaultwarden-app.yaml        # Core resources
│
├── scripts/
│   ├── 00-install-prerequisites.sh     # Directories & secrets
│   ├── 02-install-argocd.sh            # ArgoCD installation
│   └── vaultwarden_backup.sh           # Backup script
│
└── README.md
```

## Deployment Order

### Step 1: Prerequisites (Script)

```bash
chmod +x /root/Vaultwarden/scripts/*.sh
/root/Vaultwarden/scripts/00-install-prerequisites.sh
```

### Step 2: ArgoCD Installation (Script)

ArgoCD는 GitOps 도구 자체이므로 스크립트로 설치합니다.

```bash
/root/Vaultwarden/scripts/02-install-argocd.sh
```

### Step 3: Push to Git Repository

ArgoCD가 Git에서 리소스를 동기화하므로, 먼저 Git에 푸시합니다.

```bash
cd /root/Vaultwarden
git add -A
git commit -m "Vaultwarden GitOps deployment configuration"
git push origin main
```

### Step 4: Deploy ArgoCD Applications (GitOps)

ArgoCD Application을 순서대로 적용합니다. sync-wave에 의해 자동 순서 제어됩니다.

```bash
# cert-manager 먼저 (sync-wave: -100)
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/cert-manager-app.yaml

# cert-manager Ready 대기
kubectl -n argocd get application cert-manager -w

# 나머지 Applications 적용 (sync-wave 순서대로 자동 배포)
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/vaultwarden-gateway-app.yaml
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/vaultwarden-cert-app.yaml
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/vaultwarden-app.yaml
```

## Sync Wave Order

| Wave | Application | Description |
|------|-------------|-------------|
| -100 | cert-manager | cert-manager Helm chart |
| -50 | vaultwarden-gateway | Gateway + HTTPRoutes |
| -40 | vaultwarden-cert | ClusterIssuer + Certificate |
| -30 | vaultwarden | Core (StorageClass, PV, PVC, Service, Deployment) |

## Verification

### 1. ArgoCD Applications Status

```bash
kubectl -n argocd get applications
```

### 2. Check Pod Status

```bash
kubectl get pods -l app.kubernetes.io/name=vaultwarden
```

### 3. Check Certificate Issuance

```bash
kubectl get certificate vaultwarden-tls-cert
kubectl describe certificate vaultwarden-tls-cert
```

### 4. Check Gateway Status

```bash
kubectl get gateway vaultwarden-gw
kubectl get httproute
```

### 5. Web Access Test

- Main: https://svault.speedycdn.net
- Admin: https://svault.speedycdn.net/admin

## Backup

### Setup Cron Job

```bash
# Add to crontab (runs daily at 03:00)
0 3 * * * /root/Vaultwarden/scripts/vaultwarden_backup.sh
```

### Manual Backup

```bash
/root/Vaultwarden/scripts/vaultwarden_backup.sh
```

## Restore

### 1. Stop the Pod

```bash
kubectl scale deployment vaultwarden --replicas=0
```

### 2. Restore Data

```bash
# Restore database
gunzip -c /backup/vaultwarden/YYYYMMDD/db_*.sqlite3.gz > /var/lib/vaultwarden/data/db.sqlite3

# Restore attachments
tar -xzf /backup/vaultwarden/YYYYMMDD/attachments_*.tar.gz -C /var/lib/vaultwarden/data/

# Restore sends (if exists)
tar -xzf /backup/vaultwarden/YYYYMMDD/sends_*.tar.gz -C /var/lib/vaultwarden/data/
```

### 3. Restart the Pod

```bash
kubectl scale deployment vaultwarden --replicas=1
```

## Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application status
kubectl -n argocd describe application <app-name>

# Force sync
kubectl -n argocd patch application <app-name> -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"prune":false}}}' --type=merge
```

### Certificate Not Issuing

```bash
# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate status
kubectl describe certificate vaultwarden-tls-cert

# Check challenge status
kubectl get challenges
```

### Pod Not Starting

```bash
# Check pod logs
kubectl logs -l app.kubernetes.io/name=vaultwarden

# Check events
kubectl describe pod -l app.kubernetes.io/name=vaultwarden
```
