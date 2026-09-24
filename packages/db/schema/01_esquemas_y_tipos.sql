-- =====================================================================
-- ProLisSaas · 01 · Esquemas y tipos
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

CREATE TYPE plataforma.sexo AS ENUM (
  'femenino',
  'masculino',
  'no_especificado'
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
  'activo',
  'suspendido',
  'bloqueado'
);

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
