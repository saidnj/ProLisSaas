# Cómo se entra

Qué pasa desde que alguien escribe su usuario y su clave hasta que ve datos en
pantalla, y por qué esos datos son los suyos y no los de otro laboratorio.

Este flujo atraviesa las tres capas —Angular, NestJS y PostgreSQL— y es el único
donde las tres tienen algo que decir sobre lo mismo. También es donde se ve por qué
el aislamiento no depende de que nadie se equivoque.

---

## 1. Qué dispara este flujo

Una persona abre la aplicación y no tiene sesión: es la primera vez del día, se le
venció la anterior, o la cerró a propósito.

Delante de la pantalla hay un usuario del laboratorio: recepción, un técnico, el
bioquímico, el administrador. **Nunca el operador de la plataforma** — ese entra
por otro lado, con otra credencial y sobre el esquema `comercial` (`E-19`), y ese
flujo no existe todavía (`H-16`).

---

## 2. Antes de empezar

Tiene que existir:

- La empresa, con `nivel_acceso` distinto de `bloqueado` y sin `fecha_cierre` vencida. **No se mira el estado**, se mira el nivel (`F7-10`).
- El empleado, en `core.empleado`.
- El usuario, en `core.usuario`, con `estado = 'activo'` y un `password_hash` de
  verdad. **Hoy los usuarios nacen con el texto `SIN_CLAVE_PENDIENTE_ACTIVACION`**,
  que no es el hash de nada: no existe el alta de clave (`H-17`). Para las pruebas,
  `08_login.sql` les pone una clave real.
- Al menos una fila en `core.acceso_sucursal`, o el usuario entra sin poder elegir
  dónde trabaja.
- Del lado técnico: `JWT_SECRETO` en el `.env` del API, y el rol `lis_api` creado
  en la base.

---

## 3. El camino normal

### 3.1 Los pasos

**1 · La pantalla manda las credenciales.**

```
POST /auth/login    { username, password }
```

Es la **única ruta abierta** del API. El guard está puesto de forma global, así que
todo pide token salvo lo marcado con `@Publico()` — y eso es a propósito: al revés,
protegiendo ruta por ruta, el día que alguien olvide el decorador queda un endpoint
abierto y nadie se entera. Así, olvidarse significa quedar cerrado de más, que se
nota en el acto.

> **REGLA** — `F7-1` · **El guard es global y las excepciones se declaran.** Una ruta
> nueva nace protegida. Abrirla es un acto explícito, escrito con `@Publico()`.

**2 · El API busca la credencial, y aquí hay un huevo y una gallina.**

Al entrar todavía no se sabe de qué empresa es quien escribe, así que no hay
contexto que poner — y sin contexto, RLS le tapa `core.usuario` entera a `lis_app`:
una consulta normal devuelve cero filas y no hay de dónde sacar el `empresa_id`.

Por eso existe `core.buscar_credencial()`, `SECURITY DEFINER`: corre con los
privilegios de su dueño y se salta RLS. Es una grieta hecha a propósito, y por eso
está acotada — devuelve una sola fila, no acepta filtros libres, tiene el
`search_path` fijo y solo `lis_app` la puede ejecutar.

> **REGLA** — `F7-2` · **`core.buscar_credencial()` es el único punto donde se lee
> `core.usuario` sin sesión puesta.** Cualquier otra lectura sin contexto devuelve
> cero filas, y así tiene que seguir.

**3 · Se verifica la clave, en la aplicación y nunca en SQL.**

```typescript
const buena = await argon2.verify(cred.password_hash, dto.password);
```

Compararla en SQL la deja escrita en el registro de consultas de PostgreSQL y abre
la puerta a medir por tiempo de respuesta. El hash sale de la base; la comparación
ocurre en Node.

**4 · Se decide, y todos los rechazos dicen lo mismo.**

En orden: nivel de acceso de la empresa, fecha de cierre, estado del usuario, y por
último la clave. Pero el mensaje que sale para «no existe ese usuario» y para «la clave está
mal» es **idéntico**.

> **REGLA** — `F7-3` · **Usuario inexistente y clave equivocada dan la misma
> respuesta.** Distinguirlos le regala a un atacante una lista de usuarios válidos:
> prueba nombres y mira cuál contesta distinto.

**5 · Se firma el token.** Aquí el `empresa_id` que salió de la **base** queda
sellado. De ahora en adelante viaja dentro del token y nadie lo puede cambiar sin
romper la firma.

**6 · Se arma lo que la pantalla necesita**, ya con sesión puesta y RLS activo: las
sucursales donde el usuario puede entrar y sus permisos efectivos. Se actualiza
`ultimo_acceso_en` y se pone `intentos_fallidos` en cero.

**7 · El front guarda la sesión** y a partir de ahí el `tokenInterceptor` le pega la
cabecera a cada petición.

### 3.2 Qué es el token, en concreto

Tres partes separadas por puntos, y las dos primeras son **base64, no cifrado**:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9 . eyJzdWIiOiIxIiwiZW1wIjoiMSIs... . CJqOwJnu3u8BFr6n...
└────────── cabecera ──────────────┘   └────────── contenido ──────┘   └───── firma ─────┘

cabecera   {"alg":"HS256","typ":"JWT"}
contenido  {"sub":"1","emp":"1","usr":"carla.nunez","rol":"Recepcion","exp":1789707504}
```

**Cualquiera lo puede leer.** Eso no es un fallo: es el diseño. Lo que no se puede
es **cambiarlo**, porque la firma se calcula con el contenido más un secreto que
solo tiene el servidor. Comprobado: cambiar `emp` de `1` a `2` dejando la firma
vieja da `JsonWebTokenError: invalid signature`.

De ahí sale la regla que sostiene todo el aislamiento:

> **REGLA** — `F7-4` · **El `empresa_id` sale del token verificado, nunca del cuerpo
> de la petición ni de un parámetro de la URL.** Si el API aceptara un
> `?empresaId=2`, cualquiera lo cambia en la barra del navegador y RLS lo dejaría
> pasar tan tranquilo — porque RLS obedece el contexto que le pongan. RLS protege
> contra el `WHERE` olvidado, no contra un API que le cree al navegador.

Y su consecuencia inmediata:

> **REGLA** — `F7-5` · **En el token no va nada secreto.** Va quién sos, no tu clave
> ni ningún dato clínico. Si alguien lo lee, aprende que Carla es recepcionista de
> la empresa 1 — que ya lo sabía, porque es ella.

**El back no lo almacena.** Ni una tabla, ni Redis, ni un archivo. Firma y olvida;
cuando llega una petición, **recalcula** la firma y compara. Es un sello de lacre:
no hace falta un registro de qué cartas sellaste, mirás el sello y sabés si es tuyo.

### 3.3 Las tres paredes

Una petición cualquiera, ya con token, choca con tres controles distintos. Cada uno
contesta una pregunta que los otros no saben contestar:

| | Pregunta | Dónde vive | Cómo falla |
|---|---|---|---|
| **1 · RLS** | ¿De qué empresa son estas filas? | política de cada tabla | silencio: cero filas |
| **2 · Permiso** | ¿Este rol puede hacer esta acción? | `core.usuario_puede()` | error, el que llama decide |
| **3 · Sesión** | ¿Esta sesión todavía vale? | `core.sesion_vigente()` | error `28000` con mensaje |
| **3b · Nivel** | ¿Y hasta dónde llega el acceso de la empresa? | `core.puede_crear()`, `core.puede_modificar()` | error `42501` con mensaje |

La tercera pared son en realidad tres funciones, porque **el acceso de una
empresa no es un sí o un no**:

| `nivel_acceso` | SELECT | INSERT | UPDATE | lo que promete el enumerado |
|---|---|---|---|---|
| `completo` | sí | sí | sí | todo lo que el producto ofrece |
| `solo_cierre` | sí | **no** | sí | terminar lo abierto; nada nuevo |
| `solo_lectura` | sí | **no** | **no** | consultar y exportar; nada más |
| `bloqueado` | **no** | **no** | **no** | no se entra |

Medido, no supuesto: esa tabla es la salida de la prueba, y coincide línea por
línea con lo que el enumerado prometía desde el principio.

**Y una decisión que vale explicar: estas funciones miran `nivel_acceso`, nunca
`estado`.** Son dos cosas distintas que estaban confundidas — `estado_empresa`
(`prueba`, `activa`, `suspendida`, `cancelada`, `cerrada`) es el **hecho
comercial**, el porqué; `nivel_acceso` es la **consecuencia**, el qué puede
hacer. El LIS no tiene por qué saber si un laboratorio está suspendido por mora
o cancelado por decisión propia: eso lo traduce el lado comercial a un nivel,
que es lo único que cruza la frontera (`E-18`). Leer `estado` aquí era duplicar
una decisión ya tomada, con una lista escrita a mano que se rompe cada vez que
nace un estado nuevo.

Las tres viven **en la base**. Ninguna depende de que el API se acuerde de
comprobar, y por eso alcanzan también a las consultas que nadie ha escrito todavía.

**Por qué la primera calla y la tercera grita.** No es inconsistencia, es la
distinción que las separa:

- «Esta fila es de otra empresa» es una condición **de fila**. Un error delataría
  que la fila existe. El silencio no filtra nada.
- «Tu sesión ya no vale» es una condición **de sesión**. No hay nada que filtrar —
  es sobre quien pregunta, y necesita enterarse.

> **REGLA** — `F7-6` · **Una condición de fila calla; una condición de sesión
> avisa.** El silencio es correcto cuando hablar delataría la existencia de algo.
> Cuando no hay nada que delatar, callar solo confunde.

### 3.4 Cómo se escriben las políticas

Cada tabla lleva **tres** políticas, no una — `FOR SELECT`, `FOR INSERT` y
`FOR UPDATE` — porque es la única forma de que `solo_cierre` y `solo_lectura`
signifiquen algo. Con una sola política `FOR ALL`, leer y escribir eran la
misma cosa y esos dos niveles eran palabras del enumerado que nadie hacía
cumplir:

```sql
FOR SELECT USING      (empresa_id = (SELECT core.empresa_actual())
                       AND (SELECT core.sesion_vigente()))

FOR INSERT WITH CHECK (empresa_id = (SELECT core.empresa_actual())
                       AND (SELECT core.sesion_vigente())
                       AND (SELECT core.puede_crear()))

FOR UPDATE USING      (empresa_id = (SELECT core.empresa_actual())
                       AND (SELECT core.sesion_vigente()))
           WITH CHECK (empresa_id = (SELECT core.empresa_actual())
                       AND (SELECT core.sesion_vigente())
                       AND (SELECT core.puede_modificar()))
```

**No hay `FOR DELETE`, y eso también es a propósito.** Sin política, `DELETE`
queda prohibido — y además está revocado. Dos candados sobre la misma puerta.

La única excepción a la tabla de niveles es `audit.evento`: su `INSERT` solo
pide sesión vigente, sin `puede_crear()`. Dejar constancia de lo que pasó no
puede depender de si el cliente está al día con su pago.

Y los paréntesis **no son estilo**:

Envuelta en `(SELECT ...)`, PostgreSQL evalúa la función como **InitPlan**: una vez
por consulta. Escrita suelta la trata como filtro **por fila** y la llama una vez
por cada una. Medido sobre 300.000 filas con 100.000 propias:

| Política | ms |
|---|---|
| `empresa_actual()` suelta | 51.4 |
| `(SELECT empresa_actual())` envuelta | 21.6 |
| envuelta **más** `(SELECT sesion_vigente())` | **21.6** |
| las dos sueltas | 894.7 |

La comprobación de sesión **sale gratis** si está envuelta, y es diecisiete veces
más lenta si no. El paréntesis es la diferencia entre que sea viable o imposible.

> **REGLA** — `F7-7` · **Toda función dentro de una política va envuelta en
> `(SELECT ...)`.** Sin eso se ejecuta una vez por fila.

`core.sesion_vigente()` es `SECURITY DEFINER` por una razón concreta: lee
`core.usuario` y `core.empresa`, que tienen RLS. Si corriera con los privilegios de
quien llama, la política de `core.usuario` la invocaría a ella, que leería
`core.usuario`, que aplicaría la política… hasta `stack depth limit exceeded`. Como
`DEFINER` se salta RLS al leer, y el ciclo no arranca.

### 3.5 El recorrido completo de una petición posterior

```
[NAVEGADOR]  pacientes.component
                ↓
             ApiService.get<Paciente[]>('pacientes')
                ↓
             token.interceptor.ts    Authorization: Bearer eyJ...
                ↓
════════════════ la red ════════════════
                ↓
[NEST]       jwt.guard.ts            verifyAsync()  → si la firma no cuadra, 401
                └ req.sesion = { usuarioId, empresaId, ... }   NACE LA SESIÓN
                ↓
             pacientes.controller.ts   @SesionActual() sesion
                ↓
             pacientes.service.ts      prisma.conSesion(sesion, ...)
                ↓
             prisma.service.ts    BEGIN
                                  SET LOCAL ROLE lis_app
                                  set_config('lis.empresa_id', '1', true)
                                  SELECT ... FROM core.paciente      ← sin WHERE
                ↓
════════════════ PostgreSQL ════════════════
             rls_paciente agrega, invisible:
               WHERE empresa_id = (SELECT core.empresa_actual())
                 AND (SELECT core.sesion_vigente())
                                  COMMIT
                ↑  solo los de Laboratorio Ochoa
```

**El `empresa_id` hace todo el camino sin que el navegador lo toque nunca.** Sale de
la base al firmar, viaja sellado, y vuelve a la base como contexto de RLS.

Y mirá lo que **no** hay en `pacientes.service.ts`: ningún `where: { empresa_id }`.
Ese es el premio. En toda la aplicación no se escribe `empresa_id` una sola vez, y
aun así es imposible que una empresa vea a otra.

> **REGLA** — `F7-8` · **La sesión no se usa para filtrar: se usa para poner el
> contexto.** El filtro lo agrega PostgreSQL. Un servicio que escriba
> `where empresa_id` está haciendo a mano lo que la base ya garantiza, y el día que
> se olvide nadie lo va a notar.

---

## 4. Los desvíos

**La clave está mal.** Sube `intentos_fallidos` y al llegar a cinco el usuario queda
`bloqueado`. El mensaje es el mismo que para un usuario inexistente (`F7-3`). El
tope está escrito a mano en el código, no en ninguna tabla de configuración.

**El usuario está `suspendido` o `bloqueado`.** No entra, y aquí sí el mensaje es
específico: es información que necesita para saber a quién pedirle ayuda.

**La empresa no está activa.** Tampoco entra, con `HINT = contactar al operador`.

**El mismo username existe en dos empresas.** `core.buscar_credencial()` **lanza** en
vez de elegir una:

```
El usuario carla.nunez existe en 2 empresas: hace falta decir en cual entra (H-101)
```

El índice único es `(empresa_id, lower(username))`: el username es único **dentro**
de la empresa, no en el sistema. Mientras no se decida cómo se sabe la empresa antes
de entrar, `LoginDto.empresaId` es opcional y solo se usa para desempatar.

> **REGLA** — `F7-9` · **Ante dos credenciales posibles, el sistema no elige:
> falla.** Adivinar significaría meter a alguien en la empresa equivocada.

**La sesión se revoca mientras está abierta.** El administrador desactiva a alguien
que ya entró. El token sigue firmado y válido —no se puede revocar—, pero la
siguiente consulta choca con `core.sesion_vigente()`:

```
ERROR:  28000: Sesion caducada: el usuario esta suspendido
HINT:   volver a entrar
```

El `ErroresBaseFilter` lo convierte en un 401, el `errorInterceptor` de Angular ve
el 401, cierra la sesión y manda al login. La cadena completa, desde un `UPDATE` del
administrador hasta la pantalla de la recepcionista.

**Con una salvedad medida**: la política solo se evalúa si la tabla tiene al menos
una fila que filtrar. Sobre una tabla vacía, el usuario desactivado recibe cero
filas en silencio en vez del mensaje. **La garantía no cambia** —nunca ve datos—;
lo que no está garantizado es que siempre se entere por qué.

---

## 5. Qué queda en la base al terminar

Un login correcto toca **una sola fila**:

| Tabla | Columna | Qué queda |
|---|---|---|
| `core.usuario` | `ultimo_acceso_en` | `now()` |
| `core.usuario` | `intentos_fallidos` | `0` |

Un login fallido toca la misma fila: sube `intentos_fallidos` y, al llegar al tope,
cambia `estado` a `bloqueado`.

**Y no queda nada más.** No hay tabla de sesiones, no hay registro de tokens
emitidos, y **`audit.evento` no registra ni la entrada ni el intento fallido**. Eso
es un hueco: hoy no se puede contestar «¿quién entró a esta empresa y cuándo?» más
allá del último acceso, que se sobrescribe.

---

## 6. Qué puede fallar

- `H-17` — No existe el alta de clave. Los usuarios nacen con un texto que no es un
  hash y el estado `pendiente_activacion` no existe en el enumerado. **Hoy nadie
  puede entrar sin que alguien le ponga la clave a mano.**
- `H-101` — El username es único por empresa, no en el sistema. Falta decidir cómo
  se sabe la empresa antes de entrar: subdominio, código de empresa, o correo único.
- `H-103` — El token no se puede revocar. Resuelto desde la base con
  `core.sesion_vigente()`, pero el token en sí sigue siendo válido: si alguna vez se
  filtrara, el único freno es cambiar `JWT_SECRETO`, que echa a todo el mundo.
- `H-104` — Las políticas estaban sin envolver y costaban 2.4× de más. Arreglado, y
  con el efecto secundario del silencio sobre tablas vacías.
- `H-100` — De los cinco niveles de comprobación, `core.acceso_sucursal` y
  `core.sucursal.activo` siguen sin leerse. Un usuario con **cero** accesos opera en
  cualquier sede de su empresa. El nivel de la empresa, sus cuatro grados y su
  fecha de cierre **ya se comprueban**: `sesion_vigente()`, `puede_crear()` y
  `puede_modificar()`. `E-20` dejó de ser una regla sin mecanismo.
- **El tope de intentos está escrito a mano** en `auth.service.ts`, no en
  configuración.
- **Ni el intento fallido ni el bloqueo escriben en `audit.evento`.**
- **El token vive en `localStorage`**, legible por cualquier JavaScript de la página.
  La alternativa —cookie `httpOnly`— lo esconde del JavaScript pero trae CSRF y
  exige HTTPS. Sin decidir.

---

## 7. Reglas que este flujo hace cumplir

- `E-19` — Las dos administraciones no se mezclan: este flujo es solo para usuarios
  del laboratorio.
- `E-20` — El nivel de acceso de la empresa se comprueba antes que el permiso del
  usuario. **Ahora sí tiene mecanismo**: `core.sesion_vigente()` mira el estado y la
  fecha de cierre.
- `F7-1` — El guard es global; las excepciones se declaran.
- `F7-2` — `core.buscar_credencial()` es el único punto donde se lee `core.usuario`
  sin sesión.
- `F7-3` — Usuario inexistente y clave equivocada dan la misma respuesta.
- `F7-4` — El `empresa_id` sale del token verificado, nunca de la petición.
- `F7-5` — En el token no va nada secreto.
- `F7-6` — Una condición de fila calla; una condición de sesión avisa.
- `F7-7` — Toda función dentro de una política va envuelta en `(SELECT ...)`.
- `F7-8` — La sesión pone el contexto, no filtra.
- `F7-9` — Ante dos credenciales posibles, el sistema falla en vez de elegir.
- `F7-10` — **El LIS lee `nivel_acceso`, nunca `estado`.** El estado es el hecho
  comercial y su interpretación vive del otro lado de la frontera (`E-18`).
- `F7-11` — **Leer, crear y modificar son tres permisos distintos, y el nivel de
  la empresa los reparte.** Por eso cada tabla lleva tres políticas.

---

## 8. Preguntas abiertas

- **¿Cómo se sabe la empresa antes de entrar?** (`H-101`) Subdominio por empresa,
  código escrito en la pantalla, correo único, o username único en el sistema. Cada
  una cambia el índice, la pantalla y el despliegue.
- **¿Dónde vive el token?** `localStorage` o cookie `httpOnly`. Para datos clínicos
  la cookie es el destino razonable; cuesta CSRF, HTTPS obligatorio y cuatro
  archivos.
- **¿Cuánto dura la sesión?** Hoy ocho horas, elegido sin criterio. Un laboratorio
  con turnos de doce horas necesitaría otra cosa.
- **¿Se registra la entrada en `audit.evento`?** Hoy no. Para datos clínicos suele
  ser obligatorio saber quién entró y cuándo.
- **¿Cómo se elige la sucursal al entrar?** El login devuelve la lista, pero nada
  decide cuál se usa, y `lis.sucursal_id` no existe en el contexto (`H-100`).
- **¿Qué pasa con las sesiones abiertas cuando el operador suspende una empresa?**
  (`H-3`) **Resuelto, y lo resolvió el enumerado que ya existía**: depende del
  `nivel_acceso` que el lado comercial le asigne. Con `solo_lectura` el
  laboratorio sigue consultando y exportando pero no escribe; con `solo_cierre`
  puede además terminar lo que tenía abierto; con `bloqueado` no entra. Lo que
  queda por decidir no es el mecanismo sino **qué nivel corresponde a cada
  motivo** — y eso es `H-13`, del lado comercial.

---

## 9. Dónde vive en el código

**Base de datos**

| Qué | Dónde |
|---|---|
| `core.empresa_actual()`, `core.usuario_actual()` | `04_funciones.sql` |
| `core.sesion_vigente()` — puede entrar | `04_funciones.sql` |
| `core.nivel_actual()`, `puede_crear()`, `puede_modificar()` | `04_funciones.sql` |
| `core.crear_usuario()` y las cuatro de activación | `04_funciones.sql` |
| `core.usuario_puede()`, `core.usuario_puede_en()` | `04_funciones.sql` |
| `core.buscar_credencial()` | `08_login.sql` — **pendiente de mudar a `04`** |
| Las políticas (tres por tabla) y los privilegios de `lis_app` | `05_privilegios.sql` |
| Las ocho pruebas del estreno de contraseña | `93_pruebas_activacion.sql` |
| Clave real para los usuarios de prueba | `08_login.sql` |
| Demostración de RLS paso a paso | `96_demo_rls.sql` |
| Cinco peticiones contra datos reales | `97_peticiones_rls.sql` |

**API — `packages/api/src/`**

| Qué | Dónde |
|---|---|
| El tipo `Sesion` y la carga del token | `comun/sesion.ts` |
| `@SesionActual()` | `comun/sesion.decorador.ts` |
| `28000` → 401 | `comun/errores.filtro.ts` |
| `conSesion()` y `sinSesion()` | `prisma/prisma.service.ts` |
| El guard global | `auth/jwt.guard.ts` |
| `@Publico()` | `auth/publico.decorador.ts` |
| El login | `auth/auth.service.ts`, `auth.controller.ts` |
| CORS y el filtro global | `main.ts` |

**Front — `packages/web/src/`**

| Qué | Dónde |
|---|---|
| La URL del API por entorno | `environments/environment*.ts` |
| Dónde vive la sesión | `app/comun/sesion.service.ts` |
| La cabecera `Authorization` | `app/comun/token.interceptor.ts` |
| El 401 → login | `app/comun/error.interceptor.ts` |
| Los interceptores enchufados | `app/app.config.ts` |

**Lo que se pide crear**

- El alta de clave y el estado `pendiente_activacion` (`H-17`).
- El registro de la entrada en `audit.evento`.
- La elección de sucursal y `lis.sucursal_id` en el contexto (`H-100`).
- La consola del operador, con su propio flujo de entrada (`H-16`).
