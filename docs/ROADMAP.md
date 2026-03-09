# Development Roadmap

This document outlines the current state and future improvements for the `docker-develop` service installation framework.

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

---

### Phase 5 (Advanced Strategy)

#### 🔮 5.1 Secret Rotation
- **The Problem**: Reusing `JWT_SECRET` for years is a security risk.
- **The Solution**: Add a `--rotate-secrets` flag to regenerate credentials, back up the old `.env`, and restart the service clusters.

#### 🔮 5.2 Repository Organization (Archive Mode)
- **The Problem**: As more services are added, the repository grows.
- **The Solution**: Implement "Service Archival" where older or less-used services are moved to an experimental bucket.

---

## Priority Matrix

| Feature | Effort | Impact | Status |
|---|:---:|:---:|---|
| Rollback on failure | Medium | High | 📋 Planned |
| Pre-flight diagnostics | Low | High | 📋 Planned |
| Atomic file placement | Medium | Medium | 🔮 Future |
| Secret rotation | Medium | Low | 🔮 Future |
