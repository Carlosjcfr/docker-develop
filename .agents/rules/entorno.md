---
trigger: always_on
---

# Entorno

---

1. el entorno donde se van a desplegar los servicios son vm instaladas sobre proxmox con ip fijas configuradas
2. los contendores se ejcutaran co podman rootles
3. los comandos se ejecutaran desde un usuario admin-sigergy ya preconfigurado con permisos sudo para poder acceder por ssh a la vm
4. Se deben orientar las rutas para /opt
5. en caso de que sea necesrario ejcutar en algun momento comandos chmod debe indicarse explicitame en el chat y no se hara referencia el los ficheros a esta indicacion
