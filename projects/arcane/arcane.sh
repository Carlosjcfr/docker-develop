#!/bin/bash
set -euo pipefail

# ==============================================================================
# ARCANE - Management Script
# Single entry point for installing, starting, updating, and uninstalling Arcane.
#
# Usage:
#   bash arcane.sh                                (local, interactive)
#   curl -fsSL <raw_url>/arcane.sh | bash          (remote, automatic)
#
# Re-running this script on an existing installation is safe.
# ==============================================================================

REPO_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane"

# =============================================================================
# SHARED FUNCTIONS
# =============================================================================

root_protection() {
    if [[ $EUID -eq 0 ]]; then
        echo "-----------------------------------------------------------------"
        echo " ERROR: DO NOT RUN THIS SCRIPT WITH SUDO"
        echo "-----------------------------------------------------------------"
        echo " To maintain a Rootless Podman installation, this script must be"
        echo " executed as a normal user."
        echo ""
        echo " PLEASE RETRY WITH: bash arcane.sh"
        echo "-----------------------------------------------------------------"
        exit 1
    fi
}

check_dependencies() {
    for cmd in curl podman-compose; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "ERROR: '$cmd' not found. Please install it before continuing." >&2
            exit 1
        fi
    done
}

# Returns 0 if an existing Arcane installation is detected, 1 otherwise.
check_existing_installation() {
    local dir="${1:-/opt/arcane}"
    if [ -f "$dir/.env" ] && podman container exists arcane 2>/dev/null; then
        return 0
    fi
    return 1
}

download_repo_files() {
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    echo "Downloading files from repository..."
    curl -fsSL "$REPO_RAW/config.env"         -o "$TMP_DIR/config.env"
    curl -fsSL "$REPO_RAW/docker-compose.yml" -o "$TMP_DIR/docker-compose.yml"
    echo "Files downloaded."
}

offer_interactive_mode() {
    if [ -t 0 ]; then
        echo ""
        read -rp "Run in interactive mode? (customize all options) [y/N]: " INTERACTIVE
        if [[ "$INTERACTIVE" =~ ^[Yy]$ ]]; then
            echo "Downloading interactive configurator..."
            curl -fsSL "$REPO_RAW/configure.sh" -o "$TMP_DIR/configure.sh"
            bash "$TMP_DIR/configure.sh" "$TMP_DIR/config.env"
        fi
    fi
}

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"

    # Security check: abort if someone accidentally added secrets to config.env
    for FORBIDDEN_VAR in ENCRYPTION_KEY JWT_SECRET; do
        if grep -q "^${FORBIDDEN_VAR}=" "$TMP_DIR/config.env"; then
            echo "-----------------------------------------------------------------"
            echo " ERROR: SECRET DETECTED IN config.env"
            echo "-----------------------------------------------------------------"
            echo " '$FORBIDDEN_VAR' must NEVER be stored in the repository."
            echo " Remove it from config.env — secrets are auto-generated."
            echo "-----------------------------------------------------------------"
            exit 1
        fi
    done

    # Apply defaults for any variable left empty or unset
    INSTALL_DIR="${INSTALL_DIR:-/opt/arcane}"
    APP_PORT="${APP_PORT:-3552}"
    PACKAGE_VERSION="${PACKAGE_VERSION:-latest}"
    LOG_LEVEL="${LOG_LEVEL:-info}"
    ENVIRONMENT="${ENVIRONMENT:-production}"
    GIN_MODE="${GIN_MODE:-release}"
    TZ="${TZ:-UTC}"
    DATABASE_URL="${DATABASE_URL:-file:data/arcane.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate}"
    ALLOW_DOWNGRADE="${ALLOW_DOWNGRADE:-false}"
    JWT_REFRESH_EXPIRY="${JWT_REFRESH_EXPIRY:-168h}"
    FILE_PERM="${FILE_PERM:-0644}"
    DIR_PERM="${DIR_PERM:-0755}"
    TLS_ENABLED="${TLS_ENABLED:-false}"
    TLS_CERT_FILE="${TLS_CERT_FILE:-}"
    TLS_KEY_FILE="${TLS_KEY_FILE:-}"
    AGENT_MODE="${AGENT_MODE:-false}"
    AGENT_TOKEN="${AGENT_TOKEN:-}"

    echo "Configuration loaded (INSTALL_DIR=$INSTALL_DIR, APP_PORT=$APP_PORT)."
}

detect_host_ip() {
    if [ -z "${HOST_IP:-}" ]; then
        INTERFACE=$(ip route | awk '/^default/ {print $5; exit}')
        HOST_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

        if [ -z "$HOST_IP" ]; then
            echo "ERROR: Could not determine the host IP address." >&2
            echo "       Set HOST_IP in config.env (repo) and retry." >&2
            exit 1
        fi
        echo "Host IP auto-detected: $HOST_IP"
    else
        echo "Host IP from config.env: $HOST_IP"
    fi
}

manage_credentials() {
    if [ -f "$INSTALL_DIR/.env" ] && grep -q "^ENCRYPTION_KEY=" "$INSTALL_DIR/.env"; then
        echo "Existing secrets found. Reusing..."
        ENCRYPTION_KEY=$(grep "^ENCRYPTION_KEY=" "$INSTALL_DIR/.env" | cut -d '=' -f2-)
        JWT_SECRET=$(grep "^JWT_SECRET=" "$INSTALL_DIR/.env"          | cut -d '=' -f2-)
    else
        echo "First run detected. Generating secure encryption keys..."
        set +o pipefail
        ENCRYPTION_KEY=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
        JWT_SECRET=$(tr -dc 'a-f0-9'     </dev/urandom | head -c 64)
        set -o pipefail
    fi
}

setup_lingering_and_socket() {
    PUID=$(id -u)
    PGID=$(id -g)
    USER_NAME=$(id -un)

    echo "Ensuring user lingering is enabled..."
    sudo loginctl enable-linger "$USER_NAME"

    PODMAN_SOCK="/run/user/${PUID}/podman/podman.sock"

    if [ ! -S "$PODMAN_SOCK" ]; then
        echo "Podman socket not found. Attempting to enable and start it..."
        systemctl --user enable --now podman.socket 2>/dev/null || true
        for i in $(seq 1 10); do
            [ -S "$PODMAN_SOCK" ] && break
            sleep 1
        done
        if [ ! -S "$PODMAN_SOCK" ]; then
            echo "ERROR: Could not start Podman socket at $PODMAN_SOCK" >&2
            exit 1
        fi
        echo "Podman socket ready."
    fi
}

generate_runtime_env() {
    echo "Generating runtime .env file..."
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177

    cat <<EOF > "$INSTALL_DIR/.env"
# =============================================================================
# ARCANE - Runtime Environment Variables
# Auto-generated by arcane.sh — do NOT edit manually.
# To change settings, edit config.env in the repository and re-run arcane.sh.
# =============================================================================

# --- Core (auto-generated) ---
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
APP_PORT="$APP_PORT"
APP_URL="http://$HOST_IP:$APP_PORT"
PODMAN_SOCK="$PODMAN_SOCK"
ENCRYPTION_KEY="$ENCRYPTION_KEY"
JWT_SECRET="$JWT_SECRET"

# --- Application (from config.env) ---
PACKAGE_VERSION="$PACKAGE_VERSION"
ENVIRONMENT="$ENVIRONMENT"
GIN_MODE="$GIN_MODE"
LOG_LEVEL="$LOG_LEVEL"
TZ="$TZ"

# --- Database ---
DATABASE_URL="$DATABASE_URL"
ALLOW_DOWNGRADE="$ALLOW_DOWNGRADE"

# --- Security ---
JWT_REFRESH_EXPIRY="$JWT_REFRESH_EXPIRY"
FILE_PERM="$FILE_PERM"
DIR_PERM="$DIR_PERM"

# --- TLS ---
TLS_ENABLED="$TLS_ENABLED"
TLS_CERT_FILE="$TLS_CERT_FILE"
TLS_KEY_FILE="$TLS_KEY_FILE"

# --- Agent ---
AGENT_MODE="$AGENT_MODE"
AGENT_TOKEN="$AGENT_TOKEN"
EOF

    umask "$OLD_UMASK"
    echo ".env file ready (permissions 600)."
}

prepare_directories() {
    echo "Preparing data directories..."
    mkdir -p "$INSTALL_DIR" "${INSTALL_DIR}/data" "${INSTALL_DIR}/projects"
    sudo chown -R "${PUID}:${PGID}" "${INSTALL_DIR}/data" "${INSTALL_DIR}/projects"
    echo "Directories ready."
}

deploy_and_persist() {
    echo "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    podman-compose up -d

    echo "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/

    # Generate systemd unit in the current directory, then move it.
    # Uses --new to recreate the container from the image on each service start.
    # Compatible with Podman 4.x (no --dest or --restart-policy flags).
    podman generate systemd --name arcane --files --new
    mv -f container-arcane.service ~/.config/systemd/user/

    # Ensure the service restarts on failure via systemd override
    mkdir -p ~/.config/systemd/user/container-arcane.service.d
    cat <<EOF > ~/.config/systemd/user/container-arcane.service.d/restart.conf
[Service]
Restart=always
RestartSec=10
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now container-arcane.service
}

print_success() {
    echo ""
    echo "================================================================="
    echo " ARCANE deployed and secured with systemd."
    echo " Access it at: http://$HOST_IP:$APP_PORT"
    echo ""
    echo " The container will now persist after logout and on VM reboots."
    echo ""
    echo " Useful commands:"
    echo "   Status:  systemctl --user status container-arcane.service"
    echo "   Logs:    podman logs -f arcane"
    echo "   Restart: systemctl --user restart container-arcane.service"
    echo "================================================================="
}

# =============================================================================
# ACTIONS
# =============================================================================

do_install() {
    echo ""
    echo "=== ARCANE: Fresh Installation ==="
    echo ""

    download_repo_files
    offer_interactive_mode
    load_configuration
    detect_host_ip
    manage_credentials
    setup_lingering_and_socket
    prepare_directories

    # Move downloaded files into the install directory
    mv "$TMP_DIR/config.env"         "$INSTALL_DIR/config.env"
    mv "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    generate_runtime_env
    deploy_and_persist
    print_success
}

do_start() {
    echo ""
    echo "=== ARCANE: Starting ==="
    echo ""

    if systemctl --user is-active --quiet container-arcane.service 2>/dev/null; then
        echo "Arcane is already running."
    else
        systemctl --user start container-arcane.service
        echo "Arcane started successfully."
    fi

    # Load INSTALL_DIR and HOST_IP from existing .env for the status message
    if [ -f /opt/arcane/.env ]; then
        local ip port
        ip=$(grep "^HOST_IP=" /opt/arcane/.env | cut -d '=' -f2- || echo "unknown")
        port=$(grep "^APP_PORT=" /opt/arcane/.env | cut -d '=' -f2- || echo "3552")
        echo "Access it at: http://$ip:$port"
    fi
}

do_update() {
    echo ""
    echo "=== ARCANE: Updating ==="
    echo ""

    download_repo_files
    offer_interactive_mode
    load_configuration
    detect_host_ip
    manage_credentials
    setup_lingering_and_socket
    prepare_directories

    # Move downloaded files into the install directory
    mv "$TMP_DIR/config.env"         "$INSTALL_DIR/config.env"
    mv "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    generate_runtime_env

    # Pull latest image before redeploying
    echo "Pulling latest Arcane image..."
    cd "$INSTALL_DIR"
    podman-compose pull

    deploy_and_persist
    print_success
}

do_uninstall() {
    echo ""
    echo "=== ARCANE: Uninstall ==="
    echo ""
    echo " WARNING: This will permanently remove:"
    echo "   - The Arcane container and its image"
    echo "   - The systemd persistence service"
    echo ""

    # Double confirmation (mitigation for accidental selection)
    read -rp " Type 'UNINSTALL' to confirm: " CONFIRM
    if [ "$CONFIRM" != "UNINSTALL" ]; then
        echo "Uninstall cancelled."
        exit 0
    fi

    echo ""
    echo "Stopping Arcane container..."
    systemctl --user stop container-arcane.service 2>/dev/null || true
    systemctl --user disable container-arcane.service 2>/dev/null || true
    rm -f ~/.config/systemd/user/container-arcane.service
    systemctl --user daemon-reload

    echo "Removing container..."
    podman rm -f arcane 2>/dev/null || true

    echo "Removing Arcane image..."
    podman rmi "ghcr.io/getarcaneapp/arcane:${PACKAGE_VERSION:-latest}" 2>/dev/null || true

    # Ask about data removal
    echo ""
    read -rp " Also delete all data (/opt/arcane/data, /opt/arcane/projects)? [y/N]: " DELETE_DATA
    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        echo "Removing data directories..."
        rm -rf /opt/arcane/data /opt/arcane/projects
        echo "Data removed."
    else
        echo "Data preserved at /opt/arcane/data and /opt/arcane/projects."
    fi

    # Clean up config files but leave data if user chose to keep it
    rm -f /opt/arcane/.env /opt/arcane/config.env /opt/arcane/docker-compose.yml

    echo ""
    echo "================================================================="
    echo " ARCANE has been uninstalled."
    echo "================================================================="
}

# =============================================================================
# MAIN
# =============================================================================

root_protection
check_dependencies

# Detect existing installation (default path for quick check)
if check_existing_installation "/opt/arcane"; then
    if [ -t 0 ]; then
        # Interactive terminal → show management menu
        echo ""
        echo "================================================================="
        echo " ARCANE - Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/arcane"
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
            0) echo "Cancelled."; exit 0 ;;
            *) echo "Invalid option."; exit 1 ;;
        esac
    else
        # Non-interactive (curl | bash) → auto-update
        echo "Existing installation detected. Running automatic update..."
        do_update
    fi
else
    # No existing installation → fresh install
    do_install
fi
