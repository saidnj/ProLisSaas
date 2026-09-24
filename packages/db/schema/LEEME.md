# Esquema del núcleo · ProLisSaas

PostgreSQL 15+. Los archivos se ejecutan en orden; cada uno depende del anterior.

| Archivo | Qué contiene |
|---|---|
| `01_esquemas_y_tipos.sql` | Los esquemas `plataforma`, `core`, `audit` y todos los tipos enumerados |
| `02_plataforma.sql` | Catálogo de módulos y permisos, y el registro de identidad (`persona`) |
| `03_core.sql` | El núcleo: empresa, sucursal, usuario, paciente, convenio, episodio, informe |
| `04_audit.sql` | Auditoría y derivaciones entre empresas |
| `05_rls_y_funciones.sql` | Rol de aplicación, políticas RLS y funciones del núcleo |
| `06_semillas.sql` | Módulos y el catálogo de permisos |
| `07_identidad.sql` | Conflictos de identidad y el único camino para registrar un paciente |
| `10_lab_tipos.sql` | Esquemas `lab` e `integra`, y los tipos de la rama |
| `11_lab_catalogo.sql` | Áreas, tipos de muestra, analitos, pruebas, precios y rangos |
| `12_lab_operacion.sql` | Orden, muestra, rechazo, ítem de orden, resultado, valor crítico |
| `13_integra.sql` | Equipos, mapeo de códigos y mensajes crudos |
| `14_lab_rls_y_funciones.sql` | RLS de la rama y las funciones de rango, precio, validación y corrección |
| `15_lab_semillas.sql` | Permisos del módulo y `lab.sembrar_hematologia()`: los 24 analitos del Hemax 53 |
| `08_enlace_y_mensaje.sql` | `crear_enlace()`, `mis_enlaces()` y `entregar()`: lo único que cruza entre dos empresas |
| `16_roles.sql` | `core.crear_empresa()`: el alta completa, con los cuatro roles y sus permisos |
| `17_comercial.sql` | El esquema `comercial`: la relación con cada cliente. **No es del laboratorio** |
| `95_pruebas_comercial.sql` | Que el laboratorio no toque lo que decide su dueño, y al revés |
| `96_pruebas_permisos.sql` | Que cada rol pueda hacer lo suyo y solo lo suyo |
| `97_pruebas_identidad.sql` | Que el error de una empresa al registrar no contamine a las otras |
| `98_pruebas_lab.sql` | El flujo completo, del mensaje del equipo al informe corregido |
| `99_pruebas_aislamiento.sql` | Las ocho pruebas de aislamiento del núcleo |

Y aparte, para ver el diseño en un diagrama:

| Archivo | Qué contiene |
|---|---|
| `generar_sqlserver.py` | Lee la base PostgreSQL viva y escribe el espejo de SQL Server |
| `esquema_sqlserver.sql` | **Generado.** El espejo para abrir un diagrama en SSMS |

`esquema_sqlserver.sql` no se edita a mano. Se regenera:

```bash
python3 generar_sqlserver.py > esquema_sqlserver.sql
```

Un espejo escrito a mano se desincroniza y engaña: al generarlo por primera vez
resultó que le faltaban tres tablas y que `plataforma.persona` todavía mostraba
los nombres del paciente —lo contrario de lo que decidió el diseño de identidad—.
Quien mirara el diagrama para entender el sistema habría entendido mal.

El espejo incluye, marcadas como `PROPUESTA`, las tablas que el documento de la
empresa pide crear y todavía no existen. Están para poder decidir sobre su forma
viéndolas junto al resto; el día que existan en PostgreSQL se borran del
generador y este las toma solas.

```bash
createdb lis
for f in 0*.sql 1*.sql; do psql -d lis -v ON_ERROR_STOP=1 -f "$f"; done
psql -d lis -f 99_pruebas_aislamiento.sql
psql -d lis -f 96_pruebas_permisos.sql
psql -d lis -f 97_pruebas_identidad.sql
psql -d lis -f 98_pruebas_lab.sql
```

Verificado contra PostgreSQL 16.13: los quince archivos corren limpios y las
cinco suites de pruebas pasan. Cada suite se corre sobre una base recién cargada;
no están pensadas para correr una detrás de otra sobre la misma.

## Cómo se conecta la API

El rol `lis_app` **no** es superusuario y no puede saltarse RLS. Al abrir cada
transacción, la API fija la empresa con el valor que viene del token — nunca con
uno que mande el cliente:

```sql
BEGIN;
SET LOCAL lis.empresa_id = '1';   -- aislamiento entre clientes
SET LOCAL lis.usuario_id = '7';   -- comprobación de permisos
-- todo lo que pase de aquí en adelante ya está filtrado y autorizado
COMMIT;
```

Si falta `lis.empresa_id`, las consultas devuelven cero filas. Si falta
`lis.usuario_id`, las operaciones sensibles fallan por falta de permiso. Falla
cerrado en los dos casos.

**Requisito de despliegue:** la API se conecta como `lis_app` y con ningún otro
rol. `core.exigir_permiso()` se salta la comprobación para cualquier otro
usuario de base de datos — ese es el camino de carga inicial y mantenimiento.

## Las cinco reglas que este esquema hace cumplir

1. **Nada cruza la frontera de la empresa.** RLS forzado en toda tabla con
   `empresa_id`, más una llave foránea compuesta `(id, empresa_id)` en cada
   relación: colgar una fila de un padre de otra empresa es imposible aunque el
   código se equivoque.
2. **La identidad se comparte, los datos no.** `plataforma.persona` guarda
   documento, año de nacimiento y sexo — **ningún nombre**. Cada empresa guarda
   su propia copia en `core.paciente`, y el vínculo nunca la sobrescribe: si una
   empresa escribió mal el apellido, el error se queda ahí.
   Vincular exige **dos factores** (documento *y* año de nacimiento); si no
   coinciden, no se vincula y queda un conflicto para revisión. La aplicación no
   tiene `SELECT` sobre `persona` ni sobre `conflicto_identidad`: solo recibe un
   veredicto.
3. **Nada se borra.** El permiso `DELETE` está revocado. Se anula con motivo, se
   marca como fusionado, se emite una versión nueva.
4. **Los estados son enumerados, no booleanos.** `activo` solo existe donde de
   verdad significa un sí o un no.
5. **El negocio del dueño no se mezcla con el del laboratorio.** El esquema
   `comercial` guarda contratos, altas, bajas y motivos; `lis_app` no tiene ni
   `USAGE` sobre él, así que la aplicación del laboratorio no puede ni nombrarlo.
   Al LIS solo le llegan `nivel_acceso` y `fecha_cierre`, escritos por
   `comercial.registrar_evento()`, que es el único punto por donde una decisión
   comercial cruza. `core` y `lab` nunca referencian `comercial`.
6. **Cada rol puede lo suyo y solo lo suyo.** Los permisos nombran acciones del
   dominio (`resultado.validar`), `core.crear_empresa()` en `16_roles.sql` dice
   con qué nace cada puesto, y `core.exigir_permiso()` lo hace cumplir dentro de
   las funciones sensibles — no solo en la pantalla. Validar exige además número de
   colegiación: un permiso no convierte a nadie en bioquímico.

## Antes de usar esto con pacientes reales

Los rangos de referencia que siembra `lab.sembrar_hematologia()` son valores de
adulto de uso general, puestos para que el sistema arranque coherente. **No son
los rangos del laboratorio.** El bioquímico tiene que revisarlos, porque dependen
del método y el reactivo del equipo, de la población que atiende el laboratorio,
y de la altitud — en Tegucigalpa, a unos 1000 m, la hemoglobina y el hematocrito
de referencia son más altos que a nivel del mar.

Que vivan en una tabla y no en el código es precisamente para que ese ajuste sea
una tarde de trabajo del bioquímico y no una migración.

## Lo que falta

La rama de imagenología, cuando llegue: un esquema `imagen` colgando del mismo
`core.episodio`, sin tocar nada de lo que hay aquí. Y el agente local, que es
código y no base de datos.
