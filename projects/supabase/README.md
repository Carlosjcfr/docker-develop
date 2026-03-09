# Supabase

Deploy of the open-source Firebase alternative matching your `docker-develop` rootless framework guidelines.

### Service Endpoints
- **Studio (Dashboard):** `http://{IP}:3000`
- **Kong (API Gateway):** `http://{IP}:8000`
- **Postgres (DB):** `{IP}:5432`

### Security
- Passwords and JWT secrets are dynamically generated into `config.env`/`.env` automatically via the setup script.
- All persistent volumes use the `:Z` flag for safe rootless SELinux mapping.

### Quick Start
To install on your active dev-server running Podman rootless:
```bash
./projects/supabase/supabase.sh --install
```
