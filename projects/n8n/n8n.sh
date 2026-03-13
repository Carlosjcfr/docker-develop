#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/n8n"
# shellcheck source=lib.sh
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/n8n}"
    # Inicializa tus variables personalizadas aquí
    ARCANE_ICON="${ARCANE_ICON:-si:n8n}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-Automation}"
    POSTGRES_USER="${POSTGRES_USER:-n8n}"
    POSTGRES_DB="${POSTGRES_DB:-n8n}"
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
PROJECT_IP="$PROJECT_IP"

# Versions
N8N_VERSION="$N8N_VERSION"
POSTGRES_VERSION="$POSTGRES_VERSION"

# Database
POSTGRES_USER="$POSTGRES_USER"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
POSTGRES_DB="$POSTGRES_DB"

# n8n Core
N8N_PORT="$N8N_PORT"
N8N_ENCRYPTION_KEY="$N8N_ENCRYPTION_KEY"
N8N_USER_MANAGEMENT_JWT_SECRET="$N8N_USER_MANAGEMENT_JWT_SECRET"

# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/n8n}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="n8n"
    # shellcheck disable=SC2034
    UNINSTALL_SYSTEMD="container-n8n.service" 
    # shellcheck disable=SC2034
    UNINSTALL_CONTAINERS=("n8n" "n8n-db")
    
    # NOTE: UNINSTALL_IMAGES array is only for static fallback.
    # The engine now automatically discovers images from docker-compose.yml.
    # shellcheck disable=SC2034
    UNINSTALL_IMAGES=("docker.io/n8nio/n8n:latest" "docker.io/library/postgres:16-alpine")
    
    # shellcheck disable=SC2034
    UNINSTALL_VOLUMES=()
    # shellcheck disable=SC2034
    UNINSTALL_DIRS=("n8n_data" "db_data")
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/n8n}"
    if [ -f "$dir/.env" ] && podman container exists n8n 2>/dev/null; then
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
    verify_containers_running "n8n" "n8n-db"
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-n8n.service
[Unit]
Description=n8n Stack (podman-compose)
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
    systemctl --user enable --now container-n8n.service
}

print_success() {
    echo "================================================================="
    echo " n8n deployed and secured with systemd."
    echo " URL: http://$HOST_IP:$N8N_PORT"
    echo "================================================================="
}

# -----------------------------------------------------------------------------
# REQUIRED ACTIONS (Añade el bloque completo para install/start/update)
# -----------------------------------------------------------------------------
do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    
    manage_credentials "$INSTALL_DIR" POSTGRES_PASSWORD
    manage_credentials "$INSTALL_DIR" N8N_ENCRYPTION_KEY
    manage_credentials "$INSTALL_DIR" N8N_USER_MANAGEMENT_JWT_SECRET
    
    setup_lingering_and_socket
    assign_project_ip
    
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "n8n" "$INSTALL_DIR"
    print_success
}

do_start() {
    systemctl --user start container-n8n.service
}

do_update() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    
    # Preserve PROJECT_IP from existing .env if it exists
    if [ -f "$INSTALL_DIR/.env" ]; then
        PROJECT_IP=$(grep "^PROJECT_IP=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    else
        assign_project_ip
    fi
    
    generate_runtime_env
    
    cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    deploy_and_persist
    register_arcane_project "n8n" "$INSTALL_DIR"
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

if check_existing_installation "/opt/n8n"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " n8n — Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/n8n"
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
