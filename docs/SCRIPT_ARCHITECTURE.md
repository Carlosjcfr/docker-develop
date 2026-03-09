# Script Architecture — `caddy.sh`

> **Template reference** for Podman rootless single-command install scripts.
> This document describes the design patterns, validation strategy, variable model,
> and action lifecycle implemented in `caddy.sh`. Use it as the canonical baseline
> when creating install scripts for other services.

---

## 1. Overview

`caddy.sh` is a **self-contained, idempotent Bash management script** that handles
the full lifecycle of a Podman rootless service stack (install, start, update,
uninstall) from a single entry point.

### Design goals

| Goal | Implementation |
|---|---|
| Single command install (local or remote) | `curl -fsSL <url>/caddy.sh \| bash` |
| Safe re-runs | Detects existing installation and switches to management menu |
| No root execution | `root_protection()` aborts immediately if `EUID == 0` |
| Secrets never in repo | `JWT_SECRET` auto-generated, stored only in runtime `.env` |
| Fail fast, fail clear | Every failure path exits with a specific code and actionable message |
| Persistence after logout | systemd user service + `loginctl enable-linger` |

---

## 2. Execution Modes

The script detects its context at startup and routes to the correct mode:

```
bash caddy.sh
      │
      ├── root? ──────────────────────────────────────────► exit 1
      │
      ├── missing dependency? (curl, podman-compose) ─────► exit 1
      │
      ├── existing install detected?
      │       ├── interactive terminal (TTY) ──────────────► Management menu (1/2/3/0)
      │       └── piped / non-interactive ─────────────────► do_update() (automatic)
      │
      └── no existing install ──────────────────────────────► do_install()
```

### Existing installation detection

Requires **both** conditions to be true:

```bash
[ -f "$INSTALL_DIR/.env" ] && podman container exists <main_container>
```

---

## 3. Function Reference

### 3.1 Guards (run at script start, before any action)

| Function | Purpose | Exit code |
|---|---|---|
| `root_protection()` | Aborts if run with `sudo` / as root | `1` |
| `check_dependencies()` | Verifies `curl` and `podman-compose` are in PATH | `1` |

### 3.2 Shared pipeline functions

These functions are called in sequence from `do_install()` and `do_update()`:

| Order | Function | What it does |
|---|---|---|
| 1 | `download_repo_files()` | Downloads `config.env`, `docker-compose.yml`, `Caddyfile` from `$REPO_RAW` into a temp dir with `trap` cleanup |
| 2 | `offer_interactive_mode()` | If TTY detected, prompts user to run `configure.sh` for custom options |
| 3 | `load_configuration()` | Sources `config.env`, validates no secrets are present, applies all defaults via `${VAR:-default}` |
| 4 | `detect_host_ip()` | Auto-detects host IP from default route interface; falls back to `HOST_IP` in config |
| 5 | `manage_credentials()` | Reuses `JWT_SECRET` from existing `.env` or generates a new 64-char hex secret |
| 6 | `setup_lingering_and_socket()` | Enables `loginctl linger`, verifies Podman socket exists (retries 10s) |
| 7 | `enable_privileged_ports()` | Sets `net.ipv4.ip_unprivileged_port_start=0` if needed; persists via `/etc/sysctl.d/` |
| 8 | `prepare_directories()` | Validates write access, moves files to `$INSTALL_DIR`, protects `Caddyfile` on updates |
| 9 | `generate_runtime_env()` | Writes runtime `.env` with `umask 177` (permissions 600) |
| 10 | `deploy_and_persist()` | Runs `podman-compose up -d`, verifies containers, writes systemd unit, enables service |
| 11 | `print_success()` | Displays access URLs and useful commands |

### 3.3 Validation functions

| Function | Trigger | Exit code | Error condition |
|---|---|---|---|
| `check_install_dir_writable()` | Inside `prepare_directories()` | `2` | `mkdir -p` fails or directory is not writable (missing prerequisite step) |
| `verify_containers_running()` | Inside `deploy_and_persist()`, after `podman-compose up -d` | `3` | Any container not in `running` state after 3s grace period |

### 3.4 Action functions

| Function | When | Description |
|---|---|---|
| `do_install()` | No existing install | Full pipeline (steps 1–11) |
| `do_start()` | Menu option 1 | Checks service state via systemd; starts if not active |
| `do_update()` | Menu option 2 / piped mode | Full pipeline + `podman-compose pull` before redeploy |
| `do_uninstall()` | Menu option 3 | Stops service, removes containers/images, optional volume/config deletion with confirmation |

---

## 4. Exit Code Reference

| Code | Meaning |
|---|---|
| `0` | Success or deliberate cancellation (e.g. uninstall aborted) |
| `1` | Guard failure: root execution, missing dependency, secret in repo, IP detection failure, Podman socket unavailable |
| `2` | Prerequisite missing: install directory not writable — user must run `sudo mkdir + chown` first |
| `3` | Deployment failure: one or more containers not in `running` state after deploy |

---

## 5. Configuration Model

### Two-file config separation

| File | Location | Purpose | Committed to repo? |
|---|---|---|---|
| `config.env` | Repo → copied to `$INSTALL_DIR/config.env` | User-facing, editable defaults | ✅ Yes |
| `.env` | `$INSTALL_DIR/.env` (perms 600) | Runtime vars, includes secrets | ❌ Never |

### Variables: `config.env` (repo)

| Variable | Default | Configurable by user? |
|---|---|---|
| `INSTALL_DIR` | `/opt/caddy` | ✅ |
| `HOST_IP` | *(auto-detected)* | ✅ (override auto-detect) |
| `CADDY_VERSION` | `2.11-alpine` | ✅ |
| `PACKAGE_VERSION` | `0.0.2` | ✅ |
| `ACME_EMAIL` | `you@example.com` | ✅ |
| `CADDYMANAGER_UI_PORT` | `8080` | ✅ |
| `APP_NAME` | `Caddy Manager` | ✅ |
| `DARK_MODE` | `true` | ✅ |
| `BACKEND_PORT` | `3000` | ✅ |
| `DB_ENGINE` | `sqlite` | ✅ |
| `JWT_EXPIRATION` | `24h` | ✅ |
| `LOG_LEVEL` | `info` | ✅ |
| `AUDIT_LOG_MAX_SIZE_MB` | `100` | ✅ |
| `AUDIT_LOG_RETENTION_DAYS` | `90` | ✅ |
| `PING_INTERVAL` | `30000` | ✅ |
| `PING_TIMEOUT` | `2000` | ✅ |
| `METRICS_HISTORY_MAX` | `1000` | ✅ |

### Variables: `.env` (runtime, auto-generated)

| Variable | Source |
|---|---|
| `JWT_SECRET` | Generated (`tr -dc 'a-f0-9' < /dev/urandom \| head -c 64`) or reused from existing `.env` |
| `CORS_ORIGIN` | Computed as `http://$HOST_IP:$CADDYMANAGER_UI_PORT` |
| `PUID` / `PGID` | Captured from `id -u` / `id -g` |
| `PODMAN_SOCK` | Computed as `/run/user/$PUID/podman/podman.sock` |
| All `config.env` vars | Copied after defaults are applied |

> `JWT_SECRET` must **never** appear in `config.env`. The script validates this
> explicitly and exits with code `1` if found.

---

## 6. Systemd Integration

The script registers a **`Type=oneshot` + `RemainAfterExit=yes`** user service:

```ini
[Unit]
Description=<Service Name> (podman-compose)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=<INSTALL_DIR>
ExecStart=<path/to/podman-compose> up -d
ExecStop=<path/to/podman-compose> down
TimeoutStartSec=120
TimeoutStopSec=30
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
```

**Why `oneshot` + `RemainAfterExit`?**  
`podman-compose up -d` forks immediately and exits. Systemd would otherwise
consider the service "dead". `RemainAfterExit=yes` keeps the unit in `active`
state as long as the stop command has not been called, which is the correct
semantics for a compose stack manager.

---

## 7. Security Decisions

| Decision | Rationale |
|---|---|
| Script must NOT run as root | Preserves rootless Podman isolation; all containers run under the user's UID |
| Secrets auto-generated, never in repo | Prevents accidental secret exposure via version control |
| `.env` written with `umask 177` (mode 600) | Secrets file readable only by owner |
| `sudo` used only for two specific operations | `sysctl` for port binding + `loginctl enable-linger` |
| Image names fully qualified (`docker.io/...`) | Required for Podman compatibility on systems without `unqualified-search-registries` — avoids short-name resolution failures |

---

## 8. Known Podman vs Docker Differences

These issues **do not affect Docker/WSL** but are critical for Podman on Linux VMs:

| Issue | Docker behavior | Podman behavior | Fix applied |
|---|---|---|---|
| Short image names | Resolved via Docker Hub implicitly | Fails if no `unqualified-search-registries` in `/etc/containers/registries.conf` | Prefix all images with `docker.io/` |
| `podman-compose up -d` exit code | Non-zero if containers fail | **Always 0**, even on total failure | `verify_containers_running()` post-check |
| Privileged ports (80/443) | Docker daemon binds them | Rootless Podman blocked by kernel | `sysctl net.ipv4.ip_unprivileged_port_start=0` |
| Session persistence | Docker daemon is always running | User session ends on SSH logout | `loginctl enable-linger` |

---

## 9. Template Checklist — Adapting to a New Service

When using this script as a base for a new service, replace or adjust:

- [ ] `REPO_RAW` — point to the new service's raw GitHub path
- [ ] `check_existing_installation()` — change the container name used as the existence probe
- [ ] `load_configuration()` — replace variables and defaults with the new service's config
- [ ] `verify_containers_running()` — update the `REQUIRED` array with the new container names
- [ ] `do_uninstall()` — update container names, image names, and volume names
- [ ] `print_success()` — update URLs, ports, and useful commands
- [ ] `generate_runtime_env()` — update the `.env` template with the new service's variables
- [ ] Systemd unit `Description` and `WorkingDirectory`
- [ ] `enable_privileged_ports()` — omit if the service does not need ports < 1024
- [ ] `manage_credentials()` — adapt or remove if the service uses a different secret model
