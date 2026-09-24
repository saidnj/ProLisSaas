-- =====================================================================
-- ProLisSaas · 13 · Integracion con analizadores
--
-- Lo que entra de un equipo entra CRUDO y se guarda antes de intentar
-- interpretarlo. Si el mapeo falla, el mensaje original sigue ahi para
-- reprocesar. Nunca se descarta lo que mando el analizador.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Equipo
-- ---------------------------------------------------------------------

CREATE TABLE integra.equipo (
  equipo_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id     bigint NOT NULL REFERENCES core.empresa (empresa_id),
  sucursal_id    bigint NOT NULL,
  area_id        bigint,
  codigo         text NOT NULL,
  nombre         text NOT NULL,
  marca          text,
  modelo         text,
  serie          text,
  protocolo      integra.protocolo NOT NULL,
  identificador  text NOT NULL,
  bidireccional  boolean NOT NULL DEFAULT false,
  activo         boolean NOT NULL DEFAULT true,
  creado_en      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_equipo_empresa UNIQUE (equipo_id, empresa_id),
  CONSTRAINT uq_equipo_codigo  UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_equipo_identificador UNIQUE (empresa_id, identificador),
  CONSTRAINT fk_equipo_sucursal
    FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal (sucursal_id, empresa_id),
  CONSTRAINT fk_equipo_area
    FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area (area_id, empresa_id)
);

COMMENT ON COLUMN integra.equipo.identificador IS
  'Como se identifica el equipo en sus propios mensajes: el MSH-3 en HL7, el '
  'campo de sender en ASTM. Es lo unico que permite saber que equipo mando que.';

COMMENT ON COLUMN integra.equipo.protocolo IS
  'Determina que driver del agente local atiende a este equipo. El agente traduce '
  'los tres dialectos a una estructura interna unica; de aqui para arriba el '
  'sistema es igual para todos los analizadores.';

COMMENT ON COLUMN integra.equipo.bidireccional IS
  'El Hemax 53 lo soporta segun el fabricante. En la v1 va en false: el equipo '
  'solo envia. Activarlo despues no cambia ninguna tabla, porque el codigo de '
  'barras de la muestra ya existe desde el primer dia.';


-- ---------------------------------------------------------------------
-- Mapeo de codigos · "HGB" del equipo = analito Hemoglobina
-- ---------------------------------------------------------------------

CREATE TABLE integra.mapeo_codigo (
  mapeo_codigo_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  equipo_id       bigint NOT NULL,
  codigo_equipo   text NOT NULL,
  analito_id      bigint NOT NULL,
  factor          numeric(12,6) NOT NULL DEFAULT 1,
  unidad_equipo   text,
  activo          boolean NOT NULL DEFAULT true,

  CONSTRAINT uq_mapeo_codigo UNIQUE (equipo_id, codigo_equipo),
  CONSTRAINT ck_mapeo_factor CHECK (factor > 0),
  CONSTRAINT fk_mapeo_equipo
    FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo (equipo_id, empresa_id),
  CONSTRAINT fk_mapeo_analito
    FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito (analito_id, empresa_id)
);

COMMENT ON TABLE integra.mapeo_codigo IS
  'El equipo nuevo manda GLU donde el viejo mandaba GLUC: aqui se resuelve, sin '
  'que el resto del sistema se entere de que existen dos nombres.';

COMMENT ON COLUMN integra.mapeo_codigo.factor IS
  'Conversion de unidades cuando el equipo reporta en otra escala. Existe por lo '
  'que se encontro en prueba.txt: el LYM# venia diez veces mas bajo de lo que da '
  'el calculo con WBC y LYM%. Antes de usar un factor hay que confirmarlo con el '
  'manual del equipo: puede ser un error del archivo y no del analizador.';


-- ---------------------------------------------------------------------
-- Mensaje crudo
-- ---------------------------------------------------------------------

CREATE TABLE integra.mensaje_crudo (
  mensaje_crudo_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  sucursal_id       bigint NOT NULL,
  equipo_id         bigint,
  protocolo         integra.protocolo NOT NULL,

  contenido         text NOT NULL,
  contenido_hash    text NOT NULL,
  identificador_equipo  text,
  identificador_muestra text,

  estado            integra.estado_mensaje NOT NULL DEFAULT 'pendiente',
  intentos          smallint NOT NULL DEFAULT 0,
  ultimo_error      text,

  recibido_en       timestamptz NOT NULL,
  recibido_nube_en  timestamptz NOT NULL DEFAULT now(),
  procesado_en      timestamptz,

  CONSTRAINT uq_mensaje_empresa UNIQUE (mensaje_crudo_id, empresa_id),
  CONSTRAINT uq_mensaje_hash    UNIQUE (empresa_id, contenido_hash),
  CONSTRAINT ck_mensaje_procesado CHECK (
    estado = 'pendiente' OR procesado_en IS NOT NULL
  ),
  CONSTRAINT fk_mensaje_sucursal
    FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal (sucursal_id, empresa_id),
  CONSTRAINT fk_mensaje_equipo
    FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo (equipo_id, empresa_id)
);

COMMENT ON TABLE integra.mensaje_crudo IS
  'El mensaje tal cual lo mando el equipo. El agente local lo persiste ANTES de '
  'responderle el ACK al analizador: si el proceso muere entre una cosa y la otra, '
  'el equipo cree que llego y el resultado se perdio.';

COMMENT ON COLUMN integra.mensaje_crudo.contenido_hash IS
  'El agente reintenta cuando se cae el internet. Sin este hash, cada reintento '
  'crearia un resultado duplicado.';

COMMENT ON COLUMN integra.mensaje_crudo.recibido_en IS
  'Cuando lo recibio el agente en el laboratorio, no cuando llego a la nube. '
  'Con internet caido pueden pasar horas entre una cosa y la otra.';

CREATE INDEX ix_mensaje_pendiente
  ON integra.mensaje_crudo (empresa_id, recibido_en)
  WHERE estado IN ('pendiente','fallido');

CREATE INDEX ix_mensaje_muestra
  ON integra.mensaje_crudo (empresa_id, identificador_muestra)
  WHERE identificador_muestra IS NOT NULL;


CREATE TABLE integra.intento_proceso (
  intento_proceso_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id         bigint NOT NULL REFERENCES core.empresa (empresa_id),
  mensaje_crudo_id   bigint NOT NULL,
  numero_intento     smallint NOT NULL,
  exito              boolean NOT NULL,
  error              text,
  detalle            jsonb,
  intentado_en       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_intento UNIQUE (mensaje_crudo_id, numero_intento),
  CONSTRAINT ck_intento_error CHECK (exito OR error IS NOT NULL),
  CONSTRAINT fk_intento_mensaje
    FOREIGN KEY (mensaje_crudo_id, empresa_id)
    REFERENCES integra.mensaje_crudo (mensaje_crudo_id, empresa_id)
);

COMMENT ON TABLE integra.intento_proceso IS
  'Cada intento de interpretar un mensaje, con su error. Esto es lo que reemplaza '
  'al trigger de transformer.txt: el fallo queda visible en una tabla que alguien '
  'puede consultar, en vez de en un RAISE LOG que nadie lee.';


-- ---------------------------------------------------------------------
-- Llaves que faltaban por orden de creacion
-- ---------------------------------------------------------------------

ALTER TABLE lab.resultado
  ADD CONSTRAINT fk_resultado_equipo
  FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo (equipo_id, empresa_id);

ALTER TABLE lab.resultado
  ADD CONSTRAINT fk_resultado_mensaje
  FOREIGN KEY (mensaje_crudo_id, empresa_id)
  REFERENCES integra.mensaje_crudo (mensaje_crudo_id, empresa_id);
