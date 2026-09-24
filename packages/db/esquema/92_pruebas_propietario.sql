-- =====================================================================
-- ProLisSaas · 92 · Pruebas: quien administra a los que administran
--
-- Dos clases de cuenta: el PROPIETARIO (la que entrega el operador, rol
-- es_sistema, con usuario.nombrar_admin) y los ADMINISTRADORES (cualquier
-- rol con usuario.administrar). Todo lo que toque quien administra es del
-- propietario. Aqui se prueba cada puerta.
--
--   createdb p_92 · psql -d p_92 -f 01..08 y luego este archivo
--
-- Cada bloque abre su propia transaccion y la deshace: las pruebas no se
-- ensucian entre si y el orden no importa.
-- =====================================================================

\set ON_ERROR_STOP off

-- Sesiones que se reutilizan. Las tres son de la empresa 1 (Laboratorio Ochoa).
--   marlon.ochoa   Propietario
--   gabriela.sierra Jefe de sede (ya SIN usuario.administrar)
--   carla.nunez    Recepcion
SELECT empresa_id AS emp FROM core.empresa WHERE rtn = '08019016543210' \gset
SELECT usuario_id AS u_marlon   FROM core.usuario WHERE username = 'marlon.ochoa'    \gset
SELECT usuario_id AS u_gabriela FROM core.usuario WHERE username = 'gabriela.sierra' \gset
SELECT usuario_id AS u_carla    FROM core.usuario WHERE username = 'carla.nunez'     \gset
SELECT usuario_id AS u_beto     FROM core.usuario WHERE username = 'beto.rivas'      \gset
SELECT rol_id AS r_prop  FROM core.rol WHERE empresa_id = :emp AND nombre = 'Propietario'   \gset
SELECT rol_id AS r_admin FROM core.rol WHERE empresa_id = :emp AND nombre = 'Administrador' \gset
SELECT rol_id AS r_recep FROM core.rol WHERE empresa_id = :emp AND nombre = 'Recepcion'     \gset
SELECT rol_id AS r_jefe  FROM core.rol WHERE empresa_id = :emp AND nombre = 'Jefe de sede'  \gset
SELECT sucursal_id AS s_cen FROM core.sucursal WHERE empresa_id = :emp AND codigo = 'CEN' \gset

-- Un administrador de carne y hueso para las pruebas: Beto pasa a
-- Administrador (como postgres, que es el operador haciendo trampa a
-- proposito; las pruebas de abajo son las que deciden quien puede).
UPDATE core.usuario SET rol_id = :r_admin WHERE usuario_id = :u_beto;

\echo ''
\echo '=== 0 · Como quedaron los roles ====================================='
\echo '    esperado: solo Propietario es_sistema; Propietario 31, Administrador 30'
\echo '              (la diferencia es usuario.nombrar_admin); Jefe de sede sin usuario.administrar'
SELECT r.nombre, r.es_sistema, count(rp.*) AS permisos,
       bool_or(rp.permiso_id = 'usuario.nombrar_admin') AS extra,
       core.rol_es_admin(r.rol_id) AS es_admin
FROM core.rol r LEFT JOIN core.rol_permiso rp USING (rol_id)
WHERE r.empresa_id = :emp
GROUP BY r.rol_id, r.nombre, r.es_sistema ORDER BY r.es_sistema DESC, permisos DESC;

\echo ''
\echo '=== 1 · El rol del propietario no se cambia, ni por el mismo =========='
\echo '    esperado: ERROR "El rol del propietario no se cambia"'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_marlon, :r_admin, 'me bajo yo mismo');
ROLLBACK;

\echo ''
\echo '=== 2 · El rol del propietario no se asigna ==========================='
\echo '    esperado: ERROR "no se asigna: se traspasa" (cambiar_rol) y otra vez en crear_usuario'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_prop, 'que sea duena');
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'Segundo', 'Dueno')
  RETURNING empleado_id AS e_dueno \gset
SELECT core.crear_usuario(:e_dueno, :r_prop, 'segundo.dueno');
ROLLBACK;

\echo ''
\echo '=== 3 · Un administrador NO nombra administradores ===================='
\echo '    esperado: ERROR "Solo el propietario nombra administradores" (crear) y'
\echo '              "Solo el propietario nombra o retira administradores" (cambiar)'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'Clon', 'De Beto')
  RETURNING empleado_id AS e_clon \gset
SELECT core.crear_usuario(:e_clon, :r_admin, 'clon.beto');
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_admin, 'ascenso');
ROLLBACK;

\echo ''
\echo '=== 4 · ...pero si crea y cambia cuentas corrientes =================='
\echo '    esperado: un usuario_id, luego t (Carla pasa a Jefe de sede), y el evento'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'Nueva', 'Recepcionista')
  RETURNING empleado_id AS e_nueva \gset
SELECT core.crear_usuario(:e_nueva, :r_recep, 'nueva.recep') IS NOT NULL AS creo;
SELECT core.cambiar_rol(:u_carla, :r_jefe, 'cubre la jefatura de Norte') AS cambio;
SELECT accion, datos_antes->>'rol' AS de, datos_despues->>'rol' AS a, datos_despues->>'motivo' AS motivo
FROM audit.evento WHERE accion = 'usuario.rol_cambiar';
ROLLBACK;

\echo ''
\echo '=== 5 · Un administrador no le baja el rol a otro administrador ======='
\echo '    esperado: ERROR "Solo el propietario nombra o retira administradores"'
UPDATE core.usuario SET rol_id = :r_admin WHERE usuario_id = :u_carla;   -- Carla tambien es admin un momento
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_recep, 'la bajo');
ROLLBACK;

\echo ''
\echo '=== 6 · El propietario si: nombra, retira, y queda en la bitacora ====='
\echo '    esperado: t, t, y dos eventos'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_recep, 'vuelve a recepcion') AS retiro;
SELECT core.cambiar_rol(:u_carla, :r_admin, 'la nombra otra vez') AS nombro;
SELECT count(*) AS eventos FROM audit.evento WHERE accion = 'usuario.rol_cambiar';
ROLLBACK;
UPDATE core.usuario SET rol_id = :r_recep WHERE usuario_id = :u_carla;   -- Carla vuelve a ser Recepcion

\echo ''
\echo '=== 7 · Mismo rol: no hay cambio ni evento ============================'
\echo '    esperado: f y 0'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_recep) AS cambio;
SELECT count(*) AS eventos FROM audit.evento WHERE accion = 'usuario.rol_cambiar';
ROLLBACK;

\echo ''
\echo '=== 8 · Sin usuario.administrar no se cambia ningun rol ==============='
\echo '    esperado: ERROR "No tiene permiso para cambiar roles" (Gabriela es Jefe de sede)'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_gabriela'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_jefe, 'la subo');
ROLLBACK;

\echo ''
\echo '=== 9 · rol_id ya no se escribe a mano ================================'
\echo '    esperado: ERROR permission denied for table usuario'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.usuario SET rol_id = :r_admin WHERE usuario_id = :u_carla;
ROLLBACK;
\echo '    (y las dos columnas que antes usaba el login tambien estan cerradas: esperado ERROR permission denied; van por registrar_acceso, seccion 20)'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.usuario SET intentos_fallidos = 0, ultimo_acceso_en = now() WHERE usuario_id = :u_carla;
ROLLBACK;

\echo ''
\echo '=== 10 · La cuenta de un administrador la toca solo el propietario ====='
\echo '    esperado: puede_tocar_cuenta -> Beto sobre Carla t, Beto sobre Beto f,'
\echo '              Marlon sobre Beto t; luego ERROR row-level security al moverle'
\echo '              las sedes a Beto siendo Beto, y ERROR "Solo el propietario toca..."'
\echo '              al resetearle el codigo'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.puede_tocar_cuenta(:u_carla) AS beto_sobre_carla,
       core.puede_tocar_cuenta(:u_beto)  AS beto_sobre_beto;
UPDATE core.acceso_sucursal SET activo = false, retirado_en = now(), retirado_motivo = 'me saco yo'
 WHERE usuario_id = :u_beto;
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT * FROM core.generar_activacion(:u_beto, 'hash-de-prueba', 24);
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.puede_tocar_cuenta(:u_beto) AS marlon_sobre_beto;
UPDATE core.acceso_sucursal SET activo = false, retirado_en = now(), retirado_motivo = 'lo saca el dueno'
 WHERE usuario_id = :u_beto;
ROLLBACK;

\echo ''
\echo '=== 11 · Los permisos: lo que toca a quien administra es del propietario'
\echo '    esperado: ERROR "no se editan" (Propietario), ERROR "solo lo tiene el propietario"'
\echo '              (repartir el extra), ERROR "Solo el propietario cambia los permisos"'
\echo '              (Beto le da usuario.administrar a Recepcion), y luego 2 (Beto si edita Recepcion)'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.asignar_permisos_a_rol(:r_prop, ARRAY['paciente.ver']);
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.asignar_permisos_a_rol(:r_admin, ARRAY['usuario.administrar','usuario.nombrar_admin']);
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['paciente.ver','usuario.administrar']);
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.asignar_permisos_a_rol(:r_recep, ARRAY['paciente.ver','paciente.crear']) AS permisos;
ROLLBACK;

\echo ''
\echo '=== 12 · El propietario de OTRA empresa no toca nada aqui ============='
\echo '    esperado: ERROR "Ese usuario no es de esta empresa"'
SELECT usuario_id AS u_carmen FROM core.usuario WHERE username = 'carmen.fonseca' \gset
SELECT empresa_id AS emp2 FROM core.usuario WHERE username = 'carmen.fonseca' \gset
SELECT sucursal_id AS s_sjc FROM core.sucursal WHERE empresa_id = :emp2 LIMIT 1 \gset
BEGIN;
SET LOCAL lis.empresa_id = :'emp2'; SET LOCAL lis.usuario_id = :'u_carmen'; SET LOCAL lis.sucursal_id = :'s_sjc';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_rol(:u_carla, :r_admin, 'desde otra empresa');
ROLLBACK;

\echo ''
\echo '=== 13 · Desbloquear: contador en cero, estado activo, sin codigo nuevo'
\echo '    esperado: ERROR "no esta bloqueada" (Carla esta activa); luego Beto la'
\echo '              desbloquea (estado activo, intentos 0, evento con motivo);'
\echo '              ERROR "Solo el propietario..." cuando Beto intenta con Marlon;'
\echo '              ERROR de permiso cuando lo intenta Gabriela'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.desbloquear_usuario(:u_carla, 'no estaba bloqueada');
ROLLBACK;
UPDATE core.usuario SET estado = 'bloqueado', intentos_fallidos = 5 WHERE usuario_id IN (:u_carla, :u_marlon);
SELECT password_hash AS hash_antes FROM core.usuario WHERE usuario_id = :u_carla \gset
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.desbloquear_usuario(:u_carla, 'se equivoco de teclado');
RESET ROLE;  -- el hash ya no lo lee lis_app (seccion 20): se comprueba como postgres
SELECT estado, intentos_fallidos, password_hash = :'hash_antes' AS misma_clave FROM core.usuario WHERE usuario_id = :u_carla;
SET LOCAL ROLE lis_app;
SELECT accion, datos_antes->>'intentos_fallidos' AS intentos_antes, datos_despues->>'motivo' AS motivo
FROM audit.evento WHERE accion = 'usuario.desbloquear';
SELECT core.desbloquear_usuario(:u_marlon, 'lo intento un administrador');
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_gabriela'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.desbloquear_usuario(:u_carla);
ROLLBACK;
UPDATE core.usuario SET estado = 'activo', intentos_fallidos = 0 WHERE usuario_id IN (:u_carla, :u_marlon);

\echo ''
\echo '=== 14 · El username: formato, duplicado, la guardia, y sin cambio ======'
\echo '    esperado: t (carla -> carla.n); ERROR de formato; ERROR duplicado'
\echo '              (uq_usuario_username); ERROR "Solo el propietario" (Beto a Marlon);'
\echo '              f (mismo nombre); y el evento con antes/despues'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_username(:u_carla, '  Carla.N ') AS cambio;
SELECT username FROM core.usuario WHERE usuario_id = :u_carla;
SELECT accion, datos_antes->>'username' AS de, datos_despues->>'username' AS a
FROM audit.evento WHERE accion = 'usuario.username_cambiar';
SELECT core.cambiar_username(:u_carla, 'carla.n') AS sin_cambio;
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_username(:u_carla, 'carla nunez');
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_username(:u_carla, 'Gabriela.Sierra');
ROLLBACK;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.cambiar_username(:u_marlon, 'el.dueno');
ROLLBACK;

\echo ''
\echo '=== 15 · Empleado inactivo = cuenta suspendida (el trigger) ============'
\echo '    esperado: suspendido; luego activo otra vez (tenia clave), intentos 0,'
\echo '              y el par de eventos suspender/reactivar con su motivo'
SELECT empleado_id AS e_carla FROM core.usuario WHERE usuario_id = :u_carla \gset
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET activo = false WHERE empleado_id = :e_carla;
SELECT estado FROM core.usuario WHERE usuario_id = :u_carla;
UPDATE core.empleado SET activo = true WHERE empleado_id = :e_carla;
SELECT estado, intentos_fallidos FROM core.usuario WHERE usuario_id = :u_carla;
SELECT accion, datos_despues->>'estado' AS a, datos_despues->>'motivo' AS motivo
FROM audit.evento WHERE accion IN ('usuario.suspender','usuario.reactivar') ORDER BY evento_id;
ROLLBACK;
\echo '    (sin clave estrenada vuelve a pendiente_activacion, no a activo: esperado pendiente_activacion)'
BEGIN;
UPDATE core.usuario SET password_hash = '', estado = 'pendiente_activacion' WHERE usuario_id = :u_carla;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET activo = false WHERE empleado_id = :e_carla;
UPDATE core.empleado SET activo = true  WHERE empleado_id = :e_carla;
SELECT estado FROM core.usuario WHERE usuario_id = :u_carla;
ROLLBACK;
\echo '    (un empleado registrado inactivo SI recibe cuenta, pero nace suspendida y sin'
\echo '     codigo: esperado suspendido; ERROR "primero hay que reactivarla" al pedirle'
\echo '     codigo; y al activar al empleado, pendiente_activacion -- nunca tuvo clave)'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
INSERT INTO core.empleado (empresa_id, nombres, apellidos, activo) VALUES (:emp, 'Inactivo', 'Desde el inicio', false)
  RETURNING empleado_id AS e_inactivo \gset
SELECT core.crear_usuario(:e_inactivo, :r_recep, 'inactivo.inicio') AS u_inactivo \gset
RESET ROLE;  -- el hash ya no lo lee lis_app (seccion 20)
SELECT estado, password_hash = '' AS sin_clave FROM core.usuario WHERE usuario_id = :u_inactivo;
SET LOCAL ROLE lis_app;
SAVEPOINT sp;
SELECT * FROM core.generar_activacion(:u_inactivo, 'hash-de-prueba', 24);
ROLLBACK TO SAVEPOINT sp;
UPDATE core.empleado SET activo = true WHERE empleado_id = :e_inactivo;
SELECT estado FROM core.usuario WHERE usuario_id = :u_inactivo;
ROLLBACK;

\echo ''
\echo '=== 16 · Por la puerta del empleado tampoco se toca a quien no toca ======'
\echo '    esperado: ERROR "Solo el propietario toca la cuenta de un administrador"'
\echo '              (Carla admin, Beto desactiva su empleado) y ERROR "La cuenta del'
\echo '              propietario no se suspende" (Marlon se desactiva a si mismo)'
UPDATE core.usuario SET rol_id = :r_admin WHERE usuario_id = :u_carla;
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET activo = false WHERE empleado_id = :e_carla;
ROLLBACK;
UPDATE core.usuario SET rol_id = :r_recep WHERE usuario_id = :u_carla;
SELECT empleado_id AS e_marlon FROM core.usuario WHERE usuario_id = :u_marlon \gset
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_marlon'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET activo = false WHERE empleado_id = :e_marlon;
ROLLBACK;
\echo '    (y como postgres el trigger no hace nada: esperado activo, no suspendido)'
BEGIN;
UPDATE core.empleado SET activo = false WHERE empleado_id = :e_carla;
SELECT estado FROM core.usuario WHERE usuario_id = :u_carla;
ROLLBACK;

\echo ''
\echo '=== 17 · Un empleado no se repite: nombre, identidad, telefono, correo, colegiacion'
\echo '    esperado: las llaves igualan lo escrito distinto (t,t,t,t,t); cinco ERROR'
\echo '              "duplicate key ... uq_empleado_*" (Carla con otra mayuscula y acento,'
\echo '              su identidad con guiones, su telefono con +504, su correo en'
\echo '              mayusculas, la colegiacion de Marlon en minusculas y con espacio);'
\echo '              y con un apellido distinto SI entra'
SELECT core.llave_nombre('Said  Gabriel', 'Hoch Urbina') = core.llave_nombre('said', 'gabriel hoch urbina') AS nombre,
       core.llave_documento('0801-1994-08899') = core.llave_documento('0801199408899')          AS documento,
       core.llave_telefono('+504 9933-4455')   = core.llave_telefono('99334455')                AS telefono,
       core.llave_correo(' Carla.Nunez@LabOchoa.hn ') = core.llave_correo('carla.nunez@labochoa.hn') AS correo,
       core.llave_documento('cmq 2841')        = core.llave_documento('CMQ-2841')               AS colegiacion;
BEGIN;
SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'CARLA', E'N\u00fa\u00f1ez Bonilla');  -- Nunez con acento y enie, en escapes para que el archivo sea ASCII
ROLLBACK TO SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos, documento) VALUES (:emp, 'Otra', 'Persona A', '0801-1994-08899');
ROLLBACK TO SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos, telefono) VALUES (:emp, 'Otra', 'Persona B', '+504 9933-4455');
ROLLBACK TO SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos, correo) VALUES (:emp, 'Otra', 'Persona C', 'CARLA.NUNEZ@labochoa.hn');
ROLLBACK TO SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos, numero_colegiacion) VALUES (:emp, 'Otra', 'Persona D', 'cmq 2841');
ROLLBACK TO SAVEPOINT s17;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'Carla', 'Martinez Bonilla') RETURNING nombres || ' ' || apellidos AS entro;
ROLLBACK TO SAVEPOINT s17;
\echo '    (en OTRA empresa el mismo nombre si puede existir: esperado 1 fila)'
INSERT INTO core.empleado (empresa_id, nombres, apellidos) SELECT empresa_id, 'Carla', 'Nunez Bonilla' FROM core.empresa WHERE empresa_id <> :emp LIMIT 1 RETURNING empresa_id;
ROLLBACK;

\echo ''
\echo '=== 18 · El modulo de roles: crear, editar, desactivar, y el invariante ======'
\echo '    esperado, en orden:'
\echo '      a. Beto (Administrador) crea Coordinador con permisos normales: un id'
\echo '      b. ...con usuario.administrar adentro: ERROR "Solo el propietario ... vuelve administrador"'
\echo '      c. ...con usuario.nombrar_admin: ERROR "no se asignan a otro rol"'
\echo '      d. "recepcion " repetido por llave: ERROR "Ya hay un rol con ese nombre"; sin descripcion: ERROR "Hace falta la descripcion"'
\echo '      e. Beto edita Administrador (fijo): ERROR "lo mantiene el operador"'
\echo '      f. Marlon crea Subgerente (admin) y se lo pone a Beto; Beto lo edita: ERROR "No se edita el rol que tenes puesto"'
\echo '      g. mismos permisos otra vez: sin evento nuevo (eventos_antes = eventos_despues)'
\echo '      h. desactivar Coordinador con Carla adentro: ERROR 55006 "Hay 1 empleado con este rol"'
\echo '      i. Carla vuelve a Recepcion; desactivar: t; crear_usuario con el: ERROR "esta desactivado"'
\echo '      j. reactivar: t. lis_app escribe core.rol a mano: ERROR permission denied'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT core.crear_rol('Coordinador', 'Coordina la sede') AS r_coord \gset
SELECT core.asignar_permisos_a_rol(:r_coord, ARRAY['paciente.ver', 'orden.ver', 'resultado.ver']) AS permisos_coord;
SAVEPOINT s18;
SELECT core.asignar_permisos_a_rol(:r_coord, ARRAY['paciente.ver', 'usuario.administrar']);
ROLLBACK TO SAVEPOINT s18;
SELECT core.asignar_permisos_a_rol(:r_coord, ARRAY['paciente.ver', 'usuario.nombrar_admin']);
ROLLBACK TO SAVEPOINT s18;
SELECT core.crear_rol('recepcion ', 'otra recepcion');
ROLLBACK TO SAVEPOINT s18;
SELECT core.crear_rol('Sin descripcion', '   ');
ROLLBACK TO SAVEPOINT s18;
SELECT core.editar_rol(:r_admin, 'Administrador general', 'El de siempre');
ROLLBACK TO SAVEPOINT s18;
RESET ROLE;
SET LOCAL lis.usuario_id = :'u_marlon';
SET LOCAL ROLE lis_app;
SELECT core.crear_rol('Subgerente', 'Administra, pero a la medida') AS r_sub \gset
SELECT core.asignar_permisos_a_rol(:r_sub, ARRAY['usuario.administrar', 'paciente.ver']) AS permisos_sub;
SELECT core.cambiar_rol(:u_beto, :r_sub, 'prueba 18f') AS beto_a_subgerente;
RESET ROLE;
SET LOCAL lis.usuario_id = :'u_beto';
SET LOCAL ROLE lis_app;
SAVEPOINT s18f;
SELECT core.editar_rol(:r_sub, 'Subgerente 2', 'Administra, pero a la medida');
ROLLBACK TO SAVEPOINT s18f;
SELECT count(*) AS eventos_antes FROM audit.evento WHERE accion = 'rol.permisos_cambiar' AND registro_id = :r_coord \gset
SELECT core.asignar_permisos_a_rol(:r_coord, ARRAY['resultado.ver', 'orden.ver', 'paciente.ver']) AS permisos_coord_otra_vez;
SELECT :eventos_antes AS eventos_antes, count(*) AS eventos_despues FROM audit.evento WHERE accion = 'rol.permisos_cambiar' AND registro_id = :r_coord;
SELECT core.cambiar_rol(:u_carla, :r_coord, 'prueba 18h') AS carla_a_coordinador;
SAVEPOINT s18h;
SELECT core.desactivar_rol(:r_coord, 'ya no hace falta');
ROLLBACK TO SAVEPOINT s18h;
SELECT core.cambiar_rol(:u_carla, :r_recep, 'prueba 18i') AS carla_a_recepcion;
SELECT core.desactivar_rol(:r_coord, 'ya no hace falta') AS desactivado;
SELECT activo FROM core.rol WHERE rol_id = :r_coord;
SAVEPOINT s18i;
INSERT INTO core.empleado (empresa_id, nombres, apellidos) VALUES (:emp, 'Prueba', 'Rol desactivado') RETURNING empleado_id AS e_prueba \gset
SELECT core.crear_usuario(:e_prueba, :r_coord, 'prueba.desactivado');
ROLLBACK TO SAVEPOINT s18i;
SELECT core.reactivar_rol(:r_coord) AS reactivado;
SAVEPOINT s18j;
UPDATE core.rol SET nombre = 'a mano' WHERE rol_id = :r_coord;
ROLLBACK TO SAVEPOINT s18j;
ROLLBACK;

\echo ''
\echo '=== 19 · La ficha sigue a la cuenta: quien no toca la cuenta no toca la ficha ='
\echo '    esperado, en orden:'
\echo '      a. Beto (Administrador) le cambia el telefono a Carla (Recepcion): UPDATE 1'
\echo '      b. Beto le cambia el correo a Marlon (propietario): ERROR row-level security'
\echo '      c. Beto se cambia el telefono a si mismo (administrador): ERROR row-level security'
\echo '      d. Marlon (propietario) se lo cambia a si mismo y a Beto: UPDATE 1 y UPDATE 1'
\echo '      e. Gabriela (Jefe de sede, sin usuario.administrar) le cambia el telefono a Carla: ERROR'
\echo '      f. puede_tocar_ficha, vista desde Beto: Carla t, Marlon f, Beto f'
BEGIN;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET telefono = '9999-0001' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_carla);
SAVEPOINT s19b;
UPDATE core.empleado SET correo = 'otro@correo.hn' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_marlon);
ROLLBACK TO SAVEPOINT s19b;
UPDATE core.empleado SET telefono = '9999-0002' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_beto);
ROLLBACK TO SAVEPOINT s19b;
SELECT core.puede_tocar_ficha((SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_carla))  AS carla,
       core.puede_tocar_ficha((SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_marlon)) AS marlon,
       core.puede_tocar_ficha((SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_beto))   AS beto;
RESET ROLE;
SET LOCAL lis.usuario_id = :'u_marlon';
SET LOCAL ROLE lis_app;
UPDATE core.empleado SET telefono = '9999-0003' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_marlon);
UPDATE core.empleado SET telefono = '9999-0004' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_beto);
RESET ROLE;
SET LOCAL lis.usuario_id = :'u_gabriela';
SET LOCAL ROLE lis_app;
SAVEPOINT s19e;
UPDATE core.empleado SET telefono = '9999-0005' WHERE empleado_id = (SELECT empleado_id FROM core.usuario WHERE usuario_id = :u_carla);
ROLLBACK TO SAVEPOINT s19e;
ROLLBACK;

\echo ''
\echo '=== 20 · core.usuario cerrada por columnas ================================='
\echo '    esperado, en orden:'
\echo '      a. lis_app lee username y estado: 1 fila'
\echo '      b. lis_app lee password_hash: ERROR permission denied for table usuario'
\echo '      c. lis_app escribe intentos_fallidos a mano: ERROR permission denied'
\echo '      d. registrar_acceso para OTRO usuario: ERROR "la sesion no es la del usuario"'
\echo '      e. registrar_acceso propio: intentos 0 y ultimo_acceso_en de hoy'
BEGIN;
UPDATE core.usuario SET intentos_fallidos = 3 WHERE usuario_id = :u_beto;
SET LOCAL lis.empresa_id = :'emp'; SET LOCAL lis.usuario_id = :'u_beto'; SET LOCAL lis.sucursal_id = :'s_cen';
SET LOCAL ROLE lis_app;
SELECT username, estado FROM core.usuario WHERE usuario_id = :u_beto;
SAVEPOINT s20;
SELECT password_hash FROM core.usuario WHERE usuario_id = :u_beto;
ROLLBACK TO SAVEPOINT s20;
UPDATE core.usuario SET intentos_fallidos = 0 WHERE usuario_id = :u_carla;
ROLLBACK TO SAVEPOINT s20;
SELECT core.registrar_acceso(:u_carla);
ROLLBACK TO SAVEPOINT s20;
SELECT core.registrar_acceso(:u_beto);
SELECT intentos_fallidos, ultimo_acceso_en::date = current_date AS hoy FROM core.usuario WHERE usuario_id = :u_beto;
ROLLBACK;

-- Beto vuelve a ser Analista: el archivo deja la base como la encontro.
SELECT rol_id AS r_ana FROM core.rol WHERE empresa_id = :emp AND nombre = 'Analista' \gset
UPDATE core.usuario SET rol_id = :r_ana WHERE usuario_id = :u_beto;
