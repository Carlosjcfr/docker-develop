# =============================================================================
# LOGGING
# =============================================================================

log()  { echo "[$(date -u '+%H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date -u '+%H:%M:%S')] [WARN]  $*" >&2; }
err()  { echo "[$(date -u '+%H:%M:%S')] [ERROR] $*" >&2; }

# =============================================================================
# GUARDS
# =============================================================================

# Abort if the script is running as root.
# Rootless Podman must run as a normal user to maintain namespaced isolation.
root_protection() {
    if [[ $EUID -eq 0 ]]; then
        echo "-----------------------------------------------------------------"
        echo " ERROR: DO NOT RUN THIS SCRIPT WITH SUDO"
        echo "-----------------------------------------------------------------"
        echo " Rootless Podman requires a normal user session."
        echo " Please retry WITHOUT sudo."
        echo "-----------------------------------------------------------------"
        exit 1
    fi
}

# Verify that all required commands exist in PATH.
# Usage: check_dependencies CMD [CMD ...]
check_dependencies() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            err "Required command '$cmd' not found. Please install it before continuing."
            exit 1
        fi
    done
}

# Validate that no secret variable names appear in a config file.
# Secrets must never be committed to the repository.
# Usage: check_secrets_not_in_config CONFIG_FILE SECRET_NAME [SECRET_NAME ...]
check_secrets_not_in_config() {
    local config_file="${1:?check_secrets_not_in_config requires a config file path}"
    shift
    for secret_name in "$@"; do
        if grep -q "^${secret_name}=" "$config_file"; then
            echo "-----------------------------------------------------------------"
            echo " ERROR: SECRET DETECTED IN config.env"
            echo "-----------------------------------------------------------------"
            echo " '$secret_name' must NEVER be stored in the repository."
            echo " Remove it from config.env — secrets are auto-generated at runtime."
            echo "-----------------------------------------------------------------"
            exit 1
        fi
    done
}

# Validate that the installation directory is writable by the current user.
# If /opt is root-owned and the prerequisite step was skipped, fail early.
# Exit code 2 = missing prerequisite: install directory not writable.
# Usage: check_install_dir_writable DIR
check_install_dir_writable() {
    local dir="${1:?check_install_dir_writable requires a directory argument}"
    
    # Intenta crear como usuario normal. Si falla o no es escribible, escalamos a sudo.
    if ! mkdir -p "$dir" 2>/dev/null || ! [ -w "$dir" ]; then
        log "Install directory '$dir' needs elevated permissions to be created."
        log "Attempting to create it automatically using 'sudo'..."
        
        if sudo mkdir -p "$dir" && sudo chown -R "$USER:$USER" "$dir"; then
            log "Directory '$dir' prepared and ownership assigned to $USER."
        else
            echo ""
            echo "-----------------------------------------------------------------"
            echo " ERROR [exit 2]: FAILED TO PREPARE INSTALLATION DIRECTORY"
            echo "-----------------------------------------------------------------"
            echo " The script tried to run 'sudo mkdir -p $dir' but failed."
            echo " Please create it manually and assign ownership to $USER:"
            echo "   sudo mkdir -p $dir && sudo chown \$USER:\$USER $dir"
            echo "-----------------------------------------------------------------"
            exit 2
        fi
    fi
}
