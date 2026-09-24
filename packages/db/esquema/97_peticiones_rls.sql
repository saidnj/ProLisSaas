-- =====================================================================
-- ProLisSaas - 97 - Cinco peticiones, para ver RLS funcionando
--
-- Corre igual en psql y en el Query Tool de pgAdmin: no usa comandos de
-- psql (\set, \gset) ni ningun id clavado. Los ids salen del username,
-- asi que no importa que en tu base sean distintos a los de otra.
--
--     psql -U postgres -d prolissaas -f 97_peticiones_rls.sql
--
-- Todo va en transacciones que terminan en ROLLBACK: no deja rastro.
--
-- ---------------------------------------------------------------------
-- EL ORDEN DE LAS DOS PRIMERAS LINEAS DE CADA BLOQUE IMPORTA
--
--   1. set_config(...)      <- todavia como postgres. Puede LEER
--                              core.usuario para saber quien es Carla.
--   2. SET LOCAL ROLE lis_app  <- recien aqui bajamos de privilegios.
--
-- Al reves no funciona: ya convertido en lis_app y sin contexto puesto,
-- la consulta a core.usuario devolveria cero filas y no habria de donde
-- sacar el empresa_id. Es el mismo huevo y la gallina del login.
--
-- Las dos cosas son LOCALES a la transaccion y mueren en el ROLLBACK.
-- =====================================================================


\echo ''
\echo '################ 0 - QUIEN ES QUIEN ################'
-- Como postgres, sin contexto: el superusuario se salta RLS.

SELECT u.username, u.usuario_id, u.empresa_id, r.nombre AS rol,
       e.nombre_comercial AS empresa
FROM core.usuario u
JOIN core.rol     r ON r.rol_id     = u.rol_id     AND r.empresa_id = u.empresa_id
JOIN core.empresa e ON e.empresa_id = u.empresa_id
WHERE u.username IN ('carla.nunez','marlon.ochoa')
ORDER BY u.username;


-- =====================================================================
-- A - Carla pide lo que SI le toca
--
-- Fijate que el SELECT no lleva WHERE empresa_id. No hace falta: la
-- politica se lo agrega Postgres.
-- =====================================================================
\echo ''
\echo '################ A - CARLA pide lo que SI le toca ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='carla.nunez'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='carla.nunez'),true);
  END $$;
  SET LOCAL ROLE lis_app;

  SELECT current_user AS rol_de_base, current_setting('lis.empresa_id') AS contexto;

  SELECT paciente_id, empresa_id, nombres, apellidos
  FROM core.paciente ORDER BY paciente_id;
ROLLBACK;


-- =====================================================================
-- B - Carla pide una fila de OTRA empresa, por su id exacto
--
-- Primero, como postgres, se busca un paciente que NO sea de su empresa
-- y se guarda el id en una variable de sesion. Despues Carla lo pide por
-- ese id exacto.
--
-- Devuelve CERO FILAS, no un error. RLS no dice "no tenes permiso":
-- hace que la fila no exista. Si diera error se podria averiguar que
-- ids existen sin poder verlos.
-- =====================================================================
\echo ''
\echo '################ B - CARLA pide una fila de OTRA empresa ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('demo.ajeno',
      (SELECT min(paciente_id)::text FROM core.paciente
        WHERE empresa_id <> (SELECT empresa_id FROM core.usuario WHERE username='carla.nunez')),true);
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='carla.nunez'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='carla.nunez'),true);
  END $$;

  SELECT 'va a pedir el paciente_id = '||current_setting('demo.ajeno') AS aviso;

  SET LOCAL ROLE lis_app;
  SELECT paciente_id, empresa_id, nombres, apellidos
  FROM core.paciente WHERE paciente_id = current_setting('demo.ajeno')::bigint;
ROLLBACK;


-- =====================================================================
-- C - El OTRO muro: el permiso
--
-- RLS contesta QUE FILAS. El rol contesta QUE ACCIONES. Son dos cosas
-- distintas y se ven mejor juntas: Carla y Marlon son de la MISMA
-- empresa, asi que RLS les muestra exactamente los mismos pacientes.
-- Lo que pueden hacer con ellos no tiene nada que ver.
-- =====================================================================
\echo ''
\echo '################ C - CARLA (Recepcion) ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='carla.nunez'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='carla.nunez'),true);
  END $$;
  SET LOCAL ROLE lis_app;
  SELECT core.usuario_puede('paciente.crear')      AS crea_paciente,
         core.usuario_puede('resultado.validar')   AS valida_resultado,
         core.usuario_puede('usuario.administrar') AS administra_usuarios;
ROLLBACK;

\echo '################ C - MARLON (Administrador), misma empresa ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='marlon.ochoa'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='marlon.ochoa'),true);
  END $$;
  SET LOCAL ROLE lis_app;
  SELECT core.usuario_puede('paciente.crear')      AS crea_paciente,
         core.usuario_puede('resultado.validar')   AS valida_resultado,
         core.usuario_puede('usuario.administrar') AS administra_usuarios;
ROLLBACK;


-- =====================================================================
-- D - Carla intenta ESCRIBIR en otra empresa
--
-- Aqui si hay error, y es a proposito. USING decide que se lee;
-- WITH CHECK decide como puede quedar la fila. Una lectura prohibida
-- desaparece en silencio; una escritura prohibida grita.
--
-- Tiene que fallar con:
--   ERROR: new row violates row-level security policy for table "paciente"
-- =====================================================================
\echo ''
\echo '################ D - CARLA intenta escribir en otra empresa ################'
BEGIN;
  DO $$ BEGIN
    PERFORM set_config('lis.empresa_id',(SELECT empresa_id::text FROM core.usuario WHERE username='carla.nunez'),true);
    PERFORM set_config('lis.usuario_id',(SELECT usuario_id::text FROM core.usuario WHERE username='carla.nunez'),true);
  END $$;
  SET LOCAL ROLE lis_app;

  INSERT INTO core.paciente (empresa_id, nombres, apellidos)
  VALUES (2, 'Paciente', 'Colado');
ROLLBACK;


-- =====================================================================
-- E - El superusuario
--
-- La misma base, sin SET LOCAL ROLE y sin contexto. postgres es
-- superusuario y NO obedece RLS -- ni con FORCE, ni con politicas, ni
-- con nada. Ve las tres empresas.
--
-- Por eso la aplicacion NUNCA se conecta como postgres: si lo hiciera,
-- RLS estaria encendido y seria decorativo.
-- =====================================================================
\echo ''
\echo '################ E - EL SUPERUSUARIO ################'
SELECT current_user AS rol_de_base,
       coalesce(core.empresa_actual()::text,'(sin contexto)') AS contexto;

SELECT e.nombre_comercial AS empresa, count(p.paciente_id) AS pacientes
FROM core.empresa e
LEFT JOIN core.paciente p ON p.empresa_id = e.empresa_id
GROUP BY 1 ORDER BY 1;


-- =====================================================================
-- LO QUE TIENE QUE HABER SALIDO
--
--   A   los pacientes de Laboratorio Ochoa, sin WHERE empresa_id
--   B   (0 rows)  <- la fila existe, para ella no
--   C   Carla t/f/f   ·   Marlon t/t/t   <- misma empresa, otro rol
--   D   ERROR: new row violates row-level security policy
--   E   las tres empresas
--
-- Si A y E dan lo mismo, la aplicacion se esta conectando como
-- superusuario y RLS no esta protegiendo nada.
-- =====================================================================
