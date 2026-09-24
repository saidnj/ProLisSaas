# Cómo leer y escribir aquí

Esta carpeta define **cómo se comporta el sistema**, no cómo está escrito. El esquema
de base de datos ya existe en `ProLisSaas/packages/db/schema`; aquí se documenta el
flujo de trabajo que ese esquema tiene que sostener.

## Para qué sirve

Tres cosas, en este orden de importancia:

1. **Encontrar errores antes de escribir código.** Describir un flujo con detalle
   obliga a contestar preguntas que el esquema deja abiertas. Cada vez que una
   pregunta no tenga respuesta, es un hallazgo.
2. **Ser el contexto que Claude lee.** Estos documentos van a alimentar el
   `CLAUDE.md` del proyecto y las reglas por módulo.
3. **Ser el contrato con quien programe.** Incluido tú dentro de seis meses.

## Cómo está organizado

- **Territorios** (`core/`) — una pieza del núcleo por documento. Cómo vive por su
  cuenta y cómo vive con las demás.
- **Flujos** (`flujos/`) — recorridos completos que atraviesan varios territorios.
  Un territorio dice *qué es la sucursal*; un flujo dice *qué pasa cuando se da de
  alta un cliente*.
- **Hallazgos** (`hallazgos.md`) — la lista viva de lo que encontramos roto o sin
  decidir. Se alimenta de **«Qué puede salir mal»** y **«Preguntas abiertas»** de
  cada territorio, y de **«Qué puede fallar»** de cada flujo.

Cada territorio tiene las mismas once secciones, con los mismos nombres y en el
mismo orden. Que sean iguales es lo que permite comparar y notar lo que falta.

Un territorio puede **añadir una sección extra** cuando el material lo pide, pero
nunca quita ni renombra ninguna de las once. Hoy ninguno la usa: `01-la-empresa.md`
llegó a tener una y se retiró cuando el catálogo de motivos salió del LIS. Por eso **las referencias entre documentos van por nombre y
nunca por número**: «la sección de reglas propias», no «la sección 6». El número
depende de si ese documento añadió algo; el nombre, no.

Las once, en orden:

| # | Sección | Qué contesta |
|---|---|---|
| 1 | Qué es y por qué existe | Para qué está aquí esta pieza |
| 2 | Las tablas y sus campos | El diccionario, leído de la base |
| 3 | Quién la crea y con qué datos | De dónde salen las filas |
| 4 | Ciclo de vida y estados | Cómo cambia con el tiempo |
| 5 | Flujos propios | Los recorridos que empiezan y terminan aquí |
| 6 | Reglas propias | Lo que siempre es verdad, numerado |
| 7 | Cómo vive con las demás | Qué da, qué exige, qué pasa si la otra cambia |
| 8 | Quién puede hacer qué | Los permisos |
| 9 | Qué puede salir mal | Donde se cazan los problemas |
| 10 | Preguntas abiertas | Lo que falta decidir |
| 11 | Dónde vive en el código | Lo que existe y lo que se pide crear |

La sección **«Las tablas y sus campos»** es el diccionario del territorio: columna
por columna, con tipo, nulos, valor por defecto, para qué sirve y qué resuelve, más
las llaves foráneas en las dos direcciones. Se escribe **leyendo la base**, no de
memoria, y separa lo que ya existe de lo que el documento propone crear.

## Qué se copia del laboratorio y qué no

El laboratorio lleva años trabajando y hace las cosas de una manera. Parte de esa
manera es **cómo funciona el trabajo** y hay que respetarla; parte es **cómo se
sobrevive sin sistema** y no hay que heredarla. Distinguirlas es la mitad del
trabajo de estos documentos.

La pregunta que las separa: *¿por qué lo hacen así?*

- Si la respuesta habla del **paciente, la muestra, el médico o la ley** — es un
  requisito. El sistema se adapta. «El bioquímico firma cada informe» no se
  negocia porque responde de él con su colegiación.
- Si la respuesta habla de **papel, tiempo, memoria o de que alguien se acuerde**
  — es un parche. El sistema quita la causa, así que no hay que copiar el efecto.

El ejemplo que originó esta sección: el laboratorio **reinicia su numeración cada
año**. La razón no es contable ni legal — es que las boletas se escriben a mano, y
con lápiz nadie copia un número de nueve caracteres cuatrocientas veces al año.
Con papel, reiniciar es lo sensato. Con el sistema, el número lo escribe la
máquina y su longitud deja de costar nada, así que la razón desaparece y la regla
`S-11` puede decir lo contrario de lo que hace el laboratorio hoy —sin
contradecirlo, porque le quita el problema en vez de negárselo.

Un parche heredado es caro de dos maneras: cuesta construirlo, y después cuesta
quitarlo porque ya está en las pantallas y en la costumbre.

**Cuando una decisión venga de aquí, se escribe la razón.** No basta con decir
«el laboratorio lo hace así»: hay que decir por qué lo hace así, porque de eso
depende si se copia o no.

## Cómo se llaman las cosas

Las palabras viven en **`glosario.md`**, que es el documento hermano de este. Ahí
están la nomenclatura técnica, qué significa cada término y —lo más importante—
con cuál no hay que confundirlo.

Dos reglas sobre su uso:

1. **Antes de meter una palabra nueva en un documento, se busca en el glosario.**
   Si no está, se agrega ahí primero.
2. Cuando la palabra del laboratorio y la de la base no coinciden, **manda la del
   laboratorio en documentos y pantallas, y la de la base en el código**. El
   glosario dice cuál es cuál. Lo que no se permite es usar las dos como si fueran
   intercambiables sin decirlo.

La confusión que más caro nos ha salido: **«administrador» no es «operador»**. El
administrador es un empleado del laboratorio; el operador sos vos, dueño del
sistema, y no sos usuario del producto. Ver `E-19`.

La segunda: **«cliente» no es «empresa»**. La empresa es el inquilino —lo que RLS
aísla, lo que tiene sucursales y pacientes—; el cliente es quien firmó y a quien se
le factura, y vive en `comercial.cliente` (`E-21`). No se usa «cliente» para
**definir** la empresa, ni para nombrar sus datos o su gente: se dice *el
administrador de la empresa*, porque el cliente no tiene administradores, tiene
contactos. En prosa coloquial —«el primer cliente», «tu cartera de clientes»— se
entiende por contexto y se deja.

## Las cuatro marcas

Se escriben como citas y el visor las pinta distinto:

> **PENDIENTE** — Esta sección todavía no está escrita. El visor solo la cuenta
> como hueco cuando es lo **primero** que aparece bajo el encabezado, así que una
> sección ya escrita no se castiga por tener preguntas sueltas.

> **ABIERTO** — Una decisión que falta tomar dentro de una sección que ya está
> escrita. No cuenta contra el avance, pero sí se copia a `hallazgos.md`.

> **REGLA** — Algo que siempre es verdad. Va numerado con la inicial del territorio:
> `E-1` para empresa, `S-3` para sucursal. Los flujos las citan por ese código.

> **RIESGO** — Algo que puede salir mal, o una decisión que envejece mal. Todo lo
> que se marque así se copia a `hallazgos.md`.

## Flujos individuales y compartidos

Un **flujo individual** empieza y termina dentro de un territorio: suspender una
empresa, crear un permiso, desactivar una sucursal. Se escribe en **«Flujos
propios»** del documento de ese territorio.

Un **flujo compartido** atraviesa varios: dar de alta un cliente toca empresa,
sucursal, correlativos, convenio, roles, empleado y usuario. Se escribe en
`flujos/`, y cada territorio implicado lo menciona en su **«Flujos propios»** con
un enlace.

La prueba para decidir: *si al describir el flujo tengo que explicar una pieza que
no es la de este documento, es compartido.*

Los flujos se numeran `F-<prefijo del territorio>-<n>`: `F-E-3` es el tercer flujo
de la empresa. Los compartidos llevan el número del archivo: `F1-1` es la primera
regla del flujo `flujos/01`.

## Cómo numerar las reglas

| Territorio | Prefijo |
|---|---|
| La empresa | `E-` |
| La sucursal | `S-` |
| La gente que trabaja | `G-` |
| El paciente | `P-` |
| La identidad compartida | `I-` |
| Por dónde entra | `C-` |
| La visita | `V-` |
| El documento | `D-` |
| El rastro | `A-` |

Una regla nunca cambia de número. Si deja de valer, se marca como retirada y se
escribe la que la reemplaza con un número nuevo.

## Cómo ver esto

Doble clic en **`abrir-visor.bat`**. Levanta un servidor local y abre el navegador.
Deja esa pestaña abierta: se refresca sola cada dos segundos, así que cualquier
cambio en un `.md` aparece sin que hagas nada.

El navegador no puede leer archivos del disco directamente por seguridad, por eso
hace falta el servidor. Abrir `visor.html` con doble clic no funciona.
