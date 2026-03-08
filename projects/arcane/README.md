# Arcane

Self-hosted Docker/Podman management UI deployed with Podman rootless.

## Requirements

- Podman (rootless) + `podman-compose`
- `curl`

## Install

**1. Prepare the installation directory** *(only if `/opt` is not writable by your user)*

```bash
sudo mkdir -p /opt/arcane && sudo chown admin:admin /opt/arcane
```

**2. Run the installer**

```bash
curl -fsSL "https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane/install.sh" \
  -o /tmp/install.sh && bash /tmp/install.sh
```

> ⚠️ **Do NOT run with `sudo`.** The script must run as a normal user to maintain a rootless Podman environment. It will request `sudo` internally only when strictly needed.

## Configuration

All configurable variables are defined in `config.env` **in the repository**.
The installer downloads this file on every run, so changes pushed to GitHub
are applied automatically on the next execution.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `INSTALL_DIR` | `/opt/arcane` | Installation path |
| `HOST_IP` | *(auto-detect)* | Host IP for APP_URL generation |
| `APP_PORT` | `3552` | Port exposed for the web UI |
| `ENVIRONMENT` | `production` | Application environment |
| `GIN_MODE` | `release` | Framework mode |
| `LOG_LEVEL` | `info` | Log level |
| `TZ` | `Europe/Madrid` | Timezone |
| `DATABASE_URL` | `file:data/arcane.db?...` | SQLite path and pragmas |
| `ALLOW_DOWNGRADE` | `false` | Allow DB downgrades |
| `JWT_REFRESH_EXPIRY` | `168h` | Refresh token expiry |
| `FILE_PERM` | `0644` | File permissions |
| `DIR_PERM` | `0755` | Directory permissions |
| `TLS_ENABLED` | `false` | Enable direct TLS |
| `AGENT_MODE` | `false` | Enable agent mode |

> Secrets (`ENCRYPTION_KEY`, `JWT_SECRET`) are auto-generated on first run and reused on updates. They must **never** be added to `config.env`.

## Re-deploy / Update

Re-running the installer is safe. It reuses existing secrets and downloads
the latest `config.env` and `docker-compose.yml` from the repository.

```bash
cd /opt/arcane && bash install.sh
```

## Useful commands

```bash
# Service status
systemctl --user status container-arcane.service

# Live logs
podman logs -f arcane

# Restart
systemctl --user restart container-arcane.service
```

## Directory structure

```
/opt/arcane/
├── data/              → Arcane internal data (config, sessions)
├── projects/          → Docker Compose projects managed from the UI
├── .env               → Auto-generated runtime vars (do not edit)
├── config.env         → Downloaded from repo on each run (do not edit locally)
├── docker-compose.yml → Downloaded from repo on each run
└── install.sh         → Unified installer & deployment script
```
