-- =====================================================================
-- ProLisSaas · 07 · El paciente y su identidad LOCAL
--
-- Este archivo cambio de tema por completo.
--
-- ANTES resolvia identidad COMPARTIDA: plataforma.persona guardaba el
-- documento del paciente una sola vez para todo el despliegue, y las empresas
-- se colgaban de esa fila para saber que atendian al mismo senor. Traia
-- conflicto_identidad, vincular_persona(), vincular_paciente_identidad() y un
-- veredicto con cuatro valores.
--
-- Todo eso se retiro. El modelo decidido no comparte NADA entre empresas: cada
-- una anota en su propia ficha como la llama la otra
-- (core.paciente_referencia, en 03_core.sql), y el que tiene los datos es el
-- que coteja, fallando cerrado cuando duda.
--
-- Lo que queda aqui es identidad DENTRO de una empresa:
--   * registrar un paciente sin dejar entrar un documento repetido
--   * buscar posibles duplicados antes de crear uno
--   * anotar y anular la referencia externa, que nace de una confirmacion
--     humana con el paciente presente
--
-- Ver documentacion/flujos/06-el-paciente-entre-dos-empresas.md y H-73.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Registrar un paciente
--
-- Es el unico camino para crear uno. Garantiza dos cosas: que el expediente
-- se llena con lo que recepcion escribio y nunca con datos traidos de otra
-- empresa, y que un documento repetido dentro de la MISMA empresa no crea un
-- segundo expediente.
--
-- Ya no intenta vincular con ningun registro global, porque no existe.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.registrar_paciente(
  p_empresa_id       bigint,
  p_nombres          text,
  p_apellidos        text,
  p_tipo_documento   plataforma.tipo_documento,
  p_documento        text,
  p_fecha_nacimiento date,
  p_sexo             plataforma.sexo,
  p_telefono         text DEFAULT NULL,
  p_correo           text DEFAULT NULL,
  p_direccion        text DEFAULT NULL,
  p_usuario_id       bigint DEFAULT NULL
)
RETURNS TABLE (
  paciente_id bigint,
  expediente  text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_expediente text;
  v_paciente   bigint;
  v_existente  text;
BEGIN
  PERFORM core.exigir_permiso('paciente.crear', p_usuario_id);

  -- Un documento mal tecleado que ya existe aqui se atrapa ahora. Entre
  -- empresas no hay nada que atrapar: los expedientes son independientes.
  IF coalesce(p_tipo_documento,'ninguno') <> 'ninguno'
     AND btrim(coalesce(p_documento,'')) <> '' THEN
    SELECT pa.expediente INTO v_existente
    FROM core.paciente pa
    WHERE pa.empresa_id     = p_empresa_id
      AND pa.tipo_documento = p_tipo_documento
      AND pa.documento      = btrim(p_documento)
      AND pa.fusionado_en_paciente_id IS NULL;

    IF FOUND THEN
      RAISE EXCEPTION
        'Ese documento ya esta registrado en el expediente %. Abre ese expediente '
        'en vez de crear uno nuevo; si de verdad es otra persona, revisa el numero.',
        v_existente
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;

  v_expediente := core.siguiente_correlativo(p_empresa_id, NULL, 'expediente');

  INSERT INTO core.paciente (
    empresa_id, expediente,
    nombres, apellidos, tipo_documento, documento,
    fecha_nacimiento, sexo, telefono, correo, direccion,
    creado_por_usuario_id
  ) VALUES (
    p_empresa_id, v_expediente,
    btrim(p_nombres), btrim(p_apellidos),
    coalesce(p_tipo_documento,'ninguno'),
    CASE WHEN coalesce(p_tipo_documento,'ninguno') = 'ninguno'
         THEN NULL ELSE btrim(p_documento) END,
    p_fecha_nacimiento, coalesce(p_sexo,'no_especificado'),
    p_telefono, p_correo, p_direccion,
    p_usuario_id
  )
  RETURNING core.paciente.paciente_id INTO v_paciente;

  RETURN QUERY SELECT v_paciente, v_expediente;
END $$;

COMMENT ON FUNCTION core.registrar_paciente IS
  'El unico camino para crear un paciente. El expediente se llena con lo que '
  'recepcion escribio y con nada mas: ningun dato entra desde otra empresa.';

GRANT EXECUTE ON FUNCTION core.registrar_paciente TO lis_app;


-- ---------------------------------------------------------------------
-- Anotar la referencia externa
--
-- La pieza que reemplaza a toda la identidad compartida. Nace de una
-- CONFIRMACION HUMANA con el paciente presente, o de un cotejo de dos factores
-- que el sistema pudo resolver sin dudar. Nunca de elegir en una lista (F6-2).
--
-- Por eso el usuario que confirma es obligatorio: si nadie confirmo, no hay
-- referencia. Fallar cerrado es la respuesta correcta.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.anotar_referencia(
  p_empresa_id             bigint,
  p_paciente_id            bigint,
  p_contraparte_empresa_id bigint,
  p_expediente_externo     text,
  p_usuario_id             bigint,
  p_nota                   text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_referencia bigint;
BEGIN
  PERFORM core.exigir_permiso('paciente.editar', p_usuario_id);

  IF btrim(coalesce(p_expediente_externo,'')) = '' THEN
    RAISE EXCEPTION 'La referencia externa no puede ir vacia';
  END IF;

  -- Solo se anota hacia una empresa con la que hay una ruta vigente. Sin
  -- enlace no hay con quien intercambiar, asi que la referencia no tendria
  -- para que existir.
  --
  -- Se pregunta por core.mis_enlaces() y no leyendo plataforma.enlace: esa
  -- tabla no es de ninguna de las dos empresas y lis_app no tiene un solo
  -- privilegio sobre ella. Solo DOS funciones la tocan en todo el sistema --
  -- mis_enlaces() para contestar tu lado y entregar() para rutear-- y todo lo
  -- demas pasa por ellas. Si aparece una tercera, algo se torcio.
  IF NOT EXISTS (
    SELECT 1 FROM core.mis_enlaces(p_empresa_id) e
    WHERE e.contraparte_empresa_id = p_contraparte_empresa_id
  ) THEN
    RAISE EXCEPTION
      'No hay ninguna ruta vigente con esa empresa: no se puede anotar una '
      'referencia hacia alguien con quien no se trabaja';
  END IF;

  INSERT INTO core.paciente_referencia (
    empresa_id, paciente_id, contraparte_empresa_id,
    expediente_externo, confirmado_por_usuario_id, nota
  ) VALUES (
    p_empresa_id, p_paciente_id, p_contraparte_empresa_id,
    btrim(p_expediente_externo), p_usuario_id, p_nota
  )
  RETURNING referencia_id INTO v_referencia;

  RETURN v_referencia;
END $$;

COMMENT ON FUNCTION core.anotar_referencia IS
  'Nace de una confirmacion humana con el paciente presente. El usuario que '
  'confirma es obligatorio a proposito: sin el, no hay referencia.';

GRANT EXECUTE ON FUNCTION core.anotar_referencia TO lis_app;


-- ---------------------------------------------------------------------
-- Anular una referencia mal confirmada
--
-- Alguien confirmo al paciente equivocado en la ventanilla. El dano existe,
-- pero es LOCAL: la empresa que la escribio la anula y nadie mas se entera.
-- Comparalo con una identidad compartida, donde el mismo error lo heredaban
-- las dos y habia que negociarlo.
--
-- No se borra ni se edita: se anula con motivo y se escribe otra. Que alguien
-- haya confundido dos pacientes es justo lo que hay que poder auditar despues.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.anular_referencia(
  p_referencia_id bigint,
  p_motivo        text,
  p_usuario_id    bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM core.exigir_permiso('paciente.editar', p_usuario_id);

  IF btrim(coalesce(p_motivo,'')) = '' THEN
    RAISE EXCEPTION 'Anular una referencia exige un motivo';
  END IF;

  UPDATE core.paciente_referencia
     SET anulada_en = now(), anulado_motivo = btrim(p_motivo)
   WHERE referencia_id = p_referencia_id
     AND anulada_en IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa referencia no existe o ya estaba anulada';
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION core.anular_referencia TO lis_app;


-- ---------------------------------------------------------------------
-- Normalizacion minima para comparar nombres
--
-- Sin depender de la extension unaccent, que no siempre esta disponible en un
-- servidor administrado.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION unaccent_simple(p_texto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT translate(
    btrim(regexp_replace(coalesce(p_texto,''), '\s+', ' ', 'g')),
    'áéíóúÁÉÍÓÚäëïöüÄËÏÖÜàèìòùÀÈÌÒÙñÑ',
    'aeiouAEIOUaeiouAEIOUaeiouAEIOUnN'
  )
$$;

GRANT EXECUTE ON FUNCTION unaccent_simple TO lis_app;


-- ---------------------------------------------------------------------
-- Posibles duplicados DENTRO de la misma empresa
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.posibles_duplicados(
  p_empresa_id       bigint,
  p_apellidos        text,
  p_nombres          text,
  p_fecha_nacimiento date
)
RETURNS TABLE (
  paciente_id bigint,
  expediente  text,
  nombre_completo text,
  fecha_nacimiento date,
  documento   text,
  coincidencia text
)
LANGUAGE sql
STABLE
AS $$
  SELECT p.paciente_id, p.expediente, p.nombre_completo, p.fecha_nacimiento, p.documento,
         CASE
           WHEN p.fecha_nacimiento = p_fecha_nacimiento THEN 'apellidos y fecha exacta'
           ELSE 'apellidos y ano de nacimiento'
         END
  FROM core.paciente p
  WHERE p.empresa_id = p_empresa_id
    AND p.fusionado_en_paciente_id IS NULL
    AND upper(unaccent_simple(p.apellidos)) = upper(unaccent_simple(p_apellidos))
    AND (
      p.fecha_nacimiento = p_fecha_nacimiento
      OR extract(year from p.fecha_nacimiento) = extract(year from p_fecha_nacimiento)
    )
  ORDER BY (p.fecha_nacimiento = p_fecha_nacimiento) DESC, p.creado_en DESC
  LIMIT 20
$$;

COMMENT ON FUNCTION core.posibles_duplicados IS
  'Se llama ANTES de crear un paciente, y busca solo dentro de la MISMA empresa: '
  'nunca muestra pacientes de otra. Es la defensa contra el duplicado que se crea '
  'porque el paciente ya venia registrado y nadie lo busco.';

GRANT EXECUTE ON FUNCTION core.posibles_duplicados TO lis_app;
