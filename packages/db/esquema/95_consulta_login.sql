-- =====================================================================
-- ProLisSaas - 95 - La consulta de inicio de sesion
--
-- No es una consulta, son dos, y el orden importa:
--
--   PASO 1  busca la credencial.  Todavia NO hay sesion, asi que NO puede
--           correr con lis_app: sin lis.empresa_id, RLS le tapa la tabla
--           core.usuario entera y devuelve cero filas. Corre por fuera,
--           en la funcion SECURITY DEFINER del final del archivo.
--
--   PASO 2  arma la sesion.  La clave ya se verifico en la aplicacion.
--           Aqui si corre lis_app, con el contexto puesto, y todo lo que
--           devuelve ya viene recortado por RLS.
--
-- La clave NUNCA se compara en SQL. El PASO 1 devuelve el hash y la
-- aplicacion lo verifica (argon2id / bcrypt). Comparar en SQL mete la
-- clave en el log de consultas y abre la puerta a comparacion por tiempo.
--
-- Probado contra la base cargada con 07_datos_prueba.sql.
-- =====================================================================


-- ---------------------------------------------------------------------
-- PASO 1 - buscar la credencial
--
-- $1 = username    $2 = empresa_id
--
-- El segundo parametro no sobra. El indice unico es
--   uq_usuario_username (empresa_id, lower(username))
-- o sea que el username es unico DENTRO de la empresa, no en el sistema.
-- Hoy mismo dos laboratorios distintos pueden tener 'marlon.ochoa', y sin
-- empresa_id la consulta devuelve dos filas: no se sabe quien entro.
-- Como se averigua la empresa antes de entrar es cosa sin decidir (H-101).
-- ---------------------------------------------------------------------
SELECT
  u.usuario_id,
  u.empresa_id,
  u.username,
  u.password_hash,          -- se verifica en la aplicacion, no aqui
  u.estado             AS estado_usuario,
  u.intentos_fallidos,
  e.nombre             AS empresa,
  e.estado             AS estado_empresa,
  e.nivel_acceso,
  e.fecha_cierre
FROM core.usuario u
JOIN core.empresa e ON e.empresa_id = u.empresa_id
WHERE lower(u.username) = lower('marlon.ochoa')
  AND u.empresa_id      = 1;

-- Lo que la aplicacion decide con esa fila, en este orden:
--
--   estado_empresa  <> 'activa' y <> 'prueba'   -> no entra
--   fecha_cierre    ya paso                     -> no entra
--   estado_usuario  = 'bloqueado'               -> no entra
--   estado_usuario  = 'suspendido'              -> no entra
--   el hash no cuadra                           -> +1 intentos_fallidos
--   intentos_fallidos pasa del tope             -> estado = 'bloqueado'
--
-- nivel_acceso NO decide si entra: decide que puede hacer adentro
-- ('solo_lectura' entra y no escribe). Hoy ninguna funcion lo lee - E-20
-- lo exige y no existe el mecanismo (H-100).


-- ---------------------------------------------------------------------
-- PASO 2 - armar la sesion
--
-- Todo en una sola ida a la base. Devuelve un solo jsonb: la persona, la
-- empresa, el rol, y las sucursales donde puede entrar CON los permisos
-- que de verdad le sirven en cada una.
--
-- Los permisos van por sucursal a proposito. El rol dice lo que se quiso
-- dar; plataforma.modulo_sucursal dice lo que la empresa paga en esa
-- sede. Lo que sirve es la interseccion, y cambia de sede en sede: el
-- mismo rol de 30 permisos rinde 30 donde lab_clinico esta encendido y
-- 16 donde esta apagado. Una lista plana de permisos mentiria.
-- ---------------------------------------------------------------------
BEGIN;
SET LOCAL ROLE lis_app;
SET LOCAL lis.empresa_id = '1';   -- del PASO 1
SET LOCAL lis.usuario_id = '7';   -- del PASO 1

SELECT jsonb_build_object(
  'usuario', jsonb_build_object(
      'usuario_id',       u.usuario_id,
      'username',         u.username,
      'estado',           u.estado,
      'ultimo_acceso_en', u.ultimo_acceso_en),

  'persona', jsonb_build_object(
      'empleado_id', em.empleado_id,
      'nombre',      em.nombres || ' ' || em.apellidos,
      'cargo',       em.cargo,
      'correo',      em.correo,
      'colegiacion', em.numero_colegiacion,
      'activo',      em.activo),

  'empresa', jsonb_build_object(
      'empresa_id',   e.empresa_id,
      'nombre',       e.nombre,
      'comercial',    e.nombre_comercial,
      'estado',       e.estado,
      'nivel_acceso', e.nivel_acceso,
      'fecha_cierre', e.fecha_cierre),

  'rol', jsonb_build_object(
      'rol_id',     r.rol_id,
      'nombre',     r.nombre,
      'es_sistema', r.es_sistema),

  'sucursales', (
      SELECT coalesce(jsonb_agg(x ORDER BY x->>'codigo'), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
                 'sucursal_id', s.sucursal_id,
                 'codigo',      s.codigo,
                 'nombre',      s.nombre,
                 'activa',      s.activo,

                 -- lo que la empresa paga en esta sede
                 'modulos', (
                    SELECT coalesce(jsonb_agg(ms.modulo_id ORDER BY ms.modulo_id), '[]'::jsonb)
                    FROM plataforma.modulo_sucursal ms
                    WHERE ms.sucursal_id = s.sucursal_id
                      AND ms.activo),

                 -- rol x licencia: lo unico que de verdad puede hacer aqui
                 'permisos', (
                    SELECT coalesce(jsonb_agg(DISTINCT rp.permiso_id), '[]'::jsonb)
                    FROM core.rol_permiso rp
                    JOIN plataforma.permiso p
                      ON p.permiso_id = rp.permiso_id
                    JOIN plataforma.modulo_sucursal ms
                      ON ms.modulo_id   = p.modulo_id
                     AND ms.sucursal_id = s.sucursal_id
                     AND ms.activo
                    WHERE rp.rol_id     = u.rol_id
                      AND rp.empresa_id = u.empresa_id)
               ) AS x
        FROM core.acceso_sucursal a
        JOIN core.sucursal s
          ON s.sucursal_id = a.sucursal_id
         AND s.empresa_id  = a.empresa_id
        WHERE a.usuario_id = u.usuario_id
      ) q)
) AS sesion
FROM core.usuario  u
JOIN core.empleado em ON em.empleado_id = u.empleado_id AND em.empresa_id = u.empresa_id
JOIN core.empresa  e  ON e.empresa_id   = u.empresa_id
JOIN core.rol      r  ON r.rol_id       = u.rol_id      AND r.empresa_id = u.empresa_id
WHERE u.usuario_id = core.usuario_actual();

COMMIT;


-- ---------------------------------------------------------------------
-- PASO 3 - dejar constancia
--
-- Va dentro de la misma transaccion del PASO 2, con el contexto ya puesto.
-- lis_app tiene UPDATE sobre core.usuario, asi que esto corre tal cual.
-- ---------------------------------------------------------------------

-- entro bien:
UPDATE core.usuario
   SET ultimo_acceso_en  = now(),
       intentos_fallidos = 0
 WHERE usuario_id = core.usuario_actual();

-- clave equivocada (empresa_id ya se sabe del PASO 1):
UPDATE core.usuario
   SET intentos_fallidos = intentos_fallidos + 1,
       estado = CASE WHEN intentos_fallidos + 1 >= 5 THEN 'bloqueado'::core.estado_usuario
                     ELSE estado END
 WHERE usuario_id = core.usuario_actual();


-- =====================================================================
-- Lo que hace falta para que esto sea de verdad el login
-- =====================================================================
--
-- 1. La funcion del PASO 1.  Hoy ese SELECT solo corre con una conexion
--    privilegiada. Falta envolverlo en una funcion SECURITY DEFINER que
--    sea lo unico que la aplicacion puede llamar sin sesion:
--
--      CREATE FUNCTION core.buscar_credencial(p_username text, p_empresa_id bigint)
--      RETURNS TABLE (...) LANGUAGE sql STABLE SECURITY DEFINER AS $$ ... $$;
--      REVOKE ALL ON FUNCTION core.buscar_credencial FROM PUBLIC;
--      GRANT EXECUTE ON FUNCTION core.buscar_credencial TO lis_app;
--
--    Sin eso la API necesita un rol que se salte RLS, y ese rol tambien
--    se salta todo lo demas.
--
-- 2. Como se sabe la empresa antes de entrar (H-101).
--
-- 3. password_hash hoy dice 'SIN_CLAVE_PENDIENTE_ACTIVACION', que no es
--    el hash de nada: nadie puede entrar todavia. Falta el alta de clave,
--    y el estado 'pendiente_activacion' no existe en core.estado_usuario
--    (H-17).
--
-- 4. El tope de intentos (aqui 5) no esta en ninguna tabla de
--    configuracion. Esta escrito a mano en la consulta.
--
-- 5. Ni el intento fallido ni el bloqueo escriben en audit.evento.
-- =====================================================================
