# Plantilla Rápida: Nuevo Servicio

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
5. **Etiquetas (Tags):** NUNCA inventes o deduzcas tags de imagen. Si dudas de la existencia exacta de un hash/etiqueta, usa `latest`. Tags falsos provocan descargas silently-failed y desencadenan estado de contenedor `missing`.
6. **Macro-Services (Resolución Dinámica):** Para despliegues complejos compuestos por múltiples contenedores acoplados (ej: Supabase, Nextcloud), DEBES realizar una búsqueda web previa para localizar el `.env` o el `docker-compose.yml` oficial maestro de los fabricantes. Tras la investigación, **debes extraer las tags de las versiones probadas y declararlas explícitamente como variables en el `config.env`** generador, usándolas en tu `.yml` como `$MI_VERSION`. Así mantienes la coherencia de variables nativa del proyecto.
7. **Sub-Volumes (Integridad Arquitectónica):** NO inventes ni resumas "docker-compose.yml" de Macro-Stacks (ej: Supabase) ignorando sus volúmenes, carpetas y scripts de inicialización de Base de Datos. Si identificas que el ecosistema oficial reposa sobre directorios de volumen nativos (como carpetas de scripts SQL `init-db.d/`), **DEBES generar comandos en `do_install` que descarguen esos directorios (ej. con un clone sparse de git o wget iterativo) al `$INSTALL_DIR`** de forma previa a la instanciación para evitar que fallen los contenedores dependientes por permisos de esquema o tablas inexistentes.
8. **Variables Críticas (Previsión de Crasheos):** Antes de plantear el `docker-compose.yml`, debes examinar exhaustivamente el `.env.example` o la documentación oficial del fabricante para discriminar qué parámetros son esenciales. **No omitas variables de entorno orgánicas obligatorias** para un arranque funcional (ej. URLs de callback externas, tokens internos pre-generados o contraseñas core). Sin embargo, **NO incluyas a ciegas absolutamente todos los parámetros** (omite variables experimentales, opcionales, o analíticas secundarias que no sean críticas). Recrea solo el `environment:` estrictamente necesario y centralízalo a través de nuestro `config.env`.
9. **Integración con Arcane (Visibility):** Todo nuevo servicio debe integrarse en el panel de control **Arcane**. Esto implica tres requisitos obligatorios:
   - **Labels en Compose:** El contenedor principal debe incluir labels para icono (`dev.arcane.icon`), categoría (`dev.arcane.category`), nombre de proyecto (`com.docker.compose.project`), y directorio de trabajo simulado (`com.docker.compose.project.working_dir=/app/data/projects/<slug>`).
   - **Registro del Proyecto:** El script `.sh` debe llamar a `register_arcane_project "<slug>" "$INSTALL_DIR"` tras el despliegue.
   - **Variables Estéticas:** Los valores de icono y categoría deben ser parametrizables desde `config.env`.

**ESQUELETO OBLIGATORIO PARA `<slug>.sh`:**
No inventes funciones. Limítate a rellenar este exacto molde (usando variables base como `$HOST_IP` y `$PUID`):

```bash
#!/bin/bash
set -euo pipefail

GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
REPO_RAW="$REPO_BASE/projects/<slug>"
# shellcheck source=../../lib/lib.sh
source <(curl -fsSL "$REPO_BASE/lib/lib.sh")

load_configuration() {
    # shellcheck source=/dev/null
    source "$TMP_DIR/config.env"
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # Inicializa tus variables personalizadas aquí
    ARCANE_ICON="${ARCANE_ICON:-si:<icon_slug>}"
    ARCANE_CATEGORY="${ARCANE_CATEGORY:-<Category>}"
}

generate_runtime_env() {
    local OLD_UMASK=$(umask); umask 177
    cat <<EOF > "$INSTALL_DIR/.env"
HOST_IP="$HOST_IP"
PUID="$PUID"
PGID="$PGID"
PODMAN_SOCK="$PODMAN_SOCK"
# Arcane metadata
ARCANE_ICON="$ARCANE_ICON"
ARCANE_CATEGORY="$ARCANE_CATEGORY"
EOF
    umask "$OLD_UMASK"
}

do_uninstall() {
    INSTALL_DIR="${INSTALL_DIR:-/opt/<slug>}"
    # shellcheck disable=SC2034
    UNINSTALL_SVC_NAME="<NAME>"
    # shellcheck disable=SC2034
    UNINSTALL_SYSTEMD="container-<slug>.service" 
    # shellcheck disable=SC2034
    UNINSTALL_CONTAINERS=("<main_container>")
    
    # NOTE: UNINSTALL_IMAGES array is only for static fallback.
    # The engine now automatically discovers images from docker-compose.yml.
    # shellcheck disable=SC2034
    UNINSTALL_IMAGES=("<fqdn_imagen_exacta>")
    
    # shellcheck disable=SC2034
    UNINSTALL_VOLUMES=("<array_volumenes_persistentes>")
    # shellcheck disable=SC2034
    UNINSTALL_DIRS=()
    uninstall_generic_service
}

check_existing_installation() {
    local dir="${1:-/opt/<slug>}"
    if [ -f "$dir/.env" ] && podman container exists <main_container> 2>/dev/null; then
        return 0
    fi
    return 1
}

deploy_and_persist() {
    log "Starting services with podman-compose..."
    cd "$INSTALL_DIR"
    
    podman-compose config >/dev/null 2>&1 || { err "Sintaxis de docker-compose invalida. Abortando instalación."; exit 1; }
    
    log "Extrayendo imágenes de contenedor..."
    if ! podman-compose pull; then
        err "Fallo al descargar imágenes. Posible Tag inexistente o error de red."
        read -rp " ¿Deseas sustituir dinámicamente todos los tags por 'latest' e intentar de nuevo? [y/N]: " FIX_TAGS
        if [[ "$FIX_TAGS" =~ ^[Yy]$ ]]; then
            log "Parcheando tags a 'latest' en docker-compose.yml..."
            sed -i '/^[[:space:]]*image:/s/:[^:/]*$/:latest/' "$INSTALL_DIR/docker-compose.yml"
            podman-compose pull > /dev/null || { err "Fallo crítico repetido al probar con latest."; exit 1; }
        else
            err "Lanza la actualización manualmente para depurar el error."
            exit 1
        fi
    fi
    
    podman-compose up -d > /dev/null 2>&1
    verify_containers_running <tus_contenedores_aqui>
    
    rm -f "$INSTALL_DIR"/*.bak 2>/dev/null || true
    
    log "Configuring systemd service for persistence..."
    mkdir -p ~/.config/systemd/user/
    cat <<EOF > ~/.config/systemd/user/container-<slug>.service
[Unit]
Description=<NAME> Stack (podman-compose)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=$(command -v podman-compose) up -d
ExecStop=$(command -v podman-compose) down
TimeoutStartSec=120
TimeoutStopSec=30
[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now container-<slug>.service
}

print_success() {
    echo "================================================================="
    echo " <NAME> deployed and secured with systemd."
    echo " URL: http://\$HOST_IP:<PORT>"
    echo "================================================================="
}

# -----------------------------------------------------------------------------
# REQUIRED ACTIONS (Añade el bloque completo para install/start/update)
# -----------------------------------------------------------------------------
do_install() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    # manage_credentials "$INSTALL_DIR" MIVAR_SECRETA
    setup_lingering_and_socket
    
    check_install_dir_writable "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    generate_runtime_env
    deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"
    print_success
}

do_start() {
    systemctl --user start container-<slug>.service
}

do_update() {
    download_repo_files "$REPO_RAW" config.env docker-compose.yml
    offer_interactive_mode; load_configuration; detect_host_ip
    setup_lingering_and_socket
    
    generate_runtime_env
    
    cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
    cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true
    
    mv -f "$TMP_DIR/config.env" "$INSTALL_DIR/config.env"
    mv -f "$TMP_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"
    
    deploy_and_persist
    register_arcane_project "<slug>" "$INSTALL_DIR"
    print_success
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

Por último, devuélveme la línea de registro exacta para copiar/pegar en mi menú `deploy.sh` bajo la sintaxis completa de 6 campos (incluyendo el endpoint dinámico `{IP}`):
`"Nombre|projects/<slug>/<slug>.sh|/opt/<slug>|<main_container>|Descripción breve|Servicio: {IP}:<PORT>"`

---
