-- =====================================================================
-- ProLisSaas - 91 - El permiso dentro de las politicas RLS
--
-- Desde 05_privilegios.sql, las tablas OPERATIVAS (paciente, episodio,
-- orden, muestra, resultado, el catalogo...) no solo preguntan "es de mi
-- empresa" sino "tengo el permiso EN LA SEDE donde estoy parado". Estas
-- pruebas demuestran cada pedazo de esa frase.
--
--     psql -U postgres -d prolissaas -f 91_pruebas_rls_permisos.sql
--
-- Corre sobre los datos de 07_datos_prueba.sql. Todo va en una transaccion
-- que termina en ROLLBACK: no deja rastro.
--
-- Cada bloque imprime una columna "pasa". Si alguna sale f, algo se rompio.
-- =====================================================================

\set ON_ERROR_STOP off

-- Los ids, como postgres (sin RLS), antes de bajar de privilegios.
SELECT usuario_id AS u_marlon FROM core.usuario WHERE username = 'marlon.ochoa'   \gset
SELECT usuario_id AS u_carla  FROM core.usuario WHERE username = 'carla.nunez'    \gset
SELECT usuario_id AS u_beto   FROM core.usuario WHERE username = 'beto.rivas'     \gset
SELECT usuario_id AS u_sandra FROM core.usuario WHERE username = 'sandra.munguia' \gset
SELECT empresa_id AS emp FROM core.usuario WHERE username = 'marlon.ochoa' \gset
SELECT sucursal_id AS s_nor FROM core.sucursal WHERE empresa_id = :emp AND codigo = 'NOR' \gset
SELECT sucursal_id AS s_cen FROM core.sucursal WHERE empresa_id = :emp AND codigo = 'CEN' \gset

BEGIN;

-- Un paciente para las pruebas de ver y tocar, insertado como postgres.
INSERT INTO core.paciente (empresa_id, expediente, nombre_completo, fecha_nacimiento, sexo)
VALUES (:emp, 'PRUEBA-91', 'Paciente De Prueba', DATE '1990-01-01', 'femenino')
RETURNING paciente_id AS pac \gset

-- Y el catalogo de hematologia, que 07 no siembra: hace falta que lab.prueba
-- tenga filas para ver que desde una sede sin lab_clinico no se ven.
SELECT lab.sembrar_hematologia(:emp, :s_nor) \gset _

SET LOCAL ROLE lis_app;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 1 · Sin sede en el contexto, las tablas operativas no existen ==='
\echo '    esperado: pasa = t  (Marlon es Administrador y aun asi ve 0)'
SELECT set_config('lis.empresa_id', :'emp', true),
       set_config('lis.usuario_id', :'u_marlon', true),
       set_config('lis.sucursal_id', '', true) \gset _
SELECT (SELECT count(*) FROM core.paciente) = 0
   AND (SELECT count(*) FROM core.convenio) = 0
   AND NOT core.usuario_puede('paciente.ver')
   AS pasa;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 2 · Con sede, el mismo Marlon ve todo lo suyo ==='
\echo '    esperado: pasa = t'
SELECT set_config('lis.sucursal_id', :'s_cen', true) \gset _
SELECT (SELECT count(*) FROM core.paciente WHERE paciente_id = :pac) = 1
   AND (SELECT count(*) FROM core.convenio) > 0
   AND core.usuario_puede('paciente.ver')
   AS pasa;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 3 · Sin el permiso, la tabla devuelve cero -- no un error ==='
\echo '    esperado: pasa = t  (Beto es Analista: ve pacientes, no convenios)'
SELECT set_config('lis.usuario_id', :'u_beto', true),
       set_config('lis.sucursal_id', :'s_cen', true) \gset _
SELECT core.usuario_puede('paciente.ver')
   AND NOT core.usuario_puede('convenio.ver')
   AND (SELECT count(*) FROM core.paciente WHERE paciente_id = :pac) = 1
   AND (SELECT count(*) FROM core.convenio) = 0
   AS pasa;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 4 · Ver no es tocar ==='
\echo '    esperado: ERROR permission denied for table paciente'
\echo '    (core.paciente esta cerrada para lis_app: se edita por editar_paciente,'
\echo '     que exige paciente.editar; Beto ve al paciente y no lo toca a mano)'
SAVEPOINT antes_del_update;
UPDATE core.paciente SET telefono = '0000-0000' WHERE paciente_id = :pac;
ROLLBACK TO SAVEPOINT antes_del_update;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 5 · Crear exige el permiso de crear ==='
\echo '    esperado: ERROR new row violates row-level security policy'
\echo '    (Carla es Recepcion: tiene convenio.ver, no convenio.administrar)'
SELECT set_config('lis.usuario_id', :'u_carla', true),
       set_config('lis.sucursal_id', :'s_nor', true) \gset _
SAVEPOINT antes_del_insert;
INSERT INTO core.convenio (empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado)
VALUES (:emp, 'Convenio colado', 'empresa', 'credito_mensual', false);
ROLLBACK TO SAVEPOINT antes_del_insert;

\echo '    ...y con el permiso, pasa  (esperado: pasa = t)'
SELECT set_config('lis.usuario_id', :'u_marlon', true) \gset _
SAVEPOINT con_permiso;
INSERT INTO core.convenio (empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado)
VALUES (:emp, 'Convenio de prueba 91', 'empresa', 'credito_mensual', false)
RETURNING nombre = 'Convenio de prueba 91' AS pasa;
RELEASE SAVEPOINT con_permiso;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 6 · EL DE VERDAD: mismo usuario, mismo rol, dos sedes, distinta respuesta ==='
\echo '    Sandra es Bioquimica en NOR y en CEN. Se apaga lab_clinico en CEN.'
\echo '    esperado: en_nor = t · en_cen = f'
-- Apagar el modulo lo hace el operador, no lis_app: se sube a postgres un momento.
RESET ROLE;
UPDATE plataforma.modulo_sucursal
   SET activo = false, desactivado_en = now()
 WHERE sucursal_id = :s_cen AND modulo_id = 'lab_clinico';
SET LOCAL ROLE lis_app;

SELECT set_config('lis.usuario_id', :'u_sandra', true) \gset _
SELECT set_config('lis.sucursal_id', :'s_nor', true) \gset _
SELECT core.usuario_puede('resultado.ver')    AS en_nor,
       (SELECT count(*) FROM lab.prueba) > 0       AS ve_catalogo_en_nor \gset
SELECT set_config('lis.sucursal_id', :'s_cen', true) \gset _
SELECT core.usuario_puede('resultado.ver')    AS en_cen,
       (SELECT count(*) FROM lab.prueba) = 0       AS catalogo_vacio_en_cen \gset

-- \gset guarda los booleanos como texto 't'/'f': se citan y se castean.
SELECT :'en_nor'::boolean AS en_nor, :'en_cen'::boolean AS en_cen,
       (:'en_nor'::boolean AND NOT :'en_cen'::boolean
        AND :'ve_catalogo_en_nor'::boolean AND :'catalogo_vacio_en_cen'::boolean) AS pasa;

\echo '    Y sin sede en el contexto la misma pregunta es NO, aunque NOR lo tenga:'
\echo '    esperado: sin_sede = f  -- una sola regla, y falla cerrado'
SELECT set_config('lis.sucursal_id', '', true) \gset _
SELECT core.usuario_puede('resultado.ver') AS sin_sede;

-- ---------------------------------------------------------------------
\echo ''
\echo '=== 7 · Las tablas que toda la empresa lee no piden permiso ==='
\echo '    esperado: pasa = t  (Beto, sin usuario.administrar, ve sedes, roles y empleados)'
SELECT set_config('lis.usuario_id', :'u_beto', true),
       set_config('lis.sucursal_id', :'s_cen', true) \gset _
SELECT (SELECT count(*) FROM core.sucursal) > 0
   AND (SELECT count(*) FROM core.rol) > 0
   AND (SELECT count(*) FROM core.empleado) > 0
   AS pasa;

ROLLBACK;

-- =====================================================================
-- LO QUE TIENE QUE HABER SALIDO
--
--   1  t     sin sede, ni el administrador ve las tablas operativas
--   2  t     con sede, ve
--   3  t     sin el permiso: cero filas, en silencio
--   4  ERROR row-level security  (ver no es tocar)
--   5  ERROR row-level security, y despues t
--   6  en_nor = t · en_cen = f · pasa = t   <- el permiso depende de la sede
--   7  t     los directorios siguen abiertos a toda la empresa
-- =====================================================================
