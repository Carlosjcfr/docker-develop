#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/anytype"
# shellcheck source=lib.sh
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

# Versions
ANY_SYNC_BUNDLE_VERSION="$ANY_SYNC_BUNDLE_VERSION"
MONGO_VERSION="$MONGO_VERSION"
REDIS_VERSION="$REDIS_VERSION"

# Network
ANY_SYNC_DRPC_PORT="$ANY_SYNC_DRPC_PORT"
ANY_SYNC_QUIC_PORT="$ANY_SYNC_QUIC_PORT"
ANY_SYNC_INFO_PORT="$ANY_SYNC_INFO_PORT"

# Arcane
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/anytype}"
    UNINSTALL_SVC_NAME="AnyType"
    UNINSTALL_SYSTEMD="container-anytype.service" 
    UNINSTALL_CONTAINERS=("any-sync-bundle" "any-sync-mongo" "any-sync-redis")
    UNINSTALL_VOLUMES=()
    UNINSTALL_DIRS=("$INSTALL_DIR")
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/anytype}"
    if [ -f "$dir/.env" ] && podman container exists any-sync-bundle 2>/dev/null; then
        return 0
    fi
    return 1
}

deploy_and_persist() {
    log "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    
    # Ensure network exists (pre-flight check)
    podman network exists internal_net || podman network create --subnet 172.170.1.0/24 internal_net

    # Pre-cleanup to avoid "name already in use" errors on retries
    podman-compose down 2>/dev/null || true
    podman-compose up -d
    verify_containers_running "any-sync-bundle" "any-sync-mongo" "any-sync-redis"
    
    log "Configuring systemd service..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-anytype.service
[Unit]
Description=AnyType Stack (Community Bundle)
Wants=network-online.target
After=network-online.target

[Service]
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=$(command -v podman-compose) up -d
ExecStop=$(command -v podman-compose) down
TimeoutStartSec=300
[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now container-anytype.service
}

print_success() {
    echo "================================================================="
    echo " AnyType (Any-Sync Bundle) deployed successfully."
    echo " Access Dashboard at: http://$HOST_IP:$ANY_SYNC_INFO_PORT"
    echo ""
    echo " To connect your AnyType App:"
    echo " 1. Wait for the bundle to generate configs (check 'podman logs any-sync-bundle')"
    echo " 2. Locate the client configuration file at:"
    echo "    $INSTALL_DIR/etc/client.yml"
    echo " 3. Import this file into your AnyType desktop/mobile application."
    echo "================================================================="
}

do_install() {
    if [ -z "${LIB_LOCAL:-}" ]; then
        download_repo_files "$REPO_RAW" config.env docker-compose.yml
    else
        log "[DEV] LIB_LOCAL detected. Using local AnyType files."
        TMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TMP_DIR"' EXIT
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cp "$SCRIPT_DIR/config.env" "$SCRIPT_DIR/docker-compose.yml" "$TMP_DIR/"
    fi

    load_configuration; detect_host_ip
    setup_lingering_and_socket
    assign_project_ip
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/storage" "$INSTALL_DIR/etc"
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "anytype" "$INSTALL_DIR"
    print_success
}

do_start() { systemctl --user start container-anytype.service; }

do_update() {
    if [ -z "${LIB_LOCAL:-}" ]; then
        download_repo_files "$REPO_RAW" config.env docker-compose.yml
    else
        log "[DEV] LIB_LOCAL detected. Using local AnyType files."
        TMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TMP_DIR"' EXIT
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        cp "$SCRIPT_DIR/config.env" "$SCRIPT_DIR/docker-compose.yml" "$TMP_DIR/"
    fi

    load_configuration; detect_host_ip
    setup_lingering_and_socket
    
    # Preserve PROJECT_IP from existing .env if it exists
    if [ -f "$INSTALL_DIR/.env" ]; then
        PROJECT_IP=$(grep "^PROJECT_IP=" "$INSTALL_DIR/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'" | head -1)
    else
        assign_project_ip
    fi

    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "anytype" "$INSTALL_DIR"
    print_success
}

root_protection
check_dependencies curl podman-compose
parse_args "$@"

if [ -n "${CMD_ACTION:-}" ]; then
    case "$CMD_ACTION" in
        install) do_install ;;
        start) do_start ;;
        update) do_update ;;
        uninstall) do_uninstall ;;
        *) err "Invalid action."; exit 1 ;;
    esac
    exit 0
fi

if check_existing_installation "/opt/anytype"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " AnyType — Management"
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
        log "Existing installation detected. Running update..."
        do_update
    fi
else
    do_install
fi
