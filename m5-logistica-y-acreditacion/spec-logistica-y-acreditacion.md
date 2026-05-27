# Módulo: Logística y Acreditación (M5)

> **Módulo:** M5 — Logística y Acreditación
> **Responsable:** —
> **Versión:** 1.0 | **Estado:** Borrador
>
> **Stack, convenciones y modelos compartidos:** ver `/project.md` — no se repiten acá.
> **Interfaces con otros módulos:** ver `/contracts.md §M5`.

## 1. Objetivo y Contexto

### ¿Qué resuelve este módulo?

Este módulo provee la interfaz y la lógica necesaria para realizar el "check-in" o acreditación física/virtual de los participantes el día del evento. Su objetivo es registrar quiénes realmente asistieron, validando su inscripción en tiempo real y permitiendo a los organizadores tener un control de aforo instantáneo.

### Lugar en el sistema

El M5 actúa como un puente operativo el día del evento. 
- **Consume de:** M4 (Motor de Inscripciones) para saber quién tiene derecho a ingresar.
- **Provee a:** M7 (Certificación) notificando quién ya está acreditado para que se le genere el certificado de asistencia, y expone una API para que M7 consulte el listado final.

### Fuera del alcance de este módulo

- La gestión de cobros o validación de pagos (es responsabilidad de M4).
- La generación en sí del PDF del certificado (es responsabilidad de M7).
- La asignación de asientos o espacios físicos detallados.

---

## 2. Historias de Usuario y Criterios de Aceptación

### ACRE-HU-01 — Acreditación manual de un participante (ACTUALIZADA - OWASP)

**Como** organizador asignado a la puerta del evento,
**quiero** buscar a un participante y marcarlo como presente,
**para que** su asistencia quede registrada oficialmente sin manipulación externa.

**Criterios de aceptación:**
- [ ] La interfaz debe mostrar una barra de búsqueda rápida y una lista de inscriptos (obtenida del M4).
- [ ] Al hacer clic en "Acreditar", el sistema debe registrar la hora exacta de ingreso.
- [ ] Si el participante ya estaba acreditado, la interfaz debe mostrar un aviso visual y bloquear el botón.
- [ ] **[OWASP A01]** El backend debe validar mediante un middleware de control de acceso que el usuario que ejecuta el request (extraído del JWT) posee el rol de `ORGANIZADOR` y está explícitamente vinculado a ese `eventoId` en la tabla `EventoOrganizador`. Se prohíbe el acceso a organizadores globales o no asignados al evento en cuestión.


### ACRE-HU-02 — Monitor de aforo en tiempo real
**Como** organizador,
**quiero** ver un resumen numérico en la pantalla de check-in (ej. "Acreditados: 45 / Inscriptos: 100"),
**para** saber cuánta gente falta llegar.

**Criterios de aceptación:**
- [ ] La pantalla de check-in debe incluir contadores actualizados de total de inscriptos vs. total de acreditados.

---

## 3. Requisitos Funcionales y Reglas de Negocio

### 3.1 Validaciones específicas
| Regla | Descripción |
|-------|-------------|
| **Doble Acreditación** | Un participante no puede acreditarse dos veces en el mismo evento. El endpoint debe devolver un error HTTP 409 si se intenta. |
| **Validación de Inscripción** | El backend debe consultar obligatoriamente al M4. Si el usuario no está en la lista de inscriptos, o su estado no es `CONFIRMADA`, se rechaza con HTTP 422. |
| **Resiliencia de Notificación** | El disparo del evento al M7 (`POST /api/certificacion/generar/asistencia`) no debe bloquear la respuesta al frontend. Si M7 falla, la acreditación en M5 sigue siendo válida (HTTP 200/201 al frontend). |

### 3.2 Formato de Respuestas
Todo endpoint expuesto debe cumplir estrictamente con el formato estandarizado en `/project.md §5` (`{ data, error, message }`).

---

## 4. Restricciones técnicas específicas de este módulo

> El stack completo está en `/project.md §2`. Acá solo van restricciones adicionales para M5.

- **Rendimiento crítico:** La operación de acreditación (POST) debe responder al frontend en menos de 300ms, ya que se usa en situaciones de alta concurrencia (filas de personas). Por esto, el POST al M7 se debe hacer mediante un *fire-and-forget* (promesa sin `await` bloqueante) o manejador de eventos asíncrono en Node.
- **Diseño Mobile-First:** El frontend de acreditación en `src/pages/` se usará principalmente en tablets o celulares por los recepcionistas. Las clases de Tailwind CSS deben optimizarse para pantallas táctiles (botones grandes, sin *hover* dependiente).
- **Consumo interno HTTP:** Para consultar al M4, el backend de M5 usará la función `fetch` nativa de Node.js 20 llamando a `http://localhost:<PUERTO_M4>/api/inscripciones/evento/:eventoId/listado`.

---

## 5. Modelo de datos de este módulo

> Los modelos `Usuario` y `Evento` existen globalmente. No se redefinen.

```prisma
model Acreditacion {
  id            Int      @id @default(autoincrement())
  eventoId      Int
  evento        Evento   @relation(fields: [eventoId], references: [id])
  usuarioId     Int
  usuario       Usuario  @relation(fields: [usuarioId], references: [id])
  metodo        String   @default("MANUAL") // Reservado para "MANUAL", "QR" futuro
  acreditadoEn  DateTime @default(now())

  // Restricción: Un usuario solo se acredita una vez por evento
  @@unique([eventoId, usuarioId])
  // Índice para búsquedas rápidas de acreditados por evento
  @@index([eventoId])
}
```

---

## 6. Plan de Tareas

> **Instrucción para Agentes de IA (leer antes de empezar):**
> Implementá las tareas de a una por vez, estrictamente en el orden indicado.
> Al finalizar cada tarea, completá el **Reporte de cierre** y escribí la frase de pausa exacta. 
> NO avances a la siguiente tarea hasta recibir confirmación explícita del usuario.

### T1 — Modelo de datos y migraciones
**Entregables:**
- Agregar `Acreditacion` al archivo `prisma/schema.prisma` compartido.
- Relacionar bidireccionalmente si Prisma lo requiere (agregando `acreditaciones Acreditacion[]` en los modelos `Usuario` y `Evento` ya existentes).
- Ejecutar `prisma migrate dev --name add-acreditacion`.

**Reporte de cierre — completar antes de detenerse:**
- Resultado de `prisma migrate dev`: (pegar output o estado de éxito)
- Cambios realizados en schema: (breve resumen)
> ⏸ **STOP — T1 completa. Esperando confirmación para continuar con T2.**

### T2 — Servicio de integración con M4 (Inscripciones)
**Entregables:**
- Crear `src/services/inscripciones.service.js` (o `.ts`).
- Implementar función que haga un `fetch` al endpoint del M4 (`GET /api/inscripciones/evento/:eventoId/listado`) para obtener los inscriptos confirmados. Manejar posibles errores de red amigablemente.

**Reporte de cierre — completar antes de detenerse:**
- Archivo creado y funciones exportadas: (listar)
> ⏸ **STOP — T2 completa. Esperando confirmación para continuar con T3.**

### T3 — API de Acreditación y Endpoints (Backend)
**Entregables:**
- `POST /api/acreditacion/evento/:eventoId/checkin`: Valida esquema con Zod (middleware), verifica en el servicio de M4 que esté inscripto, guarda en DB (Prisma), responde 201 o 409 si ya existe. Implementar el *fire-and-forget* (EVT-01) hacia el endpoint de M7.
- `GET /api/acreditacion/evento/:eventoId/asistentes`: Endpoint público estipulado en `/contracts.md §M5` que devuelve la lista de acreditados.

**Reporte de cierre — completar antes de detenerse:**
- Rutas implementadas en Express: (listar)
- Middlewares Zod creados: (listar)
> ⏸ **STOP — T3 completa. Esperando confirmación para continuar con T4.**

### T4 — Interfaz de Usuario de Check-in (Frontend)
**Entregables:**
- Crear `src/pages/CheckInEvento.jsx` (o `.tsx`).
- Consumir el listado del M4 (vía un endpoint proxy propio o directo si la arquitectura lo permite) para armar la tabla.
- Botón "Acreditar" por fila que llame al POST de M3.
- Contadores "Acreditados / Inscriptos".
- Estilos Tailwind optimizados para mobile (botones táctiles amplios).

**Reporte de cierre — completar antes de detenerse:**
- Componentes creados: (listar)
- Hooks/Services de UI integrados: (listar)
> ⏸ **STOP — T4 completa. Esperando confirmación para finalizar módulo.**

---

## 7. Estrategia de Verificación

- [ ] **Test de Concurrencia:** Enviar dos requests simultáneos de acreditación para el mismo `usuarioId` y `eventoId`. El primero debe dar 201 y el segundo 409, garantizando la restricción `@@unique` de la base de datos.
- [ ] **Test de Integración (Fallo M4):** Simular que el endpoint del M4 devuelve 404 o 500. El endpoint de acreditación debe capturarlo y devolver un error HTTP 422 claro ("No se pudo verificar la inscripción").
- [ ] **Test de Desacoplamiento (Fallo M7):** Simular que el endpoint del M7 (Certificación) está caído. Ejecutar un check-in. Debe guardarse en base de datos correctamente y devolver 201 al cliente sin demora adicional.
- [ ] **Auditoría de Frontend:** Renderizar la página de Check-in en viewport móvil (390px ancho). Verificar que la tabla/lista de participantes no se rompa (scroll horizontal manejado correctamente) y los botones de acción midan al menos `44px` de alto (clases `h-11` o `p-3` en Tailwind).
