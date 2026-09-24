-- =====================================================================
-- ProLisSaas - 01 - Esquemas, extensiones y tipos enumerados
--
-- Lo primero que existe. Los estados son tipos enumerados y nunca booleanos:
-- un booleano solo es legitimo cuando de verdad es un si o un no.
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 01_esquemas_y_tipos.sql

-- =====================================================================
-- ProLisSaas - 01 - Esquemas y tipos
-- PostgreSQL 15+
--
-- Orden de ejecucion: 01 -> 02 -> 03 -> 04 -> 05 -> 06
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS plataforma;

CREATE SCHEMA IF NOT EXISTS core;

CREATE SCHEMA IF NOT EXISTS audit;

COMMENT ON SCHEMA plataforma IS
  'Por encima de las empresas. Sin datos clinicos. No lleva empresa_id ni RLS. '
  'Se accede solo por funciones que resuelven, nunca por SELECT directo.';

COMMENT ON SCHEMA core IS
  'El nucleo: lo que toda rama puede leer y ninguna puede modificar. '
  'Toda tabla lleva empresa_id y politica RLS. Regla: si una tabla no puede vivir aqui '
  'sin que la segunda rama la tenga que cambiar, no es del nucleo.';

COMMENT ON SCHEMA audit IS
  'Auditoria y derivaciones entre empresas. Solo se inserta: nunca UPDATE ni DELETE.';

-- ---------------------------------------------------------------------
-- Tipos de plataforma
-- ---------------------------------------------------------------------
CREATE TYPE plataforma.tipo_documento AS ENUM (
  'identidad',
  'pasaporte',
  'carnet_residencia',
  'partida_nacimiento',
  'ninguno'
);

-- Que tan delicado es un permiso: decide quien puede ponerlo en un rol.
--   normal       trabajo del dia a dia; lo asigna cualquier administrador
--   admin        vuelve al rol "de administrador": ese rol y las cuentas que
--                lo tienen solo las toca el propietario (usuario.administrar,
--                sucursal.administrar)
--   propietario  solo el rol del propietario lo tiene; NUNCA se asigna
--                (usuario.nombrar_admin)
-- Vive en la tabla y no en el codigo: cada permiso nuevo declara el suyo en
-- la semilla, y las funciones lo leen (rol_es_admin, asignar_permisos_a_rol).
CREATE TYPE plataforma.nivel_permiso AS ENUM ('normal', 'admin', 'propietario');

CREATE TYPE plataforma.sexo AS ENUM (
  'femenino',
  'masculino'
);

COMMENT ON TYPE plataforma.sexo IS
  'Sexo biologico. No es identidad de genero: determina el rango de referencia '
  'que se aplica a un resultado de laboratorio.';

-- Se retiraron con el registro de identidad compartida (H-73):
--   plataforma.veredicto_identidad
--   plataforma.tipo_conflicto
-- Ninguno de los dos tiene sentido ya: el cotejo dejo de ser global y pasa a
-- ser local y por consulta. Ver documentacion/flujos/06.



-- ---------------------------------------------------------------------
-- Tipos del nucleo
-- ---------------------------------------------------------------------
CREATE TYPE core.estado_empresa AS ENUM (
  'prueba',      -- evaluando, todavia sin contrato
  'activa',      -- opera con normalidad
  'suspendida',  -- pausa temporal; se sale reactivando
  'cancelada',   -- terminada, dentro del plazo de cierre
  'cerrada'      -- vencio el plazo: sin acceso, los datos siguen ahi
);

-- Que puede hacer una empresa AHORA MISMO. Es distinto del estado: el estado
-- dice en que punto de la relacion comercial esta, el nivel dice que se le
-- permite hoy. Lo decide el lado comercial y el LIS solo lo aplica.
CREATE TYPE core.nivel_acceso AS ENUM (
  'completo',      -- todo lo que el producto ofrece
  'solo_cierre',   -- terminar lo abierto; nada nuevo
  'solo_lectura',  -- consultar y exportar; nada mas
  'bloqueado'      -- no se entra
);

CREATE TYPE core.estado_usuario AS ENUM (
  'pendiente_activacion',  -- existe, pero todavia no tiene clave propia
  'activo',
  'suspendido',
  'bloqueado'
);

COMMENT ON TYPE core.estado_usuario IS
  'pendiente_activacion es el estado inicial: el usuario existe, el admin le '
  'entrego un codigo de activacion, y no puede entrar hasta definir su clave. '
  'Un reseteo lo devuelve aqui -- hay un solo camino para estrenar una clave.';

CREATE TYPE core.estado_episodio AS ENUM (
  'abierto',
  'cerrado',
  'anulado'
);

CREATE TYPE core.tipo_convenio AS ENUM (
  'particular',
  'clinica',
  'hospital',
  'aseguradora',
  'empresa',
  'medico'
);

CREATE TYPE core.modalidad_cobro AS ENUM (
  'particular',        -- paga el paciente en el mostrador
  'credito_mensual',   -- se acumula y se factura al convenio al corte
  'copago',            -- el paciente paga una parte
  'reembolso'          -- paga completo el paciente y gestiona su reembolso
);

CREATE TYPE core.estado_informe AS ENUM (
  'borrador',
  'emitido',
  'corregido',
  'anulado'
);

CREATE TYPE core.medio_entrega AS ENUM (
  'mostrador',
  'correo',
  'convenio'
);

-- ---------------------------------------------------------------------
-- El mensaje entre dos empresas
--
-- Reemplaza a audit.estado_derivacion, que era 'solicitada -> aceptada |
-- rechazada | completada'. Esos estados NEGOCIABAN: cada boleta esperaba que
-- alguien del otro lado dijera que si. La aceptacion se mudo una sola vez a
-- la relacion (plataforma.enlace), asi que lo que queda es entrega.
-- ---------------------------------------------------------------------
CREATE TYPE core.direccion_mensaje AS ENUM (
  'enviado',
  'recibido'
);

CREATE TYPE core.tipo_mensaje AS ENUM (
  'solicitud',             -- hospital -> lab: haceme estos examenes
  'consulta_historial',    -- conoces a este paciente? dame lo suyo
  'respuesta_historial',   -- no lo conozco | es este | no puedo confirmar
  'resultado',             -- lab -> hospital: los valores y el informe sellado
  'correccion',            -- un resultado ya entregado cambio
  'aviso'                  -- fusione dos fichas mias, corregi una referencia
);

CREATE TYPE core.estado_mensaje AS ENUM (
  'pendiente',             -- escrito, todavia no entregado   (solo enviado)
  'entregado',             -- la fila del destinatario existe (solo enviado)
  'recibido',              -- llego                           (solo recibido)
  'trabajado',             -- el destinatario lo proceso      (solo recibido)
  'descartado'             -- el destinatario dijo que no     (solo recibido)
);

CREATE TYPE core.tipo_correlativo AS ENUM (
  'expediente',
  'episodio',
  'informe',
  'orden',
  'muestra'
);

-- ---------------------------------------------------------------------
-- Tipos de auditoria
-- ---------------------------------------------------------------------
CREATE TYPE audit.estado_derivacion AS ENUM (
  'solicitada',
  'aceptada',
  'rechazada',
  'completada'
);


-- ---------------------------------------------------------- 10_lab_tipos.sql

-- =====================================================================
-- ProLisSaas - 10 - Rama de laboratorio clinico - esquemas y tipos
--
-- Todo lo de esta rama cuelga de core.episodio. Nada de aqui obliga a
-- cambiar una sola tabla del nucleo: esa fue la prueba de imagenologia.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS lab;

CREATE SCHEMA IF NOT EXISTS integra;

COMMENT ON SCHEMA lab IS
  'Rama de laboratorio clinico. Dueña de sus tablas: ningun otro modulo escribe '
  'aqui, ni siquiera para leer. Apunta al nucleo; el nucleo nunca apunta aqui.';

COMMENT ON SCHEMA integra IS
  'Equipos, mapeo de codigos y mensajes crudos. Separado de lab a proposito: el '
  'dia que la orden entre digitada a mano, esta rama sigue funcionando sin esto.';

-- ---------------------------------------------------------------------
-- Estados - tres maquinas distintas, no una
-- ---------------------------------------------------------------------
CREATE TYPE lab.estado_orden AS ENUM (
  'solicitada',
  'muestra_tomada',
  'recibida',
  'en_proceso',
  'resultados_parciales',
  'validada',
  'entregada',
  'anulada'
);

CREATE TYPE lab.estado_muestra AS ENUM (
  'pendiente',
  'tomada',
  'recibida',
  'rechazada',
  'en_proceso',
  'procesada'
);

CREATE TYPE lab.estado_resultado AS ENUM (
  'pendiente',
  'preliminar',   -- lo mando el equipo, nadie lo ha mirado
  'validado',     -- un bioquimico lo aprobo
  'corregido',    -- reemplaza a uno anterior ya validado
  'repetir'       -- se pidio repeticion
);

COMMENT ON TYPE lab.estado_orden IS
  'Una orden puede estar en_proceso mientras una de sus muestras ya fue rechazada '
  'y otra ya tiene resultados validados. Por eso los estados de orden, muestra y '
  'resultado son tres tipos distintos y no un booleano compartido.';

-- ---------------------------------------------------------------------
-- Motivos y clasificaciones
-- ---------------------------------------------------------------------
CREATE TYPE lab.motivo_rechazo AS ENUM (
  'hemolisis',
  'coagulo',
  'volumen_insuficiente',
  'mal_identificada',
  'contaminada',
  'tubo_incorrecto',
  'muestra_vencida',
  'derrame'
);

CREATE TYPE lab.tipo_valor AS ENUM (
  'numerico',
  'texto',
  'opcion',      -- positivo / negativo / indeterminado
  'booleano'
);

CREATE TYPE lab.bandera AS ENUM (
  'normal',
  'bajo',
  'alto',
  'critico_bajo',
  'critico_alto',
  'anormal'      -- para resultados no numericos
);

CREATE TYPE lab.sexo_rango AS ENUM (
  'femenino',
  'masculino',
  'ambos'
);

CREATE TYPE lab.medio_aviso AS ENUM (
  'telefono',
  'presencial',
  'correo',
  'mensaje'
);

-- ---------------------------------------------------------------------
-- Integracion
-- ---------------------------------------------------------------------
CREATE TYPE integra.protocolo AS ENUM (
  'hl7_v2',        -- el Hemax 53
  'astm_e1394',    -- mucha quimica clinica e inmunoensayo
  'propietario'    -- texto plano por serial, segun el manual del equipo
);

CREATE TYPE integra.estado_mensaje AS ENUM (
  'pendiente',
  'procesado',
  'fallido',
  'ignorado'      -- no corresponde a ninguna orden de este laboratorio
);


-- ---------------------------------------------------------- 17_comercial.sql

-- =====================================================================
-- ProLisSaas - 17 - El esquema comercial
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
--   E-17 - El LIS no conoce el motivo. Guarda que puede hacer la empresa y
--          hasta cuando; por que es asi vive aqui y no cruza.
--   E-18 - core y lab NUNCA referencian comercial. comercial referencia
--          core.empresa. Una sola direccion, y lis_app sin privilegios.
--   E-19 - Dos administraciones distintas que no se mezclan.
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
-- De quien es cada empresa
--
-- Con vigencia, porque un laboratorio se puede vender: el mismo inquilino,
-- los mismos datos, otro dueno. Eso se cierra una fila y se abre otra.
-- ---------------------------------------------------------------------

-- Para el EXCLUDE de mas abajo: gist necesita saber comparar bigint por
-- igualdad al lado de un rango, y eso lo trae esta extension.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Para buscar pacientes por parecido y no por texto exacto: "sair" tiene que
-- encontrar a Sair primero y a Said despues. Trigramas (viene con PostgreSQL;
-- en Windows tambien). Se usa con el esquema puesto (public.word_similarity,
-- public.gin_trgm_ops): desde PostgreSQL 17 los indices se construyen con
-- search_path = pg_catalog y un nombre sin esquema no se encuentra.
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- =====================================================================
-- LLAVES DE UNICIDAD
--
-- Funciones puras (IMMUTABLE) que dicen cuando dos datos escritos distinto
-- son EL MISMO dato: "Said Gabriel" y "said  gabriel", "9933-4455" y
-- "+504 9933 4455", "cmq-2841" y "CMQ 2841". Los indices unicos de
-- 03_indices.sql se construyen sobre estas llaves, y por eso viven aqui,
-- antes de las tablas: un indice no puede usar una funcion que todavia no
-- existe.
--
-- Son IMMUTABLE de verdad -- solo texto adentro, texto afuera, sin leer
-- nada -- que es lo que Postgres exige para indexar una expresion. Sin la
-- extension unaccent, que no siempre esta en un servidor administrado.
-- =====================================================================

-- Quita acentos y dieresis, y deja un solo espacio entre palabras. Sin
-- depender de la extension unaccent. La usan pacientes (posibles
-- duplicados) y las llaves de abajo. Con el esquema puesto, aqui y en
-- quien la llama: desde PostgreSQL 17, CREATE INDEX evalua la expresion
-- con search_path = pg_catalog, y un nombre sin esquema no se encuentra.
CREATE OR REPLACE FUNCTION public.unaccent_simple(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  -- La tabla de acentos va con escapes \uXXXX y no con las letras: el
  -- archivo queda en ASCII puro y carga igual desde una consola Windows
  -- (WIN1252) que desde Linux (UTF8). Es aeiou AEIOU (agudas), aeiou AEIOU
  -- (dieresis), aeiou AEIOU (graves), n N.
  SELECT translate(
    btrim(regexp_replace(coalesce(p_texto,''), '\s+', ' ', 'g')),
    E'\u00e1\u00e9\u00ed\u00f3\u00fa\u00c1\u00c9\u00cd\u00d3\u00da\u00e4\u00eb\u00ef\u00f6\u00fc\u00c4\u00cb\u00cf\u00d6\u00dc\u00e0\u00e8\u00ec\u00f2\u00f9\u00c0\u00c8\u00cc\u00d2\u00d9\u00f1\u00d1',
    'aeiouAEIOUaeiouAEIOUaeiouAEIOUnN'
  )
$$;

-- El nombre entero: nombres y apellidos juntos, en minusculas, sin acentos
-- ni espacios de mas. Es LA SUMA lo que no se repite: "Said Gabriel" +
-- "Hoch Urbina" y "Said" + "Gabriel Hoch Urbina" son la misma persona.
CREATE OR REPLACE FUNCTION core.llave_nombre(p_nombres text, p_apellidos text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT lower(public.unaccent_simple(coalesce(p_nombres,'') || ' ' || coalesce(p_apellidos,'')))
$$;

-- Identidad y colegiacion: solo letras y numeros, en mayusculas. Los
-- guiones y espacios son de quien lo escribe, no del documento:
-- "0801-1994-08899" es "0801199408899". NULL si no queda nada.
CREATE OR REPLACE FUNCTION core.llave_documento(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(regexp_replace(upper(coalesce(p_texto,'')), '[^A-Z0-9]', '', 'g'), '')
$$;

-- Telefono: solo digitos, y sin el 504 de Honduras si lo trae adelante
-- ("+504 9933-4455" y "9933-4455" son el mismo numero). NULL si no queda
-- nada.
CREATE OR REPLACE FUNCTION core.llave_telefono(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(
    CASE WHEN length(d) = 11 AND d LIKE '504%' THEN substr(d, 4) ELSE d END, '')
  FROM (SELECT regexp_replace(coalesce(p_texto,''), '\D', '', 'g') AS d) x
$$;

-- Un texto suelto (el nombre de un rol, de un examen): minusculas, sin
-- acentos, un solo espacio. NULL si no queda nada.
CREATE OR REPLACE FUNCTION core.llave_texto(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(lower(public.unaccent_simple(coalesce(p_texto,''))), '')
$$;

-- Correo: en minusculas y sin espacios alrededor. NULL si no queda nada.
CREATE OR REPLACE FUNCTION core.llave_correo(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(lower(btrim(coalesce(p_texto,''))), '')
$$;
