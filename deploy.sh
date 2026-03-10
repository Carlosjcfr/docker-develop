#!/bin/bash
set -euo pipefail

# ==============================================================================
# deploy.sh — Universal Service Manager
# Single entry point for all services in this repository.
#
# Usage:
#   bash deploy.sh                                (local, interactive)
#   curl -fsSL <raw_url>/deploy.sh | bash          (remote, automatic)
#
# No arguments needed. The script presents a menu of available services,
# shows their installation status, and dispatches to the selected service script.
#
# To add a new service: add one line to the REGISTRY array below.
# ==============================================================================

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"

# =============================================================================
# SERVICE REGISTRY
# Format per entry: "Display Name|script_path|install_dir|main_container|description|endpoints"
#
#   Display Name:    Text shown in the menu
#   script_path:     Path relative to REPO_BASE to download and execute
#   install_dir:     Directory checked to detect an existing installation
#   main_container:  Podman container name used as the existence probe
#   description:     Short one-line description shown next to the service name
#   endpoints:       Service endpoints format. Use {IP} placeholder for host IP
# =============================================================================

HOST_IP=$(hostname -I | awk '{print $1}')

REGISTRY=(
    "Arcane|projects/arcane/arcane.sh|/opt/arcane|arcane|Container management UI|UI: {IP}:3552"
    "Caddy Proxy + Manager|projects/caddy-proxy-manager/caddy.sh|/opt/caddy|caddy|Reverse proxy with TLS + web management UI|Proxy: {IP}:80 / {IP}:443, Manager: {IP}:8080"
    "Supabase|projects/supabase/supabase.sh|/opt/supabase|studio|Open source Firebase alternative|Studio: {IP}:3000, API: {IP}:8000, DB: {IP}:5432"
    "Windmill|projects/windmill/windmill.sh|/opt/windmill|windmill_server|Plataforma analítica y de workflows para desarrolladores|Servicio: {IP}:8000"
)

# =============================================================================
# HELPERS
# =============================================================================

log()  { echo "[$(date -u '+%H:%M:%S')] [INFO]  $*"; }
err()  { echo "[$(date -u '+%H:%M:%S')] [ERROR] $*" >&2; }

# Parse a field from a registry entry by index (0-based).
# Usage: registry_field ENTRY INDEX
registry_field() {
    local entry="$1"
    local idx="$2"
    echo "$entry" | cut -d'|' -f$((idx + 1))
}

# Check if a service is currently installed.
# Returns 0 if installed, 1 otherwise.
# Usage: is_installed INSTALL_DIR MAIN_CONTAINER
is_installed() {
    local dir="$1"
    local container="$2"
    
    # Check if .env exists AND if either the new short name or the old prefixed name exists
    if [ -f "$dir/.env" ]; then
        if podman container exists "$container" 2>/dev/null; then
            return 0
        fi
        # Specific check for legacy Supabase names
        if [[ "$container" == "studio" ]] && podman container exists "supabase-studio" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# =============================================================================
# GUARDS
# =============================================================================

if [[ $EUID -eq 0 ]]; then
    echo "-----------------------------------------------------------------"
    echo " ERROR: DO NOT RUN THIS SCRIPT WITH SUDO"
    echo "-----------------------------------------------------------------"
    echo " Rootless Podman requires a normal user session."
    echo " Please retry WITHOUT sudo."
    echo "-----------------------------------------------------------------"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    err "'curl' not found. Please install it before continuing."
    exit 1
fi

if ! command -v podman &>/dev/null; then
    err "'podman' not found. Please install it before continuing."
    exit 1
fi

# =============================================================================
# MAIN MENU
# =============================================================================

while true; do
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  SERVICE MANAGER"
    echo "  Repository: github.com/Carlosjcfr/docker-develop"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""

    # Build the menu dynamically from the registry, checking install status
    local_idx=0
    declare -A STATUS_MAP

    for entry in "${REGISTRY[@]}"; do
        local_idx=$((local_idx + 1))
        name=$(registry_field "$entry" 0)
        install_dir=$(registry_field "$entry" 2)
        container=$(registry_field "$entry" 3)
        description=$(registry_field "$entry" 4)
        endpoints=$(registry_field "$entry" 5)

        if [ "$local_idx" -gt 1 ]; then
            echo ""
        fi

        if is_installed "$install_dir" "$container"; then
            endpoints_resolved="${endpoints//\{IP\}/$HOST_IP}"
            IFS=',' read -ra ENDPOINT_ARRAY <<< "$endpoints_resolved"
            
            # Print the first line (Service Name + First Endpoint)
            printf "  %d) %-30s %s\n" "$local_idx" "$name" "${ENDPOINT_ARRAY[0]}"
            
            # Formateamos y alineamos los siguientes endpoints debajo
            for (( i=1; i<${#ENDPOINT_ARRAY[@]}; i++ )); do
                ep="${ENDPOINT_ARRAY[$i]}"
                # Trim leading space
                ep="${ep#"${ep%%[![:space:]]*}"}"
                printf "      %-30s %s\n" "" "$ep"
            done
        else
            status="[NOT INSTALLED]"
            printf "  %d) %-30s %s  %s\n" "$local_idx" "$name" "$status" "$description"
        fi

        STATUS_MAP[$local_idx]="$entry"
    done

    echo ""
    echo "  0) Exit"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""

    read -rp " Select a service [0-${#REGISTRY[@]}]: " CHOICE < /dev/tty

    # Validate input
    if [[ "$CHOICE" == "0" ]]; then
        log "Exiting Service Manager."
        exit 0
    fi

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || \
       [ "$CHOICE" -lt 1 ] || \
       [ "$CHOICE" -gt "${#REGISTRY[@]}" ]; then
        err "Invalid selection. Please enter a number between 0 and ${#REGISTRY[@]}."
        continue
    fi

    # ==========================================================================
    # DISPATCH
    # ==========================================================================

    SELECTED="${STATUS_MAP[$CHOICE]}"
    SERVICE_NAME=$(registry_field "$SELECTED" 0)
    SCRIPT_PATH=$(registry_field "$SELECTED" 1)
    INSTALL_DIR=$(registry_field "$SELECTED" 2)
    CONTAINER=$(registry_field "$SELECTED" 3)

    SCRIPT_URL="${REPO_BASE}/${SCRIPT_PATH}"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  $SERVICE_NAME"

    if is_installed "$INSTALL_DIR" "$CONTAINER"; then
        echo "  Status: INSTALLED at $INSTALL_DIR"
    else
        echo "  Status: NOT INSTALLED"
    fi

    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Downloading and launching service manager..."
    echo "  Script: $SCRIPT_URL"
    echo ""

    # Download the service script to a temp file and execute it.
    # The service script sources lib.sh and presents its own action menu
    # (install / start / update / uninstall / cancel).
    TMP_SCRIPT=$(mktemp /tmp/service-script.XXXXXX.sh)
    trap 'rm -f "$TMP_SCRIPT"' EXIT

    if ! curl -fsSL "$SCRIPT_URL" -o "$TMP_SCRIPT"; then
        err "Failed to download service script from: $SCRIPT_URL"
        err "Check your network connection and try again."
        rm -f "$TMP_SCRIPT"
        trap - EXIT
        continue
    fi

    # Execute the service script attached to the terminal
    export GIT_BRANCH REPO_BASE
    bash "$TMP_SCRIPT" < /dev/tty
    EXIT_CODE=$?

    # Clean up and reset trap before looping back to the main menu
    rm -f "$TMP_SCRIPT"
    trap - EXIT

    case "$EXIT_CODE" in
        0)   log "$SERVICE_NAME operation completed successfully." ;;
        1)   err "$SERVICE_NAME: guard failure or dependency error (see above)." ;;
        2)   err "$SERVICE_NAME: install directory not writable — see instructions above." ;;
        3)   err "$SERVICE_NAME: deployment failed — containers did not start (see above)." ;;
        *)   warn "$SERVICE_NAME exited with code $EXIT_CODE." ;;
    esac

    echo ""
    read -rp " Press ENTER to return to the service list..." _PAUSE < /dev/tty

done
