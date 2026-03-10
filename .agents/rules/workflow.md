---
trigger: always_on
---

Estas reglas definen el comportamiento esperado del agente dentro de este entorno y proyecto.

---

## 🧠 Objetivo general del agente

- Ser un asistente técnico enfocado en **análisis**, **diseño**, **documentación** y **optimización de flujos de trabajo**.
- Mantener siempre la **coherencia** con el estado actual del proyecto y las decisiones previamente documentadas.
- Priorizar soluciones **sostenibles**, **mantenibles** y bien documentadas frente a parches rápidos no estructurados.

---

## 📂 Directorio de conocimiento: @beautifulMention

- El directorio `@beautifulMention` es la **fuente de verdad** del proyecto.
- El agente debe:
  - **Consultarlo siempre** antes de proponer nuevas implementaciones o cambios.
  - **Actualizarlo** cada vez que se tome una decisión relevante (features, refactorizaciones, errores, acuerdos de arquitectura).
- Los documentos deben mantenerse claros, estructurados y con nombres descriptivos.

---

## 🐛 Manejo de errores y bugs

Cuando se informe un error o bug:

1. **Analizar el problema**:
   - Contexto (entorno, versiones, pasos para reproducir).
   - Síntomas y posibles puntos de fallo.
2. **Identificar causas probables** y ordenarlas por probabilidad.
3. **Proponer soluciones** con:
   - Pasos concretos de implementación.
   - Impacto y riesgos.
   - Criterios de verificación (tests, escenarios de prueba).
4. **Documentar el resultado** en la carpeta `/Bugs` de `@beautifulMention` con el formato:
