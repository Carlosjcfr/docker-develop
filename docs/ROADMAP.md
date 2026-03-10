# Install Script Roadmap — Towards Full Automation

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

## Current Status (March 2026)

The framework has completed its initial architecture phase. Key features implemented:

- ✅ **Unified Service Manager (`deploy.sh`)**
- ✅ **Compiled Shared Library (`lib/lib.sh`)**: High-performance, single-file delivery.
- ✅ **Generic Uninstall Engine**: Consistent and safe resource cleanup.
- ✅ **Security Hardening**: Non-root execution, auto-generated secrets, umask 177 protection.
- ✅ **Automation-Ready**: CLI flags (`--install`, `--update`, `--yes`, `--dry-run`) and `curl | bash` pipe support.
- ✅ **Diagnostic Intelligence**: Proactive pre-flight checks and post-deploy application health Probes (HTTP).
- ✅ **Git Hook Automation**: `pre-commit` hook for automatic library compilation.

---

## Future Goals

### Phase 4 (Tier 2/3 Strategy)

#### 📋 4.1 Rollback & Pre-update Snapshots

- **The Problem**: Overwriting files or updating images can lead to broken services with no easy way back.
- **The Solution**: Before `do_update()`, snapshot the current `.env`, `docker-compose.yml`, and `config.env`. If health checks fail post-update, automatically restore and restart the previous stack.
- **Trigger**: `verify_containers_running()` or HTTP health probes failing.

#### 📋 4.2 Enhanced Pre-flight Diagnostics

- **Disk Space Check**: Verify minimum available space (e.g., 500MB) before pulling heavy images.
- **Port Availability**: Check if `80`, `443`, or the service port are already bound by another process.
- **Image Reachability**: Check `docker.io` and GitHub connectivity before attempting downloads.

#### 📋 4.3 Atomic File Placement

- **The Problem**: A mid-update failure or interruption can leave the installation directory in a partial, broken state.
- **The Solution**: Download new files with a `.new` suffix, validate their syntax, and perform atomic `mv` operations only once the script is ready for the restart.

#### 📋 4.4 Optimización de Salida de Podman & Progress Bar

- **The Problem**: Imágenes compuestas por cientos de capas (como Supabase) inundan la salida de la terminal con mensajes "skipped: already exists", restando visibilidad a los logs de orquestación críticos. El usuario final percibe el proceso como "caótico" en lugar de estructurado.
- **The Solution**: Implementar un sistema de "Silent Mode" por defecto que redirija la salida verbosa a un archivo de log temporal (`/tmp/install.log`) y muestre una barra de progreso visual o una lista de estados simplificada.

**Análisis de la Feature:**

| Aspecto | Consideración |
| :--- | :--- |
| **Pros** | UX premium (limpia y profesional), reducción del ruido visual, facilidad para identificar fallos reales vs. ruido de red. |
| **Contras** | Mayor complejidad en Bash (manejo de subprocesos y señales), dificultad para estimar tiempos exactos en descargas paralelas. |
| **Riesgos** | Si el proceso se congela sin salida visual, el usuario puede interrumpirlo prematuramente. |

**Posibles Implementaciones:**

1. **Iterativa Secuencial (Precisión Alta)**: Pull individual de cada imagen definida en el `compose.yaml` mostrando un contador `[1/8]`. Permite saber exactamente qué imagen falla.
2. **Monitorización de Log (UX Moderna)**: Lanzar `podman-compose pull` en background y usar un bucle `while` para actualizar una barra de progreso basada en el número de imágenes completadas detectadas en el log.
3. **Spinner + Status**: Un indicador animado simple con el nombre del servicio actual siendo procesado (e.g., `⠋ Pulling supabase-db...`).

- **Impact**: Mejora drástica de la UX visual en terminal y reducción del búfer generado, acercándose a la experiencia de herramientas tipo `gh` o `docker` (v2).

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

```text
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

---

## Priority Matrix

| ID | Improvement | Effort | Impact | Suggested order |
| :--- | :--- | :--- | :--- | :--- |
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

## Recommended Next Step (Evaluation)

The originally proposed sequence was:

```text
1.4 (logging) → 1.1 + 1.2 (CLI + env vars) → 1.3 (preflight) →
3.1 (lib.sh)  → 2.1 (health checks)         → 2.2 (rollback)  →
3.2 (stack.sh)
```

**Current Fulfillment Status**:
The sequence has been successfully implemented up to **2.1 (health checks)**. `lib.sh` acts as a solid core, logging is standardized, CLI flags are functional, and pre-flight/HTTP health checks are operational. However, the sequence is **NOT completely fulfilled**.

### Missing Implementation 1: 2.2 (Rollback on Failed Updates)

- **Why it is missing:** The update logic (`do_update()`) currently creates passive backups (`.bak` files) of configurations. However, if the new containers crash or fail the post-update health checks, the script simply aborts (exit code 3), leaving the environment in a broken state. The focus so far has been on fresh installations and fixing initial deployment bugs rather than update resilience.
- **How to solve it:** Wrap the update deployment and health-check execution in a logical validation block. If `verify_containers_running` or `check_http_health` fails after an update, the script must automatically trigger a new `rollback()` function. This function will stop the broken containers, restore `.env`, `docker-compose.yml`, and `config.env` from their `.bak` variants, and re-deploy the previous known-good state.

### Missing Implementation 2: 3.2 (Top-Level Orchestrator `stack.sh`)

- **Why it is missing:** Recent development efforts prioritized the stabilization of complex individual macro-services (like Supabase and Arcane) and ensuring their compatibility with rootless Podman environments, delaying the need for a global orchestrator.
- **How to solve it:** Create a master `stack.sh` script in the root directory. This script will define a strict dependency graph (e.g., Caddy Proxy must run first), aggregate the configuration, and sequentially invoke each individual service script using the `--install` and `--yes` flags for a fully automated, one-click server provisioning workflow.
