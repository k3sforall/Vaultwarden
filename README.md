# Vaultwarden k3s Deployment

GitOps-based Vaultwarden deployment for k3s cluster using ArgoCD, Gateway API, and cert-manager.

## Configuration

| Item | Value |
|------|-------|
| Vaultwarden Domain | `svault.speedycdn.net` |
| ArgoCD Domain | `sargocd.speedycdn.net` |
| Git URL | `https://github.com/k3sforall/Vaultwarden/` |
| Node Name | `laptop-nofan` |
| cert-manager Email | `hanlim@speedykorea.com` |
| Data Path | `/var/lib/vaultwarden/data` |
| Backup Path | `/backup/vaultwarden/` |

## Directory Structure

```
/root/Vaultwarden/
├── Application/
│   ├── argocd-gateway/              # ArgoCD Gateway API (GitOps)
│   │   ├── 1010-gateway-argocd.yaml
│   │   ├── 3200-httproute-https-argocd.yaml
│   │   └── 3210-httproute-http-redirect-argocd.yaml
│   │
│   ├── vaultwarden/                 # Vaultwarden Core (GitOps)
│   │   ├── 2110-storageclass-vaultwarden.yaml
│   │   ├── 2210-pv-vaultwarden.yaml
│   │   ├── 2220-pvc-vaultwarden.yaml
│   │   ├── 2410-service-clusterip-vaultwarden.yaml
│   │   └── 2510-deployment-vaultwarden.yaml
│   │
│   ├── vaultwarden-argocd/          # ArgoCD Applications
│   │   ├── argocd-gateway-app.yaml
│   │   ├── vaultwarden-app.yaml
│   │   └── vaultwarden-gateway-app.yaml
│   │
│   └── vaultwarden-gateway/         # Vaultwarden Gateway API (GitOps)
│       ├── 1016-gateway-vaultwarden.yaml
│       ├── 3201-httproute-https-vaultwarden.yaml
│       └── 3211-httproute-http-redirect-vaultwarden.yaml
│
├── infra/
│   ├── cert-manager/
│   │   ├── 3000-app-cert-manager.yaml          # ArgoCD App (Helm)
│   │   ├── 3100-app-cert-manager-objects.yaml  # ArgoCD App (objects)
│   │   └── objects/
│   │       ├── 3100-clusterissuer-argocd.yaml
│   │       ├── 3100-clusterissuer-vaultwarden.yaml
│   │       ├── 4150-certificate-argocd.yaml
│   │       └── 4150-certificate-vaultwarden.yaml
│   │
│   └── traefik/
│       └── traefik-gateway-config.yaml
│
├── scripts/
│   ├── 00-install-prerequisites.sh
│   ├── 02-install-argocd.sh
│   └── vaultwarden_backup.sh
│
└── README.md
```

## Deployment Order

### Step 1: Prerequisites (Script)

```bash
chmod +x /root/Vaultwarden/scripts/*.sh
/root/Vaultwarden/scripts/00-install-prerequisites.sh
```

### Step 2: Traefik Gateway API Configuration

```bash
cp /root/Vaultwarden/infra/traefik/traefik-gateway-config.yaml \
   /var/lib/rancher/k3s/server/manifests/traefik-config.yaml
kubectl -n kube-system rollout restart deployment traefik
```

### Step 3: ArgoCD Installation (Script)

```bash
/root/Vaultwarden/scripts/02-install-argocd.sh
```

### Step 4: Push to Git Repository

```bash
cd /root/Vaultwarden
git add -A
git commit -m "Vaultwarden GitOps deployment"
git push origin main
```

### Step 5: Deploy ArgoCD Applications (GitOps)

```bash
# cert-manager (Helm)
kubectl apply -f /root/Vaultwarden/infra/cert-manager/3000-app-cert-manager.yaml

# Wait for cert-manager
kubectl -n argocd get application cert-manager -w

# cert-manager objects (ClusterIssuers, Certificates)
kubectl apply -f /root/Vaultwarden/infra/cert-manager/3100-app-cert-manager-objects.yaml

# Gateway Applications
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/argocd-gateway-app.yaml
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/vaultwarden-gateway-app.yaml

# Vaultwarden Core
kubectl apply -f /root/Vaultwarden/Application/vaultwarden-argocd/vaultwarden-app.yaml
```

## ArgoCD Applications

| Name | Description | Source |
|------|-------------|--------|
| cert-manager | cert-manager Helm chart | charts.jetstack.io |
| cert-manager-objects | ClusterIssuers, Certificates | infra/cert-manager/objects |
| argocd-gateway | ArgoCD Gateway API | Application/argocd-gateway |
| vaultwarden-gateway | Vaultwarden Gateway API | Application/vaultwarden-gateway |
| vaultwarden | Vaultwarden Core | Application/vaultwarden |

## Verification

```bash
# ArgoCD Applications
kubectl -n argocd get applications

# Gateways
kubectl get gateway -A

# HTTPRoutes
kubectl get httproute -A

# Certificates
kubectl get certificate -A

# Pods
kubectl get pods -l app.kubernetes.io/name=vaultwarden
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-server
```

## Access URLs

| Service | URL |
|---------|-----|
| Vaultwarden | https://svault.speedycdn.net |
| Vaultwarden Admin | https://svault.speedycdn.net/admin |
| ArgoCD | https://sargocd.speedycdn.net |

## ArgoCD Login

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

- Username: `admin`
- Password: (from above command)

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

```bash
# 1. Stop the Pod
kubectl scale deployment vaultwarden --replicas=0

# 2. Restore Data
gunzip -c /backup/vaultwarden/YYYYMMDD/db_*.sqlite3.gz > /var/lib/vaultwarden/data/db.sqlite3
tar -xzf /backup/vaultwarden/YYYYMMDD/attachments_*.tar.gz -C /var/lib/vaultwarden/data/

# 3. Restart the Pod
kubectl scale deployment vaultwarden --replicas=1
```
