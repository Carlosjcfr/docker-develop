# =============================================================================
# ENVIRONMENT BOOTSTRAP
# =============================================================================

# Enable user lingering and ensure the Podman socket is active.
# Sets globals: PUID, PGID, USER_NAME, PODMAN_SOCK
setup_lingering_and_socket() {
    PUID=$(id -u)
    PGID=$(id -g)
    USER_NAME=$(id -un)

    log "Ensuring user lingering is enabled..."
    sudo loginctl enable-linger "$USER_NAME"

    PODMAN_SOCK="/run/user/${PUID}/podman/podman.sock"

    if [ ! -S "$PODMAN_SOCK" ]; then
        log "Podman socket not found. Attempting to start it..."
        systemctl --user enable --now podman.socket 2>/dev/null || true
        for i in $(seq 1 10); do
            [ -S "$PODMAN_SOCK" ] && break
            sleep 1
        done
        if [ ! -S "$PODMAN_SOCK" ]; then
            err "Could not start Podman socket at $PODMAN_SOCK"
            exit 1
        fi
        log "Podman socket ready."
    fi
}

# Allow rootless Podman to bind privileged ports (< 1024).
# Persists the kernel parameter across reboots via /etc/sysctl.d/.
# Only call this for services that require ports 80 or 443.
enable_privileged_ports() {
    local CURRENT
    CURRENT=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo "1024")

    if [ "$CURRENT" -gt 0 ] 2>/dev/null; then
        log "Enabling unprivileged binding to ports 80/443 (requires sudo)..."
        sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0 >/dev/null
        if [ ! -f /etc/sysctl.d/99-unprivileged-ports.conf ]; then
            echo "net.ipv4.ip_unprivileged_port_start=0" | \
                sudo tee /etc/sysctl.d/99-unprivileged-ports.conf >/dev/null
            log "  Persisted in /etc/sysctl.d/99-unprivileged-ports.conf"
        fi
        log "  Ports 80/443 are now available for rootless containers."
    else
        log "Unprivileged port binding already enabled."
    fi
}

# =============================================================================
# CLI ARGUMENTS
# =============================================================================

# Parse common CLI arguments for service scripts.
# Usage: parse_args "$@"
# Sets globals: CMD_ACTION, FORCE_YES, DRY_RUN
parse_args() {
    CMD_ACTION=""
    FORCE_YES=0
    DRY_RUN=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install)   CMD_ACTION="install" ;;
            --update)    CMD_ACTION="update" ;;
            --uninstall) CMD_ACTION="uninstall" ;;
            --start)     CMD_ACTION="start" ;;
            --yes|-y)    FORCE_YES=1 ;;
            --dry-run)   DRY_RUN=1 ; log "[DRY-RUN] mode enabled" ;;
            *) err "Unknown argument: $1"; exit 1 ;;
        esac
        shift
    done
}

# =============================================================================
# FILE MANAGEMENT
# =============================================================================

# Download files from the repository into a fresh temp directory.
# Creates $TMP_DIR and registers an EXIT trap to clean it automatically.
# Usage: download_repo_files BASE_URL FILE [FILE ...]
# Sets global: TMP_DIR
download_repo_files() {
    local base_url="${1:?download_repo_files requires a base URL}"
    shift

    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT

    log "Downloading files from repository..."
    for file in "$@"; do
        curl -fsSL "${base_url}/${file}" -o "${TMP_DIR}/${file}"
    done
    log "Files downloaded."
}

# Offer an optional interactive configuration step when running in a terminal.
# Downloads and runs configure.sh, which edits $TMP_DIR/config.env.
# Requires globals: REPO_RAW, TMP_DIR
offer_interactive_mode() {
    if [ "${FORCE_YES:-0}" -eq 1 ]; then
        return
    fi
    if [ -t 0 ]; then
        echo ""
        read -rp "Run in interactive mode? (customize all options) [y/N]: " INTERACTIVE
        if [[ "$INTERACTIVE" =~ ^[Yy]$ ]]; then
            log "Downloading interactive configurator..."
            curl -fsSL "$REPO_RAW/configure.sh" -o "$TMP_DIR/configure.sh"
            bash "$TMP_DIR/configure.sh" "$TMP_DIR/config.env"
        fi
    fi
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Auto-detect the host IP from the default network route.
# If HOST_IP is already set (e.g. from config.env or env var), it is preserved.
# Sets global: HOST_IP
detect_host_ip() {
    if [ -z "${HOST_IP:-}" ]; then
        local INTERFACE
        INTERFACE=$(ip route | awk '/^default/ {print $5; exit}')
        HOST_IP=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        if [ -z "$HOST_IP" ]; then
            err "Could not determine the host IP address."
            err "Set HOST_IP in config.env and retry."
            exit 1
        fi
        log "Host IP auto-detected: $HOST_IP"
    else
        log "Host IP from config: $HOST_IP"
    fi
}

# Reuse existing secrets from .env or generate new ones.
# Each secret is exported as a bash variable in the calling scope.
# Usage: manage_credentials INSTALL_DIR SECRET_NAME [SECRET_NAME ...]
manage_credentials() {
    local install_dir="${1:?manage_credentials requires INSTALL_DIR}"
    shift
    local -a keys=("$@")
    local first_key="${keys[0]:?manage_credentials requires at least one secret name}"

    if [ -f "$install_dir/.env" ] && grep -q "^${first_key}=" "$install_dir/.env"; then
        log "Existing secrets found. Reusing..."
        for key in "${keys[@]}"; do
            local val
            val=$(grep "^${key}=" "$install_dir/.env" | cut -d '=' -f2-)
            printf -v "$key" '%s' "$val"
        done
    else
        log "First run detected. Generating secure secrets..."
        set +o pipefail
        for key in "${keys[@]}"; do
            local val
            val=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
            printf -v "$key" '%s' "$val"
        done
        set -o pipefail
    fi
}
