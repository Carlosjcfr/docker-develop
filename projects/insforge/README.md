# 🛠️ InsForge Cheat Sheet

InsForge is a backend development platform for AI coding agents.

## 🚀 Quick Access
- **App UI:** `http://<HOST_IP>:7130`
- **Auth Proxy:** `http://<HOST_IP>:7132`
- **PostgREST API:** `http://<HOST_IP>:5430`

## 🐳 Stack Management
```bash
# Start service
insforge start
# Update (Pull latest)
insforge update
# Full logs
podman-compose logs -f
```

## 🔐 Credentials
Stored in `/opt/insforge/.env`:
- `ADMIN_EMAIL`: Defined in `config.env`
- `ADMIN_PASSWORD`: Auto-generated on setup

## 📂 Directories
- **Config:** `/opt/insforge`
- **Data:** Podman volumes
- **Logs:** `/opt/insforge/insforge-logs`

---
*Integrated into Arcane Panel*
