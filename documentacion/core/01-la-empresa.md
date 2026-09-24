# La empresa

El inquilino del sistema. Es la unidad de aislamiento: todo lo que existe
pertenece a una empresa y solo a una.

*No es el cliente.* El cliente es quien firmó el contrato y a quien se le factura,
y vive en `comercial.cliente` (`E-21`). Casi siempre hay uno de cada uno, y por eso
se confunden.

> Este documento está completo y sirve de modelo para los demás. Once secciones,
> según la plantilla. Aun así, las referencias entre documentos van por **nombre**
> de sección y no por número.

## 1. Qué es y por qué existe

Una empresa es una razón social que contrata el sistema. En el primer cliente hay
dos empresas distintas en el mismo edificio —la clínica y el laboratorio— y esa es
exactamente la razón por la que la empresa existe como pieza y no como una simple
columna de configuración.

**Qué resuelve:** que dos clientes del mismo SaaS no puedan verse. Cada fila de cada
tabla de dominio lleva `empresa_id`, y la base filtra por ella con Row Level
Security, sin depender de que el código se acuerde.

**Qué pasaría sin ella:** habría que instalar una copia del sistema por cliente. Eso
convierte cada actualización en una visita, y deja de ser un SaaS.

**Qué NO es:** no es la sucursal. La empresa no atiende a nadie; atienden sus
sucursales. Todo lo operativo —precios, correlativos, equipos, accesos— cuelga de la
sucursal.

## 2. Las tablas y sus campos

En el LIS este territorio tiene **una sola tabla**: `core.empresa`. Del lado
comercial hay tres más —`cliente`, `contacto` y `cliente_empresa`, en 2.6— y lo
único que sigue sin existir es `core.empresa_configuracion`, marcada como
propuesta en 2.4.

Todo lo de esta sección está comprobado contra la base en septiembre de 2026, no
escrito de memoria.

### 2.1 · `core.empresa` — lo que existe

Nueve columnas. **Ninguna llave foránea saliente**: la empresa es la raíz del
sistema y no depende de nada.

| Columna | Tipo | Nulo | Por defecto | Para qué sirve y qué resuelve |
|---|---|---|---|---|
| `empresa_id` | `bigint` identidad | no | generado | La llave. Es el valor que viaja en `lis.empresa_id` y contra el que compara cada política RLS del sistema. Resuelve el aislamiento: sin este número, «los datos de esta empresa» no es una idea expresable. |
| `nombre` | `text` | no | — | Razón social. Va impresa en el encabezado de cada informe y en cualquier documento legal. **No es único a propósito**: dos razones sociales distintas pueden llamarse parecido, y lo único que identifica de verdad es el RTN. |
| `nombre_comercial` | `text` | sí | — | Con el que lo conoce la gente. «Laboratorio Familiar Ochoa» puede no ser la razón social registrada. Resuelve que el informe se vea como el cliente quiere sin falsear el dato legal. |
| `rtn` | `text` | sí | — | Registro Tributario Nacional **con el que esta empresa le factura a sus pacientes**, y con el que otra empresa la nombra para trabajar con ella. Único solo cuando existe, por índice parcial: eso evita dar de alta dos veces al mismo laboratorio. **No es la identidad fiscal del cliente** —esa es `comercial.cliente.rtn`— y por eso no sirve para detectar que un cliente se dio de alta dos veces: un cliente puede tener varias empresas, cada una con su RTN (`E-21`). Es opcional porque en periodo de prueba todavía no hay papeles. |
| `estado` | `core.estado_empresa` | no | `prueba` | El ciclo de vida de la suscripción. Resuelve que suspender por mora y cancelar sean cosas distintas, con salidas distintas. No decide qué se puede hacer: eso lo decide el nivel de acceso. |
| `nivel_acceso` | `core.nivel_acceso` | no | `completo` | Qué puede hacer la empresa ahora mismo. Lo decide el lado comercial y lo escribe aquí: la API lo consulta en cada petición y no puede cruzar la frontera cada vez. Es una de las dos formas en que una decisión comercial entra al LIS (`E-16`) |
| `fecha_cierre` | `date` | sí | — | Cuándo vence el plazo. La usa la tarea diaria de cierre. Vive de este lado a propósito: así el sistema se cierra solo el día que toca aunque la administración esté apagada |
| `creado_en` | `timestamptz` | no | `now()` | Cuándo se dio de alta la empresa. No la lee nadie todavía. Se queda porque se escribe una vez y no puede mentir, y porque hoy es lo único que contesta «¿desde cuándo existe esto?». El día que exista la bitácora, el `INSERT` registrado da esa misma fecha **y además el quién**, y entonces sobra (`H-97`). |

> **REGLA** — `E-22`: **ninguna tabla lleva `actualizado_en`, y la base no tiene
> triggers.** Esa columna prometía «esta fila cambió a esta hora» y no podía decir qué
> cambió, ni quién, ni qué decía antes —las tres preguntas que uno hace justo cuando algo
> salió mal—. Para eso está `audit.evento`, que ya tiene `usuario_id`, `accion`,
> `datos_antes` y `datos_despues`. Donde más importaba tampoco servía: cambiar lo que puede
> un rol es un `INSERT` o un `DELETE` en `core.rol_permiso`, no el `UPDATE` de una columna,
> así que no había fila que fechar. Se retiraron las diez columnas, los nueve triggers y
> `core.tocar_actualizado_en()`. Consecuencia: nada pasa por detrás, todo lo que ocurre está
> escrito en una función que se puede leer y probar. *(H-96, cierra H-87)*

#### Restricciones e índices

| Objeto | Qué es | Qué resuelve |
|---|---|---|
| `empresa_pkey` | Llave primaria sobre `empresa_id` | La identidad de la fila |
| `uq_empresa_rtn` | Único **parcial**: `(rtn) WHERE rtn IS NOT NULL` | Que dos empresas no compartan RTN, sin que dos empresas sin RTN choquen entre sí. Un `UNIQUE` normal no serviría: en PostgreSQL varios nulos no colisionan, pero el índice parcial deja la intención escrita |
| `rls_empresa` | Política RLS forzada | Que una empresa solo se vea a sí misma. Es la única tabla del núcleo donde la política compara contra su propia llave y no contra una columna `empresa_id` |

> **RIESGO** — La política `rls_empresa` significa que **con el rol de la
> aplicación nadie puede listar las empresas**: cada sesión solo ve la suya. Eso es
> correcto para el producto, pero deja al operador de la plataforma sin forma de
> ver su cartera de clientes. Confirma que hace falta un canal aparte con su propia
> autenticación. *(H-16)*

#### Llaves foráneas salientes

Ninguna. Es deliberado: la empresa es la raíz y no puede depender de nada, porque
todo depende de ella.

### 2.2 · Quién apunta a `core.empresa`

**Treinta y ocho** llaves foráneas, y no todas significan lo mismo. La
distinción importa porque solo una de las tres clases participa en el
aislamiento.

Eran cuarenta y dos hasta que se retiró la identidad compartida (`H-73`), y una menos desde que se retiró `core.medico` (`H-98`). Lo que
más se movió es la tercera clase —las que mencionan a **dos** empresas— que
**bajó de cinco a dos**. Es la mejor medida de que el modelo nuevo funciona.

#### Pertenencia — 34 llaves

La columna se llama `empresa_id` y quiere decir *«esta fila es de esta empresa»*.
Es la columna sobre la que actúa RLS, y la que forma la mitad de cada llave foránea
compuesta.

`core`: `sucursal`, `modulo_sucursal`, `correlativo`, `empleado`, `usuario`, `rol`,
`rol_permiso`, `acceso_sucursal`, `paciente`, `paciente_referencia`, `mensaje`,
`convenio`, `episodio`, `informe`, `informe_version`, `entrega`

`lab`: `area`, `tipo_muestra`, `analito`, `prueba`, `prueba_analito`,
`precio_prueba`, `rango_referencia`, `orden`, `muestra`, `muestra_rechazo`,
`orden_prueba`, `resultado`, `aviso_valor_critico`

`integra`: `equipo`, `mapeo_codigo`, `mensaje_crudo`, `intento_proceso`

`audit`: `evento`

#### Desde `comercial` — 2 llaves

`comercial.relacion_evento.empresa_id` y `comercial.cliente_empresa.empresa_id`.

Se llaman igual que las de arriba y **no son lo mismo**. No hay RLS en `comercial`,
así que estas columnas no aíslan nada: dicen *«este hecho del negocio es sobre ese
inquilino»*. Es la única dirección permitida por `E-18` —el negocio apunta al
producto, nunca al revés— y por eso se cuentan aparte.

#### Referencia a una segunda empresa — 2 llaves

Aquí la empresa referenciada **no es la dueña de la fila**. Son las únicas dos
del sistema, y por eso son las que hay que mirar con lupa.

| Tabla y columna | Qué significa | Qué resuelve |
|---|---|---|
| `core.convenio.empresa_destino_id` | El convenio apunta a otra empresa del sistema | Hoy la clínica es una fila de catálogo con esto en nulo; el día que entre al sistema, apunta a su empresa y la solicitud pasa de papel a electrónica sin migrar órdenes |
| `core.paciente_referencia.contraparte_empresa_id` | Cómo llama la otra empresa a mi paciente | Menciona a otra empresa pero **no le da ningún privilegio**: RLS impide leer esa fila, así que del otro lado es un número opaco. Reemplaza a `core.paciente.persona_id`, que colgaba de una fila de identidad compartida |

**Se fueron tres**, con la identidad compartida y la derivación vieja:
`core.empresa_asociada.empresa_destino_id`, `audit.derivacion.empresa_origen_id`
y `audit.derivacion.empresa_destino_id`, más
`plataforma.persona.creado_por_empresa_id` cuando la tabla dejó de existir.

`H-21` se cierra con esto: preguntaba si estaba bien que `plataforma` dependiera
de `core.empresa`, y las dos tablas que lo hacían ya no existen.

### 2.3 · La frontera con lo comercial — decisión

Dos tablas que este documento proponía —`plataforma.motivo_estado` y
`core.empresa_estado_historial`— **se retiran del LIS**. No porque estuvieran mal
pensadas, sino porque no son de esta base.

**El razonamiento.** El histórico de la relación con un cliente —cuándo entró, por
qué, cuándo se fue, hasta cuándo le vendiste el servicio— es administración del
dueño del sistema, no del laboratorio. La tabla propuesta lo delataba sola: su
columna `ejecutado_por` tenía que ser `text` y no una llave foránea a
`core.usuario`, «porque el operador de la plataforma no es un usuario de ninguna
empresa». Una tabla cuyo actor no se puede expresar en el modelo de seguridad de
su propia base está en la base equivocada. Y con RLS no había salida buena: o el
laboratorio veía su propio historial de suspensiones, o era la única tabla de
`core` sin política.

**Dónde va.** A un esquema aparte —`comercial`— **en el mismo PostgreSQL**, con
`REVOKE ALL` para `lis_app`, igual que ya se hace con `plataforma.persona`. Mismo
motor y no otra base: así el alta sigue siendo una sola transacción (`F1-1`), la
llave foránea hacia `core.empresa` es real, y no aparece el problema de dos copias
que se desincronizan. El día que haya que separarlo de verdad es un `pg_dump` de
un esquema.

Es también lo que hace la industria: de doce productos multiempresa inspeccionados
—Plausible, Cal.com, GitLab, PostHog, Odoo, Chatwoot y otros— **ninguno pone lo
administrativo en una base aparte a esta escala**. Los que separan lo hacen en un
servicio, y cuando ya no caben en una máquina.

**Qué se queda en el LIS.** Solo lo que el sistema tiene que hacer cumplir en cada
petición: `estado`, `nivel_acceso` y `fecha_cierre`, las tres en `core.empresa`.
El LIS **no sabe por qué** una empresa está limitada — recibe un nivel y una fecha
y los aplica. Esa ignorancia es la frontera.

`fecha_cierre` se queda de este lado a propósito: así el sistema se cierra solo el
día que toca, aunque la consola de administración esté apagada.

> **REGLA** — `E-17` · El LIS no conoce el motivo. `core.empresa` guarda qué puede
> hacer la empresa y hasta cuándo; por qué es así vive en `comercial` y no cruza.

> **REGLA** — `E-18` · `core` y `lab` **nunca** referencian `comercial`.
> `comercial` referencia `core.empresa`. Una sola dirección, y `lis_app` no tiene
> ni un privilegio sobre `comercial`. Si algún día una función del LIS necesita
> leer ese esquema, es que la frontera se movió y hay que revisar por qué.

> **ABIERTO** — Nada hace cumplir `E-18` todavía. Cuando el esquema exista, el
> revisor de esquema puede comprobarlo mecánicamente, que es como GitLab resuelve
> el mismo problema: declarar a qué dominio pertenece cada tabla y romper la
> comprobación si alguien cruza. *(H-53)*

#### Lo que se lleva, anotado para cuando armes lo comercial

Esto ya no se diseña aquí. Queda como insumo, no como esquema:

**Para suspender**

| Motivo | Qué pasó | Nivel inmediato | Plazo | Al vencer |
|---|---|---|---|---|
| `falta_pago` | Retraso en facturas | pendiente | pendiente | pendiente |
| `solicitud_del_cliente` | Pausa temporal: remodelación, vacaciones | pendiente | pendiente | pendiente |
| `fin_de_prueba` | Terminó la prueba sin convertir | pendiente | pendiente | pendiente |
| `incumplimiento` | Uso indebido o violación del contrato | pendiente | pendiente | pendiente |
| `riesgo_seguridad` | Cuenta comprometida, actividad anómala | `bloqueado` | `0` | — |

**Para cancelar**

| Motivo | Qué pasó | Nivel inmediato | Plazo | Al vencer |
|---|---|---|---|---|
| `cancelacion_con_antelacion` | El cliente avisó con el plazo acordado | pendiente | pendiente | `cerrada` |
| `cancelacion_voluntaria` | El cliente se va sin haber avisado | pendiente | pendiente | `cerrada` |
| `falta_pago_prolongada` | Escaló desde suspensión por mora | pendiente | pendiente | `cerrada` |
| `incumplimiento_grave` | Motivo de terminación inmediata | pendiente | pendiente | `cerrada` |
| `cierre_del_negocio` | El laboratorio cerró | pendiente | pendiente | `cerrada` |
| `migracion` | Se fue a otro sistema | pendiente | pendiente | `cerrada` |


Los valores de política siguen sin decidir (H-13), y ahora esa decisión es tuya y
de tu negocio, no del LIS.

### 2.4 · `core.empresa_configuracion` — propuesta

Uno a uno con la empresa. Existe como tabla aparte y no como columnas de `empresa`
porque va a crecer y porque son datos de presentación, no de identidad.

| Columna | Tipo | Nulo | Para qué sirve y qué resuelve |
|---|---|---|---|
| `empresa_id` | `bigint` PK **y FK** → `core.empresa` | no | La llave primaria es la foránea: fuerza el uno a uno |
| `logo` | `bytea` o ruta | sí | El logo del encabezado del informe |
| `encabezado_texto` | `text` | sí | Líneas adicionales del encabezado: registro sanitario, dirección fiscal |
| `pie_texto` | `text` | sí | Aviso legal al pie del informe |
| `bloque_firma_texto` | `text` | sí | Lo que se imprime junto a la firma del bioquímico, además de su nombre y colegiación |
| `correo_notificaciones` | `text` | sí | A dónde manda el sistema los avisos administrativos |
| `zona_horaria` | `text` | no | Con qué hora se sellan los resultados. Resuelve un problema que hoy no existe y aparecerá con el primer cliente en otro huso |

La dirección y el teléfono que van en el informe **no están aquí**: viven en
`core.sucursal`, porque cambian por sede. Aquí solo va lo que es igual para toda
la empresa.

### 2.5 · Las dos columnas por donde entra lo comercial

`nivel_acceso` y `fecha_cierre` **ya existen** y están en la tabla de 2.1. Esta
sección se queda por la regla que las gobierna.

> **REGLA** — `E-16` · `nivel_acceso` y `fecha_cierre` solo las escriben las
> funciones de cambio de estado, que son el único punto por donde una decisión
> comercial entra al LIS. Ninguna pantalla del laboratorio las escribe.

Tiene mecanismo: `lis_app` solo puede escribir `nombre_comercial` sobre
`core.empresa`. El índice `ix_empresa_cierre` sobre `(estado, fecha_cierre)`
también existe ya (`H-22`, cerrado).

### 2.6 · El cliente — quién contrató el servicio

Esto no existía y es un hueco de fondo, no un detalle. `comercial.contrato` tenía
fechas, moneda y monto, y **ninguna contraparte**: ni nombre, ni RTN, ni dirección,
ni a quién llamar. En las 45 tablas que había no existía una sola columna donde
viviera la persona o la sociedad que te contrató. Con eso **no se puede emitir una
factura**.

Lo que se usaba en su lugar era `core.empresa.rtn`, que es otra cosa.

#### Los dos RTN

| | Qué es | Dónde vive |
|---|---|---|
| **De la empresa** | Con el que **el laboratorio le factura a sus pacientes**, y con el que otra empresa lo nombra para trabajar con él | `core.empresa.rtn` |
| **Del cliente** | Con el que **vos le facturás a él** | `comercial.cliente.rtn` |

Casi siempre son el mismo número. Dejan de serlo el día que un grupo contrate bajo
la sociedad madre y cada laboratorio facture con el suyo — y ahí cada columna sigue
contestando su propia pregunta.

#### Las tres tablas

| Tabla | Qué guarda |
|---|---|
| `comercial.cliente` | Razón social o persona, tipo, RTN, dirección fiscal |
| `comercial.contacto` | Varios por cliente, con su **papel**: quién firma, quién paga, quién atiende lo técnico |
| `comercial.cliente_empresa` | De quién es cada empresa, con vigencia |

`comercial.cliente` **no tiene columna `activo`**: si el cliente sigue siéndolo se
deduce del estado de sus empresas. Dos copias del mismo estado se desincronizan, y
es justo lo que este esquema evita con `nivel_acceso`.

#### Un cliente, varias empresas

La unión es una tabla y no una columna, por dos razones que apuntan al mismo lado.

La primera es que `E-18` no deja poner `cliente_id` en `core.empresa`: `core` nunca
referencia `comercial`. La segunda es que así **un cliente puede tener varias
empresas** — un grupo con dos laboratorios que no se ven entre sí es un contrato,
una factura y dos inquilinos aislados.

Con vigencia, además, porque un laboratorio se puede vender: el mismo inquilino,
los mismos datos, otro dueño. Se cierra una fila y se abre otra, y el histórico sí
puede tener varios.

Lo que garantiza **un solo dueño en cada fecha** es una restricción de exclusión
por rango, no un índice único parcial. La diferencia importa: el índice parcial
solo impide dos filas sin fecha de fin, y deja pasar dos vigencias cerradas que se
solapen — con lo que `registrar_evento_cliente()` leería dos dueños válidos para el
mismo día. Está probado en `95_pruebas_comercial.sql`, prueba 12b.

El contrato pasó a colgar del cliente: se contrata con quien firma, no con un
inquilino. Y `comercial.registrar_evento_cliente()` aplica un evento a todas sus
empresas vigentes en una sola transacción — suspender a un cliente y que una de sus
dos empresas siga trabajando no es un estado que deba poder existir.

> **REGLA** — `E-21` · **El cliente y la empresa no son lo mismo.** La empresa es el
> inquilino del LIS: lo que RLS aísla, lo que tiene sucursales y pacientes. El
> cliente es quien firmó el contrato y a quien se le factura, y vive solo en
> `comercial`. Un cliente puede tener varias empresas; una empresa tiene un solo
> cliente vigente. El RTN de la empresa **no** es la identidad fiscal del cliente.

### 2.7 · `plataforma.enlace` — lo que existe

Una fila por **ruta entre dos sedes** de dos empresas distintas. **Ya existe**,
en `03_core.sql`; sus funciones en `08_enlace_y_mensaje.sql`. Reemplazó a
`core.empresa_asociada`, que se retiró.

Cuando se escriba `core/06-por-donde-entra.md`, esta sección y la 2.8 se mudan
ahí.

#### Por qué no alcanza unir empresas

Es lo que hace `core.empresa_asociada`, y ese es su defecto, no su virtud:

```
Empresa A con sedes A1 y A2        Empresa B con sedes B1 y B2
Lo que trabaja junto es A1 con B2.

Con un vínculo «A trabaja con B»:
  · lo que manda A2 también le cae a B          ← no tienen nada que ver
  · y B2 es inalcanzable                        ← no hay forma de nombrarla
```

**Lo que trabaja junto son las sedes, no las empresas.** La fila guarda las dos
empresas y las dos sucursales, y cada pareja distinta es otro enlace: que dos
laboratorios atiendan a A1 son dos filas, no una con dos destinos.

#### La crea el operador, no los clientes

Para que una empresa declarara su lado tendría que teclear el RTN y el código de
sede del otro. **Eso es información confidencial y no es suya.**

Con el enlace creado por el operador, ninguna empresa escribe nunca el
identificador de otro — y de paso no existe la pantalla donde ir tecleando para
averiguar quién más es cliente del sistema.

Es la misma regla que ya gobierna el alta: una empresa solo la crea el operador
(`E-8`). El enlace entre dos clientes es de la misma familia.

#### La forma

| Columna | Tipo | Nulo | Para qué sirve |
|---|---|---|---|
| `enlace_id` | `bigint` identidad | no | La llave |
| `empresa_a_id` · `sucursal_a_id` | `bigint` | no | Un lado, con FK compuesta |
| `empresa_b_id` · `sucursal_b_id` | `bigint` | no | El otro, igual |
| `vigente_desde` / `vigente_hasta` | `date` | no / sí | Cortar una ruta no apaga las demás |
| `creado_por` | `text` | no | Quién la creó. El operador no es usuario del producto, así que es texto |
| `nota` | `text` | sí | Por qué existe esta ruta |

Falta un único que impida repetir la misma ruta vigente, normalizando el orden
—`(A1,B2)` y `(B2,A1)` son la misma—: `least`/`greatest` sobre las dos
sucursales. En el espejo va como comentario porque SQL Server no admite
expresiones como llave de índice.

#### Por qué en `plataforma`

| Dónde | Por qué no |
|---|---|
| `core` | Sería una fila que ven dos empresas y una política RLS que compara dos `empresa_id` — exactamente `rls_derivacion`, que estamos matando |
| `comercial` | El LIS no podría leerla nunca (cero privilegios ahí) y la entrega la necesita. Que una función del LIS tenga que leer `comercial` significaría que la frontera se movió (`E-18`) |

`plataforma` ya es «por encima de las empresas» y ya tiene el patrón: `lis_app`
sin acceso directo, y funciones que contestan solo tu lado.

#### Qué ve cada quien

`lis_app` **no lee la tabla.** Pregunta por función y la función contesta
únicamente su lado:

```
El hospital pregunta «¿a quién le puedo mandar?»
    └─ «Laboratorio Ochoa, desde tu sede A1»

Nunca ve sucursal_b_id. No le hace falta: cuando manda, la
función resuelve el destino y escribe la fila del otro lado.
```

El nombre comercial de la contraparte sí se muestra — las dos empresas ya saben
que trabajan juntas; el operador creó el enlace justamente porque lo acordaron.

#### Lo que el enlace no dice, y por qué

**No dice qué sede está físicamente dentro de cuál.** Es la primera pregunta que
hace cualquiera que conoce el caso del primer cliente.

La vecindad no se modela porque no sostiene ninguna regla:
`core.sucursal.direccion` es texto libre y no la lee ninguna función, política,
restricción ni índice — comprobado sobre los veinte `.sql`. La prueba es el caso
contrario:

> Si el laboratorio se muda del hospital y le sigue trabajando por mensajería,
> **no cambia ni una fila del modelo.** Cambia el texto de la dirección y nada
> más. El sello sigue decidiendo la pertenencia, la orden sigue siendo el
> vínculo, y las órdenes siguen cayendo en la misma ventanilla.

Lo que el sistema necesita saber es **cuál sede atiende a cuál**, y eso es el
enlace. Que el paciente camine veinte metros o tome un taxi es una comodidad del
mundo real. La vecindad, cuando alguien la quiera leer, vive en
`core.sucursal.direccion`: *«Dentro del Hospital San José, 2do piso»*.

**Tampoco lleva lista de permisos.** El enlace abre el canal; qué puede mandar
cada quien lo siguen decidiendo los permisos de rol que ya existen.

#### Lo que se deduce y no se guarda

> *«¿Estas dos empresas trabajan juntas?»* no es una fila. Es que haya **al
> menos una ruta vigente** entre ellas.

Por eso `core.empresa_asociada` no se reemplaza por nada a nivel de empresa: se
retira y ya.

### 2.8 · `core.mensaje` — lo que existe

Reemplazó a `audit.derivacion`, que se retiró junto con `rls_derivacion` —la
única política del sistema que comparaba dos `empresa_id`—. **Ya existe**, en
`03_core.sql`, y se muda a `core/06-por-donde-entra.md` cuando ese territorio se
escriba.

#### El problema, en una comparación

| | `audit.derivacion` (retirada) | `core.mensaje` |
|---|---|---|
| Filas por hecho | **Una**, que ven dos empresas | **Una de cada lado** |
| Columna de empresa | `empresa_origen_id` y `empresa_destino_id` | `empresa_id`, la mía |
| RLS | `rls_derivacion`, la única política del sistema que compara dos empresas | La normal, la de todas |
| Sucursal | **No existe ninguna** | La mía, obligatoria |
| Estados | `solicitada → aceptada │ rechazada` | De entrega, no de negociación |

Los estados de negociación se mueren con el modelo decidido: **la aceptación se
mudó una sola vez a la relación**. Una boleta que llega es trabajo, no una
propuesta.

#### La forma

| Columna | Tipo | Nulo | Para qué sirve y qué resuelve |
|---|---|---|---|
| `mensaje_id` | `bigint` identidad | no | La llave. Interna, no viaja |
| `empresa_id` | `bigint` | no | **Mía.** RLS de siempre |
| `enlace_id` | `bigint` | no | **Por cuál ruta viajó.** Las dos filas apuntan al mismo enlace, que es de plataforma y de ninguna de las dos empresas |
| `sucursal_id` | `bigint` | no | **Mi** ventanilla. Sale del enlace, copiada aquí para que la bandeja de una sede se consulte sin salir de `core` |
| `direccion` | `enviado │ recibido` | no | Cuál de las dos filas soy |
| `tipo` | `core.tipo_mensaje` | no | Qué es lo que va adentro |
| `folio` | `uuid` | no | El número de guía del sobre. El mismo de los dos lados |
| `responde_a_folio` | `uuid` | sí | Arma el hilo: solicitud → resultado → corrección |
| `contenido` | `jsonb` | no | Lo que cruzó. Se guarda de los dos lados: «qué me mandaste» tiene que poder contestarse |
| `estado` | `core.estado_mensaje` | no | Ver abajo |

**Los tipos**, que salen de `flujos/06`:

| `tipo` | Quién | Qué lleva |
|---|---|---|
| `solicitud` | hospital → lab | Paciente, su expediente, pruebas, convenio, contexto clínico, urgencia. El médico que la pidió viaja en el `jsonb`, no como llave: `core.medico` se retiró (`H-98`) |
| `consulta_historial` | pregunta | ¿Conocés a este? Documento y año |
| `respuesta_historial` | respuesta | *no lo conozco* / *es este* / *no puedo confirmar*. Nunca una lista (`F6-3`) |
| `resultado` | lab → hospital | Los valores, y el informe sellado |
| `correccion` | lab → hospital | Un resultado ya entregado cambió. Nunca una edición silenciosa |
| `aviso` | cualquiera | Fusioné dos fichas mías (`H-74`) |

**Los estados dependen de la dirección**, y hay un `CHECK` que lo obliga:

```
mi fila enviada     pendiente ──► entregado
mi fila recibida    recibido  ──► trabajado
                              └─► descartado    (dije que no a ese remitente)
```

Un estado del otro lado en mi propia fila sería mentira: yo no sé si ya lo
trabajaron. Me entero porque vuelve un `resultado`, que es otro mensaje.

#### Dos cosas que esta forma resuelve sin tabla extra

**Sin enlace, el mensaje no sale.** La función lo rechaza en el origen, en vez de
salir y caer en una bandeja de «remitente nuevo» del otro lado. Falla más temprano
y más cerca de quien se equivocó, y por eso `sucursal_id` no puede ser nula: si
llegó, se sabe dónde cae.

**El folio es `uuid` y no el `mensaje_id`.** Si viajara el id de secuencia, el
mensaje número 4 821 le contaría al otro cuántos mensajes mandás.

Quién es la contraparte no está en el mensaje: sale del enlace, por función,
porque es un dato de plataforma. La pantalla lo pide una vez y lo guarda.

#### Lo que se lleva por delante

`audit.derivacion` y `rls_derivacion` desaparecen. `audit` se queda solo con
`evento`, que sí es un rastro y sí es de solo inserción. El mensaje vive en `core`
porque es **trabajo**, no rastro: cambia de estado, y `audit` no admite `UPDATE`.

## 3. Quién la crea y con qué datos

> **REGLA** — `E-8` · Una empresa **solo la crea el operador de la plataforma**,
> nunca un usuario del producto. No existe pantalla de autoservicio ni endpoint
> público que cree empresas.

**La precondición es comercial, no técnica.** Antes de crear la empresa hay un
acuerdo cerrado: una prueba con fecha de vencimiento, un contrato firmado, un pago
recibido. El sistema no verifica eso —vive fuera— pero el alta lo registra.

### La regla que gobierna el alta

> **REGLA** — `E-9` · No se entrega una empresa que no se pueda usar. El alta
> termina cuando el administrador de la empresa puede entrar y empezar a configurar
> por su cuenta, sin pedirle nada al operador.

Esto convierte el alta en algo más grande que insertar una fila. Ver el flujo
completo en **`flujos/01-alta-de-un-cliente.md`**; aquí quedan las condiciones que
la empresa impone.

### Los dos umbrales

Hay dos niveles de «lista», y confundirlos es lo que produce entregas a medias.

**Entregable** — el administrador puede entrar y trabajar. Es responsabilidad del
operador y sin esto no se entrega:

| # | Requisito | Por qué |
|---|---|---|
| 1 | La empresa existe con nombre y estado | Obvio, pero es el ancla de todo |
| 2 | Al menos una sucursal activa, con código | Sin sucursal no hay correlativos ni precios |
| 3 | Los cinco correlativos configurados | Sin ellos no se puede crear ni un expediente |
| 4 | El convenio `Particular` predeterminado | Ninguna orden puede existir sin convenio |
| 5 | Al menos un módulo activo en la sucursal | Si no, el sistema no ofrece nada que hacer |
| 6 | Los cuatro roles con sus permisos | Para que el admin no tenga que inventarlos |
| 7 | **Un empleado y un usuario administrador** | Sin esto nadie puede entrar. Es el paso que faltaba |
| 8 | Datos del encabezado del informe | Nombre, dirección y teléfono que se imprimen |

**Operable** — el laboratorio puede atender a un paciente de verdad. Es
responsabilidad del cliente, con acompañamiento:

| # | Requisito | Quién lo hace |
|---|---|---|
| 9 | Al menos un área de laboratorio | El bioquímico |
| 10 | Al menos un tipo de muestra | El bioquímico |
| 11 | Al menos una prueba con analitos y precio | El bioquímico |
| 12 | Rangos de referencia revisados | El bioquímico, y no es negociable |
| 13 | Los empleados reales, con sus usuarios | El administrador |

> **REGLA** — `E-10` · El sistema sabe en cuál de los dos umbrales está cada
> empresa y lo puede decir en una consulta. Una empresa entregada pero no operable
> es un estado legítimo; una empresa entregada sin cumplir los ocho primeros
> requisitos es un error del operador.

### Datos que se piden en el alta

| Dato | Obligatorio | Nota |
|---|---|---|
| Nombre (razón social) | sí | Va impreso en el informe |
| Nombre comercial | no | Con el que lo conoce la gente |
| RTN | no | Se puede empezar en prueba sin papeles |
| Nombre y código de la primera sucursal | sí | El código, 2 a 6 caracteres en mayúscula |
| Dirección y teléfono de la sucursal | sí | Van en el encabezado del informe |
| Nombre, apellidos y correo del administrador | sí | Es la persona que va a recibir el sistema |
| Módulos contratados | sí | Al menos uno |
| Motivo del alta | sí | `prueba`, `contrato`, `migracion` |

## 4. Ciclo de vida y estados

Cinco estados, los cinco ya en el esquema (`H-20`, cerrado). `cerrada` se explica
más abajo.

| Estado | Qué significa | Nivel de acceso |
|---|---|---|
| `prueba` | Recién dada de alta, en periodo de evaluación | completo |
| `activa` | Cliente al día | completo |
| `suspendida` | Hay un problema; el acceso se reduce según el motivo | según el motivo |
| `cancelada` | Se terminó la relación, pero corre un plazo de cierre | según el motivo |
| `cerrada` | Se acabó el plazo. Nadie de la empresa entra | bloqueado |

### Los cuatro niveles de acceso

Esta es la pieza clave: **el estado no decide qué se puede hacer, el nivel de acceso
sí**, y el nivel sale del motivo. Así, cuando definas las políticas, solo hay que
decir qué nivel corresponde a cada motivo.

| Nivel | Entrar | Consultar | Admitir pacientes | Procesar y validar | Entregar informes | Exportar datos |
|---|---|---|---|---|---|---|
| `completo` | sí | sí | sí | sí | sí | sí |
| `solo_cierre` | sí | sí | **no** | sí | sí | sí |
| `solo_lectura` | sí | sí | no | no | sí (reimprimir) | sí |
| `bloqueado` | no | — | — | — | — | solo el operador |

`solo_cierre` es el que resuelve *«se le da una fecha de uso para que pueda terminar
de gestionar todo»*: no entran pacientes nuevos, pero las muestras que ya están en
el analizador se procesan, se validan y se entregan. Un laboratorio no puede
quedarse con tubos a medias porque venció un contrato.

> **REGLA** — `E-11` · Ningún cambio de estado destruye datos. Un paciente que ya
> recibió un resultado tiene derecho a que ese resultado siga existiendo, sin
> importar qué pasó con el contrato de su laboratorio.

### Transiciones permitidas

```
   prueba ──activar──> activa
      │                  │  ▲
      │                  │  └──reactivar──┐
      │             suspender             │
      │                  ▼                │
      ├──────────>  suspendida ───────────┘
      │                  │
      │              cancelar
      │                  ▼
      └──cancelar──> cancelada ──vence el plazo──> cerrada
                          │                            │
                          └────reactivar (excepcional)─┘
```

> **REGLA** — `E-12` · De `cerrada` solo se sale por decisión explícita del
> operador y con constancia escrita. No es una reactivación normal.

> **ABIERTO** — ¿Cuánto tiempo se conservan los datos de una empresa `cerrada`
> antes de archivarlos o borrarlos? En salud suele estar regulado y hay que
> averiguarlo antes de firmar el primer contrato. *(H-5)*

## 5. Flujos propios

Los flujos que son solo de la empresa. El alta es compartido porque toca sucursal,
convenio, correlativos, roles y usuario, así que vive en `flujos/`.

| Código | Flujo | Tipo | Dónde |
|---|---|---|---|
| `F-E-1` | Alta de una empresa | compartido | `flujos/01-alta-de-un-cliente.md` |
| `F-E-2` | Activar | individual | aquí |
| `F-E-3` | Suspender | individual | aquí |
| `F-E-4` | Reactivar | individual | aquí |
| `F-E-5` | Cancelar | individual | aquí |
| `F-E-6` | Cerrar al vencer el plazo | individual, automático | aquí |
| `F-E-7` | Editar los datos de la empresa | individual | aquí |
| `F-E-8` | Exportar los datos de la empresa | individual | aquí |

### F-E-2 · Activar

**Quién:** el operador. **Cuándo:** se recibió el pago o se firmó el contrato.

1. El operador elige la empresa en `prueba` y pulsa activar.
2. El sistema exige un motivo (`contrato_firmado`, `pago_recibido`).
3. Se registra el cambio del lado comercial y se actualiza `nivel_acceso`.
4. El nivel de acceso pasa a `completo`.
5. Se avisa al administrador de la empresa.

Sin efectos sobre los datos. Es un cambio de estado y nada más.

### F-E-3 · Suspender

**Quién:** el operador. **Cuándo:** según el motivo.

1. El operador elige la empresa y **un motivo del catálogo**.
2. El sistema lee la política de ese motivo y calcula:
   - el nivel de acceso que aplica desde ya,
   - la fecha en que ese nivel cambia, si el motivo tiene plazo,
   - si hace falta avisar con antelación y cuántos días.
3. Si el motivo exige aviso previo y no se ha dado, el sistema **no suspende**:
   programa la suspensión para la fecha correspondiente y avisa.
4. El lado comercial registra motivo, plazo y quién lo hizo, y le pasa al LIS
   el nivel y la fecha resultantes. El LIS no recibe el motivo (`E-17`).
5. Las sesiones abiertas se recalculan en la siguiente petición: nadie se queda
   trabajando con permisos que ya no tiene.

> **ABIERTO** — Qué pasa exactamente con una sesión abierta depende de si la
> autenticación es con token sin estado o con sesión en base. Está sin decidir y
> bloquea escribir el paso 5 con precisión. *(H-3)*

### F-E-4 · Reactivar

**Quién:** el operador. **Cuándo:** se resolvió lo que causó la suspensión.

1. El operador elige la empresa suspendida y da un motivo de reactivación.
2. El estado vuelve a `activa` y el nivel a `completo`.
3. Queda registrado del lado comercial que estuvo suspendida y por qué. En el
   LIS queda su fila de `audit.evento`: el rastro no se borra en ninguno de los dos.

### F-E-5 · Cancelar

**Quién:** el operador, casi siempre a petición del cliente.

1. Se elige un motivo de cancelación del catálogo.
2. La política del motivo determina:
   - el **plazo de cierre** en días, contado desde hoy,
   - el nivel de acceso durante ese plazo (normalmente `solo_cierre`),
   - el nivel al vencer (normalmente `bloqueado`, con el estado `cerrada`),
   - si el cliente puede exportar sus datos y hasta cuándo.
3. Se fija y se guarda la **fecha de cierre**. Esa fecha es un dato, no un cálculo:
   si mañana cambia la política, las cancelaciones ya hechas conservan su plazo.
4. Se avisa al administrador de la empresa con la fecha y lo que puede hacer hasta
   entonces.

> **REGLA** — `E-13` · Toda cancelación tiene una fecha de cierre guardada, aunque
> el plazo sea cero. Una empresa cancelada sin fecha es un error.

### F-E-6 · Cerrar al vencer el plazo

**Quién:** el sistema, sin intervención. **Cuándo:** el día siguiente a la fecha de
cierre.

1. Una tarea diaria busca empresas `cancelada` con la fecha vencida.
2. Las pasa a `cerrada` y el nivel a `bloqueado`.
3. Aplica `nivel_al_vencer` y avisa al lado comercial para que registre el cierre.
4. Avisa al operador, no al cliente: para el cliente ya no hay nadie que reciba.

> **ABIERTO** — ¿Hay un aviso al cliente unos días antes de que venza? Parece
> obvio que sí, pero cuántos días es política.

### F-E-7 · Editar los datos de la empresa

**Quién:** el administrador de la empresa para nombre comercial, dirección y teléfono.
El operador para razón social, RTN y estado.

Cambiar el nombre no reescribe los informes ya emitidos: esos guardan su PDF y su
hash. El nombre nuevo aplica a los que se emitan de aquí en adelante.

### F-E-8 · Exportar los datos de la empresa

**Quién:** el administrador de la empresa, si su nivel de acceso lo permite; el
operador siempre.

> **PENDIENTE** — Definir qué incluye la exportación (¿pacientes, órdenes,
> resultados, informes en PDF?), en qué formato y cuánto tarda. Es un derecho del
> cliente y probablemente una obligación legal, así que no puede quedar sin definir
> mucho tiempo.

## 6. Reglas propias

> **REGLA** — `E-1` · Toda fila de toda tabla de dominio pertenece a exactamente
> una empresa. La única excepción del sistema es `plataforma.persona`.

> **REGLA** — `E-2` · La empresa se identifica en la sesión con
> `SET LOCAL lis.empresa_id`, y ese valor viene del token, nunca de lo que mande el
navegador.

> **REGLA** — `E-3` · Sin empresa en la sesión, las consultas devuelven cero filas.
> Falla cerrado, nunca abierto.

> **REGLA** — `E-4` · Una empresa no se borra. Se cancela y se cierra; sus datos
> permanecen.

> **REGLA** — `E-5` · El RTN es único cuando existe, y puede no existir.

> **REGLA** — `E-6` · Toda empresa tiene al menos una sucursal y un convenio
> predeterminado. Las dos cosas nacen con ella.

> **REGLA** — `E-7` · El estado de la empresa es de la suscripción. Que esté
> `suspendida` no significa que su laboratorio esté cerrado; para eso está
> `sucursal.activo`.

> **REGLA** — `E-8` · Solo el operador de la plataforma crea empresas.

> **REGLA** — `E-9` · No se entrega una empresa que no se pueda usar.

> **REGLA** — `E-10` · El sistema puede decir en qué umbral está cada empresa.

> **REGLA** — `E-11` · Ningún cambio de estado destruye datos clínicos.

> **REGLA** — `E-12` · De `cerrada` solo se sale por decisión explícita y con
> constancia.

> **REGLA** — `E-13` · Toda cancelación guarda su fecha de cierre.

> **REGLA** — ~~`E-14`~~ · **Retirada.** Decía que la política de un motivo se
> copia al historial al aplicarla. Dejó de valer cuando el catálogo de motivos y
> el historial salieron del LIS: la política ya no vive aquí. La reemplaza `E-17`.

> **REGLA** — ~~`E-15`~~ · **Retirada.** Decía que el historial de estados no se
> modifica ni se borra. Sigue siendo verdad, pero de una tabla que ya no vive en
> este territorio: el historial se fue a `comercial`. La reemplazan `E-17` y `E-18`.

> **REGLA** — `E-17` · El LIS no conoce el motivo. Guarda qué puede hacer la
> empresa y hasta cuándo; por qué es así vive en `comercial`.

> **REGLA** — `E-20` · El nivel de acceso de la empresa se comprueba antes que el
> permiso del usuario. Lo que decide el dueño vence al catálogo del producto.

> **REGLA** — `E-19` · La administración del laboratorio y la administración del
> sistema son dos trabajos distintos, con distinta persona, credencial, aplicación
> y tablas. No se mezclan nunca. Las acciones del dueño no están en el catálogo de
> permisos del producto, y ningún rol del laboratorio las alcanza.

> **REGLA** — `E-18` · `core` y `lab` nunca referencian `comercial`; `comercial`
> referencia `core.empresa`. Una sola dirección, y `lis_app` sin privilegios.

> **REGLA** — `E-16` · `nivel_acceso` y `fecha_cierre` en `core.empresa` solo las
> escriben las funciones de cambio de estado, y nadie más.

> **REGLA** — `E-21` · **El cliente y la empresa no son lo mismo.** La empresa es el
> inquilino del LIS; el cliente es quien firmó y a quien se le factura, y vive solo
> en `comercial`. Un cliente puede tener varias empresas; una empresa tiene un solo
> cliente vigente. `core.empresa.rtn` no es la identidad fiscal del cliente.

> **REGLA** — `E-22` · **Ninguna tabla lleva `actualizado_en`, y la base no tiene
> triggers.** Quién cambió qué y cuándo es trabajo de `audit.evento`, no de una
> fecha suelta que no sabe decir qué cambió ni quién. Nada ocurre por detrás: todo
> lo que pasa está escrito en una función que se puede leer y probar.

## 7. Cómo vive con las demás

### Con la sucursal
- **Le da:** su existencia, y el nivel de acceso. Una sucursal de una empresa
  bloqueada no opera aunque esté marcada como activa.
- **Le exige:** que exista al menos una desde el alta.
- **Al cancelar:** las sucursales no se desactivan en cascada. Desactivar es una
  decisión operativa; cancelar es comercial. Son cosas distintas.

### Con la gente que trabaja
- **Le da:** el ámbito. Un empleado es de la empresa, no de una sucursal.
- **Le exige:** nombres de usuario y de rol únicos **por empresa**, no globalmente.
- **Al suspender:** ningún usuario se desactiva. Lo que cambia es el nivel de acceso
  de la empresa entera, que se evalúa antes que el permiso del usuario.

> **REGLA** — `E-20` · El nivel de acceso de la empresa se comprueba **antes**
> que el permiso del usuario. Un administrador con todos los permisos de una
> empresa bloqueada no puede hacer nada. Es la bisagra entre las dos
> administraciones: lo que decide el dueño vence al catálogo de permisos del
> producto.

### Con el paciente
- **Le da:** el expediente. El mismo ser humano atendido por dos empresas tiene dos
  expedientes, y eso es correcto.
- **Al cerrar:** los expedientes siguen existiendo. Lo que desaparece es el acceso.

### Con el convenio
- **Le da:** el `Particular` predeterminado, para que ninguna orden exista sin
  convenio.
- **Caso especial:** un convenio puede apuntar a **otra empresa** del sistema. Hoy
  la clínica es una fila de catálogo con esa columna en nulo; el día que entre al
  sistema, apunta a su empresa y la derivación pasa de papel a electrónica.

### Con otra empresa (el enlace)
- **Le da:** la única puerta por la que un dato cruza la frontera, y esa puerta
  es una función —`core.entregar()`— y no una política de RLS.
- **Le exige:** una ruta vigente en `plataforma.enlace`, creada por el operador.
  Sin ella el mensaje **no sale**: falla en el origen.
- **La ruta es entre dos SEDES**, no entre dos empresas.

Esto **ya se reemplazó** por el enlace: una fila por **ruta entre dos sedes**,
con las dos empresas y las dos sucursales, **creada por el operador** y no por
los clientes. Unir empresas era demasiado grueso — lo que trabaja junto son las
sedes. Está en la sección 2.7.

> **ABIERTO** — Si la clínica se suspende, ¿el laboratorio deja de recibir sus
> derivaciones? Parece que sí —la clínica no puede admitir pacientes— pero las
> derivaciones ya enviadas tienen que poder completarse. Hay que decidirlo. *(H-79)*

### Con el registro de identidad
- **Le da:** personas nuevas cuando registra a alguien con documento que nadie tenía.
- **No le da:** ningún dato legible por otra empresa.
- **Al cerrar:** las personas que registró siguen existiendo. Son de la plataforma,
  no suyas.

## 8. Quién puede hacer qué

### Las dos administraciones

Antes de la tabla hay que separar dos cosas que la palabra «administrador» junta,
y que juntarlas es de los errores más caros que se pueden cometer aquí.

**La administración del laboratorio** es una función del producto. La ejerce el
administrador de la empresa: crea empleados y usuarios, define roles, abre
sucursales, ajusta precios, configura el encabezado de sus informes. Administra
**su laboratorio**, dentro de los límites que el sistema le da.

**La administración del sistema** es el negocio del dueño del producto. La ejerces
vos: das de alta empresas, acordás contratos, cobrás, suspendés por mora, cancelás.
Administrás **el servicio que vendés**, y tu ámbito son todos los clientes a la vez.

> **REGLA** — `E-19` · **Son dos administraciones distintas y no se mezclan
> nunca.** Distinta persona, distinta credencial, distinta aplicación, distintas
> tablas. Ninguna acción del dueño del sistema aparece en las pantallas ni en los
> permisos del producto, y ningún usuario del laboratorio —tampoco su
> `Administrador`— alcanza nada de la administración del sistema.
>
> En concreto, esto significa tres cosas:
>
> 1. **Las acciones del dueño no están en `plataforma.permiso`.** El catálogo de
>    permisos describe lo que un usuario del producto puede hacer, y el dueño no
>    es usuario del producto. Crear, suspender o cancelar una empresa nunca serán
>    un permiso que se le pueda otorgar a un rol.
> 2. **El dueño no necesita una cuenta dentro de ninguna empresa para trabajar.**
>    Si la necesitara, sus acciones quedarían registradas como si las hubiera hecho
>    un empleado del laboratorio, y el rastro mentiría.
> 3. **El rol `Administrador` del laboratorio es el techo de lo que el producto
>    ofrece.** Por encima no hay un rol «superadministrador»: hay otra aplicación.

**Por qué importa.** Si las dos se mezclan, aparece un botón de «suspender
empresa» en la pantalla de configuración de un laboratorio, o el dueño termina
necesitando un usuario dentro de cada empresa para hacer su trabajo. Lo primero
es un agujero de seguridad; lo segundo corrompe la auditoría. Las dos cosas se
descubren tarde, porque hasta que hay un segundo cliente todo parece funcionar.

Esta regla es también la razón por la que la consola de operador (H-16) no es
opcional: sin ella, la única forma de administrar el sistema sería desde dentro
del producto, que es justo lo que `E-19` prohíbe.

### Quién hace cada cosa

| Acción | Quién | Permiso |
|---|---|---|
| Crear la empresa | Operador de la plataforma | fuera del catálogo del producto |
| Activar, suspender, reactivar, cancelar | Operador | fuera del catálogo |
| Cerrar al vencer el plazo | El sistema | — |
| Ver los datos de su empresa | Cualquier usuario | — |
| Editar nombre comercial, dirección, teléfono | Administrador | `empresa.administrar` |
| Editar razón social, RTN | Operador | fuera del catálogo |
| Exportar los datos | Administrador, si el nivel lo permite | `empresa.exportar` |
| Ver su propio estado y nivel de acceso | Administrador | `empresa.administrar` |

> **ABIERTO** — Faltan dos permisos en el catálogo: `empresa.administrar` y
> `empresa.exportar`. Hoy editar los datos de la empresa cae bajo
> `usuario.administrar`, que es un nombre que ya no describe lo que hace.

> **RIESGO** — Las acciones del operador no están en el catálogo de permisos
> porque el operador no es un usuario del producto (`E-19`). Eso significa que
> **hoy no hay
> nada que las controle**: `crear_empresa()` es `SECURITY DEFINER` y sin
> comprobación. Hace falta un canal separado —una consola de operador con su propia
> autenticación— y hasta que exista, esa función no puede quedar expuesta en la API
> del producto. *(H-1)*

## 9. Qué puede salir mal

**El alta sin usuario administrador.** Hoy `crear_empresa` deja una empresa
perfectamente configurada a la que nadie puede entrar: cero empleados, cero
usuarios. Es el hallazgo más urgente y el que motiva la regla `E-9`. *(H-2)*

**Cualquiera crea empresas.** `crear_empresa` es `SECURITY DEFINER` y no comprueba
permisos. *(H-1)*

**Un motivo sin política es un agujero silencioso.** Si alguien suspende con un
motivo cuya política está en blanco, ¿qué nivel aplica? La respuesta tiene que ser
explícita y conservadora: **si la política no está definida, se aplica
`solo_lectura` y se avisa al operador.** Nunca `completo`, porque eso convierte un
motivo mal configurado en una suspensión que no suspende. *(H-14)*

**El plazo que se recalcula.** Si el plazo saliera de la política en vez de
guardarse, cambiar la política movería la fecha de cierre de clientes ya
cancelados. Del lado comercial hay que copiar la política al aplicarla, no
referenciarla — pero eso ya es diseño de ese módulo, no de este. Aquí solo llega
escribirla.

**No hay dónde configurar el encabezado del informe.** El requisito 8 del umbral
entregable no tiene tabla donde vivir. *(H-4)*

**No hay política de retención.** Qué pasa con los datos de una empresa `cerrada`
al cabo de un año. *(H-5)*

**Una empresa entregada a medias no se nota.** Sin la consulta de la regla `E-10`,
la única forma de saber que falta un correlativo es que un recepcionista no pueda
crear un expediente el primer día. *(H-15)*

## 10. Preguntas abiertas

1. Los **valores** de cada política: días de plazo, nivel durante el plazo, días de
   aviso previo. El mecanismo está; falta decidir los números.
2. ¿Qué pasa con las sesiones abiertas al cambiar el nivel de acceso? *(H-3)*
3. ¿La configuración del informe va en columnas de `empresa` o en tabla aparte?
   Me inclino por tabla aparte, porque va a crecer.
4. ¿Cuánto se conservan los datos de una empresa cerrada? *(H-5)*
5. ¿Cómo se le entrega la contraseña inicial al administrador? Ver el flujo de alta.
6. ¿Existe un plan o nivel de suscripción en el modelo, o eso vive en tu
   contabilidad y aquí solo se refleja el estado?
7. Si la clínica se suspende, ¿qué pasa con las derivaciones en curso?

## 11. Dónde vive en el código

### Lo que ya existe

| Qué | Dónde |
|---|---|
| Tabla | `core.empresa` — `03_core.sql` |
| Tipo de estado | `core.estado_empresa` — `01_esquemas_y_tipos.sql` |
| Alta parcial | `core.crear_empresa()` — `16_roles.sql` |
| Contexto de sesión | `core.empresa_actual()` — `05_rls_y_funciones.sql` |
| Política de aislamiento | `rls_empresa` — `05_rls_y_funciones.sql` |
| El cliente y sus contactos | `comercial.cliente`, `contacto`, `cliente_empresa` — `17_comercial.sql` |
| La ruta entre dos sedes | `plataforma.enlace` — `03_core.sql`; `crear_enlace()` y `mis_enlaces()` — `08_enlace_y_mensaje.sql` |
| Lo que cruza | `core.mensaje` — `03_core.sql`; `core.entregar()` — `08_enlace_y_mensaje.sql` |
| La referencia externa del paciente | `core.paciente_referencia` — `03_core.sql`; `anotar_referencia()` y `anular_referencia()` — `07_identidad.sql` |
| Evento a nivel de cliente | `comercial.registrar_evento_cliente()` — `17_comercial.sql` |
| Pruebas | `99_pruebas_aislamiento.sql`, pruebas 1 y 8 · `95_pruebas_comercial.sql`, pruebas 11 a 16 |

### Lo que este documento pide crear

Nada de esto existe en PostgreSQL. Pero sí está en el espejo de SQL Server
(`packages/db/schema/esquema_sqlserver.sql`), marcado como `PROPUESTA`, para
poder verlo en el diagrama junto al resto antes de construirlo.

| Qué | Para qué |
|---|---|
| ~~Esquema `comercial`~~ | **Hecho.** `17_comercial.sql`: `cliente`, `contacto`, `cliente_empresa`, `motivo`, `relacion_evento` y `contrato`, más `registrar_evento()`, `registrar_evento_cliente()` y `cerrar_vencidas()` |
| ~~Las dos columnas de `core.empresa`~~ | **Hecho.** `nivel_acceso` y `fecha_cierre` en `03_core.sql`, con el índice de cierre |
| `core.empresa_configuracion` | Encabezado del informe, logo, bloque de firma |
| `core.entregar()` | La función que escribe la fila del destinatario. **El único punto del sistema donde un dato cruza de empresa**, y por eso el que hay que revisar |
| ~~Estado `cerrada` en el enum~~ | **Hecho.** `01_esquemas_y_tipos.sql` |
| ~~Tipo `core.nivel_acceso`~~ | **Hecho.** `01_esquemas_y_tipos.sql` |
| `core.nivel_acceso_empresa()` | Calcular el nivel vigente de una empresa |
| `core.empresa_lista_para()` | Contestar en qué umbral está: entregable u operable |
| `core.suspender_empresa()` · `cancelar_empresa()` · `reactivar_empresa()` | Los flujos F-E-3 a F-E-5. Reciben nivel y fecha ya decididos, no el motivo |
| Tarea diaria de cierre | El flujo F-E-6 |
| Permisos `empresa.administrar` y `empresa.exportar` | Lo que falta en el catálogo |
