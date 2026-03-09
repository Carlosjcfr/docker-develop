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
