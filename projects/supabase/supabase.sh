#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/supabase"
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"
    
    STUDIO_PORT="${STUDIO_PORT:-3000}"
    KONG_PORT="${KONG_PORT:-8000}"
    POSTGRES_PORT="${POSTGRES_PORT:-5432}"

    POSTGRES_VERSION="${POSTGRES_VERSION:-15.6.1.111}"
    STUDIO_VERSION="${STUDIO_VERSION:-20240409-bf25a81}"
    KONG_VERSION="${KONG_VERSION:-2.8.1}"
    GOTRUE_VERSION="${GOTRUE_VERSION:-v2.158.1}"
    POSTGREST_VERSION="${POSTGREST_VERSION:-v12.2.0}"
    REALTIME_VERSION="${REALTIME_VERSION:-v2.33.44}"
    META_VERSION="${META_VERSION:-v0.83.2}"
    STORAGE_VERSION="${STORAGE_VERSION:-v1.11.13}"

    GOTRUE_DB_DRIVER="${GOTRUE_DB_DRIVER:-postgres}"
    JWT_EXPIRY="${JWT_EXPIRY:-3600}"
}

generate_runtime_env() {
    local OLD_UMASK=$(umask); umask 177

    # Ensure mandatory credentials exist
    manage_credentials "$INSTALL_DIR" POSTGRES_PASSWORD JWT_SECRET SECRET_KEY_BASE

    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"

STUDIO_PORT="$STUDIO_PORT"
KONG_PORT="$KONG_PORT"
POSTGRES_PORT="$POSTGRES_PORT"

POSTGRES_PASSWORD="$POSTGRES_PASSWORD"
JWT_SECRET="$JWT_SECRET"
SECRET_KEY_BASE="$SECRET_KEY_BASE"

POSTGRES_VERSION="$POSTGRES_VERSION"
STUDIO_VERSION="$STUDIO_VERSION"
KONG_VERSION="$KONG_VERSION"
GOTRUE_VERSION="$GOTRUE_VERSION"
POSTGREST_VERSION="$POSTGREST_VERSION"
REALTIME_VERSION="$REALTIME_VERSION"
META_VERSION="$META_VERSION"
STORAGE_VERSION="$STORAGE_VERSION"
GOTRUE_DB_DRIVER="$GOTRUE_DB_DRIVER"
JWT_EXPIRY="$JWT_EXPIRY"
EOF
    umask "$OLD_UMASK"

    # Generate mandatory Kong manifest for Supabase statically (always overwrite to keep in sync)
    cat <<EOF > "$INSTALL_DIR/kong.yml"
_format_version: "2.1"
_transform: true
services:
  - name: auth
    url: http://auth:9999
    routes:
      - name: auth-route
        paths:
          - /auth/v1
  - name: rest
    url: http://rest:3000
    routes:
      - name: rest-route
        paths:
          - /rest/v1
  - name: storage
    url: http://storage:5000
    routes:
      - name: storage-route
        paths:
          - /storage/v1
  - name: realtime
    url: http://realtime:4000
    routes:
      - name: realtime-route
        paths:
          - /realtime/v1
EOF
}

deploy_and_persist() {
    log "Starting services with podman-compose..."
    cd "$INSTALL_DIR"

    log "Downloading official Supabase initialization SQL volumes..."
    mkdir -p "$INSTALL_DIR/volumes/db"
    local raw_base="https://raw.githubusercontent.com/supabase/supabase/master/docker/volumes/db"
    for sql_file in realtime.sql webhooks.sql roles.sql jwt.sql _supabase.sql logs.sql pooler.sql; do
        if [ ! -f "$INSTALL_DIR/volumes/db/$sql_file" ]; then
            curl -sSL "$raw_base/$sql_file" -o "$INSTALL_DIR/volumes/db/$sql_file" || err "Failed to download $sql_file from the official repository."
        fi
    done

    log "Patching SQL scripts (Preventing psql expansion failures in rootless)..."
    sed -i "s|\\\\set pgpass \`echo \"\$POSTGRES_PASSWORD\"\`|\\\\set pgpass '${POSTGRES_PASSWORD}'|g" "$INSTALL_DIR/volumes/db/roles.sql"
    sed -i "s|\\\\set jwt_secret \`echo \"\$JWT_SECRET\"\`|\\\\set jwt_secret '${JWT_SECRET}'|g" "$INSTALL_DIR/volumes/db/jwt.sql"
    sed -i "s|\\\\set jwt_exp \`echo \"\$JWT_EXP\"\`|\\\\set jwt_exp '${JWT_EXPIRY}'|g" "$INSTALL_DIR/volumes/db/jwt.sql"

    podman-compose config > /dev/null 2>&1 || { err "Invalid docker-compose syntax. Aborting installation."; exit 1; }

    log "Pulling container images (this process is silent and may take a while)..."
    if ! podman-compose pull > /dev/null 2>&1; then
        err "Failed to download images. Possible non-existent tag or network error."
        read -rp " Do you want to dynamically replace all tags with 'latest' and try again? [y/N]: " FIX_TAGS
        if [[ "$FIX_TAGS" =~ ^[Yy]$ ]]; then
            log "Patching tags to 'latest' in docker-compose.yml..."
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null 2>&1 || { err "Repeated critical failure when testing with latest."; exit 1; }
        else
            err "Run the update manually to debug the error."
            exit 1
        fi
    fi

    log "Starting containers..."
    podman-compose up -d > /dev/null 2>&1

    verify_containers_running "supabase-db" "supabase-studio" "supabase-kong" "supabase-auth" "supabase-rest" "supabase-realtime" "supabase-meta" "supabase-storage"

    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true

    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/

    cat <<EOF > ~/.config/systemd/user/container-supabase.service
[Unit]
Description=Supabase Stack (podman-compose)
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
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now container-supabase.service
}

print_success() {
    echo ""
    echo "================================================================="
    echo " SUPABASE deployed and secured with systemd."
    echo " Studio: http://$HOST_IP:$STUDIO_PORT"
    echo " API:    http://$HOST_IP:$KONG_PORT"
    echo " DB:     $HOST_IP:$POSTGRES_PORT"
    echo ""
    echo " The containers will persist after logout and on VM reboots."
    echo "================================================================="
}

do_install() {
    echo ""
    echo "=== SUPABASE: Fresh Installation ==="
    echo ""

    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode
    load_configuration
    detect_host_ip
    setup_lingering_and_socket

    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    generate_runtime_env
    deploy_and_persist
    print_success
}

do_start() {
    echo "=== SUPABASE: Starting ==="
    systemctl --user start container-supabase.service
    log "Supabase started successfully."
}

do_update() {
    echo "=== SUPABASE: Updating ==="
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode
    load_configuration
    detect_host_ip
    setup_lingering_and_socket

    generate_runtime_env

    cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true

    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    deploy_and_persist
    print_success
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"
    UNINSTALL_SVC_NAME="Supabase"
    UNINSTALL_SYSTEMD="container-supabase.service" 
    UNINSTALL_CONTAINERS=("supabase-db" "supabase-studio" "supabase-kong" "supabase-auth" "supabase-rest" "supabase-realtime" "supabase-meta" "supabase-storage")
    
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cd "$INSTALL_DIR"
        UNINSTALL_IMAGES=($(podman-compose config | grep 'image:' | awk '{print $2}' || true))
        cd - >/dev/null
    else
        UNINSTALL_IMAGES=("docker.io/supabase/postgres:\${POSTGRES_VERSION}" "docker.io/supabase/studio:\${STUDIO_VERSION}" "docker.io/library/kong:\${KONG_VERSION}" "docker.io/supabase/gotrue:\${GOTRUE_VERSION}" "docker.io/postgrest/postgrest:\${POSTGREST_VERSION}" "docker.io/supabase/realtime:\${REALTIME_VERSION}" "docker.io/supabase/postgres-meta:\${META_VERSION}" "docker.io/supabase/storage-api:\${STORAGE_VERSION}")
    fi
    UNINSTALL_VOLUMES=("supabase_db_data" "supabase_storage_data")
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/supabase}"
    if [ -f "$dir/.env" ] && podman container exists supabase-db 2>/dev/null; then
        return 0
    fi
    return 1
}

# =============================================================================
# MAIN
# =============================================================================
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

if check_existing_installation "/opt/supabase"; then
    if [ -t 0 ] && [ "${FORCE_YES:-0}" -eq 0 ]; then
        echo ""
        echo "================================================================="
        echo " SUPABASE — Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/supabase"
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
