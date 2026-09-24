# La sucursal

El lugar físico donde se atiende. Casi todo lo operativo cuelga de una sucursal y no de la empresa: los precios, los correlativos, los equipos, los accesos.

> Documento completo. Once secciones, según la plantilla.

## 1. Qué es y por qué existe

Una sucursal es **una dirección donde hay gente atendiendo**. Es la unidad más
pequeña que puede recibir a un paciente, tomarle una muestra y entregarle un
informe con un número propio.

La empresa contesta *de quién es esto*; la sucursal contesta *dónde ocurrió
esto*. Son preguntas distintas y por eso son tablas distintas: el laboratorio
Ochoa es una empresa, pero el hemograma que se hizo en la sede del centro y el
que se hizo en la sede de la colonia salieron de dos lugares con dirección,
teléfono, equipos y numeración diferentes.

**Qué problema resuelve.** Sin ella, todo lo que en la vida real varía por sede
tendría que vivir en la empresa y valer para todas a la vez:

- El **encabezado del informe**. El paciente que se atendió en la colonia tiene
  que ver esa dirección y ese teléfono, no los de la sede central.
- La **numeración**. Dos recepciones atendiendo a la vez no pueden emitir el
  mismo número de orden, y el número tiene que decir de dónde salió.
- Los **equipos**. El Hemax 53 está físicamente en una sala. Un resultado sabe
  de qué máquina salió, y esa máquina está en un lugar.
- Los **precios**. Una sede dentro de una clínica privada puede cobrar distinto
  que una sede de barrio, con el mismo catálogo de pruebas.
- El **alcance de la gente**. Quién trabaja dónde.

**Qué pasaría si no existiera.** El sistema serviría para un laboratorio de un
solo local y se rompería el día que abriera el segundo — que es exactamente el
día en que el cliente crece y más necesita que el sistema no lo estorbe.

**Qué NO es.** No es una empresa pequeña. Una sucursal no tiene RTN, no firma
contratos, no tiene su propio estado de suscripción y no puede ver menos datos
que su empresa: el aislamiento es por empresa, no por sede. Tampoco es un área
de laboratorio: el área (hematología, química) es una división del trabajo
dentro de una sucursal y vive en la rama, no aquí.

**Dos palabras para lo mismo.** En este documento **sede** se usa como sinónimo
de **sucursal**, y **contador** como sinónimo de **correlativo**, porque así habla
el laboratorio. En la base solo existen los nombres `sucursal` y `correlativo`, y
son esos los que valen para cualquier identificador.

**El caso del primer cliente.** Hoy el laboratorio tiene **una sola sucursal**,
la que está dentro de la clínica. Todo este territorio existe con una sola fila.
Eso no lo hace opcional: es lo que hace que la segunda sede sea una tarde de
configuración y no una migración.

> **ABIERTO** — ¿La clínica que aloja al laboratorio cuenta como una sucursal de
> alguien? No. La clínica es **otra empresa** y llega por convenio o por
> derivación. Queda escrito aquí porque es la confusión más fácil de cometer al
> leer este territorio. No hace falta decidir nada: queda como aclaración.

---

## 2. Las tablas y sus campos

Tres tablas: `core.sucursal`, `core.correlativo` y `plataforma.modulo_sucursal`. Las
tres existen hoy.

Todo lo de esta sección está **comprobado contra la base** en septiembre de 2026
—esquema cargado limpio desde los dieciocho `.sql` y leído con `\d`—, no escrito
de memoria.

`core.acceso_sucursal` apunta aquí pero **no es de este territorio**: pertenece a
*La gente que trabaja*, según `00-panorama.md`. Aparece en 2.4 como llave
entrante y en «Cómo vive con las demás», no como tabla propia.

### 2.1 · `core.sucursal` — lo que existe

Nueve columnas.

| Columna | Tipo | Nulo | Por defecto | Para qué sirve y qué resuelve |
|---|---|---|---|---|
| `sucursal_id` | `bigint` identidad | no | generado | La llave. Es lo que viaja en cada episodio, cada equipo y cada correlativo. Resuelve poder decir «esto pasó aquí» sin depender del nombre, que cambia |
| `empresa_id` | `bigint` **FK** → `core.empresa` | no | — | La dueña. Es la columna sobre la que actúa RLS: sin ella la sucursal no tendría a quién pertenecer y el aislamiento no existiría |
| `nombre` | `text` | no | — | Cómo la llama la gente: «Sede Central», «Sucursal Colonia Kennedy». **Único por empresa** (`uq_sucursal_nombre`). Resuelve que en una lista de sedes no haya dos que se lean igual, que es de dónde salen los errores de recepción |
| `codigo` | `text` | no | — | Dos a seis caracteres, mayúsculas o dígitos: `LFO`, `SC`, `KEN`, `S02`. Es lo que el humano dice por teléfono y lo que **prefija los números** de esa sede. Resuelve que un número de orden diga de dónde salió sin consultar nada |
| `direccion` | `text` | sí | — | La dirección que se imprime en el encabezado del informe de esta sede. Resuelve que el informe diga dónde se atendió al paciente y no dónde está la oficina de la empresa |
| `telefono` | `text` | sí | — | El teléfono del encabezado. Es a donde llama el paciente que tiene una duda sobre su resultado, así que tiene que ser el de la sede que lo atendió |
| `activo` | `boolean` | no | `true` | Si la sede está operando. Es booleano y no enumerado a propósito: aquí sí es un sí o un no. Resuelve cerrar una sede sin borrar nada de lo que hizo |
| `creado_en` | `timestamptz` | no | `now()` | Cuándo se abrió en el sistema. No la lee nadie; se queda hasta que exista la bitácora, que dará la misma fecha y además el quién (`H-97`) |

#### Restricciones e índices

| Objeto | Qué es | Qué resuelve |
|---|---|---|
| `sucursal_pkey` | Llave primaria sobre `sucursal_id` | La identidad de la fila |
| `uq_sucursal_empresa` | `UNIQUE (sucursal_id, empresa_id)` | **La pieza clave del aislamiento.** No sirve para evitar duplicados —`sucursal_id` ya es único— sino para que las siete tablas hijas puedan referenciarla con llave compuesta. Sin este `UNIQUE`, PostgreSQL no permitiría esas llaves |
| `uq_sucursal_codigo` | `UNIQUE (empresa_id, codigo)` | Que dos sedes de la misma empresa no compartan prefijo de numeración. Si lo compartieran, dos órdenes distintas podrían llamarse igual |
| `uq_sucursal_nombre` | `UNIQUE (empresa_id, nombre)` | Que la lista de sedes sea legible. Es **más estricto que la empresa**, donde `nombre` sí puede repetirse: la razón social la desambigua el RTN, pero a una sucursal no la desambigua nada más que su nombre |
| `ck_sucursal_codigo` | `CHECK (codigo ~ '^[A-Z0-9]{2,6}$')` | Que el prefijo sea corto, en mayúscula o dígitos, sin espacios ni acentos. Resuelve que el número de orden sea legible a mano y transcribible por teléfono |
| `rls_sucursal` | Política RLS forzada, `USING` y `WITH CHECK` sobre `empresa_id = core.empresa_actual()` | Que una empresa no vea ni cree sucursales de otra |

#### Llaves foráneas salientes

Una sola: `empresa_id` → `core.empresa (empresa_id)`, con el nombre automático
`sucursal_empresa_id_fkey`.

Es **simple y no compuesta**, y eso es correcto: en `core.empresa`, `empresa_id`
*es* la llave primaria, así que no hay una segunda columna con la que formar el
par. La sucursal es el primer nivel colgando de la raíz, y de aquí para abajo
todas las llaves del sistema ya son compuestas.

> **ABIERTO** — Los nombres de restricción están mezclados. Las que se
> escribieron a mano siguen la convención (`fk_correlativo_sucursal`,
> `uq_sucursal_codigo`); las que PostgreSQL nombró solo, no
> (`sucursal_empresa_id_fkey`, `modulo_sucursal_modulo_id_fkey`). No rompe nada,
> pero después de haber definido una nomenclatura conviene decidir si se
> renombran o si se acepta la excepción por escrito. *(H-35)*

### 2.2 · `core.correlativo` — lo que existe

Siete columnas. Es la tabla que reparte los números del sistema.

| Columna | Tipo | Nulo | Por defecto | Para qué sirve y qué resuelve |
|---|---|---|---|---|
| `correlativo_id` | `bigint` identidad | no | generado | La llave. No se usa para nada más: la fila se busca siempre por `(empresa_id, tipo, sucursal_id)` |
| `empresa_id` | `bigint` **FK** → `core.empresa` | no | — | La dueña. Cada empresa tiene su propia numeración, empezando en 1 |
| `sucursal_id` | `bigint` **FK compuesta** → `core.sucursal (sucursal_id, empresa_id)` | **sí** | — | **El nulo es la parte importante.** Nulo significa «este contador es de toda la empresa»; con valor significa «es de esta sede». Resuelve que el expediente del paciente sea uno solo en toda la empresa mientras las órdenes se numeran por sede |
| `tipo` | `core.tipo_correlativo` | no | — | Qué se está numerando: `expediente`, `episodio`, `informe`, `orden`, `muestra`. Es enumerado y no texto para que nadie invente un sexto tipo por error de tipeo |
| `prefijo` | `text` | no | `''` | Lo que va antes del número: `EXP-`, `LFO-`, `LFOI-`. Resuelve que el número se pueda leer en voz alta y se sepa qué es y de dónde salió |
| `ancho` | `smallint` | no | `6` | Con cuántos dígitos se rellena: `6` da `LFO-000123`. Resuelve que los números ordenen bien alfabéticamente, que es como los ordena cualquier lista |
| `ultimo_valor` | `bigint` | no | `0` | El último número emitido. Es el estado del contador |

#### Restricciones e índices

| Objeto | Qué es | Qué resuelve |
|---|---|---|
| `correlativo_pkey` | Llave primaria sobre `correlativo_id` | La identidad de la fila |
| `uq_correlativo` | `UNIQUE (empresa_id, tipo, COALESCE(sucursal_id, 0))` | Que exista **un solo contador** por combinación. El `COALESCE` es el truco que hace que dos filas de empresa con el mismo tipo choquen: sin él, varios nulos no colisionan en PostgreSQL y una empresa podría acabar con dos contadores de expediente repartiendo números en paralelo |
| `ck_correlativo_ancho` | `CHECK (ancho >= 4 AND ancho <= 12)` | Que nadie configure un ancho absurdo. Con menos de 4 el número se ve raro; con más de 12 no cabe en una etiqueta |
| `rls_correlativo` | Política RLS forzada | Que una empresa no lea ni mueva el contador de otra |

No tiene `creado_en`, y es deliberado: esta fila cambia con cada número que
emite, así que una marca de tiempo no diría nada útil. Desde `E-22` ninguna
tabla lleva `actualizado_en` ni trigger, así que aquí ya no es una excepción.

#### Cómo se emite un número

`core.siguiente_correlativo(empresa_id, sucursal_id, tipo)` hace `UPDATE … SET
ultimo_valor = ultimo_valor + 1 … RETURNING`. El `UPDATE` toma el candado de la
fila, así que **dos recepciones simultáneas nunca reciben el mismo número**: la
segunda espera a que la primera termine su transacción.

Eso también significa que si la transacción se cae después de pedir el número,
**ese número se pierde**. Es el precio correcto: preferimos un hueco en la serie
a dos órdenes con el mismo número.

> **RIESGO** — El ámbito del contador vive en la cabeza de quien llama a la
> función. Para `expediente` hay que pasar `NULL`; para los otros cuatro, la
> sucursal. Si alguien pasa la sucursal para `expediente`, la función no
> encuentra la fila y lanza «No hay correlativo configurado para empresa … tipo …
> sucursal …», que suena a error de configuración cuando en realidad es una
> llamada mal hecha. «Dónde vive en el código» propone que la función resuelva el ámbito
> sola. *(H-25)*

### 2.3 · `plataforma.modulo_sucursal` — lo que existe

Siete columnas. Dice qué partes del producto contrató cada sede.

**Vive en `plataforma`, no en `core`, porque la escribe el operador** (`H-99`). El laboratorio no decide qué compró: la lee —RLS `FOR SELECT` la recorta a su empresa— para pintar el menú del administrador y para que `usuario_puede()` intersecte. Mismo patrón que `plataforma.enlace`, y se define en `03_core.sql` por la misma razón: necesita `core.sucursal`.

| Columna | Tipo | Nulo | Por defecto | Para qué sirve y qué resuelve |
|---|---|---|---|---|
| `sucursal_id` | `bigint` **FK compuesta** → `core.sucursal` | no | — | Dónde está encendido. Resuelve que dos sedes de la misma empresa ofrezcan cosas distintas: la central hace laboratorio e imagen, la de barrio solo laboratorio |
| `modulo_id` | `text` **FK** → `plataforma.modulo` | no | — | Qué módulo. Es texto y no número porque es un identificador de producto (`lab_clinico`), no un dato de cliente |
| `empresa_id` | `bigint` **FK** → `core.empresa` | no | — | La dueña. Redundante con la sucursal, y está a propósito: es lo que hace posible la llave compuesta y lo que RLS necesita leer sin unir tablas |
| `activo` | `boolean` | no | `true` | Si está encendido hoy. **Apagarlo quita el acceso sin borrar lo que el administrador configuró**: `rol_permiso` guarda la intención y sobrevive, esta columna guarda la licencia. Cuando el cliente vuelve a pagar, el acceso vuelve solo |
| `activado_en` | `timestamptz` | no | `now()` | Desde cuándo. Es información del operador, y ahora está en su esquema |
| `desactivado_en` | `timestamptz` | sí | — | Cuándo se apagó. `CHECK (activo OR desactivado_en IS NOT NULL)`: apagar sin decir cuándo ya no se puede (`H-26`) |
| `asignado_por` | `text` | no | — | Quién del lado del operador lo asignó. Texto y no llave foránea: el operador no es usuario de ninguna empresa (`E-19`) |

#### Restricciones e índices

| Objeto | Qué es | Qué resuelve |
|---|---|---|
| `modulo_sucursal_pkey` | Llave primaria `(sucursal_id, modulo_id)` | Que un módulo no se pueda activar dos veces en la misma sede. No incluye `empresa_id` y no le hace falta: `sucursal_id` ya es único en todo el sistema |
| `fk_modulo_sucursal_sucursal` | FK compuesta `(sucursal_id, empresa_id)` | Que no se pueda encender un módulo en la sucursal de otra empresa |
| `rls_modulo_sucursal` | Política RLS forzada | Aislamiento |

> **RIESGO** — Hay `activado_en` pero no `desactivado_en`. Cuando alguien apaga
> un módulo, se pierde cuándo lo apagó — y eso es un dato de facturación, no un
> detalle. *(H-26)*

> **RIESGO** — `plataforma.modulo` tiene dos filas, `core` y `lab_clinico`, y
> `core.crear_empresa()` solo inserta `lab_clinico`. El módulo `core` **no está
> activo en ninguna sucursal de ninguna empresa**, aunque **diecisiete** permisos
> del catálogo cuelgan de él. Si algún día una pantalla decide qué mostrar
> consultando `modulo_sucursal`, el núcleo entero desaparece. O `core` se
> inserta como cualquier otro, o se declara por escrito que es siempre implícito
> y `plataforma.modulo` no debería listarlo. *(H-27)*

### 2.4 · Quién apunta a `core.sucursal`

Siete llaves foráneas, **todas compuestas** `(sucursal_id, empresa_id)`. En este
territorio la invariante de la llave compuesta se cumple sin excepciones.

| Tabla y columna | Nulo | Qué significa |
|---|---|---|
| `core.episodio.sucursal_id` | no | **Dónde se atendió al paciente.** Es la llave que hace que el informe lleve la dirección correcta |
| `core.correlativo.sucursal_id` | sí | De qué sede es este contador. Nulo = de toda la empresa |
| `plataforma.modulo_sucursal.sucursal_id` | no | Qué contrató esta sede. **Es del operador**, no del laboratorio |
| `core.acceso_sucursal.sucursal_id` | no | Quién puede trabajar aquí. **Es del territorio de la gente**, no de este |
| `lab.precio_prueba.sucursal_id` | sí | Precio de esta sede. Nulo = precio de toda la empresa |
| `integra.equipo.sucursal_id` | no | Dónde está físicamente el analizador |
| `integra.mensaje_crudo.sucursal_id` | no | De qué sede llegó el mensaje del equipo |

Lo que hay que notar: **tres de las siete son de las ramas** (`lab`, `integra`).
La sucursal es la tabla del núcleo con la que más hablan las ramas, y eso está
bien — la rama apunta al núcleo, nunca al contrario. Cuando llegue imagenología,
sus equipos van a colgar de aquí igual y esta tabla no cambia.

Y las dos columnas nulas —precio y correlativo— son el mismo patrón: *si hay
valor, esta sede tiene lo suyo; si es nulo, vale el de la empresa*. Es el
**mecanismo** de herencia del sistema, y en el núcleo solo aparece en estos dos
lugares. `S-13` describe el orden completo en que se resuelve para el precio, que
añade un nivel más —el convenio— con su propia columna nula.

### 2.5 · Desactivar una sede sin perder el rastro — propuesta

Desactivar una sede es una decisión seria y hoy no deja rastro: `activo` pasa a
`false` y no queda quién, cuándo ni por qué.

| Columna | Tipo | Nulo | Para qué sirve y qué resuelve |
|---|---|---|---|
| `desactivado_en` | `timestamptz` | sí | Cuándo dejó de operar. Resuelve poder contestar «¿esta orden se emitió cuando la sede ya estaba cerrada?» |
| `desactivado_por_usuario_id` | `bigint` **FK compuesta** → `core.usuario` | sí | Quién lo decidió. Es una decisión que afecta a todo el personal de esa sede |
| `desactivado_motivo` | `text` | sí | Por qué. Texto libre y no catálogo: cerrar una sede pasa una vez cada varios años y un catálogo de motivos aquí sería inventar |
| `reactivado_en` | `timestamptz` | sí | Si volvió a abrir. Que las tres columnas anteriores queden llenas y esta también significa «estuvo cerrada de tal fecha a tal fecha» |

> **ABIERTO** — ¿Bastan estas cuatro columnas o la sucursal merece una tabla de
> historial como la que se propuso para la empresa? Cuatro columnas guardan
> **el último** cierre; una tabla guardaría todos. La empresa cambia de estado
> por mora varias veces al año y ahí la tabla se justifica sola; una sucursal
> abre y cierra casi nunca. Empezamos por las columnas, y si aparece una segunda
> reapertura se convierte en tabla. *(H-36)*

## 3. Quién la crea y con qué datos

### La primera sucursal

La crea **el operador de la plataforma**, dentro del alta de la empresa y en la
misma transacción. No es una decisión del cliente: `E-6` dice que toda empresa
nace con al menos una sucursal, así que el alta no puede terminar sin ella.

El detalle está en `flujos/01-alta-de-un-cliente.md`, paso 2.

### Las siguientes

Las crea **el administrador de la empresa**, con el permiso
`sucursal.administrar`. Aquí ya no hace falta el operador: abrir una sede es una
decisión del negocio del laboratorio y el sistema tiene que dejarlo hacer solo.

> **REGLA** — `S-1` · La primera sucursal la crea el operador dentro del alta.
> Las siguientes las crea el administrador de la empresa con
> `sucursal.administrar`. Ninguna sucursal se crea sin uno de los dos caminos.

### Datos que se piden

| Dato | Obligatorio | Nota |
|---|---|---|
| Nombre | sí | Único dentro de la empresa |
| Código | sí | 2 a 6 caracteres, mayúscula y dígitos. **Se propone antes de aceptarlo**, porque va a prefijar todos los números de esta sede para siempre |
| Dirección | sí | Va impresa en el informe. La columna admite nulos; el flujo no |
| Teléfono | sí | Igual |
| Módulos que se encienden | sí | Al menos uno |

La dirección y el teléfono son un caso claro de **el flujo exige más que la
base**. Las columnas son anulables porque una migración de datos viejos puede
traer sedes sin teléfono, pero una sucursal creada por el sistema no puede
quedarse sin ellos: son lo que el paciente lee en su informe.

### Lo que el sistema genera solo

Cuando se crea una sucursal, tienen que aparecer con ella **cuatro
correlativos**: `episodio`, `informe`, `orden` y `muestra`, prefijados con su
código. El de `expediente` no, porque es de la empresa y ya existe.

> **REGLA** — `S-2` · Una sucursal no existe de verdad hasta que tiene sus
> cuatro correlativos. Se crean con ella, en la misma transacción, o no se crea.

> **RIESGO** — Hoy esto **no se cumple para la segunda sucursal**.
> `core.crear_empresa()` inserta los cinco correlativos de la primera, pero no
> existe ninguna función `core.crear_sucursal()`: la segunda sede se arma con
> `INSERT` a mano y nada obliga a acordarse de los contadores. El síntoma no
> aparece al crearla —aparece semanas después, cuando la primera recepcionista
> de la sede nueva intenta admitir a un paciente y recibe «No hay correlativo
> configurado». *(H-24)*

### Umbral: cuándo una sucursal está lista

`E-9` dice que no se entrega una empresa que no se pueda usar. Lo mismo vale
sede por sede, y con la misma idea de umbral:

| # | Requisito | Por qué |
|---|---|---|
| 1 | Existe, activa, con nombre y código | El ancla |
| 2 | Dirección y teléfono | Van en el informe |
| 3 | Sus cuatro correlativos | Sin ellos no se admite a nadie |
| 4 | Al menos un módulo activo | Si no, no hay nada que hacer aquí |
| 5 | Al menos un usuario con acceso a ella | Una sede sin personal asignado no atiende |

> **REGLA** — `S-3` · El sistema puede decir, de cada sucursal, si cumple los
> cinco requisitos. Una sucursal que no los cumple no debería aparecer como
> opción al admitir a un paciente.

---

## 4. Ciclo de vida y estados

La sucursal **no tiene estados**: tiene un booleano. Es la diferencia más
importante entre este territorio y el de la empresa, y es deliberada.

La empresa tiene un ciclo de vida comercial con matices: `core.estado_empresa`
tiene cinco valores —`prueba`, `activa`, `suspendida`, `cancelada`, `cerrada`— y
cada uno tiene una salida distinta. La sucursal solo puede estar **abierta o cerrada**; no hay una sede
«suspendida por mora» ni «en prueba».

```
   crear ──> activo = true ──desactivar──> activo = false
                  ^                              │
                  └──────── reactivar ───────────┘
```

### Qué significa cada valor

| Valor | Qué significa | Qué se puede hacer |
|---|---|---|
| `activo = true` | La sede opera | Todo lo que permita el nivel de acceso de la empresa |
| `activo = false` | La sede no recibe pacientes nuevos | Leer todo su historial; cerrar lo que quedó abierto; nada nuevo |

### Qué NO cambia al desactivar

Esta es la parte que se hace mal en la mayoría de los sistemas: desactivar se
implementa como si fuera borrar, y entonces se pierden cosas.

- **Los episodios abiertos siguen abiertos.** Un paciente al que se le tomó
  muestra ayer tiene derecho a su resultado hoy, aunque hoy la sede haya cerrado.
- **Los informes ya emitidos siguen consultables y reimprimibles.** Con qué
  dirección se reimprimen es otra cuestión, y hoy no está resuelta (H-40).
- **Los correlativos no se borran ni se reinician.** Si la sede reabre, la serie
  continúa donde iba. Reiniciarla produciría dos órdenes con el mismo número.
- **Los equipos siguen atados a ella.** Si el analizador se mudó de sede, eso es
  otra operación y tiene que dejar constancia.
- **Los accesos del personal no se revocan.** Quien podía trabajar ahí sigue
  pudiendo entrar a lo que quedó abierto.

> **REGLA** — `S-4` · Desactivar una sucursal impide **abrir cosas nuevas** en
> ella. No cierra, no anula y no borra nada de lo que ya existía.

> **REGLA** — `S-5` · Una sucursal no se borra nunca. Toda la historia clínica
> del sistema apunta a ella por el lugar donde ocurrió, y ese dato no se puede
> quedar huérfano.

> **REGLA** — `S-6` · Ningún episodio se abre en una sucursal con
> `activo = false`. Es la única cosa que el booleano prohíbe, y es la que
> importa: es la puerta de entrada.

> **RIESGO** — `S-6` **no tiene hoy ningún mecanismo**. `core.sucursal.activo`
> se escribe y no se lee: no aparece en una sola política, función, restricción
> ni índice del esquema, fuera de su propia definición y su comentario. Hoy se
> puede admitir a un paciente en una sede cerrada y nada lo impide. Es el mismo
> problema que tiene `core.empresa.estado`, y por la misma razón: el estado se
> guardó antes de que existiera quién lo consultara. *(H-23)*

### La última sucursal

`E-6` dice que toda empresa tiene al menos una sucursal, y el requisito 2 del
umbral entregable de la empresa pide que **esté activa**. `E-6` por sí sola no
basta para lo que sigue —garantiza que exista, no que esté encendida—, así que
`S-7` se apoya en las dos:

> **REGLA** — `S-7` · No se puede desactivar la última sucursal activa de una
> empresa. Una empresa sin ninguna sede activa no puede atender a nadie, y para
> eso está el estado de la empresa, no el de la sucursal.

Cerrar el negocio entero es una decisión comercial y se hace cancelando la
empresa (`F-E-5`), no apagando sedes una por una.

> **ABIERTO** — `E-7` dice que «el laboratorio está cerrado» se expresa con
> `sucursal.activo`, y `S-7` impide apagar la última activa. En una empresa de
> **una sola sucursal** —el caso del primer cliente— ese hecho no se puede
> registrar en ningún sitio: cancelar la empresa no apaga la sede, y apagar la
> sede está prohibido. O `S-7` admite una excepción cuando la empresa está
> cancelada, o `E-7` señala el campo equivocado. *(H-41)*

---

## 5. Flujos propios

| Código | Flujo | Quién | Tipo |
|---|---|---|---|
| `F-S-1` | Crear una sucursal adicional | Administrador | Individual |
| `F-S-2` | Editar los datos de una sucursal | Administrador | Individual |
| `F-S-3` | Desactivar una sucursal | Administrador | Individual |
| `F-S-4` | Reactivar una sucursal | Administrador | Individual |
| `F-S-5` | Encender o apagar un módulo | Administrador | Individual |
| `F-S-6` | Cambiar el prefijo o el ancho de un correlativo | Administrador | Individual |
| — | Alta de un cliente (crea la primera) | Operador | **Compartido** → `flujos/01-alta-de-un-cliente.md` |
| — | Admisión de un paciente (elige la sede) | Recepción | **Compartido** → `flujos/03-admision-de-un-paciente.md` |

### F-S-1 · Crear una sucursal adicional

**Quién:** el administrador, con `sucursal.administrar`.
**Cuándo:** el cliente abre una sede nueva.

1. Pide nombre, código, dirección, teléfono y módulos.
2. Comprueba que el nombre y el código no existan ya en la empresa.
3. **En una sola transacción**: crea la sucursal activa, sus cuatro correlativos
   prefijados con el código, y una fila de `modulo_sucursal` por módulo.
4. Registra el evento en `audit.evento`.
5. Comprueba el umbral de `S-3` y avisa de lo que falta —típicamente, que nadie
   tiene acceso todavía.

Todo o nada, por la misma razón que el alta de empresa: una sucursal a medias no
se nota hasta que alguien no puede trabajar.

### F-S-2 · Editar los datos de una sucursal

**Quién:** el administrador. **Cuándo:** cambió la dirección o el teléfono.

Nombre, dirección y teléfono se editan sin ceremonia. El **código, no**:

> **REGLA** — `S-8` · El código de una sucursal **y el prefijo de sus
> correlativos** son inmutables desde el momento en que se emite el primer número
> con ellos. Antes de eso se puede corregir un error de tipeo; después, no. Las
> dos cosas se congelan juntas porque el prefijo es una copia del código: proteger
> solo una deja la otra como puerta de atrás.

La razón es concreta: `core.correlativo.prefijo` guarda una **copia** del código,
no una referencia. Cambiar el código deja los contadores prefijando con el viejo,
y a partir de ahí el número de una orden ya no dice de dónde salió. Peor: si el
código nuevo es el que otra sede usaba antes, aparecen dos series que se
solapan.

> **RIESGO** — `S-8` no tiene mecanismo. `codigo` es una columna editable con
> `UPDATE` concedido y nada compara contra `core.correlativo.prefijo`. La copia
> del prefijo es correcta —congelar el dato es lo que hace que un número viejo
> siga significando lo mismo—, pero entonces hace falta que algo impida cambiar
> el original. *(H-28)*

Cambiar la dirección **no debería reescribir los informes ya emitidos**: un
informe de 2024 tiene que seguir mostrando la dirección de 2024.

> **RIESGO** — Hoy no se cumple. `core.informe_version` tiene nueve columnas y
> ninguna congela el encabezado; lo único que guarda una copia del documento es
> `archivo_ruta`/`archivo_hash`, y las dos admiten nulos. Si el informe se vuelve
> a generar desde los datos en vez de recuperar el archivo, sale con la dirección
> de hoy. `S-12` no tiene dónde vivir. *(H-40)*

### F-S-3 · Desactivar una sucursal

**Quién:** el administrador. **Cuándo:** se cierra la sede.

1. Comprueba `S-7`: que no sea la última activa.
2. Muestra **qué queda abierto ahí**: episodios sin cerrar, órdenes sin
   resultado, informes en borrador. Es información, no un impedimento.
3. Pide un motivo escrito.
4. `activo = false`, con fecha, usuario y motivo (sección 2.5).
5. Registra el evento.
6. La sede desaparece de la lista de opciones al admitir, y sigue apareciendo en
   consultas e informes históricos.

> **ABIERTO** — ¿Se le avisa a la gente que tenía acceso a esa sede? Parece que
> sí, pero no hay ningún mecanismo de avisos definido todavía en el sistema.

### F-S-4 · Reactivar una sucursal

**Quién:** el administrador. Simétrico del anterior: `activo = true`,
`reactivado_en` con fecha, evento registrado.

**Los correlativos continúan donde iban.** No se reinician nunca.

### F-S-5 · Encender o apagar un módulo

**Quién:** el administrador, con `sucursal.administrar`.

Encender es un `INSERT` o un `UPDATE activo = true`. Apagar es
`activo = false` — y como no hay `DELETE`, la fila se queda con su historia.

> **REGLA** — `S-9` · Apagar un módulo en una sucursal esconde sus acciones en
> esa sede. No borra ni oculta los datos que ya produjo: un resultado de
> laboratorio sigue consultable aunque el módulo de laboratorio esté apagado.

> **RIESGO** — Igual que `S-6`, `S-9` no tiene mecanismo: nadie consulta
> `modulo_sucursal.activo`. Hoy se puede crear una orden de laboratorio en una
> sede donde el módulo está apagado. *(H-29)*

### F-S-6 · Cambiar el prefijo o el ancho de un correlativo

**Quién:** el administrador. **Cuándo:** casi nunca, y siempre es delicado.

Cambiar el **ancho** de 6 a 7 es seguro: los números viejos siguen siendo
válidos y los nuevos son más largos. Ordenan distinto en una lista alfabética,
que es el único efecto visible.

Cambiar el **prefijo** no se permite una vez emitido el primer número: es la otra
mitad de `S-8`. Si se permitiera, `S-8` no serviría de nada —bastaría con cambiar
el prefijo en vez del código para producir el mismo daño— y dos sedes podrían
acabar emitiendo la misma serie. Antes del primer número, se corrige libremente.

Lo que **no** se permite:

> **REGLA** — `S-10` · `ultimo_valor` no se edita a mano y nunca baja. Bajarlo
> hace que el sistema vuelva a emitir números ya usados, y desde ese momento dos
> documentos distintos se llaman igual.

> **ABIERTO** — Hoy `lis_app` tiene `UPDATE` sobre `core.correlativo` sin
> restricción de columna, así que `S-10` depende por completo de que la
> aplicación se porte bien. Un `CHECK` no sirve —no puede comparar con el valor
> anterior— así que serían un trigger o un `GRANT UPDATE (prefijo, ancho)` por
> columna. Lo segundo es más limpio, pero rompería la propia función que
> incrementa el contador si no se la exceptúa. *(H-34)*

---

## 6. Reglas propias

> **REGLA** — `S-1` · La primera sucursal la crea el operador dentro del alta;
> las siguientes, el administrador con `sucursal.administrar`. Ninguna sucursal se
> crea fuera de esos dos caminos.

> **REGLA** — `S-2` · Una sucursal nace con sus cuatro correlativos, en la misma
> transacción, o no nace.

> **REGLA** — `S-3` · El sistema puede decir de cada sucursal si cumple los cinco
> requisitos para atender, y una que no los cumpla no aparece como opción al
> admitir a un paciente.

> **REGLA** — `S-4` · Desactivar una sucursal impide abrir cosas nuevas en ella;
> no cierra, no anula y no borra nada de lo que ya existía.

> **REGLA** — `S-5` · Una sucursal no se borra nunca.

> **REGLA** — `S-6` · Ningún episodio se abre en una sucursal inactiva.

> **REGLA** — `S-7` · No se puede desactivar la última sucursal activa de una
> empresa.

> **REGLA** — `S-8` · El código de una sucursal es inmutable desde que se emite
> el primer número con él.

> **REGLA** — `S-9` · Apagar un módulo esconde sus acciones en esa sede, no sus
> datos.

> **REGLA** — `S-10` · `ultimo_valor` nunca baja y no se edita a mano.

> **REGLA** — `S-11` · Los correlativos no se reinician: ni al reactivar una
> sede, ni al cambiar de año, ni por petición del cliente. Un número identifica un
> documento para siempre.

> **REGLA** — `S-12` · El encabezado del informe sale de la sucursal donde se
> atendió, no de la empresa. La empresa aporta la razón social y el logo; la
> sucursal, la dirección y el teléfono.

> **REGLA** — `S-13` · El precio se resuelve de lo más específico a lo más
> general: primero la tarifa del convenio, después el precio de esta sucursal,
> después el precio de la empresa. Es el único sitio donde la herencia tiene tres
> niveles; el correlativo solo tiene dos.

### Cuáles tienen mecanismo hoy

Una regla sin mecanismo no es mentira: es una regla que vive en la aplicación o
todavía en ninguna parte. Lo que no puede pasar es que nadie sepa cuál es cuál.
Comprobado contra la base:

| Regla | ¿Algo la hace cumplir? | Qué |
|---|---|---|
| `S-1` | no | No existe `crear_sucursal()` |
| `S-2` | no | Nada obliga a los cuatro correlativos (H-24) |
| `S-3` | no | No existe `sucursal_lista_para()` |
| `S-4` | no | Reverso de `S-6`: nadie lee `activo` |
| `S-5` | **sí** | `DELETE` revocado para `lis_app` en toda tabla |
| `S-6` | no | `sucursal.activo` no se lee en ninguna parte (H-23) |
| `S-7` | no | Nada cuenta las sucursales activas de una empresa |
| `S-8` | no | `codigo` y `prefijo` son editables (H-28) |
| `S-9` | no | `modulo_sucursal.activo` no se lee (H-29) |
| `S-10` | no | `lis_app` tiene `UPDATE` sobre `ultimo_valor` (H-34) |
| `S-11` | no | Nada impide reiniciar; y el comentario de la propia tabla dice que se puede (H-39) |
| `S-12` | no | `informe_version` no tiene dónde congelar el encabezado (H-40) |
| `S-13` | **sí** | `lab.precio_para()`, con ese orden exacto |

Dos de trece. Es el estado real del territorio: el esquema guarda los datos y casi
ninguna de las reglas está escrita en la base todavía. «Dónde vive en el código» lista lo que
haría falta para cambiarlo.

`S-11` merece una nota, porque el laboratorio hoy hace lo contrario y aun así la
regla se queda.

**Hoy el laboratorio reinicia su numeración.** Lleva las boletas a mano, y con
lápiz nadie escribe `LFO-2026-000123` cuatrocientas veces al año: con papel, `123`
es lo único razonable y por eso en enero se vuelve a empezar. Ese reinicio no es
una regla del negocio — es lo que el cuaderno obliga.

El sistema quita la razón. El número lo genera y lo imprime la máquina, así que
su longitud deja de costar trabajo. Y lo que se gana es exactamente lo que el
papel no puede dar: `LFO-000123` es **una** boleta, para siempre, sin preguntar
de qué año. Si se reiniciara, esa cadena sería dos boletas distintas y
`uq_orden_numero UNIQUE (empresa_id, numero)` rechazaría la segunda — no el 1 de
enero, sino en marzo del año siguiente, cuando el contador vuelva a pasar por un
número ya emitido y haya un paciente esperando en el mostrador.

Si algún cliente futuro necesita el reinicio de verdad —por una obligación legal,
no por costumbre— la salida está estudiada y no es reiniciar a secas: es meter el
periodo dentro del número (`LFO-2026-00123`), con dos columnas en
`core.correlativo` que digan cada cuánto vuelve a empezar y a qué periodo
pertenece el valor actual. No se construye hasta que un cliente lo pida, porque
volvería condicional cada número del sistema.

Y si el cliente quiere ver el año sin nada de esto, va en el prefijo y punto.

`S-13` es la única de las trece que **ya está implementada y probada**:
`lab.precio_para()` ordena exactamente así, con la tarifa negociada ganando
sobre el precio de sede. Se cita aquí porque es una regla del territorio de la
sucursal aunque la función viva en la rama.

---

## 7. Cómo vive con las demás

### Con la empresa

- **Le da:** el lugar. La empresa no atiende a nadie; atienden sus sucursales.
- **Le exige:** existir. Una sucursal sin empresa no es nada, y la llave foránea
  lo hace imposible.
- **Recibe de ella:** el aislamiento y el nivel de acceso. Una sucursal activa de
  una empresa bloqueada no opera — el nivel de la empresa se evalúa primero.
- **Cuando la empresa se cancela:** las sucursales **no** se desactivan en
  cascada. Ya está dicho en `core/01-la-empresa.md`, «Cómo vive con las demás», y
  aquí se confirma desde el otro lado: desactivar es operativo, cancelar es
  comercial.

### Con la gente que trabaja

- **Le da:** el lugar de trabajo, a través de `core.acceso_sucursal`.
- **Le exige:** que alguien tenga acceso. El requisito 5 de `S-3`.
- **Qué hay que resolver en el documento de la gente:** `core.acceso_sucursal`
  tiene cuatro columnas, ningún `activo` y ninguna fecha de revocación, y
  `DELETE` está revocado en todo el sistema. **Hoy un acceso a sucursal no se
  puede quitar.** Y hay algo más grande: la tabla no la lee nadie —ni
  `core.usuario_puede()` ni ninguna función—, así que el acceso por sede no
  existe en la práctica: cualquier usuario de la empresa puede operar en
  cualquiera de sus sedes. *(H-30, H-31)*

### Con la visita

- **Le da:** el lugar donde ocurrió, y el número. `core.episodio.sucursal_id` es
  obligatorio: no hay visita sin sede.
- **Le exige:** que la sede esté activa (`S-6`, hoy sin mecanismo).
- **Si la sede se desactiva:** los episodios abiertos siguen su curso.

### Con el documento

- **Le da:** el encabezado (`S-12`) y la serie del número de informe.
- **Cuidado con H-7:** el número de informe es único **por empresa** en el
  esquema, mientras el correlativo de informe es **por sucursal**. Las dos cosas
  conviven hoy porque el prefijo de sede hace que los números no choquen, pero es
  una coincidencia frágil, no un diseño. Lo único que hoy hace que dos sedes no
  compartan prefijo es que `core.crear_empresa()` lo deriva del código, y
  `uq_sucursal_codigo` obliga a que el código sea único. Pero el prefijo es una
  copia editable: en cuanto alguien lo cambie a mano (`F-S-6`), dos sedes pueden
  emitir el mismo número de informe y la restricción de unicidad por empresa
  salta. Conviene decidir si la unicidad debe ser por sucursal. *(H-7, H-28)*

### Con el laboratorio (rama)

- **Le da:** el lugar de los equipos y el nivel de precios de sede.
- **Le exige:** nada. La rama apunta al núcleo, no al revés.
- `integra.equipo` y `lab.precio_prueba` son las dos tablas de rama que cuelgan
  de aquí. Cuando llegue imagenología, sus equipos hacen lo mismo y esta tabla no
  cambia.

> **RIESGO** — `integra.equipo` tiene `uq_equipo_identificador (empresa_id,
> identificador)`: el identificador del analizador es único **por empresa**, no
> por sucursal. Dos sedes con el mismo modelo de Hemax 53 probablemente reporten
> el mismo identificador de fábrica, y la segunda no se podría dar de alta. Es un
> problema del territorio de integración, encontrado desde aquí. *(H-32)*

### Con por dónde entra

- **No se tocan directamente.** El convenio es de la empresa, no de la sede. Se
  cruzan solo en el episodio y en el precio. El médico solicitante ya no está en
  la base (`H-98`).

---

## 8. Quién puede hacer qué

| Permiso | Qué permite | Qué plantilla lo trae |
|---|---|---|
| `sucursal.administrar` | Crear y configurar sucursales, sus correlativos y sus módulos | **Solo Administrador** |
| `episodio.crear` | Abrir un episodio, que es lo que consume la numeración de la sede | Administrador, Recepción |
| `equipo.administrar` | Configurar los analizadores de una sede | **Solo Administrador** |
| `catalogo.administrar` | Cambiar precios, incluidos los de sede | Administrador, Bioquímico |

Comprobado contra `core.crear_empresa()`: `sucursal.administrar` y
`equipo.administrar` no los recibe ningún rol operativo al crear la empresa. Es correcto.
Configurar sedes y equipos cambia cómo funciona el sistema para todos los demás,
y quien atiende pacientes no necesita poder hacerlo.

> **RIESGO** — El permiso existe en el catálogo y **nada lo exige**. No hay
> ninguna función `core.crear_sucursal()` que llame a `core.exigir_permiso`, así
> que hoy `sucursal.administrar` solo puede comprobarlo la pantalla — y la
> pantalla es el lado equivocado. Es el mismo hueco que tiene `crear_empresa`
> (H-1). *(H-33)*

> **ABIERTO** — ¿Hace falta un `sucursal.ver` separado? Hoy cualquiera que pueda
> leer un episodio ve el nombre de la sede donde ocurrió, y eso parece correcto:
> la lista de sedes de la propia empresa no es información sensible. *(H-47)*

---

## 9. Qué puede salir mal

**La segunda sucursal sin correlativos.** El fallo más probable de todo este
territorio, y no aparece al crearla: aparece cuando la primera recepcionista de
la sede nueva intenta admitir a un paciente. El mensaje habla de configuración y
el usuario no tiene forma de saber que le falta una fila en una tabla que nunca
vio. *(H-24)*

**Atender en una sede cerrada.** `activo` no lo lee nadie. El sistema deja abrir
episodios en una sucursal desactivada, y quien la desactivó cree que ya no se
puede. *(H-23)*

**Cambiar el código y romper la numeración.** Nada lo impide, el efecto es
silencioso, y se descubre semanas después mirando una lista de órdenes con dos
prefijos distintos. *(H-28)*

**Dos sedes, un solo Hemax.** Si el identificador de fábrica es el mismo, la
segunda sede no puede dar de alta su equipo. *(H-32)*

**El acceso por sucursal que no existe.** La tabla está, el panorama la nombra,
el alta inserta su fila — y ninguna función la consulta. Alguien va a asumir que
un usuario de una sede no puede tocar la otra, y va a estar equivocado. *(H-31)*

**Un número perdido en cada transacción fallida.** No es un error, es el diseño:
`siguiente_correlativo` incrementa el contador y si la transacción se cae el
número no vuelve. Hay que decirlo por escrito, porque un contador con huecos
alarma a quien lleva la contabilidad.

**El módulo `core` que nadie encendió.** Hoy inofensivo, mañana no. *(H-27)*

**Reiniciar la numeración cada año.** El laboratorio lo hace hoy, y lo va a pedir.
`S-11` dice que no y explica por qué —el reinicio es una consecuencia del papel, no
una regla—, pero conviene tener la respuesta lista, no improvisarla delante del
cliente. Y hay un riesgo concreto detrás: si alguien cede y edita `ultimo_valor` a
mano en enero, el daño no aparece ese día. Aparece en marzo del año siguiente,
cuando el contador vuelve a pasar por un número ya emitido. *(H-49)*

---

## 10. Preguntas abiertas

| # | Pregunta | Qué hace falta para decidir |
|---|---|---|
| 1 | ¿Columnas de desactivación o tabla de historial? | Saber si una sucursal reabre alguna vez. Con una sola reapertura las columnas sobran; con dos, hacen falta la tabla (H-36) |
| 2 | ¿El número de informe debe ser único por sucursal en vez de por empresa? | Ver un informe real y decidir si el cliente quiere que la serie de cada sede sea visible (H-7) |
| 3 | ¿Se avisa al personal cuando su sede se desactiva? | No hay ningún mecanismo de avisos en el sistema todavía. La pregunta es más grande que este territorio (H-37) |
| 4 | ¿Cómo se mueve un equipo de una sede a otra? | Decidir si `integra.equipo.sucursal_id` se edita o si el traslado deja constancia. Es del territorio de integración, pero lo dispara este (H-38) |
| 5 | ¿Se renombran las restricciones automáticas? | Decidir si la nomenclatura aplica también a lo que PostgreSQL nombró solo |
| 6 | ¿Hay horarios de atención por sucursal? | Depende de si el sistema va a prometer una hora de entrega (H-8). Hoy no hay tabla de horarios ni de días festivos |
| 7 | ¿El módulo `core` se activa como cualquier otro o es implícito? | Decidir qué significa `plataforma.modulo` y si alguna pantalla va a consultarla (H-27) |

---

## 11. Dónde vive en el código

### Lo que ya existe

| Qué | Dónde |
|---|---|
| Tabla `core.sucursal` | `03_core.sql` |
| Tabla `core.correlativo` | `03_core.sql` |
| Tabla `plataforma.modulo_sucursal` | `03_core.sql` (necesita `core.sucursal`); su política RLS en `05_rls_y_funciones.sql` |
| Tipo `core.tipo_correlativo` | `01_esquemas_y_tipos.sql` |
| Políticas `rls_sucursal`, `rls_correlativo`, `rls_modulo_sucursal` | `05_rls_y_funciones.sql`, creadas por el bucle sobre `core` |
| `core.siguiente_correlativo()` | `05_rls_y_funciones.sql` |
| Creación de la primera sucursal y sus cinco correlativos | `core.crear_empresa()` — `16_roles.sql` |
| `lab.precio_para()`, que implementa `S-13` | `14_lab_rls_y_funciones.sql` |
| Permiso `sucursal.administrar` | `06_semillas.sql` |

### Lo que este documento pide crear

| Qué | Para qué |
|---|---|
| `core.crear_sucursal()` | Crear sede, correlativos y módulos en una transacción. Cierra `S-2` y H-24. **Falta decidir cómo entra el operador**: si la función exige `sucursal.administrar`, `crear_empresa()` no puede llamarla, porque el operador no es usuario del producto (H-43) |
| `core.sucursal_lista_para()` | Contestar los cinco requisitos de `S-3` |
| Comprobación de `sucursal.activo` al abrir un episodio | Cerrar `S-6`. Puede ser un `CHECK` no expresable, así que va en la función de admisión o en un trigger |
| Comprobación de `modulo_sucursal.activo` al usar el módulo | Cerrar `S-9` |
| `core.desactivar_sucursal()` · `reactivar_sucursal()` | Los flujos `F-S-3` y `F-S-4`, con `S-7` comprobado y la constancia de la sección 2.5 |
| Cuatro columnas en `core.sucursal` | `desactivado_en`, `desactivado_por_usuario_id`, `desactivado_motivo`, `reactivado_en` |
| Ámbito automático en `siguiente_correlativo()` | Que la función busque primero por sucursal y, si no encuentra, por empresa. Así el llamador siempre puede pasar su sucursal y el ámbito deja de ser conocimiento oral. Cierra H-25 |
| Protección de `ultimo_valor` | Trigger o `GRANT` por columna, para que `S-10` tenga mecanismo |
| Protección del `codigo` una vez emitido | Para que `S-8` tenga mecanismo |
| Fila de `modulo_sucursal` para `core`, o la nota que diga que es implícito | Cerrar H-27 |
