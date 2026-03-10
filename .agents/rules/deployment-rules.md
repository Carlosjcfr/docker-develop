# Reglas de Despliegue
- **Arquitectura**: Podman rootless + Systemd user services.
- **Rutas**: `/opt/sigergy/<servicio>/` (bin/config/scripts), `/opt/sigergy/shared/` (volúmenes).
- **Systemd**: `~/.config/systemd/user/<servicio>.service`. Evitar `User=root`, usar `admin-sigergy`.
- **Config**: Variables de entorno, logs a stdout/stderr, health checks activos.
- **Podman**: Usar `--cgroups=no-conmon` y flag `:Z` en volúmenes.
