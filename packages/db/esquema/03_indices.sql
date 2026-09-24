-- =====================================================================
-- ProLisSaas - 03 - Indices
--
-- Los que sostienen una pantalla llevan su nombre en el comentario. Varios son
-- parciales: el WHERE es parte de la regla, no una optimizacion.
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 03_core.sql

-- La tarea diaria de cierre busca por aqui. Con veinte clientes da igual;
-- se anota ahora para que no de lo mismo despues.
CREATE INDEX ix_empresa_cierre ON core.empresa (estado, fecha_cierre)
  WHERE fecha_cierre IS NOT NULL;

CREATE UNIQUE INDEX uq_empresa_rtn ON core.empresa (rtn) WHERE rtn IS NOT NULL;

-- La misma ruta no se repite mientras este vigente. Hay que normalizar el
-- orden porque (A1,B2) y (B2,A1) son la misma ruta.
CREATE UNIQUE INDEX uq_enlace_ruta ON plataforma.enlace (
  least(sucursal_a_id, sucursal_b_id),
  greatest(sucursal_a_id, sucursal_b_id)
) WHERE vigente_hasta IS NULL;

CREATE INDEX ix_enlace_a ON plataforma.enlace (empresa_a_id, sucursal_a_id)
  WHERE vigente_hasta IS NULL;

CREATE INDEX ix_enlace_b ON plataforma.enlace (empresa_b_id, sucursal_b_id)
  WHERE vigente_hasta IS NULL;

-- Username unico por empresa. En minusculas, comparado sin distinguir mayusculas.
CREATE UNIQUE INDEX uq_usuario_username
  ON core.usuario (empresa_id, lower(username));

-- Un solo codigo vivo por usuario. Generar uno nuevo obliga a anular el
-- anterior, asi que nunca hay dos que sirvan a la vez.
CREATE UNIQUE INDEX uq_activacion_viva
  ON core.activacion (usuario_id)
  WHERE usado_en IS NULL AND anulado_en IS NULL;

CREATE INDEX ix_activacion_usuario
  ON core.activacion (usuario_id, creado_en DESC);

CREATE UNIQUE INDEX uq_correlativo
  ON core.correlativo (empresa_id, tipo, coalesce(sucursal_id, 0));

-- EMPLEADO: lo que identifica a una persona no se repite dentro de la
-- empresa, escrito como se escriba (las llaves de 01_tipos.sql deciden
-- cuando dos textos son el mismo dato). El nombre es la suma nombres +
-- apellidos; lo demas solo cuenta cuando esta puesto. El API pregunta
-- ANTES de escribir para decir quien lo tiene (empleados.service.ts);
-- estos indices son la garantia cuando dos guardan a la vez.
CREATE UNIQUE INDEX uq_empleado_nombre
  ON core.empleado (empresa_id, core.llave_nombre(nombres, apellidos));

CREATE UNIQUE INDEX uq_empleado_documento
  ON core.empleado (empresa_id, core.llave_documento(documento))
  WHERE core.llave_documento(documento) IS NOT NULL;

CREATE UNIQUE INDEX uq_empleado_telefono
  ON core.empleado (empresa_id, core.llave_telefono(telefono))
  WHERE core.llave_telefono(telefono) IS NOT NULL;

CREATE UNIQUE INDEX uq_empleado_correo
  ON core.empleado (empresa_id, core.llave_correo(correo))
  WHERE core.llave_correo(correo) IS NOT NULL;

CREATE UNIQUE INDEX uq_empleado_colegiacion
  ON core.empleado (empresa_id, core.llave_documento(numero_colegiacion))
  WHERE core.llave_documento(numero_colegiacion) IS NOT NULL;

-- ROL: el nombre no se repite dentro de la empresa, escrito como se
-- escriba ("Recepcion" = "recepcion" = "Recepcion "). Unico POR EMPRESA:
-- dos laboratorios pueden tener cada uno su "Recepcion". El API pregunta
-- antes para contestar 409 con el campo; esto es la garantia.
CREATE UNIQUE INDEX uq_rol_nombre
  ON core.rol (empresa_id, core.llave_texto(nombre));

-- Unico solo cuando hay documento, y por empresa. Por la LLAVE del documento
-- (solo letras y numeros, en mayusculas): "0801-2004-00844" y "0801200400844"
-- son el mismo, como en empleados.
CREATE UNIQUE INDEX uq_paciente_documento
  ON core.paciente (empresa_id, tipo_documento, core.llave_documento(documento))
  WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL;

-- La busqueda por nombre es por parecido (core.buscar_pacientes): trigramas
-- sobre la llave del nombre (minusculas, sin acentos). GIN, y con el esquema
-- del opclass puesto por lo de PostgreSQL 17 (ver 01_tipos.sql).
CREATE INDEX ix_paciente_nombre_trgm
  ON core.paciente USING gin (core.llave_texto(nombre_completo) public.gin_trgm_ops)
  WHERE fusionado_en_paciente_id IS NULL;

-- Documento y expediente se buscan por prefijo.
CREATE INDEX ix_paciente_documento
  ON core.paciente (empresa_id, core.llave_documento(documento) text_pattern_ops)
  WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL;

-- Sin texto, la lista trae los ultimos registrados.
CREATE INDEX ix_paciente_reciente
  ON core.paciente (empresa_id, creado_en DESC)
  WHERE fusionado_en_paciente_id IS NULL;

-- Una sola referencia vigente por contraparte. El historico si puede tener
-- varias, una por cada vez que hubo que corregir.
CREATE UNIQUE INDEX uq_referencia_vigente
  ON core.paciente_referencia (empresa_id, paciente_id, contraparte_empresa_id)
  WHERE anulada_en IS NULL;

-- Por aqui entra el cotejo: "me llego H-000123 del hospital, quien es aqui?"
CREATE INDEX ix_referencia_externa
  ON core.paciente_referencia (empresa_id, contraparte_empresa_id, expediente_externo)
  WHERE anulada_en IS NULL;

-- La bandeja de una sede, sin salir de core y sin funcion de por medio.
CREATE INDEX ix_mensaje_bandeja
  ON core.mensaje (empresa_id, sucursal_id, estado)
  WHERE direccion = 'recibido';

-- "Mis ordenes que todavia no se entregaron, con su antiguedad."
CREATE INDEX ix_mensaje_sin_entregar
  ON core.mensaje (empresa_id, creado_en)
  WHERE direccion = 'enviado' AND estado = 'pendiente';

CREATE INDEX ix_mensaje_hilo
  ON core.mensaje (empresa_id, responde_a_folio)
  WHERE responde_a_folio IS NOT NULL;

-- Un solo convenio predeterminado (el "particular") por empresa.
CREATE UNIQUE INDEX uq_convenio_predeterminado
  ON core.convenio (empresa_id)
  WHERE es_predeterminado;

CREATE INDEX ix_episodio_pendientes
  ON core.episodio (empresa_id, sucursal_id, creado_en DESC)
  WHERE estado = 'abierto';

CREATE INDEX ix_episodio_paciente
  ON core.episodio (empresa_id, paciente_id, creado_en DESC);


-- ---------------------------------------------------------- 04_audit.sql

CREATE INDEX ix_evento_empresa    ON audit.evento (empresa_id, ocurrido_en DESC);

CREATE INDEX ix_evento_registro   ON audit.evento (nombre_esquema, nombre_tabla, registro_id);

CREATE INDEX ix_evento_usuario    ON audit.evento (usuario_id, ocurrido_en DESC);


-- ---------------------------------------------------------- 11_lab_catalogo.sql

CREATE UNIQUE INDEX uq_precio_vigente
  ON lab.precio_prueba (
    empresa_id, prueba_id,
    coalesce(sucursal_id, 0), coalesce(convenio_id, 0), vigente_desde
  );

CREATE INDEX ix_precio_busqueda
  ON lab.precio_prueba (empresa_id, prueba_id, vigente_desde DESC);

CREATE INDEX ix_rango_analito
  ON lab.rango_referencia (empresa_id, analito_id, sexo, edad_min_dias);


-- ---------------------------------------------------------- 12_lab_operacion.sql

CREATE INDEX ix_orden_bandeja
  ON lab.orden (empresa_id, estado, urgente DESC, creado_en)
  WHERE estado NOT IN ('entregada','anulada');

CREATE INDEX ix_muestra_orden ON lab.muestra (empresa_id, orden_id);

CREATE INDEX ix_muestra_pendientes
  ON lab.muestra (empresa_id, estado, tomada_en)
  WHERE estado IN ('tomada','recibida','en_proceso');

CREATE INDEX ix_orden_prueba_orden ON lab.orden_prueba (empresa_id, orden_id);

-- Solo un resultado vigente por analito dentro de un examen pedido.
-- Corregir es marcar el anterior como no vigente e insertar una fila nueva,
-- en ese orden. Nunca se sobrescribe un valor.
CREATE UNIQUE INDEX uq_resultado_vigente
  ON lab.resultado (orden_prueba_id, analito_id)
  WHERE vigente;

CREATE INDEX ix_resultado_por_validar
  ON lab.resultado (empresa_id, estado, creado_en)
  WHERE estado = 'preliminar' AND vigente;

-- Esta es la consulta que el modelo A no podia responder:
-- "todas las hemoglobinas fuera de rango de este mes".
CREATE INDEX ix_resultado_analito_valor
  ON lab.resultado (empresa_id, analito_id, medido_en DESC)
  INCLUDE (valor_numerico, bandera)
  WHERE vigente;

CREATE INDEX ix_aviso_pendiente
  ON lab.aviso_valor_critico (empresa_id, avisado_en DESC)
  WHERE NOT confirmado;


-- ---------------------------------------------------------- 13_integra.sql

CREATE INDEX ix_mensaje_pendiente
  ON integra.mensaje_crudo (empresa_id, recibido_en)
  WHERE estado IN ('pendiente','fallido');

CREATE INDEX ix_mensaje_muestra
  ON integra.mensaje_crudo (empresa_id, identificador_muestra)
  WHERE identificador_muestra IS NOT NULL;


-- ---------------------------------------------------------- 17_comercial.sql

-- Sin columna "activo" a proposito: si el cliente sigue siendo cliente se
-- deduce del estado de sus empresas. Dos copias del mismo estado se
-- desincronizan, y es justo lo que este esquema evita con nivel_acceso.
CREATE UNIQUE INDEX uq_cliente_rtn ON comercial.cliente (rtn) WHERE rtn IS NOT NULL;

CREATE INDEX ix_contacto_cliente ON comercial.contacto (cliente_id, papel)
  WHERE activo;

CREATE INDEX ix_relacion_evento_empresa
  ON comercial.relacion_evento (empresa_id, fecha DESC, evento_id DESC);

CREATE INDEX ix_contrato_cliente ON comercial.contrato (cliente_id, fecha_inicio DESC);

