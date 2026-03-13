#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/airtable"
# shellcheck source=lib.sh
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/airtable}"
    # Initialize variables
    ARCANE_ICON="${ARCANE_ICON:-si:airtable}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-Productivity}"
    AIRTABLE_PORT="${AIRTABLE_PORT:-8081}"
}

generate_runtime_env() {
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177
    cat <<EOF > "$INSTALL_DIR/.env"
# Base info
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
PROJECT_IP="$PROJECT_IP"

# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"

# APITable Infrastructure
TIMEZONE="$TIMEZONE"
ENV="$ENV"
AIRTABLE_PORT="$AIRTABLE_PORT"
APITABLE_REGISTRY="$APITABLE_REGISTRY"
APITABLE_VERSION="$APITABLE_VERSION"

# Images
IMAGE_MINIO="$IMAGE_MINIO"
IMAGE_REDIS="$IMAGE_REDIS"
IMAGE_MYSQL="$IMAGE_MYSQL"
IMAGE_RABBITMQ="$IMAGE_RABBITMQ"

# Secrets
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
MYSQL_DATABASE="$MYSQL_DATABASE"
MYSQL_USER="root"
MYSQL_PASSWORD="$MYSQL_ROOT_PASSWORD"
MYSQL_HOST="airtable-mysql"

REDIS_PASSWORD="$REDIS_PASSWORD"
REDIS_HOST="airtable-redis"

MINIO_ACCESS_KEY="$MINIO_ACCESS_KEY"
MINIO_SECRET_KEY="$MINIO_SECRET_KEY"
MINIO_ENDPOINT="http://airtable-minio:9000"

RABBITMQ_USERNAME="$RABBITMQ_USERNAME"
RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD"
RABBITMQ_HOST="airtable-rabbitmq"

# Internal URLs
DATABASE_TABLE_PREFIX="$DATABASE_TABLE_PREFIX"
API_MAX_MODIFY_RECORD_COUNTS="$API_MAX_MODIFY_RECORD_COUNTS"
INSTANCE_MAX_MEMORY="$INSTANCE_MAX_MEMORY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/airtable}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="Airtable"
    # shellcheck disable=SC2034
    UNINSTALL_SYSTEMD="container-airtable.service" 
    # shellcheck disable=SC2034
    UNINSTALL_CONTAINERS=("airtable-gateway" "airtable-web" "airtable-backend" "airtable-room" "airtable-databus" "airtable-imageproxy" "airtable-minio" "airtable-redis" "airtable-mysql" "airtable-rabbitmq")
    
    # shellcheck disable=SC2034
    UNINSTALL_VOLUMES=("airtable_default")
    # shellcheck disable=SC2034
    UNINSTALL_DIRS=("$INSTALL_DIR/data")
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/airtable}"
    if [ -f "$dir/.env" ] && podman container exists airtable-gateway 2>/dev/null; then
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
            log "Parcheando tags a 'latest' en docker-compose.yml..."
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null || { err "Fallo crítico repetido al probar con latest."; exit 1; }
        else
            exit 1
        fi
    fi
    
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running "airtable-gateway" "airtable-backend" "airtable-mysql" "airtable-redis"
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-airtable.service
[Unit]
Description=Airtable (APITable) Stack
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=$(command -v podman-compose) up -d
ExecStop=$(command -v podman-compose) down
TimeoutStartSec=300
TimeoutStopSec=60
[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now container-airtable.service
}

print_success() {
    echo "================================================================="
    echo " Airtable (APITable) deployed and secured with systemd."
    echo " URL: http://$HOST_IP:$AIRTABLE_PORT"
    echo "================================================================="
}

do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    
    # Secret generation
    manage_credentials "$INSTALL_DIR" MYSQL_ROOT_PASSWORD
    manage_credentials "$INSTALL_DIR" REDIS_PASSWORD
    manage_credentials "$INSTALL_DIR" MINIO_ACCESS_KEY
    manage_credentials "$INSTALL_DIR" MINIO_SECRET_KEY
    manage_credentials "$INSTALL_DIR" RABBITMQ_USERNAME
    manage_credentials "$INSTALL_DIR" RABBITMQ_PASSWORD

    setup_lingering_and_socket
    assign_project_ip
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/data/mysql" "$INSTALL_DIR/data/minio" "$INSTALL_DIR/data/redis" "$INSTALL_DIR/data/rabbitmq"
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "airtable" "$INSTALL_DIR"
    print_success
}

do_start() {
    systemctl --user start container-airtable.service
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
    register_arcane_project "airtable" "$INSTALL_DIR"
    print_success
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

if check_existing_installation "/opt/airtable"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " Airtable — Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/airtable"
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
