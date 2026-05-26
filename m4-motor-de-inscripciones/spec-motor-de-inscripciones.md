# Módulo: Motor de Inscripciones (M4)

> **Módulo:** M4 — Motor de Inscripciones
> **Responsable:** Equipo de Backend/Frontend
> **Versión:** 1.0 | **Estado:** Aprobado
>
> **Stack, convenciones y modelos compartidos:** ver `/project.md` — no se repiten acá.
> **Interfaces con otros módulos:** ver `/contracts.md §M4`.

## 1. Objetivo y Contexto

### ¿Qué resuelve este módulo?
Gestiona el ciclo de vida completo de la inscripción de un usuario a un evento académico. Permite a los participantes registrarse de forma autónoma (self-service) y a los organizadores realizar cargas manuales (por ejemplo, para invitados especiales o inscripciones presenciales de último momento).

### Lugar en el sistema
Es el puente entre el Catálogo de Eventos (M2) y la Logística/Acreditación (M5). Consume la disponibilidad de los eventos y genera el listado oficial de asistentes que luego deberán hacer el check-in.

### Fuera del alcance de este módulo
- La pasarela de pagos (se asume que, si el evento es de pago, la validación financiera corresponde a otro módulo futuro o se maneja offline para esta primera iteración).
- La emisión de certificados (es responsabilidad del M7).
- La gestión de acreditaciones presenciales el día del evento (es responsabilidad del M5).

---

## 2. Historias de Usuario y Criterios de Aceptación

### INS-HU-01 — Inscripción autónoma del participante (ACTUALIZADA - OWASP)
**Como** usuario autenticado en el rol de Participante,
**quiero** inscribirme a un evento académico publicado,
**para que** mi lugar quede reservado de forma consistente y garantizada.

**Criterios de aceptación:**
- [ ] El sistema debe validar que el evento esté en estado `PUBLICADO`.
- [ ] Un usuario no puede inscribirse dos veces al mismo evento.
- [ ] **[OWASP A04]** El sistema debe implementar un bloqueo a nivel transaccional en la base de datos durante el alta de la inscripción para evitar *Race Conditions*, garantizando que bajo ninguna circunstancia se exceda el `cupoMaximo`.
- [ ] **[OWASP A08]** El endpoint no debe confiar en parámetros de estado enviados por el cliente (ej. ignorar un campo `estado: CONFIRMADA` enviado en el body); el estado inicial de la inscripción debe forzarse siempre desde la capa de servicio del backend.

### INS-HU-02 — Inscripción manual por el organizador
**Como** Organizador,
**quiero** buscar a un usuario registrado e inscribirlo manualmente en un evento de mi competencia,
**para que** pueda garantizar la asistencia de invitados especiales o resolver problemas operativos.

**Criterios de aceptación:**
- [ ] El organizador puede inscribir al usuario ignorando temporalmente la restricción de `cupoMaximo` (overselling controlado).
- [ ] El registro debe dejar trazabilidad de qué organizador realizó la inscripción.
- [ ] El listado resultante debe estar disponible para ser consumido por el M5.

---

## 3. Requisitos Funcionales y Reglas de Negocio

### 3.1 Validaciones específicas
| Campo / Condición | Regla |
|-------------------|-------|
| Evento Inactivo | No se permiten inscripciones a eventos en estado `BORRADOR` o `FINALIZADO`. |
| Cupo | Si `cupoMaximo` no es nulo, `count(inscripciones_confirmadas) < cupoMaximo`. |
| Unicidad | Combinación `(eventoId, usuarioId)` debe ser única. |
| Fechas | No se permiten nuevas inscripciones si la `fechaFin` del evento ya pasó. |

### 3.2 Estados de una inscripción
```text
PENDIENTE → CONFIRMADA → CANCELADA
```
- **PENDIENTE:** El usuario solicitó cupo, pero requiere validación (ej. revisión del organizador).
- **CONFIRMADA:** El participante tiene su lugar asegurado. El M5 lo espera para acreditación.
- **CANCELADA:** El participante se dio de baja o fue rechazado. Libera cupo.

---

## 4. Restricciones técnicas específicas de este módulo

- **Concurrencia de Base de Datos:** La validación del `cupoMaximo` y la creación de la inscripción **deben** realizarse dentro de una transacción interactiva de Prisma (`prisma.$transaction`) aislando el query para evitar *Race Conditions* (condiciones de carrera) cuando múltiples usuarios intentan tomar el último cupo al mismo tiempo.
- **Validación en Backend:** Todos los payloads de los endpoints (ej. `{ eventoId }`) deben pasar estrictamente por un middleware de Express validado con `Zod`.
- **Integración M5:** El endpoint `GET /api/inscripciones/evento/:eventoId/listado` (definido en `contracts.md`) debe estructurar los datos mapeando los campos del modelo original a los DTOs `UsuarioResumen` solicitados.

---

## 5. Modelo de datos de este módulo

> Los modelos `Usuario` y `Evento` están en `/project.md §6`. No se redefinen acá.

```prisma
model Inscripcion {
  id                Int               @id @default(autoincrement())
  eventoId          Int
  evento            Evento            @relation(fields: [eventoId], references: [id])
  usuarioId         Int
  usuario           Usuario           @relation(fields: [usuarioId], references: [id])
  estado            EstadoInscripcion @default(CONFIRMADA)
  metodoRegistro    MetodoRegistro    @default(AUTONOMA)
  registradoPorId   Int?              // Relación opcional si la carga fue manual
  registradoPor     Usuario?          @relation("RegistradoPor", fields: [registradoPorId], references: [id])
  creadoEn          DateTime          @default(now())
  actualizadoEn     DateTime          @updatedAt

  // Restricción de unicidad: un usuario un solo registro por evento
  @@unique([eventoId, usuarioId])
  
  // Convención de nombres para la tabla
  @@map("inscripciones")
}

enum EstadoInscripcion {
  PENDIENTE
  CONFIRMADA
  CANCELADA
}

enum MetodoRegistro {
  AUTONOMA
  MANUAL
}
```

*(Nota: Para que esto funcione, Prisma exigirá implícitamente agregar `inscripciones Inscripcion[]` en los modelos compartidos `Usuario` y `Evento`. Esto debe hacerse en el schema global).*

---

## 6. Plan de Tareas

> **Instrucción para Agente IA (Claude Code / OpenCode):**
> Implementá las tareas de a una por vez, en el estricto orden indicado.
> Al finalizar cada tarea, completá el **Reporte de cierre** y escribí la frase de pausa exacta.
> No avances a la siguiente tarea hasta recibir una confirmación explícita del usuario (ej. "continuar", "ok").

### T1 — Actualización de Esquema y Base de Datos
**Entregables:**
- Agregar el modelo `Inscripcion` y los Enums al archivo `/prisma/schema.prisma` global.
- Añadir los arreglos relacionales inversos en los modelos `Usuario` y `Evento` existentes en el schema.
- Ejecutar la migración: `npx prisma migrate dev --name add_inscripciones_module`.

**Reporte de cierre — completar antes de detenerse:**
- Archivos modificados: (listar)
- Resultado de `prisma migrate dev`: (pegar output)
> ⏸ **STOP — T1 completa. Esperando confirmación para continuar con T2.**

### T2 — Lógica de Negocio y Controladores (Inscripción Autónoma)
**Entregables:**
- Crear `src/middlewares/inscripcion.schema.ts` con Zod para el POST de inscripción.
- Crear `src/repositories/inscripcion.repository.ts` con la transacción para validar cupo y crear el registro.
- Crear `src/services/inscripcion.service.ts` encapsulando las reglas de negocio (validar estado del evento, fechas).
- Crear `src/controllers/inscripcion.controller.ts` y exponer `POST /api/inscripciones`.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados: (listar)
- Cobertura de pruebas agregada (Vitest): (describir)
> ⏸ **STOP — T2 completa. Esperando confirmación para continuar con T3.**

### T3 — Endpoints de Integración y Listados
**Entregables:**
- Implementar el contrato para M5: `GET /api/inscripciones/evento/:eventoId/listado`.
- Asegurar que el formato de respuesta cumple exactamente con `contracts.md` (formato DTO `UsuarioResumen` y envoltura `{ data, error, message }`).
- Crear tests unitarios en Vitest comprobando el tipado de la respuesta.

**Reporte de cierre — completar antes de detenerse:**
- Endpoint expuesto: (ruta)
- Resultado de los tests de integración: (pegar output de Vitest)
> ⏸ **STOP — T3 completa. Esperando confirmación para continuar con T4.**

### T4 — Frontend (Servicios y Vistas)
**Entregables:**
- Crear `src/services/inscripciones.service.ts` utilizando `fetch` nativo para consumir el API.
- Crear el custom hook `src/hooks/useInscripcion.ts` para manejar el estado de carga y errores de red.
- Implementar el botón/modal de inscripción en la vista de detalle del evento (`src/pages/EventoDetalle.tsx` o equivalente), utilizando Tailwind CSS puro.
- Mostrar notificaciones (toasts/alerts) basadas en el formato estándar de errores (ej. `error.code`).

**Reporte de cierre — completar antes de detenerse:**
- Componentes actualizados/creados: (listar)
- Validaciones Zod cliente implementadas: (confirmar)
> ⏸ **STOP — T4 completa. Módulo listo para revisión final.**

---

## 7. Estrategia de Verificación

Para garantizar la fiabilidad del M4, el equipo de QA o el desarrollador deberá automatizar/ejecutar lo siguiente con **Vitest**:

1. **Test de Concurrencia (Race Condition):** Simular 5 requests simultáneos a `POST /api/inscripciones` para un evento con `cupoMaximo = 1`. Afirmar que solo 1 request devuelve `HTTP 201` y los otros 4 devuelven `HTTP 409` (o 422).
2. **Test de Formato de Salida:** Llamar al endpoint de listado (`GET .../listado`) y usar Zod en el test para validar que la respuesta estructuralmente coincide con el `UsuarioResumen` del contrato.
3. **Test de Restricción Unicidad:** Intentar inscribir al mismo usuario dos veces al mismo evento. Verificar respuesta `HTTP 409 Conflict`.
4. **Verificación de UI:** Validar que el botón de inscripción se deshabilita preventivamente en el frontend (React) si el JSON del catálogo de eventos (M2) ya indica `cuposDisponibles === 0`.
