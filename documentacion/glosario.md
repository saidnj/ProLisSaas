# Glosario

Las palabras que usamos, qué significa exactamente cada una y con cuál **no** hay
que confundirla.

Existe porque la mitad de los errores de diseño que hemos encontrado empezaron por
una palabra que dos documentos usaban con dos sentidos. «Administrador» estuvo a
punto de costarnos un agujero de seguridad, y «prueba» todavía nombra dos cosas
distintas.

**Cómo se usa.** Antes de meter una palabra nueva en un documento, se busca aquí.
Si no está, se agrega aquí primero. Si está con otro sentido, se usa el de aquí o
se cambia aquí — pero no se usan las dos a la vez.

Cada entrada dice, cuando aplica, **cómo se llama en la base**. Ese nombre es el
que manda para cualquier identificador de código; la palabra en español es la que
manda en documentos y pantallas.

---

## Las que más se confunden

Esta tabla es el corazón del glosario. Si solo vas a leer una parte, que sea esta.

| No es lo mismo | Ni esto | La diferencia en una línea |
|---|---|---|
| **Operador** | **Administrador** | El operador sos vos, dueño del sistema. El administrador es un empleado del laboratorio. `E-19` |
| **Empresa** | **Sucursal** | La empresa es el laboratorio como inquilino del sistema; la sucursal es el local donde se atiende |
| **Cliente** | **Empresa** | El cliente es quien firmó el contrato y a quien le facturás. La empresa es el inquilino del LIS. Un cliente puede tener varias. `E-21` |
| **RTN de la empresa** | **RTN del cliente** | Con el primero el laboratorio le factura a sus pacientes. Con el segundo vos le facturás a él. Casi siempre el mismo número, y por eso se confunden |
| **Papel** (contacto) | **Rol** (usuario) | El papel dice para qué llamarle a un contacto del cliente. El rol dice qué puede hacer un usuario dentro del LIS |
| **Referencia externa** | **Expediente** | El expediente es mi número para este paciente. La referencia externa es el número que le da la otra empresa, anotado en mi ficha |
| **Empleado** | **Usuario** | El empleado es quien trabaja ahí; el usuario es su cuenta para entrar. Puede haber empleado sin usuario |
| **`id`** | **Número** | El `id` es interno y nadie lo ve. El número —`LFO-000123`— es el que el paciente tiene en la mano |
| **Folio** | **Número** | El folio identifica un mensaje entre dos empresas y es un `uuid`. El número identifica una boleta y lo lee un humano |
| **Derivación** | **Mensaje** | Derivar es lo que hacés: mandar al paciente o lo suyo. El mensaje es la fila con la que se hace, una de cada lado |
| **Estado** | **Nivel de acceso** | El estado dice en qué punto de la relación comercial está la empresa. El nivel dice qué puede hacer hoy. `E-7` |
| **Prueba** (examen) | **Prueba** (estado) | Un hemograma es una prueba; una empresa en evaluación está en estado `prueba`. Misma palabra, dos mundos |
| **Convenio** | **Enlace** | El convenio es un acuerdo de precios y cobro, y lo crea el laboratorio. El enlace es la ruta entre dos sedes de empresas distintas, y lo crea el operador |
| **Validar** | **Emitir** | Validar es que el bioquímico aprueba un resultado. Emitir es generar el informe con los resultados ya validados |
| **Muestra** | **Orden** | La orden es lo que se pidió; la muestra es el tubo. Una orden puede necesitar varios tubos |
| **Anular** | **Borrar** | Anular deja la fila con un motivo. Borrar no existe: `DELETE` está revocado |
| **Corregir** | **Editar** | Corregir crea una versión nueva y retira la anterior. Editar sobreescribe, y eso aquí casi nunca se permite |

---

## Las personas

### Operador · dueño del sistema
Vos. El que vende y administra el servicio. **No es usuario del producto**, no
tiene cuenta en ninguna empresa y sus acciones nunca están en el catálogo de
permisos. Da de alta empresas, acuerda contratos, cobra, suspende. Trabaja desde
una aplicación aparte, sobre el esquema `comercial`.

*Nunca se le llama «administrador».* Ver `E-19`.

### Administrador
Un **empleado del laboratorio** con el rol `Administrador`. Configura *su*
laboratorio: crea empleados y usuarios, define roles, abre sucursales, ajusta
precios, configura el encabezado de sus informes. Es el techo de lo que el
producto ofrece: por encima no hay un «superadministrador», hay otra aplicación.

En la base: una fila de `core.usuario` con un `rol_id` que apunta a la fila de
`core.rol` llamada `Administrador`.

### Empleado
Quien trabaja en el laboratorio. `core.empleado`. Tiene nombre, cargo y, si es
bioquímico, número de colegiación. **Existe aunque no pueda entrar al sistema**:
un empleado sin usuario es normal.

### Usuario
La cuenta con la que alguien entra. `core.usuario`. Cuelga de un empleado y tiene
un rol. Estados: `activo`, `suspendido`, `bloqueado`.

### Bioquímico
El profesional que **firma** los informes. No es un permiso: es un empleado con
número de colegiación. Un permiso no convierte a nadie en bioquímico — el sistema
comprueba las dos cosas antes de dejar validar.

### Analista
Procesa muestras y captura resultados. **No los aprueba.** Esa separación es a
propósito.

### Recepción
Admite pacientes, crea órdenes, en un laboratorio chico toma muestras, y entrega
informes. Es la puerta de entrada y la de salida.

### Paciente
A quien se le hacen los exámenes, **dentro de una empresa**. `core.paciente`.
Cada empresa guarda su propia copia del nombre: si una lo escribió mal, el error
se queda ahí.

### Persona
*Se retiró.* `plataforma.persona` guardaba la identidad del paciente compartida
entre empresas, sin nombres, para saber que el de la clínica y el del laboratorio
eran el mismo señor. **Ya no existe**: el modelo decidido no comparte nada entre
empresas. Cada una anota en su propia ficha cómo la llama la otra — eso es la
**referencia externa**. `H-73`.

### Referencia externa
Cómo llama la OTRA empresa a mi paciente. `core.paciente_referencia`. Es un dato
externo anotado sobre lo propio, como el número de póliza de un seguro: **no es
llave foránea** hacia el expediente ajeno y no hay integridad referencial entre
empresas.

Nace de una **confirmación humana con el paciente presente**, o de un cotejo de
dos factores que el sistema resolvió sin dudar. Nunca de elegir en una lista
(`F6-2`), y por eso el usuario que confirma es obligatorio.

Si se confirmó mal, la anula quien la escribió —con motivo, porque nada se
borra— y escribe otra. El daño es local: nadie más se entera. Compará con la
identidad compartida, donde el mismo error lo heredaban las dos empresas.

### Médico solicitante
Quien pidió los exámenes. **Hoy no existe en la base**: `core.medico` y
`core.episodio.medico_solicitante_id` se retiraron (`H-98`). Se decide cuando
esté armado el flujo de admisión, porque ahí se ve si hace falta una ficha o
basta un campo con lo que dice la boleta. Nunca es un usuario del sistema.

---

## Las organizaciones

### Empresa · inquilino
El laboratorio como unidad del sistema. `core.empresa`. **Es la unidad de
aislamiento**: todo lo que existe pertenece a una empresa y solo a una.
Estados: `prueba`, `activa`, `suspendida`, `cancelada`, `cerrada`.

**No es el cliente.** El cliente es quien firmó y a quien se le factura, y vive en
`comercial`. Casi siempre hay uno de cada uno y por eso se confunden, pero un
cliente puede tener varias empresas. Ver `E-21`.

Su `rtn` es con el que **ella** le factura a sus pacientes, no la identidad fiscal
de quien contrató.

### Cliente
Quien te contrató a vos. `comercial.cliente`. Persona natural o sociedad, con el
RTN al que le emitís la factura. Vive solo en el esquema `comercial`: el
laboratorio no sabe que existe y `lis_app` no tiene un solo privilegio ahí.

Un cliente puede tener **varias empresas** —un grupo con dos laboratorios que no se
ven entre sí— y de ahí cuelga el contrato. La unión es `comercial.cliente_empresa`,
con vigencia, porque un laboratorio se puede vender.

**La regla de la palabra.** «Cliente» a secas es `comercial.cliente`. Cuando se
habla del inquilino se dice **empresa**, y a su gente se le llama *el administrador
de la empresa*, nunca «del cliente» — el cliente no tiene administradores, tiene
**contactos**.

En prosa coloquial la palabra se entiende por contexto y no hace falta cambiarla:
«el primer cliente», «tu cartera de clientes», «el cliente avisó con antelación»
son correctas. Lo que no se hace es usarla para **definir** la empresa ni para
nombrar sus datos o su gente.

### Contacto
La persona a la que se le llama por un cliente. `comercial.contacto`. Varios por
cliente, cada uno con su **papel**.

### Papel (de un contacto)
Para qué sirve un contacto: `firma`, `pago`, `tecnico`, `general`. Se llama papel y
**no rol** a propósito — `rol` ya nombra lo que puede hacer un usuario dentro del
LIS, y son mundos distintos.

*No confundir con el papel de la boleta*, que en estos documentos aparece más
seguido: «el bioquímico firma en papel», «la derivación pasa de papel a
electrónica». Se distingue por el contexto y siempre lleva «papel **de**» cuando es
el del contacto.

### Sucursal · sede
El lugar físico donde se atiende. `core.sucursal`. **Sede es sinónimo**; el
nombre que vale para el código es `sucursal`. De aquí cuelgan los correlativos,
los precios de sede, los equipos y los accesos del personal.

### Clínica
En el caso del primer cliente: **otra empresa**, no una sucursal del laboratorio.
El laboratorio vive físicamente dentro de ella, pero son dos entidades legales.
Llega al sistema por convenio o por derivación.

### Convenio
El acuerdo de precios y cobro con quien paga. `core.convenio`. Toda orden tiene
uno, incluso la del paciente que llega y paga en el mostrador: para eso está el
convenio `Particular`, que nace con cada empresa.

### Empresa asociada
*Se retiró.* `core.empresa_asociada` se anunciaba como la autorización para que una
empresa le derivara a otra, y **no era un acuerdo**: la fila la escribía el que iba
a derivar, sobre sí mismo, y la otra parte ni la veía ni la podía quitar. Además
unía EMPRESA con EMPRESA, cuando lo que trabaja junto son las **sedes**.

La reemplazó el **enlace**. `H-76`, `H-78`.

### Enlace (entre dos empresas)
Una **ruta entre dos sedes** de dos empresas distintas. `plataforma.enlace`
(propuesta). Guarda las dos empresas y las dos sucursales, y **la crea el
operador**, no las empresas.

*No confundir con el **enlace de activación**,* el que se le manda por correo a un
empleado para que estrene su cuenta (`core.activacion_usuario`, `H-17`). Son la
misma palabra y dos cosas sin relación; **falta decidir cuál se queda con ella**
antes de que la pieza exista. *(H-80)*

**Es sede a sede, no empresa a empresa.** Unir empresas es demasiado grueso: si A
tiene las sedes A1 y A2 y lo que trabaja junto es A1 con B2, un vínculo «A trabaja
con B» hace que lo de A2 también le caiga a B, y B2 queda inalcanzable. Cada
pareja de sedes es otro enlace.

**La crea el operador** porque para declararla una empresa tendría que teclear el
RTN y el código de sede del otro, y eso es información confidencial que no es
suya. Así ninguna empresa escribe nunca el identificador de otra.

`lis_app` **no lee la tabla**: pregunta por función, y la función contesta solo su
lado —«podés mandarle al Laboratorio Ochoa desde tu sede A1»—. La sucursal del
otro no la ve nunca.

El enlace **no dice cuál sede está físicamente adentro de cuál**, a propósito: no
sostiene ninguna regla, y decirlo sería apuntar al edificio ajeno. La vecindad
vive en `core.sucursal.direccion`, como texto. Ver `01-la-empresa.md` 2.7.

*«¿Estas dos empresas trabajan juntas?»* no se guarda: **se deduce** de que haya al
menos una ruta vigente entre ellas.

**Ya existe** en `plataforma.enlace`. Reemplazó a `empresa asociada`, que se retiró
**sin sustituto a nivel de empresa**.

---

## El recorrido de un paciente

En el orden en que ocurre.

| Paso | Palabra | En la base | Qué contesta |
|---|---|---|---|
| 1 | **Expediente** | `core.paciente.expediente` | ¿Quién es esta persona? Uno para toda su vida |
| 2 | **Episodio** · visita | `core.episodio` | ¿Qué pasó ese día? |
| 3 | **Boleta** · orden | `lab.orden` | ¿Qué se le va a hacer? |
| 4 | **Muestra** | `lab.muestra` | ¿Qué hay en este tubo? |
| 5 | **Resultado** | `lab.resultado` | ¿Qué salió? |
| 6 | **Informe** | `core.informe` | ¿Qué se entrega? |
| 7 | **Entrega** | `core.entrega` | ¿A quién y cuándo se le dio? |

### Boleta
El papel con los exámenes que se le van a hacer al paciente. **Es la palabra del
laboratorio**, y la que va en pantallas y documentos. En la base se llama
`lab.orden`.

### Episodio
Una visita. Todo lo que pasó un día concreto, en una sucursal concreta. Es el
tronco del que cuelgan las ramas: hoy laboratorio, mañana imagenología.
Estados: `abierto`, `cerrado`, `anulado`.

### Muestra
El tubo. Se identifica por **código de barras**, no por correlativo, porque quien
lo lee es el analizador. Estados: `pendiente`, `tomada`, `recibida`, `rechazada`,
`en_proceso`, `procesada`.

### Resultado
El valor de un analito. Estados: `pendiente`, `preliminar`, `validado`,
`corregido`, `repetir`. **Nunca se edita**: corregir crea una fila nueva y retira
la vigencia de la anterior.

### Informe
El documento que recibe el paciente, firmado y sellado. `core.informe`, con sus
versiones en `core.informe_version`. Estados: `borrador`, `emitido`, `corregido`,
`anulado`.

### Derivación
Mandar un paciente, o lo suyo, de una empresa a otra. **La palabra se queda; la
tabla no.** `audit.derivacion` es hoy una sola fila que ven las dos empresas, con
estados de negociación —`solicitada`, `aceptada`, `rechazada`, `completada`— y la
reemplaza el **mensaje**. `H-73`.

### Mensaje
Lo que cruza entre dos empresas. `core.mensaje`. **Una fila de cada
lado**, cada una con su `empresa_id` y su RLS de siempre: ninguna fila compartida
y ninguna llave hacia el otro inquilino. Las escribe una función, que pasa a ser
el único punto del sistema donde un dato cruza de empresa.

Tipos: `solicitud`, `consulta_historial`, `respuesta_historial`, `resultado`,
`correccion`, `aviso`.

**Un mensaje no se acepta, se recibe.** La aceptación se mudó una sola vez a la
relación (ver **Enlace**), así que los estados son de entrega: lo enviado va de
`pendiente` a `entregado`, y lo recibido de `recibido` a `trabajado`.

### Folio
El identificador de un mensaje, el mismo de los dos lados. `uuid`, no el
`mensaje_id`: si viajara el número de secuencia le contaría a la otra empresa
cuántos mensajes mandás. *No confundir con el **número** de la boleta*, que es el
que el paciente tiene en la mano.

### Sin enlace
Lo que pasa cuando alguien intenta mandar por una ruta que no existe: **el mensaje
no sale**. La función lo rechaza en el origen, en vez de salir y caer en una
bandeja del otro lado. Falla más temprano y más cerca de quien se equivocó.

*Hubo un diseño anterior con una bandeja de «remitente nuevo» donde caía lo que
llegaba sin ruta. Se murió cuando el enlace pasó a crearlo el operador: sin enlace
ya no hay salida, así que no hay nada que recibir.*

---

## Los números

### `id`
El número interno de una fila: `episodio_id`, `paciente_id`. Lo genera la base,
sirve para las llaves foráneas, y **nadie lo ve nunca**. Si se ve, es un error de
diseño.

### Correlativo · contador
La tabla que reparte los números visibles. `core.correlativo`. **Contador es
sinónimo**; el nombre del código es `correlativo`. Guarda el prefijo, el ancho y
el último valor emitido. Cinco tipos: `expediente`, `episodio`, `informe`,
`orden`, `muestra`.

### Número
Lo que el paciente tiene en la mano: `LFO-000123`. Sale del correlativo, se
congela en la fila que nombra, y **no se repite jamás**. Por eso los correlativos
no se reinician (`S-11`).

### Código de barras
El identificador del tubo. `lab.muestra.codigo_barra`. Único por empresa. No es
un correlativo: lo lee una máquina, no un humano.

---

## El aislamiento entre empresas

### Multiempresa
Un solo despliegue atiende a varios laboratorios y ninguno ve nada del otro. La
palabra en inglés es *multi-tenant*; en los documentos se dice multiempresa.

### RLS · seguridad a nivel de fila
El mecanismo de PostgreSQL que filtra las filas antes de que la consulta las vea.
Está **forzado**, así que ni el dueño de la tabla se lo salta. Es lo que hace que
«los datos de esta empresa» no dependa de que el código se acuerde de filtrar.

### `lis_app`
El rol de base con el que se conecta la aplicación. No es superusuario, no puede
saltarse RLS y no tiene `DELETE` en ninguna tabla.

### Contexto de sesión
Las dos variables que la API fija al abrir cada transacción: `lis.empresa_id` y
`lis.usuario_id`. Vienen del token, **nunca de lo que mande el navegador**. Sin
empresa en la sesión, las consultas devuelven cero filas.

### Token · JWT
La credencial que el API le entrega al navegador cuando alguien entra, y que el
navegador devuelve en cada petición siguiente. *JSON Web Token*: tres partes
separadas por puntos —cabecera, contenido y firma— donde **las dos primeras se leen
sin ninguna clave**. Cualquiera puede ver qué dice; nadie puede cambiarlo, porque la
firma se calcula con un secreto que solo tiene el servidor.

**Con qué no confundirlo**: no es la contraseña, ni la contiene. Dice *quién sos*,
no *cómo lo demostraste*. Y el back **no lo guarda en ninguna parte**: lo firma y lo
olvida; cuando vuelve, recalcula la firma y compara.

En el código: se firma en `auth.service.ts` y se verifica en `auth/jwt.guard.ts`.

### Las tres paredes
Los tres controles que atraviesa una petición, cada uno contestando una pregunta que
los otros no saben contestar: **RLS** dice *de qué empresa son estas filas*,
`core.usuario_puede()` dice *si este rol puede hacer esta acción*, y
`core.sesion_vigente()` dice *si esta sesión todavía vale*. Las tres viven en la
base, no en la aplicación. Están en `flujos/07-como-se-entra.md`.

### `SECURITY DEFINER`
Una función que corre con los privilegios de **su dueño** en vez de los de quien la
llama. Como el dueño es `postgres`, que es superusuario, esas funciones **se saltan
RLS**. Es una grieta deliberada y por eso cada una está acotada: sin parámetros
libres, con el `search_path` fijo y con `REVOKE` de `PUBLIC`.

Hoy hay seis. Las dos del flujo de entrada tienen razones distintas:
`core.buscar_credencial()` porque al entrar todavía no hay contexto que poner, y
`core.sesion_vigente()` porque sin ella la política de `core.usuario` se llamaría a
sí misma hasta reventar la pila.

### InitPlan
Cómo PostgreSQL evalúa una función envuelta en `(SELECT ...)` dentro de una
política: **una vez por consulta** en vez de una vez por fila. No es un detalle de
estilo — medido sobre 300.000 filas, la diferencia es 21 ms contra 894.

### Interceptor
Del lado de Angular, una pieza que se mete entre `HttpClient` y la red y ve todas
las peticiones que salen y todas las respuestas que vuelven. Hay dos:
`token.interceptor.ts` le pega la cabecera `Authorization`, y `error.interceptor.ts`
traduce un 401 en «cerrar sesión e ir al login».

**Por qué ahí y no en un servicio**: porque el cliente generado desde el OpenAPI no
va a pasar por nuestro `ApiService`, pero sí por `HttpClient`. Lo que debe aplicarse
a *todas* las peticiones no puede vivir en un envoltorio que alguien puede esquivar.

### Guard
Del lado de NestJS, la pieza que corre **antes** de cualquier controlador y decide
si la petición sigue. El nuestro —`auth/jwt.guard.ts`— verifica la firma del token y
deja la sesión en la petición. Está puesto de forma **global**: todo pide token
salvo lo marcado con `@Publico()`, para que olvidarse signifique quedar cerrado de
más y no abierto de más.

### Llave foránea compuesta
`(tabla_id, empresa_id)` en vez de solo `(tabla_id)`. Hace **imposible** colgar
una fila de un padre de otra empresa, aunque el código se equivoque.

### Esquema
La división del sistema por módulos. Seis, y los seis existen:

| Esquema | Qué contiene |
|---|---|
| `plataforma` | Por encima de las empresas: catálogo del producto e identidad compartida |
| `core` | El núcleo: quién, dónde y cuándo |
| `lab` | La rama de laboratorio clínico |
| `integra` | Los analizadores y lo que mandan |
| `audit` | El rastro y el puente entre empresas |
| `comercial` | Tu negocio: clientes, contactos, contratos, altas y bajas. `lis_app` no tiene un solo privilegio aquí. `E-17`, `E-18`, `E-21` |

---

## El producto

### Módulo
Una parte del producto que se enciende por sucursal. Hoy dos: `core` y
`lab_clinico`.

### Permiso
Una acción del dominio que un usuario puede o no hacer: `resultado.validar`,
`orden.crear`. `plataforma.permiso`. **Solo describe acciones del usuario del
producto** — nunca del operador.

### Rol
Un conjunto de permisos, **por empresa**. `core.rol`. Cada empresa nace con
cuatro y desde ahí son suyos: cambiarlos no afecta a nadie más.

### Datos maestros del alta
Con qué nace una empresa: los cuatro roles y sus permisos, el convenio
`Particular`, los cinco correlativos, el módulo de laboratorio. Viven **dentro de
`core.crear_empresa()`** y no en tablas de plantilla.

*Hubo dos tablas —`plataforma.rol_plantilla` y `rol_plantilla_permiso`— y se
quitaron: no son parte de RBAC —el modelo es usuario → rol → permisos— sino
semilla, y una semilla que se usa cada varios meses no necesita dos tablas que
puedan desincronizarse de la realidad.*

**Todavía no están decididos**, solo escritos para poder arrancar. Se declaran
cuando `core` esté verificado entero. *(H-91)*

### Nivel de acceso
Qué puede hacer una empresa **ahora mismo**: `completo`, `solo_cierre`,
`solo_lectura`, `bloqueado`. Lo decide el lado comercial y lo escribe en
`core.empresa`. Se comprueba **antes** que el permiso del usuario (`E-20`).

### Estado
En qué punto de la relación comercial está la empresa. No decide qué se puede
hacer: eso lo decide el nivel de acceso.

---

## Cómo se escriben estos documentos

### Territorio
Una pieza del núcleo con su documento propio: la empresa, la sucursal, la gente.
Nueve en total. Cada uno tiene las mismas once secciones.

### Flujo individual
Empieza y termina dentro de un territorio. Se escribe en «Flujos propios» de ese
documento. Se numera `F-<inicial>-<n>`: `F-E-3` es el tercero de la empresa.

### Flujo compartido
Atraviesa varios territorios. Se escribe en `flujos/`, y cada territorio implicado
lo menciona con un enlace. Sus reglas se numeran `F1-1`, `F2-1`…

### Regla
Algo que siempre es verdad, numerado con la inicial del territorio: `E-` empresa,
`S-` sucursal, `G-` gente, `P-` paciente, `I-` identidad, `C-` por dónde entra,
`V-` visita, `D-` documento, `A-` rastro.

**Un número nunca se reutiliza ni cambia de significado.** Si una regla deja de
valer, se marca como retirada y se escribe la que la reemplaza con un número
nuevo.

### Hallazgo
Algo roto o sin decidir. Se numera `H-n` y vive en `hallazgos.md`.

### Las cuatro marcas

| Marca | Qué significa |
|---|---|
| `PENDIENTE` | La sección no está escrita. Cuenta como hueco solo si es lo primero bajo el encabezado |
| `ABIERTO` | Falta una decisión dentro de una sección ya escrita. Se copia a `hallazgos.md` |
| `REGLA` | Algo que siempre es verdad. Va numerado |
| `RIESGO` | Algo que puede salir mal, o una decisión que envejece mal. Se copia a `hallazgos.md` |
