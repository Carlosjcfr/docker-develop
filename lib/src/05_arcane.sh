# =============================================================================
# ARCANE INTEGRATION
# =============================================================================

# Register the service as a "Project" in Arcane by copying configs.
# Arcane maps its internal /app/data/projects to host /opt/arcane/projects.
# Usage: register_arcane_project PROJECT_NAME INSTALL_DIR
register_arcane_project() {
    local project_name="${1:?register_arcane_project requires a project name}"
    local install_dir="${2:?register_arcane_project requires an installation directory}"
    local arcane_projects_dir="/opt/arcane/projects"

    if [[ "$project_name" == "arcane" ]]; then
        log "Skipping Arcane self-registration to prevent circular self-management."
        return 0
    fi

    log "Registering project '$project_name' in Arcane..."

    # Ensure the parent directory exists
    if ! [ -d "$arcane_projects_dir/$project_name" ]; then
        if sudo mkdir -p "$arcane_projects_dir/$project_name" && sudo chown -R "$USER:$USER" "$arcane_projects_dir" 2>/dev/null; then
            log "  Created Arcane projects directory: $arcane_projects_dir/$project_name"
        else
            warn "  Could not create Arcane projects directory. Skipping registration."
            return 1
        fi
    fi

    # Copy files instead of symlinking. Symlinks break because they point to paths 
    # outside the Arcane container (e.g. /opt/supabase) which are not mounted.
    cp -f "$install_dir/docker-compose.yml" "$arcane_projects_dir/$project_name/"
    [ -f "$install_dir/.env" ] && cp -f "$install_dir/.env" "$arcane_projects_dir/$project_name/"
    
    # CRITICAL FIX: Arcane matches containers to projects by reading the 
    # 'com.docker.compose.project.working_dir' label from the running container
    # and looking for a docker-compose.yml in that EXACT directory inside its own container.
    # Since podman runs on the host at /opt/<slug>, the label says /opt/<slug>.
    # But inside Arcane, the file is at /app/data/projects/<slug>.
    # We must patch the copied compose file to FORCE the working_dir label
    # to match the container's internal path, or Arcane will never link them.
    sed -i -E "s|com.docker.compose.project.working_dir=.*|com.docker.compose.project.working_dir=/app/data/projects/$project_name|g" "$arcane_projects_dir/$project_name/docker-compose.yml" || true
    
    # If the label wasn't there to replace, inject it under the first 'labels:' section
    if ! grep -q "com.docker.compose.project.working_dir" "$arcane_projects_dir/$project_name/docker-compose.yml"; then
        sed -i "0,/labels:/s//labels:\n      - \"com.docker.compose.project.working_dir=\/app\/data\/projects\/$project_name\"/g" "$arcane_projects_dir/$project_name/docker-compose.yml" || true
    fi

    log "  Config synced to Arcane: $arcane_projects_dir/$project_name"
}
