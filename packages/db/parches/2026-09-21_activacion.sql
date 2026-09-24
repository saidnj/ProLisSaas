-- =====================================================================
-- ProLisSaas - parche: core.activacion
--
-- Para una base que se cargo ANTES de que existiera la activacion. Pone
-- lo que falta de 01_tipos.sql, 02_tablas.sql, 03_indices.sql y
-- 05_privilegios.sql, y la deja igual que una carga limpia.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-21_activacion.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- Esto es un PARCHE, no parte del esquema: la construccion limpia sigue
-- siendo 01 a 08. Cuando vuelvas a cargar de cero, este archivo sobra.
--
-- NO lo envuelvas en BEGIN/COMMIT: ALTER TYPE ... ADD VALUE no admite que
-- el valor nuevo se USE en la misma transaccion. Aqui no se usa, pero la
-- costumbre de dejarlo suelto evita sorpresas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 - El estado que faltaba  (de 01_tipos.sql)
--
-- Va BEFORE 'activo' para que el enum quede en el mismo orden que en una
-- carga limpia. El orden de un enum manda en los ORDER BY y en las
-- comparaciones, asi que no da lo mismo ponerlo al final.
-- ---------------------------------------------------------------------
ALTER TYPE core.estado_usuario ADD VALUE IF NOT EXISTS 'pendiente_activacion' BEFORE 'activo';


-- ---------------------------------------------------------------------
-- 2 - La tabla  (de 02_tablas.sql)
--
-- lis_app NO TIENE NINGUN PRIVILEGIO sobre esta tabla, ni SELECT. Solo la
-- tocan las funciones SECURITY DEFINER. Es una credencial: la aplicacion
-- no tiene por que poder pasearse por aqui.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.activacion (
  activacion_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id            bigint NOT NULL,
  empresa_id            bigint NOT NULL REFERENCES core.empresa (empresa_id),

  -- Hash argon2 del codigo, no el codigo. Si alguien lee esta tabla no puede
  -- activar cuentas ajenas. Misma historia de hash que password_hash: una
  -- sola, para que nadie dude de cual usar donde.
  codigo_hash           text   NOT NULL,

  vence_en              timestamptz NOT NULL,
  intentos_fallidos     smallint NOT NULL DEFAULT 0,

  usado_en              timestamptz,
  anulado_en            timestamptz,
  anulado_motivo        text,

  -- Quien lo genero. NULL cuando lo hizo el operador de plataforma, que no
  -- es usuario del producto (E-19).
  creado_por_usuario_id bigint,
  creado_en             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_activacion_vence CHECK (vence_en > creado_en),

  -- Usado y anulado se excluyen: o se gasto, o lo reemplazo otro.
  CONSTRAINT ck_activacion_destino
    CHECK (usado_en IS NULL OR anulado_en IS NULL),

  -- Anular exige motivo, como todo lo que se anula en este sistema.
  CONSTRAINT ck_activacion_motivo
    CHECK ((anulado_en IS NULL) = (anulado_motivo IS NULL)),

  CONSTRAINT fk_activacion_usuario
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT fk_activacion_creador
    FOREIGN KEY (creado_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE core.activacion IS
  'Codigos de un solo uso para estrenar o resetear una contrasena. El codigo '
  'se guarda hasheado y se muestra en claro UNA sola vez, al generarlo.';

COMMENT ON COLUMN core.activacion.codigo_hash IS
  'Hash argon2 del codigo. En claro no se guarda en ninguna parte: si se '
  'pierde, se genera otro.';


-- ---------------------------------------------------------------------
-- 3 - Los indices  (de 03_indices.sql)
-- ---------------------------------------------------------------------

-- Un solo codigo vivo por usuario. Generar uno nuevo obliga a anular el
-- anterior, asi que nunca hay dos que sirvan a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_activacion_viva
  ON core.activacion (usuario_id)
  WHERE usado_en IS NULL AND anulado_en IS NULL;

CREATE INDEX IF NOT EXISTS ix_activacion_usuario
  ON core.activacion (usuario_id, creado_en DESC);


-- ---------------------------------------------------------------------
-- 4 - RLS y privilegios  (de 05_privilegios.sql)
--
-- En una carga limpia estas tres politicas las pone el bucle que recorre
-- todas las tablas de core con empresa_id. Como el bucle ya corrio, aqui
-- van a mano -- identicas.
--
-- No cambian nada en la practica, porque lis_app no tiene ni un privilegio
-- sobre la tabla. Se quedan porque el dia que alguien le de un SELECT por
-- descuido, RLS ya esta puesto.
-- ---------------------------------------------------------------------
ALTER TABLE core.activacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.activacion FORCE  ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_activacion_ver    ON core.activacion;
DROP POLICY IF EXISTS rls_activacion_crear  ON core.activacion;
DROP POLICY IF EXISTS rls_activacion_editar ON core.activacion;

CREATE POLICY rls_activacion_ver ON core.activacion FOR SELECT
  USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()));

CREATE POLICY rls_activacion_crear ON core.activacion FOR INSERT
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_crear()));

CREATE POLICY rls_activacion_editar ON core.activacion FOR UPDATE
  USING (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente()) AND (SELECT core.puede_modificar()));

-- La tabla de codigos NO se toca directo, ni para leer. Solo la tocan las
-- funciones SECURITY DEFINER: si lis_app pudiera hacerle SELECT, una consulta
-- cualquiera del API podria listar los codigos vivos de toda la empresa.
REVOKE ALL ON core.activacion FROM lis_app;
REVOKE ALL ON SEQUENCE core.activacion_activacion_id_seq FROM lis_app;


-- ---------------------------------------------------------------------
-- 5 - Comprobacion
-- ---------------------------------------------------------------------
SELECT
  to_regclass('core.activacion')                                   AS tabla,
  (SELECT count(*) FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'estado_usuario'
      AND e.enumlabel = 'pendiente_activacion')                    AS enum_pendiente,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'core' AND tablename = 'activacion')        AS politicas,
  (SELECT count(*) FROM pg_indexes
    WHERE schemaname = 'core' AND tablename = 'activacion')        AS indices,
  (SELECT count(*) FROM information_schema.table_privileges
    WHERE table_schema = 'core' AND table_name = 'activacion'
      AND grantee = 'lis_app')                                     AS privilegios_lis_app;

-- Tiene que salir:
--   tabla = core.activacion · enum_pendiente = 1 · politicas = 3
--   indices = 3 (la PK y los dos de arriba) · privilegios_lis_app = 0
