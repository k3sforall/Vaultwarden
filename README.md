# Vaultwarden k3s Deployment

GitOps-based Vaultwarden deployment for k3s cluster using ArgoCD, Gateway API, and cert-manager.

## Configuration

| Item | Value |
|------|-------|
| Vaultwarden Domain | `svault.icanvoca.com:4438` |
| ArgoCD Domain | `sargocd.icanvoca.com:4438` |
| Git URL | `https://github.com/k3sforall/Vaultwarden/` |
| Node Name | `rabbitmq-node-249` |
| cert-manager Email | `admin@icanvoca.com` |
| ACME Challenge | Cloudflare DNS-01 |
| Cloudflare DNS Records | A records, TTL 60, DNS-only |
| External Port Forwarding | `1.220.22.242:8088 -> 192.168.29.249:8088`, `1.220.22.242:4438 -> 192.168.29.249:4438` |
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

# Cloudflare DNS-01 token secret
kubectl -n cert-manager create secret generic cloudflare-api-token-secret \
  --from-literal=api-token="${CF_API_TOKEN}"

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

## Sync Policy

All Applications use **manual sync** to reduce CPU load on this
low-spec single-node cluster. ArgoCD still polls Git every 3 minutes
to detect OutOfSync, but does **not** auto-apply changes. `selfHeal`
is also disabled, so cluster drift (e.g. someone running `kubectl
edit`) is not automatically reverted to Git.

| Application | syncPolicy.automated | selfHeal |
|---|---|---|
| vaultwarden, argocd-gateway, vaultwarden-gateway, cert-manager, cert-manager-objects | (removed) | off |

### Applying changes after `git push`

```bash
# Preview what will change in the cluster
argocd app diff <app-name>

# Apply a single application
argocd app sync <app-name>

# Sync all five applications at once
argocd app sync vaultwarden argocd-gateway vaultwarden-gateway \
                cert-manager cert-manager-objects
```

### When manual intervention is needed

- After `git push` of any manifest change → run `argocd app sync <app>`
- After someone runs `kubectl edit` and creates drift → run
  `argocd app sync <app>` to revert the cluster to Git
- To see overall sync state at a glance → `argocd app list`

### Trade-offs

- ✅ Lower CPU on the single-node cluster (no selfHeal scans)
- ✅ Predictable: nothing changes in the cluster without an explicit
  human sync command
- ⚠️ Cluster drift after `kubectl edit` is **not** auto-restored
- ⚠️ Forgetting to `argocd app sync` after `git push` leaves the
  cluster on the previous revision

### Re-enabling automated sync (if ever needed)

Add the following block back to each Application yaml under
`spec.syncPolicy`, commit, push, and run `kubectl apply -f` on the
Application files (Applications are not managed by ArgoCD themselves):

```yaml
    automated:
      selfHeal: true
      prune: true   # or false for vaultwarden
```

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
| Vaultwarden | https://svault.icanvoca.com:4438 |
| Vaultwarden Admin | https://svault.icanvoca.com:4438/admin |
| ArgoCD | https://sargocd.icanvoca.com:4438 |

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
