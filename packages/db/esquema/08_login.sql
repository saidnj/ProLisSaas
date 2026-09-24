-- =====================================================================
-- ProLisSaas - 08 - Lo que falta para poder entrar
--
-- Dos cosas:
--   1. core.buscar_credencial(), el unico punto por donde el API puede
--      leer core.usuario SIN sesion todavia puesta.
--   2. Una clave de verdad para los usuarios de prueba.
--
-- Cuando esto se de por bueno, la funcion se muda a 04_funciones.sql y
-- sus permisos a 05_privilegios.sql. Este archivo es el parche revisable.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1 - core.buscar_credencial()
--
-- EL PROBLEMA QUE RESUELVE
--
-- Al entrar todavia no hay lis.empresa_id, asi que RLS le tapa
-- core.usuario entera a lis_app: una consulta normal devuelve cero filas
-- y no hay de donde sacar el empresa_id. Es el huevo y la gallina.
--
-- SECURITY DEFINER hace que la funcion corra con los privilegios de su
-- DUENO (postgres), no de quien la llama, asi que se salta RLS. Es la
-- unica grieta, y por eso:
--
--   - devuelve UNA sola fila y nada mas que la credencial
--   - no acepta filtros libres, solo username y empresa
--   - SET search_path fijo, para que nadie pueda secuestrarla poniendo
--     una tabla falsa en un esquema anterior
--   - REVOKE de PUBLIC y GRANT solo a lis_app
--
-- H-101 - LA AMBIGUEDAD
-- El indice unico es (empresa_id, lower(username)): el username es unico
-- DENTRO de la empresa, no en el sistema. Dos laboratorios pueden tener
-- 'marlon.ochoa'. Mientras no se decida como se sabe la empresa antes de
-- entrar, p_empresa_id es opcional -- y si hay mas de una coincidencia,
-- la funcion REVIENTA en vez de elegir una. Adivinar seria peor.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.buscar_credencial(
  p_username   text,
  p_empresa_id bigint DEFAULT NULL
) RETURNS TABLE (
  usuario_id        bigint,
  empresa_id        bigint,
  username          text,
  password_hash     text,
  estado_usuario    core.estado_usuario,
  intentos_fallidos smallint,
  empleado_id       bigint,
  nombre            text,
  rol_id            bigint,
  rol               text,
  empresa           text,
  estado_empresa    core.estado_empresa,
  nivel_acceso      core.nivel_acceso,
  fecha_cierre      date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, core, public
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
      'El usuario % existe en % empresas: hace falta decir en cual entra (H-101)',
      p_username, v_cuantas
      USING ERRCODE = 'cardinality_violation';
  END IF;

  RETURN QUERY
  SELECT u.usuario_id,
         u.empresa_id,
         u.username,
         u.password_hash,
         u.estado,
         u.intentos_fallidos,
         em.empleado_id,
         em.nombres || ' ' || em.apellidos,
         r.rol_id,
         r.nombre,
         e.nombre,
         e.estado,
         e.nivel_acceso,
         e.fecha_cierre
  FROM core.usuario  u
  JOIN core.empleado em ON em.empleado_id = u.empleado_id AND em.empresa_id = u.empresa_id
  JOIN core.rol      r  ON r.rol_id       = u.rol_id      AND r.empresa_id = u.empresa_id
  JOIN core.empresa  e  ON e.empresa_id   = u.empresa_id
  WHERE lower(u.username) = lower(p_username)
    AND (p_empresa_id IS NULL OR u.empresa_id = p_empresa_id);
END
$fn$;

COMMENT ON FUNCTION core.buscar_credencial(text, bigint) IS
  'Unico punto por donde se lee core.usuario sin sesion puesta. SECURITY DEFINER a proposito: al entrar todavia no hay contexto y RLS taparia la tabla.';

-- En PostgreSQL una funcion nace con EXECUTE para PUBLIC. Esta se salta
-- RLS: no puede quedar al alcance de cualquier rol que llegue a la base.
REVOKE ALL     ON FUNCTION core.buscar_credencial(text, bigint) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.buscar_credencial(text, bigint) TO lis_app;


-- ---------------------------------------------------------------------
-- 2 - Una clave de verdad para los usuarios de prueba
--
-- Hoy password_hash dice 'SIN_CLAVE_PENDIENTE_ACTIVACION', que no es el
-- hash de nada: nadie puede entrar.
--
-- El hash de abajo es argon2id de la clave:   Prueba.2026
-- Generado y verificado con el mismo paquete que va a usar el API.
--
-- ES SOLO PARA DESARROLLO. El alta de clave de verdad todavia no existe
-- (H-17), y el estado 'pendiente_activacion' tampoco.
-- ---------------------------------------------------------------------

UPDATE core.usuario
   SET password_hash = '$argon2id$v=19$m=65536,p=4,t=3$I9fos8z9u3VbM3Dhh9PUuw$Re/mUyiAEK2M/CltF69jsy+qoBAhxUri3ZPsmWAlABA'
 WHERE password_hash = 'SIN_CLAVE_PENDIENTE_ACTIVACION';


-- ---------------------------------------------------------------------
-- Comprobacion
-- ---------------------------------------------------------------------
SELECT count(*) AS usuarios_que_ya_pueden_entrar
FROM core.usuario WHERE password_hash LIKE '$argon2id$%';

SELECT usuario_id, username, rol, empresa, estado_usuario, estado_empresa, nivel_acceso
FROM core.buscar_credencial('carla.nunez');
