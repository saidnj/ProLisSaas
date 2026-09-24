-- =====================================================================
-- ProLisSaas - parche: un empleado no se repite
--
-- Para una base ya cargada. Va DESPUES de 2026-09-23_cuenta_siempre.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-23_empleado_unico.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- QUE CAMBIA
-- ----------
--   core.llave_nombre / llave_documento / llave_telefono / llave_correo
--       funciones puras que dicen cuando dos textos son el mismo dato
--       ("Said  Gabriel" = "said gabriel", "+504 9933-4455" = "9933-4455").
--       unaccent_simple() se recrea igual, ahora como public.unaccent_simple
--       (se mudo de 04 a 01 en el esquema).
--   cinco indices unicos sobre core.empleado, por empresa:
--       nombre (nombres + apellidos), identidad, telefono, correo, colegiacion.
--       Los cuatro ultimos solo cuentan cuando el dato esta puesto.
--
-- SI YA HAY DUPLICADOS en la base, el parche se detiene ANTES de crear los
-- indices y los lista: hay que resolverlos a mano (cual de los dos es la
-- persona) y volver a correrlo. No decide solo.
-- =====================================================================

BEGIN;

-- Quita acentos y dieresis, y deja un solo espacio entre palabras. Sin
-- depender de la extension unaccent. La usan pacientes (posibles
-- duplicados) y las llaves de abajo. Con el esquema puesto, aqui y en
-- quien la llama: desde PostgreSQL 17, CREATE INDEX evalua la expresion
-- con search_path = pg_catalog, y un nombre sin esquema no se encuentra.
CREATE OR REPLACE FUNCTION public.unaccent_simple(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  -- La tabla de acentos va con escapes \uXXXX y no con las letras: el
  -- archivo queda en ASCII puro y carga igual desde una consola Windows
  -- (WIN1252) que desde Linux (UTF8). Es aeiou AEIOU (agudas), aeiou AEIOU
  -- (dieresis), aeiou AEIOU (graves), n N.
  SELECT translate(
    btrim(regexp_replace(coalesce(p_texto,''), '\s+', ' ', 'g')),
    E'\u00e1\u00e9\u00ed\u00f3\u00fa\u00c1\u00c9\u00cd\u00d3\u00da\u00e4\u00eb\u00ef\u00f6\u00fc\u00c4\u00cb\u00cf\u00d6\u00dc\u00e0\u00e8\u00ec\u00f2\u00f9\u00c0\u00c8\u00cc\u00d2\u00d9\u00f1\u00d1',
    'aeiouAEIOUaeiouAEIOUaeiouAEIOUnN'
  )
$$;

-- El nombre entero: nombres y apellidos juntos, en minusculas, sin acentos
-- ni espacios de mas. Es LA SUMA lo que no se repite: "Said Gabriel" +
-- "Hoch Urbina" y "Said" + "Gabriel Hoch Urbina" son la misma persona.
CREATE OR REPLACE FUNCTION core.llave_nombre(p_nombres text, p_apellidos text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(public.unaccent_simple(coalesce(p_nombres,'') || ' ' || coalesce(p_apellidos,'')))
$$;

-- Identidad y colegiacion: solo letras y numeros, en mayusculas. Los
-- guiones y espacios son de quien lo escribe, no del documento:
-- "0801-1994-08899" es "0801199408899". NULL si no queda nada.
CREATE OR REPLACE FUNCTION core.llave_documento(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(regexp_replace(upper(coalesce(p_texto,'')), '[^A-Z0-9]', '', 'g'), '')
$$;

-- Telefono: solo digitos, y sin el 504 de Honduras si lo trae adelante
-- ("+504 9933-4455" y "9933-4455" son el mismo numero). NULL si no queda
-- nada.
CREATE OR REPLACE FUNCTION core.llave_telefono(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(
    CASE WHEN length(d) = 11 AND d LIKE '504%' THEN substr(d, 4) ELSE d END, '')
  FROM (SELECT regexp_replace(coalesce(p_texto,''), '\D', '', 'g') AS d) x
$$;

-- Correo: en minusculas y sin espacios alrededor. NULL si no queda nada.
CREATE OR REPLACE FUNCTION core.llave_correo(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(lower(btrim(coalesce(p_texto,''))), '')
$$;

GRANT EXECUTE ON FUNCTION public.unaccent_simple TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_nombre(text, text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_documento(text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_telefono(text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_correo(text) TO lis_app;

-- ---------------------------------------------------------------------
-- Antes de los indices: que no haya duplicados con los que reventarian
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_lista text;
BEGIN
  SELECT string_agg(format('  %s: %s (empleados %s)', campo, llave, ids), E'\n' ORDER BY campo, llave)
    INTO v_lista
    FROM (
      SELECT 'nombre' AS campo, core.llave_nombre(nombres, apellidos) AS llave,
             string_agg(empleado_id::text, ', ' ORDER BY empleado_id) AS ids
        FROM core.empleado GROUP BY empresa_id, 2 HAVING count(*) > 1
      UNION ALL
      SELECT 'identidad', core.llave_documento(documento), string_agg(empleado_id::text, ', ' ORDER BY empleado_id)
        FROM core.empleado WHERE core.llave_documento(documento) IS NOT NULL
       GROUP BY empresa_id, 2 HAVING count(*) > 1
      UNION ALL
      SELECT 'telefono', core.llave_telefono(telefono), string_agg(empleado_id::text, ', ' ORDER BY empleado_id)
        FROM core.empleado WHERE core.llave_telefono(telefono) IS NOT NULL
       GROUP BY empresa_id, 2 HAVING count(*) > 1
      UNION ALL
      SELECT 'correo', core.llave_correo(correo), string_agg(empleado_id::text, ', ' ORDER BY empleado_id)
        FROM core.empleado WHERE core.llave_correo(correo) IS NOT NULL
       GROUP BY empresa_id, 2 HAVING count(*) > 1
      UNION ALL
      SELECT 'colegiacion', core.llave_documento(numero_colegiacion), string_agg(empleado_id::text, ', ' ORDER BY empleado_id)
        FROM core.empleado WHERE core.llave_documento(numero_colegiacion) IS NOT NULL
       GROUP BY empresa_id, 2 HAVING count(*) > 1
    ) d;

  IF v_lista IS NOT NULL THEN
    RAISE EXCEPTION E'Hay empleados repetidos; hay que resolverlos antes de seguir:\n%', v_lista;
  END IF;
END $$;

-- EMPLEADO: lo que identifica a una persona no se repite dentro de la
-- empresa, escrito como se escriba (las llaves de 01_tipos.sql deciden
-- cuando dos textos son el mismo dato). El nombre es la suma nombres +
-- apellidos; lo demas solo cuenta cuando esta puesto. El API pregunta
-- ANTES de escribir para decir quien lo tiene (empleados.service.ts);
-- estos indices son la garantia cuando dos guardan a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_empleado_nombre
  ON core.empleado (empresa_id, core.llave_nombre(nombres, apellidos));

CREATE UNIQUE INDEX IF NOT EXISTS uq_empleado_documento
  ON core.empleado (empresa_id, core.llave_documento(documento))
  WHERE core.llave_documento(documento) IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_empleado_telefono
  ON core.empleado (empresa_id, core.llave_telefono(telefono))
  WHERE core.llave_telefono(telefono) IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_empleado_correo
  ON core.empleado (empresa_id, core.llave_correo(correo))
  WHERE core.llave_correo(correo) IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_empleado_colegiacion
  ON core.empleado (empresa_id, core.llave_documento(numero_colegiacion))
  WHERE core.llave_documento(numero_colegiacion) IS NOT NULL;

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion: los cinco indices existen
-- ---------------------------------------------------------------------
SELECT indexname FROM pg_indexes
 WHERE schemaname = 'core' AND tablename = 'empleado' AND indexname LIKE 'uq\_empleado\_%'
 ORDER BY 1;
