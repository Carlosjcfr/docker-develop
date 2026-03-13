# Plantilla Rápida (v2): Nuevo Servicio

---
Actúa como experto DevOps. Crea los 5 ficheros para integrar este servicio en mi framework `docker-develop` (Podman rootless):

**[SERVICIO]:** <nombre_y_descripcion> (ej: AdGuard Home - DNS blocker)
**[PUERTOS]:** <lista_puertos>
**[VOLÚMENES]:** <lista_volumenes>
**[IMAGEN]:** <url_imagen_fqdn> (DEBE empezar por docker.io/ o ghcr.io/)

## REGLAS ESTRICTAS

1. **Rootless:** Cero referencias a `sudo` o ejecución como root.
2. **SELinux:** Todo mapeo de carpetas/volúmenes en `docker-compose.yml` debe terminar en `:Z`.
3. **Secretos:** Nunca poner passwords fijos en `config.env`; se auto-generan vía bash y se leen del entorno.
4. **Entregables:** Genera `docker-compose.yml`, `config.env`, `README.md`, el script orquestador `<slug>.sh`, y el archivo de auto-registro `.registry`.
5. **Etiquetas (Tags):** NUNCA inventes tags. Si dudas, usa `latest`.
6. **Macro-Services:** Búsqueda previa de tags oficiales y declarar explicitamente en `config.env`.
7. **Sub-Volumes:** Clonar directorios de volumen nativos (init-db.d, etc) en `do_install`.
8. **Variables Críticas:** Incluir solo parámetros esenciales discriminados de la documentación oficial.
9. **Integración con Arcane:** Labels en Compose, llamar a `register_arcane_project` y usar variables estéticas.
10. **Nombres de Contenedor:** Siempre definir `container_name` para evitar fallos en health checks.
11. **Auto-Registro:** Incluir archivo `.registry` con la línea exacta para el menú.
12. **One IP per Project (Networking):** Cada proyecto tiene una IP estática asignada en la red `internal_net` (172.170.1.0/24).

---

## ESQUEMAS DE REFERENCIA (IMPORTACIÓN REQUERIDA)

Para generar el código, utiliza los siguientes documentos base:

### 1. Script Orquestador Bash
Utiliza el esqueleto obligatorio definido en:
[docs/README/template/service_skeleton.sh](file:///c:/Users/carlo/OneDrive/My_Projects/Programacion/Servers/docker-develop/docs/README/template/service_skeleton.sh)

### 2. Patrón de Red (Docker Compose)
Aplica la configuración de red isolada por proyecto:
[docs/README/template/docker-compose-pattern.yml](file:///c:/Users/carlo/OneDrive/My_Projects/Programacion/Servers/docker-develop/docs/README/template/docker-compose-pattern.yml)

### 3. Registro en el Sistema
Sigue el formato de registro definido en:
[docs/README/template/registry-pattern.txt](file:///c:/Users/carlo/OneDrive/My_Projects/Programacion/Servers/docker-develop/docs/README/template/registry-pattern.txt)

---
