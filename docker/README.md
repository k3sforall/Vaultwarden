# Vaultwarden — standalone Docker deployment

The **active** Vaultwarden runtime (replaces the k3s pod). `vaultwarden/server:1.36.0`
fronted by Caddy terminating TLS on the same external ports as before (`:4439` https,
`:8089` http→https). See the "Docker deployment mode" section in the top-level `README.md`
for the full architecture and rollback procedure.

## Files in this directory (version-controlled)

| File | Purpose |
|------|---------|
| `docker-compose.yml` | The two-container stack (vaultwarden + caddy). |
| `Caddyfile` | TLS termination + reverse proxy. Phase A reuses the existing cert. |
| `Dockerfile.caddy` | Builds `caddy-cloudflare:local` (Caddy + Cloudflare DNS module). |
| `.env.example` | Template for the secrets file. |

**Not committed** (gitignored — provide locally): `.env`, `certs/`, `caddy_data/`, `caddy_config/`.

## Bootstrap on a fresh node

```bash
# 1. Place the config (this dir is the source of truth). Live dir used so far:
mkdir -p /opt/vaultwarden-docker && cd /opt/vaultwarden-docker
cp /path/to/repo/docker/{docker-compose.yml,Caddyfile,Dockerfile.caddy} .

# 2. Secrets
cp /path/to/repo/docker/.env.example .env && $EDITOR .env   # fill ADMIN_TOKEN, CF_API_TOKEN

# 3. TLS cert (Phase A: reuse the existing Let's Encrypt cert)
mkdir -p certs
kubectl -n default get secret vaultwarden-tls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d > certs/tls.crt
kubectl -n default get secret vaultwarden-tls-secret -o jsonpath='{.data.tls\.key}' | base64 -d > certs/tls.key
chmod 600 certs/tls.key

# 4. Build Caddy image + launch
docker build -f Dockerfile.caddy -t caddy-cloudflare:local .
docker compose up -d
```

## Phase B — permanent auto-renewal (do before the cert expires 2026-08-31)

Replace the `tls /certs/...` line in `Caddyfile` with:

```caddyfile
tls {
    dns cloudflare {env.CF_API_TOKEN}
}
```

then `docker compose restart caddy`. Caddy then issues and auto-renews via Cloudflare DNS-01.

> **Keep this dir and `/opt/vaultwarden-docker` in sync.** This repo copy is the source of
> truth for the config files; edit here, copy to the live dir (or vice-versa) and redeploy.
