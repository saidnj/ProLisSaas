-- =====================================================================
-- 94 · Pruebas de modulos, licencia y permisos de rol
--
-- Lo que un usuario puede hacer es la INTERSECCION de dos cosas:
--   ROL       lo que el administrador le dio   core.rol_permiso
--   LICENCIA  lo que el operador le vendio     plataforma.modulo_sucursal
--
-- Diez escenarios. Cada bloque dice que espera. Los que esperan ERROR lo
-- esperan de verdad: son la prueba. Se corre sobre una base recien construida.
--
--   psql -d prolissaas -f 94_pruebas_modulos.sql
--
-- Esperado: 4 errores (bloques 1, 2, 3 y 8) y ninguno mas.
-- =====================================================================

\set ON_ERROR_STOP off

-- El operador da de alta un modulo que esta empresa NO contrata.
INSERT INTO plataforma.modulo (modulo_id, nombre)
VALUES ('rayos_x', 'Rayos X');
INSERT INTO plataforma.permiso (permiso_id, modulo_id, descripcion)
VALUES ('radiografia.crear', 'rayos_x', 'Crear una orden de radiografia');

SELECT core.crear_empresa('Lab Prueba','08011111111111','Central','CEN') AS emp \gset
SELECT sucursal_id AS suc FROM core.sucursal WHERE empresa_id = :emp \gset

-- Ana es recepcionista. Luis administra.
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp,'Ana','Lopez')
  RETURNING empleado_id AS e_ana \gset
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp,'Luis','Mejia')
  RETURNING empleado_id AS e_luis \gset
SELECT rol_id AS r_recep FROM core.rol WHERE empresa_id=:emp AND nombre='Recepcion' \gset
SELECT rol_id AS r_admin FROM core.rol WHERE empresa_id=:emp AND nombre='Administrador' \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
  VALUES (:emp,:e_ana,:r_recep,'ana','x')  RETURNING usuario_id AS u_ana \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
  VALUES (:emp,:e_luis,:r_admin,'luis','x') RETURNING usuario_id AS u_luis \gset


\echo ''
\echo '=== 1 · rol_permiso no se escribe a mano ============================'
\echo '    esperado: permission denied for table rol_permiso'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_ana;
INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  VALUES (:r_recep, 'usuario.administrar', :emp);
ROLLBACK;
RESET ROLE;


\echo ''
\echo '=== 2 · quien no administra usuarios no cambia permisos ============='
\echo '    esperado: ERROR de permiso. Ana es recepcionista'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_ana;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['usuario.administrar']);
ROLLBACK;
RESET ROLE;


\echo ''
\echo '=== 3 · ni el administrador mete permisos de un modulo ajeno ========'
\echo '    esperado: ERROR que NOMBRA radiografia.crear'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_luis;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['paciente.ver','radiografia.crear']);
ROLLBACK;
RESET ROLE;


\echo ''
\echo '=== 4 · el administrador si puede, y queda en la bitacora ==========='
\echo '    esperado: 3, y un evento rol.permisos_cambiar con antes y despues'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SET LOCAL lis.usuario_id = :u_luis;
SELECT core.asignar_permisos_a_rol(
  :r_recep, ARRAY['paciente.ver','paciente.crear','orden.crear']) AS permisos_del_rol;
COMMIT;
RESET ROLE;
SELECT accion, jsonb_array_length(datos_antes->'permisos') AS cuantos_antes,
       datos_despues->'permisos' AS despues
FROM audit.evento WHERE accion = 'rol.permisos_cambiar';


\echo ''
\echo '=== 5 · con la licencia encendida, el permiso funciona =============='
\echo '    esperado: t / t'
SELECT core.usuario_puede('orden.crear', :u_ana)          AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana) AS en_la_sede;


\echo ''
\echo '=== 6 · el operador apaga lab_clinico: se cae el acceso ============='
\echo '    esperado: f / f, y la fila de rol_permiso INTACTA'
UPDATE plataforma.modulo_sucursal
   SET activo = false, desactivado_en = now()
 WHERE empresa_id = :emp AND modulo_id = 'lab_clinico';

SELECT core.usuario_puede('orden.crear', :u_ana)          AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana) AS en_la_sede;
SELECT count(*) AS filas_de_rol_permiso_intactas
FROM core.rol_permiso WHERE rol_id = :r_recep AND permiso_id = 'orden.crear';


\echo ''
\echo '=== 7 · vuelve a pagar: el acceso vuelve solo ======================='
\echo '    esperado: t / t, sin que el administrador rearme nada'
UPDATE plataforma.modulo_sucursal
   SET activo = true, desactivado_en = NULL
 WHERE empresa_id = :emp AND modulo_id = 'lab_clinico';

SELECT core.usuario_puede('orden.crear', :u_ana)          AS en_la_empresa,
       core.usuario_puede_en('orden.crear', :suc, :u_ana) AS en_la_sede;


\echo ''
\echo '=== 8 · el laboratorio no se vende modulos a si mismo ==============='
\echo '    esperado: permission denied for table modulo_sucursal'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, asignado_por)
  VALUES (:suc, 'rayos_x', :emp, 'yo mismo');
ROLLBACK;
RESET ROLE;


\echo ''
\echo '=== 9 · pero si lee los suyos, para pintar el menu =================='
\echo '    esperado: core y lab_clinico; 16 y 14 permisos'
BEGIN;
SET ROLE lis_app;
SET LOCAL lis.empresa_id = :emp;
SELECT modulo_id, activo FROM plataforma.modulo_sucursal ORDER BY 1;
SELECT modulo_id, count(*) AS permisos_en_el_menu
FROM core.permisos_disponibles() GROUP BY 1 ORDER BY 1;
COMMIT;
RESET ROLE;


\echo ''
\echo '=== 10 · el alta enciende core: sus permisos no se caen ============='
\echo '    esperado: core contratado, lab_clinico contratado, rayos_x no'
SELECT p.modulo_id, count(*) AS permisos,
       CASE WHEN EXISTS (SELECT 1 FROM plataforma.modulo_sucursal ms
                         WHERE ms.empresa_id = :emp
                           AND ms.modulo_id = p.modulo_id AND ms.activo)
            THEN 'contratado' ELSE 'sin contratar' END AS licencia
FROM plataforma.permiso p GROUP BY 1 ORDER BY 1;
