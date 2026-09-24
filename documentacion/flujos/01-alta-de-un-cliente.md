# Alta de un cliente

De la firma del acuerdo al primer usuario que puede entrar. Toca empresa, sucursal,
correlativos, convenio, módulos, roles, empleado y usuario: por eso es un flujo
compartido y no vive dentro de un territorio.

## 1. Qué dispara este flujo

Un acuerdo comercial cerrado. Puede ser de tres clases y el sistema las distingue
porque cambian lo que pasa después:

| Motivo del alta | Qué significa | Estado inicial |
|---|---|---|
| `prueba` | Evaluación con fecha de vencimiento | `prueba` |
| `contrato` | Contrato firmado o pago recibido | `activa` |
| `migracion` | Viene de otro sistema y trae datos | `activa` |

**Quién está delante de la pantalla:** el operador de la plataforma. Nunca el
cliente, y nunca desde la aplicación del producto.

> **REGLA** — Ver `E-8` en `core/01-la-empresa.md`. El alta es un acto del operador.

## 2. Antes de empezar

Lo que el operador tiene que tener en la mano antes de abrir el formulario:

- Razón social y, si existe, el RTN.
- Nombre, dirección y teléfono de la primera sucursal. **La dirección y el teléfono
  no son opcionales**: van impresos en el encabezado de cada informe.
- Un código corto para la sucursal, de 2 a 6 caracteres en mayúscula. Va en los
  correlativos y en las etiquetas de los tubos, así que se decide una vez y no se
  cambia.
- Nombre, apellidos y **correo** de la persona que va a administrar el sistema.
- Qué módulos se contrataron.
- Si es prueba, hasta qué fecha.

> **RIESGO** — Si el correo del administrador está mal, el alta termina «bien» y
> nadie recibe nada. Conviene que el formulario lo pida dos veces, como cualquier
> campo que no se puede verificar en el momento.

## 3. El camino normal

### Paso 1 · Validar antes de tocar nada

El sistema comprueba, en este orden:

1. Que el RTN no exista ya en otra empresa, si viene.
2. Que el código de sucursal tenga el formato correcto.
3. Que el correo del administrador tenga forma de correo.
4. Que los módulos elegidos existan en el catálogo del producto.

Si algo falla, no se crea nada. Esto es una validación de formulario, no una
transacción a medias.

### Paso 2 · Crear todo, en una sola transacción

> **REGLA** — `F1-1` · El alta es **todo o nada**. Si cualquier paso falla, no
> queda ninguna fila. Una empresa a medias es peor que ninguna empresa: parece que
> existe y no funciona.

En una sola transacción se crea:

| # | Qué | Detalle |
|---|---|---|
| 1 | La empresa | Con el estado que corresponde al motivo del alta |
| 2 | La primera sucursal | Activa, con su código, dirección y teléfono |
| 3 | Los cinco correlativos | `expediente` por empresa; `episodio`, `orden`, `informe` y `muestra` por sucursal, con el código de sucursal como prefijo |
| 4 | El convenio `Particular` | Marcado como predeterminado. Sin él ninguna orden puede existir |
| 5 | Los módulos contratados | Una fila por módulo en esa sucursal |
| 6 | Los cuatro roles | Copiados de las plantillas, **con sus permisos** |
| 7 | La configuración del informe | Nombre, dirección y teléfono para el encabezado |
| 8 | El empleado administrador | Con nombre, apellidos y correo |
| 9 | El usuario administrador | Con el rol Administrador, **sin contraseña**, en estado `pendiente_activacion` |
| 10 | El acceso a la sucursal | El administrador puede operar en la sede que se creó |
| 11 | La fila del historial de estado | Motivo del alta y quién la creó |

### Paso 3 · Entregar el acceso

> **REGLA** — `F1-2` · El operador **nunca** conoce la contraseña del cliente. No
> se inventa una para dictarla por teléfono ni para mandarla por correo.

1. Se genera un enlace de activación de un solo uso, con vencimiento corto.
2. Se envía al correo del administrador.
3. El administrador entra por ese enlace y define su propia contraseña.
4. El usuario pasa de `pendiente_activacion` a `activo`.
5. El enlace queda usado y no sirve dos veces.

> **ABIERTO** — Cuánto dura el enlace. Setenta y dos horas parece razonable para
> alguien que quizá no revisa el correo el mismo día, pero es una decisión que
> conviene tomar a propósito y no por descuido.

> **ABIERTO** — Qué pasa si el enlace vence sin usarse. Lo natural es que el
> operador pueda reenviarlo, y que eso quede en el historial.

### Paso 4 · Verificar que quedó entregable

El operador ejecuta la comprobación de los ocho requisitos del umbral entregable
(ver `core/01-la-empresa.md`, «Quién la crea y con qué datos»). El sistema contesta con la lista de lo
que falta, si falta algo.

> **REGLA** — `F1-3` · El alta no se da por terminada hasta que la comprobación
> pasa. Si el sistema dice que falta algo, es que falta.

### Paso 5 · Acompañar hasta operable

Esto ya no es del operador solo: es la puesta en marcha con el cliente.

1. El administrador crea a sus empleados y les da usuarios.
2. El bioquímico configura áreas, tipos de muestra, analitos y pruebas.
3. **El bioquímico revisa los rangos de referencia.** No es opcional: los que trae
   el sistema son valores generales de adulto, no los del laboratorio.
4. Se registran los equipos y su mapeo de códigos.
5. Se hace una orden de prueba de punta a punta, con un paciente ficticio, y se
   anula al terminar.

> **RIESGO** — El paso 5 es el que más se salta y el que más problemas evita. Un
> laboratorio que descubre el primer día real que el analizador no está mapeado
> pierde la confianza en el sistema de inmediato.

### El alta a mano · lo que de verdad se ejecuta hoy

Todo lo de arriba describe el alta **cuando exista la consola del operador**.
Mientras no exista, el alta se hace escribiendo las filas a mano, y esta es la
secuencia exacta —comprobada contra PostgreSQL 18, con el laboratorio Ochoa como
primer caso—.

Son **diez pasos y el orden no es negociable**: cada uno necesita el anterior.

| # | Tabla | Por qué va aquí |
|---|---|---|
| 1 | `core.empresa` | Es la raíz. No depende de nada |
| 2 | `core.sucursal` | Necesita la empresa |
| 3 | `core.empleado` | La persona. Existe aunque nunca tenga cuenta |
| 4 | `core.rol` | El rol es de la empresa, no de la sede |
| 5 | `core.usuario` | Necesita **empleado y rol a la vez** |
| 6 | `core.acceso_sucursal` | En qué sede trabaja |
| 7 | `plataforma.modulo` | El catálogo del producto. **Lo escribe el operador** |
| 8 | `plataforma.modulo_sucursal` | Qué compró la sede. **También el operador** |
| 9 | `plataforma.permiso` + `core.rol_permiso` | El catálogo de permisos y qué le toca al rol |
| 10 | `core.convenio` + `core.correlativo` | Sin esto **no se puede abrir un episodio** |

#### 1 · La empresa

```sql
INSERT INTO core.empresa (nombre, nombre_comercial, rtn, estado, nivel_acceso)
VALUES ('Laboratorio Clinico Ochoa S. de R.L.', 'Laboratorio Ochoa',
        '08019016543210', 'activa', 'completo');
```

#### 2 · La sucursal

```sql
INSERT INTO core.sucursal (empresa_id, nombre, codigo, direccion, telefono)
SELECT e.empresa_id, 'Casa Matriz', 'CEN',
       'Col. Palmira, 2a calle, Edificio Ochoa, Tegucigalpa, Francisco Morazan',
       '2232-4455'
FROM core.empresa e
WHERE e.rtn = '08019016543210';
```

> **REGLA** — `F1-4` · **Cada paso se cuelga del anterior buscándolo por su llave
> natural, nunca por un id escrito a mano.** Si se escribe `empresa_id = 1` y
> alguien recarga la base, el 1 puede ser otra empresa y la fila queda colgada del
> padre equivocado — sin error y en silencio. El RTN es único: buscar por él no se
> puede equivocar.

#### 3 · El empleado administrador

```sql
INSERT INTO core.empleado
  (empresa_id, nombres, apellidos, documento, telefono, correo,
   cargo, numero_colegiacion)
SELECT e.empresa_id,
       'Marlon Alberto', 'Ochoa Discua', '0801198504321', '9988-7766',
       'marlon.ochoa@labochoa.hn',
       'Propietario y bioquimico responsable', 'CMQ-2841'
FROM core.empresa e
WHERE e.rtn = '08019016543210';
```

Lleva `numero_colegiacion` porque en un laboratorio chico el dueño es el
bioquímico: administra **y** firma. Sin ese número, `lab.validar_resultado()` lo
rechaza aunque tenga el permiso `resultado.validar` — *un permiso no convierte a
nadie en bioquímico*. Si el administrador fuera solo administrativo, la columna va
en nulo.

#### 4 · El rol

```sql
INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema)
SELECT e.empresa_id, 'Administrador',
       'Configura la empresa: usuarios, roles, sucursales, convenios y precios',
       true
FROM core.empresa e
WHERE e.rtn = '08019016543210';
```

#### 5 · El usuario

```sql
INSERT INTO core.usuario
  (empresa_id, empleado_id, rol_id, username, password_hash, estado)
SELECT em.empresa_id, em.empleado_id, r.rol_id,
       'marlon.ochoa', 'SIN_CLAVE_PENDIENTE_ACTIVACION', 'activo'
FROM core.empleado em
JOIN core.rol r ON r.empresa_id = em.empresa_id AND r.nombre = 'Administrador'
WHERE em.documento = '0801198504321';
```

> **RIESGO** — `password_hash` es `NOT NULL` y el estado `pendiente_activacion`
> **no existe** en `core.estado_usuario`: solo hay `activo`, `suspendido` y
> `bloqueado`. Por eso aquí va un texto que no es hash de nada —nadie puede entrar
> con él— y el usuario queda `activo` de mentira. Es `H-17`, y es lo que impide
> cerrar el Paso 3 de este flujo.

#### 6 · El acceso a la sede

```sql
INSERT INTO core.acceso_sucursal (usuario_id, sucursal_id, empresa_id)
SELECT u.usuario_id, s.sucursal_id, u.empresa_id
FROM core.usuario u
JOIN core.sucursal s ON s.empresa_id = u.empresa_id AND s.codigo = 'CEN'
WHERE u.username = 'marlon.ochoa';
```

`empresa_id` sale de `u.empresa_id` y el `JOIN` exige que la sede sea de esa misma
empresa. Así es imposible darle a un usuario acceso a la sucursal de otra.

> **ABIERTO** — Esta fila **no la lee nadie** (`H-31`). Un usuario con cero filas
> aquí opera igual en cualquier sede de su empresa. Y **no se puede quitar**
> (`H-30`): la tabla no tiene `activo` ni fecha de revocación, y `DELETE` está
> revocado. Hoy es una declaración de intención, no una puerta.

#### 7 y 8 · Los módulos · **esto es del operador**

```sql
INSERT INTO plataforma.modulo (modulo_id, nombre, descripcion) VALUES
  ('core',        'Nucleo',              'Pacientes, episodios, informes y entrega. No es opcional.'),
  ('lab_clinico', 'Laboratorio clinico', 'Ordenes, muestras, resultados y validacion.')
ON CONFLICT (modulo_id) DO NOTHING;

INSERT INTO plataforma.modulo_sucursal
  (sucursal_id, modulo_id, empresa_id, activo, asignado_por)
SELECT s.sucursal_id, m.modulo_id, s.empresa_id, true, 'operador'
FROM core.sucursal s
JOIN core.empresa  e ON e.empresa_id = s.empresa_id
CROSS JOIN (VALUES ('core'), ('lab_clinico')) AS m(modulo_id)
WHERE e.rtn = '08019016543210' AND s.codigo = 'CEN'
ON CONFLICT DO NOTHING;
```

> **REGLA** — `F1-5` · **`core` se enciende siempre, junto con lo que se haya
> vendido.** De los 30 permisos, 16 son del módulo `core`. Como `usuario_puede()`
> intersecta contra la licencia, si `core` no está encendido esos 16 se caen y la
> empresa nace sin poder hacer nada, ni siquiera administrarse. Es `H-27`, cerrado
> por `H-99`.

#### 9 · Los permisos del rol

El catálogo de permisos lo siembra `06_semillas.sql`. Con él cargado, este script
le da al administrador **todos los permisos de los módulos que la empresa tiene
encendidos**:

```sql
WITH parametros AS (
  SELECT '08019016543210'::text AS rtn, 'Administrador'::text AS rol
),
empresa AS (
  SELECT e.empresa_id, p.rol FROM core.empresa e, parametros p WHERE e.rtn = p.rtn
),
rol AS (
  SELECT r.rol_id, r.empresa_id FROM core.rol r
  JOIN empresa e ON r.empresa_id = e.empresa_id AND r.nombre = e.rol
),
contratados AS (
  SELECT DISTINCT ms.modulo_id
  FROM plataforma.modulo_sucursal ms
  JOIN empresa e ON e.empresa_id = ms.empresa_id
  WHERE ms.activo
)
INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
SELECT r.rol_id, pm.permiso_id, r.empresa_id
FROM rol r
CROSS JOIN plataforma.permiso pm
WHERE pm.modulo_id IN (SELECT modulo_id FROM contratados)
ON CONFLICT (rol_id, permiso_id) DO NOTHING;
```

Es **idempotente y reutilizable**: se cambia el RTN para otra empresa, o se vuelve
a correr cuando el operador venda un módulo nuevo y solo agrega lo que falta.

> **REGLA** — `F1-6` · **El rol Administrador se define por exclusión**: todo lo
> que exista en el catálogo, de los módulos contratados. Por eso no lleva una lista
> escrita a mano — una lista fija se olvidaría de actualizar el día que entre un
> módulo nuevo. Los otros tres roles sí van por lista, porque su gracia es que
> **no** tengan todo.

#### 10 · El convenio y los correlativos

```sql
-- Particular · el paciente paga en caja. OBLIGATORIO en toda empresa
INSERT INTO core.convenio
  (empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado, activo)
SELECT e.empresa_id, 'Particular', 'particular', 'particular', true, true
FROM core.empresa e WHERE e.rtn = '08019016543210';

-- los cinco correlativos
INSERT INTO core.correlativo (empresa_id, sucursal_id, tipo, prefijo, ancho)
SELECT s.empresa_id, c.sucursal_id, c.tipo::core.tipo_correlativo, c.prefijo, c.ancho
FROM core.sucursal s
JOIN core.empresa e ON e.empresa_id = s.empresa_id
CROSS JOIN LATERAL (VALUES
    (NULL::bigint,  'expediente', 'EXP-',           6),
    (s.sucursal_id, 'episodio',   s.codigo || '-',  6),
    (s.sucursal_id, 'informe',    s.codigo || 'I-', 6),
    (s.sucursal_id, 'orden',      s.codigo || 'O-', 6),
    (s.sucursal_id, 'muestra',    s.codigo || 'M-', 8)
  ) AS c(sucursal_id, tipo, prefijo, ancho)
WHERE e.rtn = '08019016543210' AND s.codigo = 'CEN';
```

Queda así:

```
    tipo    |      ambito       | prefijo |    proximo
 expediente | (toda la empresa) | EXP-    | EXP-000001
 episodio   | CEN               | CEN-    | CEN-000001
 informe    | CEN               | CENI-   | CENI-000001
 orden      | CEN               | CENO-   | CENO-000001
 muestra    | CEN               | CENM-   | CENM-00000001
```

**El expediente es de la empresa; los otros cuatro, de la sede.** `sucursal_id` en
nulo significa «toda la empresa», y es a propósito: el paciente es de la empresa
—el mismo señor se atiende hoy en una sede y mañana en otra con el mismo
`EXP-000123`—, mientras que el episodio ocurrió en un lugar concreto.

**La muestra lleva ancho 8** y los demás 6: son las que más volumen tienen —varios
tubos por orden— y ese número va impreso en el código de barras.

#### Lo que se comprobó

Sin el paso 10 el alta **no sirve**. Intentar abrir el primer episodio antes de
crear el convenio da:

```
ERROR: insert or update on table "episodio" violates foreign key
       constraint "fk_episodio_convenio"
DETAIL: Key (convenio_id, empresa_id)=(1, 1) is not present in table "convenio".
```

Por eso `E-6` dice que toda empresa nace con un convenio predeterminado: no es una
comodidad, es lo que permite que `core.episodio.convenio_id` sea `NOT NULL`.

#### Lo que esta secuencia NO resuelve

**Falta entera la parte del operador.** Esta secuencia la ejecuta alguien conectado
como `postgres`, a mano, contra la base. Eso significa que hoy:

- **No hay quién** — no existe la consola del operador, con su propia
  autenticación y su propio rol de base de datos (`H-16`).
- **No hay control** — `core.crear_empresa()` es `SECURITY DEFINER` y no comprueba
  ningún permiso: cualquiera que pueda ejecutarla crea empresas (`H-1`).
- **No hay rastro** — ninguna de estas diez filas deja un `audit.evento`. No queda
  registrado quién dio de alta la empresa ni cuándo.
- **No hay cliente** — no se crearon `comercial.cliente`, `contacto` ni
  `cliente_empresa`. La empresa nace **sin cliente vigente**, que es el estado que
  `E-21` da por imposible, y sin poder facturarle (`H-82`).
- **No hay contrato** — nada conecta `comercial.contrato` con
  `plataforma.modulo_sucursal`: el operador enciende módulos y no queda registro de
  qué se vendió.

> **PENDIENTE** — La parte del operador. Es lo único que falta para que este flujo
> deje de ser una lista de `INSERT` y pase a ser una operación del sistema.

## 4. Los desvíos

### El cliente ya trae datos de otro sistema

El motivo del alta es `migracion`. Cambia el paso 5: antes de que entre el primer
paciente real, hay que cargar el histórico.

> **PENDIENTE** — El flujo de migración completo: qué se puede importar (pacientes,
> catálogo, resultados históricos), en qué formato, y qué pasa con los expedientes
> que ya tenían número en el sistema viejo. Es un documento propio.

### La empresa tiene varias sucursales desde el principio

El alta crea una. Las demás las crea el administrador después, y cada una necesita
sus propios correlativos y sus propios módulos activos. **Hoy eso no está
automatizado, y es la falla H-24**: la regla `S-2` del territorio de la sucursal
dice que una sede nace con sus cuatro correlativos o no nace, y
`core.crear_sucursal()` todavía no existe.

> **ABIERTO** — ¿Debería el alta aceptar varias sucursales de una vez? Para un
> cliente con tres sedes, crear dos a mano después es una fuente de olvidos.

### Es la segunda empresa del mismo edificio

El caso de la clínica y el laboratorio. Se dan de alta como dos empresas
independientes, y **después** se crea el acuerdo de asociación entre ellas. Ese es
otro flujo: `flujos/04-derivacion.md`.

### El administrador se va antes de activar su cuenta

El operador anula el enlace, cambia el correo del empleado y genera uno nuevo. El
usuario sigue siendo el mismo; lo que cambia es a quién se le entrega.

## 5. Qué queda en la base al terminar

Para una empresa nueva con una sucursal y el módulo de laboratorio:

**Lo que hoy deja `core.crear_empresa()`** — contado ejecutándola, no de memoria:

```
core.empresa                 1 fila
core.sucursal                1 fila
core.correlativo             5 filas
core.convenio                1 fila  (Particular, predeterminado)
plataforma.modulo_sucursal   2 filas (core y lab_clinico)
core.rol                     4 filas
core.rol_permiso            64 filas (30 + 15 + 11 + 8)
```

**Lo que deja en cero, y debería crear:**

```
core.empleado                0    ← deberia ser 1 (el administrador)
core.usuario                 0    ← deberia ser 1
core.acceso_sucursal         0    ← deberia ser 1
audit.evento                 0    ← deberia ser 1 (empresa.crear)
```

Los 64 permisos se reparten así: **Administrador 30** —todos los del catálogo, por
exclusión—, Bioquímico 15, Recepción 11, Analista 8.

Tres tablas que este documento mencionaba **no existen**:
`core.empresa_configuracion` sigue siendo una propuesta,
`core.empresa_estado_historial` se fue al esquema comercial como
`comercial.relacion_evento`, y el estado `pendiente_activacion` no está en el
enum.

Cero pacientes, cero episodios, cero pruebas en el catálogo. Eso es correcto: el
umbral entregable no incluye el catálogo clínico, porque lo define el bioquímico y
no el operador.

## 6. Qué puede fallar

| Qué pasa | Qué ve el operador | Qué hace |
|---|---|---|
| El RTN ya existe en otra empresa | «Ese RTN ya está registrado en *nombre*» | Verificar si es la misma empresa dándose de alta dos veces |
| El código de sucursal tiene formato inválido | «El código son 2 a 6 letras o números en mayúscula» | Corregirlo |
| El correo no tiene forma válida | «Revisa el correo del administrador» | Corregirlo |
| Falla a mitad de la transacción | «No se pudo crear la empresa» y nada queda creado | Reintentar; si persiste, es un error del sistema |
| El correo de activación no llega | Nada, y ese es el problema | El operador puede reenviar el enlace desde la ficha |
| La comprobación del paso 4 falla | La lista de lo que falta | Completarlo antes de entregar |

> **RIESGO** — Hoy `core.crear_empresa()` hace los pasos 1 a 6 y **no hace el 7,
> el 8, el 9, el 10 ni el 11**. Comprobado ejecutándola: deja cero empleados, cero
> usuarios, cero accesos y cero eventos de auditoría. La empresa nace con cuatro
> roles llenos de permisos y **nadie que pueda entrar**. *(H-2)*

> **RIESGO** — `core.crear_empresa()` es `SECURITY DEFINER` y no comprueba
> permisos. Mientras no exista una consola de operador con su propia
> autenticación, esa función no puede quedar expuesta en la API del producto.
> *(H-1)*

## 7. Reglas que este flujo hace cumplir

- `E-6` — Toda empresa tiene al menos una sucursal y un convenio predeterminado.
- `E-8` — Solo el operador crea empresas.
- `E-9` — No se entrega una empresa que no se pueda usar.
- `E-10` — El sistema sabe en qué umbral está cada empresa.
- `S-1` — La primera sucursal la crea el operador dentro del alta
  (`core/02-la-sucursal.md`).
- `S-2` — Una sucursal nace con sus correlativos o no nace.
- `F1-1` — El alta es todo o nada.
- `F1-2` — El operador nunca conoce la contraseña del cliente.
- `F1-3` — El alta no termina hasta que la comprobación pasa.
- `F1-4` — Cada fila se cuelga de la anterior por su llave natural, nunca por un
  id escrito a mano.
- `F1-5` — El módulo `core` se enciende siempre, junto con lo que se haya vendido.
- `F1-6` — El rol Administrador se define por exclusión: todo el catálogo de los
  módulos contratados.

## 8. Preguntas abiertas

1. ¿Cuánto dura el enlace de activación y qué pasa si vence?
2. ¿El alta debería aceptar varias sucursales de una vez?
3. ¿Qué incluye exactamente la migración desde otro sistema?
4. ¿Quién hace la puesta en marcha del paso 5: tú, o el cliente con un instructivo?
   La respuesta cambia cuánto tiene que guiar el sistema.
5. ¿Se le cobra al cliente la puesta en marcha? Si sí, conviene que el sistema
   registre cuándo terminó.
6. **¿Por dónde ejecuta el operador todo esto?** Es la pregunta que bloquea el
   flujo entero: hoy la secuencia se corre a mano conectado como `postgres`. Sin
   una consola con autenticación propia no hay quién, no hay control y no hay
   rastro (`H-16`, `H-1`).
7. ¿El alta crea también `comercial.cliente`, `contacto` y `cliente_empresa`? Hoy
   no lo hace, y la empresa nace sin cliente vigente (`H-82`).

## 9. Dónde vive en el código

### Lo que ya existe

| Qué | Dónde |
|---|---|
| Pasos 1 a 6 del alta | `core.crear_empresa()` — `04_funciones.sql` |
| Los cuatro roles y sus 64 permisos | Dentro de `core.crear_empresa()`. Ya no hay tablas de plantilla |
| El catálogo de módulos y los 30 permisos | `06_semillas.sql` |
| La secuencia a mano, paso a paso | La sección «El alta a mano» de este documento |

### Lo que este flujo pide crear

| Qué | Para qué |
|---|---|
| **Consola de operador** | **Lo que bloquea el flujo entero.** Sin ella todo esto se corre a mano como `postgres` |
| Extender `core.crear_empresa()` | Que haga también los pasos 7 a 11 |
| `core.empresa_configuracion` | El encabezado del informe |
| Estado `pendiente_activacion` en `core.estado_usuario` | Un usuario que existe y todavía no puede entrar |
| `core.activacion_usuario` | El enlace de un solo uso, con vencimiento y uso registrado |
| `core.empresa_lista_para()` | La comprobación del paso 4 |
| El evento `empresa.crear` en `audit.evento` | Hoy el alta no deja ningún rastro |
| El alta de `comercial.cliente` | Que la empresa nazca con cliente vigente (`E-21`, `H-82`) |
| Unir `comercial.contrato` con `plataforma.modulo_sucursal` | Que quede registro de qué módulos se vendieron |
