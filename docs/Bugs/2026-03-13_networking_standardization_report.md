# Bug Report & Improvements: Networking Standardization (March 2026)

## 1. Subnet IP Collision Risk (Core Library)

### Description
The `assign_project_ip` function in `lib/src/02_install.sh` originally only scanned active Podman containers to identify occupied IP addresses within the `internal_net` (172.170.1.0/24).

### The Problem
If a project was stopped (container not running), its IP was not detected as "in use". If a new service was installed at that moment, the library could assign the same IP to the new project. This caused a networking conflict as soon as the user tried to start the original service.

### Fix / Improvement
The function was updated to perform a dual-check:
1. **Dynamic Check**: Scans `podman network inspect` for active containers.
2. **Persistence Check**: Scans all `.env` files in `/opt/*/` for the `PROJECT_IP` variable.
   
This ensures that even stopped services have their IPs reserved in the registry of the local filesystem.

---

## 2. AnyType Project Misalignment

### Description
The `anytype` project (under `projects/anytype`) was identified as outdated regarding the "One IP per Project" architecture.

### Identified Issues
- **Missing IP Logic**: `anytype.sh` did not call `assign_project_ip` during installation.
- **Persistence Failure**: The `PROJECT_IP` variable was not being written to the runtime `.env` file.
- **Compose Networking**: The `docker-compose.yml` was using default bridge networking instead of the mandatory `internal_net` with a static IP.
- **Update Logic**: `do_update` was a simple alias for `do_install`, missing the logic to preserve the already assigned IP.

### Fix
- Updated `anytype.sh` to include `assign_project_ip` in `do_install`.
- Modified `do_update` to extract and preserve the existing `PROJECT_IP` from `/opt/anytype/.env`.
- Patched `docker-compose.yml` to:
    - Define `internal_net` as an external network.
    - Attach all services to `internal_net`.
    - Assign `${PROJECT_IP}` static address to the `any-sync-coordinator` node.

---

## 3. Library Synchronization

### Action Taken
After modifying the source module `lib/src/02_install.sh`, the shared library `lib/lib.sh` was recompiled using `bash lib/build.sh` to ensure all projects benefit from the fix immediately.
