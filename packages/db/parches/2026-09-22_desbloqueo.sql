-- =====================================================================
-- ProLisSaas - parche: desbloquear una cuenta sin codigo nuevo
--
-- Para una base ya cargada. Va DESPUES de 2026-09-22_propietario.sql (usa
-- core.puede_tocar_cuenta, que viene de ahi).
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-22_desbloqueo.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- POR QUE HACE FALTA
-- ------------------
-- La cuenta se bloquea sola al quinto intento fallido. Hasta hoy la unica
-- salida era generarle un codigo de activacion nuevo, que la deja sin clave
-- y obliga a la persona a inventarse otra cada vez que se equivoca cinco
-- veces. Ahora hay dos caminos distintos, cada uno para su estado:
--
--   pendiente_activacion  generar un codigo nuevo (el anterior se anula)
--   bloqueado             desbloquear: contador en cero, estado activo,
--                         la clave sigue siendo la suya
-- =====================================================================

CREATE OR REPLACE FUNCTION core.desbloquear_usuario(
  p_usuario_id bigint,
  p_motivo     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_empresa  bigint := core.empresa_actual();
  v_yo       bigint := core.usuario_actual();
  v_estado   core.estado_usuario;
  v_intentos smallint;
BEGIN
  IF v_empresa IS NULL OR v_yo IS NULL THEN
    RAISE EXCEPTION 'No hay sesion puesta' USING ERRCODE = '28000';
  END IF;

  IF NOT core.usuario_puede('usuario.administrar') THEN
    RAISE EXCEPTION 'No tiene permiso para desbloquear cuentas' USING ERRCODE = '42501';
  END IF;

  SELECT estado, intentos_fallidos INTO v_estado, v_intentos
    FROM core.usuario
   WHERE usuario_id = p_usuario_id AND empresa_id = v_empresa;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ese usuario no es de esta empresa' USING ERRCODE = '42501';
  END IF;

  IF NOT core.puede_tocar_cuenta(p_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario toca la cuenta de un administrador'
      USING ERRCODE = '42501';
  END IF;

  IF v_estado <> 'bloqueado' THEN
    RAISE EXCEPTION 'La cuenta no esta bloqueada: esta %', v_estado
      USING ERRCODE = '22023';
  END IF;

  UPDATE core.usuario
     SET estado = 'activo', intentos_fallidos = 0
   WHERE usuario_id = p_usuario_id;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_empresa, v_yo, 'usuario.desbloquear', 'core', 'usuario', p_usuario_id,
    jsonb_build_object('estado', 'bloqueado', 'intentos_fallidos', v_intentos),
    jsonb_build_object('estado', 'activo',
                       'motivo', coalesce(nullif(trim(p_motivo), ''),
                                          'desbloqueado desde la administracion de usuarios'))
  );
END
$fn$;

COMMENT ON FUNCTION core.desbloquear_usuario IS
  'De bloqueado a activo, con el contador en cero y sin codigo nuevo: la clave sigue '
  'siendo la suya. Solo desde bloqueado; la cuenta de un administrador solo la abre el '
  'propietario. Queda en audit.evento.';

REVOKE ALL     ON FUNCTION core.desbloquear_usuario(bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.desbloquear_usuario(bigint, text) TO lis_app;


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core' AND p.proname = 'desbloquear_usuario')             AS funcion,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core' AND p.proname = 'puede_tocar_cuenta')              AS depende_de_propietario,
  (SELECT count(*) FROM core.usuario WHERE estado = 'bloqueado')                 AS cuentas_bloqueadas_hoy;

-- Tiene que salir: funcion = 1 · depende_de_propietario = 1 (si sale 0, falta
-- correr 2026-09-22_propietario.sql primero)
