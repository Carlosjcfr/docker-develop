# Features Roadmap

> **Purpose:** Consolidated, prioritized feature list for the `docker-develop`
> service installation framework. Each feature is framed around the core goals:
> **security**, **permission correctness**, **error diagnosis**, and **automation**.
>
> For architectural detail see:
> - `ROADMAP.md` — Tier 1 and Tier 2 improvements to individual scripts
> - `TIER3_ORCHESTRATION_PLAN.md` — lib.sh, deploy.sh, and CI
> - `SCRIPT_ARCHITECTURE.md` — current caddy.sh design patterns

---

## Core Philosophy

> **Each service is installed by its own script. The framework makes that
> script secure, diagnosable, and automation-ready — not complex.**

The system is built around three layers:

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1 — Entry point                                          │
│  deploy.sh  →  discovers services, shows menu, dispatches       │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 2 — Shared foundation                                    │
│  lib.sh  →  security, permissions, diagnosis, common guards     │
├─────────────────────────────────────────────────────────────────┤
│  LAYER 3 — Service-specific scripts                             │
│  caddy.sh / arcane.sh / <service>.sh                            │
│  Only contains: config, env template, deploy, uninstall logic   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Feature Status Legend

| Symbol | Meaning |
|:---:|---|
| ✅ | Implemented |
| 🔄 | Partially implemented |
| 📋 | Planned — documented, not started |
| 🔮 | Future consideration |

---

## F1 — Security & Secrets

### F1.1 — Secret isolation (no secrets in repo) ✅
Secrets (`JWT_SECRET`, `ENCRYPTION_KEY`, etc.) are never committed to the repository.
They are auto-generated on first install and stored only in the local `.env` file
(permissions 600, `umask 177`).

**Where:** `manage_credentials()` + `generate_runtime_env()` in each service script

---

### F1.2 — Secret detection guard ✅
The script aborts with a clear error if a secret key is detected in `config.env`
(the repo-committed file). Prevents accidental exposure via version control.

**Where:** `load_configuration()` in each service script

---

### F1.3 — Root execution prevention ✅
Scripts must NOT run as root to preserve Podman rootless isolation.
`root_protection()` aborts immediately if `EUID == 0`.

**Exit code:** `1`

---

### F1.4 — Runtime `.env` hardening ✅
The runtime `.env` is written with `umask 177`, resulting in mode `600`.
Readable only by the installing user.

---

### F1.5 — Secret rotation 📋
Deliberate rotation of generated secrets via `--rotate-secrets` flag.
Backs up the current `.env`, regenerates secrets, restarts the stack.
Warns that active sessions will be invalidated.

**Scope:** `lib.sh` (rotation logic) + each service script (restart hook)

---

### F1.6 — SELinux volume label enforcement ✅
Volume mounts in `docker-compose.yml` use the `:Z` flag for SELinux relabeling.
Prevents permission denied errors on RHEL/AlmaLinux/Fedora VMs.

**Status:** Applied to ALL services. Verified in `caddy.sh` and `arcane.sh`.

---

## F2 — Permission & Directory Correctness

### F2.1 — Install directory writability guard ✅
Before writing any files, `check_install_dir_writable()` verifies that
`$INSTALL_DIR` is writable by the current user. If not, aborts with:

```
ERROR [exit 2]: INSTALLATION DIRECTORY NOT WRITABLE
REQUIRED PREREQUISITE STEP:
  sudo mkdir -p /opt/<service> && sudo chown $USER:$USER /opt/<service>
```

**Exit code:** `2`  
**Where:** `lib.sh` (inherited by all services)

---

### F2.2 — Data directory ownership enforcement ✅
For services with persistent data directories (e.g. SQLite databases, project files),
the install script explicitly sets ownership via `chown` after directory creation.

**Where:** Standardized in each service script's `prepare_directories()` using
globals set by `lib.sh` (`$PUID`, `$PGID`).

---

### F2.3 — Caddyfile and user config preservation ✅
On updates, user-modified config files (e.g. `Caddyfile`) are never overwritten.
The script checks for their existence before placing defaults.

---

### F2.4 — Atomic file placement 📋
Currently, files are `mv`'d from a temp dir into `$INSTALL_DIR`. This is
atomic at the filesystem level. However, on update, if the script is interrupted
mid-way, the install dir may be in a partially updated state.

**Proposal:** Write new files alongside with a `.new` suffix, validate them,
then atomically rename. Roll back if validation fails.

---

## F3 — Error Diagnosis

### F3.1 — Specific exit codes ✅
Every failure category has a dedicated exit code with a documented meaning:

| Code | Category |
|:---:|---|
| `0` | Success or deliberate cancellation |
| `1` | Guard failure (root exec, missing dep, secret in repo, IP detection, Podman socket) |
| `2` | Prerequisite missing: install directory not writable |
| `3` | Deployment failure: containers not running after deploy |

---

### F3.2 — Post-deploy container state check ✅
`verify_containers_running()` checks each required container is in `running` state
after `podman-compose up -d` (which always exits 0, even on total failure).
Aborts with actionable error and diagnostic commands if any container is missing.

**Where:** `lib.sh` (inherited by all services)

---

### F3.3 — Pre-flight checks 📋
A `preflight_checks()` function that validates all preconditions **before
writing any files**. Detects problems early, before partial state is created.

Planned checks:

| Check | Detects |
|---|---|
| DNS resolution of `raw.githubusercontent.com` | Network issues before any download |
| Reachability of `docker.io` | Registry access before `podman pull` |
| Available disk space in `$INSTALL_DIR` (min 500MB) | Prevents mid-pull failures |
| Podman minimum version (≥ 4.0) | Incompatible older installations |
| Conflicting container names already running | Pre-existing containers with same name |
| Port availability (80, 443, service port) | Already-bound ports |
| `ip_unprivileged_port_start` value | Warn early if sysctl sudo will be needed |

**Exit code:** `1` for any failed pre-flight check  
**Where:** Will live in `lib.sh`; called at the start of `do_install()` and `do_update()`

---

### F3.4 — Application-level HTTP health checks ✅
After verifying that containers are running (F3.2), perform HTTP health checks
against service endpoints to confirm the application inside is actually responding.

```bash
# Example for caddy stack:
poll_http "http://127.0.0.1:2019/config/"  30 2   # Caddy Admin API
poll_http "http://127.0.0.1:3000/health"   30 2   # CaddyManager backend
poll_http "http://127.0.0.1:8080/"         30 2   # CaddyManager frontend
```

- Poll with configurable timeout (default 30s, retry every 2s)
- Report which endpoint is not responding to pinpoint the failure layer
- Exit code `3` preserved; error message becomes more specific

**Where:** `lib.sh` provides `poll_http()` and `check_http_health()`

---

### F3.5 — Structured logging ✅
Standardized `log()` / `warn()` / `err()` helpers in `lib.sh` with UTC timestamps
and levels.

```
[14:32:01] [INFO]  Downloading files from repository...
[14:32:04] [ERROR] Deployment failed — caddy container not running
```

Outputs can be redirected to `tee` for persistent log files.

**Where:** `lib.sh` (inherited by all services)

---

## F4 — Automation & CI/CD Readiness

### F4.1 — Non-interactive / pipe mode ✅
When stdin is not a TTY (i.e. `curl ... | bash`), all interactive prompts are
suppressed and the script runs in automatic mode (install or update as appropriate).

---

### F4.2 — CLI argument support ✅
Named flags for full non-interactive control, enabling use from Ansible, Terraform,
or shell provisioners without file modifications.

```bash
bash caddy.sh --install
bash caddy.sh --update
bash caddy.sh --uninstall --yes          # skip confirmation prompts
bash caddy.sh --install --dry-run
INSTALL_DIR=/srv/caddy bash caddy.sh --install
```

**Where:** `parse_args()` in `lib.sh`; applied to all service scripts

---

### F4.3 — Environment variable override layer 📋
Shell environment variables override `config.env` defaults without modifying files.
Priority chain: CLI flags → shell env vars → config.env → script defaults.

```bash
CADDYMANAGER_UI_PORT=9090 ACME_EMAIL=ops@example.com bash caddy.sh --install
```

**Where:** `load_configuration()` in each service script (already uses `${VAR:-default}`
pattern; shell env vars override automatically — needs documentation and testing)

---

### F4.4 — Dry-run mode ✅
`--dry-run` flag runs all checks and prints the fact that dry-run is enabled.
(Full command-by-command simulation planned for Phase 4 CI).

```bash
bash caddy.sh --install --dry-run
```

**Where:** `lib.sh` exports a `DRY_RUN=1` flag; each side-effecting function respects it

---

### F4.5 — GitHub Actions CI 📋
Automated validation on every push to `lib/`, `projects/**/*.sh`, or `deploy.sh`:
- **ShellCheck** static analysis
- **Dry-run** execution in a Podman-enabled Ubuntu runner

Triggers: any push that modifies shell scripts or the shared library.

---

## F5 — Universal Service Manager (`deploy.sh`)

### F5.1 — Service discovery from registry ✅
`deploy.sh` maintains a service registry (Bash array).
Each entry defines: display name, script path, install dir, main container name, description.

---

### F5.2 — Installation status in menu ✅
Before showing the service list, `deploy.sh` checks which services are already
installed (via `[ -f install_dir/.env ] && podman container exists main_container`).
Status is shown next to each service:

```
  1) Caddy Proxy + Manager   [INSTALLED]
  2) Arcane                  [NOT INSTALLED]
```

---

### F5.3 — Service dispatch ✅
Selecting a service downloads its script and runs it. The service script then
shows its own management menu (install/start/update/uninstall).
`deploy.sh` never implements service-specific logic.

```bash
# Single command to access everything:
curl -fsSL "https://raw.githubusercontent.com/Carlosjcfr/docker-develop/main/deploy.sh" | bash
```

---

## F6 — Rollback & Recovery

### F6.1 — Pre-update snapshot 📋
Before `do_update()` overwrites files, snapshot current `.env`, `docker-compose.yml`,
and `config.env` to `$INSTALL_DIR/.snapshots/<timestamp>/`.

---

### F6.2 — Automatic rollback on failed update 📋
If `verify_containers_running()` or HTTP health checks (F3.4) fail after an update,
automatically restore the last snapshot and restart the previous containers.

Manual trigger: `bash <service>.sh --rollback`

---

## Priority Matrix

| Feature | Area | Effort | Impact | Status |
|---|---|:---:|:---:|---|
| F2.1 `check_install_dir_writable` in arcane.sh | Permissions | XS | High | 📋 Quick fix |
| F3.2 `verify_containers_running` in arcane.sh | Diagnosis | XS | High | 📋 Quick fix |
| F3.5 Structured logging (`lib.sh`) | Diagnosis | S | Medium | 📋 Phase 0 |
| F4.2 CLI argument support | Automation | S | High | 📋 Phase 0 |
| **lib.sh extraction** | Foundation | M | Very High | 📋 Phase 1 |
| F3.3 Pre-flight checks | Diagnosis | S | High | 📋 Phase 1 |
| F4.4 Dry-run mode | Automation | S | High | 📋 Phase 1 |
| F5.1–F5.3 `deploy.sh` | UX | M | High | 📋 Phase 2 |
| F3.4 HTTP health checks | Diagnosis | M | Medium | 📋 Phase 2 |
| F4.5 GitHub Actions CI | Automation | S | Medium | 📋 Phase 3 |
| F6.1–F6.2 Rollback | Recovery | L | Medium | 📋 Phase 3 |
| F1.5 Secret rotation | Security | M | Low | 🔮 Future |
| F2.4 Atomic file placement | Reliability | M | Low | 🔮 Future |

---

## Development Sequence

```
Phase 0 — Fix existing gaps (no architecture changes)
  ├── Add F2.1 + F3.2 to arcane.sh
  ├── Fix TD-05: replace podman generate systemd in arcane.sh
  └── Add F3.5: log()/warn()/err() to both scripts

Phase 1 — lib.sh (foundation for everything else)
  ├── Extract shared functions to lib/lib.sh
  ├── Refactor caddy.sh + arcane.sh to source lib.sh
  ├── Add F4.2 (CLI args) + F4.4 (dry-run) via parse_args() in lib.sh
  └── Add F3.3 (pre-flight checks) to lib.sh

Phase 2 — deploy.sh (service manager entry point)
  ├── Create deploy.sh with service registry
  ├── Implement F5.1 (registry) + F5.2 (status) + F5.3 (dispatch)
  └── Add F3.4 (HTTP health checks) to lib.sh

Phase 3 — Hardening
  ├── GitHub Actions CI (F4.5) using dry-run from Phase 1
  └── Rollback (F6.1 + F6.2)
```
