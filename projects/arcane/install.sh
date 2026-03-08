#!/bin/bash
set -euo pipefail

# ==============================================================================
# ARCANE - Unified Installer & Deployment Script
# Downloads config.env and docker-compose.yml from the public repository,
# configures the environment, and deploys Arcane with Podman rootless persistence.
#
# Usage:
#   bash install.sh                               (local execution)
#   curl -fsSL <raw_url>/install.sh | bash         (remote one-liner)
#
# Re-running this script is safe — it reuses existing secrets and only
# refreshes runtime values (IP, socket, systemd unit).
# ==============================================================================

REPO_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane"

# --- 1. ROOT PROTECTION ------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    echo "-----------------------------------------------------------------"
    echo " ERROR: DO NOT RUN THIS SCRIPT WITH SUDO"
    echo "-----------------------------------------------------------------"
    echo " To maintain a Rootless Podman installation, this script must be"
    echo " executed as a normal user."
    echo ""
    echo " PLEASE RETRY WITH: bash install.sh"
    echo "-----------------------------------------------------------------"
    exit 1
fi

# --- 2. DEPENDENCY CHECKS ----------------------------------------------------
for cmd in curl podman-compose; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: '$cmd' not found. Please install it before continuing." >&2
        exit 1
    fi
done

# --- 3. DOWNLOAD CONFIGURATION FROM REPOSITORY -------------------------------
# config.env is always fetched from the repo so that any change pushed to
# GitHub is automatically applied on the next install/update run.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading configuration from repository..."
curl -fsSL "$REPO_RAW/config.env"         -o "$TMP_DIR/config.env"
curl -fsSL "$REPO_RAW/docker-compose.yml" -o "$TMP_DIR/docker-compose.yml"
echo "Files downloaded."

# --- 4. LOAD CONFIGURATION ---------------------------------------------------
# Source config.env to import user-defined variables (INSTALL_DIR, APP_PORT, etc.)
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

# --- 5. PREPARE INSTALL DIRECTORY --------------------------------------------
echo "Preparing installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Move downloaded files into the install directory
mv "$TMP_DIR/config.env"         "$INSTALL_DIR/config.env"
mv "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

# Move into the install directory for the rest of the script
cd "$INSTALL_DIR"

# --- 6. HOST IP DETECTION ----------------------------------------------------
# Use HOST_IP from config.env if provided, otherwise auto-detect.
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

# --- 7. CREDENTIAL MANAGEMENT ------------------------------------------------
# If .env already exists and contains ENCRYPTION_KEY, secrets are reused
# to avoid breaking sessions on restarts.
if [ -f .env ] && grep -q "^ENCRYPTION_KEY=" .env; then
    echo "Existing .env file found. Reusing current secrets..."
    ENCRYPTION_KEY=$(grep "^ENCRYPTION_KEY=" .env | cut -d '=' -f2-)
    JWT_SECRET=$(grep "^JWT_SECRET=" .env          | cut -d '=' -f2-)
else
    echo "First run detected. Generating secure encryption keys..."
    # 64-character hex keys for Arcane.
    # pipefail is temporarily disabled: head -c closes the pipe early causing
    # SIGPIPE on tr, which would silently kill the script under set -o pipefail.
    set +o pipefail
    ENCRYPTION_KEY=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
    JWT_SECRET=$(tr -dc 'a-f0-9'     </dev/urandom | head -c 64)
    set -o pipefail
fi

# --- 8. UID/GID, LINGERING & PODMAN SOCKET ------------------------------------
PUID=$(id -u)
PGID=$(id -g)
USER_NAME=$(id -un)

# Enable lingering so user processes survive after SSH logout
echo "Ensuring user lingering is enabled..."
sudo loginctl enable-linger "$USER_NAME"

# Rootless Podman socket path — unique per user, resolved at deploy time.
PODMAN_SOCK="/run/user/${PUID}/podman/podman.sock"

if [ ! -S "$PODMAN_SOCK" ]; then
    echo "Podman socket not found. Attempting to enable and start it..."
    systemctl --user enable --now podman.socket 2>/dev/null || true
    # Wait up to 10 seconds for the socket to appear
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

# --- 9. WRITE .env (restricted permissions 600) ------------------------------
echo "Generating runtime .env file..."
OLD_UMASK=$(umask)
umask 177

cat <<EOF > .env
# =============================================================================
# ARCANE - Runtime Environment Variables
# Auto-generated by install.sh — do NOT edit manually.
# To change settings, edit config.env in the repository and re-run install.sh.
# =============================================================================

# --- Core (auto-generated) ---
HOST_IP=$HOST_IP
PUID=$PUID
PGID=$PGID
APP_PORT=$APP_PORT
APP_URL=http://$HOST_IP:$APP_PORT
PODMAN_SOCK=$PODMAN_SOCK
ENCRYPTION_KEY=$ENCRYPTION_KEY
JWT_SECRET=$JWT_SECRET

# --- Application (from config.env) ---
ENVIRONMENT=$ENVIRONMENT
GIN_MODE=$GIN_MODE
LOG_LEVEL=$LOG_LEVEL
TZ=$TZ

# --- Database ---
DATABASE_URL=$DATABASE_URL
ALLOW_DOWNGRADE=$ALLOW_DOWNGRADE

# --- Security ---
JWT_REFRESH_EXPIRY=$JWT_REFRESH_EXPIRY
FILE_PERM=$FILE_PERM
DIR_PERM=$DIR_PERM

# --- TLS ---
TLS_ENABLED=$TLS_ENABLED
TLS_CERT_FILE=$TLS_CERT_FILE
TLS_KEY_FILE=$TLS_KEY_FILE

# --- Agent ---
AGENT_MODE=$AGENT_MODE
AGENT_TOKEN=$AGENT_TOKEN
EOF

umask "$OLD_UMASK"
echo ".env file ready (permissions 600)."

# --- 10. PREPARE BIND-MOUNT DIRECTORIES --------------------------------------
# Directories must exist and be owned by the current user BEFORE podman-compose
# starts. If Podman creates them, it does so as root, causing permission errors.
echo "Preparing data directories..."
mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/projects"
sudo chown -R "${PUID}:${PGID}" "${INSTALL_DIR}/data" "${INSTALL_DIR}/projects"
echo "Directories ready."

# --- 11. DEPLOY & SYSTEMD PERSISTENCE ----------------------------------------
echo "Starting services with podman-compose..."
podman-compose up -d

echo "Configuring systemd service for persistence..."
mkdir -p ~/.config/systemd/user/

# Generate systemd unit for the container named 'arcane'.
# --new recreates the container from the image on each service start.
podman generate systemd --name arcane --files --new \
    --restart-policy=always \
    --dest ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now container-arcane.service

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
