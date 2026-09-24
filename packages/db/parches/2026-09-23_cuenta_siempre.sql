-- =====================================================================
-- ProLisSaas - parche: todo empleado tiene cuenta, tambien el inactivo
--
-- Para una base ya cargada. Va DESPUES de los cuatro anteriores
-- (2026-09-22_propietario, 2026-09-22_desbloqueo, 2026-09-23_permiso_unico,
-- 2026-09-23_cuenta).
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-23_cuenta_siempre.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- QUE CAMBIA
-- ----------
--   core.crear_usuario()       ya no rechaza al empleado inactivo: le crea la
--                              cuenta SUSPENDIDA (empleado inactivo = cuenta
--                              suspendida, la regla del trigger). Nace sin
--                              codigo; cuando lo activen, reactivar_usuario()
--                              la deja en pendiente_activacion y ahi se le
--                              genera el codigo.
--   core.generar_activacion()  rechaza a una cuenta suspendida (22023): un
--                              codigo la dejaria en pendiente_activacion, que
--                              es des-suspenderla por la puerta de atras.
--
-- QUE NO HACE: no toca las cuentas que ya existen.
-- =====================================================================

BEGIN;

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

  -- 3b · con que estado nace. Todo empleado tiene cuenta (empleado y
  --      usuario son uno), tambien el que se registra inactivo -- alguien
  --      que empieza el mes que viene. Empleado inactivo = cuenta
  --      suspendida, la misma regla que aplica tg_empleado_activo al
  --      desactivar a alguien. Nace sin codigo: cuando lo activen,
  --      reactivar_usuario() la deja en pendiente_activacion (no tiene
  --      clave) y ahi se le genera el codigo.
  SELECT activo INTO v_activo FROM core.empleado WHERE empleado_id = p_empleado_id;

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
  VALUES (v_empresa, p_empleado_id, p_rol_id, lower(p_username), '',
          CASE WHEN v_activo THEN 'pendiente_activacion'::core.estado_usuario
                             ELSE 'suspendido'::core.estado_usuario END)
  RETURNING usuario_id INTO v_nuevo;

  RETURN v_nuevo;
END
$fn$;

CREATE OR REPLACE FUNCTION core.generar_activacion(
  p_usuario_id  bigint,
  p_codigo_hash text,
  p_horas       int DEFAULT 24
) RETURNS TABLE (activacion_id bigint, vence_en timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa bigint := core.empresa_actual();
  v_yo      bigint := core.usuario_actual();
  v_vence   timestamptz := now() + make_interval(hours => p_horas);
  v_id      bigint;
BEGIN
  -- SECURITY DEFINER porque lis_app no tiene ningun privilegio sobre
  -- core.activacion. Mismas validaciones a mano que crear_usuario().
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para generar codigos de activacion'
      USING ERRCODE = '42501';
  END IF;

  -- Que el usuario objetivo sea de SU empresa. Sin esto, un admin podria
  -- resetearle la clave a alguien de otro laboratorio.
  IF NOT EXISTS (SELECT 1 FROM core.usuario
                  WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa) THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  -- Resetear el codigo de alguien es tomarle la cuenta: la de un
  -- administrador (o la del propietario) solo la toca quien tiene el
  -- extra. Al crear no estorba: crear_usuario ya exigio lo mismo.
  IF NOT core.puede_tocar_cuenta(p_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario toca la cuenta de un administrador'
      USING ERRCODE = '42501';
  END IF;

  -- Una cuenta suspendida no recibe codigo: el codigo la dejaria en
  -- pendiente_activacion, que es des-suspenderla por la puerta de atras.
  -- Suspender fue una decision (o el empleado esta inactivo); se deshace
  -- por donde se tomo. Vale para crear tambien: la cuenta de un empleado
  -- inactivo nace suspendida y sin codigo.
  IF (SELECT estado FROM core.usuario WHERE usuario_id = p_usuario_id) = 'suspendido' THEN
    RAISE EXCEPTION 'La cuenta esta suspendida: primero hay que reactivarla'
      USING ERRCODE = '22023';
  END IF;

  IF p_horas < 1 OR p_horas > 168 THEN
    RAISE EXCEPTION 'El codigo tiene que vencer entre 1 hora y 7 dias'
      USING ERRCODE = '22023';
  END IF;

  -- Un solo codigo vivo por usuario (uq_activacion_viva). El anterior no se
  -- borra: se anula con motivo, como todo aqui.
  UPDATE core.activacion
     SET anulado_en = now(), anulado_motivo = 'reemplazado por uno nuevo'
   WHERE usuario_id = p_usuario_id
     AND usado_en IS NULL AND anulado_en IS NULL;

  -- El usuario queda sin clave y sin poder entrar hasta activar. Esto es lo
  -- que hace que estrenar y resetear sean el mismo camino.
  UPDATE core.usuario
     SET estado = 'pendiente_activacion',
         password_hash = '',
         intentos_fallidos = 0
   WHERE usuario_id = p_usuario_id;

  INSERT INTO core.activacion (usuario_id, empresa_id, codigo_hash, vence_en,
                               creado_por_usuario_id)
  VALUES (p_usuario_id, v_empresa, p_codigo_hash, v_vence, v_yo)
  RETURNING core.activacion.activacion_id INTO v_id;

  RETURN QUERY SELECT v_id, v_vence;
END
$fn$;

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion: las dos funciones dicen lo nuevo
-- ---------------------------------------------------------------------
SELECT proname,
       position('suspendido' in prosrc) > 0 AS habla_de_suspendido
  FROM pg_proc
 WHERE pronamespace = 'core'::regnamespace
   AND proname IN ('crear_usuario', 'generar_activacion')
 ORDER BY proname;
