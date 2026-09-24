-- =====================================================================
-- ProLisSaas - parche: el username se edita, y el empleado manda sobre su cuenta
--
-- Para una base ya cargada. Va DESPUES de 2026-09-22_propietario.sql y de
-- 2026-09-22_desbloqueo.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-23_cuenta.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- QUE CAMBIA
-- ----------
--   core.cambiar_username()    la unica forma de escribir usuario.username
--   core.suspender_usuario()   a suspendido, con motivo y bitacora
--   core.reactivar_usuario()   de suspendido a activo (o a pendiente si
--                              nunca estreno clave)
--   trigger tg_empleado_activo empleado.activo manda sobre la cuenta: un
--                              empleado inactivo no entra. Antes seguia
--                              entrando.
--   crear_usuario()            ya no le da cuenta a un empleado inactivo
--
-- QUE NO HACE: no toca las cuentas que ya existen. Un empleado que HOY este
-- inactivo con cuenta activa sigue asi hasta que alguien lo toque; la
-- consulta del final los lista para que se decida uno por uno.
-- =====================================================================

BEGIN;

CREATE OR REPLACE FUNCTION core.cambiar_username(
  p_usuario_id bigint,
  p_username   text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_nuevo   text   := lower(trim(p_username));
  v_actual  text;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para cambiar nombres de usuario' USING ERRCODE = '42501';
  END IF;

  SELECT username INTO v_actual
    FROM core.usuario
   WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  IF NOT core.puede_tocar_cuenta(p_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario toca la cuenta de un administrador'
      USING ERRCODE = '42501';
  END IF;

  IF v_nuevo !~ '^[a-z0-9._-]{3,40}$' THEN
    RAISE EXCEPTION 'El nombre de usuario lleva de 3 a 40 letras, numeros, punto, guion o guion bajo, sin espacios'
      USING ERRCODE = '22023';
  END IF;

  IF v_nuevo = v_actual THEN
    RETURN false;
  END IF;

  UPDATE core.usuario SET username = v_nuevo
   WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa, v_yo, 'usuario.username_cambiar', 'core', 'usuario', p_usuario_id,
    jsonb_build_object('username', v_actual),
    jsonb_build_object('username', v_nuevo)
  );

  RETURN true;
END
$fn$;

COMMENT ON FUNCTION core.cambiar_username IS
  'La unica forma de escribir usuario.username. Minusculas, formato del CHECK, la '
  'cuenta de un administrador solo la toca el propietario. false si ya era ese.';

CREATE OR REPLACE FUNCTION core.suspender_usuario(
  p_usuario_id bigint,
  p_motivo     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_estado  core.estado_usuario;
  v_sistema boolean;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para suspender cuentas' USING ERRCODE = '42501';
  END IF;

  SELECT u.estado, r.es_sistema INTO v_estado, v_sistema
    FROM core.usuario u JOIN core.rol r ON r.rol_id = u.rol_id
   WHERE u.usuario_id = p_usuario_id AND u.empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  IF v_sistema THEN
    RAISE EXCEPTION 'La cuenta del propietario no se suspende: se traspasa'
      USING ERRCODE = '42501',
            HINT = 'traspasar la propiedad es una operacion del operador';
  END IF;

  IF NOT core.puede_tocar_cuenta(p_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario toca la cuenta de un administrador'
      USING ERRCODE = '42501';
  END IF;

  IF v_estado = 'suspendido' THEN
    RETURN;
  END IF;

  UPDATE core.usuario SET estado = 'suspendido'
   WHERE usuario_id = p_usuario_id;

  -- Un codigo vivo no sirve de nada en una cuenta suspendida, y no tiene
  -- que seguir sirviendo cuando se reactive: se anula.
  UPDATE core.activacion
     SET anulado_en = now(), anulado_motivo = 'cuenta suspendida'
   WHERE usuario_id = p_usuario_id
     AND usado_en IS NULL AND anulado_en IS NULL;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa, v_yo, 'usuario.suspender', 'core', 'usuario', p_usuario_id,
    jsonb_build_object('estado', v_estado),
    jsonb_build_object('estado', 'suspendido',
                       'motivo', coalesce(nullif(trim(p_motivo), ''), 'empleado desactivado'))
  );
END
$fn$;

COMMENT ON FUNCTION core.suspender_usuario IS
  'A suspendido, con motivo y en la bitacora. La del propietario no; la de un '
  'administrador solo el propietario. Anula el codigo vivo si lo habia.';

CREATE OR REPLACE FUNCTION core.reactivar_usuario(
  p_usuario_id bigint,
  p_motivo     text DEFAULT NULL
) RETURNS core.estado_usuario
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_estado  core.estado_usuario;
  v_sinclave boolean;
  v_nuevo   core.estado_usuario;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para reactivar cuentas' USING ERRCODE = '42501';
  END IF;

  SELECT estado, password_hash = '' INTO v_estado, v_sinclave
    FROM core.usuario
   WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  IF NOT core.puede_tocar_cuenta(p_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario toca la cuenta de un administrador'
      USING ERRCODE = '42501';
  END IF;

  IF v_estado <> 'suspendido' THEN
    RETURN v_estado;
  END IF;

  v_nuevo := CASE WHEN v_sinclave THEN 'pendiente_activacion' ELSE 'activo' END;

  UPDATE core.usuario SET estado = v_nuevo, intentos_fallidos = 0
   WHERE usuario_id = p_usuario_id;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa, v_yo, 'usuario.reactivar', 'core', 'usuario', p_usuario_id,
    jsonb_build_object('estado', 'suspendido'),
    jsonb_build_object('estado', v_nuevo,
                       'motivo', coalesce(nullif(trim(p_motivo), ''), 'empleado reactivado'))
  );

  RETURN v_nuevo;
END
$fn$;

COMMENT ON FUNCTION core.reactivar_usuario IS
  'De suspendido a activo (o a pendiente_activacion si nunca estreno clave). Devuelve '
  'el estado en que quedo. Mismas guardias que suspender.';

CREATE OR REPLACE FUNCTION core.tg_empleado_activo()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_usuario bigint;
BEGIN
  IF current_user <> 'lis_app' OR NEW.activo = OLD.activo THEN
    RETURN NEW;
  END IF;

  SELECT usuario_id INTO v_usuario
    FROM core.usuario
   WHERE empleado_id = NEW.empleado_id AND empresa_id = NEW.empresa_id;
  IF v_usuario IS NULL THEN
    RETURN NEW;   -- sin cuenta no hay nada que suspender
  END IF;

  IF NEW.activo THEN
    PERFORM core.reactivar_usuario(v_usuario, 'empleado reactivado');
  ELSE
    PERFORM core.suspender_usuario(v_usuario, 'empleado desactivado');
  END IF;

  RETURN NEW;
END
$fn$;

DROP TRIGGER IF EXISTS tg_empleado_activo ON core.empleado;

CREATE TRIGGER tg_empleado_activo
  BEFORE UPDATE OF activo ON core.empleado
  FOR EACH ROW EXECUTE FUNCTION core.tg_empleado_activo();

COMMENT ON TRIGGER tg_empleado_activo ON core.empleado IS
  'Empleado inactivo = cuenta suspendida; reactivarlo la devuelve. Solo desde lis_app; '
  'el operador (postgres) queda fuera a proposito.';

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
  v_nuevo   bigint;
BEGIN
  -- SECURITY DEFINER porque lis_app ya no tiene INSERT sobre core.usuario:
  -- esta funcion es la unica puerta. Y como DEFINER se salta RLS, TODO lo que
  -- RLS validaba solo hay que validarlo aqui a mano. Son cuatro cosas:

  -- 1 · que haya sesion. Sin esto, v_empresa seria NULL y la fila caeria
  --     colgada de la nada.
  IF v_empresa IS NULL OR core.usuario_actual() IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  -- 2 · el permiso. Con usuario_puede() y no exigir_permiso(): adentro de un
  --     SECURITY DEFINER, current_user es postgres y exigir_permiso() se
  --     saltaria la comprobacion en silencio (H-57).
  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para crear usuarios'
      USING ERRCODE = '42501';
  END IF;

  -- 3 · que el empleado sea de SU empresa. Sin RLS de por medio, un admin de
  --     la empresa 1 podria colgarle un usuario a un empleado de la 2.
  IF NOT EXISTS (SELECT 1 FROM core.empleado
                  WHERE empleado_id = p_empleado_id AND empresa_id = v_empresa) THEN
    RAISE EXCEPTION 'El empleado no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  -- 3b · y que este activo: empleado inactivo = cuenta suspendida, y una
  --      cuenta no nace suspendida. Primero se reactiva al empleado.
  IF NOT (SELECT activo FROM core.empleado WHERE empleado_id = p_empleado_id) THEN
    RAISE EXCEPTION 'Un empleado inactivo no puede tener cuenta: primero hay que reactivarlo'
      USING ERRCODE = '22023';
  END IF;

  -- 4 · y que el rol tambien lo sea.
  IF NOT EXISTS (SELECT 1 FROM core.rol
                  WHERE rol_id = p_rol_id AND empresa_id = v_empresa) THEN
    RAISE EXCEPTION 'El rol no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  -- 5 · el rol del propietario no se asigna: lo pone el operador, una vez.
  IF (SELECT es_sistema FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'El rol del propietario no se asigna: se traspasa'
      USING ERRCODE = '42501',
            HINT = 'traspasar la propiedad es una operacion del operador';
  END IF;

  -- 6 · y una cuenta que va a poder crear usuarios solo la crea quien
  --     tiene el extra. Si no, un administrador se clona a voluntad.
  IF core.rol_es_admin(p_rol_id) AND NOT core.usuario_puede('usuario.nombrar_admin') THEN
    RAISE EXCEPTION 'Solo el propietario nombra administradores'
      USING ERRCODE = '42501';
  END IF;

  -- password_hash vacio: no es el hash de nada, y ningun argon2.verify lo va
  -- a dar por bueno. Ademas el estado ya impide entrar.
  INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username,
                            password_hash, estado)
  VALUES (v_empresa, p_empleado_id, p_rol_id, lower(p_username),
          '', 'pendiente_activacion')
  RETURNING usuario_id INTO v_nuevo;

  RETURN v_nuevo;
END
$fn$;

REVOKE ALL     ON FUNCTION core.cambiar_username(bigint, text)    FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.suspender_usuario(bigint, text)   FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.reactivar_usuario(bigint, text)   FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.cambiar_username(bigint, text)    TO lis_app;
GRANT  EXECUTE ON FUNCTION core.suspender_usuario(bigint, text)   TO lis_app;
GRANT  EXECUTE ON FUNCTION core.reactivar_usuario(bigint, text)   TO lis_app;

COMMIT;


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core'
      AND p.proname IN ('cambiar_username','suspender_usuario','reactivar_usuario','tg_empleado_activo')) AS funciones,
  (SELECT count(*) FROM pg_trigger WHERE tgname = 'tg_empleado_activo' AND NOT tgisinternal)            AS trigger_puesto;

-- Tiene que salir: funciones = 4 · trigger_puesto = 1

-- Empleados inactivos que todavia tienen cuenta sin suspender. Con el
-- trigger ya no se puede producir; los que existan de antes se deciden a
-- mano (desactivar y reactivar al empleado desde la pantalla los alinea).
SELECT e.empleado_id, e.nombres || ' ' || e.apellidos AS empleado, u.username, u.estado
FROM core.empleado e JOIN core.usuario u ON u.empleado_id = e.empleado_id
WHERE NOT e.activo AND u.estado <> 'suspendido'
ORDER BY 1;
