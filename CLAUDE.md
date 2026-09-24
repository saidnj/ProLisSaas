# ProLisSaas

Sistema de información de laboratorio (LIS) multiempresa. Un solo despliegue
atiende a varios laboratorios; ninguno ve nada del otro.

Primer cliente: un laboratorio clínico que **vive físicamente dentro de una
clínica pero es otra empresa**. El paciente puede llegar por la clínica o
directo al laboratorio. Esa relación no es un detalle de módulo: es estructural,
y el modelo que la resuelve está en `documentacion/flujos/06-el-paciente-entre-dos-empresas.md`.

## Dónde está cada cosa

| Carpeta | Qué es |
|---|---|
| `documentacion/` | Cómo se comporta el sistema. Territorios, flujos y hallazgos |
| `documentacion/glosario.md` | Qué significa cada término y con cuál no confundirlo |
| `documentacion/documentacion.html` | **El visor.** Doble clic: lleva los documentos dentro |
| `documentacion/visor.html` | La plantilla del visor, para servir en vivo |
| `packages/db/schema/` | El esquema. Diecinueve `.sql` que corren en orden |
| `.claude/agents/` | Los dos revisores |

El esquema manda sobre lo que existe hoy. La documentación manda sobre lo que
tiene que pasar. Cuando no coinciden, es un hallazgo, no una preferencia.

## Cómo se decide aquí

- **Nada cruza la frontera de la empresa.** RLS forzado más llave foránea
  compuesta `(id, empresa_id)`. Colgar una fila del padre equivocado es
  imposible aunque el código se equivoque.
- **Nada se comparte entre empresas: se manda un mensaje.** Cuando el hospital y
  el laboratorio atienden al mismo señor, ninguno escribe en la fila del otro.
  Cada uno anota en su propia ficha cómo lo llama el otro —`core.paciente_referencia`—
  y el que tiene los datos es el que coteja. **Ya está implementado**:
  `plataforma.persona`, `conflicto_identidad`, `core.empresa_asociada` y
  `audit.derivacion` se retiraron, y con ellas `rls_derivacion`, que era la única
  política del sistema que comparaba dos empresas. Lo que cruza son dos filas —una
  de cada lado— que escribe `core.entregar()`, **el único punto donde un dato pasa
  de una empresa a otra**. Está en `documentacion/flujos/06`.
- **Nada se borra.** `DELETE` está revocado. Se anula con motivo, se marca como
  fusionado, se emite una versión nueva.
- **La base no tiene triggers, y ninguna tabla lleva `actualizado_en`** (`E-22`).
  Quién cambió qué y cuándo es trabajo de `audit.evento`, que guarda usuario,
  acción, antes y después; una fecha suelta no sabe decir qué cambió ni quién, y
  donde más importa —los permisos de un rol— el cambio ni siquiera es un `UPDATE`.
  Nada ocurre por detrás: todo lo que pasa está escrito en una función.
- **Los estados son enumerados.** `activo` solo donde de verdad es un sí o un no.
- **Cada rol puede lo suyo y solo lo suyo**, y se comprueba dentro de las
  funciones, no solo en la pantalla.
- **Hay dos administraciones y no se mezclan.** La del laboratorio es una función
  del producto: su administrador crea usuarios, abre sucursales, ajusta precios.
  La del sistema es el negocio del dueño: dar de alta empresas, contratos, cobros,
  suspensiones. Distinta persona, credencial, aplicación y tablas. Las acciones
  del dueño **nunca** están en el catálogo de permisos, porque el dueño no es
  usuario del producto (`E-19`).
- **El LIS no sabe de negocio.** Contratos, motivos de alta y de baja, y el
  histórico de la relación con cada cliente viven en el esquema `comercial`, en
  el mismo PostgreSQL pero sin un solo privilegio para `lis_app`. Al LIS solo le
  llegan `nivel_acceso` y `fecha_cierre`, ya decididos. `core` y `lab` nunca
  referencian `comercial`; `comercial` referencia `core.empresa`.
- **El cliente no es la empresa.** La empresa es el inquilino: lo que RLS aísla,
  lo que tiene sucursales y pacientes. El cliente es quien firmó y a quien se le
  factura, y vive en `comercial.cliente`. Un cliente puede tener varias empresas;
  una empresa tiene un solo cliente vigente. `core.empresa.rtn` es con el que la
  empresa le factura a sus pacientes — **no** la identidad fiscal del cliente,
  que es `comercial.cliente.rtn` (`E-21`).
- **Español para el dominio, inglés para lo técnico.** `snake_case` en la base,
  `camelCase` en la API. Un esquema por módulo: `plataforma`, `core`, `lab`,
  `integra`, `audit`.

## Cómo se escribe la documentación

Las convenciones vivas están en `documentacion/00-como-leer.md` y mandan sobre
este archivo. En corto: once secciones por territorio, cuatro marcas
(`PENDIENTE`, `ABIERTO`, `REGLA`, `RIESGO`), reglas numeradas por inicial de
territorio (`E-`, `S-`, `G-`…), y la sección de tablas se escribe **leyendo la
base**, no de memoria.

Un número de regla nunca se reutiliza ni cambia de significado.

**Después de cambiar cualquier documento, se regenera el visor:**

```bash
cd documentacion && python3 generar_visor.py
```

`documentacion.html` lleva los documentos incrustados para que abrirlo con doble
clic funcione siempre. Si no se regenera, muestra la copia vieja y lo dice en la
esquina.

**Antes de usar una palabra nueva en un documento, se busca en
`documentacion/glosario.md`.** Si no está, se agrega ahí primero. La confusión más
cara hasta ahora fue «administrador» contra «operador».

## Antes de dar algo por terminado

Corre `/revisar`. Dos agentes de solo lectura: uno cruza los documentos entre sí,
el otro los cruza contra el esquema. Ninguno escribe nada; los hallazgos entran a
`documentacion/hallazgos.md` cuando el usuario lo decide.

## Lo que todavía no está resuelto

Está en `documentacion/hallazgos.md`, que es la lista viva. Lo más grande hoy:
no existe la consola del operador de plataforma, `core.crear_empresa()` no crea
al primer usuario, y no hay política de retención de datos clínicos.

## Contexto que no está en el código

- Analizador: **Hemax 53** (B&E Bio-Technology). 28 parámetros, 24 en el
  informe, HL7 v2.3 sobre MLLP. Falta el manual de interfaz.
- El bioquímico firma en papel, con sello. No hay portal de pacientes.
- Honduras. El RTN identifica a la empresa; el número de identidad al paciente,
  y es opcional.
- El usuario escribe en español. Contéstale en español.
