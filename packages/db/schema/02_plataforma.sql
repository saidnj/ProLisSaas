-- =====================================================================
-- ProLisSaas · 02 · Esquema plataforma
--
-- Lo que es igual para todos los clientes del SaaS, mas el registro de
-- identidad que permite saber que el paciente de la clinica y el del
-- laboratorio son la misma persona.
--
-- LA REGLA DE ESTE ESQUEMA:
--   El registro de identidad guarda IDENTIFICADORES, no datos.
--   No hay nombres aqui. El nombre es el dato que mas varia entre
--   empresas -con tilde y sin tilde, dos apellidos o uno, el apodo que
--   dio el paciente ese dia- y el que mas dano hace si esta mal.
--   Cada empresa guarda el nombre en SU expediente (core.paciente) y
--   nadie lo lee desde aqui.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Catalogo de modulos del producto
-- ---------------------------------------------------------------------

CREATE TABLE plataforma.modulo (
  modulo_id    text PRIMARY KEY,
  nombre       text NOT NULL,
  descripcion  text,
  CONSTRAINT ck_modulo_id_formato CHECK (modulo_id ~ '^[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE plataforma.modulo IS
  'Los modulos que el producto ofrece. Activar uno en una sucursal es una fila '
  'en plataforma.modulo_sucursal, no un despliegue. La escribe el operador: el '
  'laboratorio no decide que compro.';


-- ---------------------------------------------------------------------
-- Catalogo de permisos
-- ---------------------------------------------------------------------

CREATE TABLE plataforma.permiso (
  permiso_id   text PRIMARY KEY,
  modulo_id    text NOT NULL REFERENCES plataforma.modulo (modulo_id),
  descripcion  text NOT NULL,
  CONSTRAINT ck_permiso_id_formato
    CHECK (permiso_id ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE plataforma.permiso IS
  'El permiso nombra una accion del dominio (resultado.validar), nunca una ruta HTTP. '
  'Atar permisos a rutas acopla la autorizacion a la forma de la URL: cambiar la URL '
  'cambia quien puede hacer que.';


/* plataforma.persona se retiro.

   Guardaba la identidad del paciente compartida entre empresas: documento,
   ano de nacimiento y sexo, sin nombres. La idea era que la clinica y el
   laboratorio supieran que atendian al mismo senor.

   El modelo decidido no comparte NADA entre empresas: cada una anota en su
   propia ficha como lo llama la otra. Eso es core.paciente_referencia, en
   03_core.sql, y con ella se fueron tambien plataforma.conflicto_identidad,
   plataforma.vincular_persona() y core.vincular_paciente_identidad().

   Ver documentacion/flujos/06-el-paciente-entre-dos-empresas.md y H-73.
   Los tipos plataforma.tipo_documento y plataforma.sexo SI se quedan: los usa
   core.paciente para su copia local. */
