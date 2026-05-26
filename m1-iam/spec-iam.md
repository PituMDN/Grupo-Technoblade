# Módulo: Identidad y Acceso (IAM) (M1)

> **Módulo:** M1 — Identidad y Acceso (IAM)
> **Responsable:** —
> **Versión:** 1.0 | **Estado:** Borrador
>
> **Stack, convenciones y modelos compartidos:** ver `/project.md` — no se repiten acá.
> **Interfaces con otros módulos:** ver `/contracts.md §M1`.

## 1. Objetivo y Contexto

### ¿Qué resuelve este módulo?

Gestiona la autenticación, el registro de usuarios y el control de acceso basado en roles (RBAC). Es el guardián de la plataforma, asegurando que cada persona pueda ingresar de forma segura y solo acceda a los recursos y acciones permitidos según su rol (Organizador, Participante, Disertante).

### Lugar en el sistema

Es el **primer punto de interacción** para cualquier usuario que necesite interactuar de forma no anónima con el sistema. Provee la identidad que consumirán todos los demás módulos (Catálogo, Inscripciones, Certificación, etc.) a través del modelo compartido `Usuario` y los middlewares de autorización.

### Fuera del alcance de este módulo

- Asignación de disertantes a charlas específicas (corresponde a M6 - Agenda).
- Proceso de inscripción a eventos (corresponde a M4 - Inscripciones).
- Recuperación avanzada de cuentas mediante flujos de validación de identidad biométrica o 2FA (se pospone para versiones futuras).

---

## 2. Historias de Usuario y Criterios de Aceptación

### IAM-HU-01 — Registro de nuevo participante

**Como** persona interesada en los eventos académicos,
**quiero** registrarme en la plataforma con mis datos personales,
**para que** pueda inscribirme a futuros eventos como participante.

**Criterios de aceptación:**

- [ ] El formulario requiere email, contraseña, nombre y apellido.
- [ ] La contraseña debe tener al menos 8 caracteres.
- [ ] El sistema verifica que el email no esté registrado previamente.
- [ ] Al crearse la cuenta, se le asigna automáticamente el rol `PARTICIPANTE`.
- [ ] El registro exitoso crea el registro en la tabla compartida `Usuario` y devuelve un código 201.

### IAM-HU-02 — Inicio de sesión y generación de token (ACTUALIZADA - OWASP)

**Como** usuario registrado,
**quiero** iniciar sesión con mi email y contraseña,
**para que** el sistema me identifique y me permita operar según mi rol de forma segura.

**Criterios de aceptación:**
- [ ] Si las credenciales son correctas, el sistema devuelve un JWT firmado con un tiempo de vida (TTL) corto (máximo 1 hora).
- [ ] **[OWASP A07]** Si las credenciales son incorrectas, el sistema devuelve un error 400 genérico ("Credenciales inválidas") asegurando que los tiempos de respuesta no revelen si el usuario existe o no.
- [ ] **[OWASP A07]** El endpoint `POST /api/auth/login` debe tener configurado un Rate Limiter estricto (ej. bloqueo de IP por 15 minutos tras 5 intentos fallidos) para evitar ataques de fuerza bruta.
- [ ] El token generado incluye el `usuarioId` y la lista de roles del usuario en su payload, siendo almacenado preferentemente en una cookie HttpOnly.

### IAM-HU-03 — Asignación de rol Disertante

**Como** Organizador,
**quiero** asignarle el rol de Disertante a un usuario registrado existente,
**para que** pueda ser vinculado a la agenda de los eventos.

**Criterios de aceptación:**

- [ ] Solo un usuario que ya posee el rol `ORGANIZADOR` puede ejecutar esta acción.
- [ ] La búsqueda del usuario a asignar se realiza por email exacto.
- [ ] El sistema añade el rol `DISERTANTE` sin eliminar los roles previos (ej. también sigue siendo `PARTICIPANTE`).

---

## 3. Requisitos Funcionales y Reglas de Negocio

### 3.1 Validaciones específicas de este módulo

| Campo | Regla |
|-------|-------|
| Email | Formato de email válido (validado con Zod: `z.string().email()`). Se guarda en minúsculas. |
| Contraseña | Mínimo 8 caracteres, validado solo en la creación. NUNCA transita hacia el cliente. |
| Roles | Un usuario puede tener múltiples roles simultáneos. Al menos debe tener uno. |

### 3.2 Matriz de Permisos (RBAC)

- **Participante:** Puede editar su perfil público y ver su historial de sesiones.
- **Disertante:** Hereda lo de participante + puede actualizar su biografía/foto de expositor (si se implementa el perfil extendido).
- **Organizador:** Tiene permisos de superusuario dentro de la plataforma para asignar roles y gestionar eventos en el M3.

---

## 4. Restricciones técnicas específicas de este módulo

> El stack completo está en `/project.md §2`. Acá solo van restricciones adicionales que aplican únicamente a este módulo.

- **Seguridad de contraseñas:** Deben hashearse usando `bcrypt` (salt rounds: 10) o `argon2` antes de guardarse en la BD. Nunca se guardan en texto plano.
- **Autenticación (JWT):** El backend debe emitir un JSON Web Token (JWT) con una expiración de 24 horas. El frontend almacenará este token y lo enviará en el header `Authorization: Bearer <token>` usando `fetch`.
- **Middlewares de validación:** Se deben crear dos middlewares centrales en Express que serán compartidos con el resto de los módulos:
  1. `requireAuth`: Verifica la validez del JWT e inyecta `req.usuario`.
  2. `requireRole(rolesRequeridos)`: Verifica que `req.usuario` contenga al menos uno de los roles solicitados.

---

## 5. Modelo de datos de este módulo

> El modelo `Usuario` está en `/project.md §6`. No redefinirlo acá.
> Se agregan solo los modelos nuevos al `/prisma/schema.prisma`, relacionándolos con `Usuario`.

```prisma
// Extensiones de IAM para el modelo compartido Usuario

model Credencial {
  id          Int      @id @default(autoincrement())
  usuarioId   Int      @unique
  usuario     Usuario  @relation(fields: [usuarioId], references: [id], onDelete: Cascade)
  hashClave   String
  creadoEn    DateTime @default(now())
  actualizadoEn DateTime @updatedAt
}

model RolUsuario {
  id          Int      @id @default(autoincrement())
  usuarioId   Int
  usuario     Usuario  @relation(fields: [usuarioId], references: [id], onDelete: Cascade)
  rol         TipoRol
  asignadoEn  DateTime @default(now())
  asignadoPor Int?     // usuarioId del organizador que asignó el rol (null si es auto-asignado al registrarse)

  @@unique([usuarioId, rol])
}

enum TipoRol {
  ORGANIZADOR
  PARTICIPANTE
  DISERTANTE
}
```

---

## 6. Plan de Tareas

> **Instrucción para Claude Code / OpenCode (leer antes de empezar):**
> Implementá las tareas de a una por vez, en el orden indicado.
> Al finalizar cada tarea, completá el **Reporte de cierre** que figura al final de ella y escribí la frase de pausa exacta. No avances a la siguiente tarea hasta recibir una confirmación explícita del usuario. Si el usuario escribe "continuar", "ok", "aprobado" o similar, recién entonces pasás a la tarea siguiente.

---

### T1 — Modelos de BD y Seed de IAM

**Entregables:**
- Modelos `Credencial` y `RolUsuario` agregados al `schema.prisma`.
- Modificación menor en `Usuario` (solo para agregar las relaciones inversas `credencial Credencial?` y `roles RolUsuario[]`).
- Migración ejecutada: `prisma migrate dev --name init-iam`.
- Seed con: 1 usuario Organizador, 1 usuario Disertante, 2 usuarios Participantes (con contraseñas conocidas, ej. "Test1234!").

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Resultado de `prisma migrate dev`: (pegar output)
- Resultado de `prisma db seed`: (pegar output)
- Qué NO se implementó en esta tarea que pertenece a tareas siguientes: (describir)
> ⏸ **STOP — T1 completa. Esperando confirmación para continuar con T2.**

---

### T2 — Endpoints de Registro y Login

**Entregables:**
- Instalación de dependencias de seguridad (`bcrypt`, `jsonwebtoken`).
- `POST /api/auth/registro`: Valida payload con Zod, crea `Usuario`, crea `Credencial` (hash), asigna rol `PARTICIPANTE` en `RolUsuario`. Responde formato estándar.
- `POST /api/auth/login`: Verifica credenciales, emite JWT. Responde formato estándar con el token en el `data`.
- Tests en Vitest (flujos de éxito y error para ambos).

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Resultado de los tests de Vitest: (pegar output)
> ⏸ **STOP — T2 completa. Esperando confirmación para continuar con T3.**

---

### T3 — Middlewares de Autenticación y Endpoints de Gestión de Roles

**Entregables:**
- `src/middlewares/requireAuth.js`: Verifica JWT y decodifica payload.
- `src/middlewares/requireRole.js`: Valida array de roles.
- `POST /api/auth/asignar-rol`: Endpoint protegido (solo Organizador). Recibe email y rol a asignar.
- Tests en Vitest verificando que los middlewares rechacen accesos no autorizados.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Resultado de los tests de Vitest: (pegar output)
> ⏸ **STOP — T3 completa. Esperando confirmación para continuar con T4.**

---

### T4 — Frontend: Páginas de Autenticación y Contexto

**Entregables:**
- Servicio HTTP en React (`src/services/api.js` o `authService.js`) usando `fetch` nativo para registro y login.
- `src/pages/Login.jsx` y `src/pages/Registro.jsx` con diseño en Tailwind CSS.
- Validación de formularios de cliente utilizando Zod.
- Contexto de React (`AuthContext`) para almacenar el estado del usuario logueado en memoria/localStorage.
- Configuración de React Router para proteger rutas privadas.

**Reporte de cierre — completar antes de detenerse:**
- Archivos creados o modificados: (listar)
- Confirmación de validación Zod en formularios: (sí/no)
> ⏸ **STOP — T4 completa. Módulo IAM finalizado.**

---

## 7. Estrategia de Verificación

Además del estándar definido en `project.md`, este módulo requiere especial atención en la seguridad:

- [ ] **Ataque a contraseñas:** Verificar directamente en la base de datos PostgreSQL que la columna `hashClave` no contiene ningún valor legible, incluso para cuentas de prueba.
- [ ] **Fuga de datos:** Asegurarse de que las respuestas HTTP del backend NUNCA devuelvan el objeto `Credencial` ni el campo de la contraseña bajo ninguna circunstancia.
- [ ] **Expiración de Sesión:** Modificar temporalmente el JWT para que expire en 1 segundo y verificar que el middleware `requireAuth` devuelva el error HTTP 401 correspondiente.
- [ ] **Escalamiento de privilegios:** Intentar consumir el endpoint `POST /api/auth/asignar-rol` enviando un JWT válido de un usuario con rol `PARTICIPANTE` y validar que retorne HTTP 403 (Forbidden).
