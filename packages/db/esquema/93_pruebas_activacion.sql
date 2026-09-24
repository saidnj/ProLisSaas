-- =====================================================================
-- ProLisSaas - 93 - El estreno de una contrasena
--
-- Necesita una base recien cargada con 01..06 y 07_datos_prueba.sql.
--
-- Simula lo que hace el API: la verificacion argon2 del codigo ocurre en la
-- aplicacion, asi que aqui se dan por buenos los hashes y se prueba todo lo
-- demas -- que es donde estan las reglas.
-- =====================================================================

\set ON_ERROR_STOP off
\echo ''
\echo '################ 0 · el admin abre sesion ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='marlon.ochoa'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='marlon.ochoa'),true);
    -- La sede tambien: usuario_puede() exige el modulo encendido EN LA SEDE del
    -- contexto, y crear_usuario / generar_activacion la llaman.
    PERFORM set_config('lis.sucursal_id',(SELECT min(s.sucursal_id)::text FROM core.sucursal s JOIN core.usuario u ON u.empresa_id = s.empresa_id WHERE u.username='marlon.ochoa'),true);
  END $$;
  SET LOCAL ROLE lis_app;
  SELECT current_user AS rol, core.usuario_puede('usuario.administrar') AS puede_crear_usuarios;

\echo ''
\echo '################ 1 · crea un empleado y su usuario ################'
\echo '   esperado: el usuario nace en pendiente_activacion, sin clave'
  INSERT INTO core.empleado (empresa_id, nombres, apellidos, documento, cargo, activo)
  VALUES (core.empresa_actual(),'Prueba','Activacion','0801200000001','Tecnico',true);

  SELECT core.crear_usuario(
    (SELECT empleado_id FROM core.empleado WHERE documento='0801200000001'),
    (SELECT rol_id FROM core.rol WHERE empresa_id=core.empresa_actual() AND nombre='Recepcion'),
    'prueba.activacion') AS usuario_nuevo;

  RESET ROLE;  -- el hash ya no lo lee lis_app: se comprueba como postgres
  SELECT username, estado, password_hash = '' AS sin_clave
  FROM core.usuario WHERE username='prueba.activacion';
  SET LOCAL ROLE lis_app;

\echo ''
\echo '################ 2 · genera el codigo ################'
\echo '   esperado: una fila, con su vencimiento'
  SELECT * FROM core.generar_activacion(
    (SELECT usuario_id FROM core.usuario WHERE username='prueba.activacion'),
    '$argon2id$v=19$m=65536,p=4,t=3$CODIGOFALSO$hashdelcodigodeactivacion', 24);
COMMIT;

\echo ''
\echo '################ 3 · la pantalla de activacion, SIN sesion ################'
\echo '   esperado: encuentra el codigo vivo aunque no haya contexto'
BEGIN;
  SET LOCAL ROLE lis_app;
  SELECT usuario_id, empresa_id, left(codigo_hash,18)||'...' AS hash, intentos_fallidos
  FROM core.buscar_activacion('prueba.activacion');
ROLLBACK;

\echo ''
\echo '################ 4 · activa: gasta el codigo y estrena la clave ################'
BEGIN;
  SET LOCAL ROLE lis_app;
  SELECT * FROM core.activar_usuario(
    -- El API NO lee core.activacion: no tiene privilegio. Saca el id de
    -- buscar_activacion(), que es SECURITY DEFINER. Asi va a ser de verdad.
    (SELECT activacion_id FROM core.buscar_activacion('prueba.activacion')),
    '$argon2id$v=19$m=65536,p=4,t=3$CLAVENUEVA$hashdelaclavequeellaeligio');
COMMIT;

SELECT username, estado, left(password_hash,18)||'...' AS clave
FROM core.usuario WHERE username='prueba.activacion';

\echo ''
\echo '################ 5 · el codigo ya no sirve ################'
\echo '   esperado: ERROR 28000, el codigo ya se uso'
BEGIN;
  SET LOCAL ROLE lis_app;
  SELECT * FROM core.activar_usuario(
    (SELECT coalesce((SELECT activacion_id FROM core.buscar_activacion('prueba.activacion')), -1)),
    '$argon2id$v=19$m=65536,p=4,t=3$OTRA$intentodereusarelcodigo');
ROLLBACK;

\echo ''
\echo '################ 6 · la puerta de al lado esta cerrada ################'
\echo '   esperado: ERROR permission denied -- no se puede crear un usuario a mano'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id','1',true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='marlon.ochoa'),true);
    PERFORM set_config('lis.sucursal_id',(SELECT min(sucursal_id)::text FROM core.sucursal WHERE empresa_id = 1),true);
  END $$;
  SET LOCAL ROLE lis_app;
  INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash, estado)
  VALUES (1, 1, 1, 'colado', 'clave_que_yo_se', 'activo');
ROLLBACK;

\echo ''
\echo '################ 7 · quien no tiene permiso no crea usuarios ################'
\echo '   esperado: ERROR 42501 -- Carla es Recepcion'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id','1',true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='carla.nunez'),true);
    PERFORM set_config('lis.sucursal_id',(SELECT min(sucursal_id)::text FROM core.sucursal WHERE empresa_id = 1),true);
  END $$;
  SET LOCAL ROLE lis_app;
  SELECT core.crear_usuario(2, 1, 'otro.colado');
ROLLBACK;

\echo ''
\echo '################ 8 · la tabla de codigos es invisible para la app ################'
\echo '   esperado: ERROR permission denied for table activacion'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id','1',true);
    PERFORM set_config('lis.usuario_id','1',true);
  END $$;
  SET LOCAL ROLE lis_app;
  SELECT count(*) FROM core.activacion;
ROLLBACK;
