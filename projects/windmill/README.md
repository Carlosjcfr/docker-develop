# Windmill Cheat Sheet

## 🚀 Acceso Rápido
- **Web UI:** `http://<HOST_IP>:8000` (o el puerto configurado en `$WINDMILL_PORT`)
- **Default Login:** Navega a la web UI y sigue los pasos para registrarte o iniciar sesión con el correo configurado como admin (dependiendo de la configuración inicial, a veces `admin@windmill.dev` / `changeme`, pero se recomienda crear la cuenta en el primer arranque).

## 📁 Arquitectura y Volúmenes
- `db_data`: Datos persistentes de la base de datos PostgreSQL.
- `worker_logs`: Logs de ejecución de tareas y scripts de los workers.
- `worker_dependency_cache`: Caché de dependencias para acelerar ejecuciones nativas.
- `lsp_cache`: Caché del servidor LSP para autocompletado en el editor integrado.

## 🛠 Comandos Útiles
- **Ver logs del Server:** `podman-compose logs -f windmill_server`
- **Ver logs de los Workers:** `podman-compose logs -f windmill_worker windmill_worker_native`
- **Reiniciar Workers:** `podman-compose restart windmill_worker windmill_worker_native`

## 🛡️ Notas de Seguridad (Rootless)
Este stack se alinea estrictamente con los principios de Podman rootless (y SELinux mediante sufijos `:Z`).
- **Secretos:** La contraseña de la DB (`$DB_PASSWORD`) es **autogenerada** aleatoriamente de forma automática, sin dejarse nunca quemada.
- **Docker Socket:** Por defecto, la capacidad de los workers de instanciar contenedores internos (docker in docker) está desactivada por requerir un daemon de root u host mount del socket. Si tus scripts lo requieren vitalmente, añade un bypass del podman socket manualmente en `docker-compose.yml`.
