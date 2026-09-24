-- =====================================================================
-- ProLisSaas · 08 · El enlace y el mensaje · lo unico que cruza
--
-- Las tablas estan en 03_core.sql, porque tienen que existir antes de que el
-- bucle de RLS de 05 les ponga politica. Aqui van las funciones.
--
-- LA IDEA. Antes, que un dato cruzara de una empresa a otra dependia de una
-- politica de RLS -- rls_derivacion, la unica del sistema que comparaba dos
-- empresa_id -- y una politica la dispara cualquier consulta desde cualquier
-- parte. Ahora depende de core.entregar(), que es el UNICO punto del sistema
-- donde eso pasa: codigo que se lee, se prueba y se audita.
--
-- SOBRE exigir_permiso. Estas funciones son SECURITY DEFINER porque tienen que
-- escribir la fila del destinatario, y core.exigir_permiso() NO SIRVE ahi
-- dentro: su escape comprueba current_user, que dentro de una funcion definida
-- por postgres vale 'postgres' y no 'lis_app', asi que la comprobacion se salta
-- siempre (H-57). Por eso aqui se llama a core.usuario_puede() directo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Crear una ruta · SOLO EL OPERADOR
--
-- Ningun cliente llama a esto. Para declararla tendria que teclear el RTN y el
-- codigo de sede del otro, que es informacion confidencial y no es suya.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION plataforma.crear_enlace(
  p_sucursal_a_id bigint,
  p_sucursal_b_id bigint,
  p_creado_por    text,
  p_nota          text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_empresa_a bigint;
  v_empresa_b bigint;
  v_enlace    bigint;
BEGIN
  SELECT empresa_id INTO v_empresa_a FROM core.sucursal WHERE sucursal_id = p_sucursal_a_id;
  SELECT empresa_id INTO v_empresa_b FROM core.sucursal WHERE sucursal_id = p_sucursal_b_id;

  IF v_empresa_a IS NULL OR v_empresa_b IS NULL THEN
    RAISE EXCEPTION 'Alguna de las dos sucursales no existe';
  END IF;
  IF v_empresa_a = v_empresa_b THEN
    RAISE EXCEPTION
      'Las dos sedes son de la misma empresa. Entre sedes propias se comparte '
      'todo y no hace falta enlace: eso no es un problema que resolver, es una '
      'sola empresa';
  END IF;

  INSERT INTO plataforma.enlace (
    empresa_a_id, sucursal_a_id, empresa_b_id, sucursal_b_id, creado_por, nota
  ) VALUES (
    v_empresa_a, p_sucursal_a_id, v_empresa_b, p_sucursal_b_id, p_creado_por, p_nota
  )
  RETURNING enlace_id INTO v_enlace;

  RETURN v_enlace;
END $$;

COMMENT ON FUNCTION plataforma.crear_enlace IS
  'La crea el operador con una conexion privilegiada. Cada pareja de sedes es '
  'una operacion manual suya: con un cliente es lo mismo que ya hace con '
  'crear_empresa, y con veinte se vuelve trabajo repetitivo (H-89).';

REVOKE ALL ON FUNCTION plataforma.crear_enlace(bigint, bigint, text, text) FROM PUBLIC;


-- ---------------------------------------------------------------------
-- Mis enlaces · lo unico que una empresa ve de sus rutas
--
-- Contesta SOLO tu lado: con quien podes trabajar y desde cual de TUS sedes.
-- La sucursal del otro no se devuelve nunca, y no hace falta: cuando mandas,
-- entregar() resuelve el destino.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.mis_enlaces(p_empresa_id bigint DEFAULT NULL)
RETURNS TABLE (
  enlace_id              bigint,
  mi_sucursal_id         bigint,
  contraparte_empresa_id bigint,
  contraparte_nombre     text,
  vigente_desde          date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT e.enlace_id,
         CASE WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
              THEN e.sucursal_a_id ELSE e.sucursal_b_id END,
         CASE WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
              THEN e.empresa_b_id  ELSE e.empresa_a_id  END,
         (SELECT coalesce(o.nombre_comercial, o.nombre) FROM core.empresa o
           WHERE o.empresa_id = CASE
                 WHEN e.empresa_a_id = coalesce(p_empresa_id, core.empresa_actual())
                 THEN e.empresa_b_id ELSE e.empresa_a_id END),
         e.vigente_desde
  FROM plataforma.enlace e
  WHERE coalesce(p_empresa_id, core.empresa_actual()) IN (e.empresa_a_id, e.empresa_b_id)
    AND e.vigente_desde <= CURRENT_DATE
    AND (e.vigente_hasta IS NULL OR e.vigente_hasta > CURRENT_DATE)
  ORDER BY 4
$$;

COMMENT ON FUNCTION core.mis_enlaces IS
  'El nombre comercial de la contraparte SI se muestra: las dos empresas ya saben '
  'que trabajan juntas, el operador creo la ruta porque lo acordaron. Lo que no '
  'se devuelve nunca es la sucursal del otro.';

GRANT EXECUTE ON FUNCTION core.mis_enlaces TO lis_app;


-- ---------------------------------------------------------------------
-- Entregar · EL UNICO PUNTO DONDE UN DATO CRUZA DE EMPRESA
--
-- Escribe DOS filas: la mia como 'enviado', la suya como 'recibido'. Las dos
-- llevan el mismo folio, que es un uuid y no el mensaje_id: si viajara el
-- numero de secuencia, el mensaje 4821 le contaria al otro cuantos mandas.
--
-- Un mensaje NO SE ACEPTA, SE RECIBE. La aceptacion se mudo una sola vez a la
-- relacion: una boleta que llega es trabajo, no una propuesta.
--
-- Sin enlace vigente NO SALE. Falla en el origen, cerca de quien se equivoco,
-- en vez de salir y caer en una bandeja del otro lado.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION core.entregar(
  p_empresa_id       bigint,
  p_enlace_id        bigint,
  p_tipo             core.tipo_mensaje,
  p_contenido        jsonb,
  p_usuario_id       bigint,
  p_responde_a_folio uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  e            plataforma.enlace%ROWTYPE;
  v_mi_suc     bigint;
  v_su_empresa bigint;
  v_su_suc     bigint;
  v_folio      uuid := gen_random_uuid();
BEGIN
  IF NOT core.usuario_puede('derivacion.solicitar', p_usuario_id) THEN
    RAISE EXCEPTION 'El usuario no tiene el permiso derivacion.solicitar'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO e FROM plataforma.enlace
   WHERE enlace_id = p_enlace_id
     AND vigente_desde <= CURRENT_DATE
     AND (vigente_hasta IS NULL OR vigente_hasta > CURRENT_DATE);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay ninguna ruta vigente con ese enlace: el mensaje no sale';
  END IF;

  IF p_empresa_id = e.empresa_a_id THEN
    v_mi_suc := e.sucursal_a_id; v_su_empresa := e.empresa_b_id; v_su_suc := e.sucursal_b_id;
  ELSIF p_empresa_id = e.empresa_b_id THEN
    v_mi_suc := e.sucursal_b_id; v_su_empresa := e.empresa_a_id; v_su_suc := e.sucursal_a_id;
  ELSE
    RAISE EXCEPTION 'Esa ruta no es de esta empresa';
  END IF;

  -- Mi fila: lo que mande.
  INSERT INTO core.mensaje (
    empresa_id, enlace_id, sucursal_id, direccion, tipo,
    folio, responde_a_folio, contenido, estado, entregado_en
  ) VALUES (
    p_empresa_id, p_enlace_id, v_mi_suc, 'enviado', p_tipo,
    v_folio, p_responde_a_folio, p_contenido, 'entregado', now()
  );

  -- Su fila: lo que le llego. Mismo folio, su empresa, SU ventanilla.
  INSERT INTO core.mensaje (
    empresa_id, enlace_id, sucursal_id, direccion, tipo,
    folio, responde_a_folio, contenido, estado
  ) VALUES (
    v_su_empresa, p_enlace_id, v_su_suc, 'recibido', p_tipo,
    v_folio, p_responde_a_folio, p_contenido, 'recibido'
  );

  RETURN v_folio;
END $$;

COMMENT ON FUNCTION core.entregar IS
  'El unico punto del sistema donde un dato pasa de una empresa a otra. Antes eso '
  'era una politica de RLS, que cualquier consulta disparaba; ahora es codigo que '
  'se lee y se prueba. Si alguna vez hay un segundo punto, algo se rompio.';

REVOKE ALL ON FUNCTION core.entregar(bigint, bigint, core.tipo_mensaje, jsonb, bigint, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.entregar TO lis_app;
