-- =====================================================================
-- ProLisSaas · 99 · Pruebas del nucleo
--
-- Estas pruebas se corren ANTES de escribir el primer endpoint, y
-- despues en cada despliegue. Si alguna falla, el aislamiento entre
-- clientes esta roto y no hay funcionalidad que valga la pena entregar.
--
--   createdb lis
--   psql -d lis -f 01..06 y luego este archivo
-- =====================================================================

\set ON_ERROR_STOP off

-- Dos empresas: el laboratorio y la clinica en cuyo edificio esta.
SELECT core.crear_empresa('Laboratorio Familiar Ochoa','0801-1990-111111','Sede Central','LFO') AS lab \gset
SELECT core.crear_empresa('Clinica San Rafael','0801-1990-222222','Consulta Externa','CSR') AS cli \gset

INSERT INTO core.empleado (empresa_id, nombres, apellidos, numero_colegiacion)
VALUES (:lab,'Said','Hoch','BQ-1234') RETURNING empleado_id \gset

INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :lab, :empleado_id, rol_id, 'said', '$argon2id$marcador'
FROM core.rol WHERE empresa_id = :lab AND nombre = 'Administrador'
RETURNING usuario_id \gset

-- registrar_paciente lee la sesion (empresa, usuario, sede) y exige paciente.crear.
SELECT sucursal_id AS s_lab FROM core.sucursal WHERE empresa_id = :lab \gset
SET lis.empresa_id = :'lab'; SET lis.usuario_id = :'usuario_id'; SET lis.sucursal_id = :'s_lab';
SELECT core.registrar_paciente('SAID GABRIEL HOCH URBINA','identidad','1807200400844',
  DATE '2004-11-15',NULL,NULL,'masculino');
RESET lis.empresa_id; RESET lis.usuario_id; RESET lis.sucursal_id;


\echo ''
\echo '=== 1 · Una empresa no ve los pacientes de otra ==================='
\echo '    esperado: 1, luego 0, luego 0'
-- Desde que las politicas llaman a core.sesion_vigente(), el contexto
-- necesita las DOS variables: sin lis.usuario_id la funcion no encuentra a
-- nadie y lanza 'Sesion caducada: el usuario ya no existe'. Antes bastaba
-- con la empresa.
SET lis.usuario_id = :'usuario_id';
SET ROLE lis_app;
SET lis.empresa_id = '1'; SET lis.sucursal_id = '1'; SELECT count(*) AS ve_empresa_1 FROM core.paciente;
SET lis.empresa_id = '2'; SET lis.sucursal_id = '3'; SELECT count(*) AS ve_empresa_2 FROM core.paciente;
SET lis.empresa_id = ''; SET lis.sucursal_id = '';  SELECT count(*) AS sin_contexto  FROM core.paciente;
RESET ROLE;
RESET lis.usuario_id;

\echo ''
\echo '=== 2 · La FK compuesta impide colgar de un padre de otra empresa ='
\echo '    esperado: ERROR fk_episodio_paciente'
INSERT INTO core.episodio (empresa_id, sucursal_id, paciente_id, convenio_id, numero, creado_por_usuario_id)
VALUES (2, 2, 1, (SELECT convenio_id FROM core.convenio WHERE empresa_id = 2), 'X-1', 1);

\echo ''
\echo '=== 3 · El enlace no se explora: se pregunta por funcion ========='
\echo '    esperado: ERROR permission denied for table enlace'
SET ROLE lis_app;
SELECT * FROM plataforma.enlace;
RESET ROLE;
\echo '    (antes esta prueba protegia plataforma.persona, que se retiro:'
\echo '     la identidad ya no se comparte entre empresas. Ver H-73)'

\echo ''
\echo '=== 4 · Nada se borra ============================================'
\echo '    esperado: ERROR permission denied for table paciente'
-- Desde que las politicas llaman a core.sesion_vigente(), el contexto necesita
-- las DOS variables. Poner solo la empresa era un atajo que el sistema real
-- nunca usa: conSesion() siempre pone las dos. Se saca el usuario ANTES de
-- SET ROLE, como postgres, porque despues RLS ya no dejaria leerlo.
SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = '1' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = '1'; SET lis.sucursal_id = '1';
DELETE FROM core.paciente WHERE paciente_id = 1;
RESET ROLE;

\echo ''
\echo '=== 5 · Lo que cruza entre empresas son DOS filas, no una ========'
\echo '    esperado: 1 y 1 · antes eran 2 y 2, la misma fila vista dos veces'
SELECT sucursal_id AS s_lab FROM core.sucursal WHERE empresa_id = :lab \gset
SELECT sucursal_id AS s_cli FROM core.sucursal WHERE empresa_id = :cli \gset
SELECT plataforma.crear_enlace(:s_cli, :s_lab, 'said') AS enl \gset

SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'s_lab'; SET lis.usuario_id = :'usuario_id';
SELECT core.entregar(:lab, :enl, 'solicitud', '{"pruebas":["hemograma"]}'::jsonb,
                     :usuario_id) IS NOT NULL AS se_entrego;
SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'s_lab'; SELECT count(*) AS ve_quien_mando   FROM core.mensaje;
SET lis.empresa_id = :'cli'; SET lis.sucursal_id = :'s_cli'; SELECT count(*) AS ve_quien_recibio FROM core.mensaje;
RESET ROLE;

\echo ''
\echo '=== 6 · Y ninguna puede escribir la fila de la otra ==============='
\echo '    esperado: ERROR row-level security policy'

SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'lab' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'s_lab';
INSERT INTO core.mensaje (empresa_id, enlace_id, sucursal_id, direccion, tipo, contenido, estado)
VALUES (:cli, :enl, :s_cli, 'recibido', 'aviso', '{}'::jsonb, 'recibido');
RESET ROLE;

\echo '=== 7 · Fusion de duplicados sin mover historia ==================='
\echo '    esperado: el duplicado apunta al ganador y queda auditado'
INSERT INTO core.paciente (empresa_id, expediente, nombre_completo, fecha_nacimiento, sexo)
VALUES (1, core.siguiente_correlativo(1, NULL, 'expediente'), 'SAID G. HOCH', DATE '2004-11-15', 'masculino')
RETURNING paciente_id \gset
SET lis.empresa_id = '1'; SET lis.sucursal_id = '1';
SELECT core.fusionar_paciente(:paciente_id, 1, 1);
SELECT paciente_id, expediente, fusionado_en_paciente_id FROM core.paciente ORDER BY paciente_id;
SELECT accion, nombre_tabla, registro_id FROM audit.evento;

\echo ''
\echo '=== 8 · Toda tabla con empresa_id tiene RLS activo y forzado ======'
\echo '    esperado: cero filas'
SELECT n.nspname AS esquema, c.relname AS tabla_sin_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
WHERE n.nspname IN ('core','lab','integra')
  AND c.relkind = 'r'
  AND NOT (c.relrowsecurity AND c.relforcerowsecurity);

\echo ''
\echo '=== 9 · Un dato solo cruza por core.entregar(), y por ningun otro lado'
\echo '    esperado: cero filas · si aparece una segunda funcion, algo se torcio'
SELECT n.nspname||'.'||p.proname AS tambien_escribe_a_otra_empresa
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('core','lab','integra','audit','plataforma')
  AND p.prosrc LIKE '%INSERT INTO core.mensaje%'
  AND p.proname <> 'entregar';

\echo ''
\echo '=== 10 · Sin enlace vigente el mensaje NO SALE ===================='
\echo '    esperado: ERROR no hay ninguna ruta vigente'
UPDATE plataforma.enlace SET vigente_hasta = CURRENT_DATE WHERE enlace_id = :enl;
SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'s_lab'; SET lis.usuario_id = :'usuario_id';
SELECT core.entregar(:lab, :enl, 'solicitud', '{}'::jsonb, :usuario_id);
RESET ROLE;
\echo '    -> cortar una ruta es ponerle fecha a la propia fila. Efecto inmediato.'
