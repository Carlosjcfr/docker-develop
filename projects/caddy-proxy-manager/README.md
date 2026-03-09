# Caddy Proxy + CaddyManager

Caddy reverse proxy with CaddyManager Web UI, deployed with Podman rootless.

## Requirements

- Podman (rootless) + `podman-compose`
- `curl`
- `sudo` access (for enabling privileged ports and lingering)

## Install

**1. Prepare the installation directory** *(only if `/opt` is not writable by your user)*

```bash
sudo mkdir -p /opt/caddy && sudo chown admin:admin /opt/caddy
```

**2. Run the installer**

```bash
curl -fsSL "https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/caddy-manager-proxy/caddy.sh \
  -o /tmp/caddy.sh && bash /tmp/caddy.sh
```

> ⚠️ **Do NOT run with `sudo`.** The script must run as a normal user. It will
> request `sudo` internally for: enabling privileged ports (80/443) and user lingering.

### What does the script do with `sudo`?

| Command | Purpose | When |
| :--- | :--- | :--- |
| `sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0` | Allow rootless Podman to bind ports 80/443 | First install |
| `sudo tee /etc/sysctl.d/99-unprivileged-ports.conf` | Persist the above across reboots | First install |
| `sudo loginctl enable-linger $USER` | Keep containers running after SSH logout | Every run |

## Management

When an existing installation is detected, `caddy.sh` shows a management menu:

```text
 CADDY PROXY + MANAGER — Management
 Existing installation detected at /opt/caddy

   1) Start      — Start the existing services
   2) Update     — Download latest config and redeploy
   3) Uninstall  — Remove containers, service, and data
   0) Cancel
```

- **Via `curl | bash`** with existing installation → runs Update automatically.
- **Uninstall** requires typing `UNINSTALL` to confirm, with a separate prompt
  before deleting TLS certificates and data volumes.

### Interactive mode

During Install or Update, if running from a terminal:

```text
Run in interactive mode? (customize all options) [y/N]:
```

## Configuration

All configurable variables are defined in `config.env` **in the repository**.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `INSTALL_DIR` | `/opt/caddy` | Installation path |
| `HOST_IP` | *(auto-detect)* | Host IP |
| `CADDY_VERSION` | `2` | Caddy image tag |
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

## Useful commands

```bash
# Service status
systemctl --user status caddy-compose.service

# Caddy logs
podman logs -f caddy

# CaddyManager backend logs
podman logs -f caddymanager-backend

# Restart all services
systemctl --user restart caddy-compose.service
```

## Directory structure

```text
/opt/caddy/
├── conf/
│   └── Caddyfile          → Caddy config (preserved on updates)
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
