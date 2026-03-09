# Contributor's Guide

This document explains how to contribute to the `docker-develop` framework and how to add new services.

---

## 1. Developer Setup

### 1.1 Automated Build System
The shared library is split into modules for maintainability but delivered as a single file. You **must** enable the Git Hooks to ensure the compiled `lib/lib.sh` is always up-to-date.

Run this once in your local repository:
```bash
git config core.hooksPath githooks
```

### 1.2 Local Library Testing
If you are modifying `lib/src/*.sh` and want to test the changes without pushing to GitHub, use the `LIB_LOCAL` variable:

```bash
# Point to your local compiled lib.sh
LIB_LOCAL="$(pwd)/lib/lib.sh" bash projects/arcane/arcane.sh
```

---

## 2. Adding a New Service

To add a new service to the framework, follow these steps:

### Step 1: Create the Project Directory
Create a folder in `projects/<service-name>/` containing:
- `docker-compose.yml`: The container stack definition.
- `config.env`: User-editable defaults (No secrets!).
- `<service>.sh`: The management script (use the template below).

### Step 2: The Script Template
Your `<service>.sh` should use the following structure to inherit all framework features:

```bash
#!/bin/bash
set -euo pipefail

# 1. Define Repository Info
GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/USER/REPO/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/my-service"

# 2. Source Shared Library
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

# 3. Implement Service-Specific Functions
load_configuration() {
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/my-service}"
    # ... other defaults
}

verify_containers_running() {
    local REQUIRED=("my-container-name")
    verify_containers_in_list "${REQUIRED[@]}"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/my-service}"
    UNINSTALL_SVC_NAME="MY_SERVICE"
    UNINSTALL_CONTAINERS=("my-container-name")
    UNINSTALL_VOLUMES=("my_data_volume")
    uninstall_generic_service
}

# 4. Entry Point
root_protection
check_dependencies curl podman-compose
parse_args "$@"
```

### Step 3: Register the Service
Add your service to the `REGISTRY` array in `deploy.sh`:
```bash
"My Service|projects/my-service/my-service.sh|/opt/my-service|my-container-name|Short description"
```

---

## 3. Best Practices & Quality Control

### 3.1 Use Fully Qualified Image Names
Always prefix images with `docker.io/` or `ghcr.io/`. Podman fails to resolve short names on many enterprise systems.
- ❌ `image: caddy:latest`
- ✅ `image: docker.io/library/caddy:latest`

### 3.2 ShellCheck
All scripts should be ShellCheck clean. The framework uses `set -euo pipefail`, so be careful with:
- Optional variables: Use `${VAR:-}` instead of `$VAR`.
- Array checks: Use `[[ -v ARRAY[@] ]]` or local re-assignment with defaults to avoid "unbound variable" errors.

### 3.3 CI Validation
Every PR is automatically validated using:
1. **ShellCheck**: Static analysis for logic errors.
2. **Dry-Run**: Execution of the script in a Podman-enabled environment to verify logic flow without side effects.
