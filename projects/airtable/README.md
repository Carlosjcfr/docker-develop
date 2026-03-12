# Airtable (APITable) Cheat Sheet

Self-hosted open-source Airtable alternative.

## Management
- **Install/Menu:** `bash airtable.sh`
- **Start:** `systemctl --user start container-airtable.service`
- **Stop:** `systemctl --user stop container-airtable.service`
- **Logs:** `podman logs -f airtable-gateway`
- **Config:** `/opt/airtable/config.env`
- **Secrets:** `/opt/airtable/.env`

## Connection Details
- **URL:** `http://<HOST_IP>:8081`
- **Admin:** Configurable via environment variables or UI.

## Components
- **Gateway:** Nginx reverse proxy (Port 8081).
- **Web:** Frontend UI.
- **Backend:** Java-based core logic.
- **Room:** Real-time collaboration.
- **DB:** MySQL 8.0.
- **Cache:** Redis.
- **Files:** MinIO (compatible with S3).

## Troubleshooting
- If containers fail to start, check `podman ps -a`.
- Verify MySQL health: `podman logs airtable-mysql`.
- Force tag update: `bash airtable.sh --update`.

---
*Integrated with Arcane Dashboard*
