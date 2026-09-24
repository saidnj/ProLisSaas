-- =====================================================================
-- ProLisSaas · 97 · Identidad local, enlace y mensaje
--
-- La pregunta que contestan estas pruebas:
--   "¿de verdad dos empresas pueden trabajar juntas sin compartir una sola
--    fila, y de verdad no pueden hacerlo sin que el operador las conecte?"
--
-- Reemplazan a las pruebas del registro de identidad compartida, que se
-- retiro con plataforma.persona (H-73).
-- =====================================================================

\set ON_ERROR_STOP off

-- El caso del primer cliente: un laboratorio con DOS sedes, una adentro del
-- hospital y otra afuera. Y el hospital, que es otra empresa.
SELECT core.crear_empresa('Laboratorio Ochoa','0801-1990-111111','Sede Central','LFO') AS lab \gset
SELECT core.crear_empresa('Hospital San Jose','0801-1990-222222','Consulta Externa','HSJ') AS hos \gset

INSERT INTO core.sucursal (empresa_id, nombre, codigo)
VALUES (:lab, 'Sede Hospital', 'LFOH') RETURNING sucursal_id AS suc_lab_hosp \gset
SELECT sucursal_id AS suc_lab_centro FROM core.sucursal
 WHERE empresa_id = :lab AND codigo = 'LFO' \gset
SELECT sucursal_id AS suc_hos FROM core.sucursal WHERE empresa_id = :hos \gset

-- Un usuario administrador en cada empresa.
INSERT INTO core.empleado (empresa_id, nombres, apellidos, numero_colegiacion)
VALUES (:lab,'Said','Hoch','BQ-1234') RETURNING empleado_id AS emp_lab \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :lab, :emp_lab, rol_id, 'said', 'x' FROM core.rol
 WHERE empresa_id = :lab AND nombre = 'Administrador'
RETURNING usuario_id AS u_lab \gset

INSERT INTO core.empleado (empresa_id, nombres, apellidos)
VALUES (:hos,'Rosa','Lopez') RETURNING empleado_id AS emp_hos \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :hos, :emp_hos, rol_id, 'rosa', 'x' FROM core.rol
 WHERE empresa_id = :hos AND nombre = 'Administrador'
RETURNING usuario_id AS u_hos \gset


\echo ''
\echo '=== 1 · Registrar un paciente ya no depende de ningun registro global =='
\echo '    esperado: un expediente EXP-000001'
SELECT * FROM core.registrar_paciente(
  :lab,'SAID GABRIEL','HOCH URBINA','identidad','0801200400844',
  DATE '2004-11-15','masculino', NULL, NULL, NULL, :u_lab);


\echo ''
\echo '=== 2 · El mismo documento repetido DENTRO de la empresa se atrapa ===='
\echo '    esperado: ERROR que manda al expediente que ya existe'
SELECT * FROM core.registrar_paciente(
  :lab,'SAID G.','HOCH','identidad','0801200400844',
  DATE '2004-11-15','masculino', NULL, NULL, NULL, :u_lab);


\echo ''
\echo '=== 3 · Y el MISMO documento en la otra empresa ahora SI se permite ==='
\echo '    esperado: expediente propio del hospital. Antes se vinculaba a una'
\echo '    fila compartida; ahora los dos expedientes son independientes.'
SELECT * FROM core.registrar_paciente(
  :hos,'SAID GABRIEL','HOCH URBINA','identidad','0801200400844',
  DATE '2004-11-15','masculino', NULL, NULL, NULL, :u_hos);

SELECT paciente_id AS pac_lab FROM core.paciente WHERE empresa_id = :lab LIMIT 1 \gset
SELECT paciente_id AS pac_hos FROM core.paciente WHERE empresa_id = :hos LIMIT 1 \gset


\echo ''
\echo '=== 4 · SIN ENLACE no se puede mandar nada ============================'
\echo '    esperado: ERROR no hay ninguna ruta vigente'
SET ROLE lis_app; SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos'; SET lis.usuario_id = :'u_hos';
SELECT core.entregar(:hos, 1, 'solicitud', '{"prueba":"hemograma"}'::jsonb, :u_hos);
RESET ROLE;


\echo ''
\echo '=== 5 · Ni anotar una referencia hacia una empresa sin ruta ==========='
\echo '    esperado: ERROR no hay ninguna ruta vigente con esa empresa'
SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'suc_lab_centro'; SET lis.usuario_id = :'u_lab';
SELECT core.anotar_referencia(:lab, :pac_lab, :hos, 'H-000123', :u_lab);
RESET ROLE;


\echo ''
\echo '=== 6 · El operador conecta DOS SEDES, no dos empresas ================'
\echo '    esperado: un enlace entre la Consulta Externa y la Sede Hospital'
SELECT plataforma.crear_enlace(:suc_hos, :suc_lab_hosp, 'said',
       'El laboratorio opera adentro del hospital') AS enlace \gset
SELECT :enlace AS enlace_id;

\echo ''
\echo '    y NO deja enlazar dos sedes de la misma empresa'
\echo '    esperado: ERROR las dos sedes son de la misma empresa'
SELECT plataforma.crear_enlace(:suc_lab_centro, :suc_lab_hosp, 'said');


\echo ''
\echo '=== 7 · Cada empresa ve SOLO SU LADO de la ruta ======================='
\echo '    esperado: el hospital ve su Consulta Externa, el lab su Sede Hospital'
\echo '    y ninguno ve la sucursal del otro'
-- Desde que las politicas llaman a core.sesion_vigente(), el contexto necesita
-- las DOS variables. Poner solo la empresa era un atajo que el sistema real
-- nunca usa: conSesion() siempre pone las dos. Se saca el usuario ANTES de
-- SET ROLE, como postgres, porque despues RLS ya no dejaria leerlo.
SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'hos' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos';
SELECT 'hospital' AS quien, mi_sucursal_id, contraparte_nombre FROM core.mis_enlaces();
SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'suc_lab_centro';
SELECT 'laboratorio' AS quien, mi_sucursal_id, contraparte_nombre FROM core.mis_enlaces();
RESET ROLE;


\echo ''
\echo '=== 8 · Entregar escribe UNA FILA DE CADA LADO, con el mismo folio ===='
SET ROLE lis_app; SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos'; SET lis.usuario_id = :'u_hos';
SELECT core.entregar(:hos, :enlace, 'solicitud',
  '{"expediente":"H-000123","pruebas":["hemograma"],"ayuno":true}'::jsonb,
  :u_hos) AS folio \gset
RESET ROLE;

\echo '    esperado: dos filas, mismo folio, empresas distintas, direcciones distintas'
SELECT empresa_id, direccion, estado, sucursal_id FROM core.mensaje
 WHERE folio = :'folio' ORDER BY direccion;


\echo ''
\echo '=== 9 · Y cada una ve solo la suya. Ninguna fila compartida ==========='
\echo '    esperado: 1 y 1, no 2 y 2'

SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'hos' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app;
SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos'; SELECT count(*) AS ve_el_hospital FROM core.mensaje;
SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'suc_lab_centro'; SELECT count(*) AS ve_el_laboratorio FROM core.mensaje;
RESET ROLE;


\echo ''
\echo '=== 10 · La solicitud cayo en la SEDE DE ADENTRO, no en la de afuera =='
\echo '    esperado: la sucursal Sede Hospital'
SELECT s.nombre AS cayo_en FROM core.mensaje m
  JOIN core.sucursal s ON s.sucursal_id = m.sucursal_id
 WHERE m.folio = :'folio' AND m.direccion = 'recibido';


\echo ''
\echo '=== 11 · Una empresa no puede escribirle una fila a otra =============='
\echo '    esperado: ERROR row-level security policy'

SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'hos' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos';
INSERT INTO core.mensaje (empresa_id, enlace_id, sucursal_id, direccion, tipo, contenido, estado)
VALUES (:lab, :enlace, :suc_lab_hosp, 'recibido', 'aviso', '{}'::jsonb, 'recibido');
RESET ROLE;


\echo ''
\echo '=== 12 · Con la ruta viva, la referencia externa ya se puede anotar ==='
\echo '    esperado: un id de referencia'
SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'suc_lab_centro'; SET lis.usuario_id = :'u_lab';
SELECT core.anotar_referencia(:lab, :pac_lab, :hos, 'H-000123', :u_lab) AS ref \gset
SELECT :ref AS referencia_id;

\echo ''
\echo '    y no se puede anotar una segunda vigente para la misma contraparte'
\echo '    esperado: ERROR uq_referencia_vigente'
SELECT core.anotar_referencia(:lab, :pac_lab, :hos, 'H-999999', :u_lab);
RESET ROLE;


\echo ''
\echo '=== 13 · Una referencia mal confirmada se ANULA con motivo ============'
\echo '    esperado: ERROR sin motivo, y despues se deja escribir otra'
SET ROLE lis_app; SET lis.empresa_id = :'lab'; SET lis.sucursal_id = :'suc_lab_centro'; SET lis.usuario_id = :'u_lab';
SELECT core.anular_referencia(:ref, '   ', :u_lab);
SELECT core.anular_referencia(:ref, 'Se confirmo al paciente equivocado', :u_lab);
SELECT core.anotar_referencia(:lab, :pac_lab, :hos, 'H-000456', :u_lab) AS ref2;
RESET ROLE;

\echo '    esperado: dos filas en el historial, una sola vigente'
SELECT count(*) AS en_el_historial,
       count(*) FILTER (WHERE anulada_en IS NULL) AS vigentes
FROM core.paciente_referencia WHERE paciente_id = :pac_lab;


\echo ''
\echo '=== 14 · El hospital NO ve la referencia del laboratorio =============='
\echo '    esperado: 0'

SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'hos' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'hos'; SET lis.sucursal_id = :'suc_hos';
SELECT count(*) AS ve_el_hospital FROM core.paciente_referencia;
RESET ROLE;


\echo ''
\echo '=== 15 · Ninguna politica del sistema compara dos empresas ============'
\echo '    esperado: cero filas · era rls_derivacion y se fue'
SELECT policyname, tablename FROM pg_policies
WHERE qual LIKE '%empresa_origen%' OR qual LIKE '%empresa_destino%'
   OR with_check LIKE '%empresa_destino%';


\echo ''
\echo '=== 16 · Y no queda rastro de la identidad compartida ================='
\echo '    esperado: cero filas'
SELECT n.nspname||'.'||c.relname AS sobrevivio
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname IN ('persona','conflicto_identidad','empresa_asociada','derivacion');
