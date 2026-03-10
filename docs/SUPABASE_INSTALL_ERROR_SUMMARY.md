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

---

## Error 7: Realtime Crash - Missing SECRET_KEY_BASE

**Problema:**
El contenedor `supabase-realtime` se queda en estado `stopped` con el error:
`** (System.EnvError) could not fetch environment variable "SECRET_KEY_BASE" because it is not set`.

**Causa Raíz:**
El motor Elixir (Phoenix) sobre el que corre Realtime exige una clave secreta de cifrado obligatoria para las cookies y sesiones internas del clúster. La IA original no incluyó esta variable ni en la generación de secretos ni en el mapa de entorno del `docker-compose.yml`.

**Solución:**
1. Modificar `supabase.sh` para que `manage_credentials` genere automáticamente una cadena aleatoria para `SECRET_KEY_BASE`.
2. Mapear dicha variable en la sección `environment:` del servicio `realtime` en el `docker-compose.yml`.

---

## Error 8: The Ghost Volume Trap & Role Mismatches (password authentication failed)

**Problema:**
Servicios como `supabase-storage` (y otros dependientes) lanzan errores masivos de conexión:
`password authentication failed for user "postgres"` o similares.

**Causa Raíz:**
1. **La Trampa del Volumen Fantasma (`Ghost Volume`):** Cuando eliminaste la carpeta `/opt/supabase` para reinstalar, el archivo `config.env` que contenía el `POSTGRES_PASSWORD` original se destruyó. Al reinstalar, el script generó un *nuevo* password. Sin embargo, el volumen Docker persistente (`supabase_db_data`) NO se borró ni se vació. Postgres detectó datos existentes, usó la contraseña antigua horneada en el volumen, ignoró los scripts `.sql` de inyección que acabábamos de crear, y denegó todas las nuevas conexiones que usaban la nueva contraseña.
2. **Rol "postgres" Hardcodeado:** En el `docker-compose.yml`, todos los servicios usaban al superusuario genérico `postgres`, ignorando los roles de ultra-precisión (`supabase_storage_admin`, `authenticator`, etc.) que el fabricante usa nativamente para segmentar permisos de seguridad.

**Solución Implementada:**
1. **Corrección de Roles en YAML:** Hemos editado el `docker-compose.yml` para que `auth` use `supabase_auth_admin`, `rest` use `authenticator`, `meta`/`realtime` usen `supabase_admin` y `storage` use `supabase_storage_admin`.
2. **Procedimiento de Limpieza Obligatorio:** Para reinstalar un stack tan denso desde cero de verdad, NUNCA basta con hacer un `rm -rf /opt`. Se deben destruir los volúmenes, o bien usando el comando nativo de nuestro framework `bash supabase.sh --uninstall`, o ejecutando `podman volume rm supabase_supabase_db_data`.

---

## Error 9: Auth Crash - Missing GOTRUE_DB_DRIVER

**Problema:**
El contenedor `supabase-auth` falla al arrancar con el error fatal:
`{"level":"fatal","msg":"Failed to load configuration: required key GOTRUE_DB_DRIVER missing value"}`.

**Causa Raíz:**
Las versiones recientes de GoTrue (como la `v2.186.0`) requieren explícitamente la definición del motor de base de datos (`postgres`) en una variable de entorno dedicada, incluso si la URL de conexión ya lo implica.

**Solución:**
1. Añadir `GOTRUE_DB_DRIVER="postgres"` al archivo `config.env`.
2. Actualizar `supabase.sh` para exportar esta variable al archivo `.env` de runtime.
3. Mapear `GOTRUE_DB_DRIVER: ${GOTRUE_DB_DRIVER}` en la sección `environment:` del servicio `auth` en `docker-compose.yml`.
