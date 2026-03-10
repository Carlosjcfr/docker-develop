# Plan de Acción: Optimización Preventiva del Template de Servicios

Este documento analiza las propuestas de mejora para `docs/NEW_SERVICE_TEMPLATE.md`, evaluando los pros, contras y el enfoque de implementación para mitigar la deuda técnica y prevenir errores silenciosos durante el ciclo de vida de los contenedores (instalación, actualización y borrado).

---

## 1. Sistema de Backup Atómico con Autolimpieza en Actualizaciones

**Propuesta:** 
Crear copias de seguridad temporales (`.bak`) de los archivos críticos (`config.env`, `docker-compose.yml`, `.env`) antes de sobrescribirlos en la función `do_update`. Si la actualización falla, se restaura; si el contenedor levanta correctamente, se eliminan los `.bak`.

**Ventajas (Pros):**
- **Resiliencia:** Previene la corrupción total del servicio si un `curl` falla a medio camino o el nuevo repositorio contiene configuraciones inválidas.
- **Rollback Transparente:** Mantiene el estado previo sano del usuario.
- **Limpieza:** Al borrar los backups post-éxito, no se ensucia el directorio de instalación `/opt/<slug>`.

**Desventajas (Contras):**
- Añade complejidad y más líneas al esqueleto obligatorio de los scripts individuales.

**Solución/Implementación Posible:**
Inyectar un bloque estructurado en `do_update` de la plantilla:
```bash
# Backup
cp "$INSTALL_DIR/config.env" "$INSTALL_DIR/config.env.bak" 2>/dev/null || true
cp "$INSTALL_DIR/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml.bak" 2>/dev/null || true

# Tras deploy_and_persist y confirmación de contenedores corriendo:
rm -f "$INSTALL_DIR"/*.bak
```
Para evitar repetir código en cada script, podríamos plantear mover esta lógica a `lib.sh` en un futuro, creando una función `backup_configs` y `cleanup_backups`.

---

## 2. Validación Pre-Flight (Dry-Run Check)

**Propuesta:** 
Ejecutar `podman-compose config -q` para validar la sintaxis YAML antes de intentar empaquetar o levantar.

**Ventajas (Pros):**
## 2. Sintaxis de Compose Segura
Antes de hacer `pull` o `up`, validaremos si el YAML mal copiado te daría un error catastrófico:
```bash
podman-compose config >/dev/null 2>&1 || { err "Sintaxis de docker-compose inválida. Abortando instalación/actualización."; exit 1; }
```

---

## 3. Registro Perfilado de Podman Pull (Log File)

**Propuesta:** 
Redirigir la salida extremadamente verbosa de la descarga de capas de Podman hacia un archivo `install.log` persistente dentro del directorio del servicio, limpiando la terminal pero preservando la trazabilidad.

**Ventajas (Pros):**
- **UX Limpia:** La terminal del usuario mantiene el foco en los "ticks" (✓) de estado del orquestador.
- **Troubleshooting:** Mantiene la salida completa disponible para depuración (`cat /opt/<slug>/install.log`) si un pull falla por timeout o credenciales.

**Desventajas (Contras):**
- El usuario no ve la barra de progreso de descarga en tiempo real, pareciendo que el script "se cuelga" si la imagen es pesada o el internet lento.

**Solución/Implementación Posible:**
Añadir feedback explícito por pantalla mientras se registra en segundo plano:
```bash
log "Extrayendo imágenes de contenedor... (Los detalles se guardan en $INSTALL_DIR/install.log)"
podman-compose pull > "$INSTALL_DIR/install.log" 2>&1 || err "Error extrayendo imágenes. Revisa install.log."
```

---

## 4. Definición Dinámica de `UNINSTALL_IMAGES` (Refinamiento)

**Propuesta:** 
Evitar que la IA (o el desarrollador) escriba un array a fuego con nombres de imágenes y versiones fijas/inventadas en la función `do_uninstall`, previniendo que al cambiar un tag futuro se queden recursos huérfanos sin borrar.

**Ventajas (Pros):**
- **Limpieza Total:** Garantiza que los borrados sean profundos y correctos, eliminando exactamente las imágenes en uso o registradas.
- **Mantenimiento Cero:** Si un servicio actualiza la imagen base (ej. migra de `alpine` a `debian`), la función de `uninstall` no se rompe silenciosamente.

**Desventajas (Contras):**
- Si se usa la extracción dinámica leyendo el `.yml`, es técnicamente más complejo en bash plano que un simple array.

**Solución/Implementación Posible:**
En lugar de forzar a la IA a rellenar `UNINSTALL_IMAGES=("foo:v1" "bar:v2")`, instruir a usar un comando Podman nativo para extraer todas las imágenes asociadas al proyecto, o usar un grep dinámico del `docker-compose.yml`. Como alternativa más segura y nativa dentro del orquestador:
```bash
# Delegar la lectura de imágenes a podman-compose o listar los tags variables
UNINSTALL_IMAGES=(\$(podman-compose config | grep 'image:' | awk '{print \$2}'))
```
*(Nota: Esto requiere pruebas para confirmar si `podman-compose config` resuelve variables de entorno correctamente antes de la destrucción).* O, exigir que las imágenes en desinstalación referencien las variables `$VERSION` inyectadas desde `config.env`.
