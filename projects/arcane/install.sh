#!/bin/bash
set -euo pipefail

# ==============================================================================
# ARCANE - Installer
# Downloads start.sh and docker-compose.yml from the public repository
# and runs the deployment.
# Usage: bash install.sh
# ==============================================================================

INSTALL_DIR="/opt/arcane"
REPO_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/projects/arcane"

# --- Dependency checks --------------------------------------------------------
for cmd in curl podman-compose; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: '$cmd' not found. Please install it before continuing." >&2
        exit 1
    fi
done

# --- Create install directory and move into it --------------------------------
echo "Preparing installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# --- Download files from repository -------------------------------------------
echo "Downloading files from repository..."
curl -fsSL "$REPO_RAW/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/start.sh"           -o start.sh
chmod +x start.sh
echo "Files downloaded."

# --- Run deployment -----------------------------------------------------------
echo "Running start.sh..."
bash start.sh
