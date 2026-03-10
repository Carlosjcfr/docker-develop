# Arcane Organization Analysis

This document analyzes how to improve the organization and visibility of services deployed via `docker-develop` within the **Arcane** management UI.

---

## 1. Problem Identification

Currently, services are deployed as individual containers in directories like `/opt/supabase` or `/opt/caddy`. From Arcane's perspective:
- Containers appear as a "flat list".
- There is no logical grouping (Stack/Project) in the UI.
- Managing a full stack (e.g., stopping all Supabase containers) requires individual actions.
- Container icons are generic, making the dashboard less intuitive.

---

## 2. Proposed Improvements

### 2.1. Dynamic Project Registration (Symlinks)
Arcane manages projects located in its internal `/app/data/projects` directory. On the host, this maps to `/opt/arcane/projects`.

**Proposed Change**:
Modify `lib.sh` or service scripts to create a symbolic link in Arcane's projects directory after a successful deployment.

```bash
# Example for Supabase
mkdir -p /opt/arcane/projects
ln -sfn /opt/supabase /opt/arcane/projects/supabase
```

**Benefits**:
- The service will appear in the **"Projects"** sidebar in Arcane.
- All containers in the stack are grouped under a single heading.
- Enables "Bulk Actions" (Start/Stop/Restart) for the entire project.

### 2.2. Standardized Labels for Metadata
Adding specific Docker/Podman labels to the `docker-compose.yml` files allows Arcane to enhance the UI.

| Label Key | Purpose | Example Value |
| :--- | :--- | :--- |
| `dev.arcane.icon` | Defines the icon shown in the dashboard | `si:supabase` or `mdi:database` |
| `com.docker.compose.project` | Explicitly groups containers (usually automatic) | `supabase` |
| `dev.arcane.category` | Categorizes the service for filtering | `Database`, `Proxy`, `UI` |

### 2.3. Container Naming Strategy
If projects are used, container names can be simplified.
- **Current**: `supabase-db`, `supabase-auth`, `supabase-rest`
- **With Projects**: `db`, `auth`, `rest` (Arcane shows them inside the "Supabase" project anyway).

---

## 3. Implementation Roadmap

| Step | Action | Priority |
| :--- | :--- | :--- |
| **Phase 1** | Implement `register_arcane_project` function in `lib.sh`. | High |
| **Phase 2**| Add `labels` section to existing `docker-compose.yml` files. | Medium |
| **Phase 3**| Update `config.env` templates to include icon preferences. | Low |

---

## 4. Summary Table

| Feature | Action | UI Impact |
| :--- | :--- | :--- |
| **Grouping** | Symlink to `/opt/arcane/projects/` | Sidebar entry + Collapsible stacks |
| **Icons** | Label `dev.arcane.icon` | Professional, recognizable dashboard |
| **Cleanliness**| Simplified `container_name` | Reduced visual clutter in project views |
| **Persistence**| Integrated via `podman-compose` | Real-time resource monitoring by group |
