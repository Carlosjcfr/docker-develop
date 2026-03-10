---
trigger: always_on
---

# Reglas de entorno de despliegue

Este documento define las reglas del entorno de despliegue del proyecto, incluyendo infraestructura, contenedores, usuarios y permisos.

---

## 1. Infraestructura y VMs

- El entorno de despliegue está compuesto por **VMs instaladas sobre Proxmox**.  
- Cada VM dispone de una **IP fija configurada** en la red.  
- Todos los servicios deben estar pensados para este modelo de infraestructura (hosts explícitos, no solo “en la nube” sin configuración).

---

## 2. Contenedores (Podman rootless)

- Los contenedores se ejecutarán usando **Podman en modo rootless**.  
- No se debe asumir que el agente o el despliegue disponen de permisos de root a nivel de sistema.  
- Cualquier configuración de contenedores debe ser compatible con el uso de Podman sin privilegios elevados.

---

## 3. Acceso SSH y usuario

- Los comandos se ejecutarán desde un usuario llamado **`admin-sigergy`**, ya preconfigurado.  
- El usuario `admin-sigergy` tiene permisos **`sudo`** para ejecutar comandos necesarios en la VM.  
- Todas las instrucciones de despliegue deben asumir que el flujo se inicia con este usuario y no con root.

---

## 4. Estructura de rutas

- Las rutas dentro del sistema deben orientarse hacia el directorio `/opt`.  
- Se recomienda usar estructuras como:
  - `/opt/sigergy/` para servicios generales,
  - `/opt/sigergy/<servicio>` para cada componente o servicio desplegado.  
- Evitar rutas arbitrarias fuera de `/opt` sin justificación explícita.

---

## 5. Gestión de permisos (chmod)

- En caso de que sea necesario ejecutar comandos `chmod` o cambios de permisos:
  - **Debe indicarse explícitamente en el chat** la necesidad de cambiar permisos.
  - **No se hará referencia en los ficheros** a esta indicación (es decir, los comandos `chmod` no se incluirán en scripts o ficheros de configuración, sino solo en instrucciones conversacionales).  
- El agente debe:
  - explicar por qué se necesitan esos permisos,
  - recomendar los mínimos necesarios (principio de menor privilegio).

---

## 6. Comportamiento esperado del agente

- El agente debe:
  - Proponer comandos y ficheros compatibles con:
    - VMs en Proxmox,
    - Podman rootless,
    - Usuario `admin-sigergy` con `sudo`.
  - Usar siempre rutas basadas en `/opt` salvo que se justifique explícitamente otra ubicación.
  - No incluir comandos `chmod` en los ficheros generados, dejando su ejecución explícita mediante el usuario (`sudo chmod ...` en el chat, si es necesario).
