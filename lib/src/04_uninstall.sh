# =============================================================================
# UNINSTALLATION ENGINE
# =============================================================================

# Centralized uninstallation logic for all services.
# Requires the caller to set the following global variables:
#   UNINSTALL_SVC_NAME      (string) e.g. "ARCANE"
#   UNINSTALL_SYSTEMD       (string) e.g. "container-arcane.service"
#   UNINSTALL_CONTAINERS    (array)  e.g. ("arcane")
#   UNINSTALL_IMAGES        (array)  e.g. ("ghcr.io/getarcaneapp/arcane:latest")
#   UNINSTALL_VOLUMES       (array)  e.g. ("caddy_data" "caddy_config")
#   UNINSTALL_DIRS          (array)  e.g. ("/opt/arcane/data")
#   UNINSTALL_DATA_WARN     (string) e.g. "WARNING: All arcane projects will be lost!"
uninstall_generic_service() {
    # Default arrays to empty if they are not defined by the caller, to avoid set -u crashes
    local -a local_volumes=("${UNINSTALL_VOLUMES[@]:-}")
    local -a local_dirs=("${UNINSTALL_DIRS[@]:-}")
    
    echo ""
    echo "=== ${UNINSTALL_SVC_NAME}: Uninstall ==="
    echo ""
    echo " WARNING: This will permanently remove:"
    echo "   - The container(s) and image(s)"
    echo "   - The systemd persistence service"
    echo ""

    if [ "$FORCE_YES" -eq 1 ]; then
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
    for c in "${UNINSTALL_CONTAINERS[@]}"; do
        podman rm -f "$c" 2>/dev/null || true
    done

    log "Removing image(s)..."
    for i in "${UNINSTALL_IMAGES[@]}"; do
        podman rmi "$i" 2>/dev/null || true
    done

    echo ""
    if [ "$FORCE_YES" -eq 1 ]; then
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
            for d in "${local_dirs[@]}"; do [ -n "$d" ] && rm -rf "$d"; done
        fi
        rm -rf "${INSTALL_DIR:?}"
        log "All data and directory removed."
    else
        if [ ${#local_volumes[@]} -gt 0 ] && [ -n "${local_volumes[0]:-}" ] || [ ${#local_dirs[@]} -gt 0 ] && [ -n "${local_dirs[0]:-}" ]; then
            log "Data preserved."
        fi
        rm -f "${INSTALL_DIR:?}/.env" "${INSTALL_DIR:?}/config.env" "${INSTALL_DIR:?}/docker-compose.yml"
        log "Config files cleaned up, but installation directory ($INSTALL_DIR) preserved."
    fi

    echo ""
    echo "================================================================="
    echo " ${UNINSTALL_SVC_NAME} has been uninstalled."
    echo "================================================================="
}
