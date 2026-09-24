-- =====================================================================
-- ProLisSaas · 14 · Aislamiento y funciones de la rama
--
-- El mismo patron del nucleo, aplicado a lab e integra sin una sola
-- excepcion. Y las tres funciones que hacen que "el rango se copia al
-- resultado" no dependa de que alguien se acuerde.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Permisos del rol de aplicacion
-- ---------------------------------------------------------------------

GRANT USAGE ON SCHEMA lab, integra TO lis_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA lab     TO lis_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA integra TO lis_app;
REVOKE DELETE ON ALL TABLES IN SCHEMA lab     FROM lis_app;
REVOKE DELETE ON ALL TABLES IN SCHEMA integra FROM lis_app;


-- ---------------------------------------------------------------------
-- RLS · identico al nucleo, sin excepciones
-- ---------------------------------------------------------------------

DO $$
DECLARE
  s text;
  t text;
BEGIN
  FOREACH s IN ARRAY ARRAY['lab','integra'] LOOP
    FOR t IN
      SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
      WHERE n.nspname = s AND c.relkind = 'r'
    LOOP
      EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', s, t);
      EXECUTE format('ALTER TABLE %I.%I FORCE  ROW LEVEL SECURITY', s, t);
      EXECUTE format(
        'CREATE POLICY %I ON %I.%I USING (empresa_id = core.empresa_actual()) '
        'WITH CHECK (empresa_id = core.empresa_actual())',
        'rls_' || t, s, t);
    END LOOP;
  END LOOP;
END $$;

-- Sin marcas de tiempo, igual que en el nucleo: las columnas actualizado_en de
-- lab.prueba, lab.orden y lab.muestra se fueron con sus triggers (H-96).


-- ---------------------------------------------------------------------
-- Que rango aplica · lo mas especifico gana
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lab.rango_para(
  p_empresa_id bigint,
  p_analito_id bigint,
  p_sexo       plataforma.sexo,
  p_edad_dias  integer,
  p_fecha      date DEFAULT current_date
)
RETURNS TABLE (
  valor_min   numeric,
  valor_max   numeric,
  critico_min numeric,
  critico_max numeric,
  rango_texto text
)
LANGUAGE sql
STABLE
AS $$
  SELECT r.valor_min, r.valor_max, r.critico_min, r.critico_max, r.texto_libre
  FROM lab.rango_referencia r
  WHERE r.empresa_id = p_empresa_id
    AND r.analito_id = p_analito_id
    AND coalesce(p_edad_dias, 0) BETWEEN r.edad_min_dias AND r.edad_max_dias
    AND (r.sexo = 'ambos' OR r.sexo::text = p_sexo::text)
    AND r.vigente_desde <= p_fecha
    AND (r.vigente_hasta IS NULL OR r.vigente_hasta >= p_fecha)
  ORDER BY
    (r.sexo <> 'ambos') DESC,                  -- el rango por sexo gana al general
    (r.edad_max_dias - r.edad_min_dias) ASC,   -- el tramo de edad mas estrecho gana
    r.vigente_desde DESC
  LIMIT 1
$$;

COMMENT ON FUNCTION lab.rango_para IS
  'Resuelve el rango del LABORATORIO. Sin edad conocida se asume adulto general, '
  'y esa suposicion queda copiada en el resultado para que se pueda auditar.';


CREATE OR REPLACE FUNCTION lab.bandera_para(
  p_valor numeric, p_min numeric, p_max numeric,
  p_critico_min numeric, p_critico_max numeric
)
RETURNS lab.bandera
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_valor IS NULL                                   THEN 'normal'::lab.bandera
    WHEN p_critico_min IS NOT NULL AND p_valor < p_critico_min THEN 'critico_bajo'
    WHEN p_critico_max IS NOT NULL AND p_valor > p_critico_max THEN 'critico_alto'
    WHEN p_min IS NOT NULL AND p_valor < p_min             THEN 'bajo'
    WHEN p_max IS NOT NULL AND p_valor > p_max             THEN 'alto'
    ELSE 'normal'
  END
$$;


-- ---------------------------------------------------------------------
-- Que precio aplica · de lo mas especifico a lo mas general
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lab.precio_para(
  p_empresa_id  bigint,
  p_prueba_id   bigint,
  p_sucursal_id bigint,
  p_convenio_id bigint,
  p_fecha       date DEFAULT current_date
)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT p.precio
  FROM lab.precio_prueba p
  WHERE p.empresa_id = p_empresa_id
    AND p.prueba_id  = p_prueba_id
    AND (p.sucursal_id IS NULL OR p.sucursal_id = p_sucursal_id)
    AND (p.convenio_id IS NULL OR p.convenio_id = p_convenio_id)
    AND p.vigente_desde <= p_fecha
    AND (p.vigente_hasta IS NULL OR p.vigente_hasta >= p_fecha)
  ORDER BY
    (p.convenio_id IS NOT NULL) DESC,   -- tarifa negociada gana
    (p.sucursal_id IS NOT NULL) DESC,   -- luego precio de esta sucursal
    p.vigente_desde DESC
  LIMIT 1
$$;


-- ---------------------------------------------------------------------
-- Registrar un resultado · el rango se copia solo
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lab.registrar_resultado(
  p_orden_prueba_id  bigint,
  p_analito_id       bigint,
  p_valor_numerico   numeric  DEFAULT NULL,
  p_valor_texto      text     DEFAULT NULL,
  p_muestra_id       bigint   DEFAULT NULL,
  p_equipo_id        bigint   DEFAULT NULL,
  p_mensaje_crudo_id bigint   DEFAULT NULL,
  p_medido_en        timestamptz DEFAULT now(),
  p_usuario_id       bigint   DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_empresa_id  bigint;
  v_sexo        plataforma.sexo;
  v_edad_dias   integer;
  v_unidad      text;
  v_metodo      text;
  v_nota        text;
  v_rango       record;
  v_resultado_id bigint;
BEGIN
  -- El sexo y la edad salen del paciente del episodio: son lo que decide el rango.
  SELECT op.empresa_id,
         pa.sexo,
         (current_date - pa.fecha_nacimiento)::integer,
         pr.metodo
    INTO v_empresa_id, v_sexo, v_edad_dias, v_metodo
  FROM lab.orden_prueba op
  JOIN lab.orden    o  ON o.orden_id     = op.orden_id
  JOIN core.episodio e ON e.episodio_id  = o.episodio_id
  JOIN core.paciente pa ON pa.paciente_id = e.paciente_id
  JOIN lab.prueba   pr ON pr.prueba_id   = op.prueba_id
  WHERE op.orden_prueba_id = p_orden_prueba_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El examen pedido % no existe', p_orden_prueba_id;
  END IF;

  SELECT unidad INTO v_unidad FROM lab.analito WHERE analito_id = p_analito_id;

  -- Sin fecha de nacimiento se asume adulto, PERO queda escrito en el resultado.
  -- Una suposicion que no se ve es una suposicion que nadie corrige.
  IF v_edad_dias IS NULL THEN
    v_edad_dias := 10950;   -- 30 anios
    v_nota := 'Rango de adulto aplicado: paciente sin fecha de nacimiento registrada';
  END IF;

  SELECT * INTO v_rango
  FROM lab.rango_para(v_empresa_id, p_analito_id, v_sexo, v_edad_dias);

  INSERT INTO lab.resultado (
    empresa_id, orden_prueba_id, analito_id, muestra_id,
    valor_numerico, valor_texto, unidad,
    rango_min, rango_max, critico_min, critico_max, rango_texto,
    bandera, estado, metodo, equipo_id, mensaje_crudo_id,
    medido_en, capturado_por_usuario_id, observacion
  ) VALUES (
    v_empresa_id, p_orden_prueba_id, p_analito_id, p_muestra_id,
    p_valor_numerico, p_valor_texto, v_unidad,
    v_rango.valor_min, v_rango.valor_max, v_rango.critico_min, v_rango.critico_max,
    v_rango.rango_texto,
    lab.bandera_para(p_valor_numerico, v_rango.valor_min, v_rango.valor_max,
                     v_rango.critico_min, v_rango.critico_max),
    'preliminar', v_metodo, p_equipo_id, p_mensaje_crudo_id,
    p_medido_en, p_usuario_id, v_nota
  )
  RETURNING resultado_id INTO v_resultado_id;

  RETURN v_resultado_id;
END $$;

COMMENT ON FUNCTION lab.registrar_resultado IS
  'El rango se copia aqui, una sola vez, en el unico camino por el que entra un '
  'resultado. Asi la regla "el informe de hace un anio muestra el rango que se uso '
  'ese dia" no depende de que nadie la olvide en algun endpoint nuevo.';


-- ---------------------------------------------------------------------
-- Corregir · insertar una version nueva, nunca sobrescribir
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lab.corregir_resultado(
  p_resultado_id   bigint,
  p_valor_numerico numeric,
  p_valor_texto    text,
  p_motivo         text,
  p_usuario_id     bigint
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_ant   lab.resultado%ROWTYPE;
  v_nuevo bigint;
BEGIN
  PERFORM core.exigir_permiso('resultado.corregir', p_usuario_id);

  IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
    RAISE EXCEPTION 'Corregir un resultado exige un motivo';
  END IF;

  SELECT * INTO v_ant FROM lab.resultado WHERE resultado_id = p_resultado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El resultado % no existe', p_resultado_id;
  END IF;
  IF NOT v_ant.vigente THEN
    RAISE EXCEPTION 'Ese resultado ya fue corregido; corrige el vigente';
  END IF;

  -- Primero se retira la vigencia del anterior y despues se inserta el nuevo.
  -- El orden importa: el indice unico parcial solo admite un resultado vigente
  -- por analito, y es esa restriccion la que garantiza que no queden dos valores
  -- validos al mismo tiempo.
  UPDATE lab.resultado SET vigente = false WHERE resultado_id = p_resultado_id;

  -- El valor viejo NO se toca: solo dejo de ser el vigente. El nuevo lleva el
  -- mismo rango que se aplico entonces, porque corregir el valor no es cambiar
  -- el criterio con el que se juzgo.
  INSERT INTO lab.resultado (
    empresa_id, orden_prueba_id, analito_id, muestra_id,
    valor_numerico, valor_texto, unidad,
    rango_min, rango_max, critico_min, critico_max, rango_texto,
    bandera, estado, metodo, equipo_id, medido_en,
    capturado_por_usuario_id, validado_por_usuario_id, validado_en,
    corrige_a_resultado_id, motivo_correccion
  ) VALUES (
    v_ant.empresa_id, v_ant.orden_prueba_id, v_ant.analito_id, v_ant.muestra_id,
    p_valor_numerico, p_valor_texto, v_ant.unidad,
    v_ant.rango_min, v_ant.rango_max, v_ant.critico_min, v_ant.critico_max,
    v_ant.rango_texto,
    lab.bandera_para(p_valor_numerico, v_ant.rango_min, v_ant.rango_max,
                     v_ant.critico_min, v_ant.critico_max),
    'corregido', v_ant.metodo, v_ant.equipo_id, v_ant.medido_en,
    p_usuario_id, p_usuario_id, now(),
    p_resultado_id, p_motivo
  )
  RETURNING resultado_id INTO v_nuevo;

  INSERT INTO audit.evento (
    empresa_id, usuario_id, accion, nombre_esquema, nombre_tabla,
    registro_id, datos_antes, datos_despues
  ) VALUES (
    v_ant.empresa_id, p_usuario_id, 'resultado.corregir', 'lab', 'resultado',
    p_resultado_id,
    jsonb_build_object('valor_numerico', v_ant.valor_numerico,
                       'valor_texto',    v_ant.valor_texto),
    jsonb_build_object('valor_numerico', p_valor_numerico,
                       'valor_texto',    p_valor_texto,
                       'motivo',         p_motivo,
                       'resultado_id',   v_nuevo)
  );

  RETURN v_nuevo;
END $$;


-- ---------------------------------------------------------------------
-- Validar
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lab.validar_resultado(
  p_resultado_id bigint,
  p_usuario_id   bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_bandera lab.bandera;
  v_empresa bigint;
BEGIN
  PERFORM core.exigir_permiso('resultado.validar', p_usuario_id);

  -- Regla del dominio, no de seguridad: quien firma un resultado tiene que
  -- tener colegiacion registrada, porque ese numero va impreso en el informe
  -- junto a la firma. Un permiso no convierte a nadie en bioquimico.
  IF NOT EXISTS (
    SELECT 1 FROM core.usuario u
    JOIN core.empleado e ON e.empleado_id = u.empleado_id AND e.empresa_id = u.empresa_id
    WHERE u.usuario_id = p_usuario_id
      AND e.numero_colegiacion IS NOT NULL
      AND btrim(e.numero_colegiacion) <> ''
  ) THEN
    RAISE EXCEPTION
      'Quien valida un resultado debe tener numero de colegiacion registrado';
  END IF;

  UPDATE lab.resultado
     SET estado = 'validado',
         validado_por_usuario_id = p_usuario_id,
         validado_en = now()
   WHERE resultado_id = p_resultado_id
     AND estado = 'preliminar'
     AND vigente
  RETURNING bandera, empresa_id INTO v_bandera, v_empresa;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El resultado % no esta preliminar y vigente', p_resultado_id;
  END IF;

  -- Un valor critico validado sin aviso registrado es exactamente el caso que
  -- este sistema existe para no dejar pasar.
  IF v_bandera IN ('critico_bajo','critico_alto')
     AND NOT EXISTS (SELECT 1 FROM lab.aviso_valor_critico
                     WHERE resultado_id = p_resultado_id) THEN
    RAISE EXCEPTION
      'Resultado % tiene valor critico (%): registra a quien se aviso antes de validar',
      p_resultado_id, v_bandera;
  END IF;

  INSERT INTO audit.evento (empresa_id, usuario_id, accion,
                            nombre_esquema, nombre_tabla, registro_id)
  VALUES (v_empresa, p_usuario_id, 'resultado.validar', 'lab', 'resultado', p_resultado_id);
END $$;

COMMENT ON FUNCTION lab.validar_resultado IS
  'Validacion POR RESULTADO. La accion "validar todo lo pendiente" de la interfaz '
  'es un ciclo sobre esta funcion: asi entregar una parte mientras se repite otra '
  'sale gratis, que es lo que pasa cuando un examen sale anomalo.';
