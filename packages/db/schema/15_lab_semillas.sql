-- =====================================================================
-- ProLisSaas · 15 · Semillas del laboratorio
--
-- El catalogo de hematologia sembrado con los 24 parametros REALES que
-- manda el Hemax 53, tomados del mensaje guardado en ProLab/prueba.txt.
--
-- ---------------------------------------------------------------------
-- ADVERTENCIA SOBRE LOS RANGOS DE REFERENCIA
--
-- Los rangos de abajo son valores de adulto de uso general, puestos para
-- que el sistema arranque con algo coherente. NO son los rangos del
-- laboratorio. Antes de usar esto con pacientes reales, el bioquimico
-- tiene que revisarlos y ajustarlos, porque dependen de:
--   · el metodo y el reactivo del equipo,
--   · la poblacion que atiende el laboratorio,
--   · y la altitud: en Tegucigalpa, a unos 1000 m, la hemoglobina y el
--     hematocrito de referencia son mas altos que a nivel del mar.
--
-- Que estos rangos vivan en una tabla y no en el codigo es justamente
-- para que ese ajuste sea una tarde de trabajo del bioquimico y no una
-- migracion.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Permisos que aporta este modulo al catalogo del producto
-- ---------------------------------------------------------------------
-- El modulo es dueno de sus permisos, igual que de sus tablas. Cuando
-- llegue imagenologia traera los suyos y no tocara estos.

INSERT INTO plataforma.permiso (permiso_id, modulo_id, descripcion) VALUES
  ('catalogo.ver',           'lab_clinico', 'Consultar pruebas, analitos y precios'),
  ('catalogo.administrar',   'lab_clinico', 'Crear pruebas y analitos, cambiar precios y rangos'),
  ('orden.ver',              'lab_clinico', 'Consultar ordenes de laboratorio'),
  ('orden.crear',            'lab_clinico', 'Crear una orden y elegir examenes'),
  ('orden.anular',           'lab_clinico', 'Anular una orden con motivo'),
  ('muestra.tomar',          'lab_clinico', 'Registrar la toma e imprimir la etiqueta'),
  ('muestra.recibir',        'lab_clinico', 'Recibir la muestra en el laboratorio'),
  ('muestra.rechazar',       'lab_clinico', 'Rechazar una muestra con motivo'),
  ('resultado.ver',          'lab_clinico', 'Consultar resultados'),
  ('resultado.capturar',     'lab_clinico', 'Digitar resultados a mano'),
  ('resultado.validar',      'lab_clinico', 'Aprobar un resultado para que salga en el informe'),
  ('resultado.corregir',     'lab_clinico', 'Emitir una correccion de un resultado ya validado'),
  ('valor_critico.registrar','lab_clinico', 'Registrar a quien se aviso de un valor critico'),
  ('equipo.administrar',     'lab_clinico', 'Configurar analizadores y su mapeo de codigos')
ON CONFLICT (permiso_id) DO NOTHING;


CREATE OR REPLACE FUNCTION lab.sembrar_hematologia(
  p_empresa_id  bigint,
  p_sucursal_id bigint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_area_hema  bigint;
  v_area_quim  bigint;
  v_edta       bigint;
  v_suero      bigint;
  v_prueba_hem bigint;
  v_prueba_glu bigint;
  v_equipo     bigint;
  v_analito    bigint;
  v_orden      smallint := 0;
  r            record;
BEGIN
  -- ---------------- areas ----------------
  INSERT INTO lab.area (empresa_id, codigo, nombre, orden_presentacion)
  VALUES (p_empresa_id, 'HEMA', 'Hematologia', 1) RETURNING area_id INTO v_area_hema;

  INSERT INTO lab.area (empresa_id, codigo, nombre, orden_presentacion)
  VALUES (p_empresa_id, 'QUIM', 'Quimica clinica', 2) RETURNING area_id INTO v_area_quim;

  -- ---------------- tipos de muestra ----------------
  INSERT INTO lab.tipo_muestra (empresa_id, codigo, nombre, color_tapon,
                                anticoagulante, volumen_min_ml, estable_horas)
  VALUES (p_empresa_id, 'EDTA', 'Sangre total con EDTA', 'Lavanda', 'EDTA K2', 2.0, 8)
  RETURNING tipo_muestra_id INTO v_edta;

  INSERT INTO lab.tipo_muestra (empresa_id, codigo, nombre, color_tapon,
                                anticoagulante, volumen_min_ml, estable_horas)
  VALUES (p_empresa_id, 'SUERO', 'Suero', 'Rojo', NULL, 3.0, 48)
  RETURNING tipo_muestra_id INTO v_suero;

  -- ---------------- analitos ----------------
  -- Los 24 parametros de reporte del Hemax 53, en el orden en que los manda.
  FOR r IN
    SELECT * FROM (VALUES
      ('WBC',    'Leucocitos',                          '10^3/uL', 2),
      ('LYM%',   'Linfocitos',                          '%',       1),
      ('MON%',   'Monocitos',                           '%',       1),
      ('NEU%',   'Neutrofilos',                         '%',       1),
      ('EOS%',   'Eosinofilos',                         '%',       1),
      ('BASO%',  'Basofilos',                           '%',       1),
      ('LYM#',   'Linfocitos absolutos',                '10^3/uL', 2),
      ('MON#',   'Monocitos absolutos',                 '10^3/uL', 2),
      ('NEU#',   'Neutrofilos absolutos',               '10^3/uL', 2),
      ('EOS#',   'Eosinofilos absolutos',               '10^3/uL', 2),
      ('BASO#',  'Basofilos absolutos',                 '10^3/uL', 2),
      ('RBC',    'Eritrocitos',                         '10^6/uL', 2),
      ('HGB',    'Hemoglobina',                         'g/dL',    1),
      ('HCT',    'Hematocrito',                         '%',       1),
      ('MCV',    'Volumen corpuscular medio',           'fL',      1),
      ('MCH',    'Hemoglobina corpuscular media',       'pg',      1),
      ('MCHC',   'Concentracion de hemoglobina C.M.',   'g/dL',    1),
      ('RDW_CV', 'Amplitud de distribucion eritrocitaria (CV)', '%',  1),
      ('RDW_SD', 'Amplitud de distribucion eritrocitaria (SD)', 'fL', 1),
      ('PLT',    'Plaquetas',                           '10^3/uL', 0),
      ('MPV',    'Volumen plaquetario medio',           'fL',      1),
      ('PDW',    'Amplitud de distribucion plaquetaria','fL',      1),
      ('PCT',    'Plaquetocrito',                       '%',       2),
      ('P_LCR',  'Ratio de plaquetas grandes',          '%',       1)
    ) AS t(codigo, nombre, unidad, decimales)
  LOOP
    INSERT INTO lab.analito (empresa_id, area_id, codigo, nombre, unidad, decimales)
    VALUES (p_empresa_id, v_area_hema, r.codigo, r.nombre, r.unidad, r.decimales);
  END LOOP;

  INSERT INTO lab.analito (empresa_id, area_id, codigo, nombre, unidad, decimales)
  VALUES (p_empresa_id, v_area_quim, 'GLU', 'Glucosa', 'mg/dL', 0);

  -- ---------------- pruebas ----------------
  -- Un hemograma: se cobra UNA vez y produce 24 resultados.
  INSERT INTO lab.prueba (empresa_id, area_id, tipo_muestra_id, codigo, nombre,
                          metodo, horas_proceso)
  VALUES (p_empresa_id, v_area_hema, v_edta, 'HEM01', 'Hemograma completo',
          'Impedancia y citometria de flujo', 4)
  RETURNING prueba_id INTO v_prueba_hem;

  INSERT INTO lab.prueba_analito (prueba_id, analito_id, empresa_id, orden_presentacion)
  SELECT v_prueba_hem, a.analito_id, p_empresa_id, a.analito_id
  FROM lab.analito a
  WHERE a.empresa_id = p_empresa_id AND a.area_id = v_area_hema;

  -- Una glucosa: se cobra una vez y produce 1 resultado. El mismo modelo
  -- sirve para las dos; por eso no hacen falta dos disenos.
  INSERT INTO lab.prueba (empresa_id, area_id, tipo_muestra_id, codigo, nombre,
                          metodo, horas_proceso, requiere_ayuno, indicaciones)
  VALUES (p_empresa_id, v_area_quim, v_suero, 'GLU01', 'Glucosa en ayunas',
          'Colorimetrico enzimatico', 4, true, 'Ayuno de 8 a 12 horas')
  RETURNING prueba_id INTO v_prueba_glu;

  INSERT INTO lab.prueba_analito (prueba_id, analito_id, empresa_id)
  SELECT v_prueba_glu, analito_id, p_empresa_id
  FROM lab.analito WHERE empresa_id = p_empresa_id AND codigo = 'GLU';

  -- ---------------- precios de lista ----------------
  INSERT INTO lab.precio_prueba (empresa_id, prueba_id, precio) VALUES
    (p_empresa_id, v_prueba_hem, 350.00),
    (p_empresa_id, v_prueba_glu, 120.00);

  -- ---------------- rangos de referencia ----------------
  -- Ver la advertencia del encabezado antes de usar esto con pacientes.
  FOR r IN
    SELECT * FROM (VALUES
      -- codigo,  sexo,        min,   max,  critico_min, critico_max
      ('WBC',    'ambos',      4.5,  11.0,   1.5,   30.0),
      ('NEU%',   'ambos',     40.0,  75.0,  NULL,   NULL),
      ('LYM%',   'ambos',     20.0,  45.0,  NULL,   NULL),
      ('MON%',   'ambos',      2.0,  10.0,  NULL,   NULL),
      ('EOS%',   'ambos',      1.0,   6.0,  NULL,   NULL),
      ('BASO%',  'ambos',      0.0,   2.0,  NULL,   NULL),
      ('NEU#',   'ambos',      1.8,   7.7,   0.5,   NULL),
      ('LYM#',   'ambos',      1.0,   4.8,  NULL,   NULL),
      ('MON#',   'ambos',      0.1,   0.9,  NULL,   NULL),
      ('EOS#',   'ambos',      0.0,   0.5,  NULL,   NULL),
      ('BASO#',  'ambos',      0.0,   0.2,  NULL,   NULL),
      ('RBC',    'masculino',  4.5,   5.9,  NULL,   NULL),
      ('RBC',    'femenino',   4.0,   5.2,  NULL,   NULL),
      ('HGB',    'masculino', 13.5,  17.5,   7.0,   20.0),
      ('HGB',    'femenino',  12.0,  15.5,   7.0,   20.0),
      ('HCT',    'masculino', 41.0,  53.0,  20.0,   60.0),
      ('HCT',    'femenino',  36.0,  46.0,  20.0,   60.0),
      ('MCV',    'ambos',     80.0, 100.0,  NULL,   NULL),
      ('MCH',    'ambos',     27.0,  33.0,  NULL,   NULL),
      ('MCHC',   'ambos',     32.0,  36.0,  NULL,   NULL),
      ('RDW_CV', 'ambos',     11.5,  14.5,  NULL,   NULL),
      ('RDW_SD', 'ambos',     37.0,  54.0,  NULL,   NULL),
      ('PLT',    'ambos',    150.0, 450.0,  20.0, 1000.0),
      ('MPV',    'ambos',      7.5,  11.5,  NULL,   NULL),
      ('PDW',    'ambos',      9.0,  17.0,  NULL,   NULL),
      ('PCT',    'ambos',      0.19,  0.39, NULL,   NULL),
      ('P_LCR',  'ambos',     13.0,  43.0,  NULL,   NULL),
      ('GLU',    'ambos',     70.0, 100.0,  40.0,  400.0)
    ) AS t(codigo, sexo, vmin, vmax, cmin, cmax)
  LOOP
    SELECT analito_id INTO v_analito
    FROM lab.analito WHERE empresa_id = p_empresa_id AND codigo = r.codigo;

    INSERT INTO lab.rango_referencia (
      empresa_id, analito_id, sexo, edad_min_dias, edad_max_dias,
      valor_min, valor_max, critico_min, critico_max
    ) VALUES (
      p_empresa_id, v_analito, r.sexo::lab.sexo_rango, 6570, 54750,  -- 18 anios en adelante
      r.vmin, r.vmax, r.cmin, r.cmax
    );
  END LOOP;

  -- ---------------- el equipo ----------------
  INSERT INTO integra.equipo (
    empresa_id, sucursal_id, area_id, codigo, nombre, marca, modelo,
    protocolo, identificador, bidireccional
  ) VALUES (
    p_empresa_id, p_sucursal_id, v_area_hema, 'HEMAX53', 'Hemax 53',
    'B&E Bio-Technology', 'Hemax 53', 'hl7_v2', 'EQUIPO_HEMA', false
  )
  RETURNING equipo_id INTO v_equipo;

  -- El equipo manda exactamente los mismos codigos que usamos como codigo de
  -- analito, asi que el mapeo es uno a uno. Con el segundo analizador dejara
  -- de serlo, y por eso esta tabla existe desde ahora.
  INSERT INTO integra.mapeo_codigo (empresa_id, equipo_id, codigo_equipo, analito_id)
  SELECT p_empresa_id, v_equipo, a.codigo, a.analito_id
  FROM lab.analito a
  WHERE a.empresa_id = p_empresa_id AND a.area_id = v_area_hema;

END $$;

COMMENT ON FUNCTION lab.sembrar_hematologia IS
  'Catalogo inicial de un laboratorio con un Hemax 53. Los 24 analitos salen del '
  'mensaje real guardado en ProLab/prueba.txt, que coincide con los 24 parametros '
  'de reporte que declara el fabricante.';
