# Product Backlog & Task Tracker

This document tracks the implementation status of all proposed features and architectural improvements identified in the documentation.

---

## 🟢 Done (Finalizadas)

| Feature | Source Document | Description |
| :--- | :--- | :--- |
| **Unified Service Manager** | `ARCHITECTURE.md` | Single entry point via `deploy.sh`. |
| **Compiled Shared Library** | `ARCHITECTURE.md` | Centralized `lib/lib.sh` logic. |
| **Generic Uninstall Engine** | `ROADMAP.md` | Standardized resource cleanup logic. |
| **Security Hardening** | `ARCHITECTURE.md` | Non-root, umask 177, auto-secrets. |
| **Automation CLI Flags** | `ROADMAP.md` | Support for `--install`, `--update`, `--yes`. |
| **Diagnostic Probes** | `ROADMAP.md` | Post-deploy HTTP health checks. |
| **Git Hook Automation** | `ARCHITECTURE.md` | Automatic compilation of `lib.sh`. |
| **Syntax Validation** | `TEMPLATE_OPTIMIZATION_PLAN.md` | `podman-compose config` check before deploy. |

---

## 🟡 In Progress (En Curso)

| Feature | Source Document | Current State |
| :--- | :--- | :--- |
| **Atomic Backups (`.bak`)** | `TEMPLATE_OPTIMIZATION_PLAN.md` | Implemented in individual scripts (Supabase); needs moving to `lib.sh`. |
| **Dynamic Image Uninstall** | `TEMPLATE_OPTIMIZATION_PLAN.md` | Implemented in Supabase; needs standardization in other services. |
| **Interactive Fallback** | `DYNAMIC_TAG_RESOLUTION_PLAN.md` | Basic implementation in Supabase for tag failures. |

---

## 🔴 Pending (Pendientes)

| Feature | Source Document | Category |
| :--- | :--- | :--- |
| **Project Symlinks (Arcane)** | `ARCANE_ORGANIZATION_ANALYSIS.md` | UI / Organization |
| **Metadata Labels (Icons/Groups)** | `ARCANE_ORGANIZATION_ANALYSIS.md` | UI / Aesthetics |
| **Simplified Container Naming** | `ARCANE_ORGANIZATION_ANALYSIS.md` | Architecture / UX |
| **Dynamic Tag Resolution** | `DYNAMIC_TAG_RESOLUTION_PLAN.md` | Reliability |
| **Silent Pull with Logging** | `TEMPLATE_OPTIMIZATION_PLAN.md` | UX / Diagnostics |
| **Rollback on Health Failure** | `ROADMAP.md` | Stability |
| **Stack Orchestrator (`stack.sh`)** | `ROADMAP.md` | Automation |
| **Enhanced Pre-flight Checks** | `ROADMAP.md` | Reliability |
| **Atomic File Placement** | `ROADMAP.md` | Reliability |
