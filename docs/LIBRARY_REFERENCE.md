# Shared Library Reference (`lib.sh`)

This document serves as the official API reference for the `docker-develop` bash core library (`lib.sh`).
It defines global variables, parameters, and usage examples for the centralized functions used by all service scripts.

## Table of Contents

1. [Global Variables](#global-variables)
2. [Core Module (`01_core.sh`)](#core-module-01_coresh)
3. [Install Module (`02_install.sh`)](#install-module-02_installsh)
4. [Health Module (`03_health.sh`)](#health-module-03_healthsh)
5. [Uninstall Module (`04_uninstall.sh`)](#uninstall-module-04_uninstallsh)
6. [Arcane Sync Module (`05_arcane.sh`)](#arcane-sync-module-05_arcanesh)

---

## Global Variables

The library functions frequently inject, read, or export the following global variables to the calling scripts context:

* **System Globals**
  * `PUID` / `PGID`: Current user and group IDs (derived from `id`).
  * `USER_NAME`: Current user string.
  * `PODMAN_SOCK`: Path to the rootless Podman Unix socket (e.g. `/run/user/1000/podman/podman.sock`).
  * `HOST_IP`: The detected primary IP address of the host machine.
* **Runtime Globals**
  * `TMP_DIR`: Temporary directory path created during `download_repo_files`.
  * `CMD_ACTION`: The parsed action from CLI args (e.g. `install`, `update`, `uninstall`).
  * `FORCE_YES`: Boolean (1/0) indicating if `-y` or `--yes` flag was passed.
  * `DRY_RUN`: Boolean (1/0) indicating if `--dry-run` was passed.

---

## Core Module (`01_core.sh`)

### `log`, `warn`, `err`

Print standard timestamped messages to the terminal. `warn` and `err` print to stderr.
**Usage:** `log "Deployment starting..."`

### `root_protection`

Aborts execution if the script is run as the `root` user (`sudo`). Required to enforce rootless Podman isolation.

### `check_dependencies [cmd...]`

Verifies that all specified commands exist in the system `$PATH`.
**Usage:** `check_dependencies curl jq podman`

### `check_secrets_not_in_config <file> [secret...]`

Ensures that no secret keys are hardcoded in the public `config.env`. Aborts if found.
**Usage:** `check_secrets_not_in_config "$TMP_DIR/config.env" "DB_PASSWORD" "JWT_SECRET"`

### `check_install_dir_writable <dir>`

Validates that the installation directory is writable by the user, or attempts to create it via `sudo` and assign ownership if it doesn't exist.

---

## Install Module (`02_install.sh`)

### `setup_lingering_and_socket`

Enables user lingering via `loginctl` and ensures the Podman unix socket is running. Populates `PUID`, `PGID`, `USER_NAME`, and `PODMAN_SOCK`.

### `enable_privileged_ports`

Allows rootless Podman to bind privileged ports (< 1024) (like 80 or 443) persistently.

### `parse_args "$@"`

Parses standard CLI arguments. Sets `CMD_ACTION`, `FORCE_YES`, and `DRY_RUN`.
**Usage:** `./service.sh --install -y`

### `download_repo_files <base_url> [file...]`

Downloads files into an automatically cleaned temporary directory (`$TMP_DIR`).
**Usage:** `download_repo_files "$REPO_RAW" "docker-compose.yml" "config.env"`

### `offer_interactive_mode`

Presents a prompt to run `configure.sh` interactively if executed in a TTY terminal and `FORCE_YES` is 0.

### `detect_host_ip`

Automatically detects the primary IPv4 address from the default route and exports it to `HOST_IP` (unless previously set).

### `assign_project_ip`

Finds the next available IP address in the `internal_net` (172.170.1.0/24) and exports it to `PROJECT_IP`. It automatically skips the gateway and any IPs already assigned to other containers or pods.

### `manage_credentials <install_dir> [secret...]`

Reuses secrets from an existing `.env` or securely generates new 64-char hexadecimal ones, exporting them to the caller environment.
**Usage:** `manage_credentials "/opt/myservice" "PG_PASSWORD" "JWT"`

---

## Health Module (`03_health.sh`)

### `verify_containers_running [container...]`

Verifies that specific containers are in the `running` state after deployment. Exits `3` if any fail.
**Usage:** `verify_containers_running "web_server" "db_replica"`

### `poll_http <url> [timeout] [interval]`

Polls an endpoint waiting for an HTTP 2xx response. Default timeout 30s.

### `check_http_health "label|url|timeout" [...]`

Runs HTTP health checks for an array of payloads. Aborts if applications fail to respond.
**Example:** `check_http_health "App UI|http://127.0.0.1:8080|30" "API|http://127.0.0.1:3000/ping|20"`

---

## Uninstall Module (`04_uninstall.sh`)

### `uninstall_generic_service`

A comprehensive, atomic engine designed to purge all traces of a service deployment.
It attempts **dynamic discovery** by parsing the `docker-compose.yml` to find images and networks, and defaults to manual arrays if parsing fails.

**Required Globals in calling script:**

* `UNINSTALL_SVC_NAME`: The human-readable name of the service.
* `UNINSTALL_SYSTEMD`: The exact filename of the `systemd` user service.
* `INSTALL_DIR`: The path to the installation directory.

**Optional Override Globals:**

* `UNINSTALL_CONTAINERS`: Array of explicit containers to `podman rm -f`.
* `UNINSTALL_IMAGES`: Array of explicit images to `podman rmi`.
* `UNINSTALL_VOLUMES`: Array of explicit persistent volumes.
* `UNINSTALL_DIRS`: Array of external directories to `sudo rm -rf`.
* `UNINSTALL_DATA_WARN`: Special warning string presented to the user before destructive actions.

**Usage in Sub-scripts:**

```bash
UNINSTALL_SVC_NAME="My Service"
UNINSTALL_SYSTEMD="container-myservice.service"
INSTALL_DIR="/opt/myservice"
uninstall_generic_service
```

---

## Arcane Sync Module (`05_arcane.sh`)

### `register_arcane_project <project_slug> <install_dir>`

Syncs service configurations to Arcane's `projects` directory, mimicking management capabilities without directly coupling the containers to the Arcane internal network.
Copies `.env` and `docker-compose.yml` strings and patches the `working_dir` compose label for UI visibility.

Includes a guard clause to prevent `arcane` from targeting itself and triggering circular restarts/aborts.

**Usage:** `register_arcane_project "myservice" "/opt/myservice"`
