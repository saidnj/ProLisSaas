-- =====================================================================
-- ProLisSaas · 12 · Operacion del laboratorio
--
-- La orden cuelga del episodio del nucleo. El informe vive en el nucleo
-- y es la orden la que apunta a el: el nucleo nunca conoce a las ramas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Orden
-- ---------------------------------------------------------------------

CREATE TABLE lab.orden (
  orden_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  episodio_id  bigint NOT NULL,
  informe_id   bigint,                    -- la rama apunta al nucleo, no al reves
  numero       text NOT NULL,
  estado       lab.estado_orden NOT NULL DEFAULT 'solicitada',
  urgente      boolean NOT NULL DEFAULT false,
  ayuno        boolean,
  observacion  text,
  anulado_motivo text,

  creado_por_usuario_id  bigint NOT NULL,
  creado_en    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_orden_empresa UNIQUE (orden_id, empresa_id),
  CONSTRAINT uq_orden_numero  UNIQUE (empresa_id, numero),
  CONSTRAINT uq_orden_episodio UNIQUE (episodio_id),
  CONSTRAINT ck_orden_anulada CHECK (
    estado <> 'anulada' OR (anulado_motivo IS NOT NULL AND btrim(anulado_motivo) <> '')
  ),
  CONSTRAINT fk_orden_episodio
    FOREIGN KEY (episodio_id, empresa_id) REFERENCES core.episodio (episodio_id, empresa_id),
  CONSTRAINT fk_orden_informe
    FOREIGN KEY (informe_id, empresa_id) REFERENCES core.informe (informe_id, empresa_id),
  CONSTRAINT fk_orden_usuario
    FOREIGN KEY (creado_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON CONSTRAINT uq_orden_episodio ON lab.orden IS
  'Un episodio tiene a lo sumo una orden de laboratorio. Manana tendra tambien '
  'una de imagenologia, en otra tabla de otro esquema, colgando del mismo episodio.';

COMMENT ON COLUMN lab.orden.estado IS
  'Es una PROYECCION del estado de sus muestras y resultados, mantenida por el '
  'servicio para que la bandeja de trabajo sea una consulta barata. La verdad esta '
  'en las filas de lab.resultado; hay una prueba que verifica que no se separen.';

CREATE INDEX ix_orden_bandeja
  ON lab.orden (empresa_id, estado, urgente DESC, creado_en)
  WHERE estado NOT IN ('entregada','anulada');


-- ---------------------------------------------------------------------
-- Muestra · el tubo
-- ---------------------------------------------------------------------

CREATE TABLE lab.muestra (
  muestra_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint NOT NULL REFERENCES core.empresa (empresa_id),
  orden_id         bigint NOT NULL,
  tipo_muestra_id  bigint NOT NULL,
  codigo_barra     text NOT NULL,
  estado           lab.estado_muestra NOT NULL DEFAULT 'pendiente',
  volumen_ml       numeric(5,2),

  tomada_en                timestamptz,
  tomada_por_usuario_id    bigint,
  recibida_en              timestamptz,
  recibida_por_usuario_id  bigint,

  observacion      text,

  CONSTRAINT uq_muestra_empresa UNIQUE (muestra_id, empresa_id),
  CONSTRAINT uq_muestra_codigo  UNIQUE (empresa_id, codigo_barra),
  CONSTRAINT ck_muestra_tomada CHECK (
    estado = 'pendiente' OR (tomada_en IS NOT NULL AND tomada_por_usuario_id IS NOT NULL)
  ),
  CONSTRAINT fk_muestra_orden
    FOREIGN KEY (orden_id, empresa_id) REFERENCES lab.orden (orden_id, empresa_id),
  CONSTRAINT fk_muestra_tipo
    FOREIGN KEY (tipo_muestra_id, empresa_id) REFERENCES lab.tipo_muestra (tipo_muestra_id, empresa_id),
  CONSTRAINT fk_muestra_tomada_por
    FOREIGN KEY (tomada_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT fk_muestra_recibida_por
    FOREIGN KEY (recibida_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE lab.muestra IS
  'Un tubo. Una orden puede necesitar tres, de tipos distintos, y uno puede '
  'rechazarse sin afectar a los demas. En los esquemas anteriores esto era un '
  'campo de texto codTubo en la boleta.';

COMMENT ON COLUMN lab.muestra.codigo_barra IS
  'LA llave del sistema. Nace aqui, se imprime en la etiqueta, viaja en el OBR-3 '
  'del mensaje del analizador y regresa igual. Nunca lo escribe una persona: por '
  'eso el resultado no puede entrar al paciente equivocado.';

CREATE INDEX ix_muestra_orden ON lab.muestra (empresa_id, orden_id);
CREATE INDEX ix_muestra_pendientes
  ON lab.muestra (empresa_id, estado, tomada_en)
  WHERE estado IN ('tomada','recibida','en_proceso');


CREATE TABLE lab.muestra_rechazo (
  muestra_rechazo_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id          bigint NOT NULL REFERENCES core.empresa (empresa_id),
  muestra_id          bigint NOT NULL,
  motivo              lab.motivo_rechazo NOT NULL,
  detalle             text,
  nueva_muestra_id    bigint,          -- la retoma, si se pidio
  rechazada_por_usuario_id bigint NOT NULL,
  rechazada_en        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT fk_rechazo_muestra
    FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra (muestra_id, empresa_id),
  CONSTRAINT fk_rechazo_nueva
    FOREIGN KEY (nueva_muestra_id, empresa_id) REFERENCES lab.muestra (muestra_id, empresa_id),
  CONSTRAINT fk_rechazo_usuario
    FOREIGN KEY (rechazada_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT ck_rechazo_distinta CHECK (nueva_muestra_id IS DISTINCT FROM muestra_id)
);

COMMENT ON TABLE lab.muestra_rechazo IS
  'El primero de los tres desvios del flujo. Que un tubo se rechace por hemolisis '
  'pasa todos los dias, y sin esta tabla el sistema no puede ni explicarle al '
  'paciente por que le van a sacar sangre otra vez.';


-- ---------------------------------------------------------------------
-- Item de orden · un examen pedido
-- ---------------------------------------------------------------------

CREATE TABLE lab.orden_prueba (
  orden_prueba_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint NOT NULL REFERENCES core.empresa (empresa_id),
  orden_id         bigint NOT NULL,
  prueba_id        bigint NOT NULL,
  muestra_id       bigint,

  -- Precio congelado al crear la orden. Si el catalogo sube manana, esto no cambia.
  precio_lista     numeric(12,2) NOT NULL,
  precio           numeric(12,2) NOT NULL,
  convenio_id      bigint NOT NULL,

  anulado_en       timestamptz,
  anulado_motivo   text,

  CONSTRAINT uq_orden_prueba_empresa UNIQUE (orden_prueba_id, empresa_id),
  CONSTRAINT uq_orden_prueba_unica   UNIQUE (orden_id, prueba_id),
  CONSTRAINT ck_orden_prueba_precio  CHECK (precio >= 0 AND precio_lista >= 0),
  CONSTRAINT ck_orden_prueba_anulada CHECK (
    (anulado_en IS NULL     AND anulado_motivo IS NULL) OR
    (anulado_en IS NOT NULL AND anulado_motivo IS NOT NULL AND btrim(anulado_motivo) <> '')
  ),
  CONSTRAINT fk_orden_prueba_orden
    FOREIGN KEY (orden_id, empresa_id) REFERENCES lab.orden (orden_id, empresa_id),
  CONSTRAINT fk_orden_prueba_prueba
    FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba (prueba_id, empresa_id),
  CONSTRAINT fk_orden_prueba_muestra
    FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra (muestra_id, empresa_id),
  CONSTRAINT fk_orden_prueba_convenio
    FOREIGN KEY (convenio_id, empresa_id) REFERENCES core.convenio (convenio_id, empresa_id)
);

COMMENT ON COLUMN lab.orden_prueba.precio IS
  'Congelado. Si el precio solo viviera en el catalogo, cambiarlo reescribiria la '
  'historia de todas las ordenes anteriores y ningun corte de caja cuadraria dos veces.';

COMMENT ON TABLE lab.orden_prueba IS
  'No lleva estado propio: su avance se deriva de sus resultados. Un estado '
  'guardado aqui seria una cuarta copia de la verdad, y las copias se separan.';

CREATE INDEX ix_orden_prueba_orden ON lab.orden_prueba (empresa_id, orden_id);


-- ---------------------------------------------------------------------
-- Resultado · una fila por analito, inmutable
-- ---------------------------------------------------------------------

CREATE TABLE lab.resultado (
  resultado_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id       bigint NOT NULL REFERENCES core.empresa (empresa_id),
  orden_prueba_id  bigint NOT NULL,
  analito_id       bigint NOT NULL,
  muestra_id       bigint,

  valor_numerico   numeric(14,4),
  valor_texto      text,
  unidad           text,

  -- El rango se COPIA al resultado. Si el laboratorio cambia sus rangos manana,
  -- el informe emitido hoy sigue mostrando el que se aplico hoy.
  rango_min        numeric(14,4),
  rango_max        numeric(14,4),
  rango_texto      text,
  critico_min      numeric(14,4),
  critico_max      numeric(14,4),
  bandera          lab.bandera NOT NULL DEFAULT 'normal',

  estado           lab.estado_resultado NOT NULL DEFAULT 'pendiente',
  metodo           text,
  equipo_id        bigint,   -- FK agregada en 13
  mensaje_crudo_id bigint,   -- FK agregada en 13
  medido_en        timestamptz,

  capturado_por_usuario_id bigint,
  validado_por_usuario_id  bigint,
  validado_en              timestamptz,

  -- vigente marca cual es el resultado actual de este analito. Es un booleano
  -- legitimo (esta fila es o no es la vigente); el estado del ciclo de vida
  -- vive en la columna estado, que si es un enumerado.
  vigente                boolean NOT NULL DEFAULT true,
  corrige_a_resultado_id bigint REFERENCES lab.resultado (resultado_id),
  motivo_correccion      text,
  observacion            text,
  creado_en        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_resultado_empresa UNIQUE (resultado_id, empresa_id),

  CONSTRAINT ck_resultado_tiene_valor CHECK (
    estado = 'pendiente' OR valor_numerico IS NOT NULL OR valor_texto IS NOT NULL
  ),
  CONSTRAINT ck_resultado_validado CHECK (
    estado NOT IN ('validado','corregido') OR
    (validado_por_usuario_id IS NOT NULL AND validado_en IS NOT NULL)
  ),
  CONSTRAINT ck_resultado_correccion CHECK (
    estado <> 'corregido' OR (
      motivo_correccion IS NOT NULL AND btrim(motivo_correccion) <> ''
      AND corrige_a_resultado_id IS NOT NULL
    )
  ),
  CONSTRAINT ck_resultado_no_se_corrige_solo
    CHECK (corrige_a_resultado_id IS DISTINCT FROM resultado_id),

  CONSTRAINT fk_resultado_orden_prueba
    FOREIGN KEY (orden_prueba_id, empresa_id) REFERENCES lab.orden_prueba (orden_prueba_id, empresa_id),
  CONSTRAINT fk_resultado_analito
    FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito (analito_id, empresa_id),
  CONSTRAINT fk_resultado_muestra
    FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra (muestra_id, empresa_id),
  CONSTRAINT fk_resultado_validado_por
    FOREIGN KEY (validado_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id)
);

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

COMMENT ON TABLE lab.resultado IS
  'Una fila por analito. El hemograma del Hemax 53 produce 24 de estas y se cobra '
  'una sola vez. Las filas no se actualizan salvo para marcarlas reemplazadas.';


-- ---------------------------------------------------------------------
-- Aviso de valor critico
-- ---------------------------------------------------------------------

CREATE TABLE lab.aviso_valor_critico (
  aviso_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id     bigint NOT NULL REFERENCES core.empresa (empresa_id),
  resultado_id   bigint NOT NULL,
  avisado_a      text NOT NULL,
  cargo          text,
  medio          lab.medio_aviso NOT NULL,
  mensaje        text,
  confirmado     boolean NOT NULL DEFAULT false,
  avisado_por_usuario_id bigint NOT NULL,
  avisado_en     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT fk_aviso_resultado
    FOREIGN KEY (resultado_id, empresa_id) REFERENCES lab.resultado (resultado_id, empresa_id),
  CONSTRAINT fk_aviso_usuario
    FOREIGN KEY (avisado_por_usuario_id, empresa_id) REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE lab.aviso_valor_critico IS
  'El segundo desvio del flujo. Una hemoglobina de 5 no es un dato para el informe '
  'de manana: es una llamada telefonica hoy, y hay que poder demostrar a quien se '
  'llamo y a que hora.';

CREATE INDEX ix_aviso_pendiente
  ON lab.aviso_valor_critico (empresa_id, avisado_en DESC)
  WHERE NOT confirmado;
