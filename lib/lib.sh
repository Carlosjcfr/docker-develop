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
    
    # Try to create as normal user. If it fails or is not writable, scale to sudo.
    if ! mkdir -p "$dir" 2>/dev/null || ! [ -w "$dir" ]; then
        log "Install directory '$dir' needs elevated permissions to be created."
        log "Attempting to create it automatically using 'sudo'..."
        
        if sudo mkdir -p "$dir" && sudo chown -R "$USER:$USER" "$dir"; then
            log "Directory '$dir' prepared and ownership assigned to $USER."
        else
            echo ""
            echo "-----------------------------------------------------------------"
            echo " ERROR [exit 2]: FAILED TO PREPARE INSTALLATION DIRECTORY"
            echo "-----------------------------------------------------------------"
            echo " The script tried to run 'sudo mkdir -p $dir' but failed."
            echo " Please create it manually and assign ownership to $USER:"
            echo "   sudo mkdir -p $dir && sudo chown \$USER:\$USER $dir"
            echo "-----------------------------------------------------------------"
            exit 2
        fi
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

# =============================================================================
# HTTP HEALTH CHECKS  (F3.4)
# =============================================================================

# Poll an HTTP endpoint until it responds (HTTP 2xx) or timeout is reached.
# Provides application-level validation beyond container state checks.
# Usage: poll_http URL [TIMEOUT_SECONDS] [RETRY_INTERVAL_SECONDS]
# Returns: 0 if endpoint responds within timeout, exits 3 otherwise.
poll_http() {
    local url="${1:?poll_http requires a URL}"
    local timeout="${2:-30}"
    local interval="${3:-2}"
    local elapsed=0

    log "Waiting for $url ..."
    while [ "$elapsed" -lt "$timeout" ]; do
        if curl -sf --max-time "$interval" "$url" >/dev/null 2>&1; then
            log "  ✓ $url"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    err "Endpoint did not respond within ${timeout}s: $url"
    return 1
}

# Run HTTP health checks for a set of named endpoints.
# Aborts with exit 3 if any endpoint fails after its timeout.
# Usage: check_http_health "label|url|timeout" ["label|url|timeout" ...]
# Example: check_http_health "Caddy Admin|http://127.0.0.1:2019/config/|20"
check_http_health() {
    local -a FAILED=()

    log "Running HTTP health checks..."
    for entry in "$@"; do
        local label url timeout
        IFS='|' read -r label url timeout <<< "$entry"
        timeout="${timeout:-30}"
        if ! poll_http "$url" "$timeout" 2 2>/dev/null; then
            FAILED+=("  ✗ $label  ($url)")
        fi
    done

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo ""
        echo "-----------------------------------------------------------------"
        echo " ERROR [exit 3]: HEALTH CHECKS FAILED — services not responding"
        echo "-----------------------------------------------------------------"
        printf '%s\n' "${FAILED[@]}"
        echo ""
        echo " The containers are running but the applications inside are not"
        echo " responding. Check the container logs for startup errors:"
        echo "   podman logs <container-name>"
        echo "-----------------------------------------------------------------"
        exit 3
    fi

    log "All health checks passed."
}

# =============================================================================
# UNINSTALLATION ENGINE
# =============================================================================

# Centralized uninstallation logic for all services.
# Requires the caller to set the following global variables:
#   UNINSTALL_SVC_NAME      (string) e.g. "ARCANE"
#   UNINSTALL_SYSTEMD       (string) e.g. "container-arcane.service"
#   UNINSTALL_CONTAINERS    (array)  e.g. ("arcane")
#   UNINSTALL_IMAGES        (array)  e.g. ("ghcr.io/getarcaneapp/arcane:latest")
#   UNINSTALL_VOLUMES       (array)  e.g. ("caddy_data" "caddy_config")
#   UNINSTALL_DIRS          (array)  e.g. ("/opt/arcane/data")
#   UNINSTALL_DATA_WARN     (string) e.g. "WARNING: All arcane projects will be lost!"
uninstall_generic_service() {
    echo ""
    echo "=== ${UNINSTALL_SVC_NAME}: Uninstall ==="
    echo ""
    echo " WARNING: This will permanently remove:"
    echo "   - The container(s) and image(s)"
    echo "   - The systemd persistence service"
    echo ""

    if [ "$FORCE_YES" -eq 1 ]; then
        CONFIRM="UNINSTALL"
    else
        read -rp " Type 'UNINSTALL' to confirm: " CONFIRM < /dev/tty
    fi
    if [ "$CONFIRM" != "UNINSTALL" ]; then
        log "Uninstall cancelled."
        exit 0
    fi

    echo ""
    log "Stopping systemd service..."
    systemctl --user stop "$UNINSTALL_SYSTEMD" 2>/dev/null || true
    systemctl --user disable "$UNINSTALL_SYSTEMD" 2>/dev/null || true
    rm -f ~/.config/systemd/user/"$UNINSTALL_SYSTEMD"
    systemctl --user daemon-reload

    log "Removing container(s)..."
    for c in "${UNINSTALL_CONTAINERS[@]}"; do
        podman rm -f "$c" 2>/dev/null || true
    done

    log "Removing image(s)..."
    for i in "${UNINSTALL_IMAGES[@]}"; do
        podman rmi "$i" 2>/dev/null || true
    done

    echo ""
    if [ "$FORCE_YES" -eq 1 ]; then
        DELETE_DATA="y"
    else
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ]; then
            echo " Persistent volumes connected to this service:"
            for v in "${UNINSTALL_VOLUMES[@]}"; do echo "   - $v"; done
        fi
        if [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
            echo " Data directories connected to this service:"
            for d in "${UNINSTALL_DIRS[@]}"; do echo "   - $d"; done
        fi
        [ -n "${UNINSTALL_DATA_WARN:-}" ] && echo " $UNINSTALL_DATA_WARN"
        echo ""
        read -rp " Delete ALL data and the installation directory ($INSTALL_DIR)? [y/N]: " DELETE_DATA < /dev/tty
    fi

    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        log "Removing configuration, data, and installation directory..."
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ]; then
            for v in "${UNINSTALL_VOLUMES[@]}"; do podman volume rm "$v" 2>/dev/null || true; done
        fi
        if [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
            for d in "${UNINSTALL_DIRS[@]}"; do sudo rm -rf "$d"; done
        fi
        sudo rm -rf "${INSTALL_DIR:?}"
        log "All data and directory removed."
    else
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ] || [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
            log "Data preserved."
        fi
        sudo rm -f "${INSTALL_DIR:?}/.env" "${INSTALL_DIR:?}/config.env" "${INSTALL_DIR:?}/docker-compose.yml"
        log "Config files cleaned up, but installation directory ($INSTALL_DIR) preserved."
    fi

    echo ""
    echo "================================================================="
    echo " ${UNINSTALL_SVC_NAME} has been uninstalled."
    echo "================================================================="
}
# =============================================================================
# ARCANE INTEGRATION
# =============================================================================

# Register the service as a "Project" in Arcane by creating a symlink.
# Arcane maps its internal /app/data/projects to host /opt/arcane/projects.
# Usage: register_arcane_project PROJECT_NAME INSTALL_DIR
register_arcane_project() {
    local project_name="${1:?register_arcane_project requires a project name}"
    local install_dir="${2:?register_arcane_project requires an installation directory}"
    local arcane_projects_dir="/opt/arcane/projects"

    log "Registering project '$project_name' in Arcane..."

    # Ensure the parent directory exists and is writable
    if ! [ -d "$arcane_projects_dir" ]; then
        if sudo mkdir -p "$arcane_projects_dir" && sudo chown -R "$USER:$USER" "$arcane_projects_dir" 2>/dev/null; then
            log "  Created Arcane projects directory: $arcane_projects_dir"
        else
            warn "  Could not create Arcane projects directory. Skipping registration."
            return 1
        fi
    fi

    # Create/update symlink
    ln -sfn "$install_dir" "$arcane_projects_dir/$project_name"
    log "  Symlink created: $arcane_projects_dir/$project_name -> $install_dir"
}
