-- =====================================================================
-- ProLisSaas · 03 · Esquema core (el nucleo)
--
-- Reglas que se cumplen sin excepcion en este archivo:
--   1. Toda tabla de dominio lleva empresa_id NOT NULL.
--   2. Todo padre declara UNIQUE (<tabla>_id, empresa_id) y todo hijo lo
--      referencia con FK compuesta. Eso hace IMPOSIBLE colgar una fila de
--      un padre de otra empresa, aunque el codigo se equivoque.
--   3. Los estados son tipos enumerados, nunca booleanos.
--   4. Nada se borra. Se anula, se marca, se versiona.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Empresa · el tenant
-- ---------------------------------------------------------------------

CREATE TABLE core.empresa (
  empresa_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre            text NOT NULL,
  nombre_comercial  text,
  rtn               text,
  estado            core.estado_empresa NOT NULL DEFAULT 'prueba',
  -- Las dos columnas por donde entra una decision comercial al LIS, y las
  -- unicas. El LIS no sabe POR QUE una empresa esta limitada: recibe un nivel
  -- y una fecha y los aplica. El motivo vive en el esquema comercial.
  nivel_acceso      core.nivel_acceso NOT NULL DEFAULT 'completo',
  fecha_cierre      date,
  creado_en         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE core.empresa IS
  'El tenant. No lleva empresa_id porque ella ES la empresa; su politica RLS '
  'compara contra el propio empresa_id.';

COMMENT ON COLUMN core.empresa.creado_en IS
  'Cuando aparecio la fila, nada mas. No la lee nadie todavia: se queda porque '
  'se escribe una vez y no puede mentir, y porque hoy es lo unico que contesta '
  '"desde cuando existe esto". El dia que exista la bitacora, el INSERT '
  'registrado da esa misma fecha y ademas el quien, y entonces sobra (H-97).';

COMMENT ON COLUMN core.empresa.rtn IS
  'El RTN con el que ESTA EMPRESA le factura a sus pacientes, y con el que otra '
  'empresa la nombra para trabajar con ella. NO es la identidad fiscal de quien '
  'contrato el servicio: esa es comercial.cliente.rtn. Casi siempre son el mismo '
  'numero, y dejan de serlo el dia que un grupo contrate bajo la sociedad madre.';

COMMENT ON COLUMN core.empresa.nivel_acceso IS
  'Que puede hacer la empresa hoy. Solo lo escriben las funciones de comercial; '
  'el laboratorio no tiene UPDATE sobre esta columna. Regla E-16.';

COMMENT ON COLUMN core.empresa.fecha_cierre IS
  'Cuando vence el plazo. Vive de este lado a proposito: asi el sistema se cierra '
  'solo el dia que toca aunque la administracion este apagada.';

-- La tarea diaria de cierre busca por aqui. Con veinte clientes da igual;
-- se anota ahora para que no de lo mismo despues.
CREATE INDEX ix_empresa_cierre ON core.empresa (estado, fecha_cierre)
  WHERE fecha_cierre IS NOT NULL;

CREATE UNIQUE INDEX uq_empresa_rtn ON core.empresa (rtn) WHERE rtn IS NOT NULL;


-- ---------------------------------------------------------------------
-- Sucursal
-- ---------------------------------------------------------------------

CREATE TABLE core.sucursal (
  sucursal_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  nombre          text NOT NULL,
  codigo          text NOT NULL,
  direccion       text,
  telefono        text,
  activo          boolean NOT NULL DEFAULT true,
  creado_en       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_sucursal_empresa   UNIQUE (sucursal_id, empresa_id),
  CONSTRAINT uq_sucursal_nombre    UNIQUE (empresa_id, nombre),
  CONSTRAINT uq_sucursal_codigo    UNIQUE (empresa_id, codigo),
  CONSTRAINT ck_sucursal_codigo    CHECK (codigo ~ '^[A-Z0-9]{2,6}$')
);

COMMENT ON COLUMN core.sucursal.codigo IS
  'Prefijo corto que va en los correlativos y en las etiquetas de codigo de barras.';

COMMENT ON COLUMN core.sucursal.activo IS
  'Booleano legitimo: la sucursal opera o no opera. No es borrado logico.';


-- ---------------------------------------------------------------------
-- El enlace · una ruta entre DOS SEDES de dos empresas distintas
--
-- Vive en el esquema plataforma pero se crea en ESTE archivo porque
-- necesita core.sucursal, que nace veinte lineas mas arriba. Ponerlo en
-- 02_plataforma.sql seria una llave hacia una tabla que todavia no existe.
--
-- REEMPLAZA A core.empresa_asociada, que se retiro. Aquella unia EMPRESA
-- con EMPRESA y ese era su defecto: si la empresa A tiene las sedes A1 y A2
-- y lo que trabaja junto es A1 con B2, un vinculo "A trabaja con B" hace que
-- lo de A2 tambien le caiga a B, y B2 se vuelve inalcanzable. Lo que trabaja
-- junto son las sedes.
--
-- Y aquella tampoco era un acuerdo: la fila la escribia el propio remitente
-- y la otra parte ni la veia. LA CREA EL OPERADOR, porque para declararla un
-- cliente tendria que teclear el RTN y el codigo de sede del otro, que es
-- informacion confidencial y no es suya.
--
-- SIN RLS a proposito: no es de ninguna de las dos empresas. lis_app no la
-- lee directo -- pregunta por core.mis_enlaces(), que solo contesta su lado.
-- ---------------------------------------------------------------------

CREATE TABLE plataforma.enlace (
  enlace_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_a_id   bigint NOT NULL,
  sucursal_a_id  bigint NOT NULL,
  empresa_b_id   bigint NOT NULL,
  sucursal_b_id  bigint NOT NULL,
  vigente_desde  date NOT NULL DEFAULT CURRENT_DATE,
  vigente_hasta  date,
  creado_por     text NOT NULL,
  nota           text,

  CONSTRAINT ck_enlace_empresas_distintas CHECK (empresa_a_id <> empresa_b_id),
  -- >= y no >: una ruta creada por error se tiene que poder cortar el mismo
  -- dia. vigente_hasta es exclusiva, asi que desde = hasta significa que
  -- nunca estuvo viva -- que es exactamente lo que paso.
  CONSTRAINT ck_enlace_vigencia
    CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde),
  CONSTRAINT fk_enlace_sucursal_a FOREIGN KEY (sucursal_a_id, empresa_a_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id),
  CONSTRAINT fk_enlace_sucursal_b FOREIGN KEY (sucursal_b_id, empresa_b_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

COMMENT ON TABLE plataforma.enlace IS
  'Que dos SEDES de empresas distintas trabajan juntas. La crea el operador. '
  '"Estas dos empresas trabajan juntas" no se guarda: se deduce de que haya al '
  'menos una ruta vigente entre ellas.';

COMMENT ON COLUMN plataforma.enlace.creado_por IS
  'Texto y no llave foranea: el operador no es usuario de ninguna empresa (E-19).';

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

REVOKE ALL ON plataforma.enlace FROM PUBLIC;


-- ---------------------------------------------------------------------
-- Modulos contratados por sucursal · la licencia
--
-- Vive en plataforma y no en core porque LA ESCRIBE EL OPERADOR: el
-- laboratorio no decide que compro. Estaba en core con INSERT y UPDATE para
-- lis_app, y con eso una empresa podia encenderse un modulo que nadie le
-- vendio y apagar el que si pagaba (H-99).
--
-- Se define en ESTE archivo, como plataforma.enlace y por la misma razon:
-- necesita core.sucursal.
--
-- El laboratorio SI la lee -- RLS la recorta a su empresa -- porque de ella
-- salen el menu del administrador y la interseccion de usuario_puede().
--
-- La llave primaria compuesta es lo que la hace muchos a muchos: una sede con
-- cuatro modulos son cuatro filas; un modulo en dos sedes, dos filas.
-- ---------------------------------------------------------------------

CREATE TABLE plataforma.modulo_sucursal (
  sucursal_id     bigint NOT NULL,
  modulo_id       text   NOT NULL REFERENCES plataforma.modulo (modulo_id),
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  activo          boolean NOT NULL DEFAULT true,
  activado_en     timestamptz NOT NULL DEFAULT now(),
  desactivado_en  timestamptz,
  asignado_por    text NOT NULL,

  PRIMARY KEY (sucursal_id, modulo_id),
  -- Apagar un modulo tiene que dejar constancia de cuando (H-26).
  CONSTRAINT ck_modulo_sucursal_apagado
    CHECK (activo OR desactivado_en IS NOT NULL),
  CONSTRAINT fk_modulo_sucursal_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

COMMENT ON TABLE plataforma.modulo_sucursal IS
  'Que modulos contrato cada SEDE. La escribe el operador, igual que '
  'plataforma.enlace. Activar laboratorio clinico en una sucursal es una fila '
  'aqui; cuando exista imagenologia, es otra fila. El nucleo nunca aprende los '
  'nombres de las ramas.';

COMMENT ON COLUMN plataforma.modulo_sucursal.asignado_por IS
  'Texto y no llave foranea: el operador no es usuario de ninguna empresa (E-19).';

COMMENT ON COLUMN plataforma.modulo_sucursal.activo IS
  'Booleano legitimo. Apagarlo quita el acceso SIN borrar lo que el '
  'administrador configuro: rol_permiso guarda la intencion y sobrevive, esta '
  'columna guarda la licencia. Cuando el cliente vuelve a pagar, el acceso '
  'vuelve solo y nadie rearma ningun rol.';

-- Se lee, no se escribe. Su politica RLS esta en 05_rls_y_funciones.sql, con
-- las demas: aqui todavia no existe core.empresa_actual().
REVOKE ALL ON plataforma.modulo_sucursal FROM PUBLIC;


-- ---------------------------------------------------------------------
-- Empleado y usuario
-- ---------------------------------------------------------------------

CREATE TABLE core.empleado (
  empleado_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  nombres         text NOT NULL,
  apellidos       text NOT NULL,
  documento       text,
  telefono        text,
  correo          text,
  cargo           text,
  numero_colegiacion text,
  activo          boolean NOT NULL DEFAULT true,
  creado_en       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_empleado_empresa UNIQUE (empleado_id, empresa_id)
);

COMMENT ON TABLE core.empleado IS
  'La persona que trabaja aqui, exista o no una cuenta de usuario. No se vincula a '
  'plataforma.persona: ese registro es para resolver identidad de pacientes entre '
  'empresas, y un empleado no necesita eso.';

COMMENT ON COLUMN core.empleado.numero_colegiacion IS
  'Del bioquimico o del medico. Va impreso en el informe junto a la firma.';


CREATE TABLE core.rol (
  rol_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  nombre       text NOT NULL,
  descripcion  text,
  es_sistema   boolean NOT NULL DEFAULT false,

  CONSTRAINT uq_rol_empresa UNIQUE (rol_id, empresa_id),
  CONSTRAINT uq_rol_nombre  UNIQUE (empresa_id, nombre)
);

-- Sin creado_en: un rol se crea con la empresa y casi nunca se toca. La fecha
-- no la iba a leer nadie.

COMMENT ON COLUMN core.rol.es_sistema IS
  'Booleano legitimo: los cuatro roles con los que nace la empresa se marcan '
  'true. Nadie lo lee todavia -- falta la regla que impida que un administrador '
  'le quite usuario.administrar a su propio rol y deje a la empresa sin nadie '
  'que pueda crear usuarios (H-90).';

COMMENT ON CONSTRAINT uq_rol_nombre ON core.rol IS
  'Unico POR EMPRESA, no globalmente. Dos laboratorios distintos pueden tener '
  'cada uno su rol "Recepcion".';


CREATE TABLE core.usuario (
  usuario_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  empleado_id       bigint NOT NULL,
  rol_id            bigint NOT NULL,
  username          text   NOT NULL,
  password_hash     text   NOT NULL,
  estado            core.estado_usuario NOT NULL DEFAULT 'activo',
  intentos_fallidos smallint NOT NULL DEFAULT 0,
  ultimo_acceso_en  timestamptz,
  creado_en         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_usuario_empresa  UNIQUE (usuario_id, empresa_id),
  CONSTRAINT uq_usuario_empleado UNIQUE (empleado_id),
  CONSTRAINT ck_usuario_username CHECK (username ~ '^[a-z0-9._-]{3,40}$'),

  CONSTRAINT fk_usuario_empleado
    FOREIGN KEY (empleado_id, empresa_id)
    REFERENCES core.empleado (empleado_id, empresa_id),
  CONSTRAINT fk_usuario_rol
    FOREIGN KEY (rol_id, empresa_id)
    REFERENCES core.rol (rol_id, empresa_id)
);

-- Username unico por empresa. En minusculas, comparado sin distinguir mayusculas.
CREATE UNIQUE INDEX uq_usuario_username
  ON core.usuario (empresa_id, lower(username));

COMMENT ON COLUMN core.usuario.password_hash IS
  'Hash con argon2id o bcrypt. La columna se llama password_hash y no password '
  'para que nadie guarde ahi una contrasena en claro por descuido.';


CREATE TABLE core.rol_permiso (
  rol_id      bigint NOT NULL,
  permiso_id  text   NOT NULL REFERENCES plataforma.permiso (permiso_id),
  empresa_id  bigint NOT NULL REFERENCES core.empresa (empresa_id),

  PRIMARY KEY (rol_id, permiso_id),
  CONSTRAINT fk_rol_permiso_rol
    FOREIGN KEY (rol_id, empresa_id)
    REFERENCES core.rol (rol_id, empresa_id)
);


CREATE TABLE core.acceso_sucursal (
  usuario_id   bigint NOT NULL,
  sucursal_id  bigint NOT NULL,
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  creado_en    timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (usuario_id, sucursal_id),
  CONSTRAINT fk_acceso_usuario
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT fk_acceso_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

COMMENT ON TABLE core.acceso_sucursal IS
  'Un usuario puede operar en varias sucursales. Viene de lislabCli, que lo tenia '
  'bien; pruebareal lo habia retrocedido a una sucursal fija por usuario.';


-- ---------------------------------------------------------------------
-- Correlativos · numeros visibles al usuario
-- ---------------------------------------------------------------------

CREATE TABLE core.correlativo (
  correlativo_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id      bigint NOT NULL REFERENCES core.empresa (empresa_id),
  sucursal_id     bigint,
  tipo            core.tipo_correlativo NOT NULL,
  prefijo         text NOT NULL DEFAULT '',
  ancho           smallint NOT NULL DEFAULT 6,
  ultimo_valor    bigint NOT NULL DEFAULT 0,

  CONSTRAINT ck_correlativo_ancho CHECK (ancho BETWEEN 4 AND 12),
  CONSTRAINT fk_correlativo_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

CREATE UNIQUE INDEX uq_correlativo
  ON core.correlativo (empresa_id, tipo, coalesce(sucursal_id, 0));

COMMENT ON TABLE core.correlativo IS
  'El numero que ve el usuario es distinto del id interno. El id autoincremental '
  'le dice a cualquiera cuantos pacientes tienes; el correlativo es por empresa '
  'y puede reiniciarse sin tocar las llaves.';


-- ---------------------------------------------------------------------
-- Paciente · el expediente dentro de una empresa
-- ---------------------------------------------------------------------

CREATE TABLE core.paciente (
  paciente_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  expediente        text NOT NULL,
  -- Copia local de la identidad al momento de registrar.
  nombres           text NOT NULL,
  apellidos         text NOT NULL,
  nombre_completo   text GENERATED ALWAYS AS (apellidos || ', ' || nombres) STORED,
  tipo_documento    plataforma.tipo_documento NOT NULL DEFAULT 'ninguno',
  documento         text,
  fecha_nacimiento  date,
  sexo              plataforma.sexo NOT NULL DEFAULT 'no_especificado',
  telefono          text,
  correo            text,
  direccion         text,

  -- Fusion de duplicados: el registro perdedor apunta al ganador y no se borra.
  fusionado_en_paciente_id  bigint REFERENCES core.paciente (paciente_id),
  fusionado_en              timestamptz,
  fusionado_por_usuario_id  bigint,

  creado_por_usuario_id  bigint,
  creado_en       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_paciente_empresa    UNIQUE (paciente_id, empresa_id),
  CONSTRAINT uq_paciente_expediente UNIQUE (empresa_id, expediente),
  CONSTRAINT ck_paciente_documento CHECK (
    (tipo_documento =  'ninguno' AND documento IS NULL) OR
    (tipo_documento <> 'ninguno' AND documento IS NOT NULL AND btrim(documento) <> '')
  ),
  CONSTRAINT ck_paciente_fusion CHECK (
    (fusionado_en_paciente_id IS NULL     AND fusionado_en IS NULL) OR
    (fusionado_en_paciente_id IS NOT NULL AND fusionado_en IS NOT NULL)
  ),
  CONSTRAINT ck_paciente_no_se_fusiona_consigo
    CHECK (fusionado_en_paciente_id IS DISTINCT FROM paciente_id)
);

COMMENT ON TABLE core.paciente IS
  'El expediente de una persona DENTRO de una empresa. Aqui si vive lo clinico. '
  'Nunca se comparte entero con otra empresa: lo que cruza es un mensaje.';

COMMENT ON COLUMN core.paciente.expediente IS
  'La identidad real del paciente. La genera el sistema, no depende del documento, '
  'y por eso recepcion nunca tiene que inventar un documento falso para poder atender.';

COMMENT ON COLUMN core.paciente.fusionado_en_paciente_id IS
  'Si este registro resulto ser duplicado, apunta al que quedo. Las ordenes viejas '
  'siguen apuntando a este id; la lectura sigue el puntero. Nunca se borra una fila.';

-- Unico solo cuando hay documento, y por empresa.
CREATE UNIQUE INDEX uq_paciente_documento
  ON core.paciente (empresa_id, tipo_documento, documento)
  WHERE documento IS NOT NULL AND fusionado_en_paciente_id IS NULL;

CREATE INDEX ix_paciente_nombre
  ON core.paciente (empresa_id, nombre_completo text_pattern_ops)
  WHERE fusionado_en_paciente_id IS NULL;


-- ---------------------------------------------------------------------
-- La referencia externa · como llama la OTRA empresa a mi paciente
--
-- Reemplaza a core.paciente.persona_id y con ella a toda plataforma.persona.
-- Aquel modelo compartia una fila de identidad entre empresas; este no
-- comparte nada: cada lado anota EN SU PROPIA FICHA como lo llama el otro,
-- igual que se anota el numero de poliza de un seguro.
--
-- No es llave foranea hacia el expediente ajeno y nunca lo sera: no hay
-- integridad referencial entre empresas. Si esta mal, la arregla quien la
-- escribio, y esa correccion no afecta a nadie mas (F6-1).
--
-- NACE DE UNA CONFIRMACION HUMANA con el paciente presente, o de un cotejo de
-- dos factores que el sistema pudo resolver sin dudar. Nunca de elegir en una
-- lista (F6-2). Por eso confirmado_por y confirmado_en son obligatorios.
--
-- La contraparte se nombra por empresa y no por enlace: el paciente es del
-- hospital sin importar por cual de sus sedes entro.
-- ---------------------------------------------------------------------

CREATE TABLE core.paciente_referencia (
  referencia_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id             bigint NOT NULL REFERENCES core.empresa (empresa_id),
  paciente_id            bigint NOT NULL,
  contraparte_empresa_id bigint NOT NULL REFERENCES core.empresa (empresa_id),

  -- Como lo llama el otro. Texto suyo, no mio: puede tener cualquier forma.
  expediente_externo     text NOT NULL,

  confirmado_por_usuario_id bigint NOT NULL,
  confirmado_en          timestamptz NOT NULL DEFAULT now(),
  nota                   text,

  -- Nada se borra. Una referencia mal confirmada se anula con motivo y se
  -- escribe otra: que alguien haya confundido dos pacientes es justo lo que
  -- hay que poder auditar despues.
  anulada_en             timestamptz,
  anulado_motivo         text,

  CONSTRAINT uq_paciente_referencia UNIQUE (referencia_id, empresa_id),
  CONSTRAINT ck_referencia_contraparte
    CHECK (contraparte_empresa_id <> empresa_id),
  CONSTRAINT ck_referencia_expediente
    CHECK (btrim(expediente_externo) <> ''),
  CONSTRAINT ck_referencia_anulacion CHECK (
    (anulada_en IS NULL     AND anulado_motivo IS NULL) OR
    (anulada_en IS NOT NULL AND anulado_motivo IS NOT NULL
     AND btrim(anulado_motivo) <> '')
  ),
  CONSTRAINT fk_referencia_paciente
    FOREIGN KEY (paciente_id, empresa_id)
    REFERENCES core.paciente (paciente_id, empresa_id),
  CONSTRAINT fk_referencia_usuario
    FOREIGN KEY (confirmado_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE core.paciente_referencia IS
  'Un dato externo anotado sobre el propio paciente. Cada empresa guarda la suya '
  'y nadie mas la toca. No hay llave hacia el expediente ajeno a proposito.';

COMMENT ON COLUMN core.paciente_referencia.contraparte_empresa_id IS
  'Menciona a otra empresa pero no le da ningun privilegio: RLS impide leer esa '
  'fila, asi que del otro lado es un numero opaco.';

-- Una sola referencia vigente por contraparte. El historico si puede tener
-- varias, una por cada vez que hubo que corregir.
CREATE UNIQUE INDEX uq_referencia_vigente
  ON core.paciente_referencia (empresa_id, paciente_id, contraparte_empresa_id)
  WHERE anulada_en IS NULL;

-- Por aqui entra el cotejo: "me llego H-000123 del hospital, quien es aqui?"
CREATE INDEX ix_referencia_externa
  ON core.paciente_referencia (empresa_id, contraparte_empresa_id, expediente_externo)
  WHERE anulada_en IS NULL;


-- ---------------------------------------------------------------------
-- El mensaje · lo que cruza entre dos empresas
--
-- Reemplaza a audit.derivacion, que era UNA fila que veian DOS empresas, con
-- rls_derivacion -- la unica politica del sistema que comparaba dos empresa_id.
-- Aqui hay UNA FILA DE CADA LADO, cada una con su empresa_id y la RLS de
-- todas. Ninguna fila compartida, ninguna llave hacia el otro inquilino.
--
-- Un mensaje NO SE ACEPTA, SE RECIBE: la aceptacion se mudo al enlace. Una
-- boleta que llega es trabajo, no una propuesta.
--
-- sucursal_id sale del enlace, copiada aqui para que la bandeja de una sede se
-- consulte sin salir de core. NO puede ser nula: sin enlace el mensaje no sale,
-- la funcion lo rechaza en el origen.
--
-- folio es uuid y no el mensaje_id: si viajara el numero de secuencia, el
-- mensaje 4821 le contaria al otro cuantos mensajes mandas.
-- ---------------------------------------------------------------------

CREATE TABLE core.mensaje (
  mensaje_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  enlace_id         bigint NOT NULL REFERENCES plataforma.enlace (enlace_id),
  sucursal_id       bigint NOT NULL,
  direccion         core.direccion_mensaje NOT NULL,
  tipo              core.tipo_mensaje NOT NULL,
  folio             uuid NOT NULL DEFAULT gen_random_uuid(),
  responde_a_folio  uuid,
  contenido         jsonb NOT NULL,
  estado            core.estado_mensaje NOT NULL DEFAULT 'pendiente',
  creado_en         timestamptz NOT NULL DEFAULT now(),
  entregado_en      timestamptz,
  trabajado_en      timestamptz,

  CONSTRAINT uq_mensaje_empresa UNIQUE (mensaje_id, empresa_id),
  -- el mismo folio existe dos veces, una de cada lado: el unico es por empresa
  CONSTRAINT uq_mensaje_folio UNIQUE (empresa_id, folio),
  CONSTRAINT ck_mensaje_no_se_responde_solo
    CHECK (responde_a_folio IS NULL OR responde_a_folio <> folio),
  -- Lo enviado se entrega; lo recibido se trabaja. Un estado del otro lado en
  -- mi propia fila seria mentira: yo no se si ya lo trabajaron. Me entero
  -- porque vuelve un resultado, que es otro mensaje.
  CONSTRAINT ck_mensaje_estado_segun_direccion CHECK (
    (direccion = 'enviado'  AND estado IN ('pendiente','entregado')) OR
    (direccion = 'recibido' AND estado IN ('recibido','trabajado','descartado'))
  ),
  CONSTRAINT fk_mensaje_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

COMMENT ON TABLE core.mensaje IS
  'Una fila de cada lado, nunca compartida. Las escribe core.entregar(), que es '
  'el UNICO punto del sistema donde un dato pasa de una empresa a otra.';

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



-- ---------------------------------------------------------------------
-- Medico solicitante · retirado a proposito (H-98)
-- ---------------------------------------------------------------------
--
-- Aqui vivia core.medico, y con ella core.episodio.medico_solicitante_id.
--
-- Por que se fue. En la practica el paciente llega con una boleta que dice
-- "Dr. Perez" y nada mas. La tabla pedia nombres y apellidos por separado, asi
-- que recepcion tenia que partir una sola palabra en dos campos obligatorios:
-- tres recepcionistas, tres costumbres. Y sin colegiacion no habia ninguna
-- unicidad -- uq_medico_colegiacion era un indice parcial WHERE colegiacion IS
-- NOT NULL -- de modo que "Dr Perez", "Dr. Perez" y "PEREZ" convivian sin que
-- nada lo impidiera, y no habia funcion de fusion para repararlo despues. Un
-- catalogo que se ensucia solo y no se puede limpiar.
--
-- Ademas no cargaba peso: ninguna funcion la leia, y la unica llave foranea
-- que la apuntaba era anulable.
--
-- Se decide cuando este armado el flujo de admision, que es donde se ve si el
-- medico tiene que ser una ficha o basta un campo de texto con lo que dice la
-- boleta. Volver a ponerla cuesta poco: una tabla sin dependencias, o una sola
-- columna en core.episodio.
--
-- Lo que SI sigue existiendo: el valor 'medico' de core.tipo_convenio. El
-- medico que tiene acuerdo de precios se nombra ahi, en convenio.nombre.


-- ---------------------------------------------------------------------
-- Convenio · por donde entro el paciente
-- ---------------------------------------------------------------------

CREATE TABLE core.convenio (
  convenio_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id            bigint NOT NULL REFERENCES core.empresa (empresa_id),
  nombre                text NOT NULL,
  tipo                  core.tipo_convenio NOT NULL,
  modalidad_cobro       core.modalidad_cobro NOT NULL DEFAULT 'particular',
  copago_porcentaje     numeric(5,2),
  dia_corte             smallint,
  recibe_copia_informe  boolean NOT NULL DEFAULT false,
  es_predeterminado     boolean NOT NULL DEFAULT false,

  -- El puente hacia el futuro: hoy NULL, manana apunta a la clinica como tenant.
  empresa_destino_id    bigint REFERENCES core.empresa (empresa_id),

  rtn                   text,
  contacto              text,
  telefono              text,
  activo                boolean NOT NULL DEFAULT true,
  creado_en             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_convenio_empresa UNIQUE (convenio_id, empresa_id),
  CONSTRAINT uq_convenio_nombre  UNIQUE (empresa_id, nombre),
  CONSTRAINT ck_convenio_copago CHECK (
    (modalidad_cobro <> 'copago' AND copago_porcentaje IS NULL) OR
    (modalidad_cobro =  'copago' AND copago_porcentaje BETWEEN 0 AND 100)
  ),
  CONSTRAINT ck_convenio_corte CHECK (
    (modalidad_cobro <> 'credito_mensual' AND dia_corte IS NULL) OR
    (modalidad_cobro =  'credito_mensual' AND dia_corte BETWEEN 1 AND 28)
  ),
  CONSTRAINT ck_convenio_destino_distinto
    CHECK (empresa_destino_id IS DISTINCT FROM empresa_id)
);

COMMENT ON COLUMN core.convenio.empresa_destino_id IS
  'Hoy la clinica es una fila de catalogo con esta columna en NULL. El dia que la '
  'clinica entre al sistema, esta columna apunta a su empresa y la solicitud pasa '
  'de papel a electronica. Sin migrar una sola orden.';

-- Un solo convenio predeterminado (el "particular") por empresa.
CREATE UNIQUE INDEX uq_convenio_predeterminado
  ON core.convenio (empresa_id)
  WHERE es_predeterminado;


-- ---------------------------------------------------------------------
-- Episodio · el tronco
-- ---------------------------------------------------------------------

CREATE TABLE core.episodio (
  episodio_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id             bigint NOT NULL REFERENCES core.empresa (empresa_id),
  sucursal_id            bigint NOT NULL,
  paciente_id            bigint NOT NULL,
  convenio_id            bigint NOT NULL,
  mensaje_id             bigint,   -- la solicitud que trajo a este paciente
  numero                 text NOT NULL,
  estado                 core.estado_episodio NOT NULL DEFAULT 'abierto',
  urgente                boolean NOT NULL DEFAULT false,
  observacion            text,
  anulado_motivo         text,
  creado_por_usuario_id  bigint NOT NULL,
  creado_en              timestamptz NOT NULL DEFAULT now(),
  cerrado_en             timestamptz,

  CONSTRAINT uq_episodio_empresa UNIQUE (episodio_id, empresa_id),
  CONSTRAINT uq_episodio_numero  UNIQUE (empresa_id, numero),
  CONSTRAINT ck_episodio_anulado CHECK (
    estado <> 'anulado' OR (anulado_motivo IS NOT NULL AND btrim(anulado_motivo) <> '')
  ),

  CONSTRAINT fk_episodio_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id),
  CONSTRAINT fk_episodio_paciente
    FOREIGN KEY (paciente_id, empresa_id)
    REFERENCES core.paciente (paciente_id, empresa_id),
  CONSTRAINT fk_episodio_convenio
    FOREIGN KEY (convenio_id, empresa_id)
    REFERENCES core.convenio (convenio_id, empresa_id),
  CONSTRAINT fk_episodio_usuario
    FOREIGN KEY (creado_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE core.episodio IS
  'Una visita del paciente. Es el tronco: existe aunque el laboratorio no participe. '
  'La orden de laboratorio, y manana la de imagenologia, cuelgan de aqui.';

CREATE INDEX ix_episodio_pendientes
  ON core.episodio (empresa_id, sucursal_id, creado_en DESC)
  WHERE estado = 'abierto';

CREATE INDEX ix_episodio_paciente
  ON core.episodio (empresa_id, paciente_id, creado_en DESC);


-- ---------------------------------------------------------------------
-- Informe · transversal, no de una rama
-- ---------------------------------------------------------------------

CREATE TABLE core.informe (
  informe_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  episodio_id  bigint NOT NULL,
  modulo_id    text   NOT NULL REFERENCES plataforma.modulo (modulo_id),
  numero       text   NOT NULL,
  estado       core.estado_informe NOT NULL DEFAULT 'borrador',

  CONSTRAINT uq_informe_empresa UNIQUE (informe_id, empresa_id),
  CONSTRAINT uq_informe_numero  UNIQUE (empresa_id, numero),
  CONSTRAINT fk_informe_episodio
    FOREIGN KEY (episodio_id, empresa_id)
    REFERENCES core.episodio (episodio_id, empresa_id)
);

COMMENT ON TABLE core.informe IS
  'Vive en el nucleo por el resultado de la prueba de imagenologia: las dos ramas '
  'emiten un documento validado, versionado, firmado y entregado, con el mismo '
  'comportamiento. Notese que NO apunta a la orden: es la rama la que apunta al '
  'informe. El nucleo nunca conoce a las ramas.';


CREATE TABLE core.informe_version (
  informe_version_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id             bigint NOT NULL REFERENCES core.empresa (empresa_id),
  informe_id             bigint NOT NULL,
  version                integer NOT NULL,
  motivo_correccion      text,
  archivo_ruta           text,
  archivo_hash           text,
  emitido_por_usuario_id bigint NOT NULL,
  emitido_en             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_informe_version UNIQUE (informe_id, version),
  CONSTRAINT ck_informe_version_positiva CHECK (version >= 1),
  CONSTRAINT ck_informe_version_motivo
    CHECK (version = 1 OR (motivo_correccion IS NOT NULL AND btrim(motivo_correccion) <> '')),
  CONSTRAINT fk_informe_version_informe
    FOREIGN KEY (informe_id, empresa_id)
    REFERENCES core.informe (informe_id, empresa_id),
  CONSTRAINT fk_informe_version_usuario
    FOREIGN KEY (emitido_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON CONSTRAINT ck_informe_version_motivo ON core.informe_version IS
  'De la version 2 en adelante hay que decir por que se corrigio. La base lo exige, '
  'no la interfaz.';


-- ---------------------------------------------------------------------
-- Entrega · el ultimo paso del flujo
-- ---------------------------------------------------------------------

CREATE TABLE core.entrega (
  entrega_id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id                bigint NOT NULL REFERENCES core.empresa (empresa_id),
  informe_version_id        bigint NOT NULL REFERENCES core.informe_version (informe_version_id),
  medio                     core.medio_entrega NOT NULL,
  entregado_a               text NOT NULL,
  parentesco                text,
  documento_receptor        text,
  entregado_por_usuario_id  bigint NOT NULL,
  entregado_en              timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT fk_entrega_usuario
    FOREIGN KEY (entregado_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE core.entrega IS
  'Quien recibio el informe, cuando y por que medio. Se registra la VERSION '
  'entregada: si despues se corrige, se sabe quien tiene en la mano la version vieja.';
