# Nuevo Servicio — `docker-develop` (Podman rootless)

Eres un experto DevOps. Genera los 5 entregables: `docker-compose.yml`, `config.env`, `README.md` (Cheat Sheet ≤30 líneas), `<slug>.sh`, `.registry`.

**[SERVICIO]:** `<nombre — descripcion>`  
**[PUERTOS]:** `<lista>`  
**[VOLÚMENES]:** `<lista>`  
**[IMAGEN]:** `<fqdn>` *(debe comenzar por `docker.io/` o `ghcr.io/`)*

---

## Reglas

| # | Regla | Detalle |
|---|---|---|
| 1 | **Rootless** | Sin `sudo` ni root en ningún fichero. |
| 2 | **SELinux** | Todos los bind-mounts en `docker-compose.yml` terminan en `:Z`. |
| 3 | **Secretos** | No pongas passwords en `config.env`; genéralos vía bash y léelos del entorno. |
| 4 | **Tags** | Nunca inventes tags. En caso de duda, usa `latest`. Tags falsos → contenedor `missing`. |
| 5 | **container_name** | Define siempre `container_name:` bajo cada `image:`. Sin él, `verify_containers_running` falla con `missing`. |
| 6 | **One IP per Project** | Llama a `assign_project_ip` antes de generar el `.env`. Persiste `PROJECT_IP`. Todos los servicios usan `ipv4_address: ${PROJECT_IP}` en `internal_net` (172.170.1.0/24). |
| 7 | **Arcane** | Contenedor principal incluye labels `dev.arcane.icon`, `dev.arcane.category`, `com.docker.compose.project`, `com.docker.compose.project.working_dir=/app/data/projects/<slug>`. Llama a `register_arcane_project "<slug>" "$INSTALL_DIR"` tras el despliegue. Icono/categoría parametrizables desde `config.env`. |
| 8 | **Auto-Registro** | Incluye `.registry` con la línea exacta para `deploy.sh`. |
| 9 | **Macro-Services** | Para stacks complejos (Supabase, Nextcloud…): busca el `.env`/`docker-compose.yml` oficial, extrae tags probadas como variables en `config.env` (e.g. `POSTGRES_VERSION=15.1`) y úsalas como `${POSTGRES_VERSION}` en el `.yml`. |
| 10 | **Sub-Volumes** | No omitas volúmenes ni scripts de init de BD. Si el stack requiere directorios nativos (e.g. `init-db.d/`), añade en `do_install` comandos que los descarguen (sparse clone / wget) antes de levantar los contenedores. |
| 11 | **Variables críticas** | Revisa `.env.example` o docs oficiales. Incluye todas las variables obligatorias para el arranque; omite las experimentales/opcionales/analíticas. Centraliza `environment:` a través de `config.env`. |

---

## Patrón networking (`docker-compose.yml`)

```yaml
services:
  main-app:
    image: ${IMAGE_TAG}
    container_name: ${CONTAINER_NAME}
    networks:
      internal_net:
        ipv4_address: ${PROJECT_IP}

networks:
  internal_net:
    external: true
```

---

## Esqueleto obligatorio `<slug>.sh`

No inventes funciones. Rellena exactamente este molde:

```bash
#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/<slug>"
# shellcheck source=lib.sh
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    ARCANE_ICON="${ARCANE_ICON:-si:<icon_slug>}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-<Category>}"
}

generate_runtime_env() {
    local OLD_UMASK; OLD_UMASK=$(umask); umask 177
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
PROJECT_IP="$PROJECT_IP"
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="<NAME>"
    UNINSTALL_SYSTEMD="container-<slug>.service"
    UNINSTALL_CONTAINERS=("<main_container>")
    # NOTE: fallback estático; el motor descubre imágenes desde docker-compose.yml automáticamente.
    UNINSTALL_IMAGES=("<fqdn_imagen_exacta>")
    UNINSTALL_VOLUMES=("<array_volumenes_persistentes>")
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/<slug>}"
    [ -f "$dir/.env" ] && podman container exists <main_container> 2>/dev/null
}

deploy_and_persist() {
    log "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    podman-compose config >/dev/null 2>&1 || { err "Sintaxis docker-compose inválida. Abortando."; exit 1; }
    if ! podman-compose pull > "$INSTALL_DIR/install.log" 2>&1; then
        err "Fallo al descargar imágenes. Revisa $INSTALL_DIR/install.log"
        read -rp " ¿Parchear tags a 'latest' e intentar de nuevo? [y/N]: " FIX_TAGS
        if [[ "$FIX_TAGS" =~ ^[Yy]$ ]]; then
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null || { err "Fallo crítico con latest."; exit 1; }
        else
            exit 1
        fi
    fi
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running <tus_contenedores_aqui>
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-<slug>.service
[Unit]
Description=<NAME> Stack (podman-compose)
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=$(command -v podman-compose) up -d
ExecStop=$(command -v podman-compose) down
TimeoutStartSec=120
TimeoutStopSec=30
[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now container-<slug>.service
}

print_success() {
    echo "================================================================="
    echo " <NAME> deployed and secured with systemd."
    echo " URL: http://$HOST_IP:<PORT>"
    echo "================================================================="
}

do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    # manage_credentials "$INSTALL_DIR" MIVAR_SECRETA
    setup_lingering_and_socket; assign_project_ip
    check_install_dir_writable "$INSTALL_DIR"; mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    generate_runtime_env; deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"; print_success
}

do_start()  { systemctl --user start container-<slug>.service; }

do_update() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    if [ -f "$INSTALL_DIR/.env" ]; then
        PROJECT_IP=$(grep "^PROJECT_IP=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"''')
    else
        assign_project_ip
    fi
    generate_runtime_env
    cp "$INSTALL_DIR/config.env"       "$INSTALL_DIR/config.env.bak"       2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true
    mv -f "$TMP_DIR/config.env"        "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"; print_success
}

root_protection
check_dependencies curl podman-compose
parse_args "$@"

if [ -n "$CMD_ACTION" ]; then
    case "$CMD_ACTION" in
        install)   do_install ;;
        start)     do_start ;;
        update)    do_update ;;
        uninstall) do_uninstall ;;
        *) err "Invalid action."; exit 1 ;;
    esac
    exit 0
fi

if check_existing_installation "/opt/<slug>"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " <NAME> — Management"
        echo "================================================================="
        echo " Instalación existente en /opt/<slug>"
        echo ""
        echo "   1) Start      — Iniciar contenedor"
        echo "   2) Update     — Descargar config y redesplegar"
        echo "   3) Uninstall  — Eliminar contenedor, servicio y datos"
        echo "   0) Cancel"
        echo ""
        read -rp " Selecciona [0-3]: " ACTION
        case "$ACTION" in
            1) do_start ;; 2) do_update ;; 3) do_uninstall ;;
            0) log "Cancelled."; exit 0 ;;
            *) err "Invalid option."; exit 1 ;;
        esac
    else
        log "Instalación existente. Ejecutando update..."
        do_update
    fi
else
    do_install
fi
```

---

## `.registry` — línea exacta para `deploy.sh`

```
"Nombre|projects/<slug>/<slug>.sh|/opt/<slug>|<main_container>|Descripción breve|Servicio: {IP}:<PORT>"
```
