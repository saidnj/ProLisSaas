-- =====================================================================
-- ProLisSaas - parche: cerrar core.usuario por columnas
--
-- Para una base ya cargada. Va DESPUES de 2026-09-24_ficha.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-25_cerrar.sql
--
-- Se puede correr dos veces sin romper nada. ASCII puro.
--
-- QUE CAMBIA
-- ----------
-- 1. password_hash deja de ser legible para lis_app. RLS recorta filas, no
--    columnas: cualquier sesion de la empresa (Recepcion incluida) podia
--    leer los hashes de sus companeros. Nadie del lado de lis_app lo
--    necesita: el login lo compara buscar_credencial() y la activacion
--    activar_usuario(), las dos SECURITY DEFINER. Revocar solo la columna no
--    sirve mientras quede el SELECT de tabla (manual de GRANT): se quita el
--    de tabla y se dan las columnas una por una. Una columna nueva en
--    core.usuario no la ve lis_app hasta que se agregue al GRANT (falla
--    cerrado).
-- 2. intentos_fallidos y ultimo_acceso_en dejan de tener UPDATE abierto.
--    Con ese UPDATE por columna, cualquier sesion podia dejarle
--    intentos_fallidos = 4 a un companero. El login los escribe por
--    core.registrar_acceso(), SECURITY DEFINER y solo para la sesion propia
--    (espejo de login_fallido).
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- core.registrar_acceso() - la clave cuadro: se anota la hora y se limpia
-- el contador. Espejo de login_fallido(), y por la misma razon SECURITY
-- DEFINER: lis_app ya no escribe intentos_fallidos ni ultimo_acceso_en a
-- mano. Con ese UPDATE por columna abierto, cualquier sesion de la empresa
-- podia dejarle intentos_fallidos = 4 a un companero y bloquearlo con el
-- siguiente error suyo. Solo sirve para la sesion propia.
--
-- El API la llama DESPUES de leer ultimo_acceso_en, a proposito: la
-- pantalla saluda con el acceso ANTERIOR ("alguien entro anoche y no fui
-- yo"), no con "hace 0 segundos".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.registrar_acceso(p_usuario_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, core
AS $fn$
BEGIN
  IF core.usuario_actual() IS DISTINCT FROM p_usuario_id THEN
    RAISE EXCEPTION 'registrar_acceso: la sesion no es la del usuario' USING ERRCODE = '42501';
  END IF;

  UPDATE core.usuario
     SET ultimo_acceso_en = now(), intentos_fallidos = 0
   WHERE usuario_id = p_usuario_id;
END
$fn$;

REVOKE ALL     ON FUNCTION core.registrar_acceso(bigint) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.registrar_acceso(bigint) TO lis_app;

-- El UPDATE, cerrado entero (antes: GRANT UPDATE (intentos_fallidos,
-- ultimo_acceso_en)). El SELECT, por columnas y sin password_hash.
REVOKE INSERT, UPDATE ON core.usuario FROM lis_app;
REVOKE SELECT ON core.usuario FROM lis_app;

GRANT  SELECT (usuario_id, empresa_id, empleado_id, rol_id, username, estado,
               intentos_fallidos, ultimo_acceso_en, creado_en)
       ON core.usuario TO lis_app;

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion: lis_app tiene SELECT en 9 columnas (ninguna es
-- password_hash) y ningun UPDATE ni INSERT.
-- ---------------------------------------------------------------------
SELECT privilege_type, string_agg(column_name, ', ' ORDER BY column_name) AS columnas
  FROM information_schema.column_privileges
 WHERE grantee = 'lis_app' AND table_schema = 'core' AND table_name = 'usuario'
 GROUP BY 1 ORDER BY 1;
