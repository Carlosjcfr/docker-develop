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
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ]; then
            echo " Persistent volumes connected to this service:"
            for v in "${UNINSTALL_VOLUMES[@]}"; do echo "   - $v"; done
        fi
        if [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
            echo " Data directories connected to this service:"
            for d in "${UNINSTALL_DIRS[@]}"; do echo "   - $d"; done
        fi
        [ -n "${UNINSTALL_DATA_WARN:-}" ] && echo " $UNINSTALL_DATA_WARN"
        echo ""
        read -rp " Delete ALL data and the installation directory ($INSTALL_DIR)? [y/N]: " DELETE_DATA < /dev/tty
    fi

    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        log "Removing configuration, data, and installation directory..."
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ]; then
            for v in "${UNINSTALL_VOLUMES[@]}"; do podman volume rm "$v" 2>/dev/null || true; done
        fi
        if [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
            for d in "${UNINSTALL_DIRS[@]}"; do rm -rf "$d"; done
        fi
        rm -rf "${INSTALL_DIR:?}"
        log "All data and directory removed."
    else
        if [ ${#UNINSTALL_VOLUMES[@]} -gt 0 ] || [ ${#UNINSTALL_DIRS[@]} -gt 0 ]; then
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
