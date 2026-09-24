#!/usr/bin/env python3
"""
Genera esquema_sqlserver.sql leyendo la base PostgreSQL real.

El espejo de SQL Server existe solo para abrir un diagrama en SSMS. Escrito a
mano se desincroniza: en septiembre de 2026 le faltaban tres tablas y
`plataforma.persona` todavia mostraba los nombres del paciente, que es
exactamente lo contrario de lo que el diseno decidio.

Por eso se genera. La fuente es la base viva; este archivo solo traduce.

    export PGPORT=55432 PGHOST=/tmp PGUSER=postgres PGDATABASE=lis_suc
    python3 generar_sqlserver.py > esquema_sqlserver.sql

Lo unico que se mantiene a mano aqui es LARGO_TEXTO: PostgreSQL usa `text` sin
longitud y SQL Server necesita una, asi que la eleccion es de quien escribe.
"""

import subprocess
import os
import re
import sys
import textwrap
from collections import defaultdict

ESQUEMAS = ('plataforma', 'core', 'audit', 'lab', 'integra', 'comercial')

# --- lo unico que se decide a mano -----------------------------------------
LARGO_TEXTO = {
    # identificadores de producto, ASCII
    'modulo_id': 'varchar(40)', 'permiso_id': 'varchar(60)',
    'rol_plantilla_id': 'varchar(40)', 'accion': 'varchar(60)',
    'nombre_esquema': 'varchar(40)', 'nombre_tabla': 'varchar(60)',
    'loinc': 'varchar(20)',
    # codigos y numeros que se dictan por telefono
    'codigo': 'varchar(30)', 'codigo_barra': 'varchar(40)',
    'codigo_equipo': 'varchar(40)', 'numero': 'varchar(40)',
    'expediente': 'varchar(40)', 'documento': 'varchar(40)',
    'documento_receptor': 'varchar(40)', 'rtn': 'varchar(20)',
    'numero_colegiacion': 'varchar(40)', 'identificador': 'varchar(60)',
    'identificador_equipo': 'varchar(60)', 'identificador_muestra': 'varchar(60)',
    'serie': 'varchar(60)', 'prefijo': 'varchar(20)',
    'abreviatura': 'varchar(20)', 'unidad': 'varchar(30)',
    'unidad_equipo': 'varchar(30)', 'telefono': 'varchar(40)',
    'contenido_hash': 'varchar(80)', 'archivo_hash': 'varchar(80)',
    'color_tapon': 'varchar(30)',
    # credenciales
    'username': 'varchar(60)', 'password_hash': 'varchar(200)',
    'correo': 'varchar(160)',
    # nombres de personas y cosas
    'nombre': 'nvarchar(160)', 'nombre_comercial': 'nvarchar(160)',
    'nombres': 'nvarchar(120)', 'apellidos': 'nvarchar(120)',
    'nombre_completo': 'nvarchar(240)', 'cargo': 'nvarchar(80)',
    'especialidad': 'nvarchar(120)', 'marca': 'nvarchar(80)',
    'modelo': 'nvarchar(80)', 'metodo': 'nvarchar(120)',
    'anticoagulante': 'nvarchar(80)', 'parentesco': 'nvarchar(60)',
    'entregado_a': 'nvarchar(160)', 'avisado_a': 'nvarchar(160)',
    'contacto': 'nvarchar(160)', 'rol': 'nvarchar(80)',
    'direccion': 'nvarchar(250)', 'archivo_ruta': 'nvarchar(400)',
    'valor_texto': 'nvarchar(200)', 'valor_declarado': 'nvarchar(200)',
    'valor_registrado': 'nvarchar(200)', 'rango_texto': 'nvarchar(120)',
    'user_agent': 'nvarchar(300)',
    # texto largo de verdad
    'descripcion': 'nvarchar(400)', 'observacion': 'nvarchar(1000)',
    'indicaciones': 'nvarchar(1000)', 'motivo': 'nvarchar(400)',
    'motivo_correccion': 'nvarchar(400)', 'anulado_motivo': 'nvarchar(400)',
    'rechazo_motivo': 'nvarchar(400)', 'resolucion': 'nvarchar(400)',
    'detalle': 'nvarchar(1000)', 'texto_libre': 'nvarchar(max)',
    'error': 'nvarchar(1000)', 'ultimo_error': 'nvarchar(1000)',
    'contenido': 'nvarchar(max)', 'mensaje': 'nvarchar(max)',
}
LARGO_POR_DEFECTO = 'nvarchar(200)'

# indices con expresion: SQL Server no los tiene, se resuelven con una columna
# calculada persistida. La clave es (tabla, expresion en PostgreSQL).
COLUMNA_CALCULADA = {
    ('core.correlativo', 'COALESCE(sucursal_id, (0)::bigint)'):
        ('sucursal_key', 'ISNULL(sucursal_id, 0)'),
    ('lab.precio_prueba', 'COALESCE(sucursal_id, (0)::bigint)'):
        ('sucursal_key', 'ISNULL(sucursal_id, 0)'),
    ('lab.precio_prueba', 'COALESCE(convenio_id, (0)::bigint)'):
        ('convenio_key', 'ISNULL(convenio_id, 0)'),
    ('core.usuario', 'lower(username)'):
        ('username_min', 'LOWER(username)'),
}


# --------------------------------------------------------------------------
# Lo que el diseno pide crear y todavia no existe en PostgreSQL
#
# Se incluye a proposito: el diagrama sirve para decidir, y para decidir hay
# que ver la forma completa. Todo lo de aqui va marcado como PROPUESTA y sale
# de `documentacion/core/01-la-empresa.md`, secciones 2.3 a 2.6.
#
# El dia que estas tablas existan en PostgreSQL, se borran de aqui y el
# generador las toma solas de la base.
# --------------------------------------------------------------------------

NIVEL_ACCESO = "'completo', 'solo_cierre', 'solo_lectura', 'bloqueado'"
ESTADO_EMPRESA_PROP = ("'prueba', 'activa', 'suspendida', 'cancelada', "
                       "'cerrada'")

# columnas propuestas que se suman a una tabla que ya existe
COLUMNAS_PROPUESTAS = {}

# valores de enumerado que el diseno pide agregar
ENUM_PROPUESTO = {}

TABLAS_PROPUESTAS = """
/* =====================================================================
   PROPUESTA · lo que el diseno pide y todavia no existe en PostgreSQL

   Estan aqui para poder verlas en el diagrama junto al resto. No las crea
   ningun archivo 01..17: si aparecen en la base real, alguien se confundio.

   Origen: documentacion/core/01-la-empresa.md seccion 2.4, y H-78.
   ===================================================================== */

-- PROPUESTA · Uno a uno con la empresa. La llave primaria es la foranea, y eso
-- es lo que fuerza el uno a uno. La direccion y el telefono del informe NO van
-- aqui: viven en core.sucursal, porque cambian por sede.
CREATE TABLE core.empresa_configuracion (
  empresa_id                bigint        NOT NULL,
  logo                      nvarchar(400),
  encabezado_texto          nvarchar(1000),
  pie_texto                 nvarchar(1000),
  bloque_firma_texto        nvarchar(1000),
  correo_notificaciones     varchar(160),
  zona_horaria              varchar(60)   NOT NULL DEFAULT 'America/Tegucigalpa',
  CONSTRAINT empresa_configuracion_pkey PRIMARY KEY (empresa_id),
  CONSTRAINT fk_configuracion_empresa FOREIGN KEY (empresa_id)
    REFERENCES core.empresa(empresa_id)
);
GO

-- El enlace y el mensaje ya NO son propuestas: existen en PostgreSQL desde
-- 03_core.sql y 08_enlace_y_mensaje.sql, asi que el generador los toma solos
-- de la base. Con ellos se retiraron core.empresa_asociada, audit.derivacion,
-- rls_derivacion, plataforma.persona y plataforma.conflicto_identidad (H-73,
-- H-76, H-78).
"""


# El nombre de la base estaba escrito a mano aqui. Ahora se puede pasar por
# PGDATABASE sin tocar el archivo; si no se pasa, sigue siendo el de siempre.
BASE = os.environ.get('PGDATABASE') or 'lis_suc'

# La base de SQL Server donde se mira el diagrama. El script la borra entera y
# la crea de nuevo en cada corrida, asi que aqui no se guarda nada.
BASE_DIAGRAMA = os.environ.get('BASE_DIAGRAMA') or 'ProLisSaasDiagrama'


def q(sql):
    r = subprocess.run(['psql', '-d', BASE, '-X', '-tAF', '\x1f', '-c', sql],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit('psql fallo:\n' + r.stderr)
    return [l.split('\x1f') for l in r.stdout.strip('\n').split('\n') if l]


# --------------------------------------------------------------------------
# 1 · leer la base
# --------------------------------------------------------------------------
enums = {}
for tipo, valores, largo in q("""
 SELECT n.nspname||'.'||t.typname,
        string_agg(quote_literal(e.enumlabel), ', ' ORDER BY e.enumsortorder),
        max(length(e.enumlabel))
 FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
 JOIN pg_namespace n ON n.oid = t.typnamespace GROUP BY 1"""):
    enums[tipo] = (valores, int(largo))

columnas = defaultdict(list)
for esq, tab, col, tipo, tipo_ud, nulo, defecto, ident in q(f"""
 SELECT c.table_schema, c.table_name, c.column_name, c.data_type,
        coalesce(c.udt_schema||'.'||c.udt_name, ''), c.is_nullable,
        coalesce(c.column_default, ''), c.is_identity
 FROM information_schema.columns c
 JOIN information_schema.tables t
   ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  AND t.table_type = 'BASE TABLE'
 WHERE c.table_schema IN {ESQUEMAS}
 ORDER BY c.table_schema, c.table_name, c.ordinal_position"""):
    columnas[f'{esq}.{tab}'].append(
        dict(nombre=col, tipo=tipo, ud=tipo_ud, nulo=nulo == 'YES',
             defecto=defecto, identidad=ident == 'YES'))

numericos = {}
for esq, tab, col, p, e in q(f"""
 SELECT table_schema, table_name, column_name, numeric_precision, numeric_scale
 FROM information_schema.columns
 WHERE table_schema IN {ESQUEMAS} AND data_type = 'numeric'"""):
    numericos[(f'{esq}.{tab}', col)] = (p, e)

restricciones = defaultdict(list)   # tabla -> (nombre, tipo, definicion)
for tabla, nombre, tipo, definicion in q(f"""
 SELECT conrelid::regclass::text, conname, contype, pg_get_constraintdef(oid)
 FROM pg_constraint
 WHERE connamespace::regnamespace::text IN {ESQUEMAS}
   AND contype IN ('p','u','c','f','x')
 ORDER BY conrelid::regclass::text,
          CASE contype WHEN 'p' THEN 1 WHEN 'u' THEN 2 WHEN 'c' THEN 3
                       WHEN 'f' THEN 4 ELSE 5 END,
          conname"""):
    restricciones[tabla].append((nombre, tipo, definicion))

indices = []
for tabla, nombre, definicion in q(f"""
 SELECT schemaname||'.'||tablename, indexname, indexdef
 FROM pg_indexes WHERE schemaname IN {ESQUEMAS} AND indexdef LIKE 'CREATE UNIQUE%'
 ORDER BY 1, 2"""):
    if any(n == nombre for n, t, d in restricciones[tabla]):
        continue                      # ya viene como CONSTRAINT UNIQUE
    indices.append((tabla, nombre, definicion))

comentarios = {}
for tabla, txt in q(f"""
 SELECT c.oid::regclass::text, obj_description(c.oid, 'pg_class')
 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN {ESQUEMAS} AND c.relkind = 'r'
   AND obj_description(c.oid, 'pg_class') IS NOT NULL"""):
    comentarios[tabla] = txt

# Los comentarios de columna tambien viajan. Se perdian, y ahi es donde esta
# escrito por que una columna es como es -- que es justo lo que uno quiere leer
# mirando el diagrama.
comentarios_col = {}
for tabla, col, txt in q(f"""
 SELECT c.oid::regclass::text, a.attname, d.description
 FROM pg_description d
 JOIN pg_class c        ON c.oid = d.objoid
 JOIN pg_namespace n    ON n.oid = c.relnamespace
 JOIN pg_attribute a    ON a.attrelid = c.oid AND a.attnum = d.objsubid
 WHERE d.objsubid > 0 AND n.nspname IN {ESQUEMAS}"""):
    comentarios_col[(tabla, col)] = txt


# --------------------------------------------------------------------------
# 2 · traducir
# --------------------------------------------------------------------------
# Lo que el generador NO supo traducir. Se junta todo y se falla al final con
# la lista completa, en vez de escribir un espejo que revienta en SSMS.
DESCONOCIDO = []

TIPOS = {
    'boolean': 'bit',
    'date':    'date',
    'uuid':    'uniqueidentifier',
    'jsonb':   'nvarchar(max)',
    'json':    'nvarchar(max)',
    'bytea':   'varbinary(max)',
    'inet':    'varchar(45)',
    # SQL Server no tiene arreglos. Un text[] se aplana a texto SOLO para que
    # la columna se vea en el diagrama; la restriccion que contaba sus
    # elementos (array_length) ya sale como comentario. Es una perdida
    # DECLARADA, no un descuido -- que es justo la diferencia que importa.
    'ARRAY':   'nvarchar(400)',
}


def tipo_sql(tabla, c):
    """PostgreSQL a T-SQL. SIN red de seguridad a proposito.

    Antes esta funcion terminaba en `return 'nvarchar(200)'`, asi que un tipo
    que nadie habia mapeado se volvia texto EN SILENCIO. Fue exactamente lo que
    paso con `uuid`: el espejo decia nvarchar(200) y el DEFAULT de al lado
    reventaba en SSMS. Ahora lo que no se conoce se anota y el espejo no sale.
    """
    t = c['tipo']
    if t == 'bigint':
        return 'bigint IDENTITY(1,1)' if c['identidad'] else 'bigint'
    if t == 'integer':
        return 'int IDENTITY(1,1)' if c['identidad'] else 'int'
    if t == 'smallint':
        return 'smallint'
    if t in TIPOS:
        return TIPOS[t]
    if t.startswith('timestamp'):
        return 'datetime2'
    if t == 'time without time zone':
        return 'time'
    if t == 'numeric':
        p, e = numericos[(tabla, c['nombre'])]
        return f'decimal({p},{e})'
    if t == 'text':
        return LARGO_TEXTO.get(c['nombre'], LARGO_POR_DEFECTO)
    if t == 'USER-DEFINED' and c['ud'] in enums:
        _, largo = enums[c['ud']]
        return f'varchar({max(20, -(-(largo + 5) // 10) * 10)})'
    DESCONOCIDO.append(f'tipo «{t}» en {tabla}.{c["nombre"]}')
    return f'/* TIPO SIN TRADUCIR: {t} */'


DEFECTOS = {
    'now()':             'sysutcdatetime()',
    'CURRENT_DATE':      'CAST(sysutcdatetime() AS date)',
    'CURRENT_TIMESTAMP': 'sysutcdatetime()',
    'gen_random_uuid()': 'NEWID()',
    'true':              '1',
    'false':             '0',
}


def defecto_sql(c):
    """Igual que tipo_sql: lo que no se conoce NO pasa de largo.

    Antes terminaba en `return f' DEFAULT {d}'`, asi que gen_random_uuid() se
    copiaba tal cual al espejo y SSMS contestaba "is not a recognized built-in
    function name". Un literal si pasa; una llamada a funcion desconocida, no.
    """
    d = c['defecto']
    if not d or 'nextval' in d or c['identidad']:
        return ''
    d = re.sub(r'::[\w\. ]+', '', d).strip()
    if d in DEFECTOS:
        return f' DEFAULT {DEFECTOS[d]}'
    if re.fullmatch(r"'[^']*'|-?\d+(\.\d+)?|\([^()]*\)", d):
        return f' DEFAULT {d}'        # literal: pasa
    if re.search(r'\w+\s*\(', d):
        DESCONOCIDO.append(f'valor por defecto «{d}»')
        return f' /* DEFAULT SIN TRADUCIR: {d} */'
    return f' DEFAULT {d}'


# Funciones de PostgreSQL que SQL Server no tiene y que no se pueden imitar en
# una linea. El CHECK que las use se pierde: sale como comentario.
SIN_TRADUCCION = ('array_length(', 'array_upper(', 'array_lower(',
                  'cardinality(', 'unnest(', 'array_position(')


def arreglar_booleanos(d, tabla):
    """En PostgreSQL una columna boolean ES una condicion: CHECK (exito OR ...)
    vale. En SQL Server `bit` no es booleano y eso da

        An expression of non-boolean type specified in a context
        where a condition is expected

    Asi que `NOT resuelto` pasa a `resuelto = 0` y `exito` suelta a `exito = 1`.
    Los nombres largos primero, para que `resuelto_en` no se coma a `resuelto`.
    """
    booleanas = sorted((c['nombre'] for c in columnas.get(tabla, [])
                        if c['tipo'] == 'boolean'), key=len, reverse=True)
    for nombre in booleanas:
        n = re.escape(nombre)
        d = re.sub(rf'\bNOT\s+{n}\b(?!\s*[=<>])', f'{nombre} = 0', d)
        d = re.sub(rf'(?<![.\w]){n}\b(?!\s*(?:=|<>|<|>|IS\b))', f'{nombre} = 1', d)
    return d


def traducir_def(d, tabla=None):
    """CHECK y FK de PostgreSQL a T-SQL."""
    d = re.sub(r'::[\w\. ]+(\[\])?', '', d)
    # `a IS DISTINCT FROM b` no existe en T-SQL
    d = re.sub(r'\(?\s*(\w+)\s+IS DISTINCT FROM\s+(\w+)\s*\)?',
               r'(\1 IS NULL OR \1 <> \2)', d)
    d = d.replace('EXTRACT(year FROM now())', 'YEAR(GETDATE())')
    d = re.sub(r'\bbtrim\(([^()]*)\)', r'LTRIM(RTRIM(\1))', d)
    d = d.replace('now()', 'sysutcdatetime()')
    d = d.replace('~~', 'LIKE')
    # PostgreSQL escribe las listas como ANY/ALL sobre un ARRAY. SQL Server no
    # tiene constructor de arreglos, asi que van a IN / NOT IN.
    #   x =  ANY (ARRAY[a,b])  ->  x IN (a,b)
    #   x <> ALL (ARRAY[a,b])  ->  x NOT IN (a,b)
    d = re.sub(r'(?:<>|!=)\s*ALL \(ARRAY\[(.*?)\]\)', r'NOT IN (\1)', d)
    d = re.sub(r'=\s*ANY \(ARRAY\[(.*?)\]\)', r'IN (\1)', d)
    d = re.sub(r'\bANY \(ARRAY\[(.*?)\]\)', r'(\1)', d)
    d = d.replace('= (', 'IN (') if ' = (' in d and ',' in d else d
    d = re.sub(r'\bIS NOT TRUE\b', '= 0', d)
    d = re.sub(r'\bIS TRUE\b', '= 1', d)
    if tabla:
        d = arreglar_booleanos(d, tabla)
    return d


def check_a_tsql(d, tabla=None):
    """Lo que SQL Server no puede expresar sale como comentario, no roto."""
    if '~' in d and 'LIKE' not in d:
        return None                    # regex: se pierde, va como comentario
    if any(f in d for f in SIN_TRADUCCION):
        return None                    # arreglos: SQL Server no los tiene
    return traducir_def(d, tabla)


def condicion_parcial(w):
    w = re.sub(r'::[\w\. ]+', '', w).strip()
    w = re.sub(r'^\((.*)\)$', r'\1', w).strip()
    # `WHERE vigente` -> `WHERE vigente = 1`
    if re.fullmatch(r'\w+', w):
        w = f'{w} = 1'
    return w


# orden topologico por llaves foraneas, dejando fuera los ciclos
deps = defaultdict(set)
fks_diferidas = []
for tabla, lista in restricciones.items():
    for nombre, tipo, d in lista:
        if tipo == 'f':
            m = re.search(r'REFERENCES ([\w\.]+)', d)
            if m and m.group(1) != tabla:
                deps[tabla].add(m.group(1))

orden, pendientes = [], set(columnas)
while pendientes:
    listas = sorted(t for t in pendientes if not (deps[t] & pendientes))
    if not listas:                     # ciclo: romperlo por la tabla con menos deps
        t = min(pendientes, key=lambda x: (len(deps[x] & pendientes), x))
        for otra in sorted(deps[t] & pendientes):
            for nombre, tipo, d in restricciones[t]:
                if tipo == 'f' and f'REFERENCES {otra}' in d:
                    fks_diferidas.append((t, nombre, d))
        deps[t] -= pendientes
        continue
    orden += listas
    pendientes -= set(listas)

diferidas_nombres = {(t, n) for t, n, _ in fks_diferidas}


# --------------------------------------------------------------------------
# 3 · escribir
# --------------------------------------------------------------------------
S = []
w = S.append

w("""/* =====================================================================
   ProLisSaas · Esquema para SQL Server — SOLO PARA VISUALIZAR

   Esta NO es la base de datos del sistema. La base real es PostgreSQL y
   vive en los archivos 01..16 de esta misma carpeta. Este script es una
   traduccion estructural para poder abrir un diagrama en SSMS.

   GENERADO. No se edita a mano: se regenera con

       python3 generar_sqlserver.py > esquema_sqlserver.sql

   La fuente es la base viva, asi que el diagrama no se puede desincronizar
   del diseno. Un espejo escrito a mano si: en septiembre de 2026 a este
   archivo le faltaban tres tablas y `plataforma.persona` todavia mostraba
   los nombres del paciente, que es lo contrario de lo que el diseno decidio.

   Que se conserva: esquemas, tablas, columnas, llaves primarias, llaves
   foraneas (incluidas las compuestas con empresa_id), restricciones unicas
   e indices filtrados. Incluido el esquema `comercial`, que es del dueno del
   sistema y no del laboratorio: se ve en el diagrama para poder comprobar de
   un vistazo que solo apunta a core.empresa y nada le apunta a el.

   Que NO se traduce, porque no aporta al diagrama:
     · Row Level Security y el rol lis_app  -> el aislamiento real
     · Las funciones y los tipos enumerados -> aqui son CHECK
     · Los CHECK con expresion regular      -> quedan como comentario

   Triggers no hay ninguno que traducir: se fueron con actualizado_en (H-96).

   Uso: abrilo en SSMS y dale F5. No hace falta crear nada antes ni elegir
   base en el desplegable -- el script se cambia solo a master, tira
   %BASE% entera y la vuelve a crear.

   Despues: Diagramas de base de datos > Nuevo diagrama > agregar todas.
   Si SSMS pide un propietario valido:
       ALTER AUTHORIZATION ON DATABASE::%BASE% TO sa;

   SE BORRA LA BASE COMPLETA cada vez, incluidos los diagramas guardados en
   dbo.sysdiagrams. Es a proposito: antes se borraban solo las tablas y los
   esquemas, y el diagrama viejo sobrevivia apuntando a tablas que ya no
   existian -- daba la impresion de que el script no aplicaba los cambios.
   Es una base para mirar el diseno, no para guardar nada.
   ===================================================================== */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   Borrado total · la base entera, no solo sus tablas

   Antes esto borraba las llaves, las tablas y los esquemas uno por uno.
   Funcionaba, pero dejaba rastro: dbo.sysdiagrams -- donde SSMS guarda los
   diagramas -- sobrevivia, y el diagrama viejo seguia abriendo apuntando a
   tablas que ya no existian. Parecia que el script no aplicaba los cambios.

   Ahora se tira la base completa y se crea de nuevo. Cero rastro.

   OJO: se pierde TODO lo que este en %BASE%, incluidos los diagramas
   guardados. Es una base para mirar el diseno, no para guardar nada.

   El USE master de arriba es obligatorio: no se puede borrar una base
   estando conectado a ella. Y como el script se cambia solo a la base
   correcta, ya no importa en que ventana de SSMS lo ejecutes.
   --------------------------------------------------------------------- */

USE master;
GO

IF DB_ID(N'%BASE%') IS NOT NULL
BEGIN
    -- Echa a cualquier otra conexion: si SSMS tiene la base abierta en el
    -- Explorador de objetos, el DROP falla sin esto.
    ALTER DATABASE [%BASE%] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [%BASE%];
    PRINT N'>>> Base anterior borrada.';
END
GO

CREATE DATABASE [%BASE%];
GO

USE [%BASE%];
GO

PRINT N'>>> Base creada limpia. Todo lo que sigue es el diseno de hoy.';
GO
""")

w(f"""
/* =====================================================================
   Los {len(ESQUEMAS)} esquemas · un modulo cada uno
   ===================================================================== */
""")
for e in ESQUEMAS:
    w(f'CREATE SCHEMA {e};\nGO\n')

TITULO = {
    'plataforma': 'PLATAFORMA · por encima de las empresas, sin datos clinicos',
    'core':       'CORE · el nucleo: quien, donde y cuando',
    'audit':      'AUDIT · el rastro y el unico puente entre empresas',
    'comercial':  'COMERCIAL · el negocio del dueno del sistema, no del laboratorio',
    'lab':        'LAB · la rama de laboratorio clinico',
    'integra':    'INTEGRA · los analizadores y lo que mandan',
}
esquema_actual = None

for tabla in orden:
    esq = tabla.split('.')[0]
    if esq != esquema_actual:
        esquema_actual = esq
        w(f"""
/* =====================================================================
   {TITULO[esq]}
   ===================================================================== */
""")

    if tabla in comentarios:
        texto = re.sub(r'\s+', ' ', comentarios[tabla]).strip()
        for linea in [texto[i:i + 72] for i in range(0, len(texto), 72)]:
            w(f'-- {linea}')

    calculadas = []
    for (t, expr), (col, tsql) in COLUMNA_CALCULADA.items():
        if t == tabla:
            calculadas.append(f'  {col:<26} AS ISNULL(NULL,NULL)')  # marcador
    lineas = []
    ancho = max(len(c['nombre']) for c in columnas[tabla])
    for c in columnas[tabla]:
        nulo = '' if c['nulo'] else ' NOT NULL'
        linea = f"  {c['nombre']:<{ancho}}  {tipo_sql(tabla, c)}{nulo}{defecto_sql(c)}"
        nota = comentarios_col.get((tabla, c['nombre']))
        if nota:
            # El comentario va PEGADO a su columna, en la misma entrada de la
            # lista: si fuera una entrada aparte, el join le colgaria una coma
            # al final de cada renglon de comentario.
            texto = re.sub(r'\s+', ' ', nota).strip()
            envuelto = '\n'.join(f'  -- {l}'
                                 for l in textwrap.wrap(texto, 68) or [texto])
            linea = envuelto + '\n' + linea
        lineas.append(linea)

    for col, tipo_col, nota in COLUMNAS_PROPUESTAS.get(tabla, []):
        lineas.append(f'  -- {nota}\n  {col:<{ancho}}  {tipo_col}')

    for (t, expr), (col, tsql) in sorted(COLUMNA_CALCULADA.items()):
        if t == tabla:
            lineas.append(
                f"  -- calculada y persistida: el indice unico de abajo la necesita,\n"
                f"  -- porque SQL Server no admite indices sobre expresiones\n"
                f"  {col:<{ancho}}  AS {tsql} PERSISTED")

    comentado = []
    for nombre, tipo, d in restricciones[tabla]:
        if (tabla, nombre) in diferidas_nombres:
            continue
        if tipo == 'p':
            cols = re.search(r'PRIMARY KEY \((.*)\)', d).group(1)
            lineas.append(f'  CONSTRAINT {nombre} PRIMARY KEY ({cols})')
        elif tipo == 'u':
            cols = re.search(r'UNIQUE \((.*)\)', d).group(1)
            lineas.append(f'  CONSTRAINT {nombre} UNIQUE ({cols})')
        elif tipo == 'c':
            tsql = check_a_tsql(d, tabla)
            if tsql:
                lineas.append(f'  CONSTRAINT {nombre} {tsql}')
            else:
                comentado.append((nombre, d))
        elif tipo == 'f':
            lineas.append(f'  CONSTRAINT {nombre} {traducir_def(d, tabla)}')
        elif tipo == 'x':
            # EXCLUDE no existe en SQL Server. No se traduce, pero tampoco se
            # calla: el espejo se generaba justamente para que no mintiera.
            comentado.append((nombre, d))

    # los enumerados se vuelven CHECK
    for c in columnas[tabla]:
        if c['tipo'] == 'USER-DEFINED' and c['ud'] in enums:
            valores, _ = enums[c['ud']]
            nota = ''
            if c['ud'] in ENUM_PROPUESTO:
                valores = ENUM_PROPUESTO[c['ud']]
                nota = ('  -- el ultimo valor es PROPUESTO: todavia no esta en '
                        'el enumerado de PostgreSQL\n')
            lineas.append(f"{nota}  CONSTRAINT ck_{tabla.split('.')[1]}_{c['nombre']}"
                          f" CHECK ({c['nombre']} IN ({valores}))")

    w(f'CREATE TABLE {tabla} (')
    w(',\n'.join(lineas))
    w(');')
    for nombre, d in comentado:
        w(f'-- {nombre}: {d}')
        w('--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si '
          'se cumple)')
    w('GO\n')

    for t, nombre, definicion in indices:
        if t != tabla:
            continue
        cuerpo = re.search(r'USING btree \((.*?)\)(?: WHERE (.*))?$', definicion)
        cols, donde = cuerpo.group(1), cuerpo.group(2)
        for (tt, expr), (colc, _) in COLUMNA_CALCULADA.items():
            if tt == tabla:
                cols = cols.replace(expr, colc)

        # SQL Server NO admite expresiones como llave de indice: exige una
        # columna calculada persistida. Si quedo una llamada a funcion sin
        # mapear en COLUMNA_CALCULADA, el indice sale como comentario en vez
        # de salir roto -- que fue lo que paso con least()/greatest() del
        # enlace y dio "Incorrect syntax near '('".
        if re.search(r'\w+\s*\(', cols):
            w(f'-- {nombre}: CREATE UNIQUE INDEX ... ({cols})'
              + (f' WHERE {donde}' if donde else ''))
            w('--   (llave con expresion; SQL Server exige una columna calculada')
            w('--    persistida. En PostgreSQL se cumple.)')
            w('GO\n')
            continue

        linea = f'CREATE UNIQUE INDEX {nombre} ON {tabla} ({cols})'
        if donde:
            linea += f' WHERE {condicion_parcial(donde)}'
        w(linea + ';')
        w('GO\n')

if fks_diferidas:
    w("""
/* =====================================================================
   Las llaves que cierran los ciclos

   Van al final porque las dos tablas se apuntan entre si y no hay orden
   de creacion que lo resuelva.
   ===================================================================== */
""")
    for tabla, nombre, d in fks_diferidas:
        w(f'ALTER TABLE {tabla} ADD CONSTRAINT {nombre} {traducir_def(d, tabla)};')
        w('GO\n')

w(TABLAS_PROPUESTAS)

w("""
PRINT N'>>> Listo. Diagramas de base de datos > Nuevo diagrama > agregar todas.';
GO
""")

# El nombre de la base del diagrama se escribe en un solo lugar y se sustituye
# aqui. Cambiarlo es cambiar BASE_DIAGRAMA, no buscar y reemplazar en el .sql.
salida = '\n'.join(S).replace('%BASE%', BASE_DIAGRAMA)


# --------------------------------------------------------------------------
# 4 · el guardia
#
# PARSEAR NO ES VALIDAR. Un analizador de T-SQL acepto sin quejarse un CHECK
# con array_length() y otros dos con una columna bit usada como condicion --
# legal en PostgreSQL, donde boolean ES una condicion, e ilegal en SQL Server,
# donde bit no lo es. SSMS los rechazo con:
#
#     'array_length' is not a recognized built-in function name
#     An expression of non-boolean type specified in a context
#     where a condition is expected
#
# Y como las tres tablas que fallaron eran padres, se cayeron seis llaves
# foraneas detras. Esto revisa el texto que sale y revienta ruidosamente, en
# vez de entregar un script que se rompe a la mitad.
# --------------------------------------------------------------------------

BOOLEANAS = {c['nombre'] for cols in columnas.values() for c in cols
             if c['tipo'] == 'boolean'}

# Lista BLANCA de tipos de SQL Server. Blanca y no negra a proposito: una lista
# de tokens prohibidos solo atrapa lo que uno ya penso, y tres veces seguidas
# se colo algo que no estaba en ella -- array_length, una columna bit usada
# como condicion, y uuid. Con lista blanca, cualquier tipo que nadie mapeo
# salta, aunque no se nos hubiera ocurrido.
TIPOS_TSQL = {
    'bigint', 'int', 'smallint', 'tinyint', 'bit', 'decimal', 'numeric',
    'money', 'float', 'real', 'date', 'time', 'datetime', 'datetime2',
    'datetimeoffset', 'char', 'varchar', 'nchar', 'nvarchar', 'text', 'ntext',
    'binary', 'varbinary', 'image', 'uniqueidentifier', 'xml', 'sql_variant',
}

PROHIBIDO = SIN_TRADUCCION + ('btrim(', 'now()', '::', '~~')

problemas = [f'(sin linea) {d}' for d in DESCONOCIDO]
en_bloque = False
for n, linea in enumerate(salida.split('\n'), 1):
    # Lo comentado no cuenta: ni los bloques /* */ ni las lineas --. Ahi es
    # justamente donde va a parar lo que no se pudo traducir.
    abre, cierra = '/*' in linea, '*/' in linea
    if abre and not cierra:
        en_bloque = True
    if en_bloque or abre or cierra or linea.lstrip().startswith('--'):
        if cierra:
            en_bloque = False
        continue

    # Sin literales de texto: 'activo' es una cadena, no la columna activo.
    codigo = re.sub(r"'(?:[^']|'')*'", "''", linea)

    for f in PROHIBIDO:
        if f == '::' and 'DATABASE::' in codigo:
            continue                   # DATABASE::nombre es T-SQL legitimo
        if f in codigo:
            problemas.append(f'{n}: «{f}» no existe en SQL Server')
    if '~' in codigo:
        problemas.append(f'{n}: expresion regular de PostgreSQL')
    # Una linea de columna: dos palabras y un tipo. Que el tipo exista.
    m = re.match(r'\s{2}(\w+)\s{2,}([A-Za-z_]+)(\(|\s|$)', linea)
    if m and m.group(1).lower() not in ('constraint',):
        tipo = m.group(2).lower()
        if tipo not in TIPOS_TSQL and tipo not in ('as',):
            problemas.append(f'{n}: «{tipo}» no es un tipo de SQL Server')
    if 'CHECK' in codigo:
        for b in BOOLEANAS:
            if re.search(rf'(?<![.\w]){re.escape(b)}\b(?!\s*(?:=|<>|<|>|IS\b))', codigo):
                problemas.append(f'{n}: «{b}» es bit y se usa como condicion')
        if re.search(r'\b(true|false)\b', codigo, re.I):
            problemas.append(f'{n}: true/false no son literales de SQL Server')

if problemas:
    sys.stderr.write('\nEL ESPEJO NO SE GENERO: no correria en SQL Server.\n\n')
    for p in problemas[:25]:
        sys.stderr.write(f'  {p}\n')
    if len(problemas) > 25:
        sys.stderr.write(f'  ... y {len(problemas)-25} mas\n')
    sys.stderr.write('\n')
    sys.exit(1)

sys.stdout.write(salida + '\n')
