#!/bin/bash
set -euo pipefail

# ==============================================================================
# CADDY PROXY + MANAGER — Management Script
# Single entry point for installing, starting, updating, and uninstalling
# Caddy reverse proxy together with CaddyManager Web UI.
#
# Usage:
#   bash caddy.sh                                 (local, interactive)
#   curl -fsSL <raw_url>/caddy.sh | bash           (remote, automatic)
#
# Re-running this script on an existing installation is safe.
# ==============================================================================

REPO_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/caddy-manager-proxy/projects/caddy-proxy-manager"

# =============================================================================
# LOGGING
# Structured output with UTC timestamps and severity levels.
# err() and warn() write to stderr so they are always visible even when
# stdout is redirected (e.g. piped to tee or a log file).
# =============================================================================

log()  { echo "[$(date -u '+%H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] [WARN]  $*" >&2; }
err()  { echo "[$(date -u '+%H:%M:%S')] [ERROR] $*" >&2; }

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
        echo " PLEASE RETRY WITH: bash caddy.sh"
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

# Returns 0 if an existing installation is detected, 1 otherwise.
check_existing_installation() {
    local dir="${1:-/opt/caddy}"
    if [ -f "$dir/.env" ] && podman container exists caddy 2>/dev/null; then
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

    # Download Caddyfile only to tmp — will be placed only on first install
    curl -fsSL "$REPO_RAW/Caddyfile"           -o "$TMP_DIR/Caddyfile"

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
    if grep -q "^JWT_SECRET=" "$TMP_DIR/config.env"; then
        echo "-----------------------------------------------------------------"
        echo " ERROR: SECRET DETECTED IN config.env"
        echo "-----------------------------------------------------------------"
        echo " 'JWT_SECRET' must NEVER be stored in the repository."
        echo " Remove it from config.env — secrets are auto-generated."
        echo "-----------------------------------------------------------------"
        exit 1
    fi

    # Apply defaults for any variable left empty or unset
    INSTALL_DIR="${INSTALL_DIR:-/opt/caddy}"
    CADDY_VERSION="${CADDY_VERSION:-2.11-alpine}"
    ACME_EMAIL="${ACME_EMAIL:-you@example.com}"
    PACKAGE_VERSION="${PACKAGE_VERSION:-0.0.2}"
    CADDYMANAGER_UI_PORT="${CADDYMANAGER_UI_PORT:-8080}"
    APP_NAME="${APP_NAME:-Caddy Manager}"
    DARK_MODE="${DARK_MODE:-true}"
    BACKEND_PORT="${BACKEND_PORT:-3000}"
    DB_ENGINE="${DB_ENGINE:-sqlite}"
    JWT_EXPIRATION="${JWT_EXPIRATION:-24h}"
    LOG_LEVEL="${LOG_LEVEL:-info}"
    AUDIT_LOG_MAX_SIZE_MB="${AUDIT_LOG_MAX_SIZE_MB:-100}"
    AUDIT_LOG_RETENTION_DAYS="${AUDIT_LOG_RETENTION_DAYS:-90}"
    PING_INTERVAL="${PING_INTERVAL:-30000}"
    PING_TIMEOUT="${PING_TIMEOUT:-2000}"
    METRICS_HISTORY_MAX="${METRICS_HISTORY_MAX:-1000}"

    echo "Configuration loaded (INSTALL_DIR=$INSTALL_DIR, UI_PORT=$CADDYMANAGER_UI_PORT)."
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
    if [ -f "$INSTALL_DIR/.env" ] && grep -q "^JWT_SECRET=" "$INSTALL_DIR/.env"; then
        echo "Existing secrets found. Reusing..."
        JWT_SECRET=$(grep "^JWT_SECRET=" "$INSTALL_DIR/.env" | cut -d '=' -f2-)
    else
        echo "First run detected. Generating secure JWT secret..."
        set +o pipefail
        JWT_SECRET=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
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

# Enable unprivileged binding to ports 80 and 443.
# Podman rootless cannot bind to ports <1024 without this kernel parameter.
# This change persists across reboots via /etc/sysctl.d/.
enable_privileged_ports() {
    local CURRENT
    CURRENT=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo "1024")

    if [ "$CURRENT" -gt 0 ] 2>/dev/null; then
        echo "Enabling unprivileged binding to ports 80/443..."
        echo "  (requires sudo — current ip_unprivileged_port_start=$CURRENT)"

        # Apply immediately
        sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0 > /dev/null

        # Persist across reboots
        if [ ! -f /etc/sysctl.d/99-unprivileged-ports.conf ]; then
            echo "net.ipv4.ip_unprivileged_port_start=0" | sudo tee /etc/sysctl.d/99-unprivileged-ports.conf > /dev/null
            echo "  Persisted in /etc/sysctl.d/99-unprivileged-ports.conf"
        fi

        echo "  Ports 80/443 are now available for rootless containers."
    else
        echo "Unprivileged port binding already enabled."
    fi
}

generate_runtime_env() {
    echo "Generating runtime .env file..."
    local OLD_UMASK
    OLD_UMASK=$(umask)
    umask 177

    CORS_ORIGIN="http://$HOST_IP:$CADDYMANAGER_UI_PORT"

    cat <<EOF > "$INSTALL_DIR/.env"
# =============================================================================
# CADDY PROXY + MANAGER — Runtime Environment Variables
# Auto-generated by caddy.sh — do NOT edit manually.
# To change settings, edit config.env in the repository and re-run caddy.sh.
# =============================================================================

# --- Core (auto-generated) ---
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"

# --- Caddy Proxy ---
CADDY_VERSION="$CADDY_VERSION"

# --- CaddyManager UI ---
PACKAGE_VERSION="$PACKAGE_VERSION"
CADDYMANAGER_UI_PORT="$CADDYMANAGER_UI_PORT"
APP_NAME="$APP_NAME"
DARK_MODE="$DARK_MODE"

# --- CaddyManager Backend ---
BACKEND_PORT="$BACKEND_PORT"
DB_ENGINE="$DB_ENGINE"
CORS_ORIGIN="$CORS_ORIGIN"
JWT_SECRET="$JWT_SECRET"
JWT_EXPIRATION="$JWT_EXPIRATION"

# --- Logging & Audit ---
LOG_LEVEL="$LOG_LEVEL"
AUDIT_LOG_MAX_SIZE_MB="$AUDIT_LOG_MAX_SIZE_MB"
AUDIT_LOG_RETENTION_DAYS="$AUDIT_LOG_RETENTION_DAYS"

# --- Health Checks ---
PING_INTERVAL="$PING_INTERVAL"
PING_TIMEOUT="$PING_TIMEOUT"

# --- Metrics ---
METRICS_HISTORY_MAX="$METRICS_HISTORY_MAX"
EOF

    umask "$OLD_UMASK"
    echo ".env file ready (permissions 600)."
}

# Validates that the installation directory exists and is writable by the
# current user. If /opt is root-owned and the user skipped the prerequisite
# step (sudo mkdir + chown), the deployment would fail silently later.
# Exit code 2 = missing prerequisite: install directory not writable.
check_install_dir_writable() {
    local dir="${1:-/opt/caddy}"

    # Try to create/write into the target directory
    if ! mkdir -p "$dir" 2>/dev/null || ! [ -w "$dir" ]; then
        echo ""
        echo "-----------------------------------------------------------------"
        echo " ERROR [exit 2]: INSTALLATION DIRECTORY NOT WRITABLE"
        echo "-----------------------------------------------------------------"
        echo " Cannot write to: $dir"
        echo ""
        echo " REQUIRED PREREQUISITE STEP (run this first, then retry):"
        echo ""
        echo "   sudo mkdir -p $dir && sudo chown \$USER:\$USER $dir"
        echo ""
        echo " This step is necessary when /opt is owned by root and your"
        echo " user does not have write access to it."
        echo "-----------------------------------------------------------------"
        exit 2
    fi
}

prepare_directories() {
    echo "Preparing installation directory: $INSTALL_DIR"
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    # Move downloaded files into the install directory
    mv -f "$TMP_DIR/config.env"         "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

    # Caddyfile: only place on first install to preserve user customizations
    if [ ! -f "$INSTALL_DIR/Caddyfile" ]; then
        mv "$TMP_DIR/Caddyfile" "$INSTALL_DIR/Caddyfile"
        echo "Default Caddyfile placed in $INSTALL_DIR/"
    else
        echo "Existing Caddyfile preserved (not overwritten)."
    fi

    # Static site directory (optional, expected by docker-compose volumes)
    mkdir -p "$INSTALL_DIR/site"

    echo "Directories ready."
}

# Verifies that all required containers are in 'running' state.
# podman-compose up -d exits 0 even when containers fail to start,
# so we must actively check the container states after the deploy.
# Exit code 3 = deployment failed: one or more containers not running.
verify_containers_running() {
    local -a REQUIRED=("caddy" "caddymanager-backend" "caddymanager-frontend")
    local -a FAILED=()

    echo "Verifying containers are running..."
    # Brief wait to allow containers to transition from 'created' to 'running'
    sleep 3

    for name in "${REQUIRED[@]}"; do
        local status
        status=$(podman inspect "$name" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
        if [[ "$status" != "running" ]]; then
            FAILED+=("  ✗ $name  (status: $status)")
        else
            echo "  ✓ $name"
        fi
    done

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo ""
        echo "-----------------------------------------------------------------"
        echo " ERROR [exit 3]: DEPLOYMENT FAILED — containers did not start"
        echo "-----------------------------------------------------------------"
        printf '%s\n' "${FAILED[@]}"
        echo ""
        echo " Most likely causes:"
        echo ""
        echo "   1. Short image names (no 'docker.io/' prefix) — Podman on"
        echo "      this system requires fully qualified registry references."
        echo "      The docker-compose.yml images must be prefixed, e.g.:"
        echo "        docker.io/lucaslorentz/caddy-docker-proxy:2.11-alpine"
        echo ""
        echo "   2. No connectivity to Docker Hub to pull the images."
        echo ""
        echo "   3. Install directory was not prepared beforehand (see exit 2)."
        echo ""
        echo " Diagnostic commands:"
        echo "   journalctl --user -u caddy-compose.service -n 80 --no-pager"
        echo "   podman ps -a"
        echo "-----------------------------------------------------------------"
        exit 3
    fi

    echo "All containers running."
}

deploy_and_persist() {
    echo "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    # Note: podman-compose up -d returns exit code 0 even when containers
    # fail to start. verify_containers_running() performs the real check.
    podman-compose up -d

    # Abort immediately if any container is not running.
    # This prevents configuring systemd persistence for a broken deployment.
    verify_containers_running

    echo "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/

    # Create a single systemd service that manages the entire compose stack.
    # This is cleaner than individual container services for multi-container setups.
    cat <<EOF > ~/.config/systemd/user/caddy-compose.service
[Unit]
Description=Caddy Proxy + CaddyManager (podman-compose)
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
    systemctl --user enable --now caddy-compose.service
}

print_success() {
    echo ""
    echo "================================================================="
    echo " CADDY PROXY + MANAGER deployed and secured with systemd."
    echo ""
    echo " Caddy Proxy:     http://$HOST_IP (ports 80, 443)"
    echo " CaddyManager UI: http://$HOST_IP:$CADDYMANAGER_UI_PORT"
    echo ""
    echo " Default login: admin / caddyrocks (change after first login!)"
    echo ""
    echo " The services will persist after logout and on VM reboots."
    echo ""
    echo " Useful commands:"
    echo "   Status:  systemctl --user status caddy-compose.service"
    echo "   Logs:    podman logs -f caddy"
    echo "   Restart: systemctl --user restart caddy-compose.service"
    echo "================================================================="
}

# =============================================================================
# ACTIONS
# =============================================================================

do_install() {
    echo ""
    echo "=== CADDY: Fresh Installation ==="
    echo ""

    download_repo_files
    offer_interactive_mode
    load_configuration
    detect_host_ip
    manage_credentials
    setup_lingering_and_socket
    enable_privileged_ports
    prepare_directories
    generate_runtime_env
    deploy_and_persist
    print_success
}

do_start() {
    echo ""
    echo "=== CADDY: Starting ==="
    echo ""

    if systemctl --user is-active --quiet caddy-compose.service 2>/dev/null; then
        echo "Caddy services are already running."
    else
        systemctl --user start caddy-compose.service
        echo "Caddy services started successfully."
    fi

    if [ -f /opt/caddy/.env ]; then
        local ip ui_port
        ip=$(grep "^HOST_IP=" /opt/caddy/.env | cut -d '=' -f2- || echo "unknown")
        ui_port=$(grep "^CADDYMANAGER_UI_PORT=" /opt/caddy/.env | cut -d '=' -f2- || echo "8080")
        echo "CaddyManager UI: http://$ip:$ui_port"
    fi
}

do_update() {
    echo ""
    echo "=== CADDY: Updating ==="
    echo ""

    download_repo_files
    offer_interactive_mode
    load_configuration
    detect_host_ip
    manage_credentials
    setup_lingering_and_socket
    enable_privileged_ports
    prepare_directories
    generate_runtime_env

    # Pull latest images before redeploying
    echo "Pulling latest images..."
    cd "$INSTALL_DIR"
    podman-compose pull

    deploy_and_persist
    print_success
}

do_uninstall() {
    echo ""
    echo "=== CADDY: Uninstall ==="
    echo ""
    echo " WARNING: This will permanently remove:"
    echo "   - All Caddy containers (caddy, caddymanager-backend, caddymanager-frontend)"
    echo "   - The systemd persistence service"
    echo "   - Container images"
    echo ""

    read -rp " Type 'UNINSTALL' to confirm: " CONFIRM
    if [ "$CONFIRM" != "UNINSTALL" ]; then
        echo "Uninstall cancelled."
        exit 0
    fi

    echo ""
    echo "Stopping services..."
    systemctl --user stop caddy-compose.service 2>/dev/null || true
    systemctl --user disable caddy-compose.service 2>/dev/null || true
    rm -f ~/.config/systemd/user/caddy-compose.service
    systemctl --user daemon-reload

    echo "Removing containers..."
    podman rm -f caddy caddymanager-backend caddymanager-frontend 2>/dev/null || true

    echo "Removing images..."
    podman rmi "docker.io/lucaslorentz/caddy-docker-proxy:${CADDY_VERSION:-2.11-alpine}" 2>/dev/null || true
    podman rmi "docker.io/caddymanager/caddymanager-backend:${PACKAGE_VERSION:-0.0.2}" 2>/dev/null || true
    podman rmi "docker.io/caddymanager/caddymanager-frontend:${PACKAGE_VERSION:-0.0.2}" 2>/dev/null || true

    # Ask about data removal
    echo ""
    echo " Persistent volumes:"
    echo "   - caddy_data     (TLS certificates — CRITICAL to preserve!)"
    echo "   - caddy_config   (runtime config)"
    echo "   - caddymanager_sqlite (CaddyManager database)"
    echo ""
    read -rp " Delete ALL persistent volumes? (WARNING: TLS certs will be lost!) [y/N]: " DELETE_DATA
    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        echo "Removing volumes..."
        podman volume rm caddy_data caddy_config caddymanager_sqlite 2>/dev/null || true
        echo "Volumes removed."
    else
        echo "Volumes preserved."
    fi

    read -rp " Delete configuration files ($INSTALL_DIR)? [y/N]: " DELETE_CONFIG
    if [[ "$DELETE_CONFIG" =~ ^[Yy]$ ]]; then
        rm -rf "${INSTALL_DIR:?}/.env" "${INSTALL_DIR:?}/config.env" \
               "${INSTALL_DIR:?}/docker-compose.yml" "${INSTALL_DIR:?}/site"
        echo "Config files removed."
        echo " Note: Caddyfile preserved at $INSTALL_DIR/conf/ (manual delete if needed)."
    else
        echo "Config files preserved."
    fi

    echo ""
    echo "================================================================="
    echo " CADDY has been uninstalled."
    echo "================================================================="
}

# =============================================================================
# MAIN
# =============================================================================

root_protection
check_dependencies

# Detect existing installation (default path for quick check)
if check_existing_installation "/opt/caddy"; then
    if [ -t 0 ]; then
        echo ""
        echo "================================================================="
        echo " CADDY PROXY + MANAGER — Management"
        echo "================================================================="
        echo " Existing installation detected at /opt/caddy"
        echo ""
        echo "   1) Start      — Start the existing services"
        echo "   2) Update     — Download latest config and redeploy"
        echo "   3) Uninstall  — Remove containers, service, and data"
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
        echo "Existing installation detected. Running automatic update..."
        do_update
    fi
else
    do_install
fi
