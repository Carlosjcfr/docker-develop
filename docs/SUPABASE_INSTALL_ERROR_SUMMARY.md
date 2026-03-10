# Error de Despliegue de Supabase - Resumen

[... Contenido previo retenido por brevedad en este documento ...]

## Error 5: Domino Effect (Clúster Descoyuntado por uso de ':latest')

**Problema:**
Al ejecutar el orquestador, varios contenedores empezaron a fallar en cascada: `supabase-studio` da estado `missing`, mientras que `supabase-auth`, `supabase-rest` y `supabase-realtime` quedan `stopped` (crasheados de inicio). 

**Causa Raíz:**
Este es exactamente el escenario descrito en el `DYNAMIC_TAG_RESOLUTION_PLAN.md`.
1. Hubo un micro-corte de red o una de las versiones hardcodeadas (como `20240409-bf25a81` de Studio) falló al descargar.
2. El instalador saltó al modo interactivo de emergencia preguntando: *"¿Deseas sustituir dinámicamente todos los tags por 'latest'?"*.
3. El usuario aceptó (`y`), forzando el comando `sed` a reescribir todo el `docker-compose.yml` para que apunte a `:latest`.
4. **¿Por qué Studio está missing?** Porque `docker.io/supabase/studio` NO publica la etiqueta `latest`. Los desarrolladores de Supabase solo publican hashes y fechas. Como `:latest` no existe en su Hub, Podman falla al extraerlo y ni siquiera crea el contenedor.
5. **¿Por qué los demás están stopped?** Contenedores como `auth` (gotrue) o `rest` (postgrest) SÍ publican una rama `latest`. Se descargaron con éxito, pero al encenderse (con versiones extremas recien salidas del horno) detectaron que estaban acoplados a un `postgres` con configuraciones incompatibles. Al no cuadrar las piezas del clúster, crashean instantáneamente por errores de base de datos y se detienen.

**Solución Inmediata a Implementar:**
El *Fallback* a `:latest` es útil para contenedores simples (como AdGuard o Nginx), pero es destructivo para Macro-Stacks (Supabase) donde todo está rígidamente interconectado. 
- Restablecer las variables del `config.env` original o eliminar la ruta corrupta (`rm -rf /opt/supabase` y reinstalar sin aceptar el parche de latest).
- Alternativamente, blindar el `docker-compose.yml` de Supabase incluyendo dependencias de arranque fuertes (`depends_on: db`).

---

## Error 6: Colapso por Mutilación Arquitectónica en Macro-Servicios

**Problema:**
Al resolver las versiones correctas en el `docker-compose.yml` de Supabase, los servicios `supabase-auth` y `supabase-storage` vuelven a quedar `stopped` al intentar arrancar.
- El log de **Auth** indica: `Failed to load configuration: required key API_EXTERNAL_URL missing value`.
- El log de **Storage** indica un fallo fatal: `permission denied for schema storage` durante las migraciones de base de datos.

**Investigación y Causa (Coolify & Oficial Repos):**
Tras contrastar nuestra instalación con soluciones robustas como Coolify y escrutar el repositorio oficial de Supabase Docker (`https://github.com/supabase/supabase`), la causa raíz es **la mutilación arquitectónica al inventar el Docker Compose**:

1. **Variables Críticas Omitidas:** El ecosistema es masivo y las iteraciones modernas de GoTrue exigen que el `docker-compose.yml` posea variables como `API_EXTERNAL_URL` mapeadas explícitamente para los callbacks OAuth, las cuales la IA original ignoró en su instanciación.
2. **Missing Volumes (El Núcleo del Fallo):** Supabase **no** usa una imagen pre-compilada "mágica" de Postgres. En el repositorio oficial, la base de datos se inicializa inyectando (vía Docker Volumes) unos **7 scripts SQL gigantes** (`roles.sql`, `jwt.sql`, `realtime.sql`, etc.) ubicados en la carpeta `docker/volumes/db/`. 
Al generar un `docker-compose.yml` minimizado y arrancar el contenedor "desnudo", Postgres se encendió como un motor genérico sin los roles internos (`supabase_admin`, `authenticator`) ni los esquemas lógicos (`storage`, `auth`) pre-creados. En consecuencia, cuando `supabase-storage` intentó conectarse, recibió un *"permission denied"* porque tal esquema ni existía ni él tenía privilegios.

**Solución Sistémica a Implementar:**
Plataformas como Coolify **no** intentan reescribir, resumir o "adivinar" el Docker Compose de Supabase; instancian repositorios complejos clonando la arquitectura completa y fiel del fabricante ("One-Click Apps").
- Para solucionar esto estructuralmente en tu framework, la IA jamás debe intentar reconstruir de memoria la estructura de dependencias de un Macro-Stack complejo. 
- Debemos instruir una regla nueva en `NEW_SERVICE_TEMPLATE.md` (Regla 7): Para Macro-Servicios que dependan de sub-directorios con scripts o volúmenes iniciales (.sql, .conf, .json), el script bash DEBE clonarlos directamente del repositorio oficial en `$INSTALL_DIR` garantizando que estén presentes *antes* del `podman-compose up -d`.
