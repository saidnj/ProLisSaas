-- =====================================================================
-- ProLisSaas - parche: el permiso dentro de las politicas RLS
--
-- Para una base ya cargada. Es EXACTAMENTE lo que se agrego a
-- 04_funciones.sql y 05_privilegios.sql -- este archivo se genera de
-- esos dos, no se escribe a mano.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-22_rls_permisos.sql
--
-- Se puede correr dos veces sin romper nada: las funciones son CREATE OR
-- REPLACE y las politicas se tiran antes de crearse.
--
-- DESPUES DE ESTO, toda peticion que toque una tabla operativa necesita
-- la sede en el contexto. El front ya la manda (eligio sede al entrar);
-- si probas con curl, el token tiene que ser el de despues de
-- POST /auth/sucursal, no el del login.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1 - Las funciones  (de 04_funciones.sql)
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- LA SEDE DEL CONTEXTO, Y LOS PERMISOS "AQUI"
--
-- conSesion() pone lis.sucursal_id junto a lis.empresa_id, sacado del
-- token firmado. Estas funciones lo leen. Es lo que H-100 dejaba abierto:
-- la sucursal viaja en el contexto y ya hay quien la use.
--
-- Como llega el permiso hasta aqui:
--
--   sede del contexto  ->  plataforma.modulo_sucursal  ->  que modulos tiene
--   modulos            ->  plataforma.permiso          ->  que permisos existen ahi
--   rol del usuario    ->  core.rol_permiso            ->  cuales tiene el rol
--
-- La interseccion es lo que de verdad puede hacer PARADO EN ESA SEDE. Un
-- permiso de lab_clinico no sirve en una sede que no lo contrato, aunque el
-- rol lo traiga.
--
-- Sin sede en el contexto la respuesta es FALSE, no "la floja". Las
-- politicas RLS de las tablas operativas dependen de esto: si cayera a la
-- version de "encendido en alguna sede", una consulta sin sede veria mas de
-- lo que debe. La API exige la sede en toda ruta que no sea de entrar.
-- ---------------------------------------------------------------------
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

-- Cualquiera de la lista, en la sede actual. Es la base: usuario_puede_aqui()
-- es esta con un solo elemento. Una sola consulta, no una por permiso.
CREATE OR REPLACE FUNCTION core.usuario_puede_alguno(p_permisos text[])
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
       WHERE u.usuario_id = core.usuario_actual()
         AND u.estado = 'activo'
         AND rp.permiso_id = ANY (p_permisos)
     )
$$;

COMMENT ON FUNCTION core.usuario_puede_alguno IS
  'true si el usuario tiene AL MENOS UNO de los permisos, y su modulo esta encendido '
  'en la sede del contexto. Para las politicas de UPDATE, donde una tabla admite '
  'varias acciones. Sin sede en el contexto devuelve false.';

CREATE OR REPLACE FUNCTION core.usuario_puede_aqui(p_permiso_id text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT core.usuario_puede_alguno(ARRAY[p_permiso_id])
$$;

COMMENT ON FUNCTION core.usuario_puede_aqui IS
  'usuario_puede_en() con la sede sacada del contexto. Es la que usan las politicas '
  'RLS de las tablas operativas. Sin sede devuelve false.';

-- La que lanza, para adentro de las funciones que ocurren en una sede.
CREATE OR REPLACE FUNCTION core.exigir_permiso_aqui(p_permiso_id text)
RETURNS void
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF current_user <> 'lis_app' THEN
    RETURN;
  END IF;

  IF core.sucursal_actual() IS NULL THEN
    RAISE EXCEPTION 'Hace falta elegir una sede antes de esta operacion'
      USING ERRCODE = 'insufficient_privilege', HINT = 'POST /auth/sucursal';
  END IF;

  IF NOT core.usuario_puede_aqui(p_permiso_id) THEN
    RAISE EXCEPTION 'El usuario no tiene el permiso % en esta sede', p_permiso_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

COMMENT ON FUNCTION core.exigir_permiso_aqui IS
  'exigir_permiso() estricta: el permiso Y el modulo encendido en la sede del contexto. '
  'Para lo que ocurre en una sede -- ordenes, muestras, resultados.';



-- ---------------------------------------------------------------------
-- 2 - Las politicas  (de 05_privilegios.sql)
-- ---------------------------------------------------------------------

-- =====================================================================
-- EL PERMISO, DENTRO DE LAS POLITICAS
--
-- Los dos bucles de arriba le pusieron a toda tabla con empresa_id tres
-- politicas que preguntan lo mismo: "de mi empresa, con sesion vigente, y
-- el nivel comercial lo permite". Eso aisla al inquilino. No dice nada de
-- QUIEN dentro del inquilino puede ver o tocar que.
--
-- Esta segunda pasada, solo para las tablas OPERATIVAS, reemplaza esas
-- politicas por unas que ademas exigen el permiso -- calculado en la sede
-- donde esta parado quien pregunta (core.usuario_puede_aqui). Con eso el
-- permiso deja de depender de que cada endpoint se acuerde de llamar a
-- exigir_permiso(): lo pone Postgres en toda consulta, la escriba quien la
-- escriba. Es la misma razon por la que el empresa_id esta en la politica
-- y no en un WHERE.
--
-- LA LISTA ES LA REGLA. Se lee de un vistazo que hace falta para ver, para
-- crear y para tocar cada tabla. Una tabla operativa nueva se agrega aqui;
-- si no se agrega, se queda con la politica generica (empresa + sesion) y
-- la prueba 91 no la cubre -- que es el aviso.
--
-- LO QUE NO ESTA, A PROPOSITO: sucursal, empleado, usuario, rol,
-- rol_permiso, acceso_sucursal, correlativo, mensaje. Son directorios que
-- toda la empresa lee: abrirSesion() los consulta ANTES de que haya sede
-- elegida y sin permiso especial. Si core.empleado pidiera
-- usuario.administrar, Recepcion no podria ni ver su propio nombre al
-- entrar. El permiso para ADMINISTRARLOS sigue en las funciones y en la API.
--
-- Cada llamada va envuelta en (SELECT ...): asi corre una vez por consulta
-- y no una vez por fila. Medido: 21 ms contra 894 ms sobre 300.000 filas.
-- =====================================================================
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
      '       AND (SELECT core.usuario_puede_aqui(%L)))',
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
      '       AND (SELECT core.usuario_puede_aqui(%L))) '
      'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
      '            AND (SELECT core.sesion_vigente()) '
      '            AND (SELECT core.puede_modificar()) '
      '            AND (SELECT core.usuario_puede_alguno(%L)))',
      'rls_' || r.tabla || '_editar', r.esquema, r.tabla, r.ver, r.editar);
  END LOOP;
END $$;



-- ---------------------------------------------------------------------
-- 3 - Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'core'
      AND p.proname IN ('sucursal_actual','usuario_puede_aqui','usuario_puede_alguno','exigir_permiso_aqui'))
                                                                    AS funciones_nuevas,
  (SELECT count(*) FROM pg_policies
    WHERE qual LIKE '%usuario_puede_aqui%' OR with_check LIKE '%usuario_puede_alguno%')
                                                                    AS politicas_con_permiso;

-- Tiene que salir:  funciones_nuevas = 4  ·  politicas_con_permiso = 60

