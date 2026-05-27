# Módulo: Certificación (M7)
 
> **Módulo:** M7 — Certificación
> **Responsable:** —
> **Versión:** 1.0 | **Estado:** Borrador
>
> **Stack, convenciones y modelos compartidos:** ver `/project.md` — no se repiten acá.
> **Interfaces con otros módulos:** ver `/contracts.md §M7`.

## 1. Objetivo y Contexto
 
### ¿Qué resuelve este módulo?
 
Es el motor encargado de la generación, almacenamiento y distribución de documentos PDF que acreditan la participación de un usuario en un evento académico. Permite la emisión de certificados de asistencia, aprobación y participación (como disertante o expositor).
 
### Lugar en el sistema
 
Este módulo es dependiente de las acciones que ocurren en los módulos M5 (Logística y Acreditación) y M3/M6 (Configuración/Agenda). No decide quién recibe un certificado; recibe órdenes explícitas (eventos o solicitudes) para generarlos basados en la asistencia o la aprobación validada externamente. Provee a los usuarios finales (participantes y disertantes) la interfaz para descargar sus comprobantes.
 
### Fuera del alcance de este módulo
 
- Toma de asistencia o registro de notas (eso pertenece a M5 y M8 respectivamente).
- Envío masivo de emails con los certificados adjuntos (se delega a un futuro servicio de notificaciones; aquí solo se permite la descarga directa).
- Verificación de pagos o cuotas al día.

---

## 2. Historias de Usuario y Criterios de Aceptación
 
### CERT-HU-01 — Configuración de plantilla por el Organizador
**Como** organizador del evento,
**quiero** configurar el texto base y la imagen de fondo del certificado,
**para que** los documentos generados tengan la identidad visual y firmas oficiales del evento.
 
**Criterios de aceptación:**
- [ ] Puedo subir una imagen base (plantilla) en formato PNG/JPG.
- [ ] Puedo definir un bloque de texto que acepte variables de reemplazo dinámico (ej: `{{nombre_completo}}`, `{{titulo_evento}}`, `{{fecha}}`).
- [ ] Puedo guardar la configuración y generar una previsualización de prueba.

### CERT-HU-02 — Pre-generación automática por Acreditación
**Como** sistema (integración con M5),
**quiero** solicitar la generación en background del certificado de asistencia en el momento que un participante se acredita,
**para que** el PDF esté listo inmediatamente cuando el participante intente descargarlo.

**Criterios de aceptación:**
- [ ] El endpoint de webhook `POST /api/certificacion/generar/asistencia` recibe la notificación (EVT-01) e inicia el proceso asíncrono o en lote de generación de PDF.
- [ ] El sistema valida con M5 (`GET /api/acreditacion/evento/:eventoId/asistentes`) que el usuario realmente esté acreditado antes de guardar el certificado definitivo.

### CERT-HU-03 — Descarga del certificado por el Participante (ACTUALIZADA - OWASP)

**Como** participante,
**quiero** acceder a mi perfil y descargar el certificado de un evento finalizado al que asistí,
**para que** pueda presentarlo sin que terceros no autorizados accedan a mi documento.

**Criterios de aceptación:**
- [ ] Veo un botón de "Descargar Certificado" en los detalles de mis eventos finalizados.
- [ ] Al hacer clic, se descarga un archivo PDF uniendo la plantilla del evento y mis datos personales.
- [ ] **[OWASP A01 - IDOR]** El endpoint de descarga (`GET /api/certificacion/descargar/:codigoVerificacion`) debe validar obligatoriamente que el `usuarioId` del registro del certificado coincide exactamente con el `usuarioId` extraído del JWT del token de sesión actual.
- [ ] **[OWASP A01]** Si un usuario intenta descargar un certificado que no le pertenece, el sistema debe responder con HTTP 403 (Forbidden) y auditar el intento de acceso no autorizado.

---

## 3. Requisitos Funcionales y Reglas de Negocio
 
### 3.1 Validaciones específicas de este módulo
 
| Campo/Acción | Regla |
|--------------|-------|
| Emisión | Nunca emitir un certificado `ASISTENCIA` si el usuario no figura en la lista provista por M5. |
| Unicidad | Un mismo usuario no puede tener dos certificados del mismo `tipo` para el mismo `evento`. |
| Código de Verificación | Cada certificado emitido genera un UUID único (`codigoVerificacion`) impreso en el PDF para futuras validaciones de autenticidad. |
| Reemplazo dinámico | El generador debe mapear `{{nombre_completo}}` leyendo la tabla compartida `Usuario` (`nombre` + `apellido`). |
 
### 3.2 Estados de un certificado
 
```
PENDIENTE_GENERACION → GENERADO
                     → REVOCADO (si la acreditación fue un error)
```

---

## 4. Restricciones técnicas específicas de este módulo

> El stack completo está en `/project.md §2`.

- **Generación de PDFs:** Utilizar la librería `pdf-lib` (Node.js) por su bajo consumo de memoria para estampar texto sobre plantillas PDF o imágenes existentes. No instalar dependencias pesadas como Puppeteer.
- **Almacenamiento temporal:** Dado que el sistema no contempla un S3 configurado por defecto, los certificados pre-generados se guardan en el sistema de archivos local temporalmente (`/uploads/certificados/`) o, como alternativa preferida, se almacena el payload en BD y el PDF real se construye *on-the-fly* si no está en caché.
- **Middlewares Zod:** Toda validación de request (ej. guardar plantilla o pedir generación) debe estar tipada con `z.object({...})` y pasar por un middleware antes de tocar el controller.
- **Manejo de Respuestas HTTP:** Cualquier fallo de validación cruzada con M5 devuelve un error estructurado HTTP `422` respetando el formato estandarizado (`{ data: null, error: {...}, message: "..."}`).

---

## 5. Modelo de datos de este módulo
 
> Los modelos `Usuario` y `Evento` están en `/project.md §6`. No redefinirlos acá. Se referencian mediante sus IDs.

```prisma
model PlantillaCertificado {
  id              Int      @id @default(autoincrement())
  eventoId        Int      @unique @map("evento_id")
  evento          Evento   @relation(fields: [eventoId], references: [id])
  imagenFondoUrl  String?  @map("imagen_fondo_url")
  textoEstructura String   @map("texto_estructura") @db.Text // JSON con posiciones o texto con variables
  creadoEn        DateTime @default(now()) @map("creado_en")
  actualizadoEn   DateTime @updatedAt @map("actualizado_en")

  @@map("plantillas_certificados")
}

model CertificadoEmitido {
  id                 Int      @id @default(autoincrement())
  eventoId           Int      @map("evento_id")
  evento             Evento   @relation(fields: [eventoId], references: [id])
  usuarioId          Int      @map("usuario_id")
  usuario            Usuario  @relation(fields: [usuarioId], references: [id])
  tipo               TipoCertificado
  codigoVerificacion String   @unique @default(uuid()) @map("codigo_verificacion")
  estado             String   @default("GENERADO") // "PENDIENTE_GENERACION", "GENERADO", "REVOCADO"
  emitidoEn          DateTime @default(now()) @map("emitido_en")

  @@unique([eventoId, usuarioId, tipo])
  @@index([codigoVerificacion])
  @@map("certificados_emitidos")
}

enum TipoCertificado {
  ASISTENCIA
  APROBACION
  DISERTACION
}
```

---

## 6. Plan de Tareas
 
> **Instrucción para Claude Code (leer antes de empezar):**
> Implementá las tareas de a una por vez, en el orden indicado.
> Al finalizar cada tarea, completá el **Reporte de cierre** que figura al final de ella y escribí la frase de pausa exacta. No avances a la siguiente tarea hasta recibir una confirmación explícita del usuario. Si el usuario escribe "continuar", "ok", "aprobado" o similar, recién entonces pasás a la tarea siguiente.
 
### T1 — Modelos de BD y Seed
**Entregables:**
- Añadir `PlantillaCertificado`, `CertificadoEmitido` y `TipoCertificado` al archivo `schema.prisma`.
- Ejecutar la migración: `prisma migrate dev --name add-certificacion`.
- Extender el seed existente creando 1 plantilla para un evento finalizado y 3 certificados emitidos para usuarios de prueba.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Resultado de `prisma migrate dev`: (pegar output)
- Qué NO se implementó en esta tarea que pertenece a tareas siguientes: (describir)
> ⏸ **STOP — T1 completa. Esperando confirmación para continuar con T2.**

### T2 — Servicio Core de PDFs (`pdf-lib`)
**Entregables:**
- Instalar dependencia `pdf-lib`.
- Crear `src/services/pdf.service.ts` con una función `generarCertificadoBuffer(plantilla, usuarioResumen, tipo)` que procese las variables de texto y construya un PDF en memoria (Buffer).

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Dependencias instaladas: (listar)
> ⏸ **STOP — T2 completa. Esperando confirmación para continuar con T3.**

### T3 — API para Organizadores (Plantillas)
**Entregables:**
- Schemas Zod para creación/actualización de plantillas.
- Endpoints en `src/routes/plantillas.routes.ts`: `GET /api/certificacion/plantillas/:eventoId`, `PUT /api/certificacion/plantillas/:eventoId`.
- Formato estandarizado en todas las respuestas.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Rutas expuestas: (listar)
> ⏸ **STOP — T3 completa. Esperando confirmación para continuar con T4.**

### T4 — API de Eventos y Pre-generación (Contrato M5)
**Entregables:**
- Implementar webhook `POST /api/certificacion/generar/asistencia` (EVT-01).
- En el controller, llamar a `fetch` interno apuntando a `GET /api/acreditacion/evento/:eventoId/asistentes` (simulado temporalmente o mockeado) para validar que el usuario pertenece a la lista antes de crear el registro `CertificadoEmitido`.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Validaciones aplicadas: (listar)
> ⏸ **STOP — T4 completa. Esperando confirmación para continuar con T5.**

### T5 — API Descarga y Frontend
**Entregables:**
- Endpoint `GET /api/certificacion/descargar/:codigoVerificacion` que devuelva el stream del PDF usando el `pdf.service.ts`.
- En Frontend (`src/services/` y `src/pages/`): Pantalla sencilla donde el usuario pueda listar sus certificados y descargarlos con fetch nativo procesando el `Blob`.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Componentes de UI creados: (listar)
> ⏸ **STOP — T5 completa. Esperando confirmación para finalizar módulo.**

---

## 7. Estrategia de Verificación
 
- [ ] **Test de integración EVT-01:** Enviar un POST a `/api/certificacion/generar/asistencia` y verificar que si M5 (mockeado) responde con 200 y el usuario en la lista, se inserte en `certificados_emitidos`. Si M5 no lo incluye, verificar que responde 422.
- [ ] **Test unitario de generación:** Proveer parámetros de prueba al `pdf.service.ts` y validar que devuelve un `Buffer` válido (comprobando el magic number `%PDF-` en el buffer).
- [ ] **Validación cruzada (Unicidad):** Intentar generar dos certificados tipo `ASISTENCIA` para el mismo usuario y evento; la DB o el ORM deben rechazarlo por el índice `@unique`.
- [ ] **Frontend Blob:** Comprobar que en el cliente, la respuesta de `GET /api/certificacion/descargar/:codigo` se intercepta correctamente generando un `URL.createObjectURL(blob)` para gatillar la descarga en el navegador sin redirecciones bruscas.
