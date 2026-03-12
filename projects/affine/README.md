# AFFiNE Cheat Sheet

All-in-one workspace (Write, Draw, Plan).

## 🚀 Management
```bash
./affine.sh         # Interactive Menu
./affine.sh install # Direct install
./affine.sh update  # Update images/config
./affine.sh start   # Manual start
```

## 📂 Structure
- **Path:** `/opt/affine`
- **Data:** `/opt/affine/data/` (Postgres, Redis, Storage)
- **Config:** `/opt/affine/.env`

## 🔗 Access
- **URL:** `http://<IP>:3010`
- **Admin:** Managed through internal flow (OIDC/Registration).

## 🛠️ Podman Tips
- **Logs:** `podman logs -f affine_server`
- **Status:** `podman ps -a`
- **Service:** `systemctl --user status container-affine`

## 🔒 Security
- **Rootless:** Running under PUID/PGID.
- **SELinux:** Relabeled with `:Z`.
- **DB:** Randomly generated password in `.env`.
