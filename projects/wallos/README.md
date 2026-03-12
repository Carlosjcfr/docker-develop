# Wallos Cheat Sheet

Personal finance management tool (PHP/SQLite).

## Usage

- **URL**: `http://<HOST_IP>:8282`
- **First Run**: Access the URL to start the on-boarding process.

## Management

```bash
./wallos.sh install    # Deploy service
./wallos.sh start      # Start existing
./wallos.sh update     # Update image/config
./wallos.sh uninstall  # Full cleanup
```

## Structure

- `./db`: SQLite database and app settings.
- `./logos`: Uploaded images and logos.

## Troubleshooting

- Check logs: `podman logs -f wallos`
- SELinux issues: Ensure volumes have `:Z` suffix.
- Permissions: Runs as user (Rootless) using PUID/PGID.

---
*Generated for docker-develop framework.*
