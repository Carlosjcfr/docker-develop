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
}

generate_runtime_env() {
    local OLD_UMASK=$(umask); umask 177

    # Aseguramos de que las credenciales obligatorias existen
    manage_credentials "$INSTALL_DIR" POSTGRES_PASSWORD JWT_SECRET

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

POSTGRES_VERSION="$POSTGRES_VERSION"
STUDIO_VERSION="$STUDIO_VERSION"
KONG_VERSION="$KONG_VERSION"
GOTRUE_VERSION="$GOTRUE_VERSION"
POSTGREST_VERSION="$POSTGREST_VERSION"
REALTIME_VERSION="$REALTIME_VERSION"
META_VERSION="$META_VERSION"
STORAGE_VERSION="$STORAGE_VERSION"
EOF
    umask "$OLD_UMASK"

    # Generamos el manifiesto de Kong obligatorio para Supabase de forma estática
    if [ ! -f "$INSTALL_DIR/kong.yml" ]; then
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
EOF
    fi
}

verify_containers_running() { 
    verify_containers_in_list "supabase-db" "supabase-studio" "supabase-kong" "supabase-auth" "supabase-rest" "supabase-realtime" "supabase-meta" "supabase-storage"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"
    UNINSTALL_SVC_NAME="Supabase"
    UNINSTALL_SYSTEMD="container-supabase.service" 
    UNINSTALL_CONTAINERS=("supabase-db" "supabase-studio" "supabase-kong" "supabase-auth" "supabase-rest" "supabase-realtime" "supabase-meta" "supabase-storage")
    UNINSTALL_IMAGES=("docker.io/supabase/postgres:\${POSTGRES_VERSION}" "docker.io/supabase/studio:\${STUDIO_VERSION}" "docker.io/library/kong:\${KONG_VERSION}" "docker.io/supabase/gotrue:\${GOTRUE_VERSION}" "docker.io/postgrest/postgrest:\${POSTGREST_VERSION}" "docker.io/supabase/realtime:\${REALTIME_VERSION}" "docker.io/supabase/postgres-meta:\${META_VERSION}" "docker.io/supabase/storage-api:\${STORAGE_VERSION}")
    UNINSTALL_VOLUMES=("supabase_db_data" "supabase_storage_data")
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

root_protection
check_dependencies curl podman-compose
parse_args "$@"
