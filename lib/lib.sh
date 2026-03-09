#!/bin/bash
# ==============================================================================
# lib.sh — Shared Function Library  (v1)
# Common functions sourced by all service install scripts in this repository.
#
# CONTRACT — scripts sourcing this library must set before calling lib functions:
#   REPO_RAW     Base URL of the service's raw GitHub files
#
# Globals SET by lib functions (available to the sourcing script after the call):
#   TMP_DIR      Temp dir created by download_repo_files() — auto-cleaned on EXIT
#   HOST_IP      Set by detect_host_ip()
#   PUID         Set by setup_lingering_and_socket()
#   PGID         Set by setup_lingering_and_socket()
#   USER_NAME    Set by setup_lingering_and_socket()
#   PODMAN_SOCK  Set by setup_lingering_and_socket()
# ==============================================================================

# =============================================================================
# LOGGING
# =============================================================================

log()  { echo "[$(date -u '+%H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] [WARN]  $*" >&2; }
err()  { echo "[$(date -u '+%H:%M:%S')] [ERROR] $*" >&2; }

# =============================================================================
# GUARDS
# =============================================================================

# Abort if the script is running as root.
# Rootless Podman must run as a normal user to maintain namespaced isolation.
root_protection() {
    if [[ $EUID -eq 0 ]]; then
        echo "-----------------------------------------------------------------"
        echo " ERROR: DO NOT RUN THIS SCRIPT WITH SUDO"
        echo "-----------------------------------------------------------------"
        echo " Rootless Podman requires a normal user session."
        echo " Please retry WITHOUT sudo."
        echo "-----------------------------------------------------------------"
        exit 1
    fi
}

# Verify that all required commands exist in PATH.
# Usage: check_dependencies CMD [CMD ...]
check_dependencies() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            err "Required command '$cmd' not found. Please install it before continuing."
            exit 1
        fi
    done
}

# Validate that no secret variable names appear in a config file.
# Secrets must never be committed to the repository.
# Usage: check_secrets_not_in_config CONFIG_FILE SECRET_NAME [SECRET_NAME ...]
check_secrets_not_in_config() {
    local config_file="${1:?check_secrets_not_in_config requires a config file path}"
    shift
    for secret_name in "$@"; do
        if grep -q "^${secret_name}=" "$config_file"; then
            echo "-----------------------------------------------------------------"
            echo " ERROR: SECRET DETECTED IN config.env"
            echo "-----------------------------------------------------------------"
            echo " '$secret_name' must NEVER be stored in the repository."
            echo " Remove it from config.env — secrets are auto-generated at runtime."
            echo "-----------------------------------------------------------------"
            exit 1
        fi
    done
}

# Validate that the installation directory is writable by the current user.
# If /opt is root-owned and the prerequisite step was skipped, fail early.
# Exit code 2 = missing prerequisite: install directory not writable.
# Usage: check_install_dir_writable DIR
check_install_dir_writable() {
    local dir="${1:?check_install_dir_writable requires a directory argument}"
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
        echo " This step is necessary when /opt is owned by root."
        echo "-----------------------------------------------------------------"
        exit 2
    fi
}

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

# =============================================================================
# DEPLOYMENT VALIDATION
# =============================================================================

# Verify that all specified containers are in 'running' state.
# podman-compose up -d always exits 0 — this catches silent failures.
# Usage: verify_containers_running CONTAINER [CONTAINER ...]
# Exit code 3 = deployment failed: one or more containers not running.
verify_containers_running() {
    local -a REQUIRED=("$@")
    local -a FAILED=()

    log "Verifying containers are running..."
    sleep 3   # Allow containers to transition from 'created' to 'running'

    for name in "${REQUIRED[@]}"; do
        local status
        status=$(podman inspect "$name" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
        if [[ "$status" != "running" ]]; then
            FAILED+=("  ✗ $name  (status: $status)")
        else
            log "  ✓ $name"
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
        echo "   1. Image name not fully qualified — Podman requires a registry"
        echo "      prefix (e.g. docker.io/image:tag or ghcr.io/image:tag)."
        echo "   2. No network access to pull images from the registry."
        echo "   3. Install directory not prepared beforehand (see exit code 2)."
        echo "   4. Port conflict with another running service."
        echo ""
        echo " Diagnostic commands:"
        echo "   podman ps -a"
        echo "   podman logs <container-name>"
        echo "   journalctl --user -u <service>.service -n 80 --no-pager"
        echo "-----------------------------------------------------------------"
        exit 3
    fi

    log "All containers running."
}
