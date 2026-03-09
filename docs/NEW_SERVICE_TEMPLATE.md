# Plantilla Rápida: Nuevo Servicio

> **Uso:** Copia desde `---` hasta el final. Rellena las 4 variables entre corchetes `[ ]` y pégalo en el chat de tu IA.

---
Actúa como experto DevOps. Crea los 4 ficheros para integrar este servicio en mi framework `docker-develop` (Podman rootless):

**[SERVICIO]:** <nombre_y_descripcion> (ej: AdGuard Home - DNS blocker)
**[PUERTOS]:** <lista_puertos>
**[VOLÚMENES]:** <lista_volumenes>
**[IMAGEN]:** <url_imagen_fqdn> (DEBE empezar por docker.io/ o ghcr.io/)

**REGLAS ESTRICTAS:**
1. **Rootless:** Cero referencias a `sudo` o ejecución como root.
2. **SELinux:** Todo mapeo de carpetas/volúmenes en `docker-compose.yml` debe terminar en `:Z`.
3. **Secretos:** Nunca poner passwords fijos en `config.env`; se auto-generan vía bash y se leen del entorno.
4. **Entregables:** Genera `docker-compose.yml`, `config.env`, `README.md` (formato "Cheat Sheet" minimalista de 30 líneas máximo), y el script orquestador `<slug>.sh`.

**ESQUELETO OBLIGATORIO PARA `<slug>.sh`:**
No inventes funciones. Limítate a rellenar este exacto molde (usando variables base como `$HOST_IP` y `$PUID`):

```bash
#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/<slug>"
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # Inicializa tus variables personalizadas aquí (ej: MIVAR="${MIVAR:-default}")
}

generate_runtime_env() {
    local OLD_UMASK=$(umask); umask 177
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
# Añade el mapeo final de tus variables para el compose aquí
EOF
    umask "$OLD_UMASK"
}

verify_containers_running() { 
    verify_containers_in_list "<main_container>" 
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    UNINSTALL_SVC_NAME="<NAME>"
    UNINSTALL_SYSTEMD="container-<slug>.service" 
    UNINSTALL_CONTAINERS=("<main_container>")
    UNINSTALL_IMAGES=("<fqdn_imagen_exacta>")
    UNINSTALL_VOLUMES=("<array_volumenes_persistentes>")
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

# -----------------------------------------------------------------------------
# REQUIRED ACTIONS (Añade el bloque completo para install/start/update)
# -----------------------------------------------------------------------------
do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    # manage_credentials "$INSTALL_DIR" MIVAR_SECRETA
    setup_lingering_and_socket
    
    mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    # deploy_and_persist function must be implemented to launch podman-compose up -d and configure systemd
}

do_start() {
    systemctl --user start container-<slug>.service
}

do_update() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    load_configuration; generate_runtime_env
    cd "$INSTALL_DIR"; podman-compose pull
    # deploy_and_persist
}

# -----------------------------------------------------------------------------
# MAIN LOOP ENTRY POINT
# -----------------------------------------------------------------------------
root_protection
check_dependencies curl podman-compose
parse_args "$@"

if [ -n "$CMD_ACTION" ]; then
    case "$CMD_ACTION" in
        install)   do_install ;;
        start)     do_start ;;
        update)    do_update ;;
        uninstall) do_uninstall ;;
        *) err "Invalid action."; exit 1 ;;
    esac
    exit 0
fi

if check_existing_installation "/opt/<slug>"; then
    echo "1) Start 2) Update 3) Uninstall"
    read -rp " Select [1-3]: " ACTION
    case "$ACTION" in
        1) do_start ;; 2) do_update ;; 3) do_uninstall ;; *) exit 0 ;;
    esac
else
    do_install
fi
```

Por último, devuélveme la línea de registro exacta para copiar/pegar en mi menú `deploy.sh` bajo la sintaxis:
`"Nombre|projects/<slug>/<slug>.sh|/opt/<slug>|<main_container>|Descripción"`
---
