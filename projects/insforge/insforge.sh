#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/insforge"
# shellcheck source=lib.sh
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/insforge}"
    # Inicializa tus variables personalizadas aquí
    ARCANE_ICON="${ARCANE_ICON:-si:insomnia}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-Development}"

    INSFORGE_PORT="${INSFORGE_PORT:-7130}"
    INSFORGE_UI_PORT="${INSFORGE_UI_PORT:-7131}"
    INSFORGE_AUTH_PORT="${INSFORGE_AUTH_PORT:-7132}"
    POSTGREST_PORT="${POSTGREST_PORT:-5430}"
    DENO_PORT="${DENO_PORT:-7133}"

    INSFORGE_VERSION="${INSFORGE_VERSION:-v1.5.0}"
    POSTGRES_VERSION="${POSTGRES_VERSION:-latest}"
    POSTGREST_VERSION="${POSTGREST_VERSION:-v12.2.12}"
    DENO_VERSION="${DENO_VERSION:-latest}"

    if [ -f "$INSTALL_DIR/.env" ]; then
        # shellcheck source=/dev/null
        source "$INSTALL_DIR/.env"
    fi
}

generate_runtime_env() {
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
# Ports
INSFORGE_PORT="$INSFORGE_PORT"
INSFORGE_UI_PORT="$INSFORGE_UI_PORT"
INSFORGE_AUTH_PORT="$INSFORGE_AUTH_PORT"
POSTGREST_PORT="$POSTGREST_PORT"
DENO_PORT="$DENO_PORT"
# Versions
INSFORGE_VERSION="$INSFORGE_VERSION"
POSTGRES_VERSION="$POSTGRES_VERSION"
POSTGREST_VERSION="$POSTGREST_VERSION"
DENO_VERSION="$DENO_VERSION"
# Credentials
ADMIN_EMAIL="$ADMIN_EMAIL"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
POSTGRES_USER="$POSTGRES_USER"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
POSTGRES_DB="$POSTGRES_DB"
JWT_SECRET="$JWT_SECRET"
ENCRYPTION_KEY="$ENCRYPTION_KEY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/insforge}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="Insforge"
    # shellcheck disable=SC2034
    UNINSTALL_SYSTEMD="container-insforge.service" 
    # shellcheck disable=SC2034
    UNINSTALL_CONTAINERS=("insforge-app" "insforge-db" "insforge-postgrest" "insforge-deno")
    
    # NOTE: UNINSTALL_IMAGES array is only for static fallback.
    # The engine now automatically discovers images from docker-compose.yml.
    # shellcheck disable=SC2034
    UNINSTALL_IMAGES=("ghcr.io/insforge/insforge-oss:v1.5.0" "ghcr.io/insforge/postgres-all:latest" "postgrest/postgrest:v12.2.12" "ghcr.io/insforge/deno-runtime:latest")
    
    # shellcheck disable=SC2034
    UNINSTALL_VOLUMES=("insforge_postgres-data" "insforge_deno_cache" "insforge_storage-data" "insforge_insforge-logs")
    # shellcheck disable=SC2034
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/insforge}"
    if [ -f "$dir/.env" ] && podman container exists insforge-app 2>/dev/null; then
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
    
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running insforge-app insforge-db insforge-postgrest insforge-deno
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-insforge.service
[Unit]
Description=Insforge Stack (podman-compose)
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
    systemctl --user enable --now container-insforge.service
}

print_success() {
    echo "================================================================="
    echo " Insforge deployed and secured with systemd."
    echo " URL: http://$HOST_IP:$INSFORGE_PORT"
    echo "================================================================="
}

# -----------------------------------------------------------------------------
# REQUIRED ACTIONS (Añade el bloque completo para install/start/update)
# -----------------------------------------------------------------------------
do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    
    manage_credentials "$INSTALL_DIR" ADMIN_PASSWORD
    manage_credentials "$INSTALL_DIR" POSTGRES_PASSWORD
    manage_credentials "$INSTALL_DIR" JWT_SECRET
    manage_credentials "$INSTALL_DIR" ENCRYPTION_KEY
    
    setup_lingering_and_socket
    
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "insforge" "$INSTALL_DIR"
    print_success
}

do_start() {
    systemctl --user start container-insforge.service
}

do_update() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    
    generate_runtime_env
    
    cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    deploy_and_persist
    register_arcane_project "insforge" "$INSTALL_DIR"
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

if check_existing_installation "/opt/insforge"; then
    echo "1) Start 2) Update 3) Uninstall"
    read -rp " Select [1-3]: " ACTION
    case "$ACTION" in
        1) do_start ;; 2) do_update ;; 3) do_uninstall ;; *) exit 0 ;;
    esac
else
    do_install
fi
