---
trigger: always_on
---

# Reglas de escalabilidad, CI/CD y ciberseguridad

Este documento define las reglas de diseño, desarrollo y despliegue para garantizar que el proyecto sea escalable, fiable y seguro.

---

## 🏗️ Arquitectura y escalabilidad

### Objetivo

Diseñar sistemas que puedan escalar horizontalmente, mantenerse estables bajo carga y evolucionar sin bloqueos arquitectónicos.

### Prácticas clave

- Priorizar **escalamiento horizontal** frente al vertical (más instancias, no solo más CPU/RAM). [web:48][web:52]  
- Usar una arquitectura **modular y desacoplada** (ej. servicios/microservicios, componentes reutilizables) para que cada parte pueda escalar de forma independiente. [web:48][web:52]  
- Diseñar servicios **stateless** siempre que sea posible, delegando estado a bases de datos, caches o servicios externos. [web:52][web:56]  
- Aprovechar plataformas cloud‑native (Kubernetes, ECS, cloud run, etc.) para gestión de orquestación, auto‑scaling y actualización sin interrupciones. [web:48][web:52]  
- Documentar el diseño de escalabilidad en el fichero de `architecture.md` del proyecto, incluyendo:
  - límites estimados (QPS, RPS, conexiones concurrentes),
  - puntos de cuello de botella esperados,
  - estrategias de mitigación.

---

## 🚀 Despliegue y CI/CD

### Objetivo

Garantizar que el pipeline de integración y despliegue sea rápido, seguro y confiable, permitiendo releases frecuentes y reversibles.

### Prácticas clave

- Usar **CI/CD completo y automatizado** en todos los entornos (dev, staging, prod). [web:49][web:53][web:57]  
- Implementar **testing en cada etapa**:
  - linters / formateo,
  - pruebas unitarias,
  - pruebas de integración,
  - pruebas de extremo a extremo (E2E) cuando sea crítico. [web:49][web:57]  
- Trabajar con **infraestructura como código** (Terraform, Pulumi, etc.) para que entornos sean reproducibles y auditable. [web:48][web:49]  
- Empaquetar servicios en **contenedores** (Docker) y usar **orchestration** (Kubernetes, Docker Compose, ECS, etc.). [web:49][web:52]  
- Implementar **despliegues continuos** con:
  - feature flags,
  - rollback automático si fallan health checks u observabilidad. [web:49][web:57]  
- Mantener un **pipeline de calidad por defecto**:
  - versionar el pipeline como código,
  - limitar despliegues manuales en producción,
  - usar solo branches protegidos y pull‑requests auditados. [web:49][web:53]

---

## 🛡️ Ciberseguridad y secure coding

### Objetivo

Integrar la seguridad desde el diseño (shift‑left) y evitar que el código sea la puerta de entrada de vulnerabilidades.

### Prácticas clave

- Aplicar **input validation y output encoding** en todos los puntos de entrada (APIs, formularios, ficheros, etc.) para evitar inyecciones y XSS. [web:50][web:54]  
- Usar **parámetros preparados o consultas parametrizadas** para evitar SQL injection y otros tipos de inyección. [web:50][web:54]  
- Implementar **autenticación y gestión de sesiones seguras**:
  - tokens seguros (JWT, oAuth con revocación),
  - uso de HTTPS,
  - MFA donde sea viable. [web:50][web:54]  
- Seguir el principio de **menor privilegio**:
  - roles mínimo necesarios,
  - “default deny” en permisos y políticas. [web:50][web:52]  
- Gestionar **dependencias de terceros**:
  - SBOM (Software Bill of Materials) cuando aplique,
  - escaneo de vulnerabilidades (SCA) y parcheo regular. [web:50][web:54]  
- Integrar **escaneo de seguridad** en CI/CD:
  - SAST (análisis estático),
  - DAST si aplica,
  - revisiones de código enfocadas en seguridad. [web:49][web:50][web:57]  
- Incluir **threat modeling** en el diseño de nuevas features críticas. [web:50][web:54]  
- Tratar los errores de forma segura:
  - sin revelar información sensible,
  - logs con contexto útil pero sin credenciales o datos sensibles. [web:50][web:54]

---

## 📊 Observabilidad y monitorización

### Objetivo

Tener visibilidad clara del sistema para detectar cuellos de botella, fallos y errores de seguridad.

### Prácticas clave

- Implementar métricas, logs y trazas distribuidas en toda la pila (APM, Prometheus, Grafana, etc.). [web:49][web:52][web:57]  
- Definir **SLOs/SLIs** básicos para servicios críticos:
  - latencia,
  - disponibilidad,
  - tasa de errores. [web:49][web:56]  
- Configurar alertas precisas (no ruido) sobre:
  - caídas de disponibilidad,
  - aumento de errores,
  - latencia anómala,
  - comportamientos sospechosos de seguridad. [web:49][web:57]  
- Incluir **dashboards por servicio** para que cada equipo pueda monitorizar sus propias métricas de escalabilidad y fiabilidad. [web:52][web:56]

---

## 🧱 Estilo y reglas de implementación

El agente debe:

- Proponer soluciones que se alineen con estas reglas de escalabilidad, CI‑CD y ciberseguridad.  
- Priorizar arquitecturas **modulares, stateless y desacopladas** frente a soluciones monolíticas rígidas. [web:48][web:52]  
- Incluir en cada propuesta de feature o refactorización:
  - impacto en escalabilidad,
  - impacto en el pipeline CI/CD,
  - riesgos de seguridad y mitigación.  
- Mantener la documentación actualizada:
  - documentar nuevas decisiones de arquitectura,
  - registrar cambios en el pipeline o en políticas de seguridad. [web:43][web:47]

---
