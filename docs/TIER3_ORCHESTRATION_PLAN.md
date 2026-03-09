# Tier 3 — Orchestration: Revised Plan

> **Revised:** 2026-03-09 — Previous version assumed a "deploy a full stack at once"
> model. This revision reflects the correct goal: a **universal service manager**
> that provides a shared, secure installation framework for individual services.

---

## Corrected Goal

The objective is **not** to install multiple services simultaneously or manage
dependencies between them. The objective is:

> Provide a single interactive entry point (`deploy.sh`) that lets an operator
> select **which service** to install/manage from those available in the repository,
> and then delegate to that service's script — which handles installation with
> rigorous security, permission, and error-diagnosis logic.

The emphasis of the entire system is on:

- **Correct permissions** at every step (directories, files, volumes, SELinux labels)
- **Proactive error diagnosis** — detect and explain problems before they happen
- **Common failure prevention** — missing `/opt/<service>` dir, SQLite not writable,
  short image names, internal service-to-DB connectivity, Podman socket issues
- **Consistent behavior** across all services via a shared library

---

## System Architecture

```
Operator
   │
   └──► bash deploy.sh  (or curl -fsSL .../deploy.sh | bash)
              │
              │  Downloads service registry from GitHub
              │  Shows interactive menu:
              │
              │   ═══════════════════════════════════════
              │    AVAILABLE SERVICES
              │   ═══════════════════════════════════════
              │    1) Caddy Proxy + Manager
              │    2) Arcane
              │    3) <next service>
              │    0) Cancel
              │   ═══════════════════════════════════════
              │
              │  User selects a service
              │
              ├──► Downloads <service>.sh from GitHub
              │
              └──► Runs <service>.sh
                         │
                         │   ═══════════════════════════
                         │    SERVICE MANAGEMENT
                         │   ═══════════════════════════
                         │    1) Install
                         │    2) Start
                         │    3) Update
                         │    4) Uninstall
                         │    0) Cancel
                         │   ═══════════════════════════
                         │
                         └──► sources lib.sh (shared functions)
                              └──► executes the selected action
```

**Key design principle:** `deploy.sh` knows nothing about service internals.
It only knows the service registry (name + script URL). All installation logic
stays in each service's dedicated script.

---

## Component 3.1 — `lib.sh` (Shared Function Library)

### Role

A shared Bash library sourced by every service script. Contains all logic that is
**identical across services** and would otherwise be copy-pasted.

The focus of `lib.sh` is specifically on the problems that cause silent failures:

```
┌─────────────────────────────────────────────────────────────┐
│  Problems lib.sh prevents                                   │
├─────────────────────────────────────────────────────────────┤
│  Permissions    │ check_install_dir_writable()              │
│                 │ Detects missing sudo prerequisite before  │
│                 │ any files are written                     │
├─────────────────┼─────────────────────────────────────────-─┤
│  Silent deploy  │ verify_containers_running()               │
│  failures       │ podman-compose exits 0 even when ALL      │
│                 │ containers fail — this catches it         │
├─────────────────┼───────────────────────────────────────────┤
│  Podman setup   │ setup_lingering_and_socket()              │
│                 │ enable_privileged_ports()                 │
│                 │ Rootless-specific requirements that are   │
│                 │ easy to miss on fresh VMs                 │
├─────────────────┼───────────────────────────────────────────┤
│  Image names    │ Documented pattern (not enforced in lib)  │
│                 │ All images MUST use docker.io/ prefix     │
│                 │ Short names fail on non-Docker systems    │
├─────────────────┼───────────────────────────────────────────┤
│  Secrets        │ load_configuration() secret guard        │
│                 │ manage_credentials() reuse/generate       │
│                 │ generate_runtime_env() umask 177          │
├─────────────────┼───────────────────────────────────────────┤
│  Diagnosis      │ verify_containers_running() exit codes    │
│                 │ log()/warn()/err() with timestamps        │
│                 │ Specific exit codes per failure type      │
└─────────────────┴───────────────────────────────────────────┘
```

### What goes in `lib.sh`

| Function | Purpose |
|---|---|
| `log()` / `warn()` / `err()` | Timestamped output; `err()` goes to stderr |
| `root_protection()` | Abort if EUID == 0 |
| `check_dependencies()` | Check required commands exist in PATH |
| `setup_lingering_and_socket()` | Enable linger + wait for Podman socket |
| `enable_privileged_ports()` | sysctl for ports < 1024; persists via sysctl.d |
| `download_repo_files()` | Generic: accepts a list of file names + base URL |
| `offer_interactive_mode()` | TTY detection + download configure.sh |
| `detect_host_ip()` | Auto-detect via default route |
| `check_install_dir_writable()` | Guard: exit 2 if directory not writable |
| `manage_credentials()` | Generic: accepts a list of secret names to reuse/generate |
| `verify_containers_running()` | Generic: accepts a list of container names to check |
| `parse_args()` | CLI flag parser shared by all scripts (--install, --update, --yes, --dry-run) |

### What stays in each service script

```
load_configuration()      ← service-specific variables and defaults
generate_runtime_env()    ← service-specific .env template
prepare_directories()     ← service-specific directory structure + chown needs
deploy_and_persist()      ← service-specific systemd unit
do_install/update/start/uninstall()
print_success()           ← service-specific URLs and commands
```

### Sourcing pattern

```bash
# At the top of each service script (after REPO_RAW is set):
LIB_RAW="https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/lib/lib.sh"
# shellcheck source=../../lib/lib.sh
source <(curl -fsSL "$LIB_RAW") || {
    echo "ERROR: Could not download lib.sh from $LIB_RAW" >&2
    exit 1
}
```

### Pros and cons

| | Detail |
|---|---|
| ✅ | Bug fixed once in lib.sh applies to all services immediately |
| ✅ | New service script is ~150 lines instead of ~500 |
| ✅ | Consistent error messages and exit codes across services |
| ⚠️ | Breaking change in lib.sh affects all services → **mitigation:** version the URL (`lib/v1/lib.sh`) |
| ⚠️ | Network dependency at start → **mitigation:** cache lib.sh locally after first download; fall back if offline |

---

## Component 3.2 — `deploy.sh` (Universal Service Manager)

### Role

Single entry point for the entire repository. The operator never needs to know
individual script URLs — they only need this one URL.

```bash
curl -fsSL "https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/deploy.sh" | bash
```

### How it works

1. Downloads the **service registry** (`registry.json` or inline in the script)
2. Checks which services are **already installed** (per-service detection)
3. Shows a **service selection menu** (not a raw list — shows install status)
4. Once a service is selected, downloads its script and runs it
5. The service script then shows its own management menu (install/start/update/uninstall)

### Service registry format

```json
[
  {
    "name": "Caddy Proxy + Manager",
    "slug": "caddy",
    "script": "projects/caddy-proxy-manager/caddy.sh",
    "install_dir": "/opt/caddy",
    "main_container": "caddy",
    "description": "Reverse proxy with web management UI (ports 80, 443, 8080)"
  },
  {
    "name": "Arcane",
    "slug": "arcane",
    "script": "projects/arcane/arcane.sh",
    "install_dir": "/opt/arcane",
    "main_container": "arcane",
    "description": "Docker/Podman management UI (port 3552)"
  }
]
```

### Menu design

```
═══════════════════════════════════════════════════════════
 SERVICE MANAGER — Available Services
═══════════════════════════════════════════════════════════

  1) Caddy Proxy + Manager   [INSTALLED]   Reverse proxy + web UI
  2) Arcane                  [NOT INSTALLED]   Container manager UI
  3) <next service>          [NOT INSTALLED]   ...

  0) Exit

 Select service [0-2]:
```

After selection:

```
═══════════════════════════════════════════════════════════
 CADDY PROXY + MANAGER — Management
═══════════════════════════════════════════════════════════
 Installed at: /opt/caddy

  1) Install   2) Start   3) Update   4) Uninstall   0) Back

 Select [0-4]:
```

> **Note:** `deploy.sh` does NOT implement install/update/uninstall logic
> itself. It downloads and runs the service-specific script, which handles
> those actions. `deploy.sh` is purely a **dispatcher**.

### Pros and cons

| | Detail |
|---|---|
| ✅ | One URL for the entire repository — operators never memorize per-service URLs |
| ✅ | Shows install status at a glance |
| ✅ | Adding new services requires only adding a registry entry — no changes to deploy.sh |
| ✅ | Works piped (`curl \| bash`) and locally (`bash deploy.sh`) |
| ⚠️ | If the registry is embedded in deploy.sh, adding services requires updating the script → **mitigation:** keep registry in a separate `registry.json` fetched at runtime |
| ⚠️ | `jq` may not be available for JSON parsing → **mitigation:** use plain text registry (one line per service) or inline Bash arrays |

---

## Component 3.3 — GitHub Actions CI

### Role

Validate scripts on every push to catch regressions before they reach a server.

```yaml
on:
  push:
    paths:
      - 'lib/**'
      - 'projects/**/*.sh'
      - 'deploy.sh'

jobs:
  shellcheck:   # Static analysis via ShellCheck
  dry-run:      # bash <service>.sh --dry-run in a Podman environment
```

`--dry-run` mode (implemented in `lib.sh`):
- Runs all pre-flight checks and config loading
- Prints the commands that would be executed
- Never writes files, starts containers, or modifies system state
- Enables CI to validate script logic without infrastructure

---

## Technical Debt Addressed

| ID | Issue | Script | Resolved by |
|---|---|---|---|
| TD-01 | `check_install_dir_writable()` missing | `arcane.sh` | 3.1 lib.sh |
| TD-02 | `verify_containers_running()` missing | `arcane.sh` | 3.1 lib.sh |
| TD-03 | `enable_privileged_ports()` missing | `arcane.sh` | 3.1 lib.sh |
| TD-04 | Inconsistent `manage_credentials()` pattern | both | 3.1 lib.sh |
| TD-05 | `podman generate systemd` deprecated in Podman 5+ | `arcane.sh:240` | Fix before 3.1 |
| TD-06 | No unified repository entry point | — | 3.2 deploy.sh |
| TD-07 | No regression detection | — | 3.3 CI |
| TD-08 | `do_update()` duplicates file-move logic in arcane.sh | `arcane.sh:331` | 3.1 lib.sh |

---

## Implementation Phases

| Phase | Deliverable | Prerequisite |
|---|---|---|
| **Phase 0** | ✅ Fix `arcane.sh`: add missing guards, fix `podman generate systemd` | None |
| **Phase 1** | ✅ `lib/lib.sh` created; both scripts refactored to source it | Phase 0 |
| **Phase 2** | ✅ `deploy.sh` with service registry and dispatcher menu | Phase 1 |
| **Phase 3** | ✅ `--dry-run` + `--yes` + `--install` flags in lib/all scripts | Phase 1 |
| **Phase 4** | ✅ `.github/workflows/scripts-ci.yml` (ShellCheck + dry-run) | Phase 3 |

---

## Open Questions

1. **Registry format:** Embedded Bash array in `deploy.sh` (simpler, no `jq` dependency).
   → Status: ✅ Implemented as Bash array.

2. **`deploy.sh` branch:** Publish on `main`?
   → Status: ✅ `deploy.sh` on `main`; service scripts branch per project.

3. **Service detection in `deploy.sh`:** Use the same `[ -f install_dir/.env ] && podman container exists main_container` check?
   → Status: ✅ Consistent detection logic implemented.

---

## CI Coverage (Phase 4)

| Job | What it validates | Trigger |
| --- | --- | --- |
| `shellcheck` | Static analysis of all `.sh` files — bad quoting, undefined vars, logic errors | Push / PR |
| `syntax` | Bash `-n` parse on every script — catches syntax errors instantly | Push / PR |
| `config-secrets` | Scans every `config.env` for committed secrets — mirrors `lib.sh` guard | Push / PR |
| `parse-args` | Unit-tests `parse_args()` from `lib.sh` directly for all known flags | Push / PR (after syntax) |
