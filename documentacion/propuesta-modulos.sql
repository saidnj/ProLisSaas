-- =====================================================================
-- PROPUESTA · Modulos, permisos y roles
-- Se aplica sobre la base ya construida, para probarla antes de tocar
-- los archivos 01..17. NO es un archivo del esquema.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 · La licencia pasa a ser del operador
-- ---------------------------------------------------------------------

ALTER TABLE core.modulo_sucursal SET SCHEMA plataforma;

ALTER TABLE plataforma.modulo_sucursal
  ADD COLUMN desactivado_en timestamptz,
  ADD COLUMN asignado_por   text NOT NULL DEFAULT 'operador';

ALTER TABLE plataforma.modulo_sucursal
  ALTER COLUMN asignado_por DROP DEFAULT;

-- Apagar un modulo tiene que dejar constancia de cuando (H-26).
ALTER TABLE plataforma.modulo_sucursal
  ADD CONSTRAINT ck_modulo_sucursal_apagado
  CHECK (activo OR desactivado_en IS NOT NULL);

COMMENT ON TABLE plataforma.modulo_sucursal IS
  'Que modulos contrato cada SEDE. La escribe el operador, igual que '
  'plataforma.enlace: el laboratorio no decide que compro. El laboratorio la '
  'LEE -- RLS la recorta a su empresa -- para pintar el menu y para que '
  'usuario_puede() intersecte.';

COMMENT ON COLUMN plataforma.modulo_sucursal.asignado_por IS
  'Texto y no llave foranea: el operador no es usuario de ninguna empresa (E-19).';

-- Se lee, no se escribe.
REVOKE ALL ON plataforma.modulo_sucursal FROM lis_app;
GRANT SELECT ON plataforma.modulo_sucursal TO lis_app;

-- La politica viajo con la tabla; se rehace sin WITH CHECK porque no hay
-- escritura posible desde el laboratorio.
DROP POLICY IF EXISTS rls_modulo_sucursal ON plataforma.modulo_sucursal;
ALTER TABLE plataforma.modulo_sucursal ENABLE  ROW LEVEL SECURITY;
ALTER TABLE plataforma.modulo_sucursal FORCE   ROW LEVEL SECURITY;
CREATE POLICY rls_modulo_sucursal ON plataforma.modulo_sucursal
  FOR SELECT USING (empresa_id = core.empresa_actual());


-- ---------------------------------------------------------------------
-- 2 · El modulo core se activa como cualquier otro
-- ---------------------------------------------------------------------
-- Sin esto, el dia que usuario_puede() intersecte, los 16 permisos de
-- core se caen y el sistema se cierra solo.

INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, asignado_por)
SELECT s.sucursal_id, 'core', s.empresa_id, 'migracion'
FROM core.sucursal s
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- 3 · La comprobacion de siempre, ahora con la licencia adentro
-- ---------------------------------------------------------------------
-- usuario_puede()     -> intencion del admin + licencia en ALGUNA sede.
--                        Para pintar menus y para lo que no ocurre en una sede.
-- usuario_puede_en()  -> la de verdad: exige que el modulo este encendido
--                        EN ESA SEDE. La usan las operaciones.
--
-- Las dos siguen siendo invoker, no SECURITY DEFINER: asi RLS sigue
-- recortando a la empresa de la sesion y nadie puede preguntar por un
-- usuario ajeno.

CREATE OR REPLACE FUNCTION core.usuario_puede_en(
  p_permiso_id  text,
  p_sucursal_id bigint,
  p_usuario_id  bigint DEFAULT NULL
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core.usuario u
    JOIN core.rol_permiso rp
      ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
    JOIN plataforma.permiso p
      ON p.permiso_id = rp.permiso_id
    JOIN plataforma.modulo_sucursal ms
      ON ms.modulo_id = p.modulo_id
     AND ms.empresa_id = u.empresa_id
     AND ms.sucursal_id = p_sucursal_id
     AND ms.activo
    WHERE u.usuario_id = coalesce(p_usuario_id, core.usuario_actual())
      AND u.estado = 'activo'
      AND rp.permiso_id = p_permiso_id
  )
$$;

CREATE OR REPLACE FUNCTION core.usuario_puede(
  p_permiso_id text,
  p_usuario_id bigint DEFAULT NULL
) RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core.usuario u
    JOIN core.rol_permiso rp
      ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
    JOIN plataforma.permiso p
      ON p.permiso_id = rp.permiso_id
    WHERE u.usuario_id = coalesce(p_usuario_id, core.usuario_actual())
      AND u.estado = 'activo'
      AND rp.permiso_id = p_permiso_id
      AND EXISTS (
        SELECT 1 FROM plataforma.modulo_sucursal ms
        WHERE ms.empresa_id = u.empresa_id
          AND ms.modulo_id  = p.modulo_id
          AND ms.activo
      )
  )
$$;


-- ---------------------------------------------------------------------
-- 4 · El menu del administrador
-- ---------------------------------------------------------------------
-- Lo que la pantalla de "crear rol" tiene derecho a mostrar. Sin sede:
-- la union de lo que la empresa tenga en alguna sucursal, porque el rol
-- es de la empresa.

CREATE OR REPLACE FUNCTION core.permisos_disponibles(p_sucursal_id bigint DEFAULT NULL)
RETURNS TABLE (permiso_id text, modulo_id text, descripcion text)
LANGUAGE sql STABLE
AS $$
  SELECT DISTINCT p.permiso_id, p.modulo_id, p.descripcion
  FROM plataforma.permiso p
  JOIN plataforma.modulo_sucursal ms
    ON ms.modulo_id = p.modulo_id AND ms.activo
  WHERE p_sucursal_id IS NULL OR ms.sucursal_id = p_sucursal_id
  ORDER BY 2, 1
$$;


-- ---------------------------------------------------------------------
-- 5 · La unica puerta para cambiar los permisos de un rol
-- ---------------------------------------------------------------------
-- Reemplaza el conjunto entero: lo que no venga en el arreglo se quita.
-- Tres comprobaciones, en este orden:
--   a. quien llama administra usuarios
--   b. el rol es de su empresa
--   c. cada permiso pertenece a un modulo que la empresa tiene encendido
--
-- Usa core.usuario_puede() y NO core.exigir_permiso(): dentro de un
-- SECURITY DEFINER de postgres, current_user deja de ser lis_app y
-- exigir_permiso se va por su escape sin comprobar nada (H-57).

CREATE OR REPLACE FUNCTION core.asignar_permisos_a_rol(
  p_rol_id     bigint,
  p_permisos   text[],
  p_usuario_id bigint DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_usuario_id bigint := coalesce(p_usuario_id, core.usuario_actual());
  v_empresa_id bigint := core.empresa_actual();
  v_antes      jsonb;
  v_ajenos     text[];
  v_cuantos    integer;
BEGIN
  IF v_empresa_id IS NULL OR v_usuario_id IS NULL THEN
    RAISE EXCEPTION 'Falta el contexto de sesion (lis.empresa_id / lis.usuario_id)';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar', v_usuario_id) THEN
    RAISE EXCEPTION 'Solo quien administra usuarios puede cambiar los permisos de un rol'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM core.rol
                 WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id) THEN
    RAISE EXCEPTION 'Ese rol no existe en esta empresa';
  END IF;

  -- c · los que no pertenecen a un modulo encendido en ninguna sede
  SELECT array_agg(x ORDER BY x) INTO v_ajenos
  FROM unnest(p_permisos) AS x
  WHERE NOT EXISTS (
    SELECT 1
    FROM plataforma.permiso p
    JOIN plataforma.modulo_sucursal ms
      ON ms.modulo_id = p.modulo_id AND ms.activo
     AND ms.empresa_id = v_empresa_id
    WHERE p.permiso_id = x
  );

  IF v_ajenos IS NOT NULL THEN
    RAISE EXCEPTION
      'Estos permisos son de modulos que esta empresa no tiene contratados: %',
      array_to_string(v_ajenos, ', ')
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT coalesce(jsonb_agg(permiso_id ORDER BY permiso_id), '[]'::jsonb)
    INTO v_antes
  FROM core.rol_permiso
  WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id;

  DELETE FROM core.rol_permiso
  WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id
    AND permiso_id <> ALL (p_permisos);

  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT p_rol_id, x, v_empresa_id FROM unnest(p_permisos) AS x
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_cuantos
  FROM core.rol_permiso WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id;

  -- Cambiar lo que puede un rol es el cambio mas delicado del sistema y
  -- hasta hoy no dejaba ningun rastro.
  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa_id, v_usuario_id, 'rol.permisos_cambiar', 'core', 'rol_permiso',
    p_rol_id, jsonb_build_object('permisos', v_antes),
    jsonb_build_object('permisos', to_jsonb(p_permisos))
  );

  RETURN v_cuantos;
END $$;

REVOKE ALL ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) TO lis_app;

-- Y se cierra la puerta de atras.
REVOKE INSERT, UPDATE ON core.rol_permiso FROM lis_app;


-- ---------------------------------------------------------------------
-- 6 · El alta apunta a la tabla nueva y enciende los DOS modulos
-- ---------------------------------------------------------------------
-- En el esquema definitivo esto son dos lineas dentro de core.crear_empresa().
-- Aqui se parchea sobre la definicion viva para poder probarlo sin tocar
-- 16_roles.sql. Recordar que ese flujo esta sin definir a proposito (H-91).

DO $patch$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'core' AND p.proname = 'crear_empresa';

  d := regexp_replace(d,
    'INSERT INTO core\.modulo_sucursal[^;]*;',
    'INSERT INTO plataforma.modulo_sucursal '
    || '(sucursal_id, modulo_id, empresa_id, asignado_por) VALUES '
    || '(v_sucursal_id, ''core'', v_empresa_id, ''alta''), '
    || '(v_sucursal_id, ''lab_clinico'', v_empresa_id, ''alta'');');

  EXECUTE d;
END $patch$;
