# Arcane

Modern Docker/Podman management UI. Self-hosted deployment using Podman rootless on a Proxmox VM.

## Requirements

- Podman (rootless)
- `podman-compose`
- `curl`

## Quick Install

Run this single command on the target server:

```bash
curl -fsSL https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane/install.sh \
  -o /tmp/install.sh && bash /tmp/install.sh
```

> **Note:** Do **not** pipe directly to bash (`curl ... | bash`) as it may cause write errors.
> Download the script first, then execute it.

## Re-deploy / Restart

If Arcane is already installed and you need to redeploy:

```bash
cd /opt/arcane
bash start.sh
```

## Files

| File | Description |
|---|---|
| `install.sh` | One-time installer: downloads files and runs `start.sh` |
| `start.sh` | Deployment logic: generates `.env` and starts services |
| `docker-compose.yml` | Service definition for Arcane (Podman rootless) |

## Data directories

All data is stored under `/opt/arcane/`:

| Path | Contents |
|---|---|
| `data/` | Internal Arcane data (config, sessions, DB) |
| `stacks/` | Docker Compose stacks managed through the UI |
