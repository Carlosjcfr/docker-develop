---
trigger: always_on
---


Este archivo define el comportamiento del agente en el entorno de desarrollo de este proyecto.

---

## Meta

- Versión: `1.0`
- Autor: `engineer`
- Descripción:  
  Reglas de comportamiento del agente en el entorno de desarrollo.

---

## Objetivo general

El agente debe:

- Ayudar a analizar, diseñar, documentar y optimizar flujos de trabajo de forma coherente con el estado del proyecto.
- Mantener la sostenibilidad, mantenibilidad y claridad por encima de soluciones rápidas no estructuradas.

---

## Directorio de conocimiento: @beautifulMention

El directorio `@beautifulMention` es la fuente de verdad del proyecto.

El agente debe:

- Consultar `@beautifulMention` siempre antes de proponer cambios o nuevas features.
- Actualizar `@beautifulMention` cada vez que se tome una decisión relevante (features, refactorizaciones, errores).
- Mantener documentos claros, con nombres descriptivos y estructura predecible.

---

## Gestión de errores y bugs

Cuando se detecte o informe un error:

- Analizar contexto, pasos de reproducción, síntomas e impacto.
- Identificar causas probables y ordenarlas por probabilidad.
- Proponer soluciones con pasos concretos, impacto y riesgos.
- Documentar el resultado en la carpeta `/Bugs` de `@beautifulMention` con formato:  
  `/Bugs/[YYYYMMDD]-[descripcion-corta].md`.

---

## Análisis de nuevas features

Cuando se analice o integre una nueva feature:

- Consultar primero `@beautifulMention` para revisar requisitos y decisiones previas.
- Evitar soluciones redundantes o que contradigan el estado actual del proyecto.
- Generar un plan de acción comparativo en tabla con columnas:  
  `Opción`, `Descripción`, `Pros`, `Contras`, `Riesgos`, `Complejidad`.
- Incluir una recomendación final justificada con la opción más adecuada.
- Documentar el resultado en la carpeta relevante de `@beautifulMention` (por ejemplo, `/Features/` o `/Design/`).

---

## Refactorizaciones

Cuando se proponga o analice una refactorización:

- Justificar el motivo: legibilidad, mantenibilidad, rendimiento, seguridad, etc.
- Definir claramente el alcance (módulos, servicios o componentes afectados).
- Proponer un plan incremental con pasos, puntos de verificación y rollback.
- Documentar el diseño y las actualizaciones en `@beautifulMention` durante el proceso.

---

## Estilo de documentación y comunicación

El agente debe:

- Usar lenguaje claro, directo y concreto.
- Preferir listas y tablas al comparar opciones.
- Emplear títulos cortos y descriptivos.
- Escribir en español, salvo que se indique lo contrario.
- Incluir criterios de éxito y ejemplos cuando sea relevante.

---

## Principios de comportamiento

El agente debe:

- No asumir el estado del proyecto; consultar siempre el directorio de conocimiento.
- Evitar soluciones que contradigan decisiones ya documentadas sin justificación explícita.
- Ser proactivo en la detección de errores de diseño o redundancias.
- Mantener coherencia de estilo y estructura en todos los documentos generados.

---

> Nombre recomendado para el archivo dentro de Antigravity:  
> `.agent/rules/agent.md`  
> o  
> `rules/agent.md` dentro del proyecto.
