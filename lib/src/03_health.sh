# =============================================================================
# DEPLOYMENT VALIDATION
# =============================================================================

# Verifies specified containers are in a 'running' state post-deployment (Ref: docs/LIBRARY_REFERENCE.md)
verify_containers_running() {
    local -a REQUIRED=("$@")
    local -a FAILED=()

    log "Verifying containers are running..."
    sleep 3   # Allow containers to transition from 'created' to 'running'

    for name in "${REQUIRED[@]}"; do
        local status
        status=$(podman inspect "$name" --format '{{.State.Status}}' 2>/dev/null || echo "missing")
        if [[ "$status" != "running" ]]; then
            FAILED+=("  ✗ $name  (status: $status)")
        else
            log "  ✓ $name"
        fi
    done

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo ""
        echo "-----------------------------------------------------------------"
        echo " ERROR [exit 3]: DEPLOYMENT FAILED — containers did not start"
        echo "-----------------------------------------------------------------"
        printf '%s\n' "${FAILED[@]}"
        echo ""
        echo " Most likely causes:"
        echo "   1. Image name not fully qualified — Podman requires a registry"
        echo "      prefix (e.g. docker.io/image:tag or ghcr.io/image:tag)."
        echo "   2. No network access to pull images from the registry."
        echo "   3. Install directory not prepared beforehand (see exit code 2)."
        echo "   4. Port conflict with another running service."
        echo ""
        echo " Diagnostic commands:"
        echo "   podman ps -a"
        echo "   podman logs <container-name>"
        echo "   journalctl --user -u <service>.service -n 80 --no-pager"
        echo "-----------------------------------------------------------------"
        exit 3
    fi

    log "All containers running."
}

# =============================================================================
# HTTP HEALTH CHECKS  (F3.4)
# =============================================================================

# Polls an HTTP endpoint for a 2xx response within a given timeout (Ref: docs/LIBRARY_REFERENCE.md)
poll_http() {
    local url="${1:?poll_http requires a URL}"
    local timeout="${2:-30}"
    local interval="${3:-2}"
    local elapsed=0

    log "Waiting for $url ..."
    while [ "$elapsed" -lt "$timeout" ]; do
        if curl -sf --max-time "$interval" "$url" >/dev/null 2>&1; then
            log "  ✓ $url"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    err "Endpoint did not respond within ${timeout}s: $url"
    return 1
}

# Runs payload array of HTTP health checks and aborts on failures (Ref: docs/LIBRARY_REFERENCE.md)
check_http_health() {
    local -a FAILED=()

    log "Running HTTP health checks..."
    for entry in "$@"; do
        local label url timeout
        IFS='|' read -r label url timeout <<< "$entry"
        timeout="${timeout:-30}"
        if ! poll_http "$url" "$timeout" 2 2>/dev/null; then
            FAILED+=("  ✗ $label  ($url)")
        fi
    done

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        echo ""
        echo "-----------------------------------------------------------------"
        echo " ERROR [exit 3]: HEALTH CHECKS FAILED — services not responding"
        echo "-----------------------------------------------------------------"
        printf '%s\n' "${FAILED[@]}"
        echo ""
        echo " The containers are running but the applications inside are not"
        echo " responding. Check the container logs for startup errors:"
        echo "   podman logs <container-name>"
        echo "-----------------------------------------------------------------"
        exit 3
    fi

    log "All health checks passed."
}
