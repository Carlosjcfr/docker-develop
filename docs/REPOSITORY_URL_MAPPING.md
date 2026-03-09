# Análisis y Plan de Acción: Mapeo de Rutas del Repositorio (Technical Debt)

## 📌 Origen del Error (curl: (22) 404 Not Found)

El error 404 que has experimentado al intentar instalar Caddy se debe a una severa debilidad de diseño en la forma en que los scripts gestionan las URLs de descarga (Hardcoding / Branch Pinning). 

Actualmente, las rutas están "quemadas" (hardcoded) en cada script apuntando a ramas específicas que podrían ya no existir, no estar sincronizadas, o que impiden testear los cambios en tu propia rama (`technical-debt-fixes`).

### Anatomía del desastre de ramas:
1. Llamaste a `deploy.sh` usando tu rama de pruebas (`technical-debt-fixes`).
2. Sin embargo, dentro de `deploy.sh`, la variable global apunta a `main`:
   `REPO_BASE="https://raw.githubusercontent.com/.../main"`
3. Por tanto, `deploy.sh` ignoró tu rama y se bajó el archivo `caddy.sh` desde la rama `main`.
4. Ese script `caddy.sh` (bajado de `main`) tiene a su vez definida otra ruta a fuego:
   `REPO_RAW=".../caddy-manager-proxy/projects/caddy-proxy-manager"`
5. `caddy.sh` intentó descargar `config.env` y `docker-compose.yml` usando la rama `caddy-manager-proxy`, provocando el **Error 404** si la rama fue borrada, fusionada o los archivos movidos.
6. A su vez, `caddy.sh` descargó la librería `lib.sh` desde "main" nuevamente:
   `_LIB_URL=".../main/lib/lib.sh"`

---

## ⚠️ Análisis de Deuda Técnica y Debilidades

| Problema | Impacto | Descripción |
| :--- | :---: | :--- |
| **Branch Pinning** (Ramas bloqueadas) | Crítico | Cada script apunta ciegamente a una rama fija (`main` o `caddy-manager-proxy`). Es imposible desarrollar y probar scripts en ramas secundarias sin editar código temporalmente y arriesgarte a comitearlo roto. |
| **Fragmentación de Variables** | Alto | `deploy.sh` usa `REPO_BASE`, `caddy.sh` usa `REPO_RAW` y `_LIB_URL`. Si cambias el nombre del usuario de GitHub o el nombre del repositorio, el despliegue colapsaría por tener que modificar decenas de ficheros. |
| **Dificultad de Testeo (CI)** | Crítico | GitHub Actions descarga el repo localmente, pero en tiempo de ejecución los scripts van a la red y bajan archivos de la rama `main`, ignorando por completo los cambios locales introducidos en la Pull Request en curso. |
| **Redundancia** | Medio | Cada servicio tiene que declarar de nuevo desde qué lugar debe descargarse. |

---

## 🛠 Plan de Acción y Solución Propuesta

El objetivo es lograr un sistema **dinámico y en cascada**, donde la rama y la base del repositorio se definan una única vez y circulen fluidamente hacia todos los scripts.

### Paso 1: Variables de Entorno Dinámicas para Control de Ramas
Implementar una variable prioritaria que permita definir la rama (Branch / Tag / Commit). 
Ejemplo en `deploy.sh` y todos los scripts:
```bash
GIT_BRANCH="${GIT_BRANCH:-main}"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/Carlosjcfr/docker-develop/$GIT_BRANCH}"
```
Esto permitirá ejecutar pruebas con una sola variable ambiental:
`GIT_BRANCH=technical-debt-fixes curl -sfSL ... | bash`

### Paso 2: Eliminación de Hardcodings (DRY - Don't Repeat Yourself)
1. **En `deploy.sh`**: Será el único archivo que necesite saber de dónde viene. Inyectará `GIT_BRANCH` y `REPO_BASE` al ejecutar los `mktemp` sub-scripts.
2. **En los scripts de servicio (`caddy.sh`, `arcane.sh`)**:
   - Reemplazar las descargas fijas de `_LIB_URL`.
   - Modificar `REPO_RAW` para que se derive dinámicamente de `$REPO_BASE`.
   ```bash
   REPO_RAW="${REPO_BASE}/projects/caddy-proxy-manager"
   ```

### Paso 3: Consolidar Descargas (Descarga Relativa en `lib.sh`)
Refactorizar `download_repo_files()` en `lib.sh` para que no dependa ciegamente de un solo repositorio, con compatibilidad para descargas locales de testing:
- Si el contexto es GitHub Actions o pruebas locales (detectado si existe un flag `LOCAL_MODE=1`), en lugar de hacer `curl`, los scripts harán simple `cp` o `cat` a partir del árbol local de directorios, facilitando brutalmente el testeo sin depender de internet.

### Siguiente Fase a Ejecutar:
Una vez me autorices a actuar, procederé a modificar `deploy.sh`, `lib.sh`, `caddy.sh` y `arcane.sh` para limpiar esta Deuda Técnica e inyectar el sistema en cascada.
