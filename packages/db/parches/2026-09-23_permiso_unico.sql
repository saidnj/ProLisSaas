-- =====================================================================
-- ProLisSaas - parche: UNA sola comprobacion de permiso
--
-- Para una base ya cargada. Va DESPUES de 2026-09-22_rls_permisos.sql
-- (reescribe las mismas politicas) y de 2026-09-22_propietario.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-23_permiso_unico.sql
--
-- Se puede correr dos veces sin romper nada. Corre entero en una
-- transaccion.
--
-- QUE CAMBIA
-- ----------
-- Habia dos formas de preguntar "tiene el permiso X": la floja
-- (usuario_puede: modulo encendido en ALGUNA sede) y la estricta
-- (usuario_puede_aqui / usuario_puede_en: encendido en la sede del
-- contexto). El front preguntaba por sede y el API por empresa. Queda UNA:
--
--   core.usuario_puede(permiso, usuario?)        el rol lo tiene Y el modulo
--                                                 esta encendido en la sede
--                                                 del contexto. Sin sede: false
--   core.usuario_puede_alguno(permisos[], usuario?)  la misma regla para una
--                                                 lista (politicas de INSERT/UPDATE)
--   core.exigir_permiso(permiso, usuario?)       la que lanza
--
-- Se van: usuario_puede_en, usuario_puede_aqui, exigir_permiso_aqui. Las 60
-- politicas de las tablas operativas se reescriben con usuario_puede().
--
-- CONSECUENCIA: toda llamada a usuario_puede() necesita lis.sucursal_id en
-- el contexto. El API lo pone en toda ruta que no sea de entrar, y
-- scripts/codigo.mjs lo pone antes de generar el codigo (version del
-- 2026-09-23 o posterior).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1 · Soltar las politicas que dependen de las funciones viejas
--     (el bloque de abajo las vuelve a crear con la nueva)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT schemaname, tablename, policyname FROM pg_policies
            WHERE (qual LIKE '%usuario_puede%' OR with_check LIKE '%usuario_puede%') LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2 · Las funciones viejas
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS core.usuario_puede_aqui(text);
DROP FUNCTION IF EXISTS core.exigir_permiso_aqui(text);
DROP FUNCTION IF EXISTS core.usuario_puede_en(text, bigint, bigint);
DROP FUNCTION IF EXISTS core.usuario_puede_alguno(text[]);

-- ---------------------------------------------------------------------
-- 3 · La regla unica (04_funciones.sql). Copiado tal cual de ahi.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 4 · Las politicas de las tablas operativas, otra vez (05_privilegios.sql)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- esquema  tabla                  para VER            para CREAR                                   para TOCAR (cualquiera de)
      ('core', 'paciente',            'paciente.ver',     ARRAY['paciente.crear'],                     ARRAY['paciente.editar','paciente.fusionar']),
      ('core', 'paciente_referencia', 'paciente.ver',     ARRAY['paciente.editar'],                    ARRAY['paciente.editar']),
      ('core', 'episodio',            'episodio.ver',     ARRAY['episodio.crear'],                     ARRAY['episodio.anular']),
      ('core', 'convenio',            'convenio.ver',     ARRAY['convenio.administrar'],               ARRAY['convenio.administrar']),
      -- No existe informe.ver: el informe se ve con el episodio al que pertenece.
      ('core', 'informe',             'episodio.ver',     ARRAY['informe.emitir'],                     ARRAY['informe.corregir','informe.entregar']),
      ('core', 'informe_version',     'episodio.ver',     ARRAY['informe.emitir','informe.corregir'],  ARRAY['informe.emitir','informe.corregir']),
      ('core', 'entrega',             'episodio.ver',     ARRAY['informe.entregar'],                   ARRAY['informe.entregar']),
      -- El catalogo del laboratorio: lo ve quien arma ordenes, lo toca quien lo administra.
      ('lab',  'area',                'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'tipo_muestra',        'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'analito',             'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'prueba',              'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'prueba_analito',      'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'rango_referencia',    'catalogo.ver',     ARRAY['catalogo.administrar'],               ARRAY['catalogo.administrar']),
      ('lab',  'precio_prueba',       'catalogo.ver',     ARRAY['catalogo.administrar','convenio.administrar'], ARRAY['catalogo.administrar','convenio.administrar']),
      -- La operacion.
      ('lab',  'orden',               'orden.ver',        ARRAY['orden.crear'],                        ARRAY['orden.anular']),
      ('lab',  'orden_prueba',        'orden.ver',        ARRAY['orden.crear'],                        ARRAY['orden.crear','orden.anular']),
      ('lab',  'muestra',             'orden.ver',        ARRAY['muestra.tomar'],                      ARRAY['muestra.recibir','muestra.rechazar']),
      ('lab',  'muestra_rechazo',     'orden.ver',        ARRAY['muestra.rechazar'],                   ARRAY['muestra.rechazar']),
      ('lab',  'resultado',           'resultado.ver',    ARRAY['resultado.capturar'],                 ARRAY['resultado.capturar','resultado.validar','resultado.corregir']),
      ('lab',  'aviso_valor_critico', 'resultado.ver',    ARRAY['valor_critico.registrar'],            ARRAY['valor_critico.registrar'])
    ) AS t(esquema, tabla, ver, crear, editar)
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 'rls_' || r.tabla || '_ver',    r.esquema, r.tabla);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 'rls_' || r.tabla || '_crear',  r.esquema, r.tabla);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 'rls_' || r.tabla || '_editar', r.esquema, r.tabla);

    -- VER: de mi empresa, sesion vigente, y el permiso de ver EN ESTA SEDE.
    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR SELECT '
      'USING (empresa_id = (SELECT core.empresa_actual()) '
      '       AND (SELECT core.sesion_vigente()) '
      '       AND (SELECT core.usuario_puede(%L)))',
      'rls_' || r.tabla || '_ver', r.esquema, r.tabla, r.ver);

    -- CREAR: lo anterior mas el nivel comercial y el permiso de crear.
    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR INSERT '
      'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
      '            AND (SELECT core.sesion_vigente()) '
      '            AND (SELECT core.puede_crear()) '
      '            AND (SELECT core.usuario_puede_alguno(%L)))',
      'rls_' || r.tabla || '_crear', r.esquema, r.tabla, r.crear);

    -- TOCAR: para alcanzar la fila hace falta VERLA (USING); para dejarla
    -- cambiada hace falta alguno de los permisos de tocar (WITH CHECK).
    EXECUTE format(
      'CREATE POLICY %I ON %I.%I FOR UPDATE '
      'USING (empresa_id = (SELECT core.empresa_actual()) '
      '       AND (SELECT core.sesion_vigente()) '
      '       AND (SELECT core.usuario_puede(%L))) '
      'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
      '            AND (SELECT core.sesion_vigente()) '
      '            AND (SELECT core.puede_modificar()) '
      '            AND (SELECT core.usuario_puede_alguno(%L)))',
      'rls_' || r.tabla || '_editar', r.esquema, r.tabla, r.ver, r.editar);
  END LOOP;
END $$;

COMMIT;


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core'
      AND p.proname IN ('usuario_puede_aqui','exigir_permiso_aqui','usuario_puede_en'))  AS funciones_viejas,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core' AND p.proname = 'usuario_puede_alguno'
      AND pg_get_function_arguments(p.oid) LIKE '%p_usuario_id%')                       AS alguno_con_usuario,
  (SELECT count(*) FROM pg_policies
    WHERE qual LIKE '%core.usuario_puede(%' OR with_check LIKE '%usuario_puede%')        AS politicas_con_permiso,
  (SELECT count(*) FROM pg_policies WHERE qual LIKE '%usuario_puede_aqui%')             AS politicas_viejas;

-- Tiene que salir: funciones_viejas = 0 · alguno_con_usuario = 1 ·
--   politicas_con_permiso = 60 · politicas_viejas = 0

-- Y la regla, en vivo: sin sede en el contexto nadie puede nada.
SELECT core.usuario_puede('paciente.ver') AS sin_sede_es_false;
