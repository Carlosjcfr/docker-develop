# Plan de Acción: Resolución Dinámica de Etiquetas (Tags) de Imágenes

Este documento valora la propuesta de crear un script/función auxiliar en `lib.sh` capaz de interrogar registros (como docker.io o ghcr.io) para obtener la "última versión estable" de una imagen, evitando descargas fallidas (estado `missing`) o caídas (estado `stopped`) por discrepancias de versiones o alucinaciones de IA.

---

## Análisis de Viabilidad Técnica

La idea conceptual es brillante y evitaría la deuda técnica de las versiones hardcodeadas, pero **técnicamente en Bash plano es un auténtico infierno debido a la heterogeneidad del ecosistema Docker**.

### El Problema de las APIs y Registros

Para averiguar los tags de *docker.io/library/nginx* usando puramente `curl` sin autenticación, hay que:

1. Hacer una petición para obtener un token Bearer OAuth2 anónimo.
2. Hacer una segunda petición a la API V2 del registro usando ese token.
3. Parsear el JSON inmenso devuelto usando `jq` (requiriendo otra dependencia en el host).
4. ... Y esto cambia completamente si el repositorio es `ghcr.io` o `quay.io`.

### El Mito de la "Última Versión Estable"

Averiguar cuál es la "estable" es el mayor reto algorítmico:

- Algunos repositorios usan semántica estricta: `v1.2.3`.
- Otros arrastran sufijos: `1.2.3-alpine`, `1.2.3-bookworm`, `1.2.3-ls123`.
- Otros mezclan builds en desarrollo: `latest`, `beta`, `rc`, `edge`.
Filtrar automáticamente mediante expresiones regulares en Bash para discriminar qué es "estable real" frente a una "Release Candidate (rc)" es extremadamente frágil y terminaría instalando versiones inestables de todos modos.

---

## Pros y Contras de la Propuesta

**Pros:**

- Eliminaría las alucinaciones de código de las versiones.
- Aseguraría despliegues actualizados sin intervención humana en cada instalación en blanco.

**Contras:**

- **Complejidad Bash:** Interpretar JSON y OAuth2 puramente en shell es pesado y propenso a fallos.
- **Tiempos de latencia:** Consultar la API para 8 imágenes distintas (caso de Supabase) sumaría un retraso de red considerable.
- **Dependencias extra:** Requeriría forzar al sistema a tener `jq` u otras utilidades.
- **Límites de API:** Docker Hub restringe las peticiones anónimas severamente (Rate Limiting). En un servidor detrás de NAT o si abusas del script, tirará error 429 "Too Many Requests".

---

## Soluciones y Alternativas Posibles

### Opción A (La Nata): Uso de `skopeo`

En lugar de reinventar la rueda con `curl`, existe una herramienta oficial llamada **Skopeo** (hermana de Podman, creada por Red Hat) dedicada a interrogar registros sin descargar imágenes.

```bash
# Permite listar todos los tags de una imagen remotamente
skopeo list-tags docker://docker.io/supabase/postgres
```

**Contra:** Supone instalar un binario extra (`skopeo`) al servidor, aunque suele venir en el ecosistema Podman. Para extraer la "última" habría que seguir filtrando la cadena.

### Opción B (El Estándar): Abrazar la etiqueta `latest`

Si no introducimos ninguna variable, obligamos explícitamente a usar `:latest`.

- **Pro:** Casi universal. Funciona en el 95% de despliegues.
- **Contra:** Algunos servicios (como ciertos contenedores de Bitnami o stacks congelados) no publican etiqueta latest. A veces puede implicar descargar un build inestable si el autor no tiene buenas prácticas.

### Opción C (El Enfoque "Release Manifest"): Scraping de GitHub / .env Remotos

La razón por la que **Supabase** fracasa al usar `latest` o versiones aleatorias es porque funciona como un clúster estrechamente acoplado y cerrado: *Supabase Studio v2.x.x* solo funcionará con *Supabase Auth v1.x.x*. Tienen dependencias cruzadas de versión.
Para estos macro-servicios, en lugar de preguntar a DockerHub:

1. Buscar en su repositorio oficial de GitHub el archivo `.env` que marca la "Release Oficial".
2. Descargarlo y evaluar esas variables exactas.

### Opción D (Validación interactiva): Fallback Inteligente

La librería no busca la última estable, pero intercepta el error. Si el script principal detona un `missing`, el script entra en un bucle interactivo advirtiendo: *"El Tag proveído no existe en Docker. ¿Quieres forzar 'latest' o proveer uno manualmente?"*

## Recomendación de Arquitectura

Para no sobredimensionar la complejidad del orquestador `lib.sh` con parseadores JSON y autenticaciones OAuth2 anónimas inconsistentes en Bash, o **romper la premisa "Zero-Dependencies" forzando la instalación de Python**, se recomienda la **Opción D combinada con Opción C/Opción B**.

Es decir, advertir terminantemente en la guía de contribución/plantilla a la IA que use `latest` por norma (ya lo aplicamos en la regla estricta #5), y dejar la especificación dura a un archivo `.env` manual aportado por el usuario en situaciones de Macro-Stacks (Supabase) donde un engranaje de versiones congeladas es obligatorio.
