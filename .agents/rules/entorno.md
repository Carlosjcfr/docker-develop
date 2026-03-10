# Reglas de Entorno
- **Infra**: VMs en Proxmox con IPs fijas.
- **Acceso**: SSH/Comandos vía usuario `admin-sigergy` (tiene `sudo`). Sin root directo.
- **Contenedores**: Podman rootless mandatorio.
- **Rutas**: Prioridad absoluta a `/opt/sigergy/`.
- **Permisos**: `chmod` NO en scripts/ficheros. Explicar necesidad en chat y ejecutar manualmente con `sudo`.
