# Análisis de Arquitectura: Centralización de la Lógica de Desinstalación

## 📌 Contexto
Actualmente, la lógica de desinstalación (`do_uninstall()`) de los servicios está codificada directamente en cada script individual (`caddy.sh`, `arcane.sh`). La propuesta es trasladar el núcleo de esta función principal a la librería compartida (`lib/lib.sh`).

---

## ⚖️ Análisis de Pros y Contras

### ✅ Pros (Ventajas de Centralizar)
1. **DRY (Don't Repeat Yourself)**: Reducimos dramáticamente (aprox. 40-50 líneas) el tamaño de *cada* script de un servicio.
2. **Mantenibilidad Centralizada**: Si el comportamiento de Podman o Systemd cambia en el futuro, solo hay que ajustar un archivo (`lib.sh`) y el parche se aplicará automáticamente a todos los servicios de tu ecosistema.
3. **Consistencia Visual y de Seguridad**: Garantizamos que todos los servicios presentes y futuros se eliminen con la misma rigurosidad (flujos de confirmación, limpieza de systemd, eliminación de `.env`), impidiendo que un script borre menos que otro por error humano.
4. **Legibilidad**: El creador de un nuevo servicio solo tendrá que aportar unos cuantos nombres de variables para que el sistema sepa cómo desinstalarlo.

### ❌ Contras (Desafíos a superar)
1. **Pérdida de Flexibilidad Directa**: Cada servicio tiene particularidades: diferentes nombres de imágenes, volúmenes de Docker, y sobre todo, **mensajes de advertencia críticos** (Ej: *"Tus certificados de Caddy se borrarán"* vs *"Tus proyectos en Arcane desaparecerán"*).
2. **Paso de Parámetros Complejo**: Bash no es el lenguaje más amigable para pasar listas (arrays) de contenedores y volúmenes dentro de una función de otra librería. Requiere estructurar muy bien la transferencia de variables.

---

## 🛠 Plan de Acción Propuesto

Centralizar esta lógica es definitivamente el paso **correcto** para lograr la madurez del framework. 

Aquí presento el esquema de cómo resolver los contras expuestos y aplicar los cambios:

### Paso 1: Creación de la función maestra en `lib.sh`
Crearemos una función universal llamada `uninstall_service()` que ejecutará el protocolo estricto:
1. Confirmación de seguridad (`UNINSTALL`).
2. Limpieza de systemd (stop, disable, rm, daemon-reload).
3. Eliminación secuencial de la lista inyectada de contenedores e imágenes.
4. Identificación dinámica de la advertencia crítica inyectada.
5. Borrado en cascada (Volúmenes de podman + carpetas de datos + INSTALL_DIR) si se confirma.

### Paso 2: Refactorización Transparente de Parámetros
Para evitar el infierno de pasar 10 argumentos en fila en bash, definiremos una "interfaz" de variables globales. En el momento que el usuario haga click en desinstalar Arcane, su script preparará el "paquete de variables" justo antes de llamar a la función maestra. 

**Ejemplo Teórico de la nueva Fase en `arcane.sh`:**
```bash
do_uninstall() {
    # Definición del paquete de desinstalación
    UNINSTALL_SVC_NAME="ARCANE"
    UNINSTALL_SYSTEMD="container-arcane.service"
    UNINSTALL_CONTAINERS=("arcane")
    UNINSTALL_IMAGES=("ghcr.io/getarcaneapp/arcane:${PACKAGE_VERSION:-latest}")
    UNINSTALL_VOLUMES=()
    UNINSTALL_DIRS=("$INSTALL_DIR/data" "$INSTALL_DIR/projects")
    UNINSTALL_DATA_WARN="WARNING: Internal database and all arcane projects will be lost!"

    # Ejecución de centralizada
    uninstall_generic_service
}
```

### Paso 3: Aplicación a los Servicios y Pruebas
1. Eliminaremos todo el bloque gigante de desinstalación de `arcane.sh` y `caddy.sh`.
2. Las reemplazaremos por esta declaración limpia.
3. Probaremos ambas integraciones para confirmar que el volumen `caddy_data` de Caddy sigue siendo advertido y parseado al sistema de eliminación de Podman.

> Con este esquema conseguiremos lo mejor de ambos mundos: La seguridad estricta y consolidada del `lib.sh` pero con la personalización quirúrgica en los scripts.
