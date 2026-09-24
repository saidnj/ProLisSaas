-- =====================================================================
-- ProLisSaas · 04 · Esquema audit
--
-- Dos cosas viven aqui: el rastro de quien hizo que, y el unico puente
-- autorizado entre dos empresas. Ninguna fila de este esquema se
-- actualiza ni se borra jamas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Derivacion · el puente entre empresas
-- ---------------------------------------------------------------------

/* audit.derivacion se retiro.
   Era UNA fila que veian DOS empresas, con estados que negociaban
   (solicitada -> aceptada | rechazada). La reemplaza core.mensaje: una fila
   de cada lado, con la RLS de todas y estados de entrega, no de negociacion.
   La aceptacion se mudo una sola vez a la relacion (plataforma.enlace).
   Ver documentacion/flujos/06 y H-73. */


-- ---------------------------------------------------------------------
-- Evento · el rastro
-- ---------------------------------------------------------------------

CREATE TABLE audit.evento (
  evento_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id     bigint REFERENCES core.empresa (empresa_id),
  usuario_id     bigint,
  ocurrido_en    timestamptz NOT NULL DEFAULT now(),

  accion         text NOT NULL,   -- 'resultado.validar', 'paciente.fusionar'
  nombre_esquema text NOT NULL,
  nombre_tabla   text NOT NULL,
  registro_id    bigint,

  datos_antes    jsonb,
  datos_despues  jsonb,

  ip             inet,
  user_agent     text,

  CONSTRAINT ck_evento_accion_formato
    CHECK (accion ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE audit.evento IS
  'Transversal a proposito. Si la auditoria vive en cada modulo, cada uno la '
  'implementa distinto y ninguno completo.';

CREATE INDEX ix_evento_empresa    ON audit.evento (empresa_id, ocurrido_en DESC);
CREATE INDEX ix_evento_registro   ON audit.evento (nombre_esquema, nombre_tabla, registro_id);
CREATE INDEX ix_evento_usuario    ON audit.evento (usuario_id, ocurrido_en DESC);


-- ---------------------------------------------------------------------
-- Llaves que faltaban por orden de creacion
-- ---------------------------------------------------------------------

ALTER TABLE core.episodio
  ADD CONSTRAINT fk_episodio_mensaje
  FOREIGN KEY (mensaje_id, empresa_id)
  REFERENCES core.mensaje (mensaje_id, empresa_id);

ALTER TABLE core.paciente
  ADD CONSTRAINT fk_paciente_creado_por
  FOREIGN KEY (creado_por_usuario_id, empresa_id)
  REFERENCES core.usuario (usuario_id, empresa_id);

ALTER TABLE core.paciente
  ADD CONSTRAINT fk_paciente_fusionado_por
  FOREIGN KEY (fusionado_por_usuario_id, empresa_id)
  REFERENCES core.usuario (usuario_id, empresa_id);
