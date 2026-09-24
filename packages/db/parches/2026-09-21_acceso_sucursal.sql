-- =====================================================================
-- ProLisSaas - parche: quitar acceso a una sucursal sin borrar la fila
--
-- Para una base ya cargada. Agrega a core.acceso_sucursal lo que le falta
-- de 02_tablas.sql y la deja igual que una carga limpia.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-21_acceso_sucursal.sql
--
-- Se puede correr dos veces sin romper nada.
--
-- POR QUE HACE FALTA
-- ------------------
-- DELETE esta revocado en todo el esquema core, y esta tabla no tenia como
-- marcar un acceso retirado. O sea que se podia dar acceso a una sede pero
-- nunca quitarlo. Ahora quitarlo es un UPDATE con motivo, como todo lo demas.
-- =====================================================================

ALTER TABLE core.acceso_sucursal
  ADD COLUMN IF NOT EXISTS activo          boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS retirado_en     timestamptz,
  ADD COLUMN IF NOT EXISTS retirado_motivo text;

-- Los dos CHECK. Se tiran primero por si el parche ya corrio: ADD CONSTRAINT
-- no tiene IF NOT EXISTS.
ALTER TABLE core.acceso_sucursal DROP CONSTRAINT IF EXISTS ck_acceso_retirado;
ALTER TABLE core.acceso_sucursal DROP CONSTRAINT IF EXISTS ck_acceso_motivo;

-- Retirar deja constancia de cuando.
ALTER TABLE core.acceso_sucursal
  ADD CONSTRAINT ck_acceso_retirado CHECK (activo OR retirado_en IS NOT NULL);

-- Y exige motivo, como todo lo que se anula en este sistema.
ALTER TABLE core.acceso_sucursal
  ADD CONSTRAINT ck_acceso_motivo
    CHECK ((retirado_en IS NULL) = (retirado_motivo IS NULL));

COMMENT ON TABLE core.acceso_sucursal IS
  'En que sedes puede pararse cada usuario. Se da con un INSERT y se quita '
  'con un UPDATE que pone activo=false con motivo: la fila nunca se borra.';

COMMENT ON COLUMN core.acceso_sucursal.activo IS
  'false = el acceso se retiro. Las consultas de sesion filtran por esto; '
  'un usuario sin ninguna sede activa no puede entrar a ningun lado.';


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM information_schema.columns
    WHERE table_schema='core' AND table_name='acceso_sucursal'
      AND column_name IN ('activo','retirado_en','retirado_motivo'))  AS columnas_nuevas,
  (SELECT count(*) FROM pg_constraint
    WHERE conrelid = 'core.acceso_sucursal'::regclass
      AND conname IN ('ck_acceso_retirado','ck_acceso_motivo'))       AS checks,
  (SELECT count(*) FROM core.acceso_sucursal WHERE activo)            AS accesos_activos;

-- Tiene que salir: columnas_nuevas = 3 · checks = 2
