# Escalabilidad, CI/CD y Seguridad
- **Arquitectura**: Escalado horizontal, modular, stateless (estado a DB/cache).
- **CI/CD**: Automatización total (dev/staging/prod). Testing: Linter, Unit, Integration, E2E.
- **IaC**: Infraestructura como código (Terraform/Pulumi). Contenedores mandatorios.
- **Seguridad (Secure Coding)**:
  - Validar inputs, escapar outputs, Queries parametrizadas.
  - JWT, HTTPS, MFA. Menor privilegio (Default Deny).
  - SBOM y escaneo SCA de dependencias. SAST en CI/CD.
  - Logs sin datos sensibles. Threat modeling en features críticas.
- **Observabilidad**: Métricas/Logs/Trazas (Prometheus/Grafana). SLO/SLI definidos.
