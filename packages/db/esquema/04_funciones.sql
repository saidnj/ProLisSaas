-- =====================================================================
-- ProLisSaas - 04 - Funciones
--
-- Aqui vive el comportamiento. Cada rol puede lo suyo y solo lo suyo, y se
-- comprueba DENTRO de estas funciones, no solo en la pantalla.
--
-- La base no tiene ningun trigger a proposito (E-22): nada ocurre por detras.
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 05_rls_y_funciones.sql

-- ---------------------------------------------------------------------
-- Contexto de empresa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.empresa_actual()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('lis.empresa_id', true), '')::bigint
$$;

COMMENT ON FUNCTION core.empresa_actual() IS
  'La API hace SET LOCAL lis.empresa_id al abrir la transaccion, con el valor que '
  'viene del token. Nunca con un valor que mande el cliente en el body o el query.';

CREATE OR REPLACE FUNCTION core.usuario_actual()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('lis.usuario_id', true), '')::bigint
$$;

-- ---------------------------------------------------------------------
-- LA TERCERA PARED - tres funciones, no una
--
-- RLS contesta "de que empresa". usuario_puede() contesta "que acciones".
-- Faltaba "y esta sesion todavia vale", que en realidad son tres preguntas
-- porque el acceso de una empresa no es un si o un no:
--
--   core.sesion_vigente()     puede ENTRAR
--   core.puede_crear()        puede crear cosas nuevas
--   core.puede_modificar()    puede terminar lo que ya estaba abierto
--
-- POR QUE MIRAN nivel_acceso Y NO estado
--
-- Son dos cosas distintas y estaban confundidas:
--
--   core.estado_empresa   prueba, activa, suspendida, cancelada, cerrada
--                         el HECHO comercial: por que esta asi
--   core.nivel_acceso     completo, solo_cierre, solo_lectura, bloqueado
--                         la CONSECUENCIA: que puede hacer
--
-- El LIS no tiene por que saber si una empresa esta suspendida por mora o
-- cancelada por decision propia. Eso es del lado comercial, que ya lo
-- traduce a un nivel (E-18: "al LIS solo le llegan nivel_acceso y
-- fecha_cierre, ya decididos"). Leer estado aqui era duplicar una decision
-- ya tomada, y una lista a mano que se rompe cada vez que nace un estado.
--
-- El nivel ya trae la respuesta escrita: 'bloqueado -- no se entra'.
--
-- COMO SE REPARTEN EN LAS POLITICAS
--
--   nivel          SELECT   INSERT   UPDATE
--   completo         si       si       si
--   solo_cierre      si       no       si      <- terminar lo abierto
--   solo_lectura     si       no       no
--   bloqueado        no       no       no
--
-- Por eso cada tabla lleva TRES politicas en vez de una: FOR SELECT,
-- FOR INSERT y FOR UPDATE. Es la unica forma de que 'solo_cierre' -- que
-- el enumerado prometia y nadie cumplia -- signifique algo.
-- ---------------------------------------------------------------------

-- El nivel de la empresa de la sesion. SECURITY DEFINER porque lee
-- core.empresa, que tiene RLS: sin esto, la politica de core.empresa
-- llamaria a esta funcion, que leeria core.empresa... hasta reventar la pila.
CREATE OR REPLACE FUNCTION core.nivel_actual()
RETURNS core.nivel_acceso
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $$
  SELECT e.nivel_acceso
  FROM core.empresa e
  WHERE e.empresa_id = core.empresa_actual()
$$;

-- ---------------------------------------------------------------------
-- core.sesion_vigente() - puede ENTRAR
--
-- Lanza en vez de devolver false. Una condicion de FILA debe callar -- un
-- error delataria que la fila existe --, pero esta es de SESION: no hay
-- nada que filtrar, es sobre quien pregunta, y necesita enterarse.
--
-- Va envuelta en (SELECT ...) en las politicas. Sin eso se ejecuta una vez
-- por fila: medido sobre 300.000 filas, 23 ms contra 894.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.sesion_vigente()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $$
DECLARE
  v_usuario core.estado_usuario;
  v_nivel   core.nivel_acceso;
  v_cierre  date;
BEGIN
  SELECT u.estado, e.nivel_acceso, e.fecha_cierre
    INTO v_usuario, v_nivel, v_cierre
  FROM core.usuario u
  JOIN core.empresa e ON e.empresa_id = u.empresa_id
  WHERE u.usuario_id = core.usuario_actual();

  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'Sesion caducada: el usuario ya no existe'
      USING ERRCODE = '28000', HINT = 'volver a entrar';
  END IF;

  IF v_usuario <> 'activo' THEN
    RAISE EXCEPTION 'Sesion caducada: el usuario esta %', v_usuario
      USING ERRCODE = '28000', HINT = 'volver a entrar';
  END IF;

  -- Una sola condicion, y la decide el lado comercial. No hay lista de
  -- estados buenos que mantener.
  IF v_nivel = 'bloqueado' THEN
    RAISE EXCEPTION 'Sesion caducada: el acceso de la empresa esta bloqueado'
      USING ERRCODE = '28000', HINT = 'contactar al operador';
  END IF;

  -- E-20 pedia que el cierre se comprobara y no tenia mecanismo (H-100).
  IF v_cierre IS NOT NULL AND v_cierre <= current_date THEN
    RAISE EXCEPTION 'Sesion caducada: la empresa cerro el %', v_cierre
      USING ERRCODE = '28000', HINT = 'contactar al operador';
  END IF;

  RETURN true;
END
$$;

-- ---------------------------------------------------------------------
-- core.puede_crear() - para el WITH CHECK de los INSERT
--
-- Solo 'completo'. Una empresa en solo_cierre puede terminar lo que tenia
-- abierto, no empezar nada: eso es lo que significa la palabra.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.puede_crear()
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_nivel core.nivel_acceso := core.nivel_actual();
BEGIN
  IF v_nivel = 'completo' THEN RETURN true; END IF;

  RAISE EXCEPTION 'El acceso de la empresa es "%": no se puede crear nada nuevo', v_nivel
    USING ERRCODE = '42501', HINT = 'contactar al operador';
END
$$;

-- ---------------------------------------------------------------------
-- core.puede_modificar() - para el WITH CHECK de los UPDATE
--
-- 'completo' y 'solo_cierre'. Terminar un informe que ya estaba empezado
-- es cerrar, no crear.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.puede_modificar()
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v_nivel core.nivel_acceso := core.nivel_actual();
BEGIN
  IF v_nivel IN ('completo', 'solo_cierre') THEN RETURN true; END IF;

  RAISE EXCEPTION 'El acceso de la empresa es "%": solo lectura', v_nivel
    USING ERRCODE = '42501', HINT = 'contactar al operador';
END
$$;

COMMENT ON FUNCTION core.sesion_vigente() IS
  'Puede entrar: usuario activo y nivel_acceso distinto de bloqueado. Lee el NIVEL, no el estado -- el estado es comercial y el LIS no lo interpreta (E-18). Lanza 28000 porque es condicion de sesion, no de fila.';

COMMENT ON FUNCTION core.puede_crear() IS
  'Para el WITH CHECK de los INSERT. Solo nivel completo.';

COMMENT ON FUNCTION core.puede_modificar() IS
  'Para el WITH CHECK de los UPDATE. Nivel completo o solo_cierre: terminar lo abierto no es crear.';

-- =====================================================================
-- COMO SE ESTRENA UNA CONTRASENA
--
-- El admin nunca conoce la contrasena de nadie (F1-2). Entrega un CODIGO de
-- un solo uso, que sirve para DEFINIR la clave y no para entrar. El mismo
-- mecanismo sirve para el reseteo: un solo camino, que no se olvida de
-- mantener.
--
-- Cuatro funciones, y se parten en dos grupos por una razon:
--
--   CON sesion    crear_usuario, generar_activacion
--                 las llama el admin, RLS activo, se comprueba permiso
--
--   SIN sesion    buscar_activacion, activar_usuario, activacion_fallida
--                 las llama la pantalla de activacion, donde todavia no hay
--                 nadie identificado. Mismo caso que buscar_credencial:
--                 SECURITY DEFINER, acotadas, sin filtros libres.
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.crear_usuario() - nace sin clave; si el empleado esta inactivo,
-- ademas suspendida
--
-- Usa core.rol_es_admin() y core.usuario_puede(), que se definen mas abajo:
-- plpgsql no resuelve los nombres hasta que se ejecuta, asi que el orden del
-- archivo no importa aqui (si importaria en una funcion LANGUAGE sql).
--
-- SECURITY DEFINER porque lis_app no tiene INSERT sobre core.usuario: esta
-- funcion es la unica puerta, y por eso valida a mano todo lo que RLS
-- validaria. Comprueba el permiso con usuario_puede() y no con
-- exigir_permiso(), por H-57.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- core.generar_activacion() - el codigo
--
-- El codigo lo genera y lo hashea la APLICACION; aqui solo llega el hash.
-- Devuelve la fila creada para que el API sepa cuando vence.
--
-- Sirve para las dos cosas: estrenar una cuenta nueva y resetear una vieja.
-- En los dos casos el usuario queda en pendiente_activacion y sin clave, que
-- es lo que hace que haya un solo camino.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- core.buscar_activacion() - SECURITY DEFINER
--
-- La pantalla de activacion no tiene sesion: mismo huevo y gallina que el
-- login. Devuelve el hash para que el API lo verifique con argon2 -- eso no
-- se puede hacer dentro de SQL.
--
-- Acotada igual que buscar_credencial: sin filtros libres, search_path fijo,
-- una fila, y REVOKE de PUBLIC.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.buscar_activacion(
  p_username   text,
  p_empresa_id bigint DEFAULT NULL
) RETURNS TABLE (
  activacion_id bigint,
  usuario_id    bigint,
  empresa_id    bigint,
  codigo_hash   text,
  vence_en      timestamptz,
  intentos_fallidos smallint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_cuantas int;
BEGIN
  SELECT count(*) INTO v_cuantas
  FROM core.usuario u
  WHERE lower(u.username) = lower(p_username)
    AND (p_empresa_id IS NULL OR u.empresa_id = p_empresa_id);

  IF v_cuantas > 1 THEN
    RAISE EXCEPTION
      'El usuario % existe en % empresas: hace falta decir en cual (H-101)',
      p_username, v_cuantas USING ERRCODE = 'cardinality_violation';
  END IF;

  RETURN QUERY
  SELECT a.activacion_id, a.usuario_id, a.empresa_id, a.codigo_hash,
         a.vence_en, a.intentos_fallidos
  FROM core.activacion a
  JOIN core.usuario u ON u.usuario_id = a.usuario_id
  WHERE lower(u.username) = lower(p_username)
    AND (p_empresa_id IS NULL OR u.empresa_id = p_empresa_id)
    AND a.usado_en IS NULL
    AND a.anulado_en IS NULL
    AND a.vence_en > now();
END
$fn$;

-- ---------------------------------------------------------------------
-- core.activacion_fallida() - SECURITY DEFINER
--
-- El codigo no cuadro. Al quinto intento se anula solo: quien lo este
-- adivinando se queda sin objetivo, y el duenno tiene que pedir otro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.activacion_fallida(
  p_activacion_id bigint,
  p_tope          int DEFAULT 5
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  UPDATE core.activacion
     SET intentos_fallidos = intentos_fallidos + 1,
         anulado_en = CASE WHEN intentos_fallidos + 1 >= p_tope
                           THEN now() ELSE anulado_en END,
         anulado_motivo = CASE WHEN intentos_fallidos + 1 >= p_tope
                               THEN 'demasiados intentos' ELSE anulado_motivo END
   WHERE activacion_id = p_activacion_id
     AND usado_en IS NULL AND anulado_en IS NULL;
END
$fn$;

-- ---------------------------------------------------------------------
-- core.login_fallido() - SECURITY DEFINER
--
-- La clave no cuadro. Mismo patron que activacion_fallida(): se cuenta, y
-- al llegar al tope la cuenta se bloquea sola. Es una funcion y no un
-- UPDATE del API porque 'estado' ya no se escribe desde lis_app (ver
-- 05_privilegios.sql): con la columna abierta, cualquier consulta del API
-- podia reactivar a un suspendido. Aqui solo se puede ir en una direccion.
--
-- Pide que la sesion sea la del propio usuario: el API la pone asi antes
-- de llamar (contarFallo), y con eso nadie le bloquea la cuenta a otro
-- desde una sesion ajena.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.login_fallido(
  p_usuario_id bigint,
  p_tope       int DEFAULT 5
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  IF core.usuario_actual() IS DISTINCT FROM p_usuario_id THEN
    RAISE EXCEPTION 'login_fallido: la sesion no es la del usuario' USING ERRCODE = '42501';
  END IF;

  UPDATE core.usuario
     SET intentos_fallidos = intentos_fallidos + 1,
         estado = CASE WHEN intentos_fallidos + 1 >= p_tope
                       THEN 'bloqueado'::core.estado_usuario ELSE estado END
   WHERE usuario_id = p_usuario_id;
END
$fn$;

-- ---------------------------------------------------------------------
-- core.desbloquear_usuario() - SECURITY DEFINER
--
-- La cuenta se bloqueo sola al quinto intento (login_fallido). Volverla a
-- abrir es poner el contador en cero y el estado en activo: la persona
-- entra con la clave de siempre. NO se le genera un codigo, porque eso la
-- obligaria a cambiar de clave cada vez que se equivoca cinco veces, y
-- una clave que se cambia a la fuerza termina en un papel pegado al
-- monitor.
--
-- Solo desde 'bloqueado'. Una cuenta suspendida o pendiente no se
-- "desbloquea": cada estado tiene su camino de vuelta.
--
-- Como generar_activacion(): sesion, permiso, misma empresa, y la cuenta
-- de un administrador solo la toca el propietario (puede_tocar_cuenta).
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- core.cambiar_username() - SECURITY DEFINER
--
-- El nombre con el que entra. lis_app no puede escribir core.usuario, asi
-- que esta es la puerta. Mismas guardias que el resto: sesion, permiso,
-- misma empresa, y la cuenta de un administrador solo la toca el
-- propietario. En minusculas y sin espacios, como lo guarda crear_usuario.
--
-- El formato lo dice aqui con palabras antes de que lo diga el CHECK de la
-- tabla con un "violates check constraint"; el duplicado lo deja pasar al
-- indice uq_usuario_username, que el API ya traduce a "ese nombre de
-- usuario ya existe en la empresa".
--
-- La sesion abierta de esa persona no se cae: el token va por usuario_id.
-- Solo el nombre que ve en el encabezado queda viejo hasta que reentre.
-- ---------------------------------------------------------------------
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

-- =====================================================================
-- EL EMPLEADO Y SU CUENTA SON UNO
--
-- El modulo de empleados ES el de usuarios: la relacion es 1 a 1 y no hay
-- pantalla aparte. Entonces la casilla "Activo" del empleado manda tambien
-- sobre la cuenta: un empleado inactivo no entra al sistema, y punto. Antes
-- no era asi -- se desactivaba al empleado y su cuenta seguia entrando,
-- porque ni buscar_credencial ni la sesion miraban empleado.activo.
--
-- Como se hace: dos funciones (suspender, reactivar) con las guardias de
-- siempre, y un trigger sobre core.empleado.activo que las llama. El
-- trigger y no el API, para que la regla valga la escriba quien la escriba.
-- El operador (postgres) queda fuera del trigger: si toca activo a mano es
-- cirugia, y sabe lo que hace.
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.suspender_usuario() - SECURITY DEFINER
--
-- De cualquier estado a 'suspendido'. La sesion abierta de esa persona
-- muere en la siguiente peticion: sesion_vigente() no deja pasar a nadie
-- que no este activo. La cuenta del propietario no se suspende -- dejaria
-- a la empresa sin nadie con el extra -- y la de un administrador solo la
-- suspende el propietario.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- core.reactivar_usuario() - SECURITY DEFINER
--
-- Solo desde 'suspendido'. Vuelve a 'activo' con su clave de siempre; si
-- nunca estreno clave (password_hash vacio) vuelve a 'pendiente_activacion'
-- y hay que generarle un codigo, como a cualquier cuenta nueva.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- El trigger: empleado.activo manda sobre la cuenta.
--
-- Corre como quien hace el UPDATE. Desde lis_app -- el API -- llama a las
-- funciones de arriba, que comprueban y dejan rastro; si la cuenta no se
-- puede tocar (la de un administrador sin ser el propietario), el UPDATE
-- del empleado entero se rechaza, que es lo que se quiere: no se puede
-- desactivar a un administrador por la puerta de al lado. Desde postgres
-- no hace nada: el operador esta operando.
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- core.activar_usuario() - SECURITY DEFINER
--
-- El codigo ya se verifico en la aplicacion. Aqui se gasta y se estrena la
-- clave, en una sola transaccion: o pasan las tres cosas o no pasa ninguna.
--
-- Devuelve el usuario_id y el empresa_id para que el API pueda firmar el
-- token sin una consulta mas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.activar_usuario(
  p_activacion_id bigint,
  p_clave_hash    text
) RETURNS TABLE (usuario_id bigint, empresa_id bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
DECLARE
  v_usuario bigint;
  v_empresa bigint;
BEGIN
  -- Se gasta el codigo. La condicion es la misma que lo daba por vivo, asi
  -- que dos peticiones simultaneas con el mismo codigo: solo una gana.
  UPDATE core.activacion
     SET usado_en = now()
   WHERE activacion_id = p_activacion_id
     AND usado_en IS NULL AND anulado_en IS NULL AND vence_en > now()
  RETURNING core.activacion.usuario_id, core.activacion.empresa_id
       INTO v_usuario, v_empresa;

  IF v_usuario IS NULL THEN
    RAISE EXCEPTION 'El codigo ya se uso, se anulo o vencio'
      USING ERRCODE = '28000', HINT = 'pedir otro al administrador';
  END IF;

  IF length(p_clave_hash) < 20 THEN
    RAISE EXCEPTION 'La clave llego sin hashear'
      USING ERRCODE = '22023';
  END IF;

  UPDATE core.usuario
     SET password_hash = p_clave_hash,
         estado = 'activo',
         intentos_fallidos = 0
   WHERE core.usuario.usuario_id = v_usuario;

  RETURN QUERY SELECT v_usuario, v_empresa;
END
$fn$;


COMMENT ON FUNCTION core.usuario_actual() IS
  'Igual que empresa_actual: la API hace SET LOCAL lis.usuario_id con el valor del '
  'token. Sin esto, las comprobaciones de permiso no tienen a quien comprobar.';

-- ---------------------------------------------------------------------
-- Permisos - quien puede hacer que, y DONDE
-- ---------------------------------------------------------------------

-- Lo que un usuario puede hacer es la INTERSECCION de dos cosas:
--
--   ROL      lo que el administrador le dio        core.rol_permiso
--   LICENCIA lo que el operador le vendio a la sede plataforma.modulo_sucursal
--
-- Separadas a proposito. El rol dice QUE SABE HACER la persona; la licencia
-- dice DONDE VALE eso. Meter la sede dentro del permiso haria explotar el
-- catalogo: un orden.crear_en_central y un orden.crear_en_norte por cada sede.
--
-- Y por eso apagar un modulo no borra nada: rol_permiso guarda la intencion y
-- sobrevive; cuando el cliente vuelve a pagar, el acceso vuelve solo.
--
-- UNA SOLA REGLA, UNA SOLA FUNCION (2026-09-23)
--
-- Antes habia dos: la "floja" (el modulo encendido en ALGUNA sede) y la
-- "estricta" (encendido en la sede del contexto), y cada sitio elegia. El
-- front preguntaba por sede y el API por empresa, y eso es exactamente la
-- clase de diferencia que un dia se convierte en un hueco. Ahora hay una:
--
--   el rol del usuario tiene el permiso           core.rol_permiso
--   y el modulo del permiso esta ENCENDIDO        plataforma.modulo_sucursal
--   EN LA SEDE DONDE ESTA PARADO                  core.sucursal_actual()
--
-- Sin sede en el contexto la respuesta es FALSE, siempre. Las politicas RLS
-- de las tablas operativas dependen de esto: si cayera a "encendido en
-- alguna sede", una consulta sin sede veria mas de lo que debe. La API exige
-- la sede en toda ruta que no sea de entrar, y el script del operador la
-- pone antes de llamar.
--
-- Como llega el permiso hasta aqui:
--
--   sede del contexto  ->  plataforma.modulo_sucursal  ->  que modulos tiene
--   modulos            ->  plataforma.permiso          ->  que permisos existen ahi
--   rol del usuario    ->  core.rol_permiso            ->  cuales tiene el rol
--
-- Son invoker y NO SECURITY DEFINER a proposito: asi RLS las sigue
-- recortando a la empresa de la sesion y nadie puede preguntar por un usuario
-- ajeno. Fallan cerrado: sin usuario, usuario no activo, sin sede, o fila
-- que RLS esconde -> false. Nunca true por omision.

CREATE OR REPLACE FUNCTION core.sucursal_actual()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('lis.sucursal_id', true), '')::bigint
$$;

COMMENT ON FUNCTION core.sucursal_actual() IS
  'La sede donde esta parado quien llama, puesta por la API desde el token. NULL '
  'entre el login y elegir sede.';

-- La base. Cualquiera de la lista, para el usuario dado (o el de la sesion),
-- en la sede del contexto. Una sola consulta, no una por permiso: es lo que
-- necesitan las politicas de UPDATE, donde una tabla admite varias acciones.
CREATE OR REPLACE FUNCTION core.usuario_puede_alguno(
  p_permisos   text[],
  p_usuario_id bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT core.sucursal_actual() IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM core.usuario u
       JOIN core.rol_permiso rp ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
       JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
       JOIN plataforma.modulo_sucursal ms
         ON ms.modulo_id   = p.modulo_id
        AND ms.empresa_id  = u.empresa_id
        AND ms.sucursal_id = core.sucursal_actual()
        AND ms.activo
       WHERE u.usuario_id = coalesce(p_usuario_id, core.usuario_actual())
         AND u.estado = 'activo'
         AND rp.permiso_id = ANY (p_permisos)
     )
$$;

COMMENT ON FUNCTION core.usuario_puede_alguno IS
  'true si el usuario tiene AL MENOS UNO de los permisos y su modulo esta encendido '
  'en la sede del contexto. Sin sede devuelve false. Es la base de usuario_puede().';

-- La de todos los dias: un permiso.
CREATE OR REPLACE FUNCTION core.usuario_puede(
  p_permiso_id text,
  p_usuario_id bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT core.usuario_puede_alguno(ARRAY[p_permiso_id], p_usuario_id)
$$;

COMMENT ON FUNCTION core.usuario_puede IS
  'LA comprobacion de permiso: el rol lo tiene Y el modulo esta encendido en la sede '
  'del contexto. Sin sede devuelve false. La usan las politicas RLS, las funciones '
  'y el API; el front pregunta lo mismo con los permisos por sede de la sesion.';

-- La que lanza, para adentro de las funciones.
CREATE OR REPLACE FUNCTION core.exigir_permiso(
  p_permiso_id text,
  p_usuario_id bigint DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  -- Escape para carga inicial y mantenimiento: la API SIEMPRE se conecta como
  -- lis_app, asi que en produccion esta rama nunca se toma. Si algun dia la API
  -- se conecta con otro rol, las comprobaciones de permiso desaparecen: es un
  -- requisito de despliegue, igual que el SET LOCAL lis.empresa_id.
  --
  -- Y por esta rama las funciones SECURITY DEFINER NO usan exigir_permiso():
  -- adentro de una, current_user es el duenno (postgres) y esto devolveria sin
  -- comprobar nada (H-57). Ellas llaman a usuario_puede() directo.
  IF current_user <> 'lis_app' THEN
    RETURN;
  END IF;

  IF core.sucursal_actual() IS NULL THEN
    RAISE EXCEPTION 'Hace falta elegir una sede antes de esta operacion'
      USING ERRCODE = 'insufficient_privilege', HINT = 'POST /auth/sucursal';
  END IF;

  IF NOT core.usuario_puede(p_permiso_id, p_usuario_id) THEN
    RAISE EXCEPTION 'El usuario no tiene el permiso % en esta sede', p_permiso_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

COMMENT ON FUNCTION core.exigir_permiso IS
  'Ultima linea de defensa, no la primera. La API debe comprobar el permiso antes '
  'de llegar aqui para dar un mensaje decente; esto atrapa el endpoint nuevo que '
  'alguien escribio sin acordarse.';

-- Lo que la pantalla de "crear rol" tiene derecho a mostrarle al administrador.
-- Sin sucursal devuelve la union de lo que la empresa tenga en alguna sede,
-- porque el rol es de la empresa y el modulo es de la sede.
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

COMMENT ON FUNCTION core.permisos_disponibles IS
  'El menu del administrador. Filtrar la lista en pantalla es una comodidad, no '
  'una proteccion: quien la escribe de verdad es asignar_permisos_a_rol().';

-- =====================================================================
-- QUIEN ADMINISTRA A LOS QUE ADMINISTRAN
--
-- Dos clases de cuenta que hay que distinguir:
--
--   PROPIETARIO   la cuenta que el OPERADOR crea al dar de alta la empresa.
--                 Su rol es es_sistema: no se le cambia a nadie, no se
--                 asigna a nadie mas y sus permisos no se editan. Trae un
--                 permiso extra, usuario.nombrar_admin, que es la unica
--                 diferencia con un administrador.
--
--   ADMINISTRADOR cualquier rol que tenga usuario.administrar -- o sea,
--                 cualquiera que pueda crear usuarios. Los nombra el
--                 propietario y solo el los toca: cambiarles el rol,
--                 resetearles el codigo, moverles las sedes.
--
-- La regla, en una frase: todo lo que toque QUIEN ADMINISTRA es del
-- propietario. Vive en tres puertas (crear_usuario, cambiar_rol,
-- asignar_permisos_a_rol), en generar_activacion y en la politica de
-- acceso_sucursal. El API la repite para contestar bonito, pero la pared
-- esta aqui.
--
-- Por que un permiso y no solo la columna es_sistema: asi la diferencia
-- entre los dos roles queda en rol_permiso como todo lo demas, la sesion
-- la trae sola y la pantalla de permisos la muestra sin un caso aparte.
-- =====================================================================

-- ---------------------------------------------------------------------
-- core.rol_es_admin() - el rol puede crear usuarios
--
-- rol_id es identidad global, asi que no hace falta la empresa para que la
-- pregunta sea univoca. STABLE y sin DEFINER: desde lis_app la ve RLS y
-- desde una DEFINER la ve postgres; en los dos casos contesta lo mismo.
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

-- ---------------------------------------------------------------------
-- core.puede_tocar_cuenta() - quien llama puede modificar ESA cuenta
--
-- Una cuenta corriente la toca cualquiera con usuario.administrar. Una de
-- clase administrador (o la del propietario) solo quien tiene el extra.
-- Es lo que usa la politica de acceso_sucursal y lo que el API pregunta
-- antes para dar un 403 que se entienda.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.puede_tocar_cuenta(p_usuario_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
           WHEN NOT core.usuario_puede('usuario.administrar') THEN false
           WHEN EXISTS (SELECT 1
                          FROM core.usuario u
                          JOIN core.rol r ON r.rol_id = u.rol_id
                         WHERE u.usuario_id = p_usuario_id
                           AND (r.es_sistema OR core.rol_es_admin(r.rol_id)))
                THEN core.usuario_puede('usuario.nombrar_admin')
           ELSE true
         END
$$;

COMMENT ON FUNCTION core.puede_tocar_cuenta IS
  'usuario.administrar alcanza para una cuenta corriente; para la de un administrador '
  'o la del propietario hace falta ademas usuario.nombrar_admin. Falla cerrado.';

-- ---------------------------------------------------------------------
-- core.puede_tocar_ficha() - la FICHA sigue a la cuenta
--
-- Nombre, cargo, correo, telefono: parecen datos inocentes, pero el correo
-- y el telefono son (o van a ser) el camino por donde llega un codigo para
-- restablecer la clave. Quien puede cambiarle el correo a alguien puede
-- quedarse con su cuenta el dia que la clave se restablezca por correo. Por
-- eso la ficha se edita con la misma regla que la cuenta
-- (puede_tocar_cuenta): la del propietario, solo el propietario; la de un
-- administrador, solo el propietario; las demas, quien administre. Un
-- empleado sin cuenta (de antes de que fuera obligatoria) lo edita quien
-- administre.
--
-- Lee core.usuario y no core.empleado a proposito: la llama la politica de
-- core.empleado, y una politica que consulta su propia tabla es recursion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.puede_tocar_ficha(p_empleado_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT CASE
           WHEN NOT core.usuario_puede('usuario.administrar') THEN false
           ELSE coalesce((SELECT core.puede_tocar_cuenta(u.usuario_id)
                            FROM core.usuario u
                           WHERE u.empleado_id = p_empleado_id
                             AND u.empresa_id  = core.empresa_actual()), true)
         END
$$;

COMMENT ON FUNCTION core.puede_tocar_ficha IS
  'La ficha (nombre, cargo, correo, telefono...) se edita con la misma regla que la '
  'cuenta: la del propietario solo el propietario, la de un administrador solo el '
  'propietario, las demas quien administre. Lo aplica rls_empleado_editar.';

-- ---------------------------------------------------------------------
-- core.cambiar_rol() - la UNICA forma de escribir usuario.rol_id
--
-- SECURITY DEFINER porque lis_app ya no tiene UPDATE sobre rol_id (ver
-- 05_privilegios.sql): igual que crear_usuario, esta funcion es la puerta y
-- por eso valida a mano todo lo que RLS validaba solo.
--
-- Lo que rechaza, en orden:
--   1. sin sesion
--   2. sin usuario.administrar
--   3. el usuario no es de la empresa (o no existe: misma respuesta)
--   4. el usuario tiene el rol del propietario -- no se cambia
--   5. el rol nuevo es el del propietario -- no se asigna, se traspasa
--      (y traspasar es del operador, no del LIS)
--   6. el rol actual o el nuevo es de administrador y quien llama no tiene
--      usuario.nombrar_admin
--
-- Que el rol nuevo le SIRVA en sus sedes (modulos encendidos) lo comprueba
-- el API antes de llamar, con la misma regla que al crear.
-- ---------------------------------------------------------------------
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

COMMENT ON FUNCTION core.cambiar_rol IS
  'La unica forma de escribir usuario.rol_id. El rol del propietario ni se cambia ni '
  'se asigna; nombrar o retirar administradores exige usuario.nombrar_admin. '
  'Devuelve false si el rol ya era ese. Deja el cambio y el motivo en audit.evento.';

-- ---------------------------------------------------------------------
-- La unica puerta para cambiar los permisos de un rol
--
-- Reemplaza el conjunto entero: lo que no venga en el arreglo se quita. Es lo
-- que le sirve a una pantalla de casillas -- el admin marca, desmarca y
-- guarda -- pero significa que un arreglo incompleto quita permisos.
--
-- Tres comprobaciones antes de tocar nada:
--   a. quien llama administra usuarios
--   b. el rol es de su empresa
--   c. cada permiso pertenece a un modulo que la empresa tiene encendido
--
-- La (c) es la que el administrador ya ve filtrada en pantalla. Pero filtrar
-- la lista es una comodidad, no una proteccion: la pantalla le habla a una API
-- y la API le habla a la tabla. Con INSERT abierto, cualquiera se saltaba la
-- pantalla. Por eso la regla vive aqui y rol_permiso quedo en solo lectura.
--
-- Usa core.usuario_puede() y NO core.exigir_permiso(): dentro de un
-- SECURITY DEFINER de postgres, current_user deja de ser lis_app y
-- exigir_permiso se va por su escape sin comprobar nada (H-57).
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- EL MODULO DE ROLES: crear, editar, desactivar, reactivar
--
-- core.rol quedo cerrada para lis_app (05_privilegios.sql): estas cuatro
-- funciones son la unica forma de escribirla, y por eso repiten a mano lo
-- que RLS validaria (sesion, empresa) y las reglas de arriba: fijo, de
-- administrador, el rol propio. Cada una deja su evento.
-- ---------------------------------------------------------------------

-- Lo que exigen las cuatro, en un solo lugar. Devuelve la fila del rol.
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

-- Desactivar es "ya no se asigna". Se niega si alguien lo tiene puesto: primero
-- se les cambia el rol. Asi nunca existe una sesion con rol desactivado y ni
-- el login ni usuario_puede() necesitan un caso aparte. 55006 (object_in_use)
-- es el SQLSTATE que el API vuelve 409.
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

-- Ya no hay excepcion. rls_derivacion era la unica politica del sistema que
-- comparaba dos empresa_id, y se fue con audit.derivacion: core.mensaje tiene
-- una fila de cada lado y le toca la politica normal del bucle de arriba.
-- Lo que cruza de una empresa a otra ahora lo escribe una funcion, que es codigo
-- que se lee y se prueba, y no una politica que dispara cualquier consulta.


-- ---------------------------------------------------------------------
-- Identidad
-- ---------------------------------------------------------------------
-- Las funciones que vinculan un paciente con el registro de identidad
-- viven en 07_identidad.sql, porque necesitan core.empresa para registrar
-- los conflictos. Aqui solo queda revocado el acceso directo a la tabla:
-- la identidad se resuelve por funcion, nunca por SELECT.


-- ---------------------------------------------------------------------
-- Correlativos
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.siguiente_correlativo(
  p_empresa_id  bigint,
  p_sucursal_id bigint,
  p_tipo        core.tipo_correlativo
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_prefijo text;
  v_ancho   smallint;
  v_valor   bigint;
BEGIN
  -- UPDATE ... RETURNING toma el candado de la fila: dos recepciones
  -- simultaneas nunca obtienen el mismo numero.
  UPDATE core.correlativo
     SET ultimo_valor = ultimo_valor + 1
   WHERE empresa_id = p_empresa_id
     AND tipo       = p_tipo
     AND coalesce(sucursal_id, 0) = coalesce(p_sucursal_id, 0)
  RETURNING prefijo, ancho, ultimo_valor
       INTO v_prefijo, v_ancho, v_valor;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'No hay correlativo configurado para empresa % tipo % sucursal %',
      p_empresa_id, p_tipo, p_sucursal_id;
  END IF;

  RETURN v_prefijo || lpad(v_valor::text, v_ancho, '0');
END $$;

-- ---------------------------------------------------------------------
-- Fusion de pacientes duplicados
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.fusionar_paciente(
  p_duplicado_id bigint,
  p_ganador_id   bigint,
  p_usuario_id   bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_empresa_id bigint := core.empresa_actual();
BEGIN
  PERFORM core.exigir_permiso('paciente.fusionar', p_usuario_id);

  IF p_duplicado_id = p_ganador_id THEN
    RAISE EXCEPTION 'Un paciente no se fusiona consigo mismo';
  END IF;

  IF EXISTS (SELECT 1 FROM core.paciente
              WHERE paciente_id = p_ganador_id
                AND fusionado_en_paciente_id IS NOT NULL) THEN
    RAISE EXCEPTION 'El paciente ganador ya fue fusionado en otro; usa ese';
  END IF;

  UPDATE core.paciente
     SET fusionado_en_paciente_id = p_ganador_id,
         fusionado_en             = now(),
         fusionado_por_usuario_id = p_usuario_id
   WHERE paciente_id = p_duplicado_id
     AND fusionado_en_paciente_id IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El paciente % no existe o ya estaba fusionado', p_duplicado_id;
  END IF;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_despues
  ) VALUES (
    v_empresa_id, p_usuario_id, 'paciente.fusionar', 'core', 'paciente',
    p_duplicado_id, jsonb_build_object('fusionado_en_paciente_id', p_ganador_id)
  );
END $$;

COMMENT ON FUNCTION core.fusionar_paciente IS
  'No mueve ni una orden. El duplicado queda apuntando al ganador y las ordenes '
  'viejas siguen apuntando al duplicado; la lectura sigue el puntero. Asi la fusion '
  'es reversible y no reescribe historia clinica.';


-- ---------------------------------------------------------- 07_identidad.sql

-- =====================================================================
-- ProLisSaas - 07 - El paciente y su identidad LOCAL
--
-- Este archivo cambio de tema por completo.
--
-- ANTES resolvia identidad COMPARTIDA: plataforma.persona guardaba el
-- documento del paciente una sola vez para todo el despliegue, y las empresas
-- se colgaban de esa fila para saber que atendian al mismo senor. Traia
-- conflicto_identidad, vincular_persona(), vincular_paciente_identidad() y un
-- veredicto con cuatro valores.
--
-- Todo eso se retiro. El modelo decidido no comparte NADA entre empresas: cada
-- una anota en su propia ficha como la llama la otra
-- (core.paciente_referencia, en 03_core.sql), y el que tiene los datos es el
-- que coteja, fallando cerrado cuando duda.
--
-- Lo que queda aqui es identidad DENTRO de una empresa:
--   * registrar un paciente sin dejar entrar un documento repetido
--   * buscar posibles duplicados antes de crear uno
--   * anotar y anular la referencia externa, que nace de una confirmacion
--     humana con el paciente presente
--
-- Ver documentacion/flujos/06-el-paciente-entre-dos-empresas.md y H-73.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Registrar un paciente
--
-- Es el unico camino para crear uno. Garantiza dos cosas: que el expediente
-- se llena con lo que recepcion escribio y nunca con datos traidos de otra
-- empresa, y que un documento repetido dentro de la MISMA empresa no crea un
-- segundo expediente.
--
-- Ya no intenta vincular con ningun registro global, porque no existe.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.registrar_paciente(
  p_empresa_id       bigint,
  p_nombres          text,
  p_apellidos        text,
  p_tipo_documento   plataforma.tipo_documento,
  p_documento        text,
  p_fecha_nacimiento date,
  p_sexo             plataforma.sexo,
  p_telefono         text DEFAULT NULL,
  p_correo           text DEFAULT NULL,
  p_direccion        text DEFAULT NULL,
  p_usuario_id       bigint DEFAULT NULL
)
RETURNS TABLE (
  paciente_id bigint,
  expediente  text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_expediente text;
  v_paciente   bigint;
  v_existente  text;
BEGIN
  PERFORM core.exigir_permiso('paciente.crear', p_usuario_id);

  -- Un documento mal tecleado que ya existe aqui se atrapa ahora. Entre
  -- empresas no hay nada que atrapar: los expedientes son independientes.
  IF coalesce(p_tipo_documento,'ninguno') <> 'ninguno'
     AND btrim(coalesce(p_documento,'')) <> '' THEN
    SELECT pa.expediente INTO v_existente
    FROM core.paciente pa
    WHERE pa.empresa_id     = p_empresa_id
      AND pa.tipo_documento = p_tipo_documento
      AND pa.documento      = btrim(p_documento)
      AND pa.fusionado_en_paciente_id IS NULL;

    IF FOUND THEN
      RAISE EXCEPTION
        'Ese documento ya esta registrado en el expediente %. Abre ese expediente '
        'en vez de crear uno nuevo; si de verdad es otra persona, revisa el numero.',
        v_existente
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  v_expediente := core.siguiente_correlativo(p_empresa_id, NULL, 'expediente');

  INSERT INTO core.paciente (
    empresa_id, expediente,
    nombres, apellidos, tipo_documento, documento,
    fecha_nacimiento, sexo, telefono, correo, direccion,
    creado_por_usuario_id
  ) VALUES (
    p_empresa_id, v_expediente,
    btrim(p_nombres), btrim(p_apellidos),
    coalesce(p_tipo_documento,'ninguno'),
    CASE WHEN coalesce(p_tipo_documento,'ninguno') = 'ninguno'
         THEN NULL ELSE btrim(p_documento) END,
    p_fecha_nacimiento, coalesce(p_sexo,'no_especificado'),
    p_telefono, p_correo, p_direccion,
    p_usuario_id
  )
  RETURNING core.paciente.paciente_id INTO v_paciente;

  RETURN QUERY SELECT v_paciente, v_expediente;
END $$;

COMMENT ON FUNCTION core.registrar_paciente IS
  'El unico camino para crear un paciente. El expediente se llena con lo que '
  'recepcion escribio y con nada mas: ningun dato entra desde otra empresa.';

-- ---------------------------------------------------------------------
-- Anotar la referencia externa
--
-- La pieza que reemplaza a toda la identidad compartida. Nace de una
-- CONFIRMACION HUMANA con el paciente presente, o de un cotejo de dos factores
-- que el sistema pudo resolver sin dudar. Nunca de elegir en una lista (F6-2).
--
-- Por eso el usuario que confirma es obligatorio: si nadie confirmo, no hay
-- referencia. Fallar cerrado es la respuesta correcta.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.anotar_referencia(
  p_empresa_id             bigint,
  p_paciente_id            bigint,
  p_contraparte_empresa_id bigint,
  p_expediente_externo     text,
  p_usuario_id             bigint,
  p_nota                   text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_referencia bigint;
BEGIN
  PERFORM core.exigir_permiso('paciente.editar', p_usuario_id);

  IF btrim(coalesce(p_expediente_externo,'')) = '' THEN
    RAISE EXCEPTION 'La referencia externa no puede ir vacia';
  END IF;

  -- Solo se anota hacia una empresa con la que hay una ruta vigente. Sin
  -- enlace no hay con quien intercambiar, asi que la referencia no tendria
  -- para que existir.
  --
  -- Se pregunta por core.mis_enlaces() y no leyendo plataforma.enlace: esa
  -- tabla no es de ninguna de las dos empresas y lis_app no tiene un solo
  -- privilegio sobre ella. Solo DOS funciones la tocan en todo el sistema --
  -- mis_enlaces() para contestar tu lado y entregar() para rutear-- y todo lo
  -- demas pasa por ellas. Si aparece una tercera, algo se torcio.
  IF NOT EXISTS (
    SELECT 1 FROM core.mis_enlaces(p_empresa_id) e
    WHERE e.contraparte_empresa_id = p_contraparte_empresa_id
  ) THEN
    RAISE EXCEPTION
      'No hay ninguna ruta vigente con esa empresa: no se puede anotar una '
      'referencia hacia alguien con quien no se trabaja';
  END IF;

  INSERT INTO core.paciente_referencia (
    empresa_id, paciente_id, contraparte_empresa_id,
    expediente_externo, confirmado_por_usuario_id, nota
  ) VALUES (
    p_empresa_id, p_paciente_id, p_contraparte_empresa_id,
    btrim(p_expediente_externo), p_usuario_id, p_nota
  )
  RETURNING referencia_id INTO v_referencia;

  RETURN v_referencia;
END $$;

COMMENT ON FUNCTION core.anotar_referencia IS
  'Nace de una confirmacion humana con el paciente presente. El usuario que '
  'confirma es obligatorio a proposito: sin el, no hay referencia.';

-- ---------------------------------------------------------------------
-- Anular una referencia mal confirmada
--
-- Alguien confirmo al paciente equivocado en la ventanilla. El dano existe,
-- pero es LOCAL: la empresa que la escribio la anula y nadie mas se entera.
-- Comparalo con una identidad compartida, donde el mismo error lo heredaban
-- las dos y habia que negociarlo.
--
-- No se borra ni se edita: se anula con motivo y se escribe otra. Que alguien
-- haya confundido dos pacientes es justo lo que hay que poder auditar despues.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.anular_referencia(
  p_referencia_id bigint,
  p_motivo        text,
  p_usuario_id    bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM core.exigir_permiso('paciente.editar', p_usuario_id);

  IF btrim(coalesce(p_motivo,'')) = '' THEN
    RAISE EXCEPTION 'Anular una referencia exige un motivo';
  END IF;

  UPDATE core.paciente_referencia
     SET anulada_en = now(), anulado_motivo = btrim(p_motivo)
   WHERE referencia_id = p_referencia_id
     AND anulada_en IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa referencia no existe o ya estaba anulada';
  END IF;
END $$;

-- (unaccent_simple vive en 01_tipos.sql, con las llaves de unicidad: los
-- indices de 03 la necesitan antes de que este archivo cargue.)

-- ---------------------------------------------------------------------
-- Posibles duplicados DENTRO de la misma empresa
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.posibles_duplicados(
  p_empresa_id       bigint,
  p_apellidos        text,
  p_nombres          text,
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
           WHEN p.fecha_nacimiento = p_fecha_nacimiento THEN 'apellidos y fecha exacta'
           ELSE 'apellidos y ano de nacimiento'
         END
  FROM core.paciente p
  WHERE p.empresa_id = p_empresa_id
    AND p.fusionado_en_paciente_id IS NULL
    AND upper(public.unaccent_simple(p.apellidos)) = upper(public.unaccent_simple(p_apellidos))
    AND (
      p.fecha_nacimiento = p_fecha_nacimiento
      OR extract(year from p.fecha_nacimiento) = extract(year from p_fecha_nacimiento)
    )
  ORDER BY (p.fecha_nacimiento = p_fecha_nacimiento) DESC, p.creado_en DESC
  LIMIT 20
$$;

COMMENT ON FUNCTION core.posibles_duplicados IS
  'Se llama ANTES de crear un paciente, y busca solo dentro de la MISMA empresa: '
  'nunca muestra pacientes de otra. Es la defensa contra el duplicado que se crea '
  'porque el paciente ya venia registrado y nadie lo busco.';


-- ---------------------------------------------------------- 08_enlace_y_mensaje.sql

-- =====================================================================
-- ProLisSaas - 08 - El enlace y el mensaje - lo unico que cruza
--
-- Las tablas estan en 03_core.sql, porque tienen que existir antes de que el
-- bucle de RLS de 05 les ponga politica. Aqui van las funciones.
--
-- LA IDEA. Antes, que un dato cruzara de una empresa a otra dependia de una
-- politica de RLS -- rls_derivacion, la unica del sistema que comparaba dos
-- empresa_id -- y una politica la dispara cualquier consulta desde cualquier
-- parte. Ahora depende de core.entregar(), que es el UNICO punto del sistema
-- donde eso pasa: codigo que se lee, se prueba y se audita.
--
-- SOBRE exigir_permiso. Estas funciones son SECURITY DEFINER porque tienen que
-- escribir la fila del destinatario, y core.exigir_permiso() NO SIRVE ahi
-- dentro: su escape comprueba current_user, que dentro de una funcion definida
-- por postgres vale 'postgres' y no 'lis_app', asi que la comprobacion se salta
-- siempre (H-57). Por eso aqui se llama a core.usuario_puede() directo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Crear una ruta - SOLO EL OPERADOR
--
-- Ningun cliente llama a esto. Para declararla tendria que teclear el RTN y el
-- codigo de sede del otro, que es informacion confidencial y no es suya.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION plataforma.crear_enlace(
  p_sucursal_a_id bigint,
  p_sucursal_b_id bigint,
  p_creado_por    text,
  p_nota          text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_empresa_a bigint;
  v_empresa_b bigint;
  v_enlace    bigint;
BEGIN
  SELECT empresa_id INTO v_empresa_a FROM core.sucursal WHERE sucursal_id = p_sucursal_a_id;
  SELECT empresa_id INTO v_empresa_b FROM core.sucursal WHERE sucursal_id = p_sucursal_b_id;

  IF v_empresa_a IS NULL OR v_empresa_b IS NULL THEN
    RAISE EXCEPTION 'Alguna de las dos sucursales no existe';
  END IF;
  IF v_empresa_a = v_empresa_b THEN
    RAISE EXCEPTION
      'Las dos sedes son de la misma empresa. Entre sedes propias se comparte '
      'todo y no hace falta enlace: eso no es un problema que resolver, es una '
      'sola empresa';
  END IF;

  INSERT INTO plataforma.enlace (
    empresa_a_id, sucursal_a_id, empresa_b_id, sucursal_b_id, creado_por, nota
  ) VALUES (
    v_empresa_a, p_sucursal_a_id, v_empresa_b, p_sucursal_b_id, p_creado_por, p_nota
  )
  RETURNING enlace_id INTO v_enlace;

  RETURN v_enlace;
END $$;

COMMENT ON FUNCTION plataforma.crear_enlace IS
  'La crea el operador con una conexion privilegiada. Cada pareja de sedes es '
  'una operacion manual suya: con un cliente es lo mismo que ya hace con '
  'crear_empresa, y con veinte se vuelve trabajo repetitivo (H-89).';

-- ---------------------------------------------------------------------
-- Mis enlaces - lo unico que una empresa ve de sus rutas
--
-- Contesta SOLO tu lado: con quien podes trabajar y desde cual de TUS sedes.
-- La sucursal del otro no se devuelve nunca, y no hace falta: cuando mandas,
-- entregar() resuelve el destino.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.mis_enlaces(p_empresa_id bigint DEFAULT NULL)
RETURNS TABLE (
  enlace_id              bigint,
  mi_sucursal_id         bigint,
  contraparte_empresa_id bigint,
  contraparte_nombre     text,
  vigente_desde          date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT e.enlace_id,
         CASE WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
              THEN e.sucursal_a_id ELSE e.sucursal_b_id END,
         CASE WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
              THEN e.empresa_b_id  ELSE e.empresa_a_id  END,
         (SELECT coalesce(o.nombre_comercial, o.nombre) FROM core.empresa o
           WHERE o.empresa_id = CASE
                 WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
                 THEN e.empresa_b_id ELSE e.empresa_a_id END),
         e.vigente_desde
  FROM plataforma.enlace e
  WHERE coalesce(p_empresa_id, core.empresa_actual()) IN (e.empresa_a_id, e.empresa_b_id)
    AND e.vigente_desde <= CURRENT_DATE
    AND (e.vigente_hasta IS NULL OR e.vigente_hasta > CURRENT_DATE)
  ORDER BY 4
$$;

COMMENT ON FUNCTION core.mis_enlaces IS
  'El nombre comercial de la contraparte SI se muestra: las dos empresas ya saben '
  'que trabajan juntas, el operador creo la ruta porque lo acordaron. Lo que no '
  'se devuelve nunca es la sucursal del otro.';

-- ---------------------------------------------------------------------
-- Entregar - EL UNICO PUNTO DONDE UN DATO CRUZA DE EMPRESA
--
-- Escribe DOS filas: la mia como 'enviado', la suya como 'recibido'. Las dos
-- llevan el mismo folio, que es un uuid y no el mensaje_id: si viajara el
-- numero de secuencia, el mensaje 4821 le contaria al otro cuantos mandas.
--
-- Un mensaje NO SE ACEPTA, SE RECIBE. La aceptacion se mudo una sola vez a la
-- relacion: una boleta que llega es trabajo, no una propuesta.
--
-- Sin enlace vigente NO SALE. Falla en el origen, cerca de quien se equivoco,
-- en vez de salir y caer en una bandeja del otro lado.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.entregar(
  p_empresa_id       bigint,
  p_enlace_id        bigint,
  p_tipo             core.tipo_mensaje,
  p_contenido        jsonb,
  p_usuario_id       bigint,
  p_responde_a_folio uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  e            plataforma.enlace%ROWTYPE;
  v_mi_suc     bigint;
  v_su_empresa bigint;
  v_su_suc     bigint;
  v_folio      uuid := gen_random_uuid();
BEGIN
  IF NOT core.usuario_puede('derivacion.solicitar', p_usuario_id) THEN
    RAISE EXCEPTION 'El usuario no tiene el permiso derivacion.solicitar'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO e FROM plataforma.enlace
   WHERE enlace_id = p_enlace_id
     AND vigente_desde <= CURRENT_DATE
     AND (vigente_hasta IS NULL OR vigente_hasta > CURRENT_DATE);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay ninguna ruta vigente con ese enlace: el mensaje no sale';
  END IF;

  IF p_empresa_id = e.empresa_a_id THEN
    v_mi_suc := e.sucursal_a_id; v_su_empresa := e.empresa_b_id; v_su_suc := e.sucursal_b_id;
  ELSIF p_empresa_id = e.empresa_b_id THEN
    v_mi_suc := e.sucursal_b_id; v_su_empresa := e.empresa_a_id; v_su_suc := e.sucursal_a_id;
  ELSE
    RAISE EXCEPTION 'Esa ruta no es de esta empresa';
  END IF;

  -- Mi fila: lo que mande.
  INSERT INTO core.mensaje (
    empresa_id, enlace_id, sucursal_id, direccion, tipo,
    folio, responde_a_folio, contenido, estado, entregado_en
  ) VALUES (
    p_empresa_id, p_enlace_id, v_mi_suc, 'enviado', p_tipo,
    v_folio, p_responde_a_folio, p_contenido, 'entregado', now()
  );

  -- Su fila: lo que le llego. Mismo folio, su empresa, SU ventanilla.
  INSERT INTO core.mensaje (
    empresa_id, enlace_id, sucursal_id, direccion, tipo,
    folio, responde_a_folio, contenido, estado
  ) VALUES (
    v_su_empresa, p_enlace_id, v_su_suc, 'recibido', p_tipo,
    v_folio, p_responde_a_folio, p_contenido, 'recibido'
  );

  RETURN v_folio;
END $$;

COMMENT ON FUNCTION core.entregar IS
  'El unico punto del sistema donde un dato pasa de una empresa a otra. Antes eso '
  'era una politica de RLS, que cualquier consulta disparaba; ahora es codigo que '
  'se lee y se prueba. Si alguna vez hay un segundo punto, algo se rompio.';


-- ---------------------------------------------------------- 14_lab_rls_y_funciones.sql

-- Sin marcas de tiempo, igual que en el nucleo: las columnas actualizado_en de
-- lab.prueba, lab.orden y lab.muestra se fueron con sus triggers (H-96).


-- ---------------------------------------------------------------------
-- Que rango aplica - lo mas especifico gana
-- ---------------------------------------------------------------------
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

CREATE OR REPLACE FUNCTION lab.bandera_para(
  p_valor numeric, p_min numeric, p_max numeric,
  p_critico_min numeric, p_critico_max numeric
)
RETURNS lab.bandera
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_valor IS NULL                                   THEN 'normal'::lab.bandera
    WHEN p_critico_min IS NOT NULL AND p_valor < p_critico_min THEN 'critico_bajo'
    WHEN p_critico_max IS NOT NULL AND p_valor > p_critico_max THEN 'critico_alto'
    WHEN p_min IS NOT NULL AND p_valor < p_min             THEN 'bajo'
    WHEN p_max IS NOT NULL AND p_valor > p_max             THEN 'alto'
    ELSE 'normal'
  END
$$;

-- ---------------------------------------------------------------------
-- Que precio aplica - de lo mas especifico a lo mas general
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION lab.precio_para(
  p_empresa_id  bigint,
  p_prueba_id   bigint,
  p_sucursal_id bigint,
  p_convenio_id bigint,
  p_fecha       date DEFAULT current_date
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT p.precio
  FROM lab.precio_prueba p
  WHERE p.empresa_id = p_empresa_id
    AND p.prueba_id  = p_prueba_id
    AND (p.sucursal_id IS NULL OR p.sucursal_id = p_sucursal_id)
    AND (p.convenio_id IS NULL OR p.convenio_id = p_convenio_id)
    AND p.vigente_desde <= p_fecha
    AND (p.vigente_hasta IS NULL OR p.vigente_hasta >= p_fecha)
  ORDER BY
    (p.convenio_id IS NOT NULL) DESC,   -- tarifa negociada gana
    (p.sucursal_id IS NOT NULL) DESC,   -- luego precio de esta sucursal
    p.vigente_desde DESC
  LIMIT 1
$$;

-- ---------------------------------------------------------------------
-- Registrar un resultado - el rango se copia solo
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION lab.registrar_resultado(
  p_orden_prueba_id  bigint,
  p_analito_id       bigint,
  p_valor_numerico   numeric  DEFAULT NULL,
  p_valor_texto      text     DEFAULT NULL,
  p_muestra_id       bigint   DEFAULT NULL,
  p_equipo_id        bigint   DEFAULT NULL,
  p_mensaje_crudo_id bigint   DEFAULT NULL,
  p_medido_en        timestamptz DEFAULT now(),
  p_usuario_id       bigint   DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_empresa_id  bigint;
  v_sexo        plataforma.sexo;
  v_edad_dias   integer;
  v_unidad      text;
  v_metodo      text;
  v_nota        text;
  v_rango       record;
  v_resultado_id bigint;
BEGIN
  -- El sexo y la edad salen del paciente del episodio: son lo que decide el rango.
  SELECT op.empresa_id,
         pa.sexo,
         (current_date - pa.fecha_nacimiento)::integer,
         pr.metodo
    INTO v_empresa_id, v_sexo, v_edad_dias, v_metodo
  FROM lab.orden_prueba op
  JOIN lab.orden    o  ON o.orden_id     = op.orden_id
  JOIN core.episodio e ON e.episodio_id  = o.episodio_id
  JOIN core.paciente pa ON pa.paciente_id = e.paciente_id
  JOIN lab.prueba   pr ON pr.prueba_id   = op.prueba_id
  WHERE op.orden_prueba_id = p_orden_prueba_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El examen pedido % no existe', p_orden_prueba_id;
  END IF;

  SELECT unidad INTO v_unidad FROM lab.analito WHERE analito_id = p_analito_id;

  -- Sin fecha de nacimiento se asume adulto, PERO queda escrito en el resultado.
  -- Una suposicion que no se ve es una suposicion que nadie corrige.
  IF v_edad_dias IS NULL THEN
    v_edad_dias := 10950;   -- 30 anios
    v_nota := 'Rango de adulto aplicado: paciente sin fecha de nacimiento registrada';
  END IF;

  SELECT * INTO v_rango
  FROM lab.rango_para(v_empresa_id, p_analito_id, v_sexo, v_edad_dias);

  INSERT INTO lab.resultado (
    empresa_id, orden_prueba_id, analito_id, muestra_id,
    valor_numerico, valor_texto, unidad,
    rango_min, rango_max, critico_min, critico_max, rango_texto,
    bandera, estado, metodo, equipo_id, mensaje_crudo_id,
    medido_en, capturado_por_usuario_id, observacion
  ) VALUES (
    v_empresa_id, p_orden_prueba_id, p_analito_id, p_muestra_id,
    p_valor_numerico, p_valor_texto, v_unidad,
    v_rango.valor_min, v_rango.valor_max, v_rango.critico_min, v_rango.critico_max,
    v_rango.rango_texto,
    lab.bandera_para(p_valor_numerico, v_rango.valor_min, v_rango.valor_max,
                     v_rango.critico_min, v_rango.critico_max),
    'preliminar', v_metodo, p_equipo_id, p_mensaje_crudo_id,
    p_medido_en, p_usuario_id, v_nota
  )
  RETURNING resultado_id INTO v_resultado_id;

  RETURN v_resultado_id;
END $$;

COMMENT ON FUNCTION lab.registrar_resultado IS
  'El rango se copia aqui, una sola vez, en el unico camino por el que entra un '
  'resultado. Asi la regla "el informe de hace un anio muestra el rango que se uso '
  'ese dia" no depende de que nadie la olvide en algun endpoint nuevo.';

-- ---------------------------------------------------------------------
-- Corregir - insertar una version nueva, nunca sobrescribir
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION lab.corregir_resultado(
  p_resultado_id   bigint,
  p_valor_numerico numeric,
  p_valor_texto    text,
  p_motivo         text,
  p_usuario_id     bigint
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_ant   lab.resultado%ROWTYPE;
  v_nuevo bigint;
BEGIN
  PERFORM core.exigir_permiso('resultado.corregir', p_usuario_id);

  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RAISE EXCEPTION 'Corregir un resultado exige un motivo';
  END IF;

  SELECT * INTO v_ant FROM lab.resultado WHERE resultado_id = p_resultado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El resultado % no existe', p_resultado_id;
  END IF;
  IF NOT v_ant.vigente THEN
    RAISE EXCEPTION 'Ese resultado ya fue corregido; corrige el vigente';
  END IF;

  -- Primero se retira la vigencia del anterior y despues se inserta el nuevo.
  -- El orden importa: el indice unico parcial solo admite un resultado vigente
  -- por analito, y es esa restriccion la que garantiza que no queden dos valores
  -- validos al mismo tiempo.
  UPDATE lab.resultado SET vigente = false WHERE resultado_id = p_resultado_id;

  -- El valor viejo NO se toca: solo dejo de ser el vigente. El nuevo lleva el
  -- mismo rango que se aplico entonces, porque corregir el valor no es cambiar
  -- el criterio con el que se juzgo.
  INSERT INTO lab.resultado (
    empresa_id, orden_prueba_id, analito_id, muestra_id,
    valor_numerico, valor_texto, unidad,
    rango_min, rango_max, critico_min, critico_max, rango_texto,
    bandera, estado, metodo, equipo_id, medido_en,
    capturado_por_usuario_id, validado_por_usuario_id, validado_en,
    corrige_a_resultado_id, motivo_correccion
  ) VALUES (
    v_ant.empresa_id, v_ant.orden_prueba_id, v_ant.analito_id, v_ant.muestra_id,
    p_valor_numerico, p_valor_texto, v_ant.unidad,
    v_ant.rango_min, v_ant.rango_max, v_ant.critico_min, v_ant.critico_max,
    v_ant.rango_texto,
    lab.bandera_para(p_valor_numerico, v_ant.rango_min, v_ant.rango_max,
                     v_ant.critico_min, v_ant.critico_max),
    'corregido', v_ant.metodo, v_ant.equipo_id, v_ant.medido_en,
    p_usuario_id, p_usuario_id, now(),
    p_resultado_id, p_motivo
  )
  RETURNING resultado_id INTO v_nuevo;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_ant.empresa_id, p_usuario_id, 'resultado.corregir', 'lab', 'resultado',
    p_resultado_id,
    jsonb_build_object('valor_numerico', v_ant.valor_numerico,
                       'valor_texto',    v_ant.valor_texto),
    jsonb_build_object('valor_numerico', p_valor_numerico,
                       'valor_texto',    p_valor_texto,
                       'motivo',         p_motivo,
                       'resultado_id',   v_nuevo)
  );

  RETURN v_nuevo;
END $$;

-- ---------------------------------------------------------------------
-- Validar
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION lab.validar_resultado(
  p_resultado_id bigint,
  p_usuario_id   bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_bandera lab.bandera;
  v_empresa bigint;
BEGIN
  PERFORM core.exigir_permiso('resultado.validar', p_usuario_id);

  -- Regla del dominio, no de seguridad: quien firma un resultado tiene que
  -- tener colegiacion registrada, porque ese numero va impreso en el informe
  -- junto a la firma. Un permiso no convierte a nadie en bioquimico.
  IF NOT EXISTS (
    SELECT 1 FROM core.usuario u
    JOIN core.empleado e ON e.empleado_id = u.empleado_id AND e.empresa_id = u.empresa_id
    WHERE u.usuario_id = p_usuario_id
      AND e.numero_colegiacion IS NOT NULL
      AND btrim(e.numero_colegiacion) <> ''
  ) THEN
    RAISE EXCEPTION
      'Quien valida un resultado debe tener numero de colegiacion registrado';
  END IF;

  UPDATE lab.resultado
     SET estado = 'validado',
         validado_por_usuario_id = p_usuario_id,
         validado_en = now()
   WHERE resultado_id = p_resultado_id
     AND estado = 'preliminar'
     AND vigente
  RETURNING bandera, empresa_id INTO v_bandera, v_empresa;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El resultado % no esta preliminar y vigente', p_resultado_id;
  END IF;

  -- Un valor critico validado sin aviso registrado es exactamente el caso que
  -- este sistema existe para no dejar pasar.
  IF v_bandera IN ('critico_bajo','critico_alto')
     AND NOT EXISTS (SELECT 1 FROM lab.aviso_valor_critico
                     WHERE resultado_id = p_resultado_id) THEN
    RAISE EXCEPTION
      'Resultado % tiene valor critico (%): registra a quien se aviso antes de validar',
      p_resultado_id, v_bandera;
  END IF;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion,
                            nombre_esquema, nombre_tabla, registro_id)
  VALUES (v_empresa, p_usuario_id, 'resultado.validar', 'lab', 'resultado', p_resultado_id);
END $$;

COMMENT ON FUNCTION lab.validar_resultado IS
  'Validacion POR RESULTADO. La accion "validar todo lo pendiente" de la interfaz '
  'es un ciclo sobre esta funcion: asi entregar una parte mientras se repite otra '
  'sale gratis, que es lo que pasa cuando un examen sale anomalo.';


-- ---------------------------------------------------------- 15_lab_semillas.sql

CREATE OR REPLACE FUNCTION lab.sembrar_hematologia(
  p_empresa_id  bigint,
  p_sucursal_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_area_hema  bigint;
  v_area_quim  bigint;
  v_edta       bigint;
  v_suero      bigint;
  v_prueba_hem bigint;
  v_prueba_glu bigint;
  v_equipo     bigint;
  v_analito    bigint;
  v_orden      smallint := 0;
  r            record;
BEGIN
  -- ---------------- areas ----------------
  INSERT INTO lab.area (empresa_id, codigo, nombre, orden_presentacion)
  VALUES (p_empresa_id, 'HEMA', 'Hematologia', 1) RETURNING area_id INTO v_area_hema;

  INSERT INTO lab.area (empresa_id, codigo, nombre, orden_presentacion)
  VALUES (p_empresa_id, 'QUIM', 'Quimica clinica', 2) RETURNING area_id INTO v_area_quim;

  -- ---------------- tipos de muestra ----------------
  INSERT INTO lab.tipo_muestra (empresa_id, codigo, nombre, color_tapon,
                                anticoagulante, volumen_min_ml, estable_horas)
  VALUES (p_empresa_id, 'EDTA', 'Sangre total con EDTA', 'Lavanda', 'EDTA K2', 2.0, 8)
  RETURNING tipo_muestra_id INTO v_edta;

  INSERT INTO lab.tipo_muestra (empresa_id, codigo, nombre, color_tapon,
                                anticoagulante, volumen_min_ml, estable_horas)
  VALUES (p_empresa_id, 'SUERO', 'Suero', 'Rojo', NULL, 3.0, 48)
  RETURNING tipo_muestra_id INTO v_suero;

  -- ---------------- analitos ----------------
  -- Los 24 parametros de reporte del Hemax 53, en el orden en que los manda.
  FOR r IN
    SELECT * FROM (VALUES
      ('WBC',    'Leucocitos',                          '10^3/uL', 2),
      ('LYM%',   'Linfocitos',                          '%',       1),
      ('MON%',   'Monocitos',                           '%',       1),
      ('NEU%',   'Neutrofilos',                         '%',       1),
      ('EOS%',   'Eosinofilos',                         '%',       1),
      ('BASO%',  'Basofilos',                           '%',       1),
      ('LYM#',   'Linfocitos absolutos',                '10^3/uL', 2),
      ('MON#',   'Monocitos absolutos',                 '10^3/uL', 2),
      ('NEU#',   'Neutrofilos absolutos',               '10^3/uL', 2),
      ('EOS#',   'Eosinofilos absolutos',               '10^3/uL', 2),
      ('BASO#',  'Basofilos absolutos',                 '10^3/uL', 2),
      ('RBC',    'Eritrocitos',                         '10^6/uL', 2),
      ('HGB',    'Hemoglobina',                         'g/dL',    1),
      ('HCT',    'Hematocrito',                         '%',       1),
      ('MCV',    'Volumen corpuscular medio',           'fL',      1),
      ('MCH',    'Hemoglobina corpuscular media',       'pg',      1),
      ('MCHC',   'Concentracion de hemoglobina C.M.',   'g/dL',    1),
      ('RDW_CV', 'Amplitud de distribucion eritrocitaria (CV)', '%',  1),
      ('RDW_SD', 'Amplitud de distribucion eritrocitaria (SD)', 'fL', 1),
      ('PLT',    'Plaquetas',                           '10^3/uL', 0),
      ('MPV',    'Volumen plaquetario medio',           'fL',      1),
      ('PDW',    'Amplitud de distribucion plaquetaria','fL',      1),
      ('PCT',    'Plaquetocrito',                       '%',       2),
      ('P_LCR',  'Ratio de plaquetas grandes',          '%',       1)
    ) AS t(codigo, nombre, unidad, decimales)
  LOOP
    INSERT INTO lab.analito (empresa_id, area_id, codigo, nombre, unidad, decimales)
    VALUES (p_empresa_id, v_area_hema, r.codigo, r.nombre, r.unidad, r.decimales);
  END LOOP;

  INSERT INTO lab.analito (empresa_id, area_id, codigo, nombre, unidad, decimales)
  VALUES (p_empresa_id, v_area_quim, 'GLU', 'Glucosa', 'mg/dL', 0);

  -- ---------------- pruebas ----------------
  -- Un hemograma: se cobra UNA vez y produce 24 resultados.
  INSERT INTO lab.prueba (empresa_id, area_id, tipo_muestra_id, codigo, nombre,
                          metodo, horas_proceso)
  VALUES (p_empresa_id, v_area_hema, v_edta, 'HEM01', 'Hemograma completo',
          'Impedancia y citometria de flujo', 4)
  RETURNING prueba_id INTO v_prueba_hem;

  INSERT INTO lab.prueba_analito (prueba_id, analito_id, empresa_id, orden_presentacion)
  SELECT v_prueba_hem, a.analito_id, p_empresa_id, a.analito_id
  FROM lab.analito a
  WHERE a.empresa_id = p_empresa_id AND a.area_id = v_area_hema;

  -- Una glucosa: se cobra una vez y produce 1 resultado. El mismo modelo
  -- sirve para las dos; por eso no hacen falta dos disenos.
  INSERT INTO lab.prueba (empresa_id, area_id, tipo_muestra_id, codigo, nombre,
                          metodo, horas_proceso, requiere_ayuno, indicaciones)
  VALUES (p_empresa_id, v_area_quim, v_suero, 'GLU01', 'Glucosa en ayunas',
          'Colorimetrico enzimatico', 4, true, 'Ayuno de 8 a 12 horas')
  RETURNING prueba_id INTO v_prueba_glu;

  INSERT INTO lab.prueba_analito (prueba_id, analito_id, empresa_id)
  SELECT v_prueba_glu, analito_id, p_empresa_id
  FROM lab.analito WHERE empresa_id = p_empresa_id AND codigo = 'GLU';

  -- ---------------- precios de lista ----------------
  INSERT INTO lab.precio_prueba (empresa_id, prueba_id, precio) VALUES
    (p_empresa_id, v_prueba_hem, 350.00),
    (p_empresa_id, v_prueba_glu, 120.00);

  -- ---------------- rangos de referencia ----------------
  -- Ver la advertencia del encabezado antes de usar esto con pacientes.
  FOR r IN
    SELECT * FROM (VALUES
      -- codigo,  sexo,        min,   max,  critico_min, critico_max
      ('WBC',    'ambos',      4.5,  11.0,   1.5,   30.0),
      ('NEU%',   'ambos',     40.0,  75.0,  NULL,   NULL),
      ('LYM%',   'ambos',     20.0,  45.0,  NULL,   NULL),
      ('MON%',   'ambos',      2.0,  10.0,  NULL,   NULL),
      ('EOS%',   'ambos',      1.0,   6.0,  NULL,   NULL),
      ('BASO%',  'ambos',      0.0,   2.0,  NULL,   NULL),
      ('NEU#',   'ambos',      1.8,   7.7,   0.5,   NULL),
      ('LYM#',   'ambos',      1.0,   4.8,  NULL,   NULL),
      ('MON#',   'ambos',      0.1,   0.9,  NULL,   NULL),
      ('EOS#',   'ambos',      0.0,   0.5,  NULL,   NULL),
      ('BASO#',  'ambos',      0.0,   0.2,  NULL,   NULL),
      ('RBC',    'masculino',  4.5,   5.9,  NULL,   NULL),
      ('RBC',    'femenino',   4.0,   5.2,  NULL,   NULL),
      ('HGB',    'masculino', 13.5,  17.5,   7.0,   20.0),
      ('HGB',    'femenino',  12.0,  15.5,   7.0,   20.0),
      ('HCT',    'masculino', 41.0,  53.0,  20.0,   60.0),
      ('HCT',    'femenino',  36.0,  46.0,  20.0,   60.0),
      ('MCV',    'ambos',     80.0, 100.0,  NULL,   NULL),
      ('MCH',    'ambos',     27.0,  33.0,  NULL,   NULL),
      ('MCHC',   'ambos',     32.0,  36.0,  NULL,   NULL),
      ('RDW_CV', 'ambos',     11.5,  14.5,  NULL,   NULL),
      ('RDW_SD', 'ambos',     37.0,  54.0,  NULL,   NULL),
      ('PLT',    'ambos',    150.0, 450.0,  20.0, 1000.0),
      ('MPV',    'ambos',      7.5,  11.5,  NULL,   NULL),
      ('PDW',    'ambos',      9.0,  17.0,  NULL,   NULL),
      ('PCT',    'ambos',      0.19,  0.39, NULL,   NULL),
      ('P_LCR',  'ambos',     13.0,  43.0,  NULL,   NULL),
      ('GLU',    'ambos',     70.0, 100.0,  40.0,  400.0)
    ) AS t(codigo, sexo, vmin, vmax, cmin, cmax)
  LOOP
    SELECT analito_id INTO v_analito
    FROM lab.analito WHERE empresa_id = p_empresa_id AND codigo = r.codigo;

    INSERT INTO lab.rango_referencia (
      empresa_id, analito_id, sexo, edad_min_dias, edad_max_dias,
      valor_min, valor_max, critico_min, critico_max
    ) VALUES (
      p_empresa_id, v_analito, r.sexo::lab.sexo_rango, 6570, 54750,  -- 18 anios en adelante
      r.vmin, r.vmax, r.cmin, r.cmax
    );
  END LOOP;

  -- ---------------- el equipo ----------------
  INSERT INTO integra.equipo (
    empresa_id, sucursal_id, area_id, codigo, nombre, marca, modelo,
    protocolo, identificador, bidireccional
  ) VALUES (
    p_empresa_id, p_sucursal_id, v_area_hema, 'HEMAX53', 'Hemax 53',
    'B&E Bio-Technology', 'Hemax 53', 'hl7_v2', 'EQUIPO_HEMA', false
  )
  RETURNING equipo_id INTO v_equipo;

  -- El equipo manda exactamente los mismos codigos que usamos como codigo de
  -- analito, asi que el mapeo es uno a uno. Con el segundo analizador dejara
  -- de serlo, y por eso esta tabla existe desde ahora.
  INSERT INTO integra.mapeo_codigo (empresa_id, equipo_id, codigo_equipo, analito_id)
  SELECT p_empresa_id, v_equipo, a.codigo, a.analito_id
  FROM lab.analito a
  WHERE a.empresa_id = p_empresa_id AND a.area_id = v_area_hema;

END $$;

COMMENT ON FUNCTION lab.sembrar_hematologia IS
  'Catalogo inicial de un laboratorio con un Hemax 53. Los 24 analitos salen del '
  'mensaje real guardado en ProLab/prueba.txt, que coincide con los 24 parametros '
  'de reporte que declara el fabricante.';


-- ---------------------------------------------------------- 16_roles.sql

-- =====================================================================
-- ProLisSaas - 16 - El alta de una empresa, con roles que sirven
--
-- QUE PUEDE HACER cada puesto de un laboratorio esta definido aqui, dentro
-- de crear_empresa(), y no en un par de tablas de plantillas.
--
-- Antes eran plataforma.rol_plantilla y plataforma.rol_plantilla_permiso.
-- Se quitaron por dos razones:
--
--   1. No son parte de RBAC. El modelo es usuario -> rol -> permisos, y las
--      plantillas no aparecen en esa cadena. Son SEMILLA, y una semilla que
--      se usa cada varios meses no necesita dos tablas.
--   2. Eran una segunda definicion de "que roles existen", que puede
--      desincronizarse de la realidad sin que nadie lo note.
--
-- El dia que exista una consola de operador donde se pueda cambiar "que le
-- toca a un laboratorio nuevo" sin abrir un .sql, vuelven a tener sentido.
-- Hoy no existe (H-16) y el esquema se corre desde estos archivos.
--
-- OJO: los datos maestros del alta -- que roles, que correlativos, que
-- convenio, que modulos -- estan aqui porque hay que arrancar con algo, no
-- porque esten decididos. El flujo de alta todavia no se declara a proposito:
-- se define cuando core este verificado entero, porque cualquier cambio de
-- ahi hacia atras obligaria a rehacerlo (H-91).
-- =====================================================================




-- ---------------------------------------------------------------------
-- Alta de empresa - ahora con roles que sirven
-- ---------------------------------------------------------------------
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

COMMENT ON FUNCTION core.crear_empresa IS
  'Dar de alta un cliente es una llamada, no una lista de pasos manuales que '
  'alguien puede hacer a medias. Los roles nacen con permisos porque un rol vacio '
  'es una promesa de que alguien lo configurara despues, y nadie lo hace.';

-- ---------------------------------------------------------------------
-- Consulta util para la pantalla de configuracion
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW core.v_rol_permiso AS
SELECT r.empresa_id,
       r.rol_id,
       r.nombre        AS rol,
       p.modulo_id,
       p.permiso_id,
       p.descripcion,
       (rp.rol_id IS NOT NULL) AS concedido
FROM core.rol r
CROSS JOIN plataforma.permiso p
LEFT JOIN core.rol_permiso rp
       ON rp.rol_id = r.rol_id AND rp.permiso_id = p.permiso_id;

COMMENT ON VIEW core.v_rol_permiso IS
  'La matriz completa rol x permiso, con o sin marca. Es exactamente lo que la '
  'pantalla de configuracion necesita pintar: una casilla por celda.';


-- ---------------------------------------------------------- 17_comercial.sql

-- ---------------------------------------------------------------------
-- El unico punto por donde una decision comercial entra al LIS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION comercial.registrar_evento(
  p_empresa_id  bigint,
  p_motivo_id   text,
  p_por         text,
  p_fecha       date DEFAULT CURRENT_DATE,
  p_nota        text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  m           comercial.motivo%ROWTYPE;
  v_nivel     core.nivel_acceso;
  v_plazo     integer;
  v_vence     date;
  v_estado    core.estado_empresa;
  v_evento_id bigint;
BEGIN
  SELECT * INTO m FROM comercial.motivo WHERE motivo_id = p_motivo_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el motivo %', p_motivo_id;
  END IF;
  IF NOT m.activo THEN
    RAISE EXCEPTION 'El motivo % esta retirado', p_motivo_id;
  END IF;
  IF m.requiere_nota AND (p_nota IS NULL OR btrim(p_nota) = '') THEN
    RAISE EXCEPTION 'El motivo % exige una nota que explique la decision', p_motivo_id;
  END IF;

  -- Un motivo sin politica pensada no se lee como "sin restriccion": se aplica
  -- lo seguro y se avisa. Pero "lo seguro" solo tiene sentido cuando el evento
  -- RESTRINGE. En un alta o una reactivacion, caer en solo_lectura no es
  -- prudencia: deja al cliente sin poder trabajar el dia que entra. Por eso los
  -- eventos que conceden acceso nacen con su politica definida y en completo, y
  -- lo que queda por decidir es el lado restrictivo: cuanto plazo y con que
  -- nivel durante el.
  IF m.politica_definida THEN
    v_nivel := m.nivel_inmediato;
    v_plazo := m.dias_plazo;
  ELSIF m.tipo_evento IN ('suspension','cancelacion','cierre') THEN
    v_nivel := 'solo_lectura';
    v_plazo := NULL;
    RAISE WARNING 'El motivo % todavia no tiene politica definida: se aplica solo_lectura', p_motivo_id;
  ELSE
    RAISE EXCEPTION 'El motivo % concede acceso y no tiene politica definida. '
                    'Definila antes de usarlo: un alta a medias no se nota hasta '
                    'que el cliente no puede trabajar', p_motivo_id;
  END IF;

  IF v_plazo IS NOT NULL THEN
    v_vence := p_fecha + v_plazo;
  END IF;

  -- El estado que le corresponde al hecho. El LIS guarda el estado para poder
  -- decir en que punto esta; lo que decide que se puede hacer es el nivel.
  v_estado := CASE m.tipo_evento
                WHEN 'alta'         THEN 'prueba'
                WHEN 'activacion'   THEN 'activa'
                WHEN 'suspension'   THEN 'suspendida'
                WHEN 'reactivacion' THEN 'activa'
                WHEN 'cancelacion'  THEN 'cancelada'
                WHEN 'cierre'       THEN 'cerrada'
              END;

  INSERT INTO comercial.relacion_evento (
    empresa_id, tipo_evento, motivo_id, fecha,
    nivel_aplicado, dias_plazo_aplicado, nivel_al_vencer_aplicado,
    estado_al_vencer_aplicado, fecha_vencimiento, politica_estaba_definida,
    nota, registrado_por
  ) VALUES (
    p_empresa_id, m.tipo_evento, m.motivo_id, p_fecha,
    v_nivel, v_plazo, m.nivel_al_vencer,
    m.estado_al_vencer, v_vence, m.politica_definida,
    p_nota, p_por
  ) RETURNING evento_id INTO v_evento_id;

  -- Y aqui, y solo aqui, la decision cruza al LIS.
  UPDATE core.empresa
     SET estado       = v_estado,
         nivel_acceso = v_nivel,
         fecha_cierre = v_vence
   WHERE empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la empresa %', p_empresa_id;
  END IF;

  RETURN v_evento_id;
END $$;

COMMENT ON FUNCTION comercial.registrar_evento IS
  'El unico camino por el que una decision comercial toca core.empresa. Escribe '
  'el hecho con su politica copiada y actualiza estado, nivel y fecha de cierre '
  'en una sola transaccion.';

-- ---------------------------------------------------------------------
-- Lo mismo, pero a nivel de cliente
--
-- Un cliente dejo de pagar: eso no le pasa a un inquilino, le pasa a el. Y
-- se tiene que aplicar a TODAS sus empresas vigentes o queda a medias.
--
-- El evento se sigue guardando por empresa a proposito: el LIS solo entiende
-- de empresas, y el historial tiene que poder leerse desde cualquiera de las
-- dos puntas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION comercial.registrar_evento_cliente(
  p_cliente_id  bigint,
  p_motivo_id   text,
  p_por         text,
  p_fecha       date DEFAULT CURRENT_DATE,
  p_nota        text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  e         record;
  v_cuenta  integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM comercial.cliente WHERE cliente_id = p_cliente_id) THEN
    RAISE EXCEPTION 'No existe el cliente %', p_cliente_id;
  END IF;

  FOR e IN
    SELECT ce.empresa_id
    FROM comercial.cliente_empresa ce
    WHERE ce.cliente_id = p_cliente_id
      AND ce.desde <= p_fecha
      AND (ce.hasta IS NULL OR ce.hasta > p_fecha)
    ORDER BY ce.empresa_id
  LOOP
    PERFORM comercial.registrar_evento(
      e.empresa_id, p_motivo_id, p_por, p_fecha, p_nota);
    v_cuenta := v_cuenta + 1;
  END LOOP;

  -- Un cliente sin ninguna empresa vigente es casi siempre un dedo, no una
  -- decision. Mejor que reviente aqui que descubrirlo cobrando.
  IF v_cuenta = 0 THEN
    RAISE EXCEPTION
      'El cliente % no tiene ninguna empresa vigente al %', p_cliente_id, p_fecha;
  END IF;

  RETURN v_cuenta;
END $$;

COMMENT ON FUNCTION comercial.registrar_evento_cliente IS
  'Aplica un evento comercial a todas las empresas vigentes del cliente, en una '
  'sola transaccion. Suspender a un cliente y que una de sus dos empresas siga '
  'trabajando no es un estado que deba poder existir.';

CREATE OR REPLACE FUNCTION comercial.cerrar_vencidas(p_hoy date DEFAULT CURRENT_DATE)
RETURNS TABLE (empresa_id bigint, nombre text, nivel core.nivel_acceso)
LANGUAGE plpgsql
AS $$
BEGIN
  -- La tarea diaria. Vive de este lado porque el plazo es una decision
  -- comercial, pero lee fecha_cierre de core.empresa, que esta ahi
  -- justamente para que esto funcione sin depender de nada externo.
  RETURN QUERY
  WITH ultimo AS (
    -- Por orden de REGISTRO, no por fecha de negocio: la politica que manda es
    -- la de la ultima decision tomada, y un evento registrado con fecha
    -- retroactiva sigue siendo la decision mas nueva.
    SELECT DISTINCT ON (e.empresa_id)
           e.empresa_id, e.nivel_al_vencer_aplicado, e.estado_al_vencer_aplicado
      FROM comercial.relacion_evento e
     WHERE e.fecha_vencimiento IS NOT NULL
     ORDER BY e.empresa_id, e.evento_id DESC
  ),
  vencidas AS (
    UPDATE core.empresa emp
       SET nivel_acceso = coalesce(u.nivel_al_vencer_aplicado, 'bloqueado'),
           estado       = coalesce(u.estado_al_vencer_aplicado, emp.estado),
           fecha_cierre = NULL
      FROM ultimo u
     WHERE u.empresa_id = emp.empresa_id
       AND emp.fecha_cierre IS NOT NULL
       AND emp.fecha_cierre <= p_hoy
    RETURNING emp.empresa_id, emp.nombre, emp.nivel_acceso
  )
  SELECT v.empresa_id, v.nombre, v.nivel_acceso FROM vencidas v;
END $$;

COMMENT ON FUNCTION comercial.cerrar_vencidas IS
  'Aplica el nivel al vencer a las empresas cuyo plazo se cumplio. Se corre una '
  'vez al dia. Si nadie la corre, el cliente conserva el nivel del plazo: el '
  'cierre no ocurre solo, ocurre porque alguien lo ejecuta.';

