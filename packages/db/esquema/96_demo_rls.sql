-- =====================================================================
-- ProLisSaas - 96 - Como funciona Row Level Security, paso a paso
--
-- Este archivo no es parte del sistema. Es para ENTENDER el mecanismo.
-- Crea un esquema "demo" de juguete, hace seis experimentos, y al final
-- te dice como borrarlo.
--
-- Corrilo entero y lee la salida:
--     psql -U postgres -d prolissaas -f 96_demo_rls.sql
--
-- No toca ninguna tabla real.
-- =====================================================================

DROP SCHEMA IF EXISTS demo CASCADE;
CREATE SCHEMA demo;

-- Una tabla de juguete: notas de tres empresas, todas revueltas.
CREATE TABLE demo.nota (
  nota_id    bigserial PRIMARY KEY,
  empresa_id bigint NOT NULL,
  texto      text   NOT NULL
);

INSERT INTO demo.nota (empresa_id, texto) VALUES
  (1,'Ochoa: pedir reactivos'),
  (1,'Ochoa: llamar al proveedor'),
  (2,'San Jose: cambiar turno'),
  (2,'San Jose: revisar caja'),
  (3,'Bioanalisis: calibrar equipo');

-- El rol con el que se conectaria la API. NOLOGIN y sin privilegios
-- especiales: es importante que NO sea superusuario, porque el
-- superusuario se salta RLS siempre y no veriamos nada de lo de abajo.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='demo_app') THEN
    CREATE ROLE demo_app NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA demo TO demo_app;
GRANT SELECT, INSERT, UPDATE ON demo.nota TO demo_app;
GRANT USAGE, SELECT ON SEQUENCE demo.nota_nota_id_seq TO demo_app;

-- La funcion que lee el contexto de la sesion. Identica en forma a
-- core.empresa_actual() del sistema de verdad.
--
--   current_setting(nombre, true) -> si la variable no existe, NULL
--                                    en vez de reventar
--   nullif(x, '')                 -> si existe pero esta vacia
--                                    (un SET LOCAL que ya expiro), NULL
CREATE FUNCTION demo.empresa_actual() RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('demo.empresa_id', true), '')::bigint
$$;


-- =====================================================================
-- PASO 1 - Sin RLS, demo_app ve TODO
--
-- Asi esta cualquier base normal. La unica cosa que separa una empresa
-- de otra es que el programador se acuerde de poner WHERE empresa_id.
-- Una consulta olvidada y se ve todo.
-- =====================================================================
\echo ''
\echo '== PASO 1 - SIN RLS: demo_app ve las cinco notas =='
BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT nota_id, empresa_id, texto FROM demo.nota ORDER BY nota_id;
COMMIT;


-- =====================================================================
-- PASO 2 - Se enciende RLS, pero todavia no hay politica
--
-- ENABLE dice "esta tabla tiene filtro de filas".
-- FORCE  dice "el dueno de la tabla TAMBIEN lo obedece" -- sin FORCE, el
--        dueno se salta sus propias politicas, que es justo el rol con
--        el que corren las migraciones.
--
-- Sin ninguna politica escrita, la respuesta por omision es NO. Cero
-- filas. RLS es "prohibido salvo que una politica lo permita".
-- =====================================================================
\echo ''
\echo '== PASO 2 - RLS encendido y SIN politica: cero filas =='
ALTER TABLE demo.nota ENABLE ROW LEVEL SECURITY;
ALTER TABLE demo.nota FORCE  ROW LEVEL SECURITY;

BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT count(*) AS filas_visibles FROM demo.nota;
COMMIT;


-- =====================================================================
-- PASO 3 - La politica, y el contexto puesto en 1
--
-- USING      -> que filas se PUEDEN LEER (SELECT, UPDATE, DELETE)
-- WITH CHECK -> que filas se PUEDEN ESCRIBIR (INSERT, UPDATE)
--
-- Postgres le pega ese USING a la tabla como si fuera un WHERE invisible,
-- en TODA consulta, la escriba quien la escriba.
-- =====================================================================
\echo ''
\echo '== PASO 3 - con politica y contexto = 1: solo las de Ochoa =='
CREATE POLICY rls_nota ON demo.nota
  USING      (empresa_id = demo.empresa_actual())
  WITH CHECK (empresa_id = demo.empresa_actual());

BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT set_config('demo.empresa_id','1',true);   -- <- el "inicio de sesion"
  SELECT nota_id, empresa_id, texto FROM demo.nota ORDER BY nota_id;
COMMIT;


-- =====================================================================
-- PASO 4 - La MISMA consulta, otro contexto
--
-- Ni una letra distinta en el SELECT. Lo unico que cambio es el
-- set_config. Eso es todo RLS.
-- =====================================================================
\echo ''
\echo '== PASO 4 - misma consulta, contexto = 2: solo las de San Jose =='
BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT set_config('demo.empresa_id','2',true);
  SELECT nota_id, empresa_id, texto FROM demo.nota ORDER BY nota_id;
COMMIT;


-- =====================================================================
-- PASO 5 - Un UPDATE sin WHERE
--
-- "UPDATE demo.nota SET texto = ..." sin ninguna condicion. En una base
-- normal esto arrasa con las cinco filas de las tres empresas.
-- Aqui toca dos.
-- =====================================================================
\echo ''
\echo '== PASO 5 - UPDATE sin WHERE: solo alcanza a las propias =='
BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT set_config('demo.empresa_id','2',true);
  UPDATE demo.nota SET texto = texto || ' [tocado]';
COMMIT;

SELECT empresa_id, texto FROM demo.nota ORDER BY nota_id;


-- =====================================================================
-- PASO 6 - WITH CHECK: intentar colgar una fila de otra empresa
--
-- Estando en la empresa 2, insertar algo con empresa_id = 1.
-- USING no lo impide (USING es para leer). WITH CHECK si.
--
-- Esto tiene que FALLAR:
--   ERROR: new row violates row-level security policy for table "nota"
-- =====================================================================
\echo ''
\echo '== PASO 6 - INSERT de una fila ajena: tiene que fallar =='
BEGIN;
  SET LOCAL ROLE demo_app;
  SELECT set_config('demo.empresa_id','2',true);
  INSERT INTO demo.nota (empresa_id, texto) VALUES (1,'me hago pasar por Ochoa');
COMMIT;


-- =====================================================================
-- Para borrar el juguete cuando termines:
--
--   DROP SCHEMA demo CASCADE;
--   DROP ROLE demo_app;
--
-- Y las tres cosas que hay que llevarse de aqui:
--
--   1. La politica se evalua SIEMPRE, en toda consulta, aunque el
--      programador olvide el WHERE. Por eso el aislamiento deja de
--      depender de que nadie se equivoque.
--
--   2. Sin contexto la respuesta es CERO FILAS, no un error. Es seguro
--      pero silencioso: la pantalla dice "no hay nada" y nadie se entera.
--
--   3. El contexto se pone con set_config(nombre, valor, TRUE). Ese TRUE
--      es "local a la transaccion". Con FALSE se queda pegado a la
--      conexion, y con un pool la siguiente peticion -- que puede ser de
--      otra empresa -- lo hereda.
-- =====================================================================
