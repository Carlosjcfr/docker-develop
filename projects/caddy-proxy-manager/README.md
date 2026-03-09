# Caddy Proxy + CaddyManager

Caddy reverse proxy with CaddyManager Web UI, deployed with Podman rootless.

## Configuration

All configurable variables are defined in `config.env` **in the repository**.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `INSTALL_DIR` | `/opt/caddy` | Installation path |
| `HOST_IP` | *(auto-detect)* | Host IP |
| `CADDY_VERSION` | `2.11-alpine` | Caddy image tag |
| `PACKAGE_VERSION`| `0.0.2` | CaddyManager image tag |
| `ACME_EMAIL` | `you@example.com` | Let's Encrypt email |
| `CADDYMANAGER_UI_PORT` | `8080` | Web UI port |
| `APP_NAME` | `Caddy Manager` | UI display name |
| `DARK_MODE` | `true` | UI dark mode |
| `BACKEND_PORT` | `3000` | Internal API port |
| `DB_ENGINE` | `sqlite` | Database engine |
| `JWT_EXPIRATION` | `24h` | JWT token expiry |
| `LOG_LEVEL` | `info` | Log level |
| `AUDIT_LOG_MAX_SIZE_MB` | `100` | Audit log max size |
| `AUDIT_LOG_RETENTION_DAYS` | `90` | Audit log retention |
| `PING_INTERVAL` | `30000` | Health check interval (ms) |
| `PING_TIMEOUT` | `2000` | Health check timeout (ms) |
| `METRICS_HISTORY_MAX` | `1000` | Metric snapshots retained |

> `JWT_SECRET` is auto-generated on first run and reused on updates. It must
> **never** be added to `config.env`.

## Default credentials

```text
Username: admin
Password: caddyrocks
```

⚠️ Change these immediately after the first login via the CaddyManager UI.

## Directory structure

```text
/opt/caddy/
├── Caddyfile              → Caddy config (preserved on updates)
├── site/                  → Static site files (optional)
├── .env                   → Auto-generated runtime vars (do not edit)
├── config.env             → Downloaded from repo on each run
├── docker-compose.yml     → Downloaded from repo on each run
└── caddy.sh               → Management script
```

## Volumes

| Volume | Purpose | Safe to delete? |
| :--- | :--- | :---: |
| `caddy_data` | TLS certificates and ACME state | ❌ **Never** |
| `caddy_config` | Caddy runtime config | ⚠️ Only if resetting |
| `caddymanager_sqlite` | CaddyManager database | ⚠️ Loses users and config |

## Useful commands

```bash
# Service status
systemctl --user status caddy-compose.service

# Caddy logs
podman logs -f caddy
podman logs -f caddymanager-backend

# Restart all services
systemctl --user restart caddy-compose.service
```
