-- =====================================================================
-- ProLisSaas · 11 · Catalogo del laboratorio
--
-- La decision estructural de todo el modulo: la PRUEBA es lo que se pide
-- y se cobra; el ANALITO es donde vive el resultado. Un hemograma se
-- cobra una vez y produce veinticuatro analitos.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Areas del laboratorio
-- ---------------------------------------------------------------------

CREATE TABLE lab.area (
  area_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id  bigint NOT NULL REFERENCES core.empresa (empresa_id),
  codigo      text NOT NULL,
  nombre      text NOT NULL,
  orden_presentacion smallint NOT NULL DEFAULT 0,
  activo      boolean NOT NULL DEFAULT true,

  CONSTRAINT uq_area_empresa UNIQUE (area_id, empresa_id),
  CONSTRAINT uq_area_codigo  UNIQUE (empresa_id, codigo)
);

COMMENT ON TABLE lab.area IS
  'Hematologia, quimica clinica, uroanalisis. Agrupa el catalogo y ordena el '
  'informe impreso, que se lee por area.';


-- ---------------------------------------------------------------------
-- Tipos de muestra
-- ---------------------------------------------------------------------

CREATE TABLE lab.tipo_muestra (
  tipo_muestra_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint NOT NULL REFERENCES core.empresa (empresa_id),
  codigo           text NOT NULL,
  nombre           text NOT NULL,
  color_tapon      text,
  anticoagulante   text,
  volumen_min_ml   numeric(5,2),
  estable_horas    smallint,
  activo           boolean NOT NULL DEFAULT true,

  CONSTRAINT uq_tipo_muestra_empresa UNIQUE (tipo_muestra_id, empresa_id),
  CONSTRAINT uq_tipo_muestra_codigo  UNIQUE (empresa_id, codigo)
);

COMMENT ON COLUMN lab.tipo_muestra.color_tapon IS
  'El color del tapon del tubo es como el flebotomista identifica el tubo en la '
  'mano. Va impreso en la etiqueta y en la hoja de toma.';

COMMENT ON COLUMN lab.tipo_muestra.estable_horas IS
  'Cuantas horas es valida la muestra desde la toma. Vencida se rechaza.';


-- ---------------------------------------------------------------------
-- Analito · donde vive el resultado
-- ---------------------------------------------------------------------

CREATE TABLE lab.analito (
  analito_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  area_id      bigint NOT NULL,
  codigo       text NOT NULL,
  nombre       text NOT NULL,
  abreviatura  text,
  tipo_valor   lab.tipo_valor NOT NULL DEFAULT 'numerico',
  unidad       text,
  decimales    smallint NOT NULL DEFAULT 2,
  opciones     text[],
  loinc        text,
  activo       boolean NOT NULL DEFAULT true,

  CONSTRAINT uq_analito_empresa UNIQUE (analito_id, empresa_id),
  CONSTRAINT uq_analito_codigo  UNIQUE (empresa_id, codigo),
  CONSTRAINT ck_analito_decimales CHECK (decimales BETWEEN 0 AND 6),
  CONSTRAINT ck_analito_numerico  CHECK (tipo_valor <> 'numerico' OR unidad IS NOT NULL),
  CONSTRAINT ck_analito_opciones  CHECK (
    (tipo_valor =  'opcion' AND opciones IS NOT NULL AND array_length(opciones,1) > 1) OR
    (tipo_valor <> 'opcion' AND opciones IS NULL)
  ),
  CONSTRAINT fk_analito_area
    FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area (area_id, empresa_id)
);

COMMENT ON COLUMN lab.analito.loinc IS
  'Codigo LOINC, opcional. Hoy no lo necesitas; el dia que un hospital pida '
  'intercambio de resultados, sin esta columna hay que mapear todo a mano.';


-- ---------------------------------------------------------------------
-- Prueba · lo que se pide y se cobra
-- ---------------------------------------------------------------------

CREATE TABLE lab.prueba (
  prueba_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint NOT NULL REFERENCES core.empresa (empresa_id),
  area_id          bigint NOT NULL,
  tipo_muestra_id  bigint NOT NULL,
  codigo           text NOT NULL,
  nombre           text NOT NULL,
  metodo           text,
  horas_proceso    smallint NOT NULL DEFAULT 24,
  requiere_ayuno   boolean NOT NULL DEFAULT false,
  indicaciones     text,
  activo           boolean NOT NULL DEFAULT true,
  creado_en        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_prueba_empresa UNIQUE (prueba_id, empresa_id),
  CONSTRAINT uq_prueba_codigo  UNIQUE (empresa_id, codigo),
  CONSTRAINT fk_prueba_area
    FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area (area_id, empresa_id),
  CONSTRAINT fk_prueba_tipo_muestra
    FOREIGN KEY (tipo_muestra_id, empresa_id)
    REFERENCES lab.tipo_muestra (tipo_muestra_id, empresa_id)
);

COMMENT ON COLUMN lab.prueba.metodo IS
  'Impedancia, colorimetrico, ELISA. Va impreso en el informe y determina que '
  'rango de referencia aplica: cambiar de metodo cambia los rangos.';


CREATE TABLE lab.prueba_analito (
  prueba_id           bigint NOT NULL,
  analito_id          bigint NOT NULL,
  empresa_id          bigint NOT NULL REFERENCES core.empresa (empresa_id),
  orden_presentacion  smallint NOT NULL DEFAULT 0,
  calculado           boolean NOT NULL DEFAULT false,

  PRIMARY KEY (prueba_id, analito_id),
  CONSTRAINT fk_prueba_analito_prueba
    FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba (prueba_id, empresa_id),
  CONSTRAINT fk_prueba_analito_analito
    FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito (analito_id, empresa_id)
);

COMMENT ON COLUMN lab.prueba_analito.calculado IS
  'true si el equipo lo deriva de otros (HCT a partir de RBC y MCV). Se guarda '
  'igual, pero se marca para no cuestionar por que no coincide al recalcular.';


-- ---------------------------------------------------------------------
-- Precio · por sucursal y convenio, con vigencia
-- ---------------------------------------------------------------------

CREATE TABLE lab.precio_prueba (
  precio_prueba_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  prueba_id         bigint NOT NULL,
  sucursal_id       bigint,     -- NULL = aplica a toda la empresa
  convenio_id       bigint,     -- NULL = precio de lista
  precio            numeric(12,2) NOT NULL,
  vigente_desde     date NOT NULL DEFAULT current_date,
  vigente_hasta     date,

  CONSTRAINT ck_precio_positivo CHECK (precio >= 0),
  CONSTRAINT ck_precio_vigencia
    CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde),
  CONSTRAINT fk_precio_prueba
    FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba (prueba_id, empresa_id),
  CONSTRAINT fk_precio_sucursal
    FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal (sucursal_id, empresa_id),
  CONSTRAINT fk_precio_convenio
    FOREIGN KEY (convenio_id, empresa_id) REFERENCES core.convenio (convenio_id, empresa_id)
);

CREATE UNIQUE INDEX uq_precio_vigente
  ON lab.precio_prueba (
    empresa_id, prueba_id,
    coalesce(sucursal_id, 0), coalesce(convenio_id, 0), vigente_desde
  );

CREATE INDEX ix_precio_busqueda
  ON lab.precio_prueba (empresa_id, prueba_id, vigente_desde DESC);

COMMENT ON TABLE lab.precio_prueba IS
  'Se resuelve de lo mas especifico a lo mas general: convenio y sucursal, luego '
  'convenio, luego sucursal, luego lista. Nunca se actualiza un precio: se cierra '
  'la vigencia del anterior y se inserta el nuevo.';


-- ---------------------------------------------------------------------
-- Rango de referencia · del laboratorio, no del equipo
-- ---------------------------------------------------------------------

CREATE TABLE lab.rango_referencia (
  rango_referencia_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  analito_id      bigint NOT NULL,
  sexo            lab.sexo_rango NOT NULL DEFAULT 'ambos',
  edad_min_dias   integer NOT NULL DEFAULT 0,
  edad_max_dias   integer NOT NULL DEFAULT 54750,   -- 150 anios
  valor_min       numeric(14,4),
  valor_max       numeric(14,4),
  critico_min     numeric(14,4),
  critico_max     numeric(14,4),
  metodo          text,
  texto_libre     text,
  vigente_desde   date NOT NULL DEFAULT current_date,
  vigente_hasta   date,

  CONSTRAINT ck_rango_edad  CHECK (edad_max_dias > edad_min_dias),
  CONSTRAINT ck_rango_orden CHECK (valor_min IS NULL OR valor_max IS NULL OR valor_max > valor_min),
  CONSTRAINT ck_rango_critico_bajo  CHECK (critico_min IS NULL OR valor_min IS NULL OR critico_min <= valor_min),
  CONSTRAINT ck_rango_critico_alto  CHECK (critico_max IS NULL OR valor_max IS NULL OR critico_max >= valor_max),
  CONSTRAINT fk_rango_analito
    FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito (analito_id, empresa_id)
);

CREATE INDEX ix_rango_analito
  ON lab.rango_referencia (empresa_id, analito_id, sexo, edad_min_dias);

COMMENT ON TABLE lab.rango_referencia IS
  'El rango lo define el LABORATORIO, no el analizador. El Hemax 53 manda 13.5-18.0 '
  'para hemoglobina en cada OBX, que es un rango de varon adulto, y ese se ignora. '
  'Aplicado a todos, una mujer con 13.0 sale marcada como baja cuando para ella es '
  'normal, y el laboratorio repite la muestra sin necesidad. Al reves, si se usara '
  'el rango femenino para todos, un varon con 13.0 pasaria como normal estando '
  'anemico. Un solo rango para los dos sexos falla en las dos direcciones.';

COMMENT ON COLUMN lab.rango_referencia.critico_min IS
  'Valor de panico. Fuera de este umbral hay que avisar a alguien y dejar constancia '
  'de a quien y cuando. No es una alerta de interfaz: es un requisito de auditoria.';

COMMENT ON COLUMN lab.rango_referencia.edad_min_dias IS
  'En dias y no en anios porque los rangos neonatales cambian por semana.';
