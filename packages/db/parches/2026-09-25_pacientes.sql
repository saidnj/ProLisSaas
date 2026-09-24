-- =====================================================================
-- ProLisSaas - parche: el modulo de pacientes
--
-- Para una base ya cargada. Va DESPUES de 2026-09-25_cerrar.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-25_pacientes.sql
--
-- Se puede correr dos veces sin romper nada (y a partir de este parche, se
-- salta solo si ya esta: plataforma.migracion). ASCII puro.
--
-- QUE CAMBIA
-- ----------
--   plataforma.migracion       NUEVA: que parches se aplicaron a esta base. Se
--                              anotan los doce anteriores y este.
--   pg_trgm                    la busqueda por parecido ("sair" -> Said).
--   plataforma.sexo            queda con dos valores: femenino, masculino.
--   core.paciente              nombre_completo es una columna normal (se van
--                              nombres y apellidos); fecha_nacimiento obligatoria
--                              + fecha_nacimiento_estimada; sexo obligatorio sin
--                              valor por omision; se va creado_por_usuario_id (la
--                              bitacora dice quien); cerrada para lis_app.
--   uq_paciente_documento      por la llave del documento (sin guiones ni
--                              minusculas), como en empleados.
--   registrar_paciente         nueva firma (lee la sesion; fecha O edad; deja
--                              paciente.crear). editar_paciente NUEVA.
--                              buscar_pacientes NUEVA. posibles_duplicados por
--                              nombre completo.
--
-- Se detiene si hay pacientes con sexo no_especificado, sin fecha de
-- nacimiento, o con documentos repetidos por llave: hay que resolverlos a
-- mano y volver a correrlo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. El registro de parches, y salir si este ya esta
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS plataforma.migracion (
  nombre       text PRIMARY KEY,
  aplicado_en  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE plataforma.migracion IS
  'Que parches de db/parches/ se le aplicaron a esta base y cuando. Lo escribe '
  'cada parche al final; lo lee cada parche al principio para no repetirse.';

SELECT EXISTS (SELECT 1 FROM plataforma.migracion WHERE nombre = '2026-09-25_pacientes') AS ya_aplicado \gset
\if :ya_aplicado
  \echo 'El parche 2026-09-25_pacientes ya esta aplicado en esta base: no hay nada que hacer.'
  \quit
\endif

BEGIN;

-- Los anteriores se anotan por su nombre (este parche solo corre sobre una
-- base que ya los tiene).
INSERT INTO plataforma.migracion (nombre) VALUES
  ('2026-09-21_acceso_sucursal'), ('2026-09-21_activacion'), ('2026-09-22_desbloqueo'),
  ('2026-09-22_propietario'), ('2026-09-22_rls_permisos'), ('2026-09-23_cuenta'),
  ('2026-09-23_cuenta_siempre'), ('2026-09-23_empleado_unico'), ('2026-09-23_permiso_unico'),
  ('2026-09-24_roles'), ('2026-09-24_ficha'), ('2026-09-25_cerrar')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 1. Lo que tiene que estar resuelto a mano antes
-- ---------------------------------------------------------------------
DO $$
DECLARE v_n int; v_lista text;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'core' AND table_name = 'paciente' AND column_name = 'nombres') THEN
    SELECT count(*) INTO v_n FROM core.paciente WHERE sexo::text = 'no_especificado';
    IF v_n > 0 THEN
      RAISE EXCEPTION 'Hay % pacientes con sexo no_especificado: hay que ponerles sexo antes de seguir', v_n;
    END IF;
    SELECT count(*) INTO v_n FROM core.paciente WHERE fecha_nacimiento IS NULL;
    IF v_n > 0 THEN
      RAISE EXCEPTION 'Hay % pacientes sin fecha de nacimiento: hay que ponersela antes de seguir', v_n;
    END IF;
  END IF;
  SELECT string_agg(format('  empresa %s, %s "%s": pacientes %s', empresa_id, tipo_documento, llave, ids), E'\n')
    INTO v_lista
    FROM (SELECT empresa_id, tipo_documento, core.llave_documento(documento) AS llave,
                 string_agg(paciente_id::text, ', ' ORDER BY paciente_id) AS ids
            FROM core.paciente
           WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL
           GROUP BY 1, 2, 3 HAVING count(*) > 1) d;
  IF v_lista IS NOT NULL THEN
    RAISE EXCEPTION E'Hay pacientes con el mismo documento escrito distinto; hay que fusionarlos o corregirlos antes:\n%', v_lista;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 2. La extension y el tipo
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Un valor de un enum no se puede quitar: se crea el tipo de nuevo y se
-- mueve lo que depende de el (la columna y lab.rango_para; el
-- registrar_paciente viejo se va de todos modos).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
              JOIN pg_namespace n ON n.oid = t.typnamespace
             WHERE n.nspname = 'plataforma' AND t.typname = 'sexo' AND e.enumlabel = 'no_especificado') THEN
    ALTER TABLE core.paciente ALTER COLUMN sexo DROP DEFAULT;
    DROP FUNCTION IF EXISTS core.registrar_paciente(bigint, text, text, plataforma.tipo_documento, text, date, plataforma.sexo, text, text, text, bigint);
    DROP FUNCTION IF EXISTS lab.rango_para(bigint, bigint, plataforma.sexo, integer, date);
    ALTER TYPE plataforma.sexo RENAME TO sexo_viejo;
    CREATE TYPE plataforma.sexo AS ENUM ('femenino', 'masculino');
    ALTER TABLE core.paciente ALTER COLUMN sexo TYPE plataforma.sexo USING sexo::text::plataforma.sexo;
    DROP TYPE plataforma.sexo_viejo;
  END IF;
END $$;

COMMENT ON TYPE plataforma.sexo IS
  'Sexo biologico. No es identidad de genero: determina el rango de referencia '
  'que se aplica a un resultado de laboratorio.';

-- ---------------------------------------------------------------------
-- 3. La tabla
-- ---------------------------------------------------------------------
ALTER TABLE core.paciente ALTER COLUMN nombre_completo DROP EXPRESSION IF EXISTS;
ALTER TABLE core.paciente DROP COLUMN IF EXISTS nombres;
ALTER TABLE core.paciente DROP COLUMN IF EXISTS apellidos;
ALTER TABLE core.paciente DROP COLUMN IF EXISTS creado_por_usuario_id;
ALTER TABLE core.paciente ADD COLUMN IF NOT EXISTS fecha_nacimiento_estimada boolean NOT NULL DEFAULT false;
ALTER TABLE core.paciente ALTER COLUMN fecha_nacimiento SET NOT NULL;
ALTER TABLE core.paciente ALTER COLUMN sexo DROP DEFAULT;
ALTER TABLE core.paciente ALTER COLUMN nombre_completo SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_paciente_nombre' AND conrelid = 'core.paciente'::regclass) THEN
    ALTER TABLE core.paciente ADD CONSTRAINT ck_paciente_nombre CHECK (length(btrim(nombre_completo)) BETWEEN 2 AND 120);
  END IF;
END $$;

COMMENT ON COLUMN core.paciente.fecha_nacimiento_estimada IS
  'true cuando la fecha salio de una edad ("25 anios", "6 meses") y no de un '
  'documento. Una fecha confirmada no vuelve a ser estimada (editar_paciente).';

-- ---------------------------------------------------------------------
-- 4. Los indices
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS core.ix_paciente_nombre;
DROP INDEX IF EXISTS core.uq_paciente_documento;

CREATE UNIQUE INDEX IF NOT EXISTS uq_paciente_documento
  ON core.paciente (empresa_id, tipo_documento, core.llave_documento(documento))
  WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_paciente_nombre_trgm
  ON core.paciente USING gin (core.llave_texto(nombre_completo) public.gin_trgm_ops)
  WHERE fusionado_en_paciente_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_paciente_documento
  ON core.paciente (empresa_id, core.llave_documento(documento) text_pattern_ops)
  WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL;

CREATE INDEX IF NOT EXISTS ix_paciente_reciente
  ON core.paciente (empresa_id, creado_en DESC)
  WHERE fusionado_en_paciente_id IS NULL;

-- ---------------------------------------------------------------------
-- 5. Las funciones (mismo texto que en esquema/04_funciones.sql)
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.registrar_paciente(bigint, text, text, plataforma.tipo_documento, text, date, plataforma.sexo, text, text, text, bigint);
DROP FUNCTION IF EXISTS core.posibles_duplicados(bigint, text, text, date);

CREATE OR REPLACE FUNCTION core.fecha_nacimiento_de(
  p_fecha date, p_anios int, p_meses int
)
RETURNS TABLE (fecha date, estimada boolean)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_con_edad boolean := p_anios IS NOT NULL OR p_meses IS NOT NULL;
BEGIN
  IF p_fecha IS NOT NULL AND v_con_edad THEN
    RAISE EXCEPTION 'Va la fecha de nacimiento o la edad, no las dos' USING ERRCODE = '22023';
  END IF;
  IF p_fecha IS NULL AND NOT v_con_edad THEN
    RAISE EXCEPTION 'Hace falta la fecha de nacimiento, o la edad si no se sabe la fecha' USING ERRCODE = '22023';
  END IF;

  IF p_fecha IS NOT NULL THEN
    IF p_fecha > current_date THEN
      RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura' USING ERRCODE = '22023';
    END IF;
    IF p_fecha < DATE '1900-01-01' THEN
      RAISE EXCEPTION 'La fecha de nacimiento no es valida' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY SELECT p_fecha, false;
    RETURN;
  END IF;

  IF coalesce(p_anios, 0) < 0 OR coalesce(p_anios, 0) > 130
     OR coalesce(p_meses, 0) < 0 OR coalesce(p_meses, 0) > 11 THEN
    RAISE EXCEPTION 'La edad lleva de 0 a 130 anios y de 0 a 11 meses' USING ERRCODE = '22023';
  END IF;
  RETURN QUERY SELECT
    (current_date - make_interval(years => coalesce(p_anios, 0), months => coalesce(p_meses, 0)))::date,
    true;
END
$fn$;

CREATE OR REPLACE FUNCTION core.validar_paciente(
  p_nombre text, p_tipo plataforma.tipo_documento, p_documento text, p_sexo plataforma.sexo
)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  IF length(coalesce(p_nombre, '')) < 2 OR length(p_nombre) > 120 THEN
    RAISE EXCEPTION 'El nombre lleva de 2 a 120 caracteres' USING ERRCODE = '22023';
  END IF;
  IF p_sexo IS NULL THEN
    RAISE EXCEPTION 'Hace falta el sexo' USING ERRCODE = '22023';
  END IF;
  IF p_tipo <> 'ninguno' AND p_documento IS NULL THEN
    RAISE EXCEPTION 'Con tipo de documento hace falta el numero' USING ERRCODE = '22023';
  END IF;
  IF p_documento IS NOT NULL AND length(p_documento) > 40 THEN
    RAISE EXCEPTION 'El documento lleva hasta 40 caracteres' USING ERRCODE = '22023';
  END IF;
END
$fn$;

CREATE OR REPLACE FUNCTION core.registrar_paciente(
  p_nombre_completo  text,
  p_tipo_documento   plataforma.tipo_documento,
  p_documento        text,
  p_fecha_nacimiento date,
  p_edad_anios       int,
  p_edad_meses       int,
  p_sexo             plataforma.sexo,
  p_telefono         text DEFAULT NULL,
  p_correo           text DEFAULT NULL,
  p_direccion        text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa    bigint := core.empresa_actual();
  v_yo         bigint := core.usuario_actual();
  v_nombre     text   := btrim(regexp_replace(coalesce(p_nombre_completo, ''), '\s+', ' ', 'g'));
  v_tipo       plataforma.tipo_documento := coalesce(p_tipo_documento, 'ninguno');
  v_documento  text   := nullif(btrim(coalesce(p_documento, '')), '');
  v_fecha      date;
  v_estimada   boolean;
  v_expediente text;
  v_existente  text;
  v_nuevo      bigint;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;
  IF NOT core.usuario_puede('paciente.crear') THEN
    RAISE EXCEPTION 'No tiene permiso para registrar pacientes' USING ERRCODE = '42501';
  END IF;

  SELECT f.fecha, f.estimada INTO v_fecha, v_estimada
    FROM core.fecha_nacimiento_de(p_fecha_nacimiento, p_edad_anios, p_edad_meses) f;
  PERFORM core.validar_paciente(v_nombre, v_tipo, v_documento, p_sexo);

  -- El documento repetido: se dice a que expediente pertenece, porque lo que
  -- recepcion quiere es abrir ese y no crear otro. Solo dentro de la empresa.
  IF v_tipo <> 'ninguno' THEN
    SELECT pa.expediente INTO v_existente
      FROM core.paciente pa
     WHERE pa.empresa_id = v_empresa
       AND pa.tipo_documento = v_tipo
       AND core.llave_documento(pa.documento) = core.llave_documento(v_documento)
       AND pa.fusionado_en_paciente_id IS NULL;
    IF FOUND THEN
      RAISE EXCEPTION 'Ese documento ya esta registrado en el expediente %', v_existente
        USING ERRCODE = '23505';
    END IF;
  ELSE
    v_documento := NULL;
  END IF;

  v_expediente := core.siguiente_correlativo(v_empresa, NULL, 'expediente');

  INSERT INTO core.paciente (
    empresa_id, expediente, nombre_completo, tipo_documento, documento,
    fecha_nacimiento, fecha_nacimiento_estimada, sexo, telefono, correo, direccion
  ) VALUES (
    v_empresa, v_expediente, v_nombre, v_tipo, v_documento,
    v_fecha, v_estimada, p_sexo,
    nullif(btrim(coalesce(p_telefono, '')), ''),
    nullif(lower(btrim(coalesce(p_correo, ''))), ''),
    nullif(btrim(coalesce(p_direccion, '')), '')
  )
  RETURNING paciente_id INTO v_nuevo;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_despues)
  VALUES (v_empresa, v_yo, 'paciente.crear', 'core', 'paciente', v_nuevo,
          jsonb_build_object('expediente', v_expediente, 'nombre_completo', v_nombre,
                             'tipo_documento', v_tipo, 'documento', v_documento,
                             'fecha_nacimiento', v_fecha, 'fecha_nacimiento_estimada', v_estimada,
                             'sexo', p_sexo));

  RETURN v_nuevo;
END
$fn$;

COMMENT ON FUNCTION core.registrar_paciente IS
  'El unico camino para crear un paciente. Exige paciente.crear; el expediente lo '
  'genera el sistema; con edad en vez de fecha, la calcula y la marca estimada. '
  'Documento repetido en la empresa: 23505 con el expediente. Deja paciente.crear.';

CREATE OR REPLACE FUNCTION core.editar_paciente(
  p_paciente_id      bigint,
  p_nombre_completo  text,
  p_tipo_documento   plataforma.tipo_documento,
  p_documento        text,
  p_fecha_nacimiento date,
  p_edad_anios       int,
  p_edad_meses       int,
  p_sexo             plataforma.sexo,
  p_telefono         text DEFAULT NULL,
  p_correo           text DEFAULT NULL,
  p_direccion        text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa    bigint := core.empresa_actual();
  v_yo         bigint := core.usuario_actual();
  v_actual     core.paciente%ROWTYPE;
  v_nombre     text   := btrim(regexp_replace(coalesce(p_nombre_completo, ''), '\s+', ' ', 'g'));
  v_tipo       plataforma.tipo_documento := coalesce(p_tipo_documento, 'ninguno');
  v_documento  text   := nullif(btrim(coalesce(p_documento, '')), '');
  v_telefono   text   := nullif(btrim(coalesce(p_telefono, '')), '');
  v_correo     text   := nullif(lower(btrim(coalesce(p_correo, ''))), '');
  v_direccion  text   := nullif(btrim(coalesce(p_direccion, '')), '');
  v_fecha      date;
  v_estimada   boolean;
  v_existente  text;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;
  IF NOT core.usuario_puede('paciente.editar') THEN
    RAISE EXCEPTION 'No tiene permiso para editar pacientes' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_actual FROM core.paciente
   WHERE paciente_id = p_paciente_id AND empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese paciente no existe en esta empresa' USING ERRCODE = '42501';
  END IF;
  IF v_actual.fusionado_en_paciente_id IS NOT NULL THEN
    RAISE EXCEPTION 'Este expediente se fusiono en otro: se edita el que quedo' USING ERRCODE = '22023';
  END IF;

  IF NOT v_actual.fecha_nacimiento_estimada
     AND (p_edad_anios IS NOT NULL OR p_edad_meses IS NOT NULL) THEN
    RAISE EXCEPTION 'La fecha de nacimiento ya esta confirmada: se corrige la fecha, no se estima'
      USING ERRCODE = '22023';
  END IF;

  -- La misma fecha estimada que ya tenia, sin edad, no afirma nada: sigue
  -- estimada. Es lo que manda la pantalla cuando se edita otra cosa (el
  -- telefono) y la fecha no se toco; si se volviera a pasar por
  -- fecha_nacimiento_de quedaria "confirmada" sin que nadie lo dijera.
  -- Confirmar es poner la fecha real, que es otra.
  IF v_actual.fecha_nacimiento_estimada
     AND p_fecha_nacimiento = v_actual.fecha_nacimiento
     AND p_edad_anios IS NULL AND p_edad_meses IS NULL THEN
    v_fecha    := v_actual.fecha_nacimiento;
    v_estimada := true;
  ELSE
    SELECT f.fecha, f.estimada INTO v_fecha, v_estimada
      FROM core.fecha_nacimiento_de(p_fecha_nacimiento, p_edad_anios, p_edad_meses) f;
  END IF;
  PERFORM core.validar_paciente(v_nombre, v_tipo, v_documento, p_sexo);
  IF v_tipo = 'ninguno' THEN v_documento := NULL; END IF;

  IF v_documento IS NOT NULL THEN
    SELECT pa.expediente INTO v_existente
      FROM core.paciente pa
     WHERE pa.empresa_id = v_empresa AND pa.paciente_id <> p_paciente_id
       AND pa.tipo_documento = v_tipo
       AND core.llave_documento(pa.documento) = core.llave_documento(v_documento)
       AND pa.fusionado_en_paciente_id IS NULL;
    IF FOUND THEN
      RAISE EXCEPTION 'Ese documento ya esta registrado en el expediente %', v_existente
        USING ERRCODE = '23505';
    END IF;
  END IF;

  -- Igual que estaba: no se escribe ni hay evento. Una fecha estimada que
  -- se vuelve a estimar con la misma edad da la misma fecha si es el mismo
  -- dia; si cambio, es un cambio.
  IF v_actual.nombre_completo = v_nombre
     AND v_actual.tipo_documento = v_tipo
     AND v_actual.documento IS NOT DISTINCT FROM v_documento
     AND v_actual.fecha_nacimiento = v_fecha
     AND v_actual.fecha_nacimiento_estimada = v_estimada
     AND v_actual.sexo = p_sexo
     AND v_actual.telefono IS NOT DISTINCT FROM v_telefono
     AND v_actual.correo IS NOT DISTINCT FROM v_correo
     AND v_actual.direccion IS NOT DISTINCT FROM v_direccion THEN
    RETURN false;
  END IF;

  UPDATE core.paciente
     SET nombre_completo = v_nombre, tipo_documento = v_tipo, documento = v_documento,
         fecha_nacimiento = v_fecha, fecha_nacimiento_estimada = v_estimada, sexo = p_sexo,
         telefono = v_telefono, correo = v_correo, direccion = v_direccion
   WHERE paciente_id = p_paciente_id;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_antes, datos_despues)
  VALUES (v_empresa, v_yo, 'paciente.editar', 'core', 'paciente', p_paciente_id,
          jsonb_build_object('nombre_completo', v_actual.nombre_completo, 'tipo_documento', v_actual.tipo_documento,
                             'documento', v_actual.documento, 'fecha_nacimiento', v_actual.fecha_nacimiento,
                             'fecha_nacimiento_estimada', v_actual.fecha_nacimiento_estimada, 'sexo', v_actual.sexo,
                             'telefono', v_actual.telefono, 'correo', v_actual.correo, 'direccion', v_actual.direccion),
          jsonb_build_object('nombre_completo', v_nombre, 'tipo_documento', v_tipo,
                             'documento', v_documento, 'fecha_nacimiento', v_fecha,
                             'fecha_nacimiento_estimada', v_estimada, 'sexo', p_sexo,
                             'telefono', v_telefono, 'correo', v_correo, 'direccion', v_direccion));
  RETURN true;
END
$fn$;

COMMENT ON FUNCTION core.editar_paciente IS
  'La ficha entera; lo que vino igual no se escribe. Exige paciente.editar. Un '
  'fusionado no se edita. Una fecha confirmada no vuelve a ser estimada; la misma '
  'fecha estimada, sin edad, sigue estimada. '
  'Devuelve false si no cambio nada. Deja paciente.editar con antes y despues.';

CREATE OR REPLACE FUNCTION core.buscar_pacientes(p_texto text, p_limite int DEFAULT 50)
RETURNS TABLE (
  paciente_id bigint, expediente text, nombre_completo text,
  tipo_documento plataforma.tipo_documento, documento text,
  fecha_nacimiento date, fecha_nacimiento_estimada boolean, sexo plataforma.sexo,
  telefono text, creado_en timestamptz, escalon int
)
LANGUAGE sql
STABLE
SET pg_trgm.word_similarity_threshold = 0.4
AS $$
  WITH q AS (
    SELECT core.llave_texto(p_texto)      AS llave,
           core.llave_documento(p_texto)  AS doc,
           upper(btrim(coalesce(p_texto, ''))) AS crudo
  )
  SELECT p.paciente_id, p.expediente, p.nombre_completo, p.tipo_documento, p.documento,
         p.fecha_nacimiento, p.fecha_nacimiento_estimada, p.sexo, p.telefono, p.creado_en,
         CASE
           WHEN q.llave IS NULL THEN 0
           WHEN core.llave_texto(p.nombre_completo) = q.llave
             OR upper(p.expediente) = q.crudo
             OR (q.doc IS NOT NULL AND core.llave_documento(p.documento) = q.doc) THEN 1
           WHEN core.llave_texto(p.nombre_completo) LIKE q.llave || '%'
             OR core.llave_texto(p.nombre_completo) LIKE '% ' || q.llave || '%'
             OR upper(p.expediente) LIKE q.crudo || '%'
             OR (q.doc IS NOT NULL AND core.llave_documento(p.documento) LIKE q.doc || '%') THEN 2
           ELSE 3
         END AS escalon
    FROM core.paciente p, q
   WHERE p.fusionado_en_paciente_id IS NULL
     AND (q.llave IS NULL
          OR core.llave_texto(p.nombre_completo) LIKE q.llave || '%'
          OR core.llave_texto(p.nombre_completo) LIKE '% ' || q.llave || '%'
          OR q.llave <% core.llave_texto(p.nombre_completo)
          OR upper(p.expediente) LIKE q.crudo || '%'
          OR (q.doc IS NOT NULL AND core.llave_documento(p.documento) LIKE q.doc || '%'))
   ORDER BY
     CASE WHEN q.llave IS NULL THEN 0 ELSE 1 END,
     CASE WHEN q.llave IS NULL THEN NULL ELSE
       CASE
         WHEN core.llave_texto(p.nombre_completo) = q.llave
           OR upper(p.expediente) = q.crudo
           OR (q.doc IS NOT NULL AND core.llave_documento(p.documento) = q.doc) THEN 1
         WHEN core.llave_texto(p.nombre_completo) LIKE q.llave || '%'
           OR core.llave_texto(p.nombre_completo) LIKE '% ' || q.llave || '%'
           OR upper(p.expediente) LIKE q.crudo || '%'
           OR (q.doc IS NOT NULL AND core.llave_documento(p.documento) LIKE q.doc || '%') THEN 2
         ELSE 3
       END END,
     CASE WHEN q.llave IS NULL THEN NULL ELSE public.word_similarity(q.llave, core.llave_texto(p.nombre_completo)) END DESC,
     CASE WHEN q.llave IS NULL THEN p.creado_en END DESC,
     p.nombre_completo
   LIMIT greatest(1, least(coalesce(p_limite, 50), 200))
$$;

COMMENT ON FUNCTION core.buscar_pacientes IS
  'La lista de pacientes: sin texto los ultimos registrados; con texto, exacto, '
  'prefijo y parecido (trigramas), en ese orden. Hasta 200 filas. RLS recorta.';

CREATE OR REPLACE FUNCTION core.posibles_duplicados(
  p_nombre_completo  text,
  p_fecha_nacimiento date
)
RETURNS TABLE (
  paciente_id bigint,
  expediente  text,
  nombre_completo text,
  fecha_nacimiento date,
  documento   text,
  coincidencia text
)
LANGUAGE sql
STABLE
AS $$
  SELECT p.paciente_id, p.expediente, p.nombre_completo, p.fecha_nacimiento, p.documento,
         CASE
           WHEN p.fecha_nacimiento = p_fecha_nacimiento THEN 'nombre y fecha exacta'
           ELSE 'nombre y ano de nacimiento'
         END
  FROM core.paciente p
  WHERE p.fusionado_en_paciente_id IS NULL
    AND core.llave_texto(p.nombre_completo) = core.llave_texto(p_nombre_completo)
    AND (
      p.fecha_nacimiento = p_fecha_nacimiento
      OR extract(year from p.fecha_nacimiento) = extract(year from p_fecha_nacimiento)
    )
  ORDER BY (p.fecha_nacimiento = p_fecha_nacimiento) DESC, p.creado_en DESC
$$;

COMMENT ON FUNCTION core.posibles_duplicados IS
  'Se llama ANTES de crear un paciente, y busca solo dentro de la MISMA empresa: '
  'nunca muestra pacientes de otra. Es la defensa contra el duplicado que se crea '
  'porque el paciente ya venia registrado y nadie lo busco.';

CREATE OR REPLACE FUNCTION lab.rango_para(
  p_empresa_id bigint,
  p_analito_id bigint,
  p_sexo       plataforma.sexo,
  p_edad_dias  integer,
  p_fecha      date DEFAULT current_date
)
RETURNS TABLE (
  valor_min   numeric,
  valor_max   numeric,
  critico_min numeric,
  critico_max numeric,
  rango_texto text
)
LANGUAGE sql
STABLE
AS $$
  SELECT r.valor_min, r.valor_max, r.critico_min, r.critico_max, r.texto_libre
  FROM lab.rango_referencia r
  WHERE r.empresa_id = p_empresa_id
    AND r.analito_id = p_analito_id
    AND coalesce(p_edad_dias, 0) BETWEEN r.edad_min_dias AND r.edad_max_dias
    AND (r.sexo = 'ambos' OR r.sexo::text = p_sexo::text)
    AND r.vigente_desde <= p_fecha
    AND (r.vigente_hasta IS NULL OR r.vigente_hasta >= p_fecha)
  ORDER BY
    (r.sexo <> 'ambos') DESC,                  -- el rango por sexo gana al general
    (r.edad_max_dias - r.edad_min_dias) ASC,   -- el tramo de edad mas estrecho gana
    r.vigente_desde DESC
  LIMIT 1
$$;

COMMENT ON FUNCTION lab.rango_para IS
  'Resuelve el rango del LABORATORIO. Sin edad conocida se asume adulto general, '
  'y esa suposicion queda copiada en el resultado para que se pueda auditar.';

-- ---------------------------------------------------------------------
-- 6. Privilegios: core.paciente cerrada; las funciones, para lis_app
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE ON core.paciente FROM lis_app;

REVOKE ALL     ON FUNCTION core.registrar_paciente(text, plataforma.tipo_documento, text, date, int, int, plataforma.sexo, text, text, text) FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.editar_paciente(bigint, text, plataforma.tipo_documento, text, date, int, int, plataforma.sexo, text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.registrar_paciente(text, plataforma.tipo_documento, text, date, int, int, plataforma.sexo, text, text, text) TO lis_app;
GRANT  EXECUTE ON FUNCTION core.editar_paciente(bigint, text, plataforma.tipo_documento, text, date, int, int, plataforma.sexo, text, text, text) TO lis_app;
GRANT  EXECUTE ON FUNCTION core.buscar_pacientes(text, int) TO lis_app;
GRANT  EXECUTE ON FUNCTION core.posibles_duplicados(text, date) TO lis_app;

-- ---------------------------------------------------------------------
-- 7. Anotado
-- ---------------------------------------------------------------------
INSERT INTO plataforma.migracion (nombre) VALUES ('2026-09-25_pacientes') ON CONFLICT DO NOTHING;

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'core' AND table_name = 'paciente'
   AND column_name IN ('nombre_completo', 'fecha_nacimiento', 'fecha_nacimiento_estimada', 'sexo')
 ORDER BY ordinal_position;
SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'sexo' ORDER BY enumsortorder;
SELECT nombre, aplicado_en::date FROM plataforma.migracion ORDER BY nombre;
