# Arcane

Self-hosted Docker/Podman management UI deployed with Podman rootless.

## Requirements

- Podman (rootless) + `podman-compose`
- `curl`

## Install

**1. Prepare the installation directory** *(only if `/opt` is not writable by your user)*

```bash
sudo mkdir -p /opt/arcane && sudo chown admin-sigergy:admin-sigergy /opt/arcane
```

**2. Run the installer**

```bash
curl -fsSL "https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane/install.sh" \
  -o /tmp/install.sh && bash /tmp/install.sh
```

> ⚠️ Always download the script first, then execute it. Do **not** pipe directly to bash (`curl ... | bash`).

## Re-deploy / Update

```bash
cd /opt/arcane && bash start.sh
```

## Directory structure

```
/opt/arcane/
├── data/        → Arcane internal data (config, sessions)
├── projects/    → Docker Compose projects managed from the UI
├── .env         → Auto-generated secrets (do not edit)
├── docker-compose.yml
└── start.sh
```
