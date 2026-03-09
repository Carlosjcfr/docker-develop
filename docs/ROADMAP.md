# Install Script Roadmap — Towards Full Automation

<<<<<<< Updated upstream
> **Scope:** Proposals to evolve the current `caddy.sh` pattern into a
> fully automated, CI/CD-ready, multi-service installation system.
> No changes have been made yet — this document is a design proposal only.

---

## Current State Summary

The current script (`caddy.sh`) is a solid baseline:

- ✅ Single-command install via `curl | bash`
- ✅ Idempotent (safe to re-run)
- ✅ Fail-fast with specific exit codes
- ✅ Secrets never committed to repo
- ✅ Systemd persistence with rootless Podman
- ⚠️ Interactive mode breaks unattended execution (CI/CD)
- ⚠️ Configuration requires modifying a repo file (`config.env`)
- ⚠️ No pre-flight checks before starting deployment
- ⚠️ Post-deploy verification only checks container state, not service health
- ⚠️ No rollback capability on failed updates
- ⚠️ Each service has its own independent script — no shared foundation

---

## Proposed Improvements

### TIER 1 — Quick wins (low effort, high impact)

---

#### 1.1 CLI Argument Support

**Problem:** The interactive menu breaks `curl | bash` pipelines and CI/CD runners.  
**Proposal:** Support named flags alongside the current interactive mode.

```bash
# Examples
bash caddy.sh --install
bash caddy.sh --update
bash caddy.sh --uninstall --yes          # skip confirmation prompts
bash caddy.sh --install --config /path/to/custom.env
bash caddy.sh --install --port 9090 --dir /srv/caddy
```

**Design notes:**

- Parse with `getopts` or a manual `while [[ $# -gt 0 ]]` loop
- `--yes` / `-y` flag to suppress all interactive prompts globally
- Maintain backward compatibility: no flags = current interactive behavior
- Override individual variables via flags (`--port`, `--dir`, `--email`)

**Impact:** Enables non-interactive automation without changing config files.

---

#### 1.2 Environment Variable Override Layer

**Problem:** Customization requires editing `config.env` in the repo (or interactive mode).  
**Proposal:** Add a third config layer — environment variables set in the calling shell take priority over `config.env` defaults, without modifying any file.

```bash
# Priority chain (highest to lowest):
# 1. CLI flags        --port 9090
# 2. Shell env vars   CADDYMANAGER_UI_PORT=9090 bash caddy.sh
# 3. config.env       CADDYMANAGER_UI_PORT=9090
# 4. Script defaults  ${CADDYMANAGER_UI_PORT:-8080}

INSTALL_DIR=/srv/caddy ACME_EMAIL=ops@example.com bash caddy.sh --install
```

**Impact:** Zero-modification deploys. Ideal for Ansible, Terraform, or shell-based provisioners.

---

#### 1.3 Pre-flight Checks

**Problem:** Failures occur mid-deploy (after writing files) due to conditions that could have been detected upfront.  
**Proposal:** Add a `preflight_checks()` function that runs before any write operation.

Checks to include:

| Check | Why |
|---|---|
| DNS resolution of `raw.githubusercontent.com` | Detect network issues before downloading |
| Docker Hub reachability (`docker.io`) | Detect registry access before `podman pull` |
| Available disk space in `$INSTALL_DIR` (min ~500MB) | Prevent mid-pull failures |
| `ip_unprivileged_port_start` current value | Early warn if sysctl will need sudo |
| Existing containers with conflicting names | Warn before a failed `podman run` |
| Podman version compatibility (min 4.x) | Guard against old installations |

**Impact:** Fail before writing anything — cleaner error recovery, no partial state.

---

#### 1.4 Structured Logging with Timestamps

**Problem:** Output is plain `echo` — hard to redirect, parse, or debug remotely.  
**Proposal:** Replace bare `echo` calls with a `log()` helper that adds level + timestamp.

```bash
log()  { echo "[$(date -u '+%H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] [WARN]  $*" >&2; }
err()  { echo "[$(date -u '+%H:%M:%S')] [ERROR] $*" >&2; }
```

Output format:

```
[14:32:01] [INFO]  Downloading files from repository...
[14:32:03] [INFO]  Configuration loaded (INSTALL_DIR=/opt/caddy, UI_PORT=8080).
[14:32:04] [ERROR] DEPLOYMENT FAILED — containers did not start
```

**Impact:** Logs are grep-friendly, can be piped to `tee`, and are trivially collectable by a log aggregator.

---

### TIER 2 — Robustness improvements (medium effort)

---

#### 2.1 Application-Level Health Checks

**Problem:** `verify_containers_running()` only checks that the container process exists (`status == running`). The service inside may still be booting, crashing, or misconfigured.  
**Proposal:** After confirming container state, perform HTTP health checks against known endpoints.

```bash
# Caddy Admin API — should respond 200
curl -sf http://127.0.0.1:2019/config/ > /dev/null

# CaddyManager backend health endpoint
curl -sf http://127.0.0.1:3000/health > /dev/null

# CaddyManager UI
curl -sf http://127.0.0.1:8080/ > /dev/null
```

- Poll with a configurable timeout (default 30s, retry every 2s)
- Report which endpoint is not responding to pinpoint the failure layer
- Exit code 3 is preserved but the error message becomes more specific

**Impact:** True end-to-end health validation — confirms the application is serving, not just that the container is alive.

---

#### 2.2 Rollback on Failed Update

**Problem:** `do_update()` overwrites files and restarts services. If the new version fails, there is no recovery path other than manual intervention.  
**Proposal:** Before updating, snapshot the current state; restore automatically on failure.

```bash
# Snapshot before update
snapshot_dir="$INSTALL_DIR/.snapshots/$(date -u '+%Y%m%dT%H%M%S')"
mkdir -p "$snapshot_dir"
cp "$INSTALL_DIR/.env"              "$snapshot_dir/"
cp "$INSTALL_DIR/docker-compose.yml" "$snapshot_dir/"
cp "$INSTALL_DIR/config.env"        "$snapshot_dir/"

# On update failure → restore snapshot and restart previous containers
```

- Keep last N snapshots (default: 3), auto-delete older ones
- Rollback is automatic when `verify_containers_running()` or health checks fail
- Manual rollback option: `bash caddy.sh --rollback`

**Impact:** Safe updates — a failed version upgrade does not leave the service down.

---

#### 2.3 Secret Rotation Support

**Problem:** `JWT_SECRET` is generated once and reused forever. There is no mechanism to rotate it deliberately.  
**Proposal:** Add a `--rotate-secrets` flag that regenerates credentials and restarts the stack.

```bash
bash caddy.sh --rotate-secrets
```

- Only available as an explicit flag (not part of normal update)
- Warns that active sessions will be invalidated
- Requires `--yes` to proceed non-interactively
- Backs up the old `.env` before rotation

**Impact:** Enables periodic credential rotation without a full reinstall.

---

### TIER 3 — Multi-service orchestration (higher effort, strategic)

---

#### 3.1 Shared Library (`lib.sh`)

**Problem:** Each service script duplicates the same functions (`root_protection`, `check_dependencies`, `log`, `setup_lingering_and_socket`, etc.).  
**Proposal:** Extract a shared `lib.sh` into a common location that all service scripts source.

```
docker-develop/
├── lib/
│   └── lib.sh          ← common functions for all service scripts
├── projects/
│   ├── caddy-proxy-manager/
│   │   └── caddy.sh    ← sources lib.sh; only service-specific logic
│   ├── arcane/
│   │   └── arcane.sh   ← sources lib.sh; only service-specific logic
│   └── <next-service>/
│       └── <service>.sh
```

```bash
# Each service script starts with:
LIB_URL="https://raw.githubusercontent.com/.../lib/lib.sh"
source <(curl -fsSL "$LIB_URL")
```

**What stays in each service script (not in lib):**

- `REPO_RAW` URL
- `load_configuration()` (service-specific variables and defaults)
- `generate_runtime_env()` (service-specific `.env` template)
- `verify_containers_running()` (service-specific container list)
- `do_uninstall()` (service-specific assets to remove)
- `print_success()` (service-specific URLs and commands)

**What moves to `lib.sh`:**

- `root_protection()`
- `check_dependencies()`
- `log()` / `warn()` / `err()`
- `preflight_checks()`
- `download_repo_files()`
- `setup_lingering_and_socket()`
- `enable_privileged_ports()`
- `manage_credentials()`
- `check_install_dir_writable()`
- `parse_args()`

**Impact:** One fix in `lib.sh` applies to all service scripts. New services require
implementing only the 6 service-specific functions listed above.

---

#### 3.2 Stack Orchestrator (`stack.sh`)

**Problem:** Each service is installed independently with no coordination between them (shared networks, service dependencies, install order).  
**Proposal:** A top-level `stack.sh` that installs the full server stack in the correct order.

```bash
bash stack.sh --install         # installs all services
bash stack.sh --install caddy   # installs only caddy
bash stack.sh --status          # shows health of all services
bash stack.sh --update all      # updates all services
```

Service dependency graph:

```
caddy (proxy) ──► must be installed first
     │
     └──► arcane
     └──► <next-service>
```

**Features:**

- Install services in dependency order
- Skip already-installed services (idempotent)
- Aggregate status view: all containers from all services in one table
- Coordinated updates (update proxy last to avoid downtime)

**Impact:** Single command to provision a complete server environment from zero.

---

#### 3.3 GitHub Actions CI Validation

**Problem:** Script bugs are only discovered when running on the actual server.  
**Proposal:** Add a GitHub Actions workflow that validates scripts on every push.

```yaml
# .github/workflows/script-lint.yml
- name: ShellCheck (static analysis)
  uses: ludeeus/action-shellcheck@master

- name: Dry-run on Ubuntu (Podman)
  run: |
    # Install Podman, run script in --dry-run mode
    bash caddy.sh --dry-run
```

**`--dry-run` mode:**

- Parses all config, runs all checks, prints the podman commands that *would* be executed
- Never creates containers, writes files, or modifies system state
- Returns exit code 0 only if all pre-flight checks pass

**Impact:** Catches regressions (broken variable substitution, missing quotes, logic errors)
before they reach a production server.
=======
This document outlines the current state, identified technical debt, and future improvements for the `docker-develop` service installation framework.

---

## 🚀 Current Status (March 2026)

The framework has successfully transitioned to a **Modular Library Architecture**.

### Key Achievements

- ✅ **Universal Entry Point (`deploy.sh`)**: Centralized service discovery and dispatching.
- ✅ **Compiled Shared Library (`lib/lib.sh`)**: High-performance delivery from `lib/src/`.
- ✅ **Generic Uninstall Engine**: Standardized and safe cleanup with data preservation options.
- ✅ **Security First**: Non-root execution, `umask 177` for secrets, and `sysctl` unprivileged port management.
- ✅ **Automation-Ready**: Full CLI flag support (`--install`, `--update`, `--uninstall`, `--yes`, `--dry-run`).
- ✅ **Diagnostic Probes**: Post-deploy HTTP health checks integrated into the core flow.

---

## 🛠️ Technical Debt Monitor

We track areas where code duplication or suboptimal patterns still exist to prioritize refactoring.

| ID | Issue | Impact | Status |
|---|---|---|---|
| **TD-01** | **Duplicate Systemd Logic** | High | 📋 Each script manually writes its unit file. Needs `lib.sh` helper. |
| **TD-02** | **Management Menu Boilerplate** | Medium | 📋 Every service script duplicates the same 1-3 interactive menu. |
| **TD-03** | **Hardcoded Path in `do_start`** | Low | ✅ Fixed in all scripts. Now using `$INSTALL_DIR`. |
| **TD-04** | **Unbound Array Expansion** | High | ✅ Fixed in `uninstall.sh`. Audit other loops for `set -u` compatibility. |
| **TD-05** | **Boilerplate Variable Defaults** | Low | 📋 `VAR="${VAR:-default}"` takes 20+ lines per script. |

---

## 🎯 Future Phases

### Phase 4: Reliability & Recovery (In Progress)

#### 📋 4.1 Rollback & Pre-update Snapshots

- **Problem**: Failed updates leave the service down or in a partial state.
- **Solution**: Before `do_update()`, snapshot `.env`, `docker-compose.yml`, and `config.env`.
- **Auto-Rollback**: If `verify_containers_running()` or HTTP probes fail, restore the snapshot automatically.

#### 📋 4.2 Enhanced Pre-flight Diagnostics

- **Disk Space**: Verify `>500MB` available in `$INSTALL_DIR`.
- **Port Conflict**: Check if required ports (80, 443, etc.) are already bound.
- **Registry Access**: Test connectivity to `docker.io` and `ghcr.io` early.

#### 📋 4.3 Atomic File Placement

- **Logic**: Use `.new` suffixes for downloads, validate, and only then `mv` to final destination.

---

### Phase 5: Hardening & UX

#### 🔮 5.1 Secret Rotation Engine

- Implementation of `--rotate-secrets` to regenerate `JWT_SECRET` and restart stacks safely.

#### 🔮 5.2 Centralized Status Dashboard

- `deploy.sh` enhancement to show a live status table of ALL installed services (Up/Down, Ports, Uptime).

#### 🔮 5.3 Modular Systemd Helper

- Complete `TD-01` by providing a single function in `lib.sh` that takes `SERVICE_NAME` and `INSTALL_DIR` to generate the unit file.
>>>>>>> Stashed changes

---

## 📈 Priority Matrix

<<<<<<< Updated upstream
| ID | Improvement | Effort | Impact | Suggested order |
|---|---|---|---|---|
| 1.1 | CLI argument support | Low | High | **1st** |
| 1.2 | Env var override layer | Low | High | **1st** |
| 1.3 | Pre-flight checks | Low | High | **2nd** |
| 1.4 | Structured logging | Low | Medium | **2nd** |
| 2.1 | App-level health checks | Medium | High | **3rd** |
| 2.2 | Rollback on failed update | Medium | High | **3rd** |
| 2.3 | Secret rotation | Medium | Medium | 4th |
| 3.1 | Shared `lib.sh` | Medium | Very High | **Before adding more services** |
| 3.2 | Stack orchestrator | High | Very High | Once 2+ services exist |
| 3.3 | GitHub Actions CI | Low | Medium | Anytime |

---

## Recommended Next Step

Before adding a second service script (e.g. for Arcane or any future service),
implement **3.1 (shared `lib.sh`)** first. The refactor cost is minimal when there
are only 1–2 scripts, but grows significantly with each new service added without it.

The natural implementation sequence is:

```
1.4 (logging) → 1.1 + 1.2 (CLI + env vars) → 1.3 (preflight) →
3.1 (lib.sh)  → 2.1 (health checks)         → 2.2 (rollback)  →
3.2 (stack.sh)
```
=======
| Feature | Effort | Impact | Status |
|---|:---:|:---:|---|
| **Rollback on failure** | Medium | High | 📋 Planned |
| **Systemd Helper (`lib.sh`)** | Low | Medium | 📋 Quick-win |
| **Pre-flight diagnostics** | Low | High | 📋 Planned |
| **Status Dashboard** | Medium | High | 🔮 Future |
| **Secret rotation** | Medium | Medium | 🔮 Future |
>>>>>>> Stashed changes
