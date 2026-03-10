# =============================================================================
# ENVIRONMENT BOOTSTRAP
# =============================================================================

# Enables user lingering and verifies Podman socket (Ref: docs/LIBRARY_REFERENCE.md)
# shellcheck disable=SC2034
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

# Enables rootless Podman to bind privileged ports < 1024 (Ref: docs/LIBRARY_REFERENCE.md)
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

# Parses CLI arguments and sets CMD_ACTION, FORCE_YES, DRY_RUN (Ref: docs/LIBRARY_REFERENCE.md)
# shellcheck disable=SC2034
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

# Downloads repository files into a fresh auto-cleaned temp directory (Ref: docs/LIBRARY_REFERENCE.md)
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

# Offers interactive configuration step via TTY if FORCE_YES=0 (Ref: docs/LIBRARY_REFERENCE.md)
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

# Auto-detects the primary host IP address (Ref: docs/LIBRARY_REFERENCE.md)
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

# Reuses existing secrets or securely generates new hexadecimal keys (Ref: docs/LIBRARY_REFERENCE.md)
manage_credentials() {
    local install_dir="${1:?manage_credentials requires INSTALL_DIR}"
    shift
    local -a keys=("$@")
    local first_key="${keys[0]:?manage_credentials requires at least one secret name}"

    if [ -f "$install_dir/.env" ] && grep -q "^${first_key}=" "$install_dir/.env"; then
        log "Existing secrets found. Reusing..."
        for key in "${keys[@]}"; do
            local val
            val=$(grep "^${key}=" "$install_dir/.env" | cut -d '=' -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
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
