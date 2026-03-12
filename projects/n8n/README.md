# n8n — Workflow Automation
Cheat Sheet for n8n deployment in Podman rootless.

## Quick Links
- **UI:** http://${HOST_IP}:5678
- **Data Dir:** /opt/n8n/n8n_data
- **DB Dir:** /opt/n8n/db_data

## Common Commands
- **Logs:** `podman logs -f n8n`
- **Restart:** `systemctl --user restart container-n8n.service`
- **Backup:** Copy the `n8n_data` folder.

## Database
- **Type:** PostgreSQL 16
- **Local Access:** `podman exec -it n8n-db psql -U n8n`

## Troubleshooting
- **Permissions:** Folders use `:Z` for SELinux compliance.
- **Port Conflict:** Check `config.env` if 5678 is taken.
- **Webhook:** Ensure `WEBHOOK_URL` in `.env` matches your address method.
