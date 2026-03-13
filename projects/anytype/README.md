# Anytype (Self-Hosted Bundle)

Sync your Anytype data on your own infrastructure using the optimized all-in-one bundle.

## Quick Management
- **Management Menu:** `./anytype.sh`
- **Start Service:** `systemctl --user start container-anytype.service`
- **Stop Service:** `systemctl --user stop container-anytype.service`
- **Logs:** `podman logs -f anytype`

## Client Configuration (CRITICAL)
Self-hosting Anytype requires a configuration file for the client to know where to connect:
1. After installation, locate the file: `/opt/anytype/etc/client-config.yml`.
2. On your Anytype Client (Desktop/Mobile), go to **Settings > Network**.
3. Select **Self-hosted** and upload/import the `client-config.yml` file.

## Network & Ports
- **Internal IP:** Assigned via `PROJECT_IP` in `internal_net`.
- **Sync Entry:** 443 (TCP/UDP)
- **Coordinator:** 8000 (UDP)
- **Consensus:** 8001-8003 (UDP)
- **gRPC API:** 31010-31012 (TCP)

---
*Powered by Any-Sync Bundle*
