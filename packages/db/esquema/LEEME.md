# El esquema

Seis archivos que corren **en orden**. Cada uno tiene un solo tipo de objeto,
para poder leer el modelo completo de un tirón.

| Archivo | Qué trae | Por qué va aquí |
|---|---|---|
| `01_tipos.sql` | Los seis esquemas, la extensión `btree_gist` y los 27 tipos enumerados | Lo primero que existe. Los estados son enumerados, nunca booleanos |
| `02_tablas.sql` | **Las 44 tablas**, con sus llaves, restricciones y comentarios | En orden de dependencia. Es el modelo entero |
| `03_indices.sql` | Los 37 índices | Después de las tablas. Varios son parciales: el `WHERE` es parte de la regla |
| `04_funciones.sql` | Las 27 funciones y la vista | Aquí vive el comportamiento. Las de `LANGUAGE sql` se validan al crearse, así que necesitan las tablas |
| `05_privilegios.sql` | El rol `lis_app`, los `GRANT`/`REVOKE` y las 35 políticas RLS | Va después de las funciones porque las políticas llaman a `core.empresa_actual()` |
| `06_semillas.sql` | El catálogo del producto: módulos, los 30 permisos, y los 24 parámetros del Hemax 53 | Lo último |

## Cargarla

**En Windows:** doble clic en `cargar-db.bat`. Busca `psql` solo, crea la base y
corre los seis en orden, parando al primer error.

**A mano:**

```bash
createdb -U postgres prolissaas
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 01_tipos.sql
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 02_tablas.sql
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 03_indices.sql
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 04_funciones.sql
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 05_privilegios.sql
psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 06_semillas.sql
```

Necesita **PostgreSQL 16 o más**: usa `GENERATED ALWAYS AS IDENTITY`, RLS
forzado y `btree_gist`.

## Verla

En **pgAdmin** —viene con el instalador de PostgreSQL y es una aplicación web—
conectate al servidor local y desplegá `Databases > prolissaas > Schemas`.

Para el diagrama entidad-relación: **clic derecho sobre el esquema `core` →
ERD For Schema**. Por esquema y no por base: con 44 tablas, un diagrama de todo
es ilegible.

## Las pruebas

Seis archivos, `94` a `99`. **Cada uno necesita una base recién cargada**: dan
de alta sus propias empresas y chocan entre sí si se corren seguidos.

| Archivo | Qué prueba | Errores esperados |
|---|---|---|
| `94_pruebas_modulos.sql` | La licencia por sede y quién puede tocar los permisos de un rol | 4 |
| `95_pruebas_comercial.sql` | La frontera con el esquema comercial | 9 |
| `96_pruebas_permisos.sql` | Que cada rol pueda lo suyo y solo lo suyo | 2 |
| `97_pruebas_identidad.sql` | El paciente entre dos empresas | 7 |
| `98_pruebas_lab.sql` | Orden, muestra, resultado, validación | 1 |
| `99_pruebas_aislamiento.sql` | Que nada cruce la frontera de la empresa | 5 |

**Los errores son la prueba.** Cada bloque provoca a propósito el error que
demuestra que la regla funciona; el archivo dice qué espera antes de cada uno.
Si alguno da un número distinto al de la tabla, algo se rompió.

## El espejo de SQL Server

`esquema_sqlserver.sql` lo genera `generar_sqlserver.py` **leyendo la base
viva**, no estos archivos. Existía para poder ver el diagrama en SSMS; desde
que pgAdmin dibuja el ERD ya no hace falta para eso, pero se deja como
comprobación barata de que el modelo es portable.

**No sirve como origen.** Pierde 35 políticas RLS, 27 funciones, 27 tipos
enumerados y 35 `GRANT`/`REVOKE`. Es una fotografía de las tablas, no el
sistema.

```bash
export PGHOST=/tmp PGPORT=5432 PGUSER=postgres PGDATABASE=prolissaas
python3 generar_sqlserver.py > esquema_sqlserver.sql
```
