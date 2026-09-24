-- =====================================================================
-- ProLisSaas · 16 · El alta de una empresa, con roles que sirven
--
-- QUE PUEDE HACER cada puesto de un laboratorio esta definido aqui, dentro
-- de crear_empresa(), y no en un par de tablas de plantillas.
--
-- Antes eran plataforma.rol_plantilla y plataforma.rol_plantilla_permiso.
-- Se quitaron por dos razones:
--
--   1. No son parte de RBAC. El modelo es usuario -> rol -> permisos, y las
--      plantillas no aparecen en esa cadena. Son SEMILLA, y una semilla que
--      se usa cada varios meses no necesita dos tablas.
--   2. Eran una segunda definicion de "que roles existen", que puede
--      desincronizarse de la realidad sin que nadie lo note.
--
-- El dia que exista una consola de operador donde se pueda cambiar "que le
-- toca a un laboratorio nuevo" sin abrir un .sql, vuelven a tener sentido.
-- Hoy no existe (H-16) y el esquema se corre desde estos archivos.
--
-- OJO: los datos maestros del alta -- que roles, que correlativos, que
-- convenio, que modulos -- estan aqui porque hay que arrancar con algo, no
-- porque esten decididos. El flujo de alta todavia no se declara a proposito:
-- se define cuando core este verificado entero, porque cualquier cambio de
-- ahi hacia atras obligaria a rehacerlo (H-91).
-- =====================================================================




-- ---------------------------------------------------------------------
-- Alta de empresa · ahora con roles que sirven
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.crear_empresa(
  p_nombre          text,
  p_rtn             text,
  p_sucursal_nombre text,
  p_sucursal_codigo text
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_empresa_id  bigint;
  v_sucursal_id bigint;
BEGIN
  INSERT INTO core.empresa (nombre, rtn, estado)
  VALUES (p_nombre, p_rtn, 'prueba')
  RETURNING empresa_id INTO v_empresa_id;

  INSERT INTO core.sucursal (empresa_id, nombre, codigo)
  VALUES (v_empresa_id, p_sucursal_nombre, upper(p_sucursal_codigo))
  RETURNING sucursal_id INTO v_sucursal_id;

  -- Toda empresa nace con el convenio "Particular" como predeterminado:
  -- ninguna orden existe sin convenio, ni siquiera la del paciente que
  -- llega directo y paga en el mostrador.
  INSERT INTO core.convenio (
    empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado
  ) VALUES (
    v_empresa_id, 'Particular', 'particular', 'particular', true
  );

  -- Correlativos: expediente por empresa, el resto por sucursal.
  INSERT INTO core.correlativo (empresa_id, sucursal_id, tipo, prefijo, ancho) VALUES
    (v_empresa_id, NULL,          'expediente', 'EXP-', 6),
    (v_empresa_id, v_sucursal_id, 'episodio',   upper(p_sucursal_codigo) || '-', 6),
    (v_empresa_id, v_sucursal_id, 'informe',    upper(p_sucursal_codigo) || 'I-', 6),
    (v_empresa_id, v_sucursal_id, 'orden',      upper(p_sucursal_codigo) || 'O-', 6),
    (v_empresa_id, v_sucursal_id, 'muestra',    upper(p_sucursal_codigo) || 'M-', 8);

  -- Los DOS modulos, no solo lab_clinico. Antes core no se encendia nunca, y
  -- como usuario_puede() ahora intersecta contra la licencia, los dieciseis
  -- permisos de core se caian y la empresa nacia sin poder hacer nada (H-27).
  INSERT INTO plataforma.modulo_sucursal
    (sucursal_id, modulo_id, empresa_id, asignado_por)
  VALUES
    (v_sucursal_id, 'core',        v_empresa_id, 'alta'),
    (v_sucursal_id, 'lab_clinico', v_empresa_id, 'alta');

  -- ------------------------------------------------------------------
  -- Los cuatro roles con los que nace la empresa, CON sus permisos.
  --
  -- Que nazcan con permisos es el punto: un rol vacio es la promesa de que
  -- alguien lo va a configurar despues, y nadie lo hace.
  --
  -- No es una jerarquia. Son cuatro puestos de un laboratorio real, y sus
  -- permisos salen de lo que cada uno hace en el flujo.
  -- ------------------------------------------------------------------

  INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema) VALUES
    (v_empresa_id, 'Administrador',
     'Configura el sistema. No es un puesto clinico.', true),
    (v_empresa_id, 'Recepcion',
     'Admite pacientes, crea ordenes, toma muestras y entrega informes.', false),
    (v_empresa_id, 'Analista',
     'Recibe muestras, las procesa y captura resultados. No los aprueba.', false),
    (v_empresa_id, 'Bioquimico',
     'Todo lo del analista, mas validar, corregir y emitir informes.', false);
  -- Solo el Administrador va marcado como de sistema. Los otros tres tambien
  -- nacen con la empresa, pero el cliente los puede renombrar o repurposear;
  -- el que no se puede quedar sin permisos es el que administra (H-90).

  -- ADMINISTRADOR · se define por EXCLUSION: todo lo que exista en el
  -- catalogo, incluidos los modulos que se agreguen despues.
  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT r.rol_id, p.permiso_id, v_empresa_id
  FROM core.rol r
  CROSS JOIN plataforma.permiso p
  WHERE r.empresa_id = v_empresa_id AND r.nombre = 'Administrador';

  -- Los tres puestos operativos, uno por uno.
  INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
  SELECT r.rol_id, t.permiso_id, v_empresa_id
  FROM (VALUES
    -- RECEPCION · la puerta de entrada y la de salida
    ('Recepcion',  'paciente.ver'),
    ('Recepcion',  'paciente.crear'),
    ('Recepcion',  'paciente.editar'),
    ('Recepcion',  'episodio.ver'),
    ('Recepcion',  'episodio.crear'),
    ('Recepcion',  'convenio.ver'),
    ('Recepcion',  'catalogo.ver'),            -- necesita ver precios para cobrar
    ('Recepcion',  'orden.ver'),
    ('Recepcion',  'orden.crear'),
    ('Recepcion',  'muestra.tomar'),           -- en un laboratorio chico, ella toma
    ('Recepcion',  'informe.entregar'),

    -- ANALISTA · procesa, pero NO aprueba. Esa separacion es el punto.
    ('Analista',   'paciente.ver'),
    ('Analista',   'episodio.ver'),
    ('Analista',   'catalogo.ver'),
    ('Analista',   'orden.ver'),
    ('Analista',   'muestra.recibir'),
    ('Analista',   'muestra.rechazar'),
    ('Analista',   'resultado.ver'),
    ('Analista',   'resultado.capturar'),

    -- BIOQUIMICO · lo del analista mas la firma
    ('Bioquimico', 'paciente.ver'),
    ('Bioquimico', 'episodio.ver'),
    ('Bioquimico', 'catalogo.ver'),
    ('Bioquimico', 'orden.ver'),
    ('Bioquimico', 'muestra.recibir'),
    ('Bioquimico', 'muestra.rechazar'),
    ('Bioquimico', 'resultado.ver'),
    ('Bioquimico', 'resultado.capturar'),
    ('Bioquimico', 'resultado.validar'),
    ('Bioquimico', 'resultado.corregir'),
    ('Bioquimico', 'valor_critico.registrar'),
    ('Bioquimico', 'informe.emitir'),
    ('Bioquimico', 'informe.corregir'),
    ('Bioquimico', 'catalogo.administrar'),    -- es quien define rangos y metodos
    ('Bioquimico', 'orden.anular')
  ) AS t(rol, permiso_id)
  JOIN core.rol r ON r.empresa_id = v_empresa_id AND r.nombre = t.rol;

  -- ------------------------------------------------------------------
  -- Lo que NINGUN rol operativo recibe, a proposito
  --
  --   paciente.fusionar      junta dos expedientes clinicos
  --   usuario.administrar    crear usuarios y cambiar permisos
  --   sucursal.administrar   configurar sedes
  --   equipo.administrar     tocar el mapeo de codigos de un analizador
  --   derivacion.solicitar   mandar datos de un paciente a otra empresa
  --   auditoria.ver          leer el rastro de todos
  --
  -- Los tiene solo el Administrador. Que no esten en recepcion ni en
  -- bioquimico no es un olvido: son acciones que cambian a quien puede hacer
  -- que, o que sacan datos de la empresa. Se dan una por una.
  -- ------------------------------------------------------------------

  RETURN v_empresa_id;
END $$;

-- En PostgreSQL una funcion nace con EXECUTE para PUBLIC. Esta crea empresas y
-- es SECURITY DEFINER: no puede quedar al alcance de cualquier rol que llegue a
-- la base. Mientras no exista la consola del operador, se ejecuta solo desde una
-- conexion privilegiada.
REVOKE ALL ON FUNCTION core.crear_empresa(text, text, text, text) FROM PUBLIC;

COMMENT ON FUNCTION core.crear_empresa IS
  'Dar de alta un cliente es una llamada, no una lista de pasos manuales que '
  'alguien puede hacer a medias. Los roles nacen con permisos porque un rol vacio '
  'es una promesa de que alguien lo configurara despues, y nadie lo hace.';


-- ---------------------------------------------------------------------
-- Consulta util para la pantalla de configuracion
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW core.v_rol_permiso AS
SELECT r.empresa_id,
       r.rol_id,
       r.nombre        AS rol,
       p.modulo_id,
       p.permiso_id,
       p.descripcion,
       (rp.rol_id IS NOT NULL) AS concedido
FROM core.rol r
CROSS JOIN plataforma.permiso p
LEFT JOIN core.rol_permiso rp
       ON rp.rol_id = r.rol_id AND rp.permiso_id = p.permiso_id;

COMMENT ON VIEW core.v_rol_permiso IS
  'La matriz completa rol x permiso, con o sin marca. Es exactamente lo que la '
  'pantalla de configuracion necesita pintar: una casilla por celda.';

GRANT SELECT ON core.v_rol_permiso TO lis_app;
