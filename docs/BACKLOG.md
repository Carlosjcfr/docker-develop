# Product Backlog & Task Tracker

This document tracks the implementation status of all proposed features and architectural improvements identified in the documentation.

---

## 🟢 Done (Finalizadas)

| Feature | Source Document | Description |
| :--- | :--- | :--- |
| **Permission Denied in `rm -rf`** | `04_uninstall.sh` | High |
| **Atomic Uninstall Engine** | `ROADMAP.md` | Dynamic resource discovery (Compose) + Sudo-fix for permissions. |
| **Arcane Self-Management Guard** | `lib/src/05_arcane.sh` | Prevents Arcane from managing (and stopping) itself. |
| **Source Module Restoration** | `lib/build.sh` | `05_arcane.sh` correctly integrated into the library entry point. |
| **Unified Service Manager** | `ARCHITECTURE.md` | Single entry point via `deploy.sh`. |
| **Compiled Shared Library** | `ARCHITECTURE.md` | Centralized `lib/lib.sh` logic. |
| **Security Hardening** | `ARCHITECTURE.md` | Non-root, umask 177, auto-secrets. |
| **Automation CLI Flags** | `ROADMAP.md` | Support for `--install`, `--update`, `--yes`. |
| **Diagnostic Probes** | `ROADMAP.md` | Post-deploy HTTP health checks. |
| **Git Hook Automation** | `ARCHITECTURE.md` | Automatic compilation of `lib.sh`. |
| **Syntax Validation** | `TEMPLATE_OPTIMIZATION_PLAN.md` | `podman-compose config` check before deploy. |
| **Arcane Sync Engine** | `ARCANE_ORGANIZATION_ANALYSIS.md` | Copy + Label patching (Replaces symlinks). |
| **Dynamic Image Uninstall** | `TEMPLATE_OPTIMIZATION_PLAN.md` | Auto-detection in `lib.sh` via labels and compose parsing. |
| **Library API Abstraction** | `LIBRARY_DOCUMENTATION_ANALYSIS.md` | Extracted generic documentation to markdown, slimming bash source. |

---

## 🔵 Testing (En Pruebas)

> [!TIP]
> Tasks move here once implemented. If tests pass, move to **Done**. If bugs are found, move to **Debug**.

| Feature | Source Document | Current State |
| :--- | :--- | :--- |
| | | |

---

## 🟠 Debug (Corrección de Errores)

| Bug / Issue | Source Document | Priority |
| :--- | :--- | :--- |

---

## 🟡 In Progress (En Curso)

| Feature | Source Document | Current State |
| :--- | :--- | :--- |
| **Atomic Backups (`.bak`)** | `TEMPLATE_OPTIMIZATION_PLAN.md` | Basic logic tested in Supabase; needs moving to `lib.sh`. |
| **Interactive Fallback** | `DYNAMIC_TAG_RESOLUTION_PLAN.md` | Interactive patch to `:latest` in Supabase; needs generalization. |

---

## 🔴 Pending (Pendientes)

| Feature | Source Document | Category |
| :--- | :--- | :--- |
| **Arcane Phase 2 (Webhook Agent)** | `ARCANE_EVOLUTION_ANALYSIS.md` | Management / UX |
| **Metadata Labels (Icons/Groups)** | `ARCANE_ORGANIZATION_ANALYSIS.md` | UI / Aesthetics |
| **Simplified Container Naming** | `ARCANE_ORGANIZATION_ANALYSIS.md` | Architecture / UX |
| **Dynamic Tag Resolution** | `DYNAMIC_TAG_RESOLUTION_PLAN.md` | Reliability |
| **Silent Pull with Logging** | `TEMPLATE_OPTIMIZATION_PLAN.md` | UX / Diagnostics |
| **Rollback on Health Failure** | `ROADMAP.md` | Stability |
| **Stack Orchestrator (`stack.sh`)** | `ROADMAP.md` | Automation |
| **Enhanced Pre-flight Checks** | `ROADMAP.md` | Reliability |
| **Atomic File Placement** | `ROADMAP.md` | Reliability |
