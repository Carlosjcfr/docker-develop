#!/bin/bash
# =============================================================================
# ANYTYPE - Service Orchestrator (AIO Bundle)
# =============================================================================
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/anytype"

# =============================================================================
# SHARED LIBRARY (Development Mode Support)
# =============================================================================
if [[ -n "${LIB_LOCAL:-}" && -f "$LIB_LOCAL" ]]; then
    source "$LIB_LOCAL"
else
    source <(curl -fsSL "$REPO_BASE/lib/lib.sh")
fi

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/anytype}"
    ARCANE_ICON="${ARCANE_ICON:-si:anytype}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-Productivity}"
    IMAGE_TAG="${IMAGE_TAG:-grishy/any-sync-bundle:latest}"
    CONTAINER_NAME="${CONTAINER_NAME:-anytype}"
}

generate_runtime_env() {
    log "Generating runtime .env file..."
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177
    
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
PROJECT_IP="$PROJECT_IP"

# Service Configuration
IMAGE_TAG="$IMAGE_TAG"
CONTAINER_NAME="$CONTAINER_NAME"

# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
    log ".env file ready."
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/anytype}"
    UNINSTALL_SVC_NAME="Anytype"
    UNINSTALL_SYSTEMD="container-anytype.service" 
    UNINSTALL_CONTAINERS=("anytype")
    UNINSTALL_VOLUMES=("anytype_data" "anytype_etc") # Named if it was using named volumes, but we use bind
    UNINSTALL_DIRS=("$INSTALL_DIR/data" "$INSTALL_DIR/etc")
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/anytype}"
    if [ -f "$dir/.env" ] && podman container exists anytype 2>/dev/null; then
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
        err "Fallo al descargar imágenes. Revisa $INSTALL_DIR/install.log"
        read -rp " ¿Deseas sustituir dinámicamente todos los tags por 'latest' e intentar de nuevo? [y/N]: " FIX_TAGS
        if [[ "$FIX_TAGS" =~ ^[Yy]$ ]]; then
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null || { err "Fallo crítico repetido al probar con latest."; exit 1; }
        else
            exit 1
        fi
    fi
    
    podman-compose down 2>/dev/null || true
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running "anytype"
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-anytype.service
[Unit]
Description=Anytype Stack (podman-compose)
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
    systemctl --user enable --now container-anytype.service
}

print_success() {
    echo "================================================================="
    echo " Anytype deployed and secured with systemd."
    echo " IP: $PROJECT_IP"
    echo " HOST Entry: $HOST_IP"
    echo ""
    echo " IMPORTANT: To configure your client:"
    echo " 1. Download the config from: $INSTALL_DIR/etc/client-config.yml"
    echo " 2. Upload it to your Anytype app (Settings -> Network -> Self-hosted)"
    echo "================================================================="
}

prepare_directories() {
    log "Preparing data directories..."
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/etc"
    sudo chown -R "${PUID:-$UID}:${PGID:-$UID}" "$INSTALL_DIR/data" "$INSTALL_DIR/etc"
    log "Directories ready."
}

do_install() {
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
        elif [ -f "$REPO_ROOT/projects/anytype/config.env" ]; then
            cp "$REPO_ROOT/projects/anytype/config.env" "$REPO_ROOT/projects/anytype/docker-compose.yml" "$TMP_DIR/"
        else
            err "Local files not found."
            exit 1
        fi
    fi

    load_configuration; detect_host_ip
    setup_lingering_and_socket
    assign_project_ip
    prepare_directories
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "anytype" "$INSTALL_DIR"
    print_success
}

do_start() {
    systemctl --user start container-anytype.service
}

do_update() {
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
        elif [ -f "$REPO_ROOT/projects/anytype/config.env" ]; then
            cp "$REPO_ROOT/projects/anytype/config.env" "$REPO_ROOT/projects/anytype/docker-compose.yml" "$TMP_DIR/"
        else
            err "Local files not found."
            exit 1
        fi
    fi

    load_configuration; detect_host_ip
    setup_lingering_and_socket
    
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
    register_arcane_project "anytype" "$INSTALL_DIR"
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

if check_existing_installation "/opt/anytype"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " Anytype — Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/anytype"
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
        do_update
    fi
else
    do_install
fi
