/* =====================================================================
   ProLisSaas · Esquema para SQL Server — SOLO PARA VISUALIZAR

   Esta NO es la base de datos del sistema. La base real es PostgreSQL y
   vive en los archivos 01..16 de esta misma carpeta. Este script es una
   traduccion estructural para poder abrir un diagrama en SSMS.

   GENERADO. No se edita a mano: se regenera con

       python3 generar_sqlserver.py > esquema_sqlserver.sql

   La fuente es la base viva, asi que el diagrama no se puede desincronizar
   del diseno. Un espejo escrito a mano si: en septiembre de 2026 a este
   archivo le faltaban tres tablas y `plataforma.persona` todavia mostraba
   los nombres del paciente, que es lo contrario de lo que el diseno decidio.

   Que se conserva: esquemas, tablas, columnas, llaves primarias, llaves
   foraneas (incluidas las compuestas con empresa_id), restricciones unicas
   e indices filtrados. Incluido el esquema `comercial`, que es del dueno del
   sistema y no del laboratorio: se ve en el diagrama para poder comprobar de
   un vistazo que solo apunta a core.empresa y nada le apunta a el.

   Que NO se traduce, porque no aporta al diagrama:
     · Row Level Security y el rol lis_app  -> el aislamiento real
     · Las funciones y los tipos enumerados -> aqui son CHECK
     · Los CHECK con expresion regular      -> quedan como comentario

   Triggers no hay ninguno que traducir: se fueron con actualizado_en (H-96).

   Uso: abrilo en SSMS y dale F5. No hace falta crear nada antes ni elegir
   base en el desplegable -- el script se cambia solo a master, tira
   ProLisSaasDiagrama entera y la vuelve a crear.

   Despues: Diagramas de base de datos > Nuevo diagrama > agregar todas.
   Si SSMS pide un propietario valido:
       ALTER AUTHORIZATION ON DATABASE::ProLisSaasDiagrama TO sa;

   SE BORRA LA BASE COMPLETA cada vez, incluidos los diagramas guardados en
   dbo.sysdiagrams. Es a proposito: antes se borraban solo las tablas y los
   esquemas, y el diagrama viejo sobrevivia apuntando a tablas que ya no
   existian -- daba la impresion de que el script no aplicaba los cambios.
   Es una base para mirar el diseno, no para guardar nada.
   ===================================================================== */

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   Borrado total · la base entera, no solo sus tablas

   Antes esto borraba las llaves, las tablas y los esquemas uno por uno.
   Funcionaba, pero dejaba rastro: dbo.sysdiagrams -- donde SSMS guarda los
   diagramas -- sobrevivia, y el diagrama viejo seguia abriendo apuntando a
   tablas que ya no existian. Parecia que el script no aplicaba los cambios.

   Ahora se tira la base completa y se crea de nuevo. Cero rastro.

   OJO: se pierde TODO lo que este en ProLisSaasDiagrama, incluidos los diagramas
   guardados. Es una base para mirar el diseno, no para guardar nada.

   El USE master de arriba es obligatorio: no se puede borrar una base
   estando conectado a ella. Y como el script se cambia solo a la base
   correcta, ya no importa en que ventana de SSMS lo ejecutes.
   --------------------------------------------------------------------- */

USE master;
GO

IF DB_ID(N'ProLisSaasDiagrama') IS NOT NULL
BEGIN
    -- Echa a cualquier otra conexion: si SSMS tiene la base abierta en el
    -- Explorador de objetos, el DROP falla sin esto.
    ALTER DATABASE [ProLisSaasDiagrama] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [ProLisSaasDiagrama];
    PRINT N'>>> Base anterior borrada.';
END
GO

CREATE DATABASE [ProLisSaasDiagrama];
GO

USE [ProLisSaasDiagrama];
GO

PRINT N'>>> Base creada limpia. Todo lo que sigue es el diseno de hoy.';
GO


/* =====================================================================
   Los 6 esquemas · un modulo cada uno
   ===================================================================== */

CREATE SCHEMA plataforma;
GO

CREATE SCHEMA core;
GO

CREATE SCHEMA audit;
GO

CREATE SCHEMA lab;
GO

CREATE SCHEMA integra;
GO

CREATE SCHEMA comercial;
GO


/* =====================================================================
   COMERCIAL · el negocio del dueno del sistema, no del laboratorio
   ===================================================================== */

-- La contraparte del contrato: a quien le facturas vos. No es la empresa -
-- - la empresa es el inquilino del LIS. Un cliente puede tener varias.
CREATE TABLE comercial.cliente (
  cliente_id        bigint IDENTITY(1,1) NOT NULL,
  nombre            nvarchar(160) NOT NULL,
  tipo              varchar(20) NOT NULL,
  -- El RTN con el que se le factura A EL. No confundir con
  -- core.empresa.rtn, que es con el que la empresa le factura a sus
  -- pacientes. Casi siempre son el mismo numero y por eso conviene
  -- tenerlos separados desde ahora.
  rtn               varchar(20),
  direccion_fiscal  nvarchar(200),
  nota              nvarchar(200),
  creado_en         datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT cliente_pkey PRIMARY KEY (cliente_id),
  CONSTRAINT ck_cliente_tipo CHECK (tipo IN ('natural', 'juridica'))
);
GO

CREATE UNIQUE INDEX uq_cliente_rtn ON comercial.cliente (rtn) WHERE rtn IS NOT NULL;
GO

-- Por que entro o por que se fue un cliente, con lo que eso le hace a su a
-- cceso. El LIS no conoce esta tabla: solo recibe el nivel que sale de aqu
-- i.
CREATE TABLE comercial.motivo (
  motivo_id          nvarchar(200) NOT NULL,
  tipo_evento        varchar(20) NOT NULL,
  nombre             nvarchar(160) NOT NULL,
  descripcion        nvarchar(400),
  nivel_inmediato    varchar(20) NOT NULL DEFAULT 'solo_lectura',
  dias_plazo         int,
  nivel_al_vencer    varchar(20),
  estado_al_vencer   varchar(20),
  aviso_previo_dias  smallint NOT NULL DEFAULT 0,
  permite_exportar   bit NOT NULL DEFAULT 1,
  reversible         bit NOT NULL DEFAULT 1,
  requiere_nota      bit NOT NULL DEFAULT 0,
  -- La columna que impide el agujero silencioso: mientras sea false,
  -- aplicar este motivo deja al cliente en solo_lectura y avisa, en vez
  -- de confiar en campos en blanco. Se pone en true cuando alguien
  -- decidio de verdad los valores.
  politica_definida  bit NOT NULL DEFAULT 0,
  activo             bit NOT NULL DEFAULT 1,
  creado_en          datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT motivo_pkey PRIMARY KEY (motivo_id),
  CONSTRAINT ck_motivo_al_vencer CHECK (((dias_plazo IS NULL) OR (nivel_al_vencer IS NOT NULL))),
  CONSTRAINT ck_motivo_aviso CHECK ((aviso_previo_dias >= 0)),
  CONSTRAINT ck_motivo_plazo CHECK (((dias_plazo IS NULL) OR (dias_plazo >= 0))),
  CONSTRAINT ck_motivo_tipo_evento CHECK (tipo_evento IN ('alta', 'activacion', 'suspension', 'reactivacion', 'cancelacion', 'cierre')),
  CONSTRAINT ck_motivo_nivel_inmediato CHECK (nivel_inmediato IN ('completo', 'solo_cierre', 'solo_lectura', 'bloqueado')),
  CONSTRAINT ck_motivo_nivel_al_vencer CHECK (nivel_al_vencer IN ('completo', 'solo_cierre', 'solo_lectura', 'bloqueado')),
  CONSTRAINT ck_motivo_estado_al_vencer CHECK (estado_al_vencer IN ('prueba', 'activa', 'suspendida', 'cancelada', 'cerrada'))
);
-- ck_motivo_formato: CHECK ((motivo_id ~ '^[a-z][a-z0-9_]*$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- El tenant. No lleva empresa_id porque ella ES la empresa; su politica RL
-- S compara contra el propio empresa_id.
CREATE TABLE core.empresa (
  empresa_id        bigint IDENTITY(1,1) NOT NULL,
  nombre            nvarchar(160) NOT NULL,
  nombre_comercial  nvarchar(160),
  -- El RTN con el que ESTA EMPRESA le factura a sus pacientes, y con el
  -- que otra empresa la nombra para trabajar con ella. NO es la
  -- identidad fiscal de quien contrato el servicio: esa es
  -- comercial.cliente.rtn. Casi siempre son el mismo numero, y dejan de
  -- serlo el dia que un grupo contrate bajo la sociedad madre.
  rtn               varchar(20),
  estado            varchar(20) NOT NULL DEFAULT 'prueba',
  -- Que puede hacer la empresa hoy. Solo lo escriben las funciones de
  -- comercial; el laboratorio no tiene UPDATE sobre esta columna. Regla
  -- E-16.
  nivel_acceso      varchar(20) NOT NULL DEFAULT 'completo',
  -- Cuando vence el plazo. Vive de este lado a proposito: asi el sistema
  -- se cierra solo el dia que toca aunque la administracion este
  -- apagada.
  fecha_cierre      date,
  -- Cuando aparecio la fila, nada mas. No la lee nadie todavia: se queda
  -- porque se escribe una vez y no puede mentir, y porque hoy es lo
  -- unico que contesta "desde cuando existe esto". El dia que exista la
  -- bitacora, el INSERT registrado da esa misma fecha y ademas el quien,
  -- y entonces sobra (H-97).
  creado_en         datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT empresa_pkey PRIMARY KEY (empresa_id),
  CONSTRAINT ck_empresa_estado CHECK (estado IN ('prueba', 'activa', 'suspendida', 'cancelada', 'cerrada')),
  CONSTRAINT ck_empresa_nivel_acceso CHECK (nivel_acceso IN ('completo', 'solo_cierre', 'solo_lectura', 'bloqueado'))
);
GO

CREATE UNIQUE INDEX uq_empresa_rtn ON core.empresa (rtn) WHERE rtn IS NOT NULL;
GO


/* =====================================================================
   PLATAFORMA · por encima de las empresas, sin datos clinicos
   ===================================================================== */

-- Los modulos que el producto ofrece. Activar uno en una sucursal es una f
-- ila en plataforma.modulo_sucursal, no un despliegue. La escribe el opera
-- dor: el laboratorio no decide que compro.
CREATE TABLE plataforma.modulo (
  modulo_id    varchar(40) NOT NULL,
  nombre       nvarchar(160) NOT NULL,
  descripcion  nvarchar(400),
  CONSTRAINT modulo_pkey PRIMARY KEY (modulo_id)
);
-- ck_modulo_id_formato: CHECK ((modulo_id ~ '^[a-z][a-z0-9_]*$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO


/* =====================================================================
   AUDIT · el rastro y el unico puente entre empresas
   ===================================================================== */

-- Transversal a proposito. Si la auditoria vive en cada modulo, cada uno l
-- a implementa distinto y ninguno completo.
CREATE TABLE audit.evento (
  evento_id       bigint IDENTITY(1,1) NOT NULL,
  empresa_id      bigint,
  usuario_id      bigint,
  ocurrido_en     datetime2 NOT NULL DEFAULT sysutcdatetime(),
  accion          varchar(60) NOT NULL,
  nombre_esquema  varchar(40) NOT NULL,
  nombre_tabla    varchar(60) NOT NULL,
  registro_id     bigint,
  datos_antes     nvarchar(max),
  datos_despues   nvarchar(max),
  ip              varchar(45),
  user_agent      nvarchar(300),
  CONSTRAINT evento_pkey PRIMARY KEY (evento_id),
  CONSTRAINT evento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
-- ck_evento_accion_formato: CHECK ((accion ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO


/* =====================================================================
   COMERCIAL · el negocio del dueno del sistema, no del laboratorio
   ===================================================================== */

-- La unica union entre el negocio y el producto. Vive de este lado porque 
-- core nunca referencia comercial (E-18).
CREATE TABLE comercial.cliente_empresa (
  cliente_id  bigint NOT NULL,
  empresa_id  bigint NOT NULL,
  desde       date NOT NULL DEFAULT CAST(sysutcdatetime() AS date),
  hasta       date,
  nota        nvarchar(200),
  CONSTRAINT cliente_empresa_pkey PRIMARY KEY (cliente_id, empresa_id, desde),
  CONSTRAINT ck_cliente_empresa_vigencia CHECK (((hasta IS NULL) OR (hasta >= desde))),
  CONSTRAINT cliente_empresa_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES comercial.cliente(cliente_id),
  CONSTRAINT cliente_empresa_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
-- ex_cliente_empresa_sin_solape: EXCLUDE USING gist (empresa_id WITH =, daterange(desde, hasta, '[)'::text) WITH &&)
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO

CREATE TABLE comercial.contacto (
  contacto_id  bigint IDENTITY(1,1) NOT NULL,
  cliente_id   bigint NOT NULL,
  nombre       nvarchar(160) NOT NULL,
  papel        varchar(20) NOT NULL DEFAULT 'general',
  cargo        nvarchar(80),
  telefono     varchar(40),
  correo       varchar(160),
  -- Booleano legitimo: la persona sigue en el puesto o ya no. No es
  -- borrado logico -- un contacto que se fue se queda, porque firmo
  -- cosas.
  activo       bit NOT NULL DEFAULT 1,
  nota         nvarchar(200),
  creado_en    datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT contacto_pkey PRIMARY KEY (contacto_id),
  CONSTRAINT contacto_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES comercial.cliente(cliente_id),
  CONSTRAINT ck_contacto_papel CHECK (papel IN ('firma', 'pago', 'tecnico', 'general'))
);
GO

-- Desde cuando, hasta cuando y en que terminos. fecha_fin es la fecha del 
-- contrato, no la del cierre tecnico: esa la calcula el motivo y vive en c
-- ore.empresa.fecha_cierre.
CREATE TABLE comercial.contrato (
  contrato_id            bigint IDENTITY(1,1) NOT NULL,
  cliente_id             bigint NOT NULL,
  referencia             nvarchar(200),
  fecha_inicio           date NOT NULL,
  fecha_fin              date,
  renovacion_automatica  bit NOT NULL DEFAULT 0,
  moneda                 nvarchar(200) NOT NULL DEFAULT 'HNL',
  monto_periodo          decimal(12,2),
  periodo_meses          smallint NOT NULL DEFAULT 1,
  condiciones            nvarchar(200),
  CONSTRAINT contrato_pkey PRIMARY KEY (contrato_id),
  CONSTRAINT ck_contrato_monto CHECK (((monto_periodo IS NULL) OR (monto_periodo >= (0)))),
  CONSTRAINT ck_contrato_periodo CHECK (((periodo_meses >= 1) AND (periodo_meses <= 60))),
  CONSTRAINT ck_contrato_vigencia CHECK (((fecha_fin IS NULL) OR (fecha_fin > fecha_inicio))),
  CONSTRAINT contrato_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES comercial.cliente(cliente_id)
);
GO

-- La linea de tiempo de cada cliente: entro, se activo, se suspendio, se f
-- ue. Una fila por hecho, con su fecha y su motivo. No lleva estado anteri
-- or ni estado nuevo: el estado de hoy vive en core.empresa y el de ayer s
-- e lee recorriendo estas filas.
CREATE TABLE comercial.relacion_evento (
  evento_id                  bigint IDENTITY(1,1) NOT NULL,
  empresa_id                 bigint NOT NULL,
  tipo_evento                varchar(20) NOT NULL,
  motivo_id                  nvarchar(200) NOT NULL,
  fecha                      date NOT NULL DEFAULT CAST(sysutcdatetime() AS date),
  nivel_aplicado             varchar(20) NOT NULL,
  dias_plazo_aplicado        int,
  nivel_al_vencer_aplicado   varchar(20),
  estado_al_vencer_aplicado  varchar(20),
  fecha_vencimiento          date,
  politica_estaba_definida   bit NOT NULL,
  nota                       nvarchar(200),
  -- Quien lo hizo. Es texto y no una llave foranea a core.usuario a
  -- proposito: el dueno del sistema no es usuario de ninguna empresa.
  -- Regla E-19.
  registrado_por             nvarchar(200) NOT NULL,
  registrado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT relacion_evento_pkey PRIMARY KEY (evento_id),
  CONSTRAINT ck_evento_nota CHECK (((nota IS NULL) OR (LTRIM(RTRIM(nota)) <> ''))),
  CONSTRAINT relacion_evento_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT relacion_evento_motivo_id_fkey FOREIGN KEY (motivo_id) REFERENCES comercial.motivo(motivo_id),
  CONSTRAINT ck_relacion_evento_tipo_evento CHECK (tipo_evento IN ('alta', 'activacion', 'suspension', 'reactivacion', 'cancelacion', 'cierre')),
  CONSTRAINT ck_relacion_evento_nivel_aplicado CHECK (nivel_aplicado IN ('completo', 'solo_cierre', 'solo_lectura', 'bloqueado')),
  CONSTRAINT ck_relacion_evento_nivel_al_vencer_aplicado CHECK (nivel_al_vencer_aplicado IN ('completo', 'solo_cierre', 'solo_lectura', 'bloqueado')),
  CONSTRAINT ck_relacion_evento_estado_al_vencer_aplicado CHECK (estado_al_vencer_aplicado IN ('prueba', 'activa', 'suspendida', 'cancelada', 'cerrada'))
);
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

CREATE TABLE core.convenio (
  convenio_id           bigint IDENTITY(1,1) NOT NULL,
  empresa_id            bigint NOT NULL,
  nombre                nvarchar(160) NOT NULL,
  tipo                  varchar(20) NOT NULL,
  modalidad_cobro       varchar(20) NOT NULL DEFAULT 'particular',
  copago_porcentaje     decimal(5,2),
  dia_corte             smallint,
  recibe_copia_informe  bit NOT NULL DEFAULT 0,
  es_predeterminado     bit NOT NULL DEFAULT 0,
  -- Hoy la clinica es una fila de catalogo con esta columna en NULL. El
  -- dia que la clinica entre al sistema, esta columna apunta a su
  -- empresa y la solicitud pasa de papel a electronica. Sin migrar una
  -- sola orden.
  empresa_destino_id    bigint,
  rtn                   varchar(20),
  contacto              nvarchar(160),
  telefono              varchar(40),
  activo                bit NOT NULL DEFAULT 1,
  creado_en             datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT convenio_pkey PRIMARY KEY (convenio_id),
  CONSTRAINT uq_convenio_empresa UNIQUE (convenio_id, empresa_id),
  CONSTRAINT uq_convenio_nombre UNIQUE (empresa_id, nombre),
  CONSTRAINT ck_convenio_copago CHECK ((((modalidad_cobro <> 'copago') AND (copago_porcentaje IS NULL)) OR ((modalidad_cobro = 'copago') AND ((copago_porcentaje >= (0)) AND (copago_porcentaje <= (100)))))),
  CONSTRAINT ck_convenio_corte CHECK ((((modalidad_cobro <> 'credito_mensual') AND (dia_corte IS NULL)) OR ((modalidad_cobro = 'credito_mensual') AND ((dia_corte >= 1) AND (dia_corte <= 28))))),
  CONSTRAINT ck_convenio_destino_distinto CHECK ((empresa_destino_id IS NULL OR empresa_destino_id <> empresa_id)),
  CONSTRAINT convenio_empresa_destino_id_fkey FOREIGN KEY (empresa_destino_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT convenio_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_convenio_tipo CHECK (tipo IN ('particular', 'clinica', 'hospital', 'aseguradora', 'empresa', 'medico')),
  CONSTRAINT ck_convenio_modalidad_cobro CHECK (modalidad_cobro IN ('particular', 'credito_mensual', 'copago', 'reembolso'))
);
GO

CREATE UNIQUE INDEX uq_convenio_predeterminado ON core.convenio (empresa_id) WHERE es_predeterminado = 1;
GO

-- La persona que trabaja aqui, exista o no una cuenta de usuario. No se vi
-- ncula a plataforma.persona: ese registro es para resolver identidad de p
-- acientes entre empresas, y un empleado no necesita eso.
CREATE TABLE core.empleado (
  empleado_id         bigint IDENTITY(1,1) NOT NULL,
  empresa_id          bigint NOT NULL,
  nombres             nvarchar(120) NOT NULL,
  apellidos           nvarchar(120) NOT NULL,
  documento           varchar(40),
  telefono            varchar(40),
  correo              varchar(160),
  cargo               nvarchar(80),
  -- Del bioquimico o del medico. Va impreso en el informe junto a la
  -- firma.
  numero_colegiacion  varchar(40),
  activo              bit NOT NULL DEFAULT 1,
  creado_en           datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT empleado_pkey PRIMARY KEY (empleado_id),
  CONSTRAINT uq_empleado_empresa UNIQUE (empleado_id, empresa_id),
  CONSTRAINT empleado_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

CREATE TABLE core.rol (
  rol_id       bigint IDENTITY(1,1) NOT NULL,
  empresa_id   bigint NOT NULL,
  nombre       nvarchar(160) NOT NULL,
  descripcion  nvarchar(400),
  -- Booleano legitimo: los cuatro roles con los que nace la empresa se
  -- marcan true. Nadie lo lee todavia -- falta la regla que impida que
  -- un administrador le quite usuario.administrar a su propio rol y deje
  -- a la empresa sin nadie que pueda crear usuarios (H-90).
  es_sistema   bit NOT NULL DEFAULT 0,
  CONSTRAINT rol_pkey PRIMARY KEY (rol_id),
  CONSTRAINT uq_rol_empresa UNIQUE (rol_id, empresa_id),
  CONSTRAINT uq_rol_nombre UNIQUE (empresa_id, nombre),
  CONSTRAINT rol_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

CREATE TABLE core.sucursal (
  sucursal_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id   bigint NOT NULL,
  nombre       nvarchar(160) NOT NULL,
  -- Prefijo corto que va en los correlativos y en las etiquetas de
  -- codigo de barras.
  codigo       varchar(30) NOT NULL,
  direccion    nvarchar(250),
  telefono     varchar(40),
  -- Booleano legitimo: la sucursal opera o no opera. No es borrado
  -- logico.
  activo       bit NOT NULL DEFAULT 1,
  creado_en    datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT sucursal_pkey PRIMARY KEY (sucursal_id),
  CONSTRAINT uq_sucursal_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_sucursal_empresa UNIQUE (sucursal_id, empresa_id),
  CONSTRAINT uq_sucursal_nombre UNIQUE (empresa_id, nombre),
  CONSTRAINT sucursal_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
-- ck_sucursal_codigo: CHECK ((codigo ~ '^[A-Z0-9]{2,6}$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO


/* =====================================================================
   LAB · la rama de laboratorio clinico
   ===================================================================== */

-- Hematologia, quimica clinica, uroanalisis. Agrupa el catalogo y ordena e
-- l informe impreso, que se lee por area.
CREATE TABLE lab.area (
  area_id             bigint IDENTITY(1,1) NOT NULL,
  empresa_id          bigint NOT NULL,
  codigo              varchar(30) NOT NULL,
  nombre              nvarchar(160) NOT NULL,
  orden_presentacion  smallint NOT NULL DEFAULT 0,
  activo              bit NOT NULL DEFAULT 1,
  CONSTRAINT area_pkey PRIMARY KEY (area_id),
  CONSTRAINT uq_area_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_area_empresa UNIQUE (area_id, empresa_id),
  CONSTRAINT area_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

CREATE TABLE lab.tipo_muestra (
  tipo_muestra_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id       bigint NOT NULL,
  codigo           varchar(30) NOT NULL,
  nombre           nvarchar(160) NOT NULL,
  -- El color del tapon del tubo es como el flebotomista identifica el
  -- tubo en la mano. Va impreso en la etiqueta y en la hoja de toma.
  color_tapon      varchar(30),
  anticoagulante   nvarchar(80),
  volumen_min_ml   decimal(5,2),
  -- Cuantas horas es valida la muestra desde la toma. Vencida se
  -- rechaza.
  estable_horas    smallint,
  activo           bit NOT NULL DEFAULT 1,
  CONSTRAINT tipo_muestra_pkey PRIMARY KEY (tipo_muestra_id),
  CONSTRAINT uq_tipo_muestra_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_tipo_muestra_empresa UNIQUE (tipo_muestra_id, empresa_id),
  CONSTRAINT tipo_muestra_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO


/* =====================================================================
   PLATAFORMA · por encima de las empresas, sin datos clinicos
   ===================================================================== */

-- El permiso nombra una accion del dominio (resultado.validar), nunca una 
-- ruta HTTP. Atar permisos a rutas acopla la autorizacion a la forma de la
--  URL: cambiar la URL cambia quien puede hacer que.
CREATE TABLE plataforma.permiso (
  permiso_id   varchar(60) NOT NULL,
  modulo_id    varchar(40) NOT NULL,
  descripcion  nvarchar(400) NOT NULL,
  CONSTRAINT permiso_pkey PRIMARY KEY (permiso_id),
  CONSTRAINT permiso_modulo_id_fkey FOREIGN KEY (modulo_id) REFERENCES plataforma.modulo(modulo_id)
);
-- ck_permiso_id_formato: CHECK ((permiso_id ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- El numero que ve el usuario es distinto del id interno. El id autoincrem
-- ental le dice a cualquiera cuantos pacientes tienes; el correlativo es p
-- or empresa y puede reiniciarse sin tocar las llaves.
CREATE TABLE core.correlativo (
  correlativo_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id      bigint NOT NULL,
  sucursal_id     bigint,
  tipo            varchar(20) NOT NULL,
  prefijo         varchar(20) NOT NULL DEFAULT '',
  ancho           smallint NOT NULL DEFAULT 6,
  ultimo_valor    bigint NOT NULL DEFAULT 0,
  -- calculada y persistida: el indice unico de abajo la necesita,
  -- porque SQL Server no admite indices sobre expresiones
  sucursal_key    AS ISNULL(sucursal_id, 0) PERSISTED,
  CONSTRAINT correlativo_pkey PRIMARY KEY (correlativo_id),
  CONSTRAINT ck_correlativo_ancho CHECK (((ancho >= 4) AND (ancho <= 12))),
  CONSTRAINT correlativo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_correlativo_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT ck_correlativo_tipo CHECK (tipo IN ('expediente', 'episodio', 'informe', 'orden', 'muestra'))
);
GO

CREATE UNIQUE INDEX uq_correlativo ON core.correlativo (empresa_id, tipo, sucursal_key);
GO

CREATE TABLE core.rol_permiso (
  rol_id      bigint NOT NULL,
  permiso_id  varchar(60) NOT NULL,
  empresa_id  bigint NOT NULL,
  CONSTRAINT rol_permiso_pkey PRIMARY KEY (rol_id, permiso_id),
  CONSTRAINT fk_rol_permiso_rol FOREIGN KEY (rol_id, empresa_id) REFERENCES core.rol(rol_id, empresa_id),
  CONSTRAINT rol_permiso_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT rol_permiso_permiso_id_fkey FOREIGN KEY (permiso_id) REFERENCES plataforma.permiso(permiso_id)
);
GO

CREATE TABLE core.usuario (
  usuario_id         bigint IDENTITY(1,1) NOT NULL,
  empresa_id         bigint NOT NULL,
  empleado_id        bigint NOT NULL,
  rol_id             bigint NOT NULL,
  username           varchar(60) NOT NULL,
  -- Hash con argon2id o bcrypt. La columna se llama password_hash y no
  -- password para que nadie guarde ahi una contrasena en claro por
  -- descuido.
  password_hash      varchar(200) NOT NULL,
  estado             varchar(20) NOT NULL DEFAULT 'activo',
  intentos_fallidos  smallint NOT NULL DEFAULT 0,
  ultimo_acceso_en   datetime2,
  creado_en          datetime2 NOT NULL DEFAULT sysutcdatetime(),
  -- calculada y persistida: el indice unico de abajo la necesita,
  -- porque SQL Server no admite indices sobre expresiones
  username_min       AS LOWER(username) PERSISTED,
  CONSTRAINT usuario_pkey PRIMARY KEY (usuario_id),
  CONSTRAINT uq_usuario_empleado UNIQUE (empleado_id),
  CONSTRAINT uq_usuario_empresa UNIQUE (usuario_id, empresa_id),
  CONSTRAINT fk_usuario_empleado FOREIGN KEY (empleado_id, empresa_id) REFERENCES core.empleado(empleado_id, empresa_id),
  CONSTRAINT fk_usuario_rol FOREIGN KEY (rol_id, empresa_id) REFERENCES core.rol(rol_id, empresa_id),
  CONSTRAINT usuario_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_usuario_estado CHECK (estado IN ('activo', 'suspendido', 'bloqueado'))
);
-- ck_usuario_username: CHECK ((username ~ '^[a-z0-9._-]{3,40}$'::text))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO

CREATE UNIQUE INDEX uq_usuario_username ON core.usuario (empresa_id, username_min);
GO


/* =====================================================================
   INTEGRA · los analizadores y lo que mandan
   ===================================================================== */

CREATE TABLE integra.equipo (
  equipo_id      bigint IDENTITY(1,1) NOT NULL,
  empresa_id     bigint NOT NULL,
  sucursal_id    bigint NOT NULL,
  area_id        bigint,
  codigo         varchar(30) NOT NULL,
  nombre         nvarchar(160) NOT NULL,
  marca          nvarchar(80),
  modelo         nvarchar(80),
  serie          varchar(60),
  -- Determina que driver del agente local atiende a este equipo. El
  -- agente traduce los tres dialectos a una estructura interna unica; de
  -- aqui para arriba el sistema es igual para todos los analizadores.
  protocolo      varchar(20) NOT NULL,
  -- Como se identifica el equipo en sus propios mensajes: el MSH-3 en
  -- HL7, el campo de sender en ASTM. Es lo unico que permite saber que
  -- equipo mando que.
  identificador  varchar(60) NOT NULL,
  -- El Hemax 53 lo soporta segun el fabricante. En la v1 va en false: el
  -- equipo solo envia. Activarlo despues no cambia ninguna tabla, porque
  -- el codigo de barras de la muestra ya existe desde el primer dia.
  bidireccional  bit NOT NULL DEFAULT 0,
  activo         bit NOT NULL DEFAULT 1,
  creado_en      datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT equipo_pkey PRIMARY KEY (equipo_id),
  CONSTRAINT uq_equipo_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_equipo_empresa UNIQUE (equipo_id, empresa_id),
  CONSTRAINT uq_equipo_identificador UNIQUE (empresa_id, identificador),
  CONSTRAINT equipo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_equipo_area FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area(area_id, empresa_id),
  CONSTRAINT fk_equipo_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT ck_equipo_protocolo CHECK (protocolo IN ('hl7_v2', 'astm_e1394', 'propietario'))
);
GO


/* =====================================================================
   LAB · la rama de laboratorio clinico
   ===================================================================== */

CREATE TABLE lab.analito (
  analito_id   bigint IDENTITY(1,1) NOT NULL,
  empresa_id   bigint NOT NULL,
  area_id      bigint NOT NULL,
  codigo       varchar(30) NOT NULL,
  nombre       nvarchar(160) NOT NULL,
  abreviatura  varchar(20),
  tipo_valor   varchar(20) NOT NULL DEFAULT 'numerico',
  unidad       varchar(30),
  decimales    smallint NOT NULL DEFAULT 2,
  opciones     nvarchar(400),
  -- Codigo LOINC, opcional. Hoy no lo necesitas; el dia que un hospital
  -- pida intercambio de resultados, sin esta columna hay que mapear todo
  -- a mano.
  loinc        varchar(20),
  activo       bit NOT NULL DEFAULT 1,
  CONSTRAINT analito_pkey PRIMARY KEY (analito_id),
  CONSTRAINT uq_analito_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_analito_empresa UNIQUE (analito_id, empresa_id),
  CONSTRAINT ck_analito_decimales CHECK (((decimales >= 0) AND (decimales <= 6))),
  CONSTRAINT ck_analito_numerico CHECK (((tipo_valor <> 'numerico') OR (unidad IS NOT NULL))),
  CONSTRAINT analito_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_analito_area FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area(area_id, empresa_id),
  CONSTRAINT ck_analito_tipo_valor CHECK (tipo_valor IN ('numerico', 'texto', 'opcion', 'booleano'))
);
-- ck_analito_opciones: CHECK ((((tipo_valor = 'opcion'::lab.tipo_valor) AND (opciones IS NOT NULL) AND (array_length(opciones, 1) > 1)) OR ((tipo_valor <> 'opcion'::lab.tipo_valor) AND (opciones IS NULL))))
--   (SQL Server no lo traduce, se pierde en el espejo. En PostgreSQL si se cumple)
GO

CREATE TABLE lab.prueba (
  prueba_id        bigint IDENTITY(1,1) NOT NULL,
  empresa_id       bigint NOT NULL,
  area_id          bigint NOT NULL,
  tipo_muestra_id  bigint NOT NULL,
  codigo           varchar(30) NOT NULL,
  nombre           nvarchar(160) NOT NULL,
  -- Impedancia, colorimetrico, ELISA. Va impreso en el informe y
  -- determina que rango de referencia aplica: cambiar de metodo cambia
  -- los rangos.
  metodo           nvarchar(120),
  horas_proceso    smallint NOT NULL DEFAULT 24,
  requiere_ayuno   bit NOT NULL DEFAULT 0,
  indicaciones     nvarchar(1000),
  activo           bit NOT NULL DEFAULT 1,
  creado_en        datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT prueba_pkey PRIMARY KEY (prueba_id),
  CONSTRAINT uq_prueba_codigo UNIQUE (empresa_id, codigo),
  CONSTRAINT uq_prueba_empresa UNIQUE (prueba_id, empresa_id),
  CONSTRAINT fk_prueba_area FOREIGN KEY (area_id, empresa_id) REFERENCES lab.area(area_id, empresa_id),
  CONSTRAINT fk_prueba_tipo_muestra FOREIGN KEY (tipo_muestra_id, empresa_id) REFERENCES lab.tipo_muestra(tipo_muestra_id, empresa_id),
  CONSTRAINT prueba_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO


/* =====================================================================
   PLATAFORMA · por encima de las empresas, sin datos clinicos
   ===================================================================== */

-- Que dos SEDES de empresas distintas trabajan juntas. La crea el operador
-- . "Estas dos empresas trabajan juntas" no se guarda: se deduce de que ha
-- ya al menos una ruta vigente entre ellas.
CREATE TABLE plataforma.enlace (
  enlace_id      bigint IDENTITY(1,1) NOT NULL,
  empresa_a_id   bigint NOT NULL,
  sucursal_a_id  bigint NOT NULL,
  empresa_b_id   bigint NOT NULL,
  sucursal_b_id  bigint NOT NULL,
  vigente_desde  date NOT NULL DEFAULT CAST(sysutcdatetime() AS date),
  vigente_hasta  date,
  -- Texto y no llave foranea: el operador no es usuario de ninguna
  -- empresa (E-19).
  creado_por     nvarchar(200) NOT NULL,
  nota           nvarchar(200),
  CONSTRAINT enlace_pkey PRIMARY KEY (enlace_id),
  CONSTRAINT ck_enlace_empresas_distintas CHECK ((empresa_a_id <> empresa_b_id)),
  CONSTRAINT ck_enlace_vigencia CHECK (((vigente_hasta IS NULL) OR (vigente_hasta >= vigente_desde))),
  CONSTRAINT fk_enlace_sucursal_a FOREIGN KEY (sucursal_a_id, empresa_a_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT fk_enlace_sucursal_b FOREIGN KEY (sucursal_b_id, empresa_b_id) REFERENCES core.sucursal(sucursal_id, empresa_id)
);
GO

-- uq_enlace_ruta: CREATE UNIQUE INDEX ... (LEAST(sucursal_a_id, sucursal_b_id), GREATEST(sucursal_a_id, sucursal_b_id)) WHERE (vigente_hasta IS NULL)
--   (llave con expresion; SQL Server exige una columna calculada
--    persistida. En PostgreSQL se cumple.)
GO

-- Que modulos contrato cada SEDE. La escribe el operador, igual que plataf
-- orma.enlace. Activar laboratorio clinico en una sucursal es una fila aqu
-- i; cuando exista imagenologia, es otra fila. El nucleo nunca aprende los
--  nombres de las ramas.
CREATE TABLE plataforma.modulo_sucursal (
  sucursal_id     bigint NOT NULL,
  modulo_id       varchar(40) NOT NULL,
  empresa_id      bigint NOT NULL,
  -- Booleano legitimo. Apagarlo quita el acceso SIN borrar lo que el
  -- administrador configuro: rol_permiso guarda la intencion y
  -- sobrevive, esta columna guarda la licencia. Cuando el cliente vuelve
  -- a pagar, el acceso vuelve solo y nadie rearma ningun rol.
  activo          bit NOT NULL DEFAULT 1,
  activado_en     datetime2 NOT NULL DEFAULT sysutcdatetime(),
  desactivado_en  datetime2,
  -- Texto y no llave foranea: el operador no es usuario de ninguna
  -- empresa (E-19).
  asignado_por    nvarchar(200) NOT NULL,
  CONSTRAINT modulo_sucursal_pkey PRIMARY KEY (sucursal_id, modulo_id),
  CONSTRAINT ck_modulo_sucursal_apagado CHECK ((activo = 1 OR (desactivado_en IS NOT NULL))),
  CONSTRAINT fk_modulo_sucursal_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT modulo_sucursal_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT modulo_sucursal_modulo_id_fkey FOREIGN KEY (modulo_id) REFERENCES plataforma.modulo(modulo_id)
);
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- Un usuario puede operar en varias sucursales. Viene de lislabCli, que lo
--  tenia bien; pruebareal lo habia retrocedido a una sucursal fija por usu
-- ario.
CREATE TABLE core.acceso_sucursal (
  usuario_id   bigint NOT NULL,
  sucursal_id  bigint NOT NULL,
  empresa_id   bigint NOT NULL,
  creado_en    datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT acceso_sucursal_pkey PRIMARY KEY (usuario_id, sucursal_id),
  CONSTRAINT acceso_sucursal_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_acceso_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT fk_acceso_usuario FOREIGN KEY (usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id)
);
GO

-- Una fila de cada lado, nunca compartida. Las escribe core.entregar(), qu
-- e es el UNICO punto del sistema donde un dato pasa de una empresa a otra
-- .
CREATE TABLE core.mensaje (
  mensaje_id        bigint IDENTITY(1,1) NOT NULL,
  empresa_id        bigint NOT NULL,
  enlace_id         bigint NOT NULL,
  sucursal_id       bigint NOT NULL,
  direccion         varchar(20) NOT NULL,
  tipo              varchar(30) NOT NULL,
  folio             uniqueidentifier NOT NULL DEFAULT NEWID(),
  responde_a_folio  uniqueidentifier,
  contenido         nvarchar(max) NOT NULL,
  estado            varchar(20) NOT NULL DEFAULT 'pendiente',
  creado_en         datetime2 NOT NULL DEFAULT sysutcdatetime(),
  entregado_en      datetime2,
  trabajado_en      datetime2,
  CONSTRAINT mensaje_pkey PRIMARY KEY (mensaje_id),
  CONSTRAINT uq_mensaje_empresa UNIQUE (mensaje_id, empresa_id),
  CONSTRAINT uq_mensaje_folio UNIQUE (empresa_id, folio),
  CONSTRAINT ck_mensaje_estado_segun_direccion CHECK ((((direccion = 'enviado') AND (estado IN ('pendiente', 'entregado'))) OR ((direccion = 'recibido') AND (estado IN ('recibido', 'trabajado', 'descartado'))))),
  CONSTRAINT ck_mensaje_no_se_responde_solo CHECK (((responde_a_folio IS NULL) OR (responde_a_folio <> folio))),
  CONSTRAINT fk_mensaje_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT mensaje_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT mensaje_enlace_id_fkey FOREIGN KEY (enlace_id) REFERENCES plataforma.enlace(enlace_id),
  CONSTRAINT ck_mensaje_direccion CHECK (direccion IN ('enviado', 'recibido')),
  CONSTRAINT ck_mensaje_tipo CHECK (tipo IN ('solicitud', 'consulta_historial', 'respuesta_historial', 'resultado', 'correccion', 'aviso')),
  CONSTRAINT ck_mensaje_estado CHECK (estado IN ('pendiente', 'entregado', 'recibido', 'trabajado', 'descartado'))
);
GO

-- El expediente de una persona DENTRO de una empresa. Aqui si vive lo clin
-- ico. Nunca se comparte entero con otra empresa: lo que cruza es un mensa
-- je.
CREATE TABLE core.paciente (
  paciente_id               bigint IDENTITY(1,1) NOT NULL,
  empresa_id                bigint NOT NULL,
  -- La identidad real del paciente. La genera el sistema, no depende del
  -- documento, y por eso recepcion nunca tiene que inventar un documento
  -- falso para poder atender.
  expediente                varchar(40) NOT NULL,
  nombres                   nvarchar(120) NOT NULL,
  apellidos                 nvarchar(120) NOT NULL,
  nombre_completo           nvarchar(240),
  tipo_documento            varchar(30) NOT NULL DEFAULT 'ninguno',
  documento                 varchar(40),
  fecha_nacimiento          date,
  sexo                      varchar(20) NOT NULL DEFAULT 'no_especificado',
  telefono                  varchar(40),
  correo                    varchar(160),
  direccion                 nvarchar(250),
  -- Si este registro resulto ser duplicado, apunta al que quedo. Las
  -- ordenes viejas siguen apuntando a este id; la lectura sigue el
  -- puntero. Nunca se borra una fila.
  fusionado_en_paciente_id  bigint,
  fusionado_en              datetime2,
  fusionado_por_usuario_id  bigint,
  creado_por_usuario_id     bigint,
  creado_en                 datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT paciente_pkey PRIMARY KEY (paciente_id),
  CONSTRAINT uq_paciente_empresa UNIQUE (paciente_id, empresa_id),
  CONSTRAINT uq_paciente_expediente UNIQUE (empresa_id, expediente),
  CONSTRAINT ck_paciente_documento CHECK ((((tipo_documento = 'ninguno') AND (documento IS NULL)) OR ((tipo_documento <> 'ninguno') AND (documento IS NOT NULL) AND (LTRIM(RTRIM(documento)) <> '')))),
  CONSTRAINT ck_paciente_fusion CHECK ((((fusionado_en_paciente_id IS NULL) AND (fusionado_en IS NULL)) OR ((fusionado_en_paciente_id IS NOT NULL) AND (fusionado_en IS NOT NULL)))),
  CONSTRAINT ck_paciente_no_se_fusiona_consigo CHECK ((fusionado_en_paciente_id IS NULL OR fusionado_en_paciente_id <> paciente_id)),
  CONSTRAINT fk_paciente_creado_por FOREIGN KEY (creado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT fk_paciente_fusionado_por FOREIGN KEY (fusionado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT paciente_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT paciente_fusionado_en_paciente_id_fkey FOREIGN KEY (fusionado_en_paciente_id) REFERENCES core.paciente(paciente_id),
  CONSTRAINT ck_paciente_tipo_documento CHECK (tipo_documento IN ('identidad', 'pasaporte', 'carnet_residencia', 'partida_nacimiento', 'ninguno')),
  CONSTRAINT ck_paciente_sexo CHECK (sexo IN ('femenino', 'masculino', 'no_especificado'))
);
GO

CREATE UNIQUE INDEX uq_paciente_documento ON core.paciente (empresa_id, tipo_documento, documento) WHERE (documento IS NOT NULL) AND (fusionado_en_paciente_id IS NULL);
GO


/* =====================================================================
   INTEGRA · los analizadores y lo que mandan
   ===================================================================== */

-- El equipo nuevo manda GLU donde el viejo mandaba GLUC: aqui se resuelve,
--  sin que el resto del sistema se entere de que existen dos nombres.
CREATE TABLE integra.mapeo_codigo (
  mapeo_codigo_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id       bigint NOT NULL,
  equipo_id        bigint NOT NULL,
  codigo_equipo    varchar(40) NOT NULL,
  analito_id       bigint NOT NULL,
  -- Conversion de unidades cuando el equipo reporta en otra escala.
  -- Existe por lo que se encontro en prueba.txt: el LYM# venia diez
  -- veces mas bajo de lo que da el calculo con WBC y LYM%. Antes de usar
  -- un factor hay que confirmarlo con el manual del equipo: puede ser un
  -- error del archivo y no del analizador.
  factor           decimal(12,6) NOT NULL DEFAULT 1,
  unidad_equipo    varchar(30),
  activo           bit NOT NULL DEFAULT 1,
  CONSTRAINT mapeo_codigo_pkey PRIMARY KEY (mapeo_codigo_id),
  CONSTRAINT uq_mapeo_codigo UNIQUE (equipo_id, codigo_equipo),
  CONSTRAINT ck_mapeo_factor CHECK ((factor > (0))),
  CONSTRAINT fk_mapeo_analito FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito(analito_id, empresa_id),
  CONSTRAINT fk_mapeo_equipo FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo(equipo_id, empresa_id),
  CONSTRAINT mapeo_codigo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

-- El mensaje tal cual lo mando el equipo. El agente local lo persiste ANTE
-- S de responderle el ACK al analizador: si el proceso muere entre una cos
-- a y la otra, el equipo cree que llego y el resultado se perdio.
CREATE TABLE integra.mensaje_crudo (
  mensaje_crudo_id       bigint IDENTITY(1,1) NOT NULL,
  empresa_id             bigint NOT NULL,
  sucursal_id            bigint NOT NULL,
  equipo_id              bigint,
  protocolo              varchar(20) NOT NULL,
  contenido              nvarchar(max) NOT NULL,
  -- El agente reintenta cuando se cae el internet. Sin este hash, cada
  -- reintento crearia un resultado duplicado.
  contenido_hash         varchar(80) NOT NULL,
  identificador_equipo   varchar(60),
  identificador_muestra  varchar(60),
  estado                 varchar(20) NOT NULL DEFAULT 'pendiente',
  intentos               smallint NOT NULL DEFAULT 0,
  ultimo_error           nvarchar(1000),
  -- Cuando lo recibio el agente en el laboratorio, no cuando llego a la
  -- nube. Con internet caido pueden pasar horas entre una cosa y la
  -- otra.
  recibido_en            datetime2 NOT NULL,
  recibido_nube_en       datetime2 NOT NULL DEFAULT sysutcdatetime(),
  procesado_en           datetime2,
  CONSTRAINT mensaje_crudo_pkey PRIMARY KEY (mensaje_crudo_id),
  CONSTRAINT uq_mensaje_empresa UNIQUE (mensaje_crudo_id, empresa_id),
  CONSTRAINT uq_mensaje_hash UNIQUE (empresa_id, contenido_hash),
  CONSTRAINT ck_mensaje_procesado CHECK (((estado = 'pendiente') OR (procesado_en IS NOT NULL))),
  CONSTRAINT fk_mensaje_equipo FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo(equipo_id, empresa_id),
  CONSTRAINT fk_mensaje_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT mensaje_crudo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_mensaje_crudo_protocolo CHECK (protocolo IN ('hl7_v2', 'astm_e1394', 'propietario')),
  CONSTRAINT ck_mensaje_crudo_estado CHECK (estado IN ('pendiente', 'procesado', 'fallido', 'ignorado'))
);
GO


/* =====================================================================
   LAB · la rama de laboratorio clinico
   ===================================================================== */

-- Se resuelve de lo mas especifico a lo mas general: convenio y sucursal, 
-- luego convenio, luego sucursal, luego lista. Nunca se actualiza un preci
-- o: se cierra la vigencia del anterior y se inserta el nuevo.
CREATE TABLE lab.precio_prueba (
  precio_prueba_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id        bigint NOT NULL,
  prueba_id         bigint NOT NULL,
  sucursal_id       bigint,
  convenio_id       bigint,
  precio            decimal(12,2) NOT NULL,
  vigente_desde     date NOT NULL DEFAULT CAST(sysutcdatetime() AS date),
  vigente_hasta     date,
  -- calculada y persistida: el indice unico de abajo la necesita,
  -- porque SQL Server no admite indices sobre expresiones
  convenio_key      AS ISNULL(convenio_id, 0) PERSISTED,
  -- calculada y persistida: el indice unico de abajo la necesita,
  -- porque SQL Server no admite indices sobre expresiones
  sucursal_key      AS ISNULL(sucursal_id, 0) PERSISTED,
  CONSTRAINT precio_prueba_pkey PRIMARY KEY (precio_prueba_id),
  CONSTRAINT ck_precio_positivo CHECK ((precio >= (0))),
  CONSTRAINT ck_precio_vigencia CHECK (((vigente_hasta IS NULL) OR (vigente_hasta > vigente_desde))),
  CONSTRAINT fk_precio_convenio FOREIGN KEY (convenio_id, empresa_id) REFERENCES core.convenio(convenio_id, empresa_id),
  CONSTRAINT fk_precio_prueba FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba(prueba_id, empresa_id),
  CONSTRAINT fk_precio_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT precio_prueba_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

CREATE UNIQUE INDEX uq_precio_vigente ON lab.precio_prueba (empresa_id, prueba_id, sucursal_key, convenio_key, vigente_desde);
GO

CREATE TABLE lab.prueba_analito (
  prueba_id           bigint NOT NULL,
  analito_id          bigint NOT NULL,
  empresa_id          bigint NOT NULL,
  orden_presentacion  smallint NOT NULL DEFAULT 0,
  -- true si el equipo lo deriva de otros (HCT a partir de RBC y MCV). Se
  -- guarda igual, pero se marca para no cuestionar por que no coincide
  -- al recalcular.
  calculado           bit NOT NULL DEFAULT 0,
  CONSTRAINT prueba_analito_pkey PRIMARY KEY (prueba_id, analito_id),
  CONSTRAINT fk_prueba_analito_analito FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito(analito_id, empresa_id),
  CONSTRAINT fk_prueba_analito_prueba FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba(prueba_id, empresa_id),
  CONSTRAINT prueba_analito_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

-- El rango lo define el LABORATORIO, no el analizador. El Hemax 53 manda 1
-- 3.5-18.0 para hemoglobina en cada OBX, que es un rango de varon adulto, 
-- y ese se ignora. Aplicado a todos, una mujer con 13.0 sale marcada como 
-- baja cuando para ella es normal, y el laboratorio repite la muestra sin 
-- necesidad. Al reves, si se usara el rango femenino para todos, un varon 
-- con 13.0 pasaria como normal estando anemico. Un solo rango para los dos
--  sexos falla en las dos direcciones.
CREATE TABLE lab.rango_referencia (
  rango_referencia_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id           bigint NOT NULL,
  analito_id           bigint NOT NULL,
  sexo                 varchar(20) NOT NULL DEFAULT 'ambos',
  -- En dias y no en anios porque los rangos neonatales cambian por
  -- semana.
  edad_min_dias        int NOT NULL DEFAULT 0,
  edad_max_dias        int NOT NULL DEFAULT 54750,
  valor_min            decimal(14,4),
  valor_max            decimal(14,4),
  -- Valor de panico. Fuera de este umbral hay que avisar a alguien y
  -- dejar constancia de a quien y cuando. No es una alerta de interfaz:
  -- es un requisito de auditoria.
  critico_min          decimal(14,4),
  critico_max          decimal(14,4),
  metodo               nvarchar(120),
  texto_libre          nvarchar(max),
  vigente_desde        date NOT NULL DEFAULT CAST(sysutcdatetime() AS date),
  vigente_hasta        date,
  CONSTRAINT rango_referencia_pkey PRIMARY KEY (rango_referencia_id),
  CONSTRAINT ck_rango_critico_alto CHECK (((critico_max IS NULL) OR (valor_max IS NULL) OR (critico_max >= valor_max))),
  CONSTRAINT ck_rango_critico_bajo CHECK (((critico_min IS NULL) OR (valor_min IS NULL) OR (critico_min <= valor_min))),
  CONSTRAINT ck_rango_edad CHECK ((edad_max_dias > edad_min_dias)),
  CONSTRAINT ck_rango_orden CHECK (((valor_min IS NULL) OR (valor_max IS NULL) OR (valor_max > valor_min))),
  CONSTRAINT fk_rango_analito FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito(analito_id, empresa_id),
  CONSTRAINT rango_referencia_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_rango_referencia_sexo CHECK (sexo IN ('femenino', 'masculino', 'ambos'))
);
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- Una visita del paciente. Es el tronco: existe aunque el laboratorio no p
-- articipe. La orden de laboratorio, y manana la de imagenologia, cuelgan 
-- de aqui.
CREATE TABLE core.episodio (
  episodio_id            bigint IDENTITY(1,1) NOT NULL,
  empresa_id             bigint NOT NULL,
  sucursal_id            bigint NOT NULL,
  paciente_id            bigint NOT NULL,
  convenio_id            bigint NOT NULL,
  mensaje_id             bigint,
  numero                 varchar(40) NOT NULL,
  estado                 varchar(20) NOT NULL DEFAULT 'abierto',
  urgente                bit NOT NULL DEFAULT 0,
  observacion            nvarchar(1000),
  anulado_motivo         nvarchar(400),
  creado_por_usuario_id  bigint NOT NULL,
  creado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  cerrado_en             datetime2,
  CONSTRAINT episodio_pkey PRIMARY KEY (episodio_id),
  CONSTRAINT uq_episodio_empresa UNIQUE (episodio_id, empresa_id),
  CONSTRAINT uq_episodio_numero UNIQUE (empresa_id, numero),
  CONSTRAINT ck_episodio_anulado CHECK (((estado <> 'anulado') OR ((anulado_motivo IS NOT NULL) AND (LTRIM(RTRIM(anulado_motivo)) <> '')))),
  CONSTRAINT episodio_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_episodio_convenio FOREIGN KEY (convenio_id, empresa_id) REFERENCES core.convenio(convenio_id, empresa_id),
  CONSTRAINT fk_episodio_mensaje FOREIGN KEY (mensaje_id, empresa_id) REFERENCES core.mensaje(mensaje_id, empresa_id),
  CONSTRAINT fk_episodio_paciente FOREIGN KEY (paciente_id, empresa_id) REFERENCES core.paciente(paciente_id, empresa_id),
  CONSTRAINT fk_episodio_sucursal FOREIGN KEY (sucursal_id, empresa_id) REFERENCES core.sucursal(sucursal_id, empresa_id),
  CONSTRAINT fk_episodio_usuario FOREIGN KEY (creado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT ck_episodio_estado CHECK (estado IN ('abierto', 'cerrado', 'anulado'))
);
GO

-- Un dato externo anotado sobre el propio paciente. Cada empresa guarda la
--  suya y nadie mas la toca. No hay llave hacia el expediente ajeno a prop
-- osito.
CREATE TABLE core.paciente_referencia (
  referencia_id              bigint IDENTITY(1,1) NOT NULL,
  empresa_id                 bigint NOT NULL,
  paciente_id                bigint NOT NULL,
  -- Menciona a otra empresa pero no le da ningun privilegio: RLS impide
  -- leer esa fila, asi que del otro lado es un numero opaco.
  contraparte_empresa_id     bigint NOT NULL,
  expediente_externo         nvarchar(200) NOT NULL,
  confirmado_por_usuario_id  bigint NOT NULL,
  confirmado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  nota                       nvarchar(200),
  anulada_en                 datetime2,
  anulado_motivo             nvarchar(400),
  CONSTRAINT paciente_referencia_pkey PRIMARY KEY (referencia_id),
  CONSTRAINT uq_paciente_referencia UNIQUE (referencia_id, empresa_id),
  CONSTRAINT ck_referencia_anulacion CHECK ((((anulada_en IS NULL) AND (anulado_motivo IS NULL)) OR ((anulada_en IS NOT NULL) AND (anulado_motivo IS NOT NULL) AND (LTRIM(RTRIM(anulado_motivo)) <> '')))),
  CONSTRAINT ck_referencia_contraparte CHECK ((contraparte_empresa_id <> empresa_id)),
  CONSTRAINT ck_referencia_expediente CHECK ((LTRIM(RTRIM(expediente_externo)) <> '')),
  CONSTRAINT fk_referencia_paciente FOREIGN KEY (paciente_id, empresa_id) REFERENCES core.paciente(paciente_id, empresa_id),
  CONSTRAINT fk_referencia_usuario FOREIGN KEY (confirmado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT paciente_referencia_contraparte_empresa_id_fkey FOREIGN KEY (contraparte_empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT paciente_referencia_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

CREATE UNIQUE INDEX uq_referencia_vigente ON core.paciente_referencia (empresa_id, paciente_id, contraparte_empresa_id) WHERE anulada_en IS NULL;
GO


/* =====================================================================
   INTEGRA · los analizadores y lo que mandan
   ===================================================================== */

-- Cada intento de interpretar un mensaje, con su error. Esto es lo que ree
-- mplaza al trigger de transformer.txt: el fallo queda visible en una tabl
-- a que alguien puede consultar, en vez de en un RAISE LOG que nadie lee.
CREATE TABLE integra.intento_proceso (
  intento_proceso_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id          bigint NOT NULL,
  mensaje_crudo_id    bigint NOT NULL,
  numero_intento      smallint NOT NULL,
  exito               bit NOT NULL,
  error               nvarchar(1000),
  detalle             nvarchar(max),
  intentado_en        datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT intento_proceso_pkey PRIMARY KEY (intento_proceso_id),
  CONSTRAINT uq_intento UNIQUE (mensaje_crudo_id, numero_intento),
  CONSTRAINT ck_intento_error CHECK ((exito = 1 OR (error IS NOT NULL))),
  CONSTRAINT fk_intento_mensaje FOREIGN KEY (mensaje_crudo_id, empresa_id) REFERENCES integra.mensaje_crudo(mensaje_crudo_id, empresa_id),
  CONSTRAINT intento_proceso_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- Vive en el nucleo por el resultado de la prueba de imagenologia: las dos
--  ramas emiten un documento validado, versionado, firmado y entregado, co
-- n el mismo comportamiento. Notese que NO apunta a la orden: es la rama l
-- a que apunta al informe. El nucleo nunca conoce a las ramas.
CREATE TABLE core.informe (
  informe_id   bigint IDENTITY(1,1) NOT NULL,
  empresa_id   bigint NOT NULL,
  episodio_id  bigint NOT NULL,
  modulo_id    varchar(40) NOT NULL,
  numero       varchar(40) NOT NULL,
  estado       varchar(20) NOT NULL DEFAULT 'borrador',
  CONSTRAINT informe_pkey PRIMARY KEY (informe_id),
  CONSTRAINT uq_informe_empresa UNIQUE (informe_id, empresa_id),
  CONSTRAINT uq_informe_numero UNIQUE (empresa_id, numero),
  CONSTRAINT fk_informe_episodio FOREIGN KEY (episodio_id, empresa_id) REFERENCES core.episodio(episodio_id, empresa_id),
  CONSTRAINT informe_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT informe_modulo_id_fkey FOREIGN KEY (modulo_id) REFERENCES plataforma.modulo(modulo_id),
  CONSTRAINT ck_informe_estado CHECK (estado IN ('borrador', 'emitido', 'corregido', 'anulado'))
);
GO

CREATE TABLE core.informe_version (
  informe_version_id      bigint IDENTITY(1,1) NOT NULL,
  empresa_id              bigint NOT NULL,
  informe_id              bigint NOT NULL,
  version                 int NOT NULL,
  motivo_correccion       nvarchar(400),
  archivo_ruta            nvarchar(400),
  archivo_hash            varchar(80),
  emitido_por_usuario_id  bigint NOT NULL,
  emitido_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT informe_version_pkey PRIMARY KEY (informe_version_id),
  CONSTRAINT uq_informe_version UNIQUE (informe_id, version),
  CONSTRAINT ck_informe_version_motivo CHECK (((version = 1) OR ((motivo_correccion IS NOT NULL) AND (LTRIM(RTRIM(motivo_correccion)) <> '')))),
  CONSTRAINT ck_informe_version_positiva CHECK ((version >= 1)),
  CONSTRAINT fk_informe_version_informe FOREIGN KEY (informe_id, empresa_id) REFERENCES core.informe(informe_id, empresa_id),
  CONSTRAINT fk_informe_version_usuario FOREIGN KEY (emitido_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT informe_version_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO


/* =====================================================================
   LAB · la rama de laboratorio clinico
   ===================================================================== */

CREATE TABLE lab.orden (
  orden_id               bigint IDENTITY(1,1) NOT NULL,
  empresa_id             bigint NOT NULL,
  episodio_id            bigint NOT NULL,
  informe_id             bigint,
  numero                 varchar(40) NOT NULL,
  -- Es una PROYECCION del estado de sus muestras y resultados, mantenida
  -- por el servicio para que la bandeja de trabajo sea una consulta
  -- barata. La verdad esta en las filas de lab.resultado; hay una prueba
  -- que verifica que no se separen.
  estado                 varchar(30) NOT NULL DEFAULT 'solicitada',
  urgente                bit NOT NULL DEFAULT 0,
  ayuno                  bit,
  observacion            nvarchar(1000),
  anulado_motivo         nvarchar(400),
  creado_por_usuario_id  bigint NOT NULL,
  creado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT orden_pkey PRIMARY KEY (orden_id),
  CONSTRAINT uq_orden_empresa UNIQUE (orden_id, empresa_id),
  CONSTRAINT uq_orden_episodio UNIQUE (episodio_id),
  CONSTRAINT uq_orden_numero UNIQUE (empresa_id, numero),
  CONSTRAINT ck_orden_anulada CHECK (((estado <> 'anulada') OR ((anulado_motivo IS NOT NULL) AND (LTRIM(RTRIM(anulado_motivo)) <> '')))),
  CONSTRAINT fk_orden_episodio FOREIGN KEY (episodio_id, empresa_id) REFERENCES core.episodio(episodio_id, empresa_id),
  CONSTRAINT fk_orden_informe FOREIGN KEY (informe_id, empresa_id) REFERENCES core.informe(informe_id, empresa_id),
  CONSTRAINT fk_orden_usuario FOREIGN KEY (creado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT orden_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_orden_estado CHECK (estado IN ('solicitada', 'muestra_tomada', 'recibida', 'en_proceso', 'resultados_parciales', 'validada', 'entregada', 'anulada'))
);
GO


/* =====================================================================
   CORE · el nucleo: quien, donde y cuando
   ===================================================================== */

-- Quien recibio el informe, cuando y por que medio. Se registra la VERSION
--  entregada: si despues se corrige, se sabe quien tiene en la mano la ver
-- sion vieja.
CREATE TABLE core.entrega (
  entrega_id                bigint IDENTITY(1,1) NOT NULL,
  empresa_id                bigint NOT NULL,
  informe_version_id        bigint NOT NULL,
  medio                     varchar(20) NOT NULL,
  entregado_a               nvarchar(160) NOT NULL,
  parentesco                nvarchar(60),
  documento_receptor        varchar(40),
  entregado_por_usuario_id  bigint NOT NULL,
  entregado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT entrega_pkey PRIMARY KEY (entrega_id),
  CONSTRAINT entrega_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT entrega_informe_version_id_fkey FOREIGN KEY (informe_version_id) REFERENCES core.informe_version(informe_version_id),
  CONSTRAINT fk_entrega_usuario FOREIGN KEY (entregado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT ck_entrega_medio CHECK (medio IN ('mostrador', 'correo', 'convenio'))
);
GO


/* =====================================================================
   LAB · la rama de laboratorio clinico
   ===================================================================== */

-- Un tubo. Una orden puede necesitar tres, de tipos distintos, y uno puede
--  rechazarse sin afectar a los demas. En los esquemas anteriores esto era
--  un campo de texto codTubo en la boleta.
CREATE TABLE lab.muestra (
  muestra_id               bigint IDENTITY(1,1) NOT NULL,
  empresa_id               bigint NOT NULL,
  orden_id                 bigint NOT NULL,
  tipo_muestra_id          bigint NOT NULL,
  -- LA llave del sistema. Nace aqui, se imprime en la etiqueta, viaja en
  -- el OBR-3 del mensaje del analizador y regresa igual. Nunca lo
  -- escribe una persona: por eso el resultado no puede entrar al
  -- paciente equivocado.
  codigo_barra             varchar(40) NOT NULL,
  estado                   varchar(20) NOT NULL DEFAULT 'pendiente',
  volumen_ml               decimal(5,2),
  tomada_en                datetime2,
  tomada_por_usuario_id    bigint,
  recibida_en              datetime2,
  recibida_por_usuario_id  bigint,
  observacion              nvarchar(1000),
  CONSTRAINT muestra_pkey PRIMARY KEY (muestra_id),
  CONSTRAINT uq_muestra_codigo UNIQUE (empresa_id, codigo_barra),
  CONSTRAINT uq_muestra_empresa UNIQUE (muestra_id, empresa_id),
  CONSTRAINT ck_muestra_tomada CHECK (((estado = 'pendiente') OR ((tomada_en IS NOT NULL) AND (tomada_por_usuario_id IS NOT NULL)))),
  CONSTRAINT fk_muestra_orden FOREIGN KEY (orden_id, empresa_id) REFERENCES lab.orden(orden_id, empresa_id),
  CONSTRAINT fk_muestra_recibida_por FOREIGN KEY (recibida_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT fk_muestra_tipo FOREIGN KEY (tipo_muestra_id, empresa_id) REFERENCES lab.tipo_muestra(tipo_muestra_id, empresa_id),
  CONSTRAINT fk_muestra_tomada_por FOREIGN KEY (tomada_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT muestra_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_muestra_estado CHECK (estado IN ('pendiente', 'tomada', 'recibida', 'rechazada', 'en_proceso', 'procesada'))
);
GO

-- El primero de los tres desvios del flujo. Que un tubo se rechace por hem
-- olisis pasa todos los dias, y sin esta tabla el sistema no puede ni expl
-- icarle al paciente por que le van a sacar sangre otra vez.
CREATE TABLE lab.muestra_rechazo (
  muestra_rechazo_id        bigint IDENTITY(1,1) NOT NULL,
  empresa_id                bigint NOT NULL,
  muestra_id                bigint NOT NULL,
  motivo                    varchar(30) NOT NULL,
  detalle                   nvarchar(1000),
  nueva_muestra_id          bigint,
  rechazada_por_usuario_id  bigint NOT NULL,
  rechazada_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT muestra_rechazo_pkey PRIMARY KEY (muestra_rechazo_id),
  CONSTRAINT ck_rechazo_distinta CHECK ((nueva_muestra_id IS NULL OR nueva_muestra_id <> muestra_id)),
  CONSTRAINT fk_rechazo_muestra FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra(muestra_id, empresa_id),
  CONSTRAINT fk_rechazo_nueva FOREIGN KEY (nueva_muestra_id, empresa_id) REFERENCES lab.muestra(muestra_id, empresa_id),
  CONSTRAINT fk_rechazo_usuario FOREIGN KEY (rechazada_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT muestra_rechazo_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_muestra_rechazo_motivo CHECK (motivo IN ('hemolisis', 'coagulo', 'volumen_insuficiente', 'mal_identificada', 'contaminada', 'tubo_incorrecto', 'muestra_vencida', 'derrame'))
);
GO

-- No lleva estado propio: su avance se deriva de sus resultados. Un estado
--  guardado aqui seria una cuarta copia de la verdad, y las copias se sepa
-- ran.
CREATE TABLE lab.orden_prueba (
  orden_prueba_id  bigint IDENTITY(1,1) NOT NULL,
  empresa_id       bigint NOT NULL,
  orden_id         bigint NOT NULL,
  prueba_id        bigint NOT NULL,
  muestra_id       bigint,
  precio_lista     decimal(12,2) NOT NULL,
  -- Congelado. Si el precio solo viviera en el catalogo, cambiarlo
  -- reescribiria la historia de todas las ordenes anteriores y ningun
  -- corte de caja cuadraria dos veces.
  precio           decimal(12,2) NOT NULL,
  convenio_id      bigint NOT NULL,
  anulado_en       datetime2,
  anulado_motivo   nvarchar(400),
  CONSTRAINT orden_prueba_pkey PRIMARY KEY (orden_prueba_id),
  CONSTRAINT uq_orden_prueba_empresa UNIQUE (orden_prueba_id, empresa_id),
  CONSTRAINT uq_orden_prueba_unica UNIQUE (orden_id, prueba_id),
  CONSTRAINT ck_orden_prueba_anulada CHECK ((((anulado_en IS NULL) AND (anulado_motivo IS NULL)) OR ((anulado_en IS NOT NULL) AND (anulado_motivo IS NOT NULL) AND (LTRIM(RTRIM(anulado_motivo)) <> '')))),
  CONSTRAINT ck_orden_prueba_precio CHECK (((precio >= (0)) AND (precio_lista >= (0)))),
  CONSTRAINT fk_orden_prueba_convenio FOREIGN KEY (convenio_id, empresa_id) REFERENCES core.convenio(convenio_id, empresa_id),
  CONSTRAINT fk_orden_prueba_muestra FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra(muestra_id, empresa_id),
  CONSTRAINT fk_orden_prueba_orden FOREIGN KEY (orden_id, empresa_id) REFERENCES lab.orden(orden_id, empresa_id),
  CONSTRAINT fk_orden_prueba_prueba FOREIGN KEY (prueba_id, empresa_id) REFERENCES lab.prueba(prueba_id, empresa_id),
  CONSTRAINT orden_prueba_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id)
);
GO

-- Una fila por analito. El hemograma del Hemax 53 produce 24 de estas y se
--  cobra una sola vez. Las filas no se actualizan salvo para marcarlas ree
-- mplazadas.
CREATE TABLE lab.resultado (
  resultado_id              bigint IDENTITY(1,1) NOT NULL,
  empresa_id                bigint NOT NULL,
  orden_prueba_id           bigint NOT NULL,
  analito_id                bigint NOT NULL,
  muestra_id                bigint,
  valor_numerico            decimal(14,4),
  valor_texto               nvarchar(200),
  unidad                    varchar(30),
  rango_min                 decimal(14,4),
  rango_max                 decimal(14,4),
  rango_texto               nvarchar(120),
  critico_min               decimal(14,4),
  critico_max               decimal(14,4),
  bandera                   varchar(20) NOT NULL DEFAULT 'normal',
  estado                    varchar(20) NOT NULL DEFAULT 'pendiente',
  metodo                    nvarchar(120),
  equipo_id                 bigint,
  mensaje_crudo_id          bigint,
  medido_en                 datetime2,
  capturado_por_usuario_id  bigint,
  validado_por_usuario_id   bigint,
  validado_en               datetime2,
  vigente                   bit NOT NULL DEFAULT 1,
  corrige_a_resultado_id    bigint,
  motivo_correccion         nvarchar(400),
  observacion               nvarchar(1000),
  creado_en                 datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT resultado_pkey PRIMARY KEY (resultado_id),
  CONSTRAINT uq_resultado_empresa UNIQUE (resultado_id, empresa_id),
  CONSTRAINT ck_resultado_correccion CHECK (((estado <> 'corregido') OR ((motivo_correccion IS NOT NULL) AND (LTRIM(RTRIM(motivo_correccion)) <> '') AND (corrige_a_resultado_id IS NOT NULL)))),
  CONSTRAINT ck_resultado_no_se_corrige_solo CHECK ((corrige_a_resultado_id IS NULL OR corrige_a_resultado_id <> resultado_id)),
  CONSTRAINT ck_resultado_tiene_valor CHECK (((estado = 'pendiente') OR (valor_numerico IS NOT NULL) OR (valor_texto IS NOT NULL))),
  CONSTRAINT ck_resultado_validado CHECK (((estado NOT IN ('validado', 'corregido')) OR ((validado_por_usuario_id IS NOT NULL) AND (validado_en IS NOT NULL)))),
  CONSTRAINT fk_resultado_analito FOREIGN KEY (analito_id, empresa_id) REFERENCES lab.analito(analito_id, empresa_id),
  CONSTRAINT fk_resultado_equipo FOREIGN KEY (equipo_id, empresa_id) REFERENCES integra.equipo(equipo_id, empresa_id),
  CONSTRAINT fk_resultado_mensaje FOREIGN KEY (mensaje_crudo_id, empresa_id) REFERENCES integra.mensaje_crudo(mensaje_crudo_id, empresa_id),
  CONSTRAINT fk_resultado_muestra FOREIGN KEY (muestra_id, empresa_id) REFERENCES lab.muestra(muestra_id, empresa_id),
  CONSTRAINT fk_resultado_orden_prueba FOREIGN KEY (orden_prueba_id, empresa_id) REFERENCES lab.orden_prueba(orden_prueba_id, empresa_id),
  CONSTRAINT fk_resultado_validado_por FOREIGN KEY (validado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT resultado_corrige_a_resultado_id_fkey FOREIGN KEY (corrige_a_resultado_id) REFERENCES lab.resultado(resultado_id),
  CONSTRAINT resultado_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT ck_resultado_bandera CHECK (bandera IN ('normal', 'bajo', 'alto', 'critico_bajo', 'critico_alto', 'anormal')),
  CONSTRAINT ck_resultado_estado CHECK (estado IN ('pendiente', 'preliminar', 'validado', 'corregido', 'repetir'))
);
GO

CREATE UNIQUE INDEX uq_resultado_vigente ON lab.resultado (orden_prueba_id, analito_id) WHERE vigente = 1;
GO

-- El segundo desvio del flujo. Una hemoglobina de 5 no es un dato para el 
-- informe de manana: es una llamada telefonica hoy, y hay que poder demost
-- rar a quien se llamo y a que hora.
CREATE TABLE lab.aviso_valor_critico (
  aviso_id                bigint IDENTITY(1,1) NOT NULL,
  empresa_id              bigint NOT NULL,
  resultado_id            bigint NOT NULL,
  avisado_a               nvarchar(160) NOT NULL,
  cargo                   nvarchar(80),
  medio                   varchar(20) NOT NULL,
  mensaje                 nvarchar(max),
  confirmado              bit NOT NULL DEFAULT 0,
  avisado_por_usuario_id  bigint NOT NULL,
  avisado_en              datetime2 NOT NULL DEFAULT sysutcdatetime(),
  CONSTRAINT aviso_valor_critico_pkey PRIMARY KEY (aviso_id),
  CONSTRAINT aviso_valor_critico_empresa_id_fkey FOREIGN KEY (empresa_id) REFERENCES core.empresa(empresa_id),
  CONSTRAINT fk_aviso_resultado FOREIGN KEY (resultado_id, empresa_id) REFERENCES lab.resultado(resultado_id, empresa_id),
  CONSTRAINT fk_aviso_usuario FOREIGN KEY (avisado_por_usuario_id, empresa_id) REFERENCES core.usuario(usuario_id, empresa_id),
  CONSTRAINT ck_aviso_valor_critico_medio CHECK (medio IN ('telefono', 'presencial', 'correo', 'mensaje'))
);
GO


/* =====================================================================
   PROPUESTA · lo que el diseno pide y todavia no existe en PostgreSQL

   Estan aqui para poder verlas en el diagrama junto al resto. No las crea
   ningun archivo 01..17: si aparecen en la base real, alguien se confundio.

   Origen: documentacion/core/01-la-empresa.md seccion 2.4, y H-78.
   ===================================================================== */

-- PROPUESTA · Uno a uno con la empresa. La llave primaria es la foranea, y eso
-- es lo que fuerza el uno a uno. La direccion y el telefono del informe NO van
-- aqui: viven en core.sucursal, porque cambian por sede.
CREATE TABLE core.empresa_configuracion (
  empresa_id                bigint        NOT NULL,
  logo                      nvarchar(400),
  encabezado_texto          nvarchar(1000),
  pie_texto                 nvarchar(1000),
  bloque_firma_texto        nvarchar(1000),
  correo_notificaciones     varchar(160),
  zona_horaria              varchar(60)   NOT NULL DEFAULT 'America/Tegucigalpa',
  CONSTRAINT empresa_configuracion_pkey PRIMARY KEY (empresa_id),
  CONSTRAINT fk_configuracion_empresa FOREIGN KEY (empresa_id)
    REFERENCES core.empresa(empresa_id)
);
GO

-- El enlace y el mensaje ya NO son propuestas: existen en PostgreSQL desde
-- 03_core.sql y 08_enlace_y_mensaje.sql, asi que el generador los toma solos
-- de la base. Con ellos se retiraron core.empresa_asociada, audit.derivacion,
-- rls_derivacion, plataforma.persona y plataforma.conflicto_identidad (H-73,
-- H-76, H-78).


PRINT N'>>> Listo. Diagramas de base de datos > Nuevo diagrama > agregar todas.';
GO

