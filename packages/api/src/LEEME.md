# El API: como esta organizado y las reglas para que siga asi

## El mapa

```
src/
  main.ts            arranque: CORS, ValidationPipe (whitelist), filtro de errores
  app.module.ts      registra los modulos; el guard de sesion es GLOBAL (todo pide token salvo @Publico)
  comun/             lo que no es de ningun modulo
    sesion.ts                que trae el token (empresa, usuario, sede)
    sesion.decorador.ts      @SesionActual()
    errores.filtro.ts        SQLSTATE de Postgres -> 401/403/409/400 con mensaje legible
    codigo.ts                el codigo de activacion (lo usan empleados y auth)
    permiso.ts               exigirPermiso(): "tiene el permiso?" antes de trabajar, con un 403 legible
  prisma/            la conexion: conSesion() abre la transaccion y pone la sesion (SET LOCAL ROLE lis_app + lis.*)
  auth/              entrar, activar, yo; el guard JWT
  empleados/         empleado + cuenta (son uno): crear, guardar, codigo nuevo, desbloquear
    cuenta.ts                sedes, rol, username, "se puede tocar?" -- dentro de la transaccion de quien llama
    rol-en-sedes.ts          el rol le sirve en alguna de esas sedes?
    duplicados.ts            nombre, identidad, telefono, correo, colegiacion, usuario: no se repiten
  roles/             core.rol + core.rol_permiso: lista, ficha, crear, guardar (rol y permisos en una transaccion)
  catalogo/          TODAS las listas para elegir: /catalogo/roles, /catalogo/sucursales, /catalogo/permisos (regla 3)
  pacientes/         core.paciente (apenas empezado)

  (cuando tenga pantalla de administrar nace sucursales/, con el mismo molde)
```

Cada modulo de negocio tiene la misma forma:

```
x/
  x.module.ts          lo registra: controllers y providers
  x.controller.ts      las rutas de /x (administrar)
  x.service.ts         el UNICO codigo que le habla a las tablas de x
  tipos.ts             lo que devuelve: las formas que el front espeja en Interfaces/
  dto/                 lo que recibe: crear-x.dto.ts, actualizar-x.dto.ts (class-validator)
```

## Las reglas

**1. Un modulo por area, y la ruta es del modulo.** `@Controller('sucursales')`
solo puede existir en `sucursales/`. Nadie mas declara una ruta con ese nombre.
Un modulo es dueno de sus rutas, su servicio, sus DTOs y sus tipos.

**2. Lo que un modulo necesita de otro, lo pide; no lo duplica.** El formulario
de empleados necesita sedes y roles: el front se las pide al catalogo. Leer
tablas ajenas *para validar dentro de una transaccion* esta bien (guardar un
empleado comprueba que la sede exista y que el rol le sirva ahi). Lo que no se
hace es escribir en tablas ajenas ni exponer rutas ajenas.

**3. `/catalogo/<cosa>`: las listas para elegir, todas en `catalogo/`.** Es una
capa de LECTURA que mira tablas de varios modulos, y esta bien: no escribe en
ninguna. Algo es catalogo solo si cumple TODO esto:

  1. Sirve para elegir o para mostrar el nombre de algo: llenar un select, unas
     casillas, un buscador de "elegi uno", o traducir un id a su nombre.
  2. Solo lectura. Nunca escribe, nunca decide una regla de negocio.
  3. Trae lo minimo para elegir bien: `id`, `nombre`, y algun campo mas solo si
     sin el se elige mal (el codigo de la sede; de que modulos son los permisos
     de un rol). Nada de contadores, fechas, quien lo creo, ni lo que muestra la
     pantalla de administrar.
  4. Solo lo vigente: `WHERE activo` siempre. Lo dado de baja no se elige. Si una
     ficha vieja apunta a algo dado de baja, la ficha lo muestra por su nombre
     igual: el nombre viene con la ficha, no con el catalogo.
  5. El alcance lo pone la SESION, nunca el front. Siempre la empresa de la sesion
     (RLS, como todo). Y la sede de la sesion (`core.sucursal_actual()`) cuando la
     cosa es de la sede. Cada catalogo declara su alcance:
       - `empresa`: roles (son de la empresa); sucursales (se elige entre todas las
         abiertas: el formulario de empleados asigna varias).
       - `sede`: lo que se configura por sede: modulos encendidos aqui, examenes
         que se ofrecen aqui, precios de aqui.
     El front nunca manda un id de sede ni de empresa para pedir un catalogo.
  6. Permiso: sesion vigente. Las filas las decide la base.

  Lo que NO es catalogo: la lista de la pantalla de administrar (con inactivos,
  busqueda, paginado, contadores) -> `GET /<cosa>` del modulo dueno, con su
  permiso. Cualquier cosa que escriba. Cualquier lista que dependa de una regla
  ("que roles puedo asignar yo" se calcula en el front con el catalogo y la
  sesion).

  Los catalogos que hay: `roles` (empresa, solo activos), `sucursales` (empresa,
  solo abiertas), `permisos` (empresa: los de los modulos contratados, por modulo,
  con su nivel). En el front, `CatalogoService` tiene un metodo por lista y
  `Interfaces/catalogo.interface.ts` sus formas.

**4. Los tipos van en `tipos.ts`, no en el servicio.** Es el contrato con el
front: `Interfaces/<cosa>.interface.ts` tiene los mismos nombres y campos.
Cuando cambia lo que devuelve una ruta, se cambian los dos.

**5. `comun/` es solo lo que no es de nadie.** Si algo lo usa un solo modulo,
vive en ese modulo (por eso `cuenta.ts` y `rol-en-sedes.ts` estan en
`empleados/`). Sube a `comun/` el dia que lo use un segundo modulo (asi subio
`permiso.ts`: lo usan empleados y roles).

**6. La regla vive en la base; el API la explica.** Permisos, quien toca que
cuenta, unicidad, estados: todo eso lo hacen cumplir las funciones SECURITY
DEFINER, las politicas RLS y los indices de Postgres. El API pregunta antes
para contestar un 403 o un 409 con un mensaje que se entienda y con todos los
choques de una vez, pero si alguien escribe manana una ruta y se olvida, la base
lo rechaza igual. Cada funcion de la base lo dice en su propio comentario.

**7. Todo lo que se guarda junto va en UNA transaccion.** Empleado + cuenta +
sedes + codigo; rol + permisos: o queda todo o no queda nada. `prisma.conSesion()`
abre la transaccion y pone la sesion; adentro se hace todo; lo que revento la
deshace.

**9. Quien edita que rol, y el agujero que cierra.** Un rol con `usuario.administrar`
edita roles. Si pudiera editar cualquier rol -- o el suyo -- se daria a si mismo
lo que quisiera. Por eso `plataforma.permiso.nivel` y `core.rol_para_editar()`:

  - `propietario` (`usuario.nombrar_admin`): no se le pone a ningun rol.
  - `admin` (`usuario.administrar`, `sucursal.administrar`): lo pone solo el
    propietario, y un rol que tenga alguno es "de administrador": lo edita, lo
    asigna y lo desactiva solo el propietario.
  - nadie edita el rol que tiene puesto; los fijos (`es_fijo`: Propietario y
    Administrador, los entrego el operador) no se editan desde el LIS.
  - un rol no se desactiva mientras alguien lo tenga (55006 -> 409).

  El API lo repite en los mensajes y el front lo pinta en gris, pero la regla
  esta en la base: sin `usuario.nombrar_admin` no hay forma de volverse
  administrador, venga la peticion de donde venga.

**8. Nombres.** Rutas: sustantivo plural en espanol (`/empleados`, `/sucursales`,
`/catalogo/roles`). Clases: `CrearXDto`, `ActualizarXDto`, tipos `XDeLista`,
`XDeCatalogo`, `XGuardado`. Archivos en minusculas con guion. Sin acentos ni
enies en el codigo (tampoco en los .sql: la consola de Windows los rompe).

## Como se agrega un catalogo nuevo (ej. examenes)

1. `catalogo/tipos.ts`: `ExamenDeCatalogo` con lo minimo para elegir.
2. `catalogo/catalogo.service.ts`: `examenes(sesion)`, con su alcance en el
   comentario (`sede`, si son los que se ofrecen en esta sede) y `WHERE activo`.
3. `catalogo/catalogo.controller.ts`: `@Get('examenes')`.
4. En el front: `ExamenDeCatalogo` en `Interfaces/catalogo.interface.ts` y
   `examenes()` en `CatalogoService`.

## Como se agrega un modulo nuevo (ej. sucursales, cuando tenga pantalla)

`roles/` es el ejemplo mas chico y completo: `tipos.ts` (`RolDeLista`,
`RolCompleto`), `dto/`, un servicio que solo llama funciones de la base, y el
front espejo en `Interfaces/rol.interface.ts` + `Servicios/roles.service.ts` +
`Componentes/roles/{lista,formulario,detalle}`.

1. `src/sucursales/` con `sucursales.module.ts`, `sucursales.service.ts`, `tipos.ts`.
2. `sucursales.controller.ts` -> `@Controller('sucursales')` + `dto/`, con su permiso.
3. Registrarlo en `app.module.ts`.
4. En el front: `Interfaces/sucursal.interface.ts` (espejo de `tipos.ts`) y
   `Servicios/sucursales.service.ts`. El catalogo sigue siendo `catalogo.sucursales()`.
