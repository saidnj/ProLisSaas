# Pendientes

Lo que falta, en el orden en que conviene hacerlo. Se tacha aquí cuando entra
al repositorio. Los "sets" son bloques chicos que se aplican, se prueban y se
suben de una vez.

## Sets acordados con la revisión externa

1. ~~`git init`~~ — hecho (`7c0edae`).
2. ~~Set "cerrar"~~ — hecho (`297dd41`): `password_hash` por columnas,
   `registrar_acceso`, CORS sin `credentials`, un solo esquema, e2e viejo fuera.
   - Queda tuyo: `.claude/agents/revisor-esquema.md` apunta todavía a
     `db/schema` (dos líneas). Todo lo que está bajo `.claude/` lo editás y lo
     subís vos: las herramientas de la sesión no entran ahí.
3. ~~Set "rendimiento"~~ — hecho (`fe641f4`): 7 → 5 idas por petición, pool
   explícito con `DB_POOL_MAX`, `P2028` → 503, `40001`/`40P01` → 409,
   `22P02`/`23502` → 400, arreglos directos, `.env.ejemplo`.
4. **Set "ficha sensible"** — antes de la primera puesta en producción:
   identidad, teléfono, correo y colegiación de `core.empleado` solo con
   `usuario.administrar`, desde la base (privilegios por columna + vista o
   función SECURITY DEFINER). Nombre y cargo siguen abiertos: `abrirSesion()`
   los lee antes de que haya sede. Toca la lista, la ficha y `duplicados.ts`.
5. **`plataforma.migracion`**: tabla donde cada parche anota su nombre al
   final y se salta solo si ya está. Entra con el próximo parche que se
   escriba; los once anteriores se registran a mano una vez.
6. **Throttler** en `/auth/login` y `/auth/activar` por IP
   (`@nestjs/throttler`; ojo con `X-Forwarded-For` detrás de un proxy).
7. **Refrescar la sesión al navegar**: `GET /auth/yo` desde el guard, para que
   un cambio de rol o de permisos le llegue a quien está adentro sin volver a
   entrar. Hoy los botones de más se pintan y el back rechaza.
8. **Pruebas e2e del API**: los scripts `curl` que se corren en cada set pasan
   a Jest (`test/`). Hoy `npm run test:e2e` no encuentra pruebas.

## Del producto (decisiones pendientes)

- **"Mi perfil" / cambiar mi clave**: no existe. Mientras tanto un
  administrador no edita ni su propia ficha (la ficha sigue a la cuenta): se
  lo pide al propietario.
- **Sucursales**: módulo de administrar (abrir, configurar, cerrar sedes), con
  el mismo molde que empleados y roles. El catálogo ya existe.
- **Pacientes**: apenas empezado. Al armarlo: `exigirPermiso` en `listar` y
  paginación por cursor `(apellidos, nombres, paciente_id)`.
- **Auditoría**: pantalla sobre `audit.evento`.
- **Traspaso de propiedad**: es del operador, no del LIS; falta definirlo.
- **Estrategia de errores en el front**: decisión conjunta pendiente (hoy cada
  pantalla muestra `error-caja` con el mensaje del back).
- **Menú**: la opción "Usuarios" está apagada y sin ruta; empleados ya es
  usuarios. Quitarla.
- `/auth/yo`: marcado para borrar antes de producción.

## Documentación (no se empieza sin acordarlo)

- `documentacion/` no cuenta nada de lo hecho desde el set de cuenta:
  empleado = usuario, roles con nivel, la ficha sigue a la cuenta,
  `core.usuario` cerrada.
- `documentacion.html` se regenera con `generar_visor.py` después de tocar
  los `.md`.

## Más adelante, si hace falta

- `packages/contratos` (tipos compartidos front/back): cuando haya un segundo
  consumidor del API. No arregla las claves de `jsonb_build_object`: eso lo
  ven las pruebas.
- `httpResource` / `rxResource` en Angular: probarlo en la próxima pantalla
  nueva, no reescribir las que hay.
- PgBouncer en modo transacción: el diseño ya es compatible (todo va con
  `SET LOCAL`).
