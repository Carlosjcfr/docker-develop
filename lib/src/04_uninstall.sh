# =============================================================================
# ATOMIC UNINSTALLATION ENGINE
# =============================================================================

# Internal helper to extract resources from a project directory.
# Uses podman-compose to parse the YAML and resolve variables.
_discover_compose_resources() {
    local dir="${1:?_discover_compose_resources requires a directory}"
    local compose_file="$dir/docker-compose.yml"

    if [ -f "$compose_file" ]; then
        # Use podman-compose config to resolve syntax and show the absolute state.
        # We extract images and container names (if defined).
        # We run this in the project directory so it can find .env files if present.
        (
            cd "$dir" 2>/dev/null || exit
            # Extract images: filter 'image:', remove prefix, remove quotes
            # Extract containers: if 'container_name' is used, we get it. 
            # If not, we fall back to podman's internal project mapping.
            podman-compose config 2>/dev/null
        )
    fi
}

# Centralized uninstallation logic for all services.
# Supports Dynamic Discovery: if docker-compose.yml exists, it ignores manual 
# arrays unless discovery fails.
# Requires:
#   UNINSTALL_SVC_NAME      (string) e.g. "ARCANE"
#   UNINSTALL_SYSTEMD       (string) e.g. "container-arcane.service"
#   INSTALL_DIR             (string) e.g. "/opt/arcane"
# Optional overrides (used as fallbacks):
#   UNINSTALL_CONTAINERS    (array)
#   UNINSTALL_IMAGES        (array)
#   UNINSTALL_VOLUMES       (array)
#   UNINSTALL_DIRS          (array)
#   UNINSTALL_DATA_WARN     (string)
uninstall_generic_service() {
    # 1. Discovery Phase
    local -a discovered_imgs=()
    local -a discovered_containers=()
    local compose_file="${INSTALL_DIR}/docker-compose.yml"

    if [ -f "$compose_file" ]; then
        log "Analyzing project resources dynamically..."
        # Extract images using a robust grep/awk on the resolve config
        # We use a subshell to avoid changing the current directory
        local raw_config
        raw_config=$(cd "$INSTALL_DIR" && podman-compose config 2>/dev/null || true)
        
        if [ -n "$raw_config" ]; then
            while read -r img; do
                [ -n "$img" ] && discovered_imgs+=("$img")
            done < <(echo "$raw_config" | grep 'image:' | awk '{print $2}' | tr -d '"' | tr -d "'" | sort -u)
            
            # For containers, if they aren't explicit in 'container_name', 
            # they are usually <project>_<service>_1. 
            # It's safer to use the manual list or 'podman ps' by label later.
        fi
    fi

    # Merge discovered with manual (prioritize discovered)
    if [ ${#discovered_imgs[@]} -gt 0 ]; then
        UNINSTALL_IMAGES=("${discovered_imgs[@]}")
    else
        UNINSTALL_IMAGES=("${UNINSTALL_IMAGES[@]:-}")
    fi

    # Fallback/Default arrays to empty if they are not defined, to avoid set -u crashes
    local -a local_containers=("${UNINSTALL_CONTAINERS[@]:-}")
    local -a local_volumes=("${UNINSTALL_VOLUMES[@]:-}")
    local -a local_dirs=("${UNINSTALL_DIRS[@]:-}")
    
    echo ""
    echo "=== ${UNINSTALL_SVC_NAME}: Uninstall ==="
    echo ""
    echo " WARNING: This will permanently remove:"
    echo "   - The container(s) and image(s)"
    echo "   - The systemd persistence service"
    echo ""

    if [ "${FORCE_YES:-0}" -eq 1 ]; then
        CONFIRM="UNINSTALL"
    else
        read -rp " Type 'UNINSTALL' to confirm: " CONFIRM < /dev/tty
    fi
    if [ "$CONFIRM" != "UNINSTALL" ]; then
        log "Uninstall cancelled."
        exit 0
    fi

    echo ""
    log "Stopping systemd service..."
    systemctl --user stop "$UNINSTALL_SYSTEMD" 2>/dev/null || true
    systemctl --user disable "$UNINSTALL_SYSTEMD" 2>/dev/null || true
    rm -f ~/.config/systemd/user/"$UNINSTALL_SYSTEMD"
    systemctl --user daemon-reload

    log "Removing container(s)..."
    # If we have manual containers, remove them. 
    # Also, try to remove by project label if podman-compose was used.
    for c in "${local_containers[@]}"; do
        [ -n "$c" ] && podman rm -f "$c" 2>/dev/null || true
    done
    
    # Advanced: Try to find containers by the directory name if it matches podman-compose pattern
    local project_name
    project_name=$(basename "$INSTALL_DIR" | tr -d '-') 
    podman ps -a --filter "label=com.docker.compose.project=$project_name" --format "{{.Names}}" | xargs -r podman rm -f 2>/dev/null || true

    log "Removing image(s)..."
    for i in "${UNINSTALL_IMAGES[@]}"; do
        [ -n "$i" ] && podman rmi "$i" 2>/dev/null || true
    done

    echo ""
    if [ "${FORCE_YES:-0}" -eq 1 ]; then
        DELETE_DATA="y"
    else
        if [ ${#local_volumes[@]} -gt 0 ] && [ -n "${local_volumes[0]:-}" ]; then
            echo " Persistent volumes connected to this service:"
            for v in "${local_volumes[@]}"; do [ -n "$v" ] && echo "   - $v"; done
        fi
        if [ ${#local_dirs[@]} -gt 0 ] && [ -n "${local_dirs[0]:-}" ]; then
            echo " Data directories connected to this service:"
            for d in "${local_dirs[@]}"; do [ -n "$d" ] && echo "   - $d"; done
        fi
        [ -n "${UNINSTALL_DATA_WARN:-}" ] && echo " $UNINSTALL_DATA_WARN"
        echo ""
        read -rp " Delete ALL data and the installation directory ($INSTALL_DIR)? [y/N]: " DELETE_DATA < /dev/tty
    fi

    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        log "Removing configuration, data, and installation directory..."
        if [ ${#local_volumes[@]} -gt 0 ] && [ -n "${local_volumes[0]:-}" ]; then
            for v in "${local_volumes[@]}"; do [ -n "$v" ] && podman volume rm "$v" 2>/dev/null || true; done
        fi
        if [ ${#local_dirs[@]} -gt 0 ] && [ -n "${local_dirs[0]:-}" ]; then
            for d in "${local_dirs[@]}"; do [ -n "$d" ] && sudo rm -rf "$d"; done
        fi
        sudo rm -rf "${INSTALL_DIR:?}"
        log "All data and directory removed."
    else
        if [ ${#local_volumes[@]} -gt 0 ] && [ -n "${local_volumes[0]:-}" ] || [ ${#local_dirs[@]} -gt 0 ] && [ -n "${local_dirs[0]:-}" ]; then
            log "Data preserved."
        fi
        sudo rm -f "${INSTALL_DIR:?}/.env" "${INSTALL_DIR:?}/config.env" "${INSTALL_DIR:?}/docker-compose.yml"
        log "Config files cleaned up, but installation directory ($INSTALL_DIR) preserved."
    fi

    echo ""
    echo "================================================================="
    echo " ${UNINSTALL_SVC_NAME} has been uninstalled."
    echo "================================================================="
}
