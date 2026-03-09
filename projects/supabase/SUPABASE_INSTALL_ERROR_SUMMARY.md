# Error de Despliegue de Supabase - Resumen

**Problema:**
Al ejecutar `deploy.sh` y seleccionar Supabase, el script arrojaba un "completed successfully" inmediato sin descargar ficheros, sin instalar el servicio y sin mostrar el menú de configuración.

**Causa Raíz:**
El fichero `docs/NEW_SERVICE_TEMPLATE.md` estipulaba una **"REGLA ESTRICTA"** para que el generador de código usar únicamente un "esqueleto" de variables truncado. El esqueleto dado en la plantilla **carecía de la lógica principal de ejecución (`MAIN`) y de las funciones declarativas del ciclo de vida (`do_install`, `do_update`, `do_start`)**, terminando el script justo después de interpretar los argumentos de entrada en `parse_args "$@"`.

Al aplicar este molde estrictamente a `supabase.sh`, el script se convirtió en una librería de funciones muertas sin que ninguna pieza de código las invocara (el script abría, declaraba sus métodos, y terminaba saliendo con un código de éxito).

**Solución Implementada:**

1. Modificar `docs/NEW_SERVICE_TEMPLATE.md` para incluir de forma permanente las directivas necesarias e instruir al modelo a que **también** genere el bloque de control principal (`MAIN`) y las funciones del ciclo de vida (`do_install`, `do_start`, etc).
2. Refactorizar el archivo `/projects/supabase/supabase.sh` para incluir los menús estándar y los enrutadores de ejecución habituales.

---

## Error 2: Permisos Denegados al crear el Directorio de Instalación

**Problema:**
Durante una instalación en limpio (`do_install`), el script falla al intentar invocar `mkdir -p /opt/supabase` debido a permisos insuficientes, cayendo en un error "Permission denied" dado que se ejecuta en rootless.

**Causa Raíz:**
La plantilla básica `do_install` omitía la llamada al helper protector proporcionado en `lib.sh`: `check_install_dir_writable`. Esta función evalúa la creación de la ruta de instalación (`$INSTALL_DIR`) y ejecuta de forma segura el comando `sudo mkdir` otorgando los permisos `chown` pertinentes al usuario sin comprometer el aislamiento principal de Podman.

**Solución Implementada:**
Se ha actualizado `docs/NEW_SERVICE_TEMPLATE.md` y `projects/supabase/supabase.sh` inyectando `check_install_dir_writable "$INSTALL_DIR"` justo antes de las sentencias nativas `mkdir -p "$INSTALL_DIR"`. Esto garantiza que `/opt/` contenga el espacio habilitado antes de la transferencia de ficheros.

---

## Error 3: Identificador no válido en 'verify_containers'

**Problema:**
La ejecución se detiene tras arrancar pods, indicando: `verify_containers_in_list: command not found`.

**Causa Raíz:**
La plantilla antigua estaba declarando localmente una función empaquetadora que redirigía hacia otra función inexistente dependiente de `lib.sh`. El helper original y correcto documentado en `lib.sh` se llama en realidad `verify_containers_running`, el cual recibe la matriz de contenedores por parámetros en línea.

**Solución Implementada:**
Se ha eliminado la re-declaración inútil del validador de contenedores en `NEW_SERVICE_TEMPLATE.md`, moviendo la llamada de `verify_containers_running "contenedor"` directamente dentro de la subrutina `deploy_and_persist`. Este exacto ajuste también ha sido parcheado sobre `projects/supabase/supabase.sh`.
