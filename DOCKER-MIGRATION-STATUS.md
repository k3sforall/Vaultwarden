# Vaultwarden — Docker Migration Status

_Last updated: 2026-06-03_

Vaultwarden was migrated **out of k3s into a standalone Docker stack** on node
`rabbitmq-node-249`, keeping the same data, domain, and external ports. The k3s manifests
are retained for rollback only. This document is the single source of truth for the current
state and the remaining work.

---

## 1. Current state (ACTIVE = Docker)

| Item | Value |
|------|-------|
| Runtime | Docker Compose stack on `rabbitmq-node-249` |
| Live dir | `/opt/vaultwarden-docker/` |
| Config (git) | [`docker/`](docker/) — `docker-compose.yml`, `Caddyfile`, `Dockerfile.caddy`, `.env.example` |
| App | `vaultwarden/server:1.36.0` (internal `:80`) |
| Front proxy | Caddy (`caddy-cloudflare:local`, built with the Cloudflare DNS module) |
| URL | `https://svault.icanvoca.com:4439` (https) · `:8089` (http → 301 https) |
| HTTP/3 | Disabled (TCP-only: `servers { protocols h1 h2 }`) |
| Data | bind-mount `/var/lib/vaultwarden/data` (unchanged host dir) |
| TLS (Phase A) | **Reused** Let's Encrypt cert from k8s secret `vaultwarden-tls-secret`, in `certs/` — **no ACME**. Valid **until 2026-08-31** |
| Restart policy | `unless-stopped`; Docker service enabled on boot |
| Secrets (not in git) | `.env` (`ADMIN_TOKEN`, `CF_API_TOKEN`), `certs/tls.crt`+`tls.key` |

### k3s side (stopped, kept for rollback)
- `Deployment/vaultwarden` → `replicas: 0` (also set in git, commit `441b1a9`).
- Traefik `Service` live-patched to `ClusterIP` to free host ports `:8089`/`:4439`
  (removed `svclb-traefik`). **This is not in git** — it's a live `kubectl patch`.
- cert-manager, ArgoCD, Traefik pods all still running.

### Verified end-to-end (2026-06-03)
- External (public IP) `/alive`, `/api/config` (reports `2025.12.0` = 1.36.0), web vault — all OK with valid public cert.
- Local through Caddy: `/alive` 200, `:8089` → 301, `prelogin` + `prelogin/password` → 200, unauth `/api/accounts/profile` → 401.
- **Real browser-extension login succeeded** — `connect/token` 200 (`User 임승환 logged in successfully`), WebSocket `/notifications/hub` 200, `/api/sync` 200.
- Data preserved: 4 users, 1237 ciphers, 2 orgs; `quick_check = ok`.

---

## 2. Remaining TODO

- [ ] **(Required, before 2026-08-31) Phase B — permanent cert auto-renewal.**
  Currently the cert is the reused k8s one with **no auto-renew**. Once the Let's Encrypt
  duplicate-cert rate-limit window has cleared (a few days after 2026-06-03), switch Caddy to
  manage the cert via Cloudflare DNS-01:
  1. In `docker/Caddyfile` **and** `/opt/vaultwarden-docker/Caddyfile`, replace
     `tls /certs/tls.crt /certs/tls.key` with:
     ```caddyfile
     tls {
         dns cloudflare {env.CF_API_TOKEN}
     }
     ```
  2. `cd /opt/vaultwarden-docker && docker compose restart caddy`
  3. Confirm Caddy obtained/loaded the cert (`docker logs vaultwarden-caddy | grep -i certificate`)
     and `/alive` still 200.
  4. Commit the Caddyfile change. (`CF_API_TOKEN` is already in `.env`; the image already has the module.)

- [ ] **(Decision) ArgoCD external access (`sargocd.icanvoca.com:4439`).**
  Offline while Docker owns `:4439` (ArgoCD pods still run; reachable via `kubectl port-forward`).
  Decide one of: (a) accept it offline, (b) have Caddy also reverse-proxy `sargocd` to an exposed
  `argocd-server`, or (c) tear down ArgoCD/cert-manager/Traefik entirely (full k3s decommission).

- [ ] **(Hygiene) Keep `docker/` (git) and `/opt/vaultwarden-docker/` in sync.**
  They are identical today. Edit in one place, copy to the other, redeploy.

- [ ] **(Optional, later) Decommission k3s** if the Docker setup proves stable and ArgoCD is no
  longer needed — removes the over-engineering this migration was meant to address.

- [ ] **(Optional) Harden `ADMIN_TOKEN`** — Vaultwarden warns it's plaintext; consider an Argon2
  PHC string (`vaultwarden hash`). Functionally fine as-is (same token as before).

- [ ] **(Verify) Backup cron** — the existing `scripts/vaultwarden_backup.sh` (daily 03:00) backs up
  the host data dir, which is unchanged, so it still works. Confirm it no longer references the k3s
  pod for the WAL flush (Docker container holds the DB now). A pre-migration backup exists at
  `/backup/vaultwarden/20260603-200256-pre-docker/`.

---

## 3. Operations quick reference

```bash
cd /opt/vaultwarden-docker

docker compose ps                 # status
docker compose logs -f vaultwarden   # live app logs (watch a login)
docker compose restart caddy      # after Caddyfile edits
docker compose up -d              # apply compose changes
docker build -f Dockerfile.caddy -t caddy-cloudflare:local .   # rebuild Caddy image
```

### Rollback to k3s (⚠️ never run both — shared SQLite single-writer)
```bash
cd /opt/vaultwarden-docker && docker compose down
kubectl -n kube-system patch svc traefik -p '{"spec":{"type":"LoadBalancer"}}'   # svclb returns, sargocd back
kubectl -n default scale deploy/vaultwarden --replicas=1                          # and revert replicas:0 in git
```

See also: top-level [`README.md`](README.md) ("Docker deployment mode") and
[`docker/README.md`](docker/README.md) (bootstrap on a fresh node).
