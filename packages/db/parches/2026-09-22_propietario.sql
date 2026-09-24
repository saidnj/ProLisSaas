-- =====================================================================
-- ProLisSaas - parche: el propietario y los administradores
--
-- Para una base ya cargada. La deja igual que una carga limpia de
-- 02/04/05/06 despues de este cambio, y MIGRA los datos que ya tiene.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-22_propietario.sql
--
-- Se puede correr dos veces sin romper nada. Corre entero en una
-- transaccion: si algo falla, no queda a medias.
--
-- QUE CAMBIA
-- ----------
-- Dos clases de cuenta que antes eran la misma:
--
--   PROPIETARIO   la cuenta que el operador entrega con la empresa. Su rol
--                 es es_sistema: no se cambia, no se asigna, no se edita.
--                 Tiene un permiso extra, usuario.nombrar_admin.
--   ADMINISTRADOR cualquier rol con usuario.administrar. Los nombra el
--                 propietario y solo el los toca.
--
-- Nuevo: core.rol_es_admin(), core.puede_tocar_cuenta(), core.cambiar_rol()
-- (la unica forma de escribir usuario.rol_id), core.login_fallido() (el
-- contador de claves malas, que escribe 'estado'), el permiso
-- usuario.nombrar_admin, guardias en crear_usuario, generar_activacion y
-- asignar_permisos_a_rol, la politica de acceso_sucursal, y el UPDATE de
-- core.usuario cerrado a las dos columnas que el API toca directo.
--
-- QUE MIGRA (por empresa)
-- -----------------------
--   1. el rol 'Administrador' pasa a llamarse 'Propietario', es_sistema=true,
--      y recibe usuario.nombrar_admin
--   2. se crea un 'Administrador' nuevo (es_sistema=false) con los mismos
--      permisos menos el extra
--   3. si mas de un usuario tenia el rol viejo, el de usuario_id mas bajo
--      queda como Propietario y los demas pasan al Administrador nuevo
--      (se avisa con NOTICE quien fue)
--   4. todos los demas roles quedan es_sistema=false (07 los marcaba todos)
--   5. 'Jefe de sede' pierde usuario.administrar (decision del 2026-09-22)
--   6. cualquier OTRO rol que tenga usuario.administrar se avisa con NOTICE
--      y se deja como esta: es un administrador mas, y eso lo decide el
--      propietario de esa empresa
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1 · El permiso (06_semillas.sql)
-- ---------------------------------------------------------------------
INSERT INTO plataforma.permiso (permiso_id, modulo_id, descripcion) VALUES
  ('usuario.nombrar_admin','core', 'Nombrar administradores y tocar sus cuentas. Solo el propietario')
ON CONFLICT (permiso_id) DO NOTHING;

COMMENT ON COLUMN core.rol.es_sistema IS
  'true solo en el rol del PROPIETARIO, la cuenta que el operador entrega con la '
  'empresa. Lo leen crear_usuario, cambiar_rol y asignar_permisos_a_rol: ese rol no '
  'se asigna, no se cambia y sus permisos no se editan. Con eso siempre queda alguien '
  'que pueda crear usuarios (H-90). Traspasarlo es del operador, no del LIS.';


-- ---------------------------------------------------------------------
-- 2 · Las funciones (04_funciones.sql). Copiadas tal cual de ahi.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.rol_es_admin(p_rol_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM core.rol_permiso
    WHERE rol_id = p_rol_id AND permiso_id = 'usuario.administrar'
  )
$$;

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

  -- Lo que toca a QUIEN ADMINISTRA es del propietario:
  --   - el rol del propietario no se edita, por nadie
  --   - el extra no se reparte: vive solo en ese rol
  --   - un rol que es o que pasaria a ser de administrador lo edita solo
  --     quien tiene el extra. Si no, un administrador convierte a
  --     Recepcion en administradores, o se quita a si mismo el permiso
  --     y deja a la empresa sin nadie que cree usuarios (H-90).
  IF (SELECT es_sistema FROM core.rol WHERE rol_id = p_rol_id) THEN
    RAISE EXCEPTION 'Los permisos del propietario no se editan'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF 'usuario.nombrar_admin' = ANY (p_permisos) THEN
    RAISE EXCEPTION 'usuario.nombrar_admin solo lo tiene el propietario: no se asigna a otro rol'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF (core.rol_es_admin(p_rol_id) OR 'usuario.administrar' = ANY (p_permisos))
     AND NOT core.usuario_puede('usuario.nombrar_admin', v_usuario_id) THEN
    RAISE EXCEPTION 'Solo el propietario cambia los permisos de un rol de administrador'
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
  'La unica forma de escribir core.rol_permiso. REEMPLAZA el conjunto entero. '
  'Registra el cambio en audit.evento con el antes y el despues.';

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

  INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema) VALUES
    (v_empresa_id, 'Propietario',
     'La cuenta que el operador entrega con la empresa. Nombra a los administradores.', true),
    (v_empresa_id, 'Administrador',
     'Configura el sistema. No es un puesto clinico.', false),
    (v_empresa_id, 'Recepcion',
     'Admite pacientes, crea ordenes, toma muestras y entrega informes.', false),
    (v_empresa_id, 'Analista',
     'Recibe muestras, las procesa y captura resultados. No los aprueba.', false),
    (v_empresa_id, 'Bioquimico',
     'Todo lo del analista, mas validar, corregir y emitir informes.', false);
  -- Solo el Propietario va marcado como de sistema. Los otros cuatro tambien
  -- nacen con la empresa, pero el cliente los puede renombrar o repurposear;
  -- el que no se puede quedar sin permisos es el que administra (H-90).

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
-- 3 · Privilegios y politicas (05_privilegios.sql)
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE ON core.usuario FROM lis_app;

GRANT  UPDATE (intentos_fallidos, ultimo_acceso_en) ON core.usuario TO lis_app;

REVOKE ALL     ON FUNCTION core.cambiar_rol(bigint, bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.cambiar_rol(bigint, bigint, text) TO lis_app;

REVOKE ALL     ON FUNCTION core.login_fallido(bigint, int) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.login_fallido(bigint, int) TO lis_app;

DROP POLICY IF EXISTS rls_acceso_sucursal_crear  ON core.acceso_sucursal;
DROP POLICY IF EXISTS rls_acceso_sucursal_editar ON core.acceso_sucursal;

CREATE POLICY rls_acceso_sucursal_crear ON core.acceso_sucursal
  FOR INSERT
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente())
              AND (SELECT core.puede_crear())
              AND core.puede_tocar_cuenta(usuario_id));

CREATE POLICY rls_acceso_sucursal_editar ON core.acceso_sucursal
  FOR UPDATE
  USING      (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente())
              AND (SELECT core.puede_modificar())
              AND core.puede_tocar_cuenta(usuario_id));


-- ---------------------------------------------------------------------
-- 4 · La migracion de los datos, empresa por empresa
-- ---------------------------------------------------------------------
DO $mig$
DECLARE
  e          record;
  v_prop     bigint;   -- rol Propietario (el Administrador viejo, renombrado)
  v_admin    bigint;   -- rol Administrador nuevo
  v_dueno    bigint;   -- el usuario que queda como propietario
  v_otro     record;
  v_rol      record;
BEGIN
  FOR e IN SELECT empresa_id, nombre FROM core.empresa ORDER BY empresa_id LOOP

    SELECT rol_id INTO v_prop FROM core.rol
     WHERE empresa_id = e.empresa_id AND nombre = 'Propietario';

    IF v_prop IS NULL THEN
      -- Primera vez: el Administrador de nacimiento se vuelve Propietario.
      SELECT rol_id INTO v_prop FROM core.rol
       WHERE empresa_id = e.empresa_id AND nombre = 'Administrador';

      IF v_prop IS NULL THEN
        RAISE NOTICE 'empresa % (%): no tiene rol Administrador, no se migra nada', e.empresa_id, e.nombre;
        CONTINUE;
      END IF;

      UPDATE core.rol
         SET nombre = 'Propietario',
             descripcion = 'La cuenta que el operador entrega con la empresa. Nombra a los administradores',
             es_sistema = true
       WHERE rol_id = v_prop;

      INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema)
      VALUES (e.empresa_id, 'Administrador',
              'Configura la empresa entera: usuarios, roles, sucursales, convenios y precios', false)
      RETURNING rol_id INTO v_admin;

      -- El Administrador nuevo hereda los permisos del viejo (sin el extra,
      -- que todavia no lo tiene nadie).
      INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
      SELECT v_admin, permiso_id, e.empresa_id
        FROM core.rol_permiso WHERE rol_id = v_prop
      ON CONFLICT DO NOTHING;

      RAISE NOTICE 'empresa % (%): Administrador -> Propietario (rol %), Administrador nuevo = rol %',
        e.empresa_id, e.nombre, v_prop, v_admin;
    ELSE
      SELECT rol_id INTO v_admin FROM core.rol
       WHERE empresa_id = e.empresa_id AND nombre = 'Administrador';
    END IF;

    -- El extra, solo al propietario. Idempotente.
    INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
    VALUES (v_prop, 'usuario.nombrar_admin', e.empresa_id)
    ON CONFLICT DO NOTHING;

    UPDATE core.rol SET es_sistema = true  WHERE rol_id = v_prop AND NOT es_sistema;
    UPDATE core.rol SET es_sistema = false
     WHERE empresa_id = e.empresa_id AND rol_id <> v_prop AND es_sistema;

    -- Un solo propietario. Si varios tenian el rol viejo, se queda el mas
    -- antiguo (creado_en, y a igual fecha el usuario_id mas bajo); los demas
    -- pasan al Administrador nuevo. Es una suposicion: el NOTICE de abajo
    -- dice quien quedo, y si no es el correcto se corrige como postgres:
    --
    --   UPDATE core.usuario SET rol_id = <rol Administrador> WHERE username = '<el que quedo>';
    --   UPDATE core.usuario SET rol_id = <rol Propietario>   WHERE username = '<el correcto>';
    SELECT usuario_id INTO v_dueno FROM core.usuario
     WHERE rol_id = v_prop ORDER BY creado_en, usuario_id LIMIT 1;
    IF v_dueno IS NULL THEN
      RAISE NOTICE 'empresa % (%): NINGUN usuario tiene el rol Propietario -- el operador tiene que crear uno',
        e.empresa_id, e.nombre;
    END IF;
    FOR v_otro IN SELECT usuario_id, username FROM core.usuario
                   WHERE rol_id = v_prop AND usuario_id <> v_dueno LOOP
      UPDATE core.usuario SET rol_id = v_admin WHERE usuario_id = v_otro.usuario_id;
      RAISE NOTICE 'empresa % (%): HABIA MAS DE UN ADMINISTRADOR. % pasa a Administrador; el propietario queda como usuario_id % -- revisar que sea el correcto',
        e.empresa_id, e.nombre, v_otro.username, v_dueno;
    END LOOP;

    -- Jefe de sede ya no crea usuarios.
    DELETE FROM core.rol_permiso
     WHERE empresa_id = e.empresa_id AND permiso_id = 'usuario.administrar'
       AND rol_id IN (SELECT rol_id FROM core.rol
                       WHERE empresa_id = e.empresa_id AND nombre = 'Jefe de sede');
    IF FOUND THEN
      RAISE NOTICE 'empresa % (%): Jefe de sede pierde usuario.administrar', e.empresa_id, e.nombre;
    END IF;

    -- Cualquier otro rol que administre usuarios se avisa y se respeta.
    FOR v_rol IN SELECT r.rol_id, r.nombre FROM core.rol r
                  WHERE r.empresa_id = e.empresa_id
                    AND r.rol_id NOT IN (v_prop, v_admin)
                    AND core.rol_es_admin(r.rol_id) LOOP
      RAISE NOTICE 'empresa % (%): el rol "%" tiene usuario.administrar -- cuenta como administrador; revisar si es lo que se quiere',
        e.empresa_id, e.nombre, v_rol.nombre;
    END LOOP;
  END LOOP;
END $mig$;

COMMIT;


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core'
      AND p.proname IN ('rol_es_admin','puede_tocar_cuenta','cambiar_rol','login_fallido')) AS funciones_nuevas,
  (SELECT count(*) FROM plataforma.permiso WHERE permiso_id = 'usuario.nombrar_admin') AS permiso_extra,
  (SELECT count(*) FROM core.empresa)                                              AS empresas,
  (SELECT count(*) FROM core.rol WHERE es_sistema)                                 AS roles_propietario,
  (SELECT count(*) FROM core.rol WHERE nombre = 'Administrador' AND NOT es_sistema) AS roles_administrador,
  (SELECT count(*) FROM core.rol_permiso WHERE permiso_id = 'usuario.nombrar_admin') AS extras_repartidos,
  (SELECT count(*) FROM information_schema.column_privileges
    WHERE grantee = 'lis_app' AND table_schema = 'core' AND table_name = 'usuario'
      AND privilege_type = 'UPDATE')                                               AS columnas_update_usuario,
  (SELECT count(*) FROM pg_policies WHERE tablename = 'acceso_sucursal'
      AND qual IS NULL AND with_check LIKE '%puede_tocar_cuenta%'
       OR (tablename = 'acceso_sucursal' AND with_check LIKE '%puede_tocar_cuenta%')) AS politicas_acceso;

-- Tiene que salir: funciones_nuevas = 4 · permiso_extra = 1 ·
--   roles_propietario = empresas · roles_administrador = empresas ·
--   extras_repartidos = empresas · columnas_update_usuario = 2 · politicas_acceso = 2

-- Quien es el propietario de cada empresa, para revisar de un vistazo:
SELECT e.empresa_id, e.nombre AS empresa, u.username AS propietario
FROM core.empresa e
LEFT JOIN core.rol r ON r.empresa_id = e.empresa_id AND r.es_sistema
LEFT JOIN core.usuario u ON u.rol_id = r.rol_id
ORDER BY e.empresa_id;
