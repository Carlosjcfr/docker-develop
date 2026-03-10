# Checklist de Despliegue
- [ ] **Estructura**: Carpeta en `/opt/sigergy/<servicio>`.
- [ ] **Rootless**: Ejecución con usuario `admin-sigergy`. Sin privilegios elevados.
- [ ] **Systemd**: Fichero en `~/.config/systemd/user/`.
  - Incluye: `ExecStartPre` (cleanup), `ExecStart` (podman run), `ExecStop` (stop).
- [ ] **Salud**: Endpoint `/health` y logs vía `journalctl --user -u <svc>`.
- [ ] **Seguridad**: Sin `--privileged`. `chmod` solo vía chat (instrucción manual).
- [ ] **Documentación**: Incluir plantilla de servicio y comandos de gestión.
