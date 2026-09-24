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
5. ~~`plataforma.migracion`~~ — hecho (set pacientes): cada parche anota su
   nombre al final y se salta solo si ya está (`\gset` + `\if`). El de
   pacientes registra los doce anteriores; la carga limpia siembra los trece.
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
  el mismo molde que empleados y roles. El catálogo ya existe. **Antes hay que
  decidir quién crea las sucursales: el propietario desde el LIS, o el operador
  (como parte del contrato).** Hasta entonces, queda pendiente.
- **Pacientes**: registrar, editar y ver están (set pacientes). Queda:
  - **Duplicados**: la pantalla de "posibles duplicados" al registrar
    (`core.posibles_duplicados` ya compara nombre y año) y la de fusionar
    (`core.fusionar_paciente` pasa a SECURITY DEFINER cuando tenga pantalla;
    la opción "Fusionar duplicados" del menú sigue apagada).
  - **"Crear boleta"**: los botones están apagados hasta que exista el módulo
    de órdenes.
  - **Paginación**: la lista trae los últimos 50 y lo demás se busca. Si un
    día hace falta "ver todos", va por cursor `(creado_en, paciente_id)`.
  - Detalle: una fecha estimada que resulte ser exactamente la real no se
    puede "confirmar" sin cambiarla (la base toma la misma fecha como "no la
    toqué"). Es un caso de uno en 365 y queda documentado en `editar_paciente`.
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
