-- =====================================================================
-- ProLisSaas - parche: la ficha del empleado sigue a la cuenta
--
-- Para una base ya cargada. Va DESPUES de 2026-09-24_roles.sql.
--
--     psql -U postgres -d prolissaas -v ON_ERROR_STOP=1 -f 2026-09-24_ficha.sql
--
-- Se puede correr dos veces sin romper nada. ASCII puro.
--
-- QUE CAMBIA
-- ----------
-- Hasta hoy, cualquiera con usuario.administrar editaba la FICHA de
-- cualquier empleado (nombre, cargo, correo, telefono...), incluida la del
-- propietario y la de otros administradores, aunque su CUENTA estuviera
-- cerrada para el. El correo y el telefono son el camino por donde llega (o
-- va a llegar) un codigo para restablecer la clave: quien puede cambiarlos
-- puede quedarse con la cuenta.
--
-- Desde este parche la ficha se edita con la misma regla que la cuenta
-- (core.puede_tocar_cuenta):
--   - la del propietario, solo el propietario
--   - la de un administrador, solo el propietario
--   - las demas, quien tenga usuario.administrar
--   - un empleado sin cuenta (de antes), quien tenga usuario.administrar
-- Lo aplica la politica rls_empleado_editar de core.empleado, con la funcion
-- nueva core.puede_tocar_ficha(). El API pregunta antes para contestar un
-- 403 que se entienda; esto es la pared.
-- =====================================================================

BEGIN;

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

GRANT EXECUTE ON FUNCTION core.puede_tocar_ficha(bigint) TO lis_app;

DROP POLICY IF EXISTS rls_empleado_editar ON core.empleado;

CREATE POLICY rls_empleado_editar ON core.empleado
  FOR UPDATE
  USING      (empresa_id = (SELECT core.empresa_actual()) AND (SELECT core.sesion_vigente()))
  WITH CHECK (empresa_id = (SELECT core.empresa_actual())
              AND (SELECT core.sesion_vigente())
              AND (SELECT core.puede_modificar())
              AND core.puede_tocar_ficha(empleado_id));

COMMIT;

-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT polname, polcmd, pg_get_expr(polwithcheck, polrelid) AS with_check
  FROM pg_policy WHERE polrelid = 'core.empleado'::regclass ORDER BY 1;
