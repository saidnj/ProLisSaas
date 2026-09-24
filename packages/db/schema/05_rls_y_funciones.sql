-- =====================================================================
-- ProLisSaas · 05 · Aislamiento y funciones
--
-- Esta es la parte que hace que "nada cruza la frontera de la empresa"
-- deje de depender de que nadie olvide un WHERE.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Roles de base de datos
-- ---------------------------------------------------------------------

-- El rol con el que se conecta la API. No es superusuario y no puede
-- saltarse RLS. El dueno de las tablas es otro rol distinto a proposito:
-- el dueno de una tabla ignora sus propias politicas salvo FORCE.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lis_app') THEN
    CREATE ROLE lis_app NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA core, audit, plataforma TO lis_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core TO lis_app;
GRANT SELECT, INSERT              ON ALL TABLES IN SCHEMA audit TO lis_app;
GRANT SELECT                      ON plataforma.modulo, plataforma.permiso TO lis_app;

-- La licencia se lee, no se escribe: la escribe el operador. RLS la recorta a
-- la empresa de la sesion, asi que el laboratorio ve la suya y nada mas.
GRANT SELECT                      ON plataforma.modulo_sucursal TO lis_app;

-- Nada se borra. Ni siquiera se le da el permiso.
REVOKE DELETE ON ALL TABLES IN SCHEMA core  FROM lis_app;
REVOKE DELETE ON ALL TABLES IN SCHEMA audit FROM lis_app;

-- Los permisos de un rol NO se escriben a mano. Se cambian por
-- core.asignar_permisos_a_rol(), que comprueba tres cosas antes de tocar nada.
-- Con el INSERT abierto, cualquier usuario se daba usuario.administrar a si
-- mismo, y se metia permisos de modulos que su empresa no contrata (H-99).
REVOKE INSERT, UPDATE ON core.rol_permiso FROM lis_app;

-- El enlace no se lee directo: se pregunta por core.mis_enlaces(), que solo
-- contesta tu lado. Asi una empresa nunca ve la sucursal de la otra.
REVOKE ALL ON plataforma.enlace FROM lis_app;

-- core.empresa es la unica tabla del nucleo que el laboratorio NO puede editar
-- a su gusto. Con el UPDATE completo, un usuario del cliente se levantaba su
-- propia suspension (estado de 'suspendida' a 'activa') y se cambiaba el RTN:
-- RLS deja pasar la propia fila, asi que la politica no lo impedia. El nivel de
-- acceso y la fecha de cierre son decisiones del lado comercial y por eso
-- tampoco se tocan desde aqui.
--
-- Lo unico que el laboratorio configura de si mismo es como quiere que se lea
-- su nombre en el informe.
REVOKE UPDATE ON core.empresa FROM lis_app;
GRANT  UPDATE (nombre_comercial) ON core.empresa TO lis_app;



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

COMMENT ON FUNCTION core.usuario_actual() IS
  'Igual que empresa_actual: la API hace SET LOCAL lis.usuario_id con el valor del '
  'token. Sin esto, las comprobaciones de permiso no tienen a quien comprobar.';


-- ---------------------------------------------------------------------
-- Permisos · quien puede hacer que
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
-- Las dos son invoker y NO SECURITY DEFINER a proposito: asi RLS las sigue
-- recortando a la empresa de la sesion y nadie puede preguntar por un usuario
-- ajeno.

CREATE OR REPLACE FUNCTION core.usuario_puede(
  p_permiso_id text,
  p_usuario_id bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core.usuario u
    JOIN core.rol_permiso rp ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
    JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
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

COMMENT ON FUNCTION core.usuario_puede IS
  'El modulo tiene que estar encendido en ALGUNA sede de la empresa. Para pintar '
  'menus y para lo que no ocurre en una sucursal concreta. Donde hay sucursal se '
  'usa usuario_puede_en(), que es mas estricta. '
  'Falla cerrado: si no hay usuario, si el usuario esta suspendido o si RLS oculta '
  'la fila, devuelve false. Nunca devuelve true por omision.';


CREATE OR REPLACE FUNCTION core.usuario_puede_en(
  p_permiso_id  text,
  p_sucursal_id bigint,
  p_usuario_id  bigint DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core.usuario u
    JOIN core.rol_permiso rp ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
    JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
    JOIN plataforma.modulo_sucursal ms
      ON ms.modulo_id   = p.modulo_id
     AND ms.empresa_id  = u.empresa_id
     AND ms.sucursal_id = p_sucursal_id
     AND ms.activo
    WHERE u.usuario_id = coalesce(p_usuario_id, core.usuario_actual())
      AND u.estado = 'activo'
      AND rp.permiso_id = p_permiso_id
  )
$$;

COMMENT ON FUNCTION core.usuario_puede_en IS
  'La estricta: exige que el modulo del permiso este encendido EN ESA SEDE. La '
  'usan las operaciones, que ya reciben la sucursal. Falta decidir si la '
  'sucursal viaja en el contexto de sesion como lis.empresa_id (H-100).';


-- Lo que la pantalla de "crear rol" tiene derecho a mostrarle al administrador.
-- Sin sucursal devuelve la union de lo que la empresa tenga en alguna sede,
-- porque el rol es de la empresa y el modulo es de la sede.
CREATE OR REPLACE FUNCTION core.permisos_disponibles(p_sucursal_id bigint DEFAULT NULL)
RETURNS TABLE (permiso_id text, modulo_id text, descripcion text)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT p.permiso_id, p.modulo_id, p.descripcion
  FROM plataforma.permiso p
  JOIN plataforma.modulo_sucursal ms ON ms.modulo_id = p.modulo_id AND ms.activo
  WHERE p_sucursal_id IS NULL OR ms.sucursal_id = p_sucursal_id
  ORDER BY 2, 1
$$;

COMMENT ON FUNCTION core.permisos_disponibles IS
  'El menu del administrador. Filtrar la lista en pantalla es una comodidad, no '
  'una proteccion: quien la escribe de verdad es asignar_permisos_a_rol().';


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
  IF current_user <> 'lis_app' THEN
    RETURN;
  END IF;

  IF NOT core.usuario_puede(p_permiso_id, p_usuario_id) THEN
    RAISE EXCEPTION 'El usuario no tiene el permiso %', p_permiso_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

COMMENT ON FUNCTION core.exigir_permiso IS
  'Ultima linea de defensa, no la primera. La API debe comprobar el permiso antes '
  'de llegar aqui para dar un mensaje decente; esto atrapa el endpoint nuevo que '
  'alguien escribio sin acordarse.';


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

REVOKE ALL    ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) TO lis_app;


-- ---------------------------------------------------------------------
-- Politicas RLS
-- ---------------------------------------------------------------------

-- La empresa se ve a si misma.
ALTER TABLE core.empresa ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.empresa FORCE  ROW LEVEL SECURITY;
CREATE POLICY rls_empresa ON core.empresa
  USING      (empresa_id = core.empresa_actual())
  WITH CHECK (empresa_id = core.empresa_actual());

-- La licencia: cada empresa ve la suya y nada mas. FOR SELECT y sin WITH CHECK
-- porque desde el laboratorio no hay escritura posible -- solo tiene SELECT.
-- Se declara aqui y no en 03_core.sql porque alla todavia no existe
-- core.empresa_actual(), y no entra en el bucle de abajo porque ese recorre
-- core y esta tabla vive en plataforma.
ALTER TABLE plataforma.modulo_sucursal ENABLE ROW LEVEL SECURITY;
ALTER TABLE plataforma.modulo_sucursal FORCE  ROW LEVEL SECURITY;
CREATE POLICY rls_modulo_sucursal ON plataforma.modulo_sucursal
  FOR SELECT USING (empresa_id = core.empresa_actual());

-- Todas las demas tablas de core, por su columna empresa_id.
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
    WHERE n.nspname = 'core' AND c.relkind = 'r' AND c.relname <> 'empresa'
  LOOP
    EXECUTE format('ALTER TABLE core.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE core.%I FORCE  ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY %I ON core.%I USING (empresa_id = core.empresa_actual()) '
      'WITH CHECK (empresa_id = core.empresa_actual())',
      'rls_' || t, t);
  END LOOP;
END $$;

-- audit.evento: cada empresa ve lo suyo, y solo puede insertar.
ALTER TABLE audit.evento ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.evento FORCE  ROW LEVEL SECURITY;
CREATE POLICY rls_evento ON audit.evento
  USING      (empresa_id = core.empresa_actual())
  WITH CHECK (empresa_id = core.empresa_actual());

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


-- ---------------------------------------------------------------------
-- Sin triggers · a proposito
-- ---------------------------------------------------------------------
--
-- Aqui vivia core.tocar_actualizado_en() y el bloque que le colgaba nueve
-- triggers. Se fue con las columnas actualizado_en (H-96).
--
-- La razon: esa columna prometia "esta fila cambio a esta hora" y no podia
-- decir que cambio, ni quien, ni que decia antes -- las tres preguntas que uno
-- hace justo cuando algo salio mal. Para eso esta audit.evento, que ya tiene
-- usuario_id, accion, datos_antes y datos_despues. Y donde mas importaba no
-- servia de nada: cambiar lo que puede un rol es un INSERT o un DELETE en
-- core.rol_permiso, no el UPDATE de una columna, asi que no habia fila que
-- fechar.
--
-- Consecuencia: la base no tiene ningun trigger propio. Nada pasa por detras;
-- todo lo que ocurre esta escrito en una funcion que se puede leer y probar.
-- Si alguna vez hace falta un trigger, que sea el de la bitacora y ninguno mas.


-- ---------------------------------------------------------------------
-- Verificacion · esta consulta debe devolver CERO filas, siempre
-- ---------------------------------------------------------------------

-- Toda tabla con empresa_id tiene que tener RLS activo y forzado.
-- Ponla en la suite de tests: es la red que atrapa la tabla nueva que
-- alguien agrego sin politica.
--
--   SELECT n.nspname, c.relname
--   FROM pg_class c
--   JOIN pg_namespace n ON n.oid = c.relnamespace
--   JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
--   WHERE n.nspname IN ('core','lab','integra','plataforma')
--     AND c.relkind = 'r'
--     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
--
-- plataforma esta en la lista desde que modulo_sucursal vive ahi: tiene
-- empresa_id, asi que tiene que estar en la red. plataforma.enlace NO tiene
-- empresa_id -- tiene dos, empresa_a_id y empresa_b_id, y no es de ninguna de
-- las dos -- asi que no cae en la consulta y su ausencia de RLS es correcta.
