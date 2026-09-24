-- =====================================================================
-- ProLisSaas · 17 · El esquema comercial
--
-- Esto NO es del laboratorio. Es del dueno del sistema.
--
-- Aqui vive la relacion comercial con cada cliente: quien es, a quien se le
-- llama, cuando entro, por que, que se le acordo, hasta cuando, y por que se
-- fue. El LIS no lee nada de este esquema. Solo recibe el resultado -- un
-- nivel de acceso y una fecha -- escrito en core.empresa por las funciones
-- de aqui abajo.
--
-- CLIENTE Y EMPRESA NO SON LO MISMO. La empresa es el inquilino del LIS: lo
-- que RLS aisla, lo que tiene sucursales y pacientes. El cliente es quien
-- firmo y a quien se le factura. Casi siempre hay uno de cada uno y por eso
-- se confunden, pero un cliente puede tener varias empresas -- un grupo con
-- dos laboratorios que no se ven entre si -- y entonces es un contrato, una
-- factura y dos inquilinos aislados.
--
-- Reglas que implementa (documentacion/core/01-la-empresa.md):
--   E-17 · El LIS no conoce el motivo. Guarda que puede hacer la empresa y
--          hasta cuando; por que es asi vive aqui y no cruza.
--   E-18 · core y lab NUNCA referencian comercial. comercial referencia
--          core.empresa. Una sola direccion, y lis_app sin privilegios.
--   E-19 · Dos administraciones distintas que no se mezclan.
--
-- Por que en el mismo PostgreSQL y no en otra base: para que el alta siga
-- siendo una sola transaccion (F1-1), para que la llave foranea hacia
-- core.empresa sea real, y para que no existan dos copias del estado del
-- cliente que se puedan desincronizar. Es lo que hacen Plausible, Cal.com y
-- GitLab dentro de su instancia. El dia que haya que separarlo de verdad es
-- un pg_dump de un esquema.
--
-- QUIEN LO USA HOY: vos, con una conexion privilegiada, escribiendo SQL. Con
-- un cliente y dos sucursales no hace falta una consola. Cuando haga falta,
-- lo que se agrega es un rol propio y una aplicacion encima -- no se mueve
-- nada de aqui. Queda anotado en H-58.
-- =====================================================================


CREATE SCHEMA IF NOT EXISTS comercial;

COMMENT ON SCHEMA comercial IS
  'El negocio del dueno del sistema: contratos, altas, bajas y cobros. El LIS '
  'no lo lee. lis_app no tiene ni un privilegio aqui, y esa es la frontera.';


-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------

-- Que le paso a la relacion con el cliente. Cada valor es un hecho, no una
-- transicion: el historial se lee como una linea de tiempo -- "entro el 15 de
-- enero por contrato firmado", "se fue el 1 de febrero por migracion" -- y no
-- como pares de estado anterior y estado nuevo.
CREATE TYPE comercial.tipo_evento AS ENUM (
  'alta',          -- el cliente entra al sistema
  'activacion',    -- pasa de prueba a cliente que paga
  'suspension',    -- pausa: se sale reactivando
  'reactivacion',  -- vuelve de una suspension
  'cancelacion',   -- termina la relacion, empieza el plazo de cierre
  'cierre'         -- vencio el plazo: se corta el acceso
);

-- Quien firma el contrato. En Honduras un laboratorio puede estar a nombre de
-- una sociedad o del RTN de su dueno, y las dos cosas se facturan igual.
CREATE TYPE comercial.tipo_cliente AS ENUM (
  'natural',       -- una persona, con su propio RTN
  'juridica'       -- una sociedad
);

-- Para que hay que llamarle a esta persona. Se llama "papel" y no "rol" a
-- proposito: rol ya significa otra cosa en core.rol, y son mundos distintos.
CREATE TYPE comercial.papel_contacto AS ENUM (
  'firma',         -- quien firma el contrato
  'pago',          -- a quien se le manda la factura
  'tecnico',       -- con quien se coordina lo del sistema
  'general'
);


-- ---------------------------------------------------------------------
-- El cliente · quien te contrato
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

-- Sin columna "activo" a proposito: si el cliente sigue siendo cliente se
-- deduce del estado de sus empresas. Dos copias del mismo estado se
-- desincronizan, y es justo lo que este esquema evita con nivel_acceso.

CREATE UNIQUE INDEX uq_cliente_rtn ON comercial.cliente (rtn) WHERE rtn IS NOT NULL;


-- ---------------------------------------------------------------------
-- Contactos · a quien se le llama
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

CREATE INDEX ix_contacto_cliente ON comercial.contacto (cliente_id, papel)
  WHERE activo;


-- ---------------------------------------------------------------------
-- De quien es cada empresa
--
-- Con vigencia, porque un laboratorio se puede vender: el mismo inquilino,
-- los mismos datos, otro dueno. Eso se cierra una fila y se abre otra.
-- ---------------------------------------------------------------------

-- Para el EXCLUDE de mas abajo: gist necesita saber comparar bigint por
-- igualdad al lado de un rango, y eso lo trae esta extension.
CREATE EXTENSION IF NOT EXISTS btree_gist;

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

CREATE INDEX ix_relacion_evento_empresa
  ON comercial.relacion_evento (empresa_id, fecha DESC, evento_id DESC);

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

CREATE INDEX ix_contrato_cliente ON comercial.contrato (cliente_id, fecha_inicio DESC);

COMMENT ON TABLE comercial.contrato IS
  'Desde cuando, hasta cuando y en que terminos. fecha_fin es la fecha del '
  'contrato, no la del cierre tecnico: esa la calcula el motivo y vive en '
  'core.empresa.fecha_cierre.';


-- ---------------------------------------------------------------------
-- La frontera, hecha cumplir con permisos
--
-- lis_app no recibe nada. Ni USAGE sobre el esquema, asi que la aplicacion
-- del laboratorio no puede ni nombrar estas tablas. Es el mismo mecanismo
-- con el que plataforma.persona esta protegida.
-- ---------------------------------------------------------------------

REVOKE ALL ON SCHEMA comercial FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA comercial FROM PUBLIC;


-- ---------------------------------------------------------------------
-- El unico punto por donde una decision comercial entra al LIS
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION comercial.registrar_evento(
  p_empresa_id  bigint,
  p_motivo_id   text,
  p_por         text,
  p_fecha       date DEFAULT CURRENT_DATE,
  p_nota        text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  m           comercial.motivo%ROWTYPE;
  v_nivel     core.nivel_acceso;
  v_plazo     integer;
  v_vence     date;
  v_estado    core.estado_empresa;
  v_evento_id bigint;
BEGIN
  SELECT * INTO m FROM comercial.motivo WHERE motivo_id = p_motivo_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe el motivo %', p_motivo_id;
  END IF;
  IF NOT m.activo THEN
    RAISE EXCEPTION 'El motivo % esta retirado', p_motivo_id;
  END IF;
  IF m.requiere_nota AND (p_nota IS NULL OR btrim(p_nota) = '') THEN
    RAISE EXCEPTION 'El motivo % exige una nota que explique la decision', p_motivo_id;
  END IF;

  -- Un motivo sin politica pensada no se lee como "sin restriccion": se aplica
  -- lo seguro y se avisa. Pero "lo seguro" solo tiene sentido cuando el evento
  -- RESTRINGE. En un alta o una reactivacion, caer en solo_lectura no es
  -- prudencia: deja al cliente sin poder trabajar el dia que entra. Por eso los
  -- eventos que conceden acceso nacen con su politica definida y en completo, y
  -- lo que queda por decidir es el lado restrictivo: cuanto plazo y con que
  -- nivel durante el.
  IF m.politica_definida THEN
    v_nivel := m.nivel_inmediato;
    v_plazo := m.dias_plazo;
  ELSIF m.tipo_evento IN ('suspension','cancelacion','cierre') THEN
    v_nivel := 'solo_lectura';
    v_plazo := NULL;
    RAISE WARNING 'El motivo % todavia no tiene politica definida: se aplica solo_lectura', p_motivo_id;
  ELSE
    RAISE EXCEPTION 'El motivo % concede acceso y no tiene politica definida. '
                    'Definila antes de usarlo: un alta a medias no se nota hasta '
                    'que el cliente no puede trabajar', p_motivo_id;
  END IF;

  IF v_plazo IS NOT NULL THEN
    v_vence := p_fecha + v_plazo;
  END IF;

  -- El estado que le corresponde al hecho. El LIS guarda el estado para poder
  -- decir en que punto esta; lo que decide que se puede hacer es el nivel.
  v_estado := CASE m.tipo_evento
                WHEN 'alta'         THEN 'prueba'
                WHEN 'activacion'   THEN 'activa'
                WHEN 'suspension'   THEN 'suspendida'
                WHEN 'reactivacion' THEN 'activa'
                WHEN 'cancelacion'  THEN 'cancelada'
                WHEN 'cierre'       THEN 'cerrada'
              END;

  INSERT INTO comercial.relacion_evento (
    empresa_id, tipo_evento, motivo_id, fecha,
    nivel_aplicado, dias_plazo_aplicado, nivel_al_vencer_aplicado,
    estado_al_vencer_aplicado, fecha_vencimiento, politica_estaba_definida,
    nota, registrado_por
  ) VALUES (
    p_empresa_id, m.tipo_evento, m.motivo_id, p_fecha,
    v_nivel, v_plazo, m.nivel_al_vencer,
    m.estado_al_vencer, v_vence, m.politica_definida,
    p_nota, p_por
  ) RETURNING evento_id INTO v_evento_id;

  -- Y aqui, y solo aqui, la decision cruza al LIS.
  UPDATE core.empresa
     SET estado       = v_estado,
         nivel_acceso = v_nivel,
         fecha_cierre = v_vence
   WHERE empresa_id = p_empresa_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe la empresa %', p_empresa_id;
  END IF;

  RETURN v_evento_id;
END $$;

COMMENT ON FUNCTION comercial.registrar_evento IS
  'El unico camino por el que una decision comercial toca core.empresa. Escribe '
  'el hecho con su politica copiada y actualiza estado, nivel y fecha de cierre '
  'en una sola transaccion.';


-- ---------------------------------------------------------------------
-- Lo mismo, pero a nivel de cliente
--
-- Un cliente dejo de pagar: eso no le pasa a un inquilino, le pasa a el. Y
-- se tiene que aplicar a TODAS sus empresas vigentes o queda a medias.
--
-- El evento se sigue guardando por empresa a proposito: el LIS solo entiende
-- de empresas, y el historial tiene que poder leerse desde cualquiera de las
-- dos puntas.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION comercial.registrar_evento_cliente(
  p_cliente_id  bigint,
  p_motivo_id   text,
  p_por         text,
  p_fecha       date DEFAULT CURRENT_DATE,
  p_nota        text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  e         record;
  v_cuenta  integer := 0;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM comercial.cliente WHERE cliente_id = p_cliente_id) THEN
    RAISE EXCEPTION 'No existe el cliente %', p_cliente_id;
  END IF;

  FOR e IN
    SELECT ce.empresa_id
    FROM comercial.cliente_empresa ce
    WHERE ce.cliente_id = p_cliente_id
      AND ce.desde <= p_fecha
      AND (ce.hasta IS NULL OR ce.hasta > p_fecha)
    ORDER BY ce.empresa_id
  LOOP
    PERFORM comercial.registrar_evento(
      e.empresa_id, p_motivo_id, p_por, p_fecha, p_nota);
    v_cuenta := v_cuenta + 1;
  END LOOP;

  -- Un cliente sin ninguna empresa vigente es casi siempre un dedo, no una
  -- decision. Mejor que reviente aqui que descubrirlo cobrando.
  IF v_cuenta = 0 THEN
    RAISE EXCEPTION
      'El cliente % no tiene ninguna empresa vigente al %', p_cliente_id, p_fecha;
  END IF;

  RETURN v_cuenta;
END $$;

COMMENT ON FUNCTION comercial.registrar_evento_cliente IS
  'Aplica un evento comercial a todas las empresas vigentes del cliente, en una '
  'sola transaccion. Suspender a un cliente y que una de sus dos empresas siga '
  'trabajando no es un estado que deba poder existir.';


CREATE OR REPLACE FUNCTION comercial.cerrar_vencidas(p_hoy date DEFAULT CURRENT_DATE)
RETURNS TABLE (empresa_id bigint, nombre text, nivel core.nivel_acceso)
LANGUAGE plpgsql
AS $$
BEGIN
  -- La tarea diaria. Vive de este lado porque el plazo es una decision
  -- comercial, pero lee fecha_cierre de core.empresa, que esta ahi
  -- justamente para que esto funcione sin depender de nada externo.
  RETURN QUERY
  WITH ultimo AS (
    -- Por orden de REGISTRO, no por fecha de negocio: la politica que manda es
    -- la de la ultima decision tomada, y un evento registrado con fecha
    -- retroactiva sigue siendo la decision mas nueva.
    SELECT DISTINCT ON (e.empresa_id)
           e.empresa_id, e.nivel_al_vencer_aplicado, e.estado_al_vencer_aplicado
      FROM comercial.relacion_evento e
     WHERE e.fecha_vencimiento IS NOT NULL
     ORDER BY e.empresa_id, e.evento_id DESC
  ),
  vencidas AS (
    UPDATE core.empresa emp
       SET nivel_acceso = coalesce(u.nivel_al_vencer_aplicado, 'bloqueado'),
           estado       = coalesce(u.estado_al_vencer_aplicado, emp.estado),
           fecha_cierre = NULL
      FROM ultimo u
     WHERE u.empresa_id = emp.empresa_id
       AND emp.fecha_cierre IS NOT NULL
       AND emp.fecha_cierre <= p_hoy
    RETURNING emp.empresa_id, emp.nombre, emp.nivel_acceso
  )
  SELECT v.empresa_id, v.nombre, v.nivel_acceso FROM vencidas v;
END $$;

COMMENT ON FUNCTION comercial.cerrar_vencidas IS
  'Aplica el nivel al vencer a las empresas cuyo plazo se cumplio. Se corre una '
  'vez al dia. Si nadie la corre, el cliente conserva el nivel del plazo: el '
  'cierre no ocurre solo, ocurre porque alguien lo ejecuta.';


REVOKE ALL ON ALL FUNCTIONS IN SCHEMA comercial FROM PUBLIC;


-- ---------------------------------------------------------------------
-- Los motivos que ya conocemos
--
-- Los que CONCEDEN acceso nacen definidos y en completo: que un cliente activo
-- pueda trabajar no es una politica por decidir, es lo normal.
--
-- Los que RESTRINGEN quedan en false, y hasta que alguien decida sus valores
-- aplican solo_lectura y avisan. La excepcion es riesgo_seguridad, que si trae
-- politica: es el unico donde esperar es peor que equivocarse.
-- ---------------------------------------------------------------------

INSERT INTO comercial.motivo
  (motivo_id, tipo_evento, nombre, descripcion,
   nivel_inmediato, dias_plazo, nivel_al_vencer, estado_al_vencer,
   requiere_nota, politica_definida)
VALUES
  -- Entrada
  ('prueba_gratuita',   'alta', 'Periodo de prueba',
   'Evaluacion sin contrato firmado',                'completo', NULL, NULL, NULL, false, true),
  ('contrato_firmado',  'alta', 'Contrato firmado',
   'Entra directamente como cliente',                'completo', NULL, NULL, NULL, false, true),
  ('migracion',         'alta', 'Migracion desde otro sistema',
   'Viene de otro sistema y trae datos',             'completo', NULL, NULL, NULL, true,  true),

  -- Activacion
  ('pago_recibido',     'activacion', 'Pago recibido',
   'Se cobro la primera factura',                    'completo', NULL, NULL, NULL, false, true),
  ('contrato_activado', 'activacion', 'Contrato activado',
   'Termino la prueba y firmo',                      'completo', NULL, NULL, NULL, false, true),

  -- Suspension
  ('falta_pago',        'suspension', 'Falta de pago',
   'Retraso en facturas',                            'solo_lectura', NULL, NULL, NULL, false, false),
  ('solicitud_cliente', 'suspension', 'A peticion del cliente',
   'Pausa temporal: remodelacion, vacaciones',       'solo_lectura', NULL, NULL, NULL, true,  false),
  ('fin_de_prueba',     'suspension', 'Fin del periodo de prueba',
   'Termino la prueba sin convertir',                'solo_lectura', NULL, NULL, NULL, false, false),
  ('incumplimiento',    'suspension', 'Incumplimiento del contrato',
   'Uso indebido o violacion de los terminos',       'solo_lectura', NULL, NULL, NULL, true,  false),
  ('riesgo_seguridad',  'suspension', 'Riesgo de seguridad',
   'Cuenta comprometida o actividad anomala',        'bloqueado', 0, 'bloqueado', 'suspendida', true, true),

  -- Reactivacion
  ('pago_regularizado', 'reactivacion', 'Pago regularizado',
   'Se pusieron al dia',                             'completo', NULL, NULL, NULL, false, true),
  ('acuerdo_alcanzado', 'reactivacion', 'Acuerdo alcanzado',
   'Se resolvio lo que motivo la suspension',        'completo', NULL, NULL, NULL, true,  true),

  -- Cancelacion
  ('cancelacion_con_antelacion', 'cancelacion', 'Cancelacion con antelacion',
   'El cliente aviso con el plazo acordado',         'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('cancelacion_voluntaria',     'cancelacion', 'Cancelacion voluntaria',
   'El cliente se va sin haber avisado',             'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('falta_pago_prolongada',      'cancelacion', 'Falta de pago prolongada',
   'Escalo desde una suspension por mora',           'solo_cierre', NULL, 'bloqueado',    'cerrada', true,  false),
  ('incumplimiento_grave',       'cancelacion', 'Incumplimiento grave',
   'Motivo de terminacion inmediata',                'bloqueado',   NULL, 'bloqueado',    'cerrada', true,  false),
  ('cierre_del_negocio',         'cancelacion', 'El laboratorio cerro',
   'El cliente dejo de operar',                      'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('migracion_a_otro',           'cancelacion', 'Se fue a otro sistema',
   'Cambio de proveedor',                            'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),

  -- Cierre
  ('plazo_vencido',     'cierre', 'Vencio el plazo de cierre',
   'La tarea diaria lo aplico',                      'bloqueado', NULL, NULL, NULL, false, true),
  ('cierre_solicitado', 'cierre', 'Cierre solicitado por el cliente',
   'Pidio cortar el acceso antes de que venza',      'bloqueado', NULL, NULL, NULL, true,  true)
ON CONFLICT (motivo_id) DO NOTHING;
