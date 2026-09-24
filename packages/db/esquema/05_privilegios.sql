-- =====================================================================
-- ProLisSaas - 05 - El rol de la aplicacion, los privilegios y Row Level Security
--
-- El aislamiento real. RLS forzado en toda tabla con empresa_id, y lis_app sin
-- DELETE en ninguna parte: nada se borra, se anula con motivo.
--
-- Va despues de las funciones porque las politicas llaman a core.empresa_actual().
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 03_core.sql

REVOKE ALL ON plataforma.enlace FROM PUBLIC;

-- Se lee, no se escribe. Su politica RLS esta en 05_rls_y_funciones.sql, con
-- las demas: aqui todavia no existe core.empresa_actual().
REVOKE ALL ON plataforma.modulo_sucursal FROM PUBLIC;


-- ---------------------------------------------------------- 05_rls_y_funciones.sql

-- =====================================================================
-- ProLisSaas - 05 - Aislamiento y funciones
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

-- ON ALL TABLES alcanza tambien a las vistas, y ahora las vistas se crean
-- ANTES que esta linea. core.v_rol_permiso es de solo lectura: es la matriz
-- rol x permiso para la pantalla de configuracion. No es actualizable
-- --lleva CROSS JOIN y LEFT JOIN-- asi que escribir por ahi ya es imposible,
-- pero el privilegio se quita igual: que una vista de consulta aparezca con
-- INSERT dependia del ORDEN de los archivos, y eso no es una garantia.
REVOKE INSERT, UPDATE ON core.v_rol_permiso FROM lis_app;

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

-- core.rol, igual: la unica forma de escribirla son crear_rol, editar_rol,
-- desactivar_rol y reactivar_rol (04_funciones.sql), que exigen el permiso
-- y aplican las reglas de fijo / administrador / rol propio.
REVOKE INSERT, UPDATE ON core.rol FROM lis_app;

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

REVOKE ALL    ON FUNCTION core.crear_rol(text, text)          FROM PUBLIC;
REVOKE ALL    ON FUNCTION core.editar_rol(bigint, text, text)  FROM PUBLIC;
REVOKE ALL    ON FUNCTION core.desactivar_rol(bigint, text)    FROM PUBLIC;
REVOKE ALL    ON FUNCTION core.reactivar_rol(bigint)           FROM PUBLIC;
REVOKE ALL    ON FUNCTION core.rol_para_editar(bigint, text)   FROM PUBLIC;  -- ayudante de las tres de arriba
GRANT  EXECUTE ON FUNCTION core.crear_rol(text, text)          TO lis_app;
GRANT  EXECUTE ON FUNCTION core.editar_rol(bigint, text, text) TO lis_app;
GRANT  EXECUTE ON FUNCTION core.desactivar_rol(bigint, text)   TO lis_app;
GRANT  EXECUTE ON FUNCTION core.reactivar_rol(bigint)          TO lis_app;
GRANT  EXECUTE ON FUNCTION core.llave_texto(text)              TO lis_app;

REVOKE ALL    ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.asignar_permisos_a_rol(bigint, text[], bigint) TO lis_app;

-- La tercera pared. Se llama desde TODAS las politicas, asi que lis_app
-- necesita ejecutarla; y como es SECURITY DEFINER se le quita a PUBLIC.
REVOKE ALL     ON FUNCTION core.sesion_vigente() FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.sesion_vigente() TO lis_app;

-- Las otras dos paredes. nivel_actual() es SECURITY DEFINER (lee core.empresa,
-- que tiene RLS), asi que se le quita a PUBLIC.
REVOKE ALL     ON FUNCTION core.nivel_actual() FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.nivel_actual()    TO lis_app;

GRANT  EXECUTE ON FUNCTION core.puede_crear()     TO lis_app;

GRANT  EXECUTE ON FUNCTION core.puede_modificar() TO lis_app;
GRANT  EXECUTE ON FUNCTION core.puede_tocar_ficha(bigint) TO lis_app;

-- ---------------------------------------------------------------------
-- core.activacion - como se estrena una contrasena
-- ---------------------------------------------------------------------

-- La tabla de codigos NO se toca directo, ni para leer. Solo la tocan las
-- funciones de abajo, que corren como SECURITY DEFINER. Es una credencial:
-- si lis_app pudiera hacerle SELECT, una consulta cualquiera del API podria
-- listar los codigos vivos de toda la empresa.
REVOKE ALL ON core.activacion FROM lis_app;

REVOKE ALL ON SEQUENCE core.activacion_activacion_id_seq FROM lis_app;

-- Las dos que llama el admin CON sesion. Son SECURITY DEFINER porque lis_app
-- ya no puede escribir ni en core.usuario ni en core.activacion -- pasan a ser
-- la unica puerta, y por eso validan a mano lo que RLS validaba solo: que haya
-- sesion, el permiso, y que el empleado, el rol y el usuario objetivo sean de
-- la empresa de quien llama.
REVOKE ALL     ON FUNCTION core.crear_usuario(bigint, bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.crear_usuario(bigint, bigint, text) TO lis_app;

REVOKE ALL     ON FUNCTION core.generar_activacion(bigint, text, int) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.generar_activacion(bigint, text, int) TO lis_app;

-- Las tres que corren SIN sesion, para la pantalla de activacion. Se saltan
-- RLS, asi que se le quitan a PUBLIC antes de darselas a lis_app.
REVOKE ALL     ON FUNCTION core.buscar_activacion(text, bigint) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.buscar_activacion(text, bigint) TO lis_app;

REVOKE ALL     ON FUNCTION core.activacion_fallida(bigint, int) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.activacion_fallida(bigint, int) TO lis_app;

-- La clave que no cuadro. Escribe 'estado', que lis_app ya no puede tocar.
REVOKE ALL     ON FUNCTION core.login_fallido(bigint, int) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.login_fallido(bigint, int) TO lis_app;

-- Y el camino de vuelta: de bloqueado a activo, sin codigo nuevo.
REVOKE ALL     ON FUNCTION core.desbloquear_usuario(bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.desbloquear_usuario(bigint, text) TO lis_app;

-- El nombre con el que entra, y el empleado que manda sobre su cuenta
-- (suspender / reactivar; el trigger de core.empleado las llama).
REVOKE ALL     ON FUNCTION core.cambiar_username(bigint, text)    FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.suspender_usuario(bigint, text)   FROM PUBLIC;
REVOKE ALL     ON FUNCTION core.reactivar_usuario(bigint, text)   FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.cambiar_username(bigint, text)    TO lis_app;
GRANT  EXECUTE ON FUNCTION core.suspender_usuario(bigint, text)   TO lis_app;
GRANT  EXECUTE ON FUNCTION core.reactivar_usuario(bigint, text)   TO lis_app;

REVOKE ALL     ON FUNCTION core.activar_usuario(bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.activar_usuario(bigint, text) TO lis_app;

-- ---------------------------------------------------------------------
-- La pared que hace que todo lo anterior signifique algo
--
-- Con INSERT abierto sobre core.usuario, cualquiera del API podia crear un
-- usuario con estado 'activo' y una clave que el mismo eligio -- saltandose
-- el codigo de activacion, el permiso y F1-2 de un solo INSERT. La funcion
-- habria sido una sugerencia, no una regla.
--
-- Mismo razonamiento que cerro core.rol_permiso y plataforma.modulo_sucursal
-- en H-99: si hay una funcion que comprueba, la puerta de al lado se cierra.
--
-- Y el UPDATE se cierra ENTERO: todo entra por una funcion que comprueba:
--
--   rol_id         core.cambiar_rol()         el rol del propietario no se
--                                             toca; un administrador solo lo
--                                             nombra o retira el propietario
--   estado, clave  generar_activacion / activar_usuario / login_fallido /
--                  desbloquear_usuario / suspender_usuario / reactivar_usuario
--   username       core.cambiar_username()
--   intentos, ultimo acceso   login_fallido() / registrar_acceso(): solo la
--                             sesion propia. Antes estas dos columnas tenian
--                             UPDATE abierto "para el login", y cualquier
--                             sesion podia dejarle intentos_fallidos = 4 a un
--                             companero.
--
-- Antes el UPDATE estaba abierto entero "para que el admin edite el rol".
-- Con el rol abierto, la regla de quien nombra administradores habria sido
-- una sugerencia: un UPDATE del API y listo.
REVOKE INSERT, UPDATE ON core.usuario FROM lis_app;

REVOKE ALL     ON FUNCTION core.registrar_acceso(bigint) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.registrar_acceso(bigint) TO lis_app;

-- Y el SELECT va por columnas, SIN password_hash. Con el SELECT de tabla,
-- cualquier sesion de la empresa (Recepcion incluida) podia leer los hashes
-- de sus companeros: RLS recorta filas, no columnas. Nadie del lado de
-- lis_app necesita el hash: el login lo compara buscar_credencial() y la
-- activacion activar_usuario(), las dos SECURITY DEFINER.
--
-- OJO: revocar solo la columna no sirve (GRANT de tabla + REVOKE de columna
-- "no hace lo que uno espera", dice el manual): se quita el SELECT de la
-- tabla entera y se dan las columnas una por una. Una columna nueva en
-- core.usuario no la ve lis_app hasta que se agregue aqui: falla cerrado.
REVOKE SELECT ON core.usuario FROM lis_app;

GRANT  SELECT (usuario_id, empresa_id, empleado_id, rol_id, username, estado,
               intentos_fallidos, ultimo_acceso_en, creado_en)
       ON core.usuario TO lis_app;

REVOKE ALL     ON FUNCTION core.cambiar_rol(bigint, bigint, text) FROM PUBLIC;

GRANT  EXECUTE ON FUNCTION core.cambiar_rol(bigint, bigint, text) TO lis_app;

-- ---------------------------------------------------------------------
-- Politicas RLS
--
-- Dos cosas que parecen detalle y no lo son:
--
-- 1. Las funciones van ENVUELTAS en (SELECT ...). Asi Postgres las evalua
--    como InitPlan -- una vez por consulta -- en vez de como filtro por
--    fila. Medido sobre 300.000 filas: 51 ms sueltas contra 21 envueltas,
--    y con sesion_vigente() agregada la diferencia es 894 contra 23.
--
-- 2. Cada tabla lleva TRES politicas, no una: FOR SELECT, FOR INSERT y
--    FOR UPDATE. Es la unica forma de que core.nivel_acceso signifique algo:
--
--      nivel          SELECT   INSERT   UPDATE
--      completo         si       si       si
--      solo_cierre      si       no       si     <- terminar lo abierto
--      solo_lectura     si       no       no
--      bloqueado        no       no       no
--
--    Con una sola politica FOR ALL, 'solo_cierre' y 'solo_lectura' eran
--    palabras del enumerado que nadie hacia cumplir.
--
--    No hay FOR DELETE a proposito: sin politica, DELETE queda prohibido --
--    y ademas esta revocado. Dos candados sobre la misma puerta.
--
-- 3. Las tres funciones cuestan cero: el InitPlan las ejecuta una sola vez
--    por consulta. Cierran de paso el hueco de que el token dura ocho horas
--    y no se puede revocar.
-- ---------------------------------------------------------------------

-- La empresa se ve a si misma.
ALTER TABLE core.empresa ENABLE ROW LEVEL SECURITY;

ALTER TABLE core.empresa FORCE  ROW LEVEL SECURITY;

CREATE POLICY rls_empresa_ver ON core.empresa
  FOR SELECT USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()));

-- Sin FOR INSERT: una empresa no se crea a si misma. La crea el operador con
-- core.crear_empresa(), que es SECURITY DEFINER.
CREATE POLICY rls_empresa_editar ON core.empresa
  FOR UPDATE
  USING      (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_modificar()));

-- La licencia: cada empresa ve la suya y nada mas. FOR SELECT y sin WITH CHECK
-- porque desde el laboratorio no hay escritura posible -- solo tiene SELECT.
-- Se declara aqui y no en 03_core.sql porque alla todavia no existe
-- core.empresa_actual(), y no entra en el bucle de abajo porque ese recorre
-- core y esta tabla vive en plataforma.
ALTER TABLE plataforma.modulo_sucursal ENABLE ROW LEVEL SECURITY;

ALTER TABLE plataforma.modulo_sucursal FORCE  ROW LEVEL SECURITY;

CREATE POLICY rls_modulo_sucursal ON plataforma.modulo_sucursal
  FOR SELECT USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()));

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
      'CREATE POLICY %I ON core.%I FOR SELECT '
      'USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))',
      'rls_' || t || '_ver', t);

      EXECUTE format(
      'CREATE POLICY %I ON core.%I FOR INSERT '
      'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
      '            AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_crear()))',
      'rls_' || t || '_crear', t);

      EXECUTE format(
      'CREATE POLICY %I ON core.%I FOR UPDATE '
      'USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente())) '
      'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
      '            AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_modificar()))',
      'rls_' || t || '_editar', t);
  END LOOP;
END $$;

-- core.activacion entra sola en el bucle de arriba: tiene empresa_id. La
-- politica no le cambia nada en la practica, porque lis_app no tiene ningun
-- privilegio sobre la tabla -- pero se queda, porque el dia que alguien le de
-- un SELECT por descuido, RLS ya esta puesto.

-- ---------------------------------------------------------------------
-- core.acceso_sucursal: las sedes de un ADMINISTRADOR las mueve solo el
-- propietario. El API lo pregunta antes (core.puede_tocar_cuenta) para
-- contestar un 403 que se entienda; esto es la pared para el que no pase
-- por el API. Se reescriben las dos politicas del bucle con la condicion
-- de mas, sobre la fila que se escribe (el usuario_id de esa fila).
-- ---------------------------------------------------------------------
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
-- core.empleado: la FICHA sigue a la cuenta (core.puede_tocar_ficha). Un
-- administrador cualquiera no le cambia el correo ni el telefono al
-- propietario ni a otro administrador: por ahi llega (o va a llegar) el
-- codigo que restablece una clave. El API lo pregunta antes para contestar
-- un 403 que se entienda; esto es la pared. Misma tecnica que
-- acceso_sucursal: se reescribe la politica del bucle con la condicion de
-- mas, sobre la fila que se escribe.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS rls_empleado_editar ON core.empleado;

CREATE POLICY rls_empleado_editar ON core.empleado
  FOR UPDATE
  USING      (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente())
              AND (SELECT core.puede_modificar())
              AND core.puede_tocar_ficha(empleado_id));

-- audit.evento: cada empresa ve lo suyo, y solo puede insertar.
ALTER TABLE audit.evento ENABLE ROW LEVEL SECURITY;

ALTER TABLE audit.evento FORCE  ROW LEVEL SECURITY;

-- audit.evento es la UNICA excepcion a la tabla de niveles, y es deliberada:
-- dejar constancia de lo que paso no puede depender de si el cliente esta al
-- dia con su pago. Si alguien pudo hacer algo, la bitacora tiene que poder
-- anotarlo. Por eso el INSERT solo pide sesion vigente, sin puede_crear().
CREATE POLICY rls_evento_ver ON audit.evento
  FOR SELECT USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()));

CREATE POLICY rls_evento_anotar ON audit.evento
  FOR INSERT WITH CHECK (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()));


-- ---------------------------------------------------------- 07_identidad.sql

GRANT EXECUTE ON FUNCTION core.registrar_paciente TO lis_app;

GRANT EXECUTE ON FUNCTION core.anotar_referencia TO lis_app;

GRANT EXECUTE ON FUNCTION core.anular_referencia TO lis_app;

GRANT EXECUTE ON FUNCTION public.unaccent_simple TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_nombre(text, text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_documento(text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_telefono(text) TO lis_app;
GRANT EXECUTE ON FUNCTION core.llave_correo(text) TO lis_app;

GRANT EXECUTE ON FUNCTION core.posibles_duplicados TO lis_app;


-- ---------------------------------------------------------- 08_enlace_y_mensaje.sql

REVOKE ALL ON FUNCTION plataforma.crear_enlace(bigint, bigint, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION core.mis_enlaces TO lis_app;

REVOKE ALL ON FUNCTION core.entregar(bigint, bigint, core.tipo_mensaje, jsonb, bigint, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION core.entregar TO lis_app;


-- ---------------------------------------------------------- 14_lab_rls_y_funciones.sql

-- =====================================================================
-- ProLisSaas - 14 - Aislamiento y funciones de la rama
--
-- El mismo patron del nucleo, aplicado a lab e integra sin una sola
-- excepcion. Y las tres funciones que hacen que "el rango se copia al
-- resultado" no dependa de que alguien se acuerde.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Permisos del rol de aplicacion
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA lab, integra TO lis_app;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA lab     TO lis_app;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA integra TO lis_app;

REVOKE DELETE ON ALL TABLES IN SCHEMA lab     FROM lis_app;

REVOKE DELETE ON ALL TABLES IN SCHEMA integra FROM lis_app;

-- ---------------------------------------------------------------------
-- RLS - identico al nucleo, sin excepciones
-- ---------------------------------------------------------------------
DO $$
DECLARE
  s text;
  t text;
BEGIN
  FOREACH s IN ARRAY ARRAY['lab','integra'] LOOP
    FOR t IN
      SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
      WHERE n.nspname = s AND c.relkind = 'r'
    LOOP
      EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', s, t);
      EXECUTE format('ALTER TABLE %I.%I FORCE  ROW LEVEL SECURITY', s, t);
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR SELECT '
        'USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))',
        'rls_' || t || '_ver', s, t);

      EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR INSERT '
        'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
        '            AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_crear()))',
        'rls_' || t || '_crear', s, t);

      EXECUTE format(
        'CREATE POLICY %I ON %I.%I FOR UPDATE '
        'USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente())) '
        'WITH CHECK (empresa_id = (SELECT core.empresa_actual()) '
        '            AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_modificar()))',
        'rls_' || t || '_editar', s, t);
    END LOOP;
  END LOOP;
END $$;


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
-- donde esta parado quien pregunta (core.usuario_puede). Con eso el
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


-- ---------------------------------------------------------- 16_roles.sql

-- En PostgreSQL una funcion nace con EXECUTE para PUBLIC. Esta crea empresas y
-- es SECURITY DEFINER: no puede quedar al alcance de cualquier rol que llegue a
-- la base. Mientras no exista la consola del operador, se ejecuta solo desde una
-- conexion privilegiada.
REVOKE ALL ON FUNCTION core.crear_empresa(text, text, text, text) FROM PUBLIC;

GRANT SELECT ON core.v_rol_permiso TO lis_app;


-- ---------------------------------------------------------- 17_comercial.sql

-- ---------------------------------------------------------------------
-- La frontera, hecha cumplir con permisos
--
-- lis_app no recibe nada. Ni USAGE sobre el esquema, asi que la aplicacion
-- del laboratorio no puede ni nombrar estas tablas. Es el mismo mecanismo
-- con el que plataforma.persona esta protegida.
-- ---------------------------------------------------------------------
REVOKE ALL ON SCHEMA comercial FROM PUBLIC;

REVOKE ALL ON ALL TABLES IN SCHEMA comercial FROM PUBLIC;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA comercial FROM PUBLIC;

