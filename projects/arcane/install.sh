#!/bin/bash
set -euo pipefail

# ==============================================================================
# ARCANE - Installer
# Downloads start.sh and docker-compose.yml from the public repository
# and runs the deployment.
# Usage: bash install.sh
#   OR:  curl -fsSL <raw_url>/install.sh | bash
# ==============================================================================

INSTALL_DIR="/opt/arcane"
REPO_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane"
TMP_DIR=$(mktemp -d)

# Cleanup temp dir on exit (error or success)
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Dependency checks --------------------------------------------------------
for cmd in curl podman-compose; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: '$cmd' not found. Please install it before continuing." >&2
        exit 1
    fi
done

# --- Create install directory -------------------------------------------------
echo "Preparing installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# --- Download files to /tmp first (always writable) --------------------------
echo "Downloading files from repository..."
curl -fsSL "$REPO_RAW/docker-compose.yml" -o "$TMP_DIR/docker-compose.yml"
curl -fsSL "$REPO_RAW/start.sh"           -o "$TMP_DIR/start.sh"
chmod +x "$TMP_DIR/start.sh"
echo "Files downloaded."

# --- Move files to install directory ------------------------------------------
mv "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
mv "$TMP_DIR/start.sh"           "$INSTALL_DIR/start.sh"

# --- Run deployment -----------------------------------------------------------
echo "Running start.sh..."
cd "$INSTALL_DIR"
bash start.sh
