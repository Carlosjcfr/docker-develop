# 🛡️ AnyType Self-Hosted (Podman)

AnyType es una plataforma "local-first" y cifrada. Este despliegue utiliza la arquitectura de clusters `any-sync`.

### 🚀 Gestión Rápida

- **Instalar/Actualizar**: `./anytype.sh`
- **Puertos Core**: `1001-1016` (TCP/UDP para Sync)
- **Dashboard Externo**: No tiene UI web nativa.

### 🔑 Configuración del Cliente

Para conectar tu App de escritorio/móvil:

1. Localiza el archivo generado: `/opt/anytype/etc/client.yml`
2. Copia su contenido a tu cliente AnyType en **Settings > Nodes > Self-hosted**.
3. Asegúrate de que el puerto `1004` (Coordinator) es accesible desde tu dispositivo.

### 📂 Persistencia

- **Data**: `/opt/anytype/storage/`
- **Configs**: `/opt/anytype/etc/` (Generadas dinámicamente)

> [!IMPORTANT]
> Si cambias la `HOST_IP`, debes ejecutar `./anytype.sh update` para regenerar los certificados de red.
