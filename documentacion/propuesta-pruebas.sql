-- Prueba de la propuesta. Cada bloque dice que espera.
\set ON_ERROR_STOP off

-- El operador da de alta un modulo que esta empresa no contrata
INSERT INTO plataforma.modulo (modulo_id,nombre) VALUES ('rayos_x','Rayos X');
INSERT INTO plataforma.permiso (permiso_id,modulo_id,descripcion)
VALUES ('radiografia.crear','rayos_x','Crear una orden de radiografia');

SELECT core.crear_empresa('Lab Prueba','08011111111111','Central','CEN') AS emp \gset
SELECT sucursal_id AS suc FROM core.sucursal WHERE empresa_id = :emp \gset

-- El alta todavia no mete 'core' (eso es del flujo, H-91): lo hace la migracion
INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, asignado_por)
VALUES (:suc,'core',:emp,'operador') ON CONFLICT DO NOTHING;

-- Ana, recepcionista. Luis, administrador.
INSERT INTO core.empleado (empresa_id,nombres,apellidos) VALUES (:emp,'Ana','Lopez')
  RETURNING empleado_id AS e_ana \gset
INSERT INTO core.empleado (empresa_id,nombres,apellidos) VALUES (:emp,'Luis','Mejia')
  RETURNING empleado_id AS e_luis \gset
SELECT rol_id AS r_recep FROM core.rol WHERE empresa_id=:emp AND nombre='Recepcion' \gset
SELECT rol_id AS r_admin FROM core.rol WHERE empresa_id=:emp AND nombre='Administrador' \gset
INSERT INTO core.usuario (empresa_id,empleado_id,rol_id,username,password_hash)
  VALUES (:emp,:e_ana,:r_recep,'ana','x') RETURNING usuario_id AS u_ana \gset
INSERT INTO core.usuario (empresa_id,empleado_id,rol_id,username,password_hash)
  VALUES (:emp,:e_luis,:r_admin,'luis','x') RETURNING usuario_id AS u_luis \gset

\echo ''
\echo '################ 1 · Ana ya no puede escribir rol_permiso directo'
\echo '   esperado: permission denied'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_ana;
INSERT INTO core.rol_permiso (rol_id,permiso_id,empresa_id)
  VALUES (:r_recep,'usuario.administrar',:emp);
ROLLBACK;
RESET ROLE;

\echo ''
\echo '################ 2 · Ana llama la funcion: no es administradora'
\echo '   esperado: ERROR de permiso'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_ana;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['usuario.administrar']);
ROLLBACK;
RESET ROLE;

\echo ''
\echo '################ 3 · Luis (admin) mete un permiso de un modulo NO contratado'
\echo '   esperado: ERROR nombrando radiografia.crear'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_luis;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['paciente.ver','radiografia.crear']);
ROLLBACK;
RESET ROLE;

\echo ''
\echo '################ 4 · Luis mete permisos legitimos'
\echo '   esperado: devuelve 3 y queda registrado en audit.evento'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_luis;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['paciente.ver','paciente.crear','orden.crear']) AS permisos_del_rol;
COMMIT;
RESET ROLE;
SELECT accion, datos_antes->'permisos' AS antes, datos_despues->'permisos' AS despues
FROM audit.evento WHERE accion='rol.permisos_cambiar';

\echo ''
\echo '################ 5 · Ana ahora puede lo que su rol dice'
\echo '   esperado: t / t'
SELECT core.usuario_puede('orden.crear', :u_ana)             AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana)    AS en_la_sede;

\echo ''
\echo '################ 6 · El operador apaga lab_clinico (dejan de pagarlo)'
\echo '   esperado: f / f, SIN tocar rol_permiso'
UPDATE plataforma.modulo_sucursal
   SET activo = false, desactivado_en = now()
 WHERE empresa_id = :emp AND modulo_id = 'lab_clinico';
SELECT core.usuario_puede('orden.crear', :u_ana)          AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana) AS en_la_sede;
SELECT count(*) AS filas_de_rol_permiso_intactas
FROM core.rol_permiso WHERE rol_id = :r_recep AND permiso_id = 'orden.crear';

\echo ''
\echo '################ 7 · Vuelve a pagar: se enciende y el permiso vuelve solo'
\echo '   esperado: t / t'
UPDATE plataforma.modulo_sucursal
   SET activo = true, desactivado_en = NULL
 WHERE empresa_id = :emp AND modulo_id = 'lab_clinico';
SELECT core.usuario_puede('orden.crear', :u_ana)          AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana) AS en_la_sede;

\echo ''
\echo '################ 8 · El laboratorio no puede encenderse un modulo'
\echo '   esperado: permission denied'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
INSERT INTO plataforma.modulo_sucursal (sucursal_id,modulo_id,empresa_id,asignado_por)
  VALUES (:suc,'rayos_x',:emp,'yo mismo');
ROLLBACK;
RESET ROLE;

\echo ''
\echo '################ 9 · Pero si puede LEER los suyos, para pintar el menu'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SELECT modulo_id, activo FROM plataforma.modulo_sucursal ORDER BY 1;
SELECT modulo_id, count(*) AS permisos_en_el_menu
FROM core.permisos_disponibles() GROUP BY 1 ORDER BY 1;
COMMIT;
RESET ROLE;

\echo ''
\echo '################ 10 · Los 16 permisos de core ya no se caen'
SELECT p.modulo_id, count(*) AS permisos,
       CASE WHEN EXISTS (SELECT 1 FROM plataforma.modulo_sucursal ms
                         WHERE ms.empresa_id=:emp AND ms.modulo_id=p.modulo_id AND ms.activo)
            THEN 'contratado' ELSE '*** SE CAEN ***' END AS licencia
FROM plataforma.permiso p GROUP BY 1 ORDER BY 1;
