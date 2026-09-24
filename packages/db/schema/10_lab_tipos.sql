-- =====================================================================
-- ProLisSaas · 10 · Rama de laboratorio clinico · esquemas y tipos
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
-- Estados · tres maquinas distintas, no una
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
