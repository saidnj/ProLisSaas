-- =====================================================================
-- ProLisSaas - 02 - Las tablas
--
-- TODAS las tablas del sistema, en orden de dependencia, con sus llaves,
-- restricciones y comentarios. Los indices van en 03, los privilegios y las
-- politicas RLS en 05.
--
-- Dos reglas que se cumplen sin excepcion:
--   1. Toda tabla de dominio lleva empresa_id NOT NULL.
--   2. Todo padre declara UNIQUE (<tabla>_id, empresa_id) y todo hijo lo
--      referencia con llave foranea compuesta. Eso hace IMPOSIBLE colgar una
--      fila de un padre de otra empresa, aunque el codigo se equivoque.
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 02_plataforma.sql

-- =====================================================================
-- ProLisSaas - 02 - Esquema plataforma
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
-- Los parches aplicados a esta base
--
-- Cada parche de db/parches/ anota su nombre al terminar y se salta solo si
-- ya esta. Una base cargada desde estos archivos los trae todos anotados
-- (06_semillas.sql), porque ya los contiene.
-- ---------------------------------------------------------------------
CREATE TABLE plataforma.migracion (
  nombre       text PRIMARY KEY,
  aplicado_en  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE plataforma.migracion IS
  'Que parches de db/parches/ se le aplicaron a esta base y cuando. Lo escribe '
  'cada parche al final; lo lee cada parche al principio para no repetirse.';

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
  nivel        plataforma.nivel_permiso NOT NULL DEFAULT 'normal',
  CONSTRAINT ck_permiso_id_formato
    CHECK (permiso_id ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
);

COMMENT ON TABLE plataforma.permiso IS
  'El permiso nombra una accion del dominio (resultado.validar), nunca una ruta HTTP. '
  'Atar permisos a rutas acopla la autorizacion a la forma de la URL: cambiar la URL '
  'cambia quien puede hacer que.';


-- ---------------------------------------------------------- 03_core.sql

-- =====================================================================
-- ProLisSaas - 03 - Esquema core (el nucleo)
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
-- Empresa - el tenant
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
-- El enlace - una ruta entre DOS SEDES de dos empresas distintas
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

-- ---------------------------------------------------------------------
-- Modulos contratados por sucursal - la licencia
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
  es_fijo      boolean NOT NULL DEFAULT false,
  activo       boolean NOT NULL DEFAULT true,

  CONSTRAINT uq_rol_empresa UNIQUE (rol_id, empresa_id)
  -- El nombre unico por empresa es un indice sobre su llave (03_indices.sql,
  -- uq_rol_nombre): "Recepcion" y "recepcion" son el mismo rol.
);

-- Sin creado_en: un rol se crea con la empresa y casi nunca se toca. La fecha
-- no la iba a leer nadie.
COMMENT ON COLUMN core.rol.es_sistema IS
  'true solo en el rol del PROPIETARIO, la cuenta que el operador entrega con la '
  'empresa. Lo leen crear_usuario, cambiar_rol y asignar_permisos_a_rol: ese rol no '
  'se asigna, no se cambia y sus permisos no se editan. Con eso siempre queda alguien '
  'que pueda crear usuarios (H-90). Traspasarlo es del operador, no del LIS.';

COMMENT ON COLUMN core.rol.es_fijo IS
  'true en los roles que ENTREGA EL OPERADOR con la empresa: Propietario y '
  'Administrador. Desde el LIS no se editan (nombre, descripcion, permisos) ni se '
  'desactivan: son la garantia de que la empresa siempre tiene quien administre y de '
  'que "Administrador" significa lo mismo en todos los clientes. Los mantiene el '
  'operador. Si el cliente quiere un administrador a su medida, el propietario crea '
  'otro rol con usuario.administrar, y ese si es suyo.';

COMMENT ON COLUMN core.rol.activo IS
  'false = ya no se asigna: sale del catalogo y crear_usuario / cambiar_rol lo '
  'rechazan. No se puede desactivar un rol que alguien tenga puesto '
  '(desactivar_rol se niega y dice cuantos): asi nunca existe una sesion con rol '
  'desactivado y usuario_puede() no necesita un caso aparte.';

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

COMMENT ON COLUMN core.usuario.password_hash IS
  'Hash con argon2id o bcrypt. La columna se llama password_hash y no password '
  'para que nadie guarde ahi una contrasena en claro por descuido.';

-- ---------------------------------------------------------------------
-- core.activacion - como se estrena una contrasena
--
-- El admin NUNCA conoce la contrasena de nadie (F1-2). Lo que entrega es un
-- CODIGO, que no es lo mismo:
--
--                        el codigo          la contrasena
--   sirve para entrar     NO                si
--   sirve para            definir la clave  trabajar
--   quien lo sabe         admin y persona   solo la persona
--   cuanto vive           un uso, 24 horas  hasta que la cambie
--
-- El mismo mecanismo sirve para el reseteo: el usuario vuelve a
-- pendiente_activacion y se le genera otro codigo. Un solo camino.
--
-- lis_app NO TIENE NINGUN PRIVILEGIO sobre esta tabla, ni SELECT. Solo la
-- tocan las funciones SECURITY DEFINER. Es una credencial: la aplicacion no
-- tiene por que poder pasearse por aqui.
-- ---------------------------------------------------------------------
CREATE TABLE core.activacion (
  activacion_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  usuario_id            bigint NOT NULL,
  empresa_id            bigint NOT NULL REFERENCES core.empresa (empresa_id),

  -- Hash argon2 del codigo, no el codigo. Si alguien lee esta tabla no puede
  -- activar cuentas ajenas. Misma historia de hash que password_hash: una
  -- sola, para que nadie dude de cual usar donde.
  codigo_hash           text   NOT NULL,

  vence_en              timestamptz NOT NULL,
  intentos_fallidos     smallint NOT NULL DEFAULT 0,

  usado_en              timestamptz,
  anulado_en            timestamptz,
  anulado_motivo        text,

  -- Quien lo genero. NULL cuando lo hizo el operador de plataforma, que no
  -- es usuario del producto (E-19).
  creado_por_usuario_id bigint,
  creado_en             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_activacion_vence CHECK (vence_en > creado_en),

  -- Usado y anulado se excluyen: o se gasto, o lo reemplazo otro.
  CONSTRAINT ck_activacion_destino
    CHECK (usado_en IS NULL OR anulado_en IS NULL),

  -- Anular exige motivo, como todo lo que se anula en este sistema.
  CONSTRAINT ck_activacion_motivo
    CHECK ((anulado_en IS NULL) = (anulado_motivo IS NULL)),

  CONSTRAINT fk_activacion_usuario
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT fk_activacion_creador
    FOREIGN KEY (creado_por_usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id)
);

COMMENT ON TABLE core.activacion IS
  'Codigos de un solo uso para estrenar o resetear una contrasena. El codigo '
  'se guarda hasheado y se muestra en claro UNA sola vez, al generarlo.';

COMMENT ON COLUMN core.activacion.codigo_hash IS
  'Hash argon2 del codigo. En claro no se guarda en ninguna parte: si se '
  'pierde, se genera otro.';

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

  -- Quitarle una sede a alguien es un UPDATE, no un DELETE -- igual que todo
  -- lo demas aqui. La fila se queda y dice que el acceso se retiro, cuando y
  -- por que. Que en marzo Gabriela pudiera entrar a la sede Norte es un hecho
  -- que paso: borrarlo no lo deshace, solo lo esconde.
  --
  -- Volver a darle acceso es el UPDATE contrario, sobre la misma fila (la
  -- llave primaria es el par usuario-sucursal). Eso conserva el estado actual
  -- y el ultimo retiro; el recorrido completo -- dado, quitado, vuelto a dar
  -- -- es trabajo de audit.evento, que guarda antes y despues (E-22).
  activo          boolean NOT NULL DEFAULT true,
  retirado_en     timestamptz,
  retirado_motivo text,

  PRIMARY KEY (usuario_id, sucursal_id),

  -- Retirar deja constancia de cuando. Mismo patron que modulo_sucursal.
  CONSTRAINT ck_acceso_retirado
    CHECK (activo OR retirado_en IS NOT NULL),

  -- Y exige motivo, como todo lo que se anula en este sistema.
  CONSTRAINT ck_acceso_motivo
    CHECK ((retirado_en IS NULL) = (retirado_motivo IS NULL)),

  CONSTRAINT fk_acceso_usuario
    FOREIGN KEY (usuario_id, empresa_id)
    REFERENCES core.usuario (usuario_id, empresa_id),
  CONSTRAINT fk_acceso_sucursal
    FOREIGN KEY (sucursal_id, empresa_id)
    REFERENCES core.sucursal (sucursal_id, empresa_id)
);

COMMENT ON TABLE core.acceso_sucursal IS
  'En que sedes puede pararse cada usuario. Se da con un INSERT y se quita '
  'con un UPDATE que pone activo=false con motivo: la fila nunca se borra.';

COMMENT ON COLUMN core.acceso_sucursal.activo IS
  'false = el acceso se retiro. Las consultas de sesion filtran por esto; '
  'un usuario sin ninguna sede activa no puede entrar a ningun lado.';

COMMENT ON TABLE core.acceso_sucursal IS
  'Un usuario puede operar en varias sucursales. Viene de lislabCli, que lo tenia '
  'bien; pruebareal lo habia retrocedido a una sucursal fija por usuario.';

-- ---------------------------------------------------------------------
-- Correlativos - numeros visibles al usuario
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

COMMENT ON TABLE core.correlativo IS
  'El numero que ve el usuario es distinto del id interno. El id autoincremental '
  'le dice a cualquiera cuantos pacientes tienes; el correlativo es por empresa '
  'y puede reiniciarse sin tocar las llaves.';

-- ---------------------------------------------------------------------
-- Paciente - el expediente dentro de una empresa
-- ---------------------------------------------------------------------
CREATE TABLE core.paciente (
  paciente_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id        bigint NOT NULL REFERENCES core.empresa (empresa_id),
  expediente        text NOT NULL,
  -- El nombre tal como lo dicta el paciente, en un solo campo: recepcion no
  -- separa nombres de apellidos (y en un laboratorio no hace falta).
  nombre_completo   text NOT NULL,
  tipo_documento    plataforma.tipo_documento NOT NULL DEFAULT 'ninguno',
  documento         text,
  -- Obligatoria: los rangos de referencia dependen de la edad. Cuando no se
  -- sabe la fecha, recepcion pone la edad y la base calcula la fecha,
  -- marcada como estimada; la edad no se guarda nunca.
  fecha_nacimiento  date NOT NULL,
  fecha_nacimiento_estimada boolean NOT NULL DEFAULT false,
  -- Obligatorio y biologico: decide el rango de referencia. Sin valor por
  -- omision a proposito: se pregunta.
  sexo              plataforma.sexo NOT NULL,
  telefono          text,
  correo            text,
  direccion         text,

  -- Fusion de duplicados: el registro perdedor apunta al ganador y no se borra.
  fusionado_en_paciente_id  bigint REFERENCES core.paciente (paciente_id),
  fusionado_en              timestamptz,
  fusionado_por_usuario_id  bigint,

  -- Quien lo registro y quien lo edito esta en audit.evento (paciente.crear,
  -- paciente.editar): no hay creado_por ni actualizado_en (E-22).
  creado_en       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_paciente_empresa    UNIQUE (paciente_id, empresa_id),
  CONSTRAINT uq_paciente_expediente UNIQUE (empresa_id, expediente),
  CONSTRAINT ck_paciente_nombre CHECK (length(btrim(nombre_completo)) BETWEEN 2 AND 120),
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

COMMENT ON COLUMN core.paciente.fecha_nacimiento_estimada IS
  'true cuando la fecha salio de una edad ("25 anios", "6 meses") y no de un '
  'documento. Una fecha confirmada no vuelve a ser estimada (editar_paciente).';

COMMENT ON COLUMN core.paciente.fusionado_en_paciente_id IS
  'Si este registro resulto ser duplicado, apunta al que quedo. Las ordenes viejas '
  'siguen apuntando a este id; la lectura sigue el puntero. Nunca se borra una fila.';

-- ---------------------------------------------------------------------
-- La referencia externa - como llama la OTRA empresa a mi paciente
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

-- ---------------------------------------------------------------------
-- El mensaje - lo que cruza entre dos empresas
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

-- ---------------------------------------------------------------------
-- Medico solicitante - retirado a proposito (H-98)
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
-- Convenio - por donde entro el paciente
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

-- ---------------------------------------------------------------------
-- Episodio - el tronco
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

-- ---------------------------------------------------------------------
-- Informe - transversal, no de una rama
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
-- Entrega - el ultimo paso del flujo
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


-- ---------------------------------------------------------- 04_audit.sql

-- =====================================================================
-- ProLisSaas - 04 - Esquema audit
--
-- Dos cosas viven aqui: el rastro de quien hizo que, y el unico puente
-- autorizado entre dos empresas. Ninguna fila de este esquema se
-- actualiza ni se borra jamas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Derivacion - el puente entre empresas
-- ---------------------------------------------------------------------

/* audit.derivacion se retiro.
   Era UNA fila que veian DOS empresas, con estados que negociaban
   (solicitada -> aceptada | rechazada). La reemplaza core.mensaje: una fila
   de cada lado, con la RLS de todas y estados de entrega, no de negociacion.
   La aceptacion se mudo una sola vez a la relacion (plataforma.enlace).
   Ver documentacion/flujos/06 y H-73. */


-- ---------------------------------------------------------------------
-- Evento - el rastro
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

-- ---------------------------------------------------------------------
-- Llaves que faltaban por orden de creacion
-- ---------------------------------------------------------------------
ALTER TABLE core.episodio
  ADD CONSTRAINT fk_episodio_mensaje
  FOREIGN KEY (mensaje_id, empresa_id)
  REFERENCES core.mensaje (mensaje_id, empresa_id);

ALTER TABLE core.paciente
  ADD CONSTRAINT fk_paciente_fusionado_por
  FOREIGN KEY (fusionado_por_usuario_id, empresa_id)
  REFERENCES core.usuario (usuario_id, empresa_id);


-- ---------------------------------------------------------- 11_lab_catalogo.sql

-- =====================================================================
-- ProLisSaas - 11 - Catalogo del laboratorio
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
-- Analito - donde vive el resultado
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
-- Prueba - lo que se pide y se cobra
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
-- Precio - por sucursal y convenio, con vigencia
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

COMMENT ON TABLE lab.precio_prueba IS
  'Se resuelve de lo mas especifico a lo mas general: convenio y sucursal, luego '
  'convenio, luego sucursal, luego lista. Nunca se actualiza un precio: se cierra '
  'la vigencia del anterior y se inserta el nuevo.';

-- ---------------------------------------------------------------------
-- Rango de referencia - del laboratorio, no del equipo
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


-- ---------------------------------------------------------- 12_lab_operacion.sql

-- =====================================================================
-- ProLisSaas - 12 - Operacion del laboratorio
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

-- ---------------------------------------------------------------------
-- Muestra - el tubo
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
-- Item de orden - un examen pedido
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

-- ---------------------------------------------------------------------
-- Resultado - una fila por analito, inmutable
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


-- ---------------------------------------------------------- 13_integra.sql

-- =====================================================================
-- ProLisSaas - 13 - Integracion con analizadores
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
-- Mapeo de codigos - "HGB" del equipo = analito Hemoglobina
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


-- ---------------------------------------------------------- 17_comercial.sql

-- ---------------------------------------------------------------------
-- El cliente - quien te contrato
--
-- Es la raiz de todo este esquema y no existia. Antes el contrato colgaba
-- directo de core.empresa, o sea de un inquilino tecnico del LIS, y no habia
-- donde guardar a quien facturarle. Con eso no se puede emitir una factura.
--
-- Un cliente puede tener VARIAS empresas: un grupo con dos laboratorios que
-- no se ven entre si es un contrato, una factura y dos inquilinos aislados.
-- Por eso la union es una tabla y no una columna -- y de todos modos E-18 no
-- deja poner cliente_id en core.empresa, porque core nunca referencia
-- comercial. La flecha va en una sola direccion.
-- ---------------------------------------------------------------------
CREATE TABLE comercial.cliente (
  cliente_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre            text NOT NULL,
  tipo              comercial.tipo_cliente NOT NULL,
  rtn               text,
  direccion_fiscal  text,
  nota              text,
  creado_en         timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE comercial.cliente IS
  'La contraparte del contrato: a quien le facturas vos. No es la empresa -- la '
  'empresa es el inquilino del LIS. Un cliente puede tener varias.';

COMMENT ON COLUMN comercial.cliente.rtn IS
  'El RTN con el que se le factura A EL. No confundir con core.empresa.rtn, que '
  'es con el que la empresa le factura a sus pacientes. Casi siempre son el '
  'mismo numero y por eso conviene tenerlos separados desde ahora.';

-- ---------------------------------------------------------------------
-- Contactos - a quien se le llama
--
-- Varios por cliente, porque el que firma casi nunca es el que paga y
-- ninguno de los dos es el que contesta cuando se cae el analizador.
-- ---------------------------------------------------------------------
CREATE TABLE comercial.contacto (
  contacto_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cliente_id    bigint NOT NULL REFERENCES comercial.cliente (cliente_id),
  nombre        text NOT NULL,
  papel         comercial.papel_contacto NOT NULL DEFAULT 'general',
  cargo         text,
  telefono      text,
  correo        text,
  activo        boolean NOT NULL DEFAULT true,
  nota          text,
  creado_en     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN comercial.contacto.activo IS
  'Booleano legitimo: la persona sigue en el puesto o ya no. No es borrado '
  'logico -- un contacto que se fue se queda, porque firmo cosas.';

CREATE TABLE comercial.cliente_empresa (
  cliente_id   bigint NOT NULL REFERENCES comercial.cliente (cliente_id),
  empresa_id   bigint NOT NULL REFERENCES core.empresa (empresa_id),
  desde        date NOT NULL DEFAULT CURRENT_DATE,
  hasta        date,
  nota         text,

  PRIMARY KEY (cliente_id, empresa_id, desde),
  -- >= por lo mismo que plataforma.enlace: una fila creada por error se
  -- corta el mismo dia. El rango [desde, hasta) queda vacio y no solapa nada.
  CONSTRAINT ck_cliente_empresa_vigencia
    CHECK (hasta IS NULL OR hasta >= desde),

  -- Una empresa tiene UN dueno en cada fecha. El historico si puede tener
  -- varios, uno detras de otro.
  --
  -- Un indice unico parcial sobre las filas abiertas no alcanza: impide dos
  -- duenos sin fecha de fin, pero deja pasar dos vigencias cerradas que se
  -- solapan, y entonces registrar_evento_cliente() leeria dos duenos validos
  -- para el mismo dia. El rango lo cierra de verdad.
  CONSTRAINT ex_cliente_empresa_sin_solape
    EXCLUDE USING gist (
      empresa_id WITH =,
      daterange(desde, hasta, '[)') WITH &&
    )
);

COMMENT ON TABLE comercial.cliente_empresa IS
  'La unica union entre el negocio y el producto. Vive de este lado porque core '
  'nunca referencia comercial (E-18).';

-- ---------------------------------------------------------------------
-- El catalogo de motivos, con su politica
--
-- Es lo que hace que definir las politicas mas adelante sea editar filas y
-- no tocar codigo. Hoy casi todas estan en blanco a proposito: la estructura
-- ya esta y solo hay que llenarla.
-- ---------------------------------------------------------------------
CREATE TABLE comercial.motivo (
  motivo_id          text PRIMARY KEY,
  tipo_evento        comercial.tipo_evento NOT NULL,
  nombre             text NOT NULL,
  descripcion        text,

  -- La politica. Que se le aplica al cliente cuando se usa este motivo.
  nivel_inmediato    core.nivel_acceso NOT NULL DEFAULT 'solo_lectura',
  dias_plazo         integer,
  nivel_al_vencer    core.nivel_acceso,
  estado_al_vencer   core.estado_empresa,
  aviso_previo_dias  smallint NOT NULL DEFAULT 0,
  permite_exportar   boolean  NOT NULL DEFAULT true,
  reversible         boolean  NOT NULL DEFAULT true,
  requiere_nota      boolean  NOT NULL DEFAULT false,

  -- Mientras esto sea false, el motivo no tiene politica pensada todavia y
  -- el sistema aplica lo seguro: solo_lectura y aviso, nunca completo.
  -- Es lo que impide que un valor en blanco se lea como "sin restriccion".
  politica_definida  boolean  NOT NULL DEFAULT false,

  activo             boolean  NOT NULL DEFAULT true,
  creado_en          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_motivo_formato    CHECK (motivo_id ~ '^[a-z][a-z0-9_]*$'),
  CONSTRAINT ck_motivo_plazo      CHECK (dias_plazo IS NULL OR dias_plazo >= 0),
  CONSTRAINT ck_motivo_aviso      CHECK (aviso_previo_dias >= 0),
  -- Si hay plazo, hay que decir a que se pasa al vencer. Un plazo que vence
  -- hacia ningun sitio deja al cliente en un limbo que nadie vigila.
  CONSTRAINT ck_motivo_al_vencer  CHECK (
    dias_plazo IS NULL OR nivel_al_vencer IS NOT NULL
  )
);

COMMENT ON TABLE comercial.motivo IS
  'Por que entro o por que se fue un cliente, con lo que eso le hace a su acceso. '
  'El LIS no conoce esta tabla: solo recibe el nivel que sale de aqui.';

COMMENT ON COLUMN comercial.motivo.politica_definida IS
  'La columna que impide el agujero silencioso: mientras sea false, aplicar este '
  'motivo deja al cliente en solo_lectura y avisa, en vez de confiar en campos '
  'en blanco. Se pone en true cuando alguien decidio de verdad los valores.';

-- ---------------------------------------------------------------------
-- El historial de la relacion
--
-- Una fila por hecho. Nada se edita y nada se borra: un registro equivocado
-- se corrige con otro hecho, no reescribiendo el anterior.
-- ---------------------------------------------------------------------
CREATE TABLE comercial.relacion_evento (
  evento_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  empresa_id         bigint NOT NULL REFERENCES core.empresa (empresa_id),
  tipo_evento        comercial.tipo_evento NOT NULL,
  motivo_id          text NOT NULL REFERENCES comercial.motivo (motivo_id),

  -- Cuando ocurrio como hecho del negocio, que no es lo mismo que cuando se
  -- tecleo. Permite registrar hoy una suspension acordada para el lunes.
  fecha              date NOT NULL DEFAULT CURRENT_DATE,

  -- La politica COPIADA en el momento de aplicarla, no referenciada. Si
  -- manana cambias el plazo de falta_pago de 15 a 30 dias, las suspensiones
  -- ya hechas conservan los 15 con los que se aplicaron. Es el mismo
  -- principio del precio congelado en la orden y del rango en el resultado.
  nivel_aplicado           core.nivel_acceso NOT NULL,
  dias_plazo_aplicado      integer,
  nivel_al_vencer_aplicado core.nivel_acceso,
  estado_al_vencer_aplicado core.estado_empresa,
  fecha_vencimiento        date,
  politica_estaba_definida boolean NOT NULL,

  nota               text,
  registrado_por     text NOT NULL,
  registrado_en      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_evento_nota CHECK (nota IS NULL OR btrim(nota) <> '')
);

COMMENT ON TABLE comercial.relacion_evento IS
  'La linea de tiempo de cada cliente: entro, se activo, se suspendio, se fue. '
  'Una fila por hecho, con su fecha y su motivo. No lleva estado anterior ni '
  'estado nuevo: el estado de hoy vive en core.empresa y el de ayer se lee '
  'recorriendo estas filas.';

COMMENT ON COLUMN comercial.relacion_evento.registrado_por IS
  'Quien lo hizo. Es texto y no una llave foranea a core.usuario a proposito: '
  'el dueno del sistema no es usuario de ninguna empresa. Regla E-19.';

-- ---------------------------------------------------------------------
-- El contrato
--
-- Separado del historial porque es otra cosa: el historial dice que paso,
-- el contrato dice hasta cuando se ofrece el servicio y en que terminos.
--
-- Cuelga del CLIENTE, no de la empresa: se contrata con quien firma, no con
-- un inquilino. Un contrato cubre todas las empresas vigentes de ese cliente.
-- ---------------------------------------------------------------------
CREATE TABLE comercial.contrato (
  contrato_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cliente_id         bigint NOT NULL REFERENCES comercial.cliente (cliente_id),
  referencia         text,
  fecha_inicio       date NOT NULL,
  fecha_fin          date,
  renovacion_automatica boolean NOT NULL DEFAULT false,
  moneda             text NOT NULL DEFAULT 'HNL',
  monto_periodo      numeric(12,2),
  periodo_meses      smallint NOT NULL DEFAULT 1,
  condiciones        text,

  CONSTRAINT ck_contrato_vigencia CHECK (fecha_fin IS NULL OR fecha_fin > fecha_inicio),
  CONSTRAINT ck_contrato_monto    CHECK (monto_periodo IS NULL OR monto_periodo >= 0),
  CONSTRAINT ck_contrato_periodo  CHECK (periodo_meses BETWEEN 1 AND 60)
);

COMMENT ON TABLE comercial.contrato IS
  'Desde cuando, hasta cuando y en que terminos. fecha_fin es la fecha del '
  'contrato, no la del cierre tecnico: esa la calcula el motivo y vive en '
  'core.empresa.fecha_cierre.';

