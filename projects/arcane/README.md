# Arcane

Self-hosted Docker/Podman management UI deployed with Podman rootless.

## Configuration

All configurable variables are defined in `config.env` **in the repository**.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `INSTALL_DIR` | `/opt/arcane` | Installation path |
| `HOST_IP` | *(auto-detect)* | Host IP for APP_URL generation |
| `APP_PORT` | `3552` | Port exposed for the web UI |
| `ENVIRONMENT` | `production` | Application environment |
| `GIN_MODE` | `release` | Framework mode |
| `LOG_LEVEL` | `info` | Log level |
| `TZ` | `Europe/Madrid` | Timezone |
| `JWT_REFRESH_EXPIRY` | `168h` | Refresh token expiry |
| `FILE_PERM` | `0644` | File permissions |
| `DIR_PERM` | `0755` | Directory permissions |
| `TLS_ENABLED` | `false` | Enable direct TLS |
| `AGENT_MODE` | `false` | Enable agent mode |

> Secrets (`ENCRYPTION_KEY`, `JWT_SECRET`) are auto-generated on first run and reused on updates. They must **never** be added to `config.env`.

## Directory structure

```
/opt/arcane/
├── data/              → Arcane internal data (config, sessions)
├── projects/          → Docker Compose projects managed from the UI
├── .env               → Auto-generated runtime vars (do not edit)
├── config.env         → Downloaded from repo on each run
├── docker-compose.yml → Downloaded from repo on each run
└── arcane.sh          → Management script (install/start/update/uninstall)
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
