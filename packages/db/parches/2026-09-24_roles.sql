-- =====================================================================
-- ProLisSaas - parche: el modulo de roles
--
-- Para una base ya cargada. Va DESPUES de 2026-09-23_empleado_unico.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-24_roles.sql
--
-- Se puede correr dos veces sin romper nada. ASCII puro.
--
-- QUE CAMBIA
-- ----------
--   plataforma.permiso.nivel   normal | admin | propietario. Decide quien puede
--                              poner cada permiso en un rol. Lo leen
--                              rol_es_admin() y asignar_permisos_a_rol().
--   core.rol.es_fijo           Propietario y Administrador: los entrego el
--                              operador; desde el LIS no se editan ni desactivan.
--   core.rol.activo            un rol desactivado ya no se asigna a nadie.
--   uq_rol_nombre              pasa de UNIQUE (empresa_id, nombre) a un indice
--                              por llave (minusculas, sin acentos, un espacio).
--   core.rol cerrada           lis_app ya no escribe core.rol a mano: crear_rol,
--                              editar_rol, desactivar_rol, reactivar_rol.
--   asignar_permisos_a_rol     mira el nivel; nadie edita un rol fijo ni el rol
--                              que tiene puesto; con el mismo conjunto no escribe.
--   crear_usuario, cambiar_rol rechazan un rol desactivado.
--   crear_empresa              deja fijos a Propietario y Administrador.
--   permisos_disponibles       devuelve tambien el nivel.
--
-- Si hay roles con el mismo nombre escrito distinto ("Recepcion" y "recepcion"),
-- se detiene y los lista: hay que decidir a mano y volver a correrlo.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. El tipo, las columnas, los niveles
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                  WHERE n.nspname = 'plataforma' AND t.typname = 'nivel_permiso') THEN
    CREATE TYPE plataforma.nivel_permiso AS ENUM ('normal', 'admin', 'propietario');
  END IF;
END $$;

ALTER TABLE plataforma.permiso ADD COLUMN IF NOT EXISTS nivel plataforma.nivel_permiso NOT NULL DEFAULT 'normal';
ALTER TABLE core.rol ADD COLUMN IF NOT EXISTS es_fijo boolean NOT NULL DEFAULT false;
ALTER TABLE core.rol ADD COLUMN IF NOT EXISTS activo  boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN core.rol.es_fijo IS
  'true en los roles que ENTREGA EL OPERADOR con la empresa: Propietario y '
  'Administrador. Desde el LIS no se editan (nombre, descripcion, permisos) ni se '
  'desactivan: son la garantia de que la empresa siempre tiene quien administre y de '
  'que "Administrador" significa lo mismo en todos los clientes. Los mantiene el '
  'operador. Si el cliente quiere un administrador a su medida, el propietario crea '
  'otro rol con usuario.administrar, y ese si es suyo.';

COMMENT ON COLUMN core.rol.activo IS
  'false = ya no se asigna: sale del catalogo y crear_usuario / cambiar_rol lo '
  'rechazan. No se puede desactivar un rol que alguien tenga puesto '
  '(desactivar_rol se niega y dice cuantos): asi nunca existe una sesion con rol '
  'desactivado y usuario_puede() no necesita un caso aparte.';

UPDATE plataforma.permiso SET nivel = 'propietario'
 WHERE permiso_id = 'usuario.nombrar_admin' AND nivel <> 'propietario';
UPDATE plataforma.permiso SET nivel = 'admin'
 WHERE permiso_id IN ('usuario.administrar', 'sucursal.administrar') AND nivel <> 'admin';

-- ---------------------------------------------------------------------
-- 2. La llave del nombre y el indice unico sobre ella
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.llave_texto(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(lower(public.unaccent_simple(coalesce(p_texto,''))), '')
$$;

GRANT EXECUTE ON FUNCTION core.llave_texto(text) TO lis_app;

DO $$
DECLARE v_lista text;
BEGIN
  SELECT string_agg(format('  empresa %s: "%s" (roles %s)', empresa_id, llave, ids), E'\n')
    INTO v_lista
    FROM (SELECT empresa_id, core.llave_texto(nombre) AS llave,
                 string_agg(rol_id::text, ', ' ORDER BY rol_id) AS ids
            FROM core.rol GROUP BY 1, 2 HAVING count(*) > 1) d;
  IF v_lista IS NOT NULL THEN
    RAISE EXCEPTION E'Hay roles con el mismo nombre escrito distinto; hay que resolverlos a mano antes de seguir:\n%', v_lista;
  END IF;
END $$;

ALTER TABLE core.rol DROP CONSTRAINT IF EXISTS uq_rol_nombre;
CREATE UNIQUE INDEX IF NOT EXISTS uq_rol_nombre ON core.rol (empresa_id, core.llave_texto(nombre));

-- Los que entrego el operador: el del propietario (es_sistema) y Administrador.
UPDATE core.rol SET es_fijo = true
 WHERE (es_sistema OR core.llave_texto(nombre) = 'administrador') AND NOT es_fijo;

-- ---------------------------------------------------------------------
-- 3. Las funciones (mismo texto que en esquema/04_funciones.sql)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.rol_es_admin(p_rol_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  -- De administrador = tiene algun permiso de nivel 'admin' (hoy
  -- usuario.administrar y sucursal.administrar). El nivel vive en
  -- plataforma.permiso, no aqui: un modulo nuevo trae sus permisos con su
  -- nivel y esta funcion no cambia.
  SELECT EXISTS (
    SELECT 1
    FROM core.rol_permiso rp
    JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
    WHERE rp.rol_id = p_rol_id AND p.nivel = 'admin'
  )
$$;

CREATE OR REPLACE FUNCTION core.asignar_permisos_a_rol(
  p_rol_id     bigint,
  p_permisos   text[],
  p_usuario_id bigint DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
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

  -- EL INVARIANTE: nadie edita un rol que pueda editar roles, salvo el
  -- propietario. Editar roles es usuario.administrar; cualquier rol que lo
  -- tenga es de administrador (nivel 'admin'); y un rol de administrador --
  -- o uno que pasaria a serlo -- lo edita solo quien tiene el extra. Asi la
  -- cadena se corta sola: un administrador edita Recepcion, no Administrador,
  -- ni el suyo, ni vuelve administradores a Recepcion, ni se deja a la
  -- empresa sin nadie que cree usuarios (H-90). De aqui salen las reglas:
  --   - el rol del propietario no se edita, por nadie
  --   - un rol fijo (lo entrego el operador) tampoco: lo mantiene el operador
  --   - nadie edita el rol que tiene puesto (dicho aparte, con su mensaje)
  --   - un permiso de nivel 'propietario' no se asigna nunca
  --   - un permiso de nivel 'admin' lo asigna solo el propietario
  IF (SELECT es_sistema FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'Los permisos del propietario no se editan'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF (SELECT es_fijo FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'Este rol lo entrego el operador y lo mantiene el operador: sus permisos no se editan desde aqui'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_rol_id = (SELECT rol_id FROM core.usuario WHERE usuario_id = v_usuario_id) THEN
    RAISE EXCEPTION 'No se edita el rol que tenes puesto'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Los que no existen se nombran, no se dejan caer en la llave foranea.
  SELECT array_agg(x ORDER BY x) INTO v_ajenos
  FROM unnest(p_permisos) AS x
  WHERE NOT EXISTS (SELECT 1 FROM plataforma.permiso p WHERE p.permiso_id = x);
  IF v_ajenos IS NOT NULL THEN
    RAISE EXCEPTION 'Estos permisos no existen: %', array_to_string(v_ajenos, ', ')
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (SELECT 1 FROM plataforma.permiso p
              WHERE p.permiso_id = ANY (p_permisos) AND p.nivel = 'propietario') THEN
    RAISE EXCEPTION 'Los permisos del propietario no se asignan a otro rol'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF (core.rol_es_admin(p_rol_id)
      OR EXISTS (SELECT 1 FROM plataforma.permiso p
                  WHERE p.permiso_id = ANY (p_permisos) AND p.nivel = 'admin'))
     AND NOT core.usuario_puede('usuario.nombrar_admin', v_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario cambia los permisos de un rol de administrador, o vuelve administrador a un rol'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Los que no pertenecen a un modulo encendido en ninguna sede. El error los
  -- nombra: "no se pudo" no le sirve a nadie.
  SELECT array_agg(x ORDER BY x) INTO v_ajenos
  FROM unnest(p_permisos) AS x
  WHERE NOT EXISTS (
    SELECT 1
    FROM plataforma.permiso p
    JOIN plataforma.modulo_sucursal ms
      ON ms.modulo_id = p.modulo_id AND ms.activo AND ms.empresa_id = v_empresa_id
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

  -- El mismo conjunto: no se escribe nada y no hay evento. Que el API pueda
  -- mandar los permisos tal como estan en pantalla sin comparar antes.
  IF v_antes = (SELECT coalesce(jsonb_agg(DISTINCT x ORDER BY x), '[]'::jsonb) FROM unnest(p_permisos) AS x) THEN
    RETURN (SELECT count(*) FROM core.rol_permiso WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id);
  END IF;

  DELETE FROM core.rol_permiso
  WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id
    AND permiso_id <> ALL (p_permisos);

  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT p_rol_id, x, v_empresa_id FROM unnest(p_permisos) AS x
  ON CONFLICT DO NOTHING;

  SELECT count(*) INTO v_cuantos
  FROM core.rol_permiso WHERE rol_id = p_rol_id AND empresa_id = v_empresa_id;

  -- Cambiar lo que puede un rol es la modificacion mas delicada del sistema y
  -- hasta hoy no dejaba ningun rastro: rol_permiso no tiene ni una fecha, y no
  -- podria tenerla, porque el cambio es un INSERT o un DELETE y no el UPDATE
  -- de una fila. El rastro va donde corresponde, que es la bitacora.
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

COMMENT ON FUNCTION core.asignar_permisos_a_rol IS
  'La unica forma de escribir core.rol_permiso. REEMPLAZA el conjunto entero; con el '
  'mismo conjunto no escribe ni deja evento. Lee el NIVEL de cada permiso: los de '
  'propietario no se asignan, los de admin solo los pone el propietario. Nadie edita '
  'un rol fijo ni el rol que tiene puesto. Registra el cambio en audit.evento.';

CREATE OR REPLACE FUNCTION core.rol_para_editar(p_rol_id bigint, p_que text)
RETURNS core.rol
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_rol     core.rol%ROWTYPE;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;
  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para administrar roles' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_rol FROM core.rol WHERE rol_id = p_rol_id AND empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese rol no existe en esta empresa' USING ERRCODE = '42501';
  END IF;
  IF v_rol.es_fijo THEN
    RAISE EXCEPTION 'Este rol lo entrego el operador y lo mantiene el operador: no se % desde aqui', p_que
      USING ERRCODE = '42501';
  END IF;
  IF v_rol.rol_id = (SELECT rol_id FROM core.usuario WHERE usuario_id = v_yo) THEN
    RAISE EXCEPTION 'No se % el rol que tenes puesto', p_que USING ERRCODE = '42501';
  END IF;
  IF core.rol_es_admin(v_rol.rol_id) AND NOT core.usuario_puede('usuario.nombrar_admin') THEN
    RAISE EXCEPTION 'Solo el propietario % un rol de administrador', p_que USING ERRCODE = '42501';
  END IF;
  RETURN v_rol;
END
$fn$;

CREATE OR REPLACE FUNCTION core.crear_rol(p_nombre text, p_descripcion text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_nombre  text   := btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g'));
  v_desc    text   := nullif(btrim(coalesce(p_descripcion, '')), '');
  v_nuevo   bigint;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;
  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para crear roles' USING ERRCODE = '42501';
  END IF;
  IF length(v_nombre) < 2 OR length(v_nombre) > 60 THEN
    RAISE EXCEPTION 'El nombre del rol lleva de 2 a 60 caracteres' USING ERRCODE = '22023';
  END IF;
  -- La descripcion no es adorno: es lo que lee quien va a asignar el rol
  -- ("a quien se le pone"). Sin ella, un rol es un nombre y una lista de
  -- codigos.
  IF v_desc IS NULL OR length(v_desc) > 200 THEN
    RAISE EXCEPTION 'Hace falta la descripcion del rol (hasta 200 caracteres)' USING ERRCODE = '22023';
  END IF;

  -- El nombre repetido lo atrapa uq_rol_nombre (23505); aqui se dice con
  -- palabras, porque el indice solo sabe decir "duplicate key".
  IF EXISTS (SELECT 1 FROM core.rol
              WHERE empresa_id = v_empresa AND core.llave_texto(nombre) = core.llave_texto(v_nombre)) THEN
    RAISE EXCEPTION 'Ya hay un rol con ese nombre' USING ERRCODE = '23505';
  END IF;

  -- Nace sin permisos y ACTIVO: los permisos los pone asignar_permisos_a_rol
  -- en la misma transaccion (lo hace el API); un rol vacio que quede
  -- guardado es una transaccion que se deshizo a medias, y eso no pasa.
  INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema, es_fijo, activo)
  VALUES (v_empresa, v_nombre, v_desc, false, false, true)
  RETURNING rol_id INTO v_nuevo;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_despues)
  VALUES (v_empresa, v_yo, 'rol.crear', 'core', 'rol', v_nuevo,
          jsonb_build_object('nombre', v_nombre, 'descripcion', v_desc));

  RETURN v_nuevo;
END
$fn$;

CREATE OR REPLACE FUNCTION core.editar_rol(p_rol_id bigint, p_nombre text, p_descripcion text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_rol     core.rol%ROWTYPE := core.rol_para_editar(p_rol_id, 'edita');
  v_nombre  text := btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g'));
  v_desc    text := nullif(btrim(coalesce(p_descripcion, '')), '');
BEGIN
  IF length(v_nombre) < 2 OR length(v_nombre) > 60 THEN
    RAISE EXCEPTION 'El nombre del rol lleva de 2 a 60 caracteres' USING ERRCODE = '22023';
  END IF;
  IF v_desc IS NULL OR length(v_desc) > 200 THEN
    RAISE EXCEPTION 'Hace falta la descripcion del rol (hasta 200 caracteres)' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM core.rol
              WHERE empresa_id = v_rol.empresa_id AND rol_id <> p_rol_id
                AND core.llave_texto(nombre) = core.llave_texto(v_nombre)) THEN
    RAISE EXCEPTION 'Ya hay un rol con ese nombre' USING ERRCODE = '23505';
  END IF;

  -- Igual que estaba: no se escribe ni hay evento.
  IF v_rol.nombre = v_nombre AND v_rol.descripcion IS NOT DISTINCT FROM v_desc THEN
    RETURN false;
  END IF;

  UPDATE core.rol SET nombre = v_nombre, descripcion = v_desc WHERE rol_id = p_rol_id;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_antes, datos_despues)
  VALUES (v_rol.empresa_id, core.usuario_actual(), 'rol.editar', 'core', 'rol', p_rol_id,
          jsonb_build_object('nombre', v_rol.nombre, 'descripcion', v_rol.descripcion),
          jsonb_build_object('nombre', v_nombre, 'descripcion', v_desc));
  RETURN true;
END
$fn$;

CREATE OR REPLACE FUNCTION core.desactivar_rol(p_rol_id bigint, p_motivo text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_rol     core.rol%ROWTYPE := core.rol_para_editar(p_rol_id, 'desactiva');
  v_cuantos integer;
BEGIN
  IF NOT v_rol.activo THEN
    RETURN false;
  END IF;

  SELECT count(*) INTO v_cuantos FROM core.usuario WHERE rol_id = p_rol_id;
  IF v_cuantos > 0 THEN
    RAISE EXCEPTION 'Hay % con este rol: cambiales el rol primero',
      CASE WHEN v_cuantos = 1 THEN '1 empleado' ELSE v_cuantos || ' empleados' END
      USING ERRCODE = '55006';
  END IF;

  UPDATE core.rol SET activo = false WHERE rol_id = p_rol_id;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_antes, datos_despues)
  VALUES (v_rol.empresa_id, core.usuario_actual(), 'rol.desactivar', 'core', 'rol', p_rol_id,
          jsonb_build_object('activo', true),
          jsonb_build_object('activo', false, 'motivo', coalesce(nullif(btrim(p_motivo), ''), 'desactivado desde la administracion de roles')));
  RETURN true;
END
$fn$;

CREATE OR REPLACE FUNCTION core.reactivar_rol(p_rol_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_rol core.rol%ROWTYPE := core.rol_para_editar(p_rol_id, 'reactiva');
BEGIN
  IF v_rol.activo THEN
    RETURN false;
  END IF;
  UPDATE core.rol SET activo = true WHERE rol_id = p_rol_id;
  INSERT INTO audit.evento (empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla, registro_id, datos_antes, datos_despues)
  VALUES (v_rol.empresa_id, core.usuario_actual(), 'rol.reactivar', 'core', 'rol', p_rol_id,
          jsonb_build_object('activo', false), jsonb_build_object('activo', true));
  RETURN true;
END
$fn$;

COMMENT ON FUNCTION core.crear_rol IS
  'La unica forma de crear un rol. Nace activo y sin permisos; el API le pone los '
  'permisos con asignar_permisos_a_rol en la misma transaccion. Exige usuario.administrar; '
  'nombre unico por llave (2 a 60) y descripcion obligatoria (hasta 200). Deja rol.crear en audit.evento.';

COMMENT ON FUNCTION core.editar_rol IS
  'Nombre y descripcion (los dos obligatorios). Un rol fijo, el propio o uno de '
  'administrador (sin ser propietario) no se editan. Devuelve false si no cambio nada. Deja rol.editar.';

COMMENT ON FUNCTION core.desactivar_rol IS
  'Ya no se asigna. Se niega (55006) si algun usuario lo tiene: primero se les cambia '
  'el rol. Mismas guardas que editar_rol. Deja rol.desactivar con el motivo.';

COMMENT ON FUNCTION core.reactivar_rol IS
  'Vuelve a asignarse. Mismas guardas que editar_rol. Deja rol.reactivar.';

CREATE OR REPLACE FUNCTION core.crear_usuario(
  p_empleado_id bigint,
  p_rol_id      bigint,
  p_username    text
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_activo  boolean;
  v_nuevo   bigint;
BEGIN
  -- SECURITY DEFINER porque lis_app ya no tiene INSERT sobre core.usuario:
  -- esta funcion es la unica puerta. Y como DEFINER se salta RLS, TODO lo que
  -- RLS validaba solo hay que validarlo aqui a mano. Son cuatro cosas:

  -- 1 - que haya sesion. Sin esto, v_empresa seria NULL y la fila caeria
  --     colgada de la nada.
  IF v_empresa IS NULL OR core.usuario_actual() IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  -- 2 - el permiso. Con usuario_puede() y no exigir_permiso(): adentro de un
  --     SECURITY DEFINER, current_user es postgres y exigir_permiso() se
  --     saltaria la comprobacion en silencio (H-57).
  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para crear usuarios'
      USING ERRCODE = '42501';
  END IF;

  -- 3 - que el empleado sea de SU empresa. Sin RLS de por medio, un admin de
  --     la empresa 1 podria colgarle un usuario a un empleado de la 2.
  IF NOT EXISTS (SELECT 1 FROM core.empleado
                  WHERE empleado_id = p_empleado_id AND empresa_id = v_empresa) THEN
    RAISE EXCEPTION 'El empleado no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  -- 3b - con que estado nace. Todo empleado tiene cuenta (empleado y
  --      usuario son uno), tambien el que se registra inactivo -- alguien
  --      que empieza el mes que viene. Empleado inactivo = cuenta
  --      suspendida, la misma regla que aplica tg_empleado_activo al
  --      desactivar a alguien. Nace sin codigo: cuando lo activen,
  --      reactivar_usuario() la deja en pendiente_activacion (no tiene
  --      clave) y ahi se le genera el codigo.
  SELECT activo INTO v_activo FROM core.empleado WHERE empleado_id = p_empleado_id;

  -- 4 - y que el rol tambien lo sea.
  IF NOT EXISTS (SELECT 1 FROM core.rol
                  WHERE rol_id = p_rol_id AND empresa_id = v_empresa) THEN
    RAISE EXCEPTION 'El rol no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  -- 4b - y que este activo: un rol desactivado ya no se asigna.
  IF NOT (SELECT activo FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'Ese rol esta desactivado: ya no se asigna' USING ERRCODE = '22023';
  END IF;

  -- 5 - el rol del propietario no se asigna: lo pone el operador, una vez.
  IF (SELECT es_sistema FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'El rol del propietario no se asigna: se traspasa'
      USING ERRCODE = '42501',
            HINT = 'traspasar la propiedad es una operacion del operador';
  END IF;

  -- 6 - y una cuenta que va a poder crear usuarios solo la crea quien
  --     tiene el extra. Si no, un administrador se clona a voluntad.
  IF core.rol_es_admin(p_rol_id) AND NOT core.usuario_puede('usuario.nombrar_admin') THEN
    RAISE EXCEPTION 'Solo el propietario nombra administradores'
      USING ERRCODE = '42501';
  END IF;

  -- password_hash vacio: no es el hash de nada, y ningun argon2.verify lo va
  -- a dar por bueno. Ademas el estado ya impide entrar.
  INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username,
                            password_hash, estado)
  VALUES (v_empresa, p_empleado_id, p_rol_id, lower(p_username), '',
          CASE WHEN v_activo THEN 'pendiente_activacion'::core.estado_usuario
                             ELSE 'suspendido'::core.estado_usuario END)
  RETURNING usuario_id INTO v_nuevo;

  RETURN v_nuevo;
END
$fn$;

CREATE OR REPLACE FUNCTION core.cambiar_rol(
  p_usuario_id bigint,
  p_rol_id     bigint,
  p_motivo     text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa   bigint := core.empresa_actual();
  v_yo        bigint := core.usuario_actual();
  v_actual    core.rol%ROWTYPE;
  v_nuevo     core.rol%ROWTYPE;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para cambiar roles' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_actual
    FROM core.usuario u
    JOIN core.rol r ON r.rol_id = u.rol_id
   WHERE u.usuario_id = p_usuario_id AND u.empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_nuevo
    FROM core.rol r
   WHERE r.rol_id = p_rol_id AND r.empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese rol no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  IF v_actual.es_sistema THEN
    RAISE EXCEPTION 'El rol del propietario no se cambia'
      USING ERRCODE = '42501',
            HINT = 'traspasar la propiedad es una operacion del operador';
  END IF;

  IF v_nuevo.es_sistema THEN
    RAISE EXCEPTION 'El rol del propietario no se asigna: se traspasa'
      USING ERRCODE = '42501',
            HINT = 'traspasar la propiedad es una operacion del operador';
  END IF;

  IF NOT v_nuevo.activo AND v_nuevo.rol_id <> v_actual.rol_id THEN
    RAISE EXCEPTION 'Ese rol esta desactivado: ya no se asigna' USING ERRCODE = '22023';
  END IF;

  IF (core.rol_es_admin(v_actual.rol_id) OR core.rol_es_admin(v_nuevo.rol_id))
     AND NOT core.usuario_puede('usuario.nombrar_admin') THEN
    RAISE EXCEPTION 'Solo el propietario nombra o retira administradores'
      USING ERRCODE = '42501';
  END IF;

  -- Mismo rol: no hay cambio y no hay evento. Que el API no tenga que
  -- comparar antes de llamar.
  IF v_actual.rol_id = v_nuevo.rol_id THEN
    RETURN false;
  END IF;

  UPDATE core.usuario SET rol_id = p_rol_id
   WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa;

  -- Cambiar lo que alguien puede hacer es un hecho que hay que poder
  -- reconstruir: quien, a quien, de que a que, y por que.
  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa, v_yo, 'usuario.rol_cambiar', 'core', 'usuario', p_usuario_id,
    jsonb_build_object('rol_id', v_actual.rol_id, 'rol', v_actual.nombre),
    jsonb_build_object('rol_id', v_nuevo.rol_id,  'rol', v_nuevo.nombre,
                       'motivo', coalesce(nullif(trim(p_motivo), ''),
                                          'cambiado desde la administracion de usuarios'))
  );

  RETURN true;
END
$fn$;

CREATE OR REPLACE FUNCTION core.crear_empresa(
  p_nombre          text,
  p_rtn             text,
  p_sucursal_nombre text,
  p_sucursal_codigo text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id  bigint;
  v_sucursal_id bigint;
BEGIN
  INSERT INTO core.empresa (nombre, rtn, estado)
  VALUES (p_nombre, p_rtn, 'prueba')
  RETURNING empresa_id INTO v_empresa_id;

  INSERT INTO core.sucursal (empresa_id, nombre, codigo)
  VALUES (v_empresa_id, p_sucursal_nombre, upper(p_sucursal_codigo))
  RETURNING sucursal_id INTO v_sucursal_id;

  -- Toda empresa nace con el convenio "Particular" como predeterminado:
  -- ninguna orden existe sin convenio, ni siquiera la del paciente que
  -- llega directo y paga en el mostrador.
  INSERT INTO core.convenio (
    empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado
  ) VALUES (
    v_empresa_id, 'Particular', 'particular', 'particular', true
  );

  -- Correlativos: expediente por empresa, el resto por sucursal.
  INSERT INTO core.correlativo (empresa_id, sucursal_id, tipo, prefijo, ancho) VALUES
    (v_empresa_id, NULL,          'expediente', 'EXP-', 6),
    (v_empresa_id, v_sucursal_id, 'episodio',   upper(p_sucursal_codigo) || '-', 6),
    (v_empresa_id, v_sucursal_id, 'informe',    upper(p_sucursal_codigo) || 'I-', 6),
    (v_empresa_id, v_sucursal_id, 'orden',      upper(p_sucursal_codigo) || 'O-', 6),
    (v_empresa_id, v_sucursal_id, 'muestra',    upper(p_sucursal_codigo) || 'M-', 8);

  -- Los DOS modulos, no solo lab_clinico. Antes core no se encendia nunca, y
  -- como usuario_puede() ahora intersecta contra la licencia, los dieciseis
  -- permisos de core se caian y la empresa nacia sin poder hacer nada (H-27).
  INSERT INTO plataforma.modulo_sucursal
    (sucursal_id, modulo_id, empresa_id, asignado_por)
  VALUES
    (v_sucursal_id, 'core',        v_empresa_id, 'alta'),
    (v_sucursal_id, 'lab_clinico', v_empresa_id, 'alta');

  -- ------------------------------------------------------------------
  -- Los cinco roles con los que nace la empresa, CON sus permisos.
  --
  -- Que nazcan con permisos es el punto: un rol vacio es la promesa de que
  -- alguien lo va a configurar despues, y nadie lo hace.
  --
  -- No es una jerarquia. Son puestos de un laboratorio real, y sus
  -- permisos salen de lo que cada uno hace en el flujo. Los dos primeros
  -- son la excepcion: no son puestos, son quien administra.
  --
  --   PROPIETARIO   la cuenta que crea el OPERADOR. es_sistema: su rol no
  --                 se cambia, no se asigna y no se edita. Todo el catalogo
  --                 mas usuario.nombrar_admin.
  --   ADMINISTRADOR los que nombra el propietario. Todo el catalogo MENOS
  --                 el extra. Su rol si se cambia y se edita, pero solo
  --                 por el propietario.
  -- ------------------------------------------------------------------

  INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema, es_fijo) VALUES
    (v_empresa_id, 'Propietario',
     'La cuenta que el operador entrega con la empresa. Nombra a los administradores.', true, true),
    (v_empresa_id, 'Administrador',
     'Configura el sistema. No es un puesto clinico.', false, true),
    (v_empresa_id, 'Recepcion',
     'Admite pacientes, crea ordenes, toma muestras y entrega informes.', false, false),
    (v_empresa_id, 'Analista',
     'Recibe muestras, las procesa y captura resultados. No los aprueba.', false, false),
    (v_empresa_id, 'Bioquimico',
     'Todo lo del analista, mas validar, corregir y emitir informes.', false, false);
  -- Solo el Propietario va marcado como de sistema. Propietario y
  -- Administrador van como FIJOS: los mantiene el operador, el LIS no los
  -- edita ni los desactiva. Los otros tres tambien nacen con la empresa, pero
  -- son del cliente: los renombra, los repurposea o los desactiva.

  -- PROPIETARIO y ADMINISTRADOR se definen por EXCLUSION: todo lo que
  -- exista en el catalogo, incluidos los modulos que se agreguen despues.
  -- La unica diferencia entre los dos es el extra.
  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT r.rol_id, p.permiso_id, v_empresa_id
  FROM core.rol r
  CROSS JOIN plataforma.permiso p
  WHERE r.empresa_id = v_empresa_id
    AND (r.nombre = 'Propietario'
         OR (r.nombre = 'Administrador' AND p.permiso_id <> 'usuario.nombrar_admin'));

  -- Los tres puestos operativos, uno por uno.
  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT r.rol_id, t.permiso_id, v_empresa_id
  FROM (VALUES
    -- RECEPCION - la puerta de entrada y la de salida
    ('Recepcion',  'paciente.ver'),
    ('Recepcion',  'paciente.crear'),
    ('Recepcion',  'paciente.editar'),
    ('Recepcion',  'episodio.ver'),
    ('Recepcion',  'episodio.crear'),
    ('Recepcion',  'convenio.ver'),
    ('Recepcion',  'catalogo.ver'),            -- necesita ver precios para cobrar
    ('Recepcion',  'orden.ver'),
    ('Recepcion',  'orden.crear'),
    ('Recepcion',  'muestra.tomar'),           -- en un laboratorio chico, ella toma
    ('Recepcion',  'informe.entregar'),

    -- ANALISTA - procesa, pero NO aprueba. Esa separacion es el punto.
    ('Analista',   'paciente.ver'),
    ('Analista',   'episodio.ver'),
    ('Analista',   'catalogo.ver'),
    ('Analista',   'orden.ver'),
    ('Analista',   'muestra.recibir'),
    ('Analista',   'muestra.rechazar'),
    ('Analista',   'resultado.ver'),
    ('Analista',   'resultado.capturar'),

    -- BIOQUIMICO - lo del analista mas la firma
    ('Bioquimico', 'paciente.ver'),
    ('Bioquimico', 'episodio.ver'),
    ('Bioquimico', 'catalogo.ver'),
    ('Bioquimico', 'orden.ver'),
    ('Bioquimico', 'muestra.recibir'),
    ('Bioquimico', 'muestra.rechazar'),
    ('Bioquimico', 'resultado.ver'),
    ('Bioquimico', 'resultado.capturar'),
    ('Bioquimico', 'resultado.validar'),
    ('Bioquimico', 'resultado.corregir'),
    ('Bioquimico', 'valor_critico.registrar'),
    ('Bioquimico', 'informe.emitir'),
    ('Bioquimico', 'informe.corregir'),
    ('Bioquimico', 'catalogo.administrar'),    -- es quien define rangos y metodos
    ('Bioquimico', 'orden.anular')
  ) AS t(rol, permiso_id)
  JOIN core.rol r ON r.empresa_id = v_empresa_id AND r.nombre = t.rol;

  -- ------------------------------------------------------------------
  -- Lo que NINGUN rol operativo recibe, a proposito
  --
  --   paciente.fusionar      junta dos expedientes clinicos
  --   usuario.administrar    crear usuarios y cambiar permisos
  --   sucursal.administrar   configurar sedes
  --   equipo.administrar     tocar el mapeo de codigos de un analizador
  --   derivacion.solicitar   mandar datos de un paciente a otra empresa
  --   auditoria.ver          leer el rastro de todos
  --
  -- Los tienen solo el Propietario y el Administrador. Que no esten en
  -- recepcion ni en bioquimico no es un olvido: son acciones que cambian a
  -- quien puede hacer que, o que sacan datos de la empresa. Se dan una por
  -- una -- y usuario.administrar solo la da el propietario, porque darla es
  -- nombrar un administrador.
  -- ------------------------------------------------------------------

  RETURN v_empresa_id;
END $$;

-- Cambia lo que devuelve (agrega nivel): CREATE OR REPLACE no puede, se crea de nuevo.
DROP FUNCTION IF EXISTS core.permisos_disponibles(bigint);
CREATE OR REPLACE FUNCTION core.permisos_disponibles(p_sucursal_id bigint DEFAULT NULL)
RETURNS TABLE (permiso_id text, modulo_id text, descripcion text, nivel plataforma.nivel_permiso)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT p.permiso_id, p.modulo_id, p.descripcion, p.nivel
  FROM plataforma.permiso p
  JOIN plataforma.modulo_sucursal ms ON ms.modulo_id = p.modulo_id AND ms.activo
  WHERE p_sucursal_id IS NULL OR ms.sucursal_id = p_sucursal_id
  ORDER BY 2, 1
$$;

-- ---------------------------------------------------------------------
-- 4. Privilegios: core.rol cerrada; las funciones nuevas, para lis_app
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE ON core.rol FROM lis_app;
REVOKE ALL     ON FUNCTION core.crear_rol(text, text)              FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.editar_rol(bigint, text, text)     FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.desactivar_rol(bigint, text)       FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.reactivar_rol(bigint)              FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.rol_para_editar(bigint, text)      FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.crear_rol(text, text)              TO lis_app;
GRANT  EXECUTE ON FUNCTION core.editar_rol(bigint, text, text)     TO lis_app;
GRANT  EXECUTE ON FUNCTION core.desactivar_rol(bigint, text)       TO lis_app;
GRANT  EXECUTE ON FUNCTION core.reactivar_rol(bigint)              TO lis_app;

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT permiso_id, nivel FROM plataforma.permiso WHERE nivel <> 'normal' ORDER BY 2, 1;
SELECT empresa_id, nombre, es_sistema, es_fijo, activo FROM core.rol WHERE es_fijo ORDER BY 1, 2;
SELECT proname FROM pg_proc WHERE pronamespace = 'core'::regnamespace
   AND proname IN ('crear_rol', 'editar_rol', 'desactivar_rol', 'reactivar_rol', 'rol_para_editar') ORDER BY 1;
