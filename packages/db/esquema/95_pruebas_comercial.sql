-- =====================================================================
-- ProLisSaas · 95 · Pruebas de la frontera comercial
--
-- La pregunta: "¿de verdad el laboratorio no puede tocar lo que decide su
-- dueno, y de verdad lo que decide el dueno llega al sistema?"
-- =====================================================================

\set ON_ERROR_STOP off

SELECT core.crear_empresa('Laboratorio Frontera','0801-5555','Central','LFR') AS emp \gset


\echo ''
\echo '=== 1 · lis_app no puede ni nombrar el esquema comercial =========='
\echo '    esperado: ERROR permission denied for schema comercial'
-- Desde que las politicas llaman a core.sesion_vigente(), el contexto necesita
-- las DOS variables. Poner solo la empresa era un atajo que el sistema real
-- nunca usa: conSesion() siempre pone las dos. Se saca el usuario ANTES de
-- SET ROLE, como postgres, porque despues RLS ya no dejaria leerlo.
SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'emp' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'emp';
SELECT count(*) FROM comercial.motivo;
RESET ROLE;


\echo ''
\echo '=== 2 · el laboratorio ya no se levanta su propia suspension ======'
SELECT comercial.registrar_evento(:emp, 'falta_pago', 'said') AS ev \gset
SELECT estado, nivel_acceso FROM core.empresa WHERE empresa_id = :emp;
\echo '    -> politica sin definir: aplica solo_lectura, no completo'


SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'emp' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'emp';
\echo '    esperado: ERROR permission denied (columna estado)'
UPDATE core.empresa SET estado = 'activa' WHERE empresa_id = :emp;
\echo '    esperado: ERROR permission denied (columna nivel_acceso)'
UPDATE core.empresa SET nivel_acceso = 'completo' WHERE empresa_id = :emp;
\echo '    esperado: ERROR permission denied (columna rtn)'
UPDATE core.empresa SET rtn = '9999-FALSO' WHERE empresa_id = :emp;
RESET ROLE;

SELECT estado, nivel_acceso, rtn FROM core.empresa WHERE empresa_id = :emp;
\echo '    -> sigue suspendida, en solo_lectura y con su RTN'


\echo ''
\echo '=== 3 · lo que el laboratorio SI puede configurar de si mismo ====='

-- crear_empresa() no crea usuarios (H-2) y esta prueba necesita uno, porque
-- las politicas ya comprueban core.sesion_vigente(). Se crea aqui como
-- postgres: lis_app tiene revocado el INSERT sobre core.usuario y la funcion
-- core.crear_usuario() exigiria una sesion que todavia no existe.
INSERT INTO core.empleado (empresa_id, nombres, apellidos, documento, cargo, activo)
VALUES (:emp, 'Admin', 'De Prueba', '0000-95-1', 'Administrador', true);

INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash, estado)
SELECT :emp,
       (SELECT empleado_id FROM core.empleado WHERE documento = '0000-95-1'),
       (SELECT rol_id FROM core.rol WHERE empresa_id = :emp AND nombre = 'Administrador'),
       'admin.prueba95', '$argon2id$marcador', 'activo'
RETURNING usuario_id AS _usr \gset

SET lis.usuario_id = :'_usr';

-- Esta prueba cambio de sentido, y el cambio es el hallazgo.
--
-- La prueba 2 dejo la empresa SUSPENDIDA, y comercial.registrar_evento() le
-- puso nivel_acceso = 'solo_lectura'. Antes eso era una palabra que nadie
-- hacia cumplir: el laboratorio suspendido seguia editandose el nombre
-- comercial tan tranquilo. Ahora las politicas separan SELECT de INSERT y de
-- UPDATE segun el nivel, asi que 'solo_lectura' significa lo que dice.
\echo '    a) suspendida en solo_lectura: NO puede ni cambiarse el nombre'
\echo '       esperado: ERROR 42501 -- solo lectura'
SET ROLE lis_app; SET lis.empresa_id = :'emp';
UPDATE core.empresa SET nombre_comercial = 'Lab Frontera' WHERE empresa_id = :emp;
RESET ROLE;

\echo '    b) y con el acceso completo, si puede'
UPDATE core.empresa SET nivel_acceso = 'completo' WHERE empresa_id = :emp;
SET ROLE lis_app; SET lis.empresa_id = :'emp';
UPDATE core.empresa SET nombre_comercial = 'Lab Frontera' WHERE empresa_id = :emp;
RESET ROLE;
SELECT nombre_comercial FROM core.empresa WHERE empresa_id = :emp;


\echo ''
\echo '=== 4 · la decision del dueno llega al sistema ===================='
SELECT comercial.registrar_evento(:emp, 'pago_regularizado', 'said') AS ev2 \gset
SELECT estado, nivel_acceso FROM core.empresa WHERE empresa_id = :emp;


\echo ''
\echo '=== 5 · la politica se COPIA, no se referencia ===================='
\echo '    riesgo_seguridad tiene politica definida: bloqueado, plazo 0'
SELECT comercial.registrar_evento(:emp, 'riesgo_seguridad', 'said',
                                  CURRENT_DATE, 'Cuenta comprometida') AS ev3 \gset
SELECT nivel_aplicado, dias_plazo_aplicado, fecha_vencimiento, politica_estaba_definida
  FROM comercial.relacion_evento WHERE evento_id = :ev3;

\echo '    ahora cambio la politica del motivo...'
UPDATE comercial.motivo SET nivel_inmediato = 'solo_lectura', dias_plazo = 30
 WHERE motivo_id = 'riesgo_seguridad';

SELECT nivel_aplicado, dias_plazo_aplicado FROM comercial.relacion_evento WHERE evento_id = :ev3;
\echo '    -> la fila de ayer no cambio. Eso es E-14 del lado comercial.'
UPDATE comercial.motivo SET nivel_inmediato = 'bloqueado', dias_plazo = 0
 WHERE motivo_id = 'riesgo_seguridad';


\echo ''
\echo '=== 6 · el historial es una linea de tiempo, no pares de estado ==='
SELECT tipo_evento, motivo_id, fecha, nivel_aplicado, registrado_por
  FROM comercial.relacion_evento
 WHERE empresa_id = :emp ORDER BY evento_id;


\echo ''
\echo '=== 7 · un motivo que exige nota no pasa sin ella ================='
\echo '    esperado: ERROR sobre la nota'
SELECT comercial.registrar_evento(:emp, 'incumplimiento', 'said');


\echo ''
\echo '=== 8 · la tarea diaria de cierre ================================='
SELECT comercial.registrar_evento(:emp, 'falta_pago_prolongada', 'said',
                                  CURRENT_DATE - 40, 'Cuatro meses sin pagar') AS ev4 \gset
UPDATE comercial.motivo SET dias_plazo = 30, politica_definida = true
 WHERE motivo_id = 'falta_pago_prolongada';
SELECT comercial.registrar_evento(:emp, 'falta_pago_prolongada', 'said',
                                  CURRENT_DATE - 40, 'Con politica ya definida') AS ev5 \gset
SELECT estado, nivel_acceso, fecha_cierre FROM core.empresa WHERE empresa_id = :emp;
\echo '    -> la fecha de cierre ya vencio; la tarea diaria la cierra:'
SELECT * FROM comercial.cerrar_vencidas();
SELECT estado, nivel_acceso, fecha_cierre FROM core.empresa WHERE empresa_id = :emp;


\echo ''
\echo '=== 9 · lo que solo el operador puede llamar, nadie mas lo alcanza ='
SELECT has_function_privilege('public', 'core.crear_empresa(text,text,text,text)', 'EXECUTE') AS crear_empresa,
       has_function_privilege('public', 'plataforma.crear_enlace(bigint,bigint,text,text)', 'EXECUTE') AS crear_enlace,
       has_function_privilege('public', 'core.entregar(bigint,bigint,core.tipo_mensaje,jsonb,bigint,uuid)', 'EXECUTE') AS entregar;
\echo '    esperado: f, f y f · en PostgreSQL una funcion nace con EXECUTE'
\echo '    para PUBLIC, asi que cada una lleva su REVOKE explicito'


\echo ''
\echo '=== 10 · ninguna tabla de core o lab apunta a comercial ==========='
\echo '    esperado: cero filas · es la regla E-18'
SELECT c.conrelid::regclass::text AS tabla, c.conname
FROM pg_constraint c
JOIN pg_class f ON f.oid = c.confrelid
JOIN pg_namespace n ON n.oid = f.relnamespace
WHERE c.contype = 'f' AND n.nspname = 'comercial'
  AND c.connamespace::regnamespace::text IN ('core','lab','integra','audit','plataforma');


-- ---------------------------------------------------------------------
-- El cliente · quien contrato el servicio
-- ---------------------------------------------------------------------

SELECT core.crear_empresa('Laboratorio Norte','0801-6001','Central','LNO') AS e1 \gset
SELECT core.crear_empresa('Laboratorio Sur',  '0801-6002','Central','LSU') AS e2 \gset

INSERT INTO comercial.cliente (nombre, tipo, rtn)
VALUES ('Grupo Diagnostico S. de R.L.', 'juridica', '0801-9999-000001')
RETURNING cliente_id AS cli \gset

INSERT INTO comercial.cliente (nombre, tipo, rtn)
VALUES ('Dr. Otro Dueno', 'natural', '0801-9999-000002')
RETURNING cliente_id AS cli2 \gset


\echo ''
\echo '=== 11 · lis_app no puede ni nombrar las tablas del cliente ======='
\echo '    esperado: ERROR permission denied for schema comercial'

SELECT coalesce(min(usuario_id)::text,'') AS _usr FROM core.usuario WHERE empresa_id = :'e1' \gset
SET lis.usuario_id = :'_usr';
SET ROLE lis_app; SET lis.empresa_id = :'e1';
SELECT count(*) FROM comercial.cliente;
RESET ROLE;


\echo ''
\echo '=== 12 · una empresa tiene UN dueno a la vez ======================'
INSERT INTO comercial.cliente_empresa (cliente_id, empresa_id) VALUES (:cli, :e1);
INSERT INTO comercial.cliente_empresa (cliente_id, empresa_id) VALUES (:cli, :e2);
\echo '    esperado: ERROR ex_cliente_empresa_sin_solape'
INSERT INTO comercial.cliente_empresa (cliente_id, empresa_id) VALUES (:cli2, :e1);


\echo ''
\echo '=== 12b · ni dos vigencias cerradas que se solapen ================'
\echo '    lo que un indice unico parcial dejaba pasar'
\echo '    esperado: ERROR ex_cliente_empresa_sin_solape'
INSERT INTO comercial.cliente_empresa (cliente_id, empresa_id, desde, hasta)
VALUES (:cli2, :e2, CURRENT_DATE - 30, CURRENT_DATE + 30);


\echo ''
\echo '=== 13 · pero un laboratorio se puede vender ======================'
\echo '    esperado: 2 filas para esa empresa, una sola vigente'
UPDATE comercial.cliente_empresa SET hasta = CURRENT_DATE + 1
 WHERE cliente_id = :cli AND empresa_id = :e1;
INSERT INTO comercial.cliente_empresa (cliente_id, empresa_id, desde)
VALUES (:cli2, :e1, CURRENT_DATE + 1);
SELECT count(*) AS duenos_en_el_historial,
       count(*) FILTER (WHERE hasta IS NULL) AS duenos_vigentes
FROM comercial.cliente_empresa WHERE empresa_id = :e1;

-- se deshace para las pruebas que siguen
DELETE FROM comercial.cliente_empresa WHERE cliente_id = :cli2;
UPDATE comercial.cliente_empresa SET hasta = NULL
 WHERE cliente_id = :cli AND empresa_id = :e1;


\echo ''
\echo '=== 14 · suspender al CLIENTE suspende todas sus empresas ========='
\echo '    esperado: 2 empresas tocadas, las dos en solo_lectura'
SELECT comercial.registrar_evento_cliente(:cli, 'falta_pago', 'said') AS empresas_tocadas;
SELECT empresa_id, estado, nivel_acceso FROM core.empresa
WHERE empresa_id IN (:e1, :e2) ORDER BY empresa_id;


\echo ''
\echo '=== 15 · un cliente sin empresas vigentes revienta ================'
\echo '    esperado: ERROR no tiene ninguna empresa vigente'
SELECT comercial.registrar_evento_cliente(:cli2, 'falta_pago', 'said');


\echo ''
\echo '=== 16 · el contrato cuelga del cliente, no del inquilino ========='
\echo '    esperado: cliente_id, y ninguna FK hacia core.empresa'
SELECT string_agg(column_name, ', ' ORDER BY ordinal_position) AS columnas_de_enlace
FROM information_schema.columns
WHERE table_schema='comercial' AND table_name='contrato'
  AND column_name IN ('cliente_id','empresa_id');
