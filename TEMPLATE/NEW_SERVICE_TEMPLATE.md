# Plantilla Rápida: Nuevo Servicio

---
Actúa como experto DevOps. Crea los 5 ficheros para integrar este servicio en mi framework `docker-develop` (Podman rootless):

**[SERVICIO]:** <nombre_y_descripcion> (ej: AdGuard Home - DNS blocker)
**[PUERTOS]:** <lista_puertos>
**[VOLÚMENES]:** <lista_volumenes>
**[IMAGEN]:** <url_imagen_fqdn> (DEBE empezar por docker.io/ o ghcr.io/)

---

**REGLAS ESTRICTAS:**

1. **Rootless & SELinux:** Cero referencias a `sudo`. Todo mapeo de carpetas en `docker-compose.yml` DEBE terminar en `:Z` para compatibilidad con SELinux en Podman.
2. **Secretos Dinámicos:** Nunca pongas passwords fijos en `config.env`. Deben generarse vía bash en el script (usando `openssl rand`) y persistirse en el `.env` local.
3. **Tags de Imagen (Precisión):** NUNCA inventes o deduzcas tags de imagen. Si dudas, usa `latest`. Tags erróneos causan estados `missing` silenciosos.
4. **Macro-Services (Resolución Dinámica):** Si el servicio es complejo (multi-contenedor), realiza una búsqueda web previa para localizar el `.env` o `docker-compose.yml` oficial. Extrae las tags probadas y decláralas como variables en el `config.env`.
5. **Sub-Volumes & Integridad:** En servicios que dependen de carpetas de inicialización (ej. `init-db.d/`), genera comandos en `do_install` para descargar esos directorios antes de arrancar los contenedores.
6. **Integración con Arcane (Visibility):** El contenedor principal requiere labels para icono (`dev.arcane.icon`), categoría (`dev.arcane.category`), nombre de proyecto (`com.docker.compose.project`), y directorio de trabajo (`com.docker.compose.project.working_dir=/app/data/projects/<slug>`).
7. **Nombres de Contenedor Explícitos:** Define siempre `container_name: <nombre>` en cada servicio de Compose. Sin esto, las comprobaciones de estado de nuestro framework fallarán.
8. **Sincronización de Entorno (CRÍTICO):** Cualquier variable declarada en `config.env` que se use en `docker-compose.yml` (especialmente versiones como `${MONGO_VERSION}`) **DEBE** ser añadida explícitamente a la función `generate_runtime_env` del script `.sh`. Si olvidas añadir una versión al `.env` final, Podman fallará con el error `invalid reference format`.
9. **Fin de Línea Unix (LF):** Todos los archivos `.sh` y `.env` deben ser guardados estrictamente con formato de fin de línea Unix (LF). El formato Windows (CRLF) causará errores sintácticos invisibles como `\r: command not found`.
10. **Modo de Desarrollo (Pruebas Locales):** El script debe incluir soporte para `LIB_LOCAL`. Esto permite probar cambios locales sin necesidad de subirlos a GitHub indicando `export LIB_LOCAL=$(pwd)/lib/lib.sh`. El script debe deducir la ruta del repositorio basándose en la ubicación de `LIB_LOCAL`.
11. **Investigación de Terceros (Community First):** Antes de implementar un stack complejo desde cero, el paso obligatorio es buscar "community scripts" o "all-in-one bundles" (ej: `community-scripts.org` o proyectos `aio` en GitHub).
12. **Menú de Gestión Interactivo:** Si el servicio ya está instalado (detectado por `check_existing_installation`), el script DEBE mostrar un menú interactivo con las opciones: 1) Start, 2) Update, 3) Uninstall, 0) Cancel.

---

**ESQUELETO OBLIGATORIO PARA `<slug>.sh`:**

```bash
#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/<slug>"
# shellcheck source=lib.sh
if [[ -n "${LIB_LOCAL:-}" && -f "$LIB_LOCAL" ]]; then
    source "$LIB_LOCAL"
else
    source <(curl -fsSL "$REPO_BASE/lib/lib.sh")
fi

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # Inicializa tus variables personalizadas aquí
    ARCANE_ICON="${ARCANE_ICON:-si:<icon_slug>}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-<Category>}"
}

generate_runtime_env() {
    log "Generating runtime .env file..."
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177
    
    # CRITICAL: Every variable used in docker-compose.yml (especially VERSION tags) 
    # MUST be explicitly added here, otherwise Podman will fail with 'invalid reference format'.
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
PROJECT_IP="$PROJECT_IP"

# Service Configuration (Add every variable from config.env used in compose here)
# EXAMPLE_VERSION="$EXAMPLE_VERSION"

# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
    log ".env file ready."
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="<NAME>"
    # shellcheck disable=SC2034
    UNINSTALL_SYSTEMD="container-<slug>.service" 
    # shellcheck disable=SC2034
    UNINSTALL_CONTAINERS=("<main_container>")
    UNINSTALL_VOLUMES=("<array_volumenes_persistentes>")
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/<slug>}"
    if [ -f "$dir/.env" ] && podman container exists <main_container> 2>/dev/null; then
        return 0
    fi
    return 1
}

deploy_and_persist() {
    log "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    
    podman-compose config >/dev/null 2>&1 || { err "Sintaxis de docker-compose invalida. Abortando instalación."; exit 1; }
    
    log "Extrayendo imágenes de contenedor..."
    if ! podman-compose pull > "$INSTALL_DIR/install.log" 2>&1; then
        err "Fallo al descargar imágenes. Posible Tag inexistente o error de red. Revisa $INSTALL_DIR/install.log"
        read -rp " ¿Deseas sustituir dinámicamente todos los tags por 'latest' e intentar de nuevo? [y/N]: " FIX_TAGS
        if [[ "$FIX_TAGS" =~ ^[Yy]$ ]]; then
            log "Parcheando tags a 'latest' en docker-compose.yml..."
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null || { err "Fallo crítico repetido al probar con latest."; exit 1; }
        else
            err "Lanza la actualización manualmente para depurar el error."
            exit 1
        fi
    fi
    
    # Pre-cleanup to avoid "name already in use" errors on retries
    podman-compose down 2>/dev/null || true
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running <tus_contenedores_aqui>
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
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

prepare_directories() {
    log "Preparing data directories..."
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    # Ensure containers can always write to these folders even in complex rootless mappings
    # sudo chown -R "${PUID:-$UID}:${PGID:-$UID}" "$INSTALL_DIR/data"
    log "Directories ready."
}

# -----------------------------------------------------------------------------
# REQUIRED ACTIONS
# -----------------------------------------------------------------------------
do_install() {
    # Development Mode: Use local files if LIB_LOCAL is active
    if [ -z "${LIB_LOCAL:-}" ]; then
        download_repo_files "$REPO_RAW" config.env docker-compose.yml
    else
        log "[DEV] LIB_LOCAL detected. Using local project files."
        TMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TMP_DIR"' EXIT
        
        local SCRIPT_DIR REPO_ROOT
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_ROOT="$(cd "$(dirname "$LIB_LOCAL")/.." && pwd)"
        
        if [ -f "$SCRIPT_DIR/config.env" ]; then
            cp "$SCRIPT_DIR/config.env" "$SCRIPT_DIR/docker-compose.yml" "$TMP_DIR/"
        elif [ -f "$REPO_ROOT/projects/<slug>/config.env" ]; then
            cp "$REPO_ROOT/projects/<slug>/config.env" "$REPO_ROOT/projects/<slug>/docker-compose.yml" "$TMP_DIR/"
        else
            err "Local files not found in $SCRIPT_DIR or $REPO_ROOT/projects/<slug>"
            exit 1
        fi
    fi

    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    assign_project_ip
    
    prepare_directories
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"
    print_success
}

do_start() { systemctl --user start container-<slug>.service; }

do_update() {
    # Development Mode: Use local files if LIB_LOCAL is active
    if [ -z "${LIB_LOCAL:-}" ]; then
        download_repo_files "$REPO_RAW" config.env docker-compose.yml
    else
        log "[DEV] LIB_LOCAL detected. Using local project files."
        TMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TMP_DIR"' EXIT
        
        local SCRIPT_DIR REPO_ROOT
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_ROOT="$(cd "$(dirname "$LIB_LOCAL")/.." && pwd)"
        
        if [ -f "$SCRIPT_DIR/config.env" ]; then
            cp "$SCRIPT_DIR/config.env" "$SCRIPT_DIR/docker-compose.yml" "$TMP_DIR/"
        elif [ -f "$REPO_ROOT/projects/<slug>/config.env" ]; then
            cp "$REPO_ROOT/projects/<slug>/config.env" "$REPO_ROOT/projects/<slug>/docker-compose.yml" "$TMP_DIR/"
        else
            err "Local files not found in $SCRIPT_DIR or $REPO_ROOT/projects/<slug>"
            exit 1
        fi
    fi

    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    
    # Preserve PROJECT_IP from existing .env if it exists
    if [ -f "$INSTALL_DIR/.env" ]; then
        PROJECT_IP=$(grep "^PROJECT_IP=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | head -1)
    else
        assign_project_ip
    fi

    prepare_directories
    generate_runtime_env
    
    cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"
    print_success
}

# -----------------------------------------------------------------------------
# MAIN LOOP ENTRY POINT
# -----------------------------------------------------------------------------
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
        echo " Existing installation detected at /opt/<slug>"
        echo ""
        echo "   1) Start      — Start the existing container"
        echo "   2) Update     — Download latest config and redeploy"
        echo "   3) Uninstall  — Remove container, service, and data"
        echo "   0) Cancel"
        echo ""
        read -rp " Select [0-3]: " ACTION

        case "$ACTION" in
            1) do_start ;;
            2) do_update ;;
            3) do_uninstall ;;
            0) log "Cancelled."; exit 0 ;;
            *) err "Invalid option."; exit 1 ;;
        esac
    else
        log "Existing installation detected. Running update..."
        do_update
    fi
else
    do_install
fi
```

**DOCKER-COMPOSE.YML (Networking Pattern):**
```yaml
services:
  main-app:
    image: docker.io/library/${IMAGE_TAG}
    container_name: ${CONTAINER_NAME}
    networks:
      internal_net:
        ipv4_address: ${PROJECT_IP}

networks:
  internal_net:
    external: true
```

---
