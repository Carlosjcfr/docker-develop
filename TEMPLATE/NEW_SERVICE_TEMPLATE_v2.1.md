# Plantilla Rápida (v2.1): Nuevo Servicio

---
Actúa como experto DevOps. Crea los 5 ficheros para integrar este servicio en mi framework `docker-develop` (Podman rootless):

**[SERVICIO]:** <nombre_y_descripcion> (ej: AdGuard Home - DNS blocker)
**[PUERTOS]:** <lista_puertos>
**[VOLÚMENES]:** <lista_volumenes>
**[IMAGEN]:** <url_imagen_fqdn> (DEBE empezar por docker.io/ o ghcr.io/)

---

## REGLAS ESTRICTAS DE ARQUITECTURA

> [!IMPORTANT]
> Debes seguir estas reglas con exactitud quirúrgica. Cualquier desviación romperá la integridad del sistema.

1. **Rootless & SELinux:** Cero referencias a `sudo`. Todo mapeo de carpetas en `docker-compose.yml` DEBE terminar en `:Z` para compatibilidad con SELinux en Podman.
2. **Secretos Dinámicos:** Nunca pongas passwords fijos en `config.env`. Deben generarse vía bash en el script (usando `openssl rand`) y persistirse en el `.env` local.
3. **Tags de Imagen (Precisión):** NUNCA inventes o deduzcas tags. Si dudas, usa `latest`. Tags erróneos causan estados `missing` silenciosos.
4. **Macro-Services (Resolución Dinámica):** Si el servicio es complejo (multi-contenedor), realiza una búsqueda web previa para localizar el `.env` o `docker-compose.yml` oficial. Extrae las tags probadas y decláralas como variables en el `config.env`.
5. **Sub-Volumes & Integridad:** En servicios que dependen de carpetas de inicialización (ej. `init-db.d/`), genera comandos en `do_install` para descargar esos directorios antes de arrancar los contenedores.
6. **Variables Críticas (Previsión de Crasheos):** Examina el `.env.example` oficial. Incluye solo los parámetros estrictamente esenciales para un arranque funcional. Evita variables opcionales o experimentales.
7. **Nombres de Contenedor Explícitos:** Define siempre `container_name: <nombre>` en cada servicio de Compose. Sin esto, las comprobaciones de estado de nuestro framework fallarán.

### Integración con Arcane (Visibility)

Todo servicio debe incluir:

- **Labels en Compose:** El contenedor principal requiere:
  - `dev.arcane.icon`: `<icon_slug>` (ej. `si:nginx`)
  - `dev.arcane.category`: `<Category>`
  - `com.docker.compose.project`: `<slug>`
  - `com.docker.compose.project.working_dir`: `/app/data/projects/<slug>`
- **Registro:** El script `.sh` debe llamar a `register_arcane_project "<slug>" "$INSTALL_DIR"`.

### Networking: One IP per Project

Cada proyecto tiene una IP estática aislada en la red `internal_net` (172.170.1.0/24).

- **Bash:** Llamar a `assign_project_ip` antes de generar el `.env`.
- **Persistencia:** La variable `PROJECT_IP` debe guardarse en el `.env`.

---

## ESQUEMAS DE REFERENCIA (LECTURA OBLIGATORIA)

Utiliza los siguientes documentos base para la estructura exacta:

### 1. Script Orquestador Bash

Utiliza el esqueleto obligatorio definido en:
[TEMPLATE/service_skeleton.sh](TEMPLATE/service_skeleton.sh)

### 2. Patrón de Red (Networking Pattern)

**DEBES** aplicar esta estructura en tu `docker-compose.yml`:

```yaml
services:
  main-app:
    image: ${IMAGE_TAG}
    container_name: ${CONTAINER_NAME}
    networks:
      internal_net:
        ipv4_address: ${PROJECT_IP}

networks:
  internal_net:
    external: true
```

*(Ver detalle en: [TEMPLATE/docker-compose-pattern.yml](TEMPLATE/docker-compose-pattern.yml))*

### 3. Registro en el Sistema

Genera el archivo `.registry` con esta sintaxis de 6 campos (endpoint dinámico `{IP}`):
`"Nombre|projects/<slug>/<slug>.sh|/opt/<slug>|<main_container>|Descripción breve|Servicio: {IP}:<PORT>"`

*(Ver detalle en: [TEMPLATE/registry-pattern.txt](TEMPLATE/registry-pattern.txt))*

---

## ENTREGABLES REQUERIDOS

1. `docker-compose.yml` (Con labels de Arcane y Networking estático).
2. `config.env` (Con variables estéticas y tags de imagen definidos).
3. `README.md` (Cheat Sheet minimalista, <30 líneas).
4. `<slug>.sh` (Implementando `assign_project_ip` y preservando la IP en `do_update`).
5. `.registry` (Formato de 6 campos).
