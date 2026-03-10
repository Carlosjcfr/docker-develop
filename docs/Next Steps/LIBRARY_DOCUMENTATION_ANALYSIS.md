# Análisis de Documentación de Librería

Este documento analiza la situación actual de los comentarios y documentación técnica dentro de los archivos fuente de la librería compartida.

---

## 🔍 Análisis de la Situación Actual

* **Problema:** El fichero resultante `lib.sh` (y sus fuentes) están saturados de texto. Nombres de proyectos específicos se están "colando" en la librería base a través de los bloques "Example" o "Usage".
* **Archivos Afectados:** `02_install.sh`, `03_health.sh`, `04_uninstall.sh`, `05_arcane.sh`.

### Ejemplo del Problema Actual (`04_uninstall.sh`)

```bash
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
```

---

## 🛠️ Propuesta de Refactorización

### 1. Creación de `docs/LIBRARY_REFERENCE.md` (o `API.md`)

Crear un documento centralizado en la carpeta `docs/` que actúe como "El Manual del Desarrollador" para el framework. Este documento agrupará:

* **Variables Globales Inyectadas:** Explicación de qué hacen variables como `$TMP_DIR`, `$HOST_IP`, `$PUID`, `$PGID`, `$PODMAN_SOCK`.
* **Firma de Funciones (API):** Documentar métodos clave como `download_repo_files`, `verify_containers_running`, `check_http_health`, `uninstall_generic_service`.
* **Ejemplos de Implementación:** Aquí sí usaremos subservicios ficticios o nombres abstraídos (`<slug>`, `MyService`).

### 2. Adelgazamiento de `lib/src/*.sh`

Una vez la documentación esté a salvo en su Markdown, reduciremos los comentarios del código bash a **una sola línea explicativa** por función.

**Cómo quedaría el código tras la limpieza:**

```bash
# Elimina los contenedores, imágenes y volúmenes de un servicio. (Ref: docs/LIBRARY_REFERENCE.md)
uninstall_generic_service() {
    # Discovery Phase
    ...
```

---

## ⚖️ Pros y Contras del Cambio

### ✅ Pros (Ventajas)

* **Agnosticismo Total:** Eliminamos de raíz cualquier mención a Arcane, Caddy o Supabase del núcleo del sistema. La librería vuelve a ser un motor 100% genérico.
* **Código más Limpio ("Clean Code"):** El archivo que se descarga e interpreta cada vez (`lib.sh`) reduce drásticamente su tamaño y peso al eliminar cientos de líneas de comentarios. Los desarrolladores ven la lógica directamente.
* **Mejor Experiencia de Lectura:** Leer una API en Markdown (con tablas, negritas y bloques de sintaxis) es infinitamente mejor que leer el crudo de `#` en bash.
* **Menos Confusión:** Evita la sensación visual de "código acoplado" o "spaghetti" que puede dar ver variables como `e.g. "ARCANE"` en una función de desinstalación genérica.

### ❌ Contras (Desventajas)

* **Cambio de Contexto:** Cuando estés trabajando en crear un script nuevo (`servicioX.sh`), tendrás que abrir `docs/LIBRARY_REFERENCE.md` en otra pestaña si no te acuerdas de cuántos parámetros lleva una función de `lib.sh`, en lugar de encontrar la respuesta leyendo el propio bash.
