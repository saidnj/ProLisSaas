-- =====================================================================
-- ProLisSaas · 98 · Pruebas de la rama de laboratorio
--
-- Recorre el flujo completo con el mensaje real del Hemax 53: admision,
-- toma, recepcion, llegada del mensaje, resultados, validacion, valor
-- critico y correccion.
-- =====================================================================

\set ON_ERROR_STOP off

-- ---------------------------------------------------------------------
-- Montaje
-- ---------------------------------------------------------------------
SELECT core.crear_empresa('Laboratorio Familiar Ochoa','0801-9999','Sede Central','LFO') AS emp \gset
SELECT sucursal_id AS suc FROM core.sucursal WHERE empresa_id = :emp \gset
SELECT lab.sembrar_hematologia(:emp, :suc);

INSERT INTO core.empleado (empresa_id, nombres, apellidos, numero_colegiacion)
VALUES (:emp,'Said','Hoch','BQ-1234') RETURNING empleado_id \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :emp, :empleado_id, rol_id, 'said', '$argon2id$marcador'
FROM core.rol WHERE empresa_id = :emp AND nombre='Administrador'
RETURNING usuario_id AS usr \gset

SELECT convenio_id AS conv FROM core.convenio WHERE empresa_id = :emp AND es_predeterminado \gset

-- Paciente masculino adulto (el del mensaje de prueba.txt)
INSERT INTO core.paciente (empresa_id, expediente, nombres, apellidos,
                           tipo_documento, documento, fecha_nacimiento, sexo,
                           creado_por_usuario_id)
VALUES (:emp, core.siguiente_correlativo(:emp,NULL,'expediente'),
        'SAID GABRIEL','HOCH URBINA','identidad','1807200400844','2002-11-15','masculino', :usr)
RETURNING paciente_id AS pac \gset

INSERT INTO core.episodio (empresa_id, sucursal_id, paciente_id, convenio_id,
                           numero, creado_por_usuario_id)
VALUES (:emp, :suc, :pac, :conv, core.siguiente_correlativo(:emp,:suc,'episodio'), :usr)
RETURNING episodio_id AS epi \gset

INSERT INTO lab.orden (empresa_id, episodio_id, numero, creado_por_usuario_id)
VALUES (:emp, :epi, core.siguiente_correlativo(:emp,:suc,'orden'), :usr)
RETURNING orden_id AS ord \gset

-- El tubo, con su codigo de barras: la llave que unira el mensaje con la orden.
INSERT INTO lab.muestra (empresa_id, orden_id, tipo_muestra_id, codigo_barra,
                         estado, tomada_en, tomada_por_usuario_id)
SELECT :emp, :ord, tipo_muestra_id, 'T-202', 'tomada', now(), :usr
FROM lab.tipo_muestra WHERE empresa_id = :emp AND codigo = 'EDTA'
RETURNING muestra_id AS mue \gset

-- El examen pedido, con el precio congelado que resuelve la funcion.
INSERT INTO lab.orden_prueba (empresa_id, orden_id, prueba_id, muestra_id,
                              convenio_id, precio_lista, precio)
SELECT :emp, :ord, p.prueba_id, :mue, :conv,
       lab.precio_para(:emp, p.prueba_id, :suc, NULL),
       lab.precio_para(:emp, p.prueba_id, :suc, :conv)
FROM lab.prueba p WHERE p.empresa_id = :emp AND p.codigo = 'HEM01'
RETURNING orden_prueba_id AS opr \gset


\echo ''
\echo '=== 1 · Un hemograma se cobra una vez y produce 24 analitos ======='
SELECT p.nombre AS prueba,
       (SELECT count(*) FROM lab.prueba_analito pa WHERE pa.prueba_id = p.prueba_id) AS analitos,
       (SELECT precio FROM lab.orden_prueba WHERE orden_prueba_id = :opr) AS se_cobra
FROM lab.prueba p WHERE p.prueba_id = (SELECT prueba_id FROM lab.orden_prueba WHERE orden_prueba_id = :opr);


\echo ''
\echo '=== 2 · Llega el mensaje del equipo, crudo, antes de interpretarlo ='
INSERT INTO integra.mensaje_crudo (
  empresa_id, sucursal_id, equipo_id, protocolo, contenido, contenido_hash,
  identificador_equipo, identificador_muestra, recibido_en
)
SELECT :emp, :suc, e.equipo_id, 'hl7_v2',
       'MSH|^~\&|EQUIPO_HEMA|Lab_Familiar_Ochoa|65161|LIS_SISTEMA|RECEP|202604111650||ORU^R01|MSG98765|P|2.3'
       || E'\r' || 'OBR|1||T-202|Hemograma|||202604111645' || E'\r' || '(24 OBX)',
       md5('MSG98765'), 'EQUIPO_HEMA', 'T-202', now()
FROM integra.equipo e WHERE e.empresa_id = :emp AND e.codigo = 'HEMAX53'
RETURNING mensaje_crudo_id AS msg \gset
SELECT mensaje_crudo_id, estado, identificador_muestra FROM integra.mensaje_crudo WHERE mensaje_crudo_id = :msg;


\echo ''
\echo '=== 3 · Los 24 valores del mensaje, resueltos por el mapeo ========'
DO $$
DECLARE
  v_emp bigint; v_opr bigint; v_mue bigint; v_msg bigint; v_eq bigint;
  r record; v_analito bigint;
BEGIN
  SELECT empresa_id INTO v_emp FROM core.empresa WHERE nombre LIKE 'Laboratorio Familiar%';
  SELECT orden_prueba_id INTO v_opr FROM lab.orden_prueba WHERE empresa_id = v_emp;
  SELECT muestra_id INTO v_mue FROM lab.muestra WHERE empresa_id = v_emp;
  SELECT mensaje_crudo_id INTO v_msg FROM integra.mensaje_crudo WHERE empresa_id = v_emp;
  SELECT equipo_id INTO v_eq FROM integra.equipo WHERE empresa_id = v_emp;

  FOR r IN SELECT * FROM (VALUES
    ('WBC',8.67),('LYM%',32.33),('MON%',6.56),('NEU%',60.03),('EOS%',0.96),
    ('BASO%',0.12),('LYM#',2.80),('MON#',0.57),('NEU#',5.21),('EOS#',0.08),
    ('BASO#',0.01),('RBC',4.89),('HGB',14.6),('HCT',44.7),('MCV',91.6),
    ('MCH',29.8),('MCHC',32.6),('RDW_CV',13.5),('RDW_SD',39.7),('PLT',293),
    ('MPV',6.9),('PDW',17.0),('PCT',0.20),('P_LCR',17.27)
  ) AS t(codigo, valor)
  LOOP
    SELECT m.analito_id INTO v_analito
    FROM integra.mapeo_codigo m
    WHERE m.equipo_id = v_eq AND m.codigo_equipo = r.codigo;

    PERFORM lab.registrar_resultado(
      v_opr, v_analito, r.valor::numeric, NULL, v_mue, v_eq, v_msg, now(), NULL);
  END LOOP;

  UPDATE integra.mensaje_crudo
     SET estado='procesado', procesado_en=now(), intentos=1
   WHERE mensaje_crudo_id = v_msg;
END $$;

SELECT count(*) AS resultados_creados FROM lab.resultado WHERE orden_prueba_id = :opr;


\echo ''
\echo '=== 4 · El rango que se aplico es el del LABORATORIO =============='
\echo '    (el mensaje traia 13.5-18.0 de fabrica; el laboratorio usa el suyo)'
SELECT a.codigo, r.valor_numerico AS valor, r.unidad,
       r.rango_min || ' - ' || r.rango_max AS rango_aplicado, r.bandera
FROM lab.resultado r JOIN lab.analito a USING (analito_id)
WHERE r.orden_prueba_id = :opr AND a.codigo IN ('HGB','HCT','MPV','PDW','WBC')
ORDER BY a.codigo;


\echo ''
\echo '=== 5 · EL PUNTO DEL DISENO ======================================='
\echo '    La MISMA hemoglobina de 13.0 en un paciente hombre y en una mujer'
INSERT INTO core.paciente (empresa_id, expediente, nombres, apellidos,
                           fecha_nacimiento, sexo, creado_por_usuario_id)
VALUES (:emp, core.siguiente_correlativo(:emp,NULL,'expediente'),
        'MARIA','LOPEZ','1990-05-20','femenino', :usr)
RETURNING paciente_id AS pac2 \gset
INSERT INTO core.episodio (empresa_id, sucursal_id, paciente_id, convenio_id, numero, creado_por_usuario_id)
VALUES (:emp,:suc,:pac2,:conv, core.siguiente_correlativo(:emp,:suc,'episodio'), :usr)
RETURNING episodio_id AS epi2 \gset
INSERT INTO lab.orden (empresa_id, episodio_id, numero, creado_por_usuario_id)
VALUES (:emp,:epi2, core.siguiente_correlativo(:emp,:suc,'orden'), :usr)
RETURNING orden_id AS ord2 \gset
INSERT INTO lab.orden_prueba (empresa_id, orden_id, prueba_id, convenio_id, precio_lista, precio)
SELECT :emp,:ord2,prueba_id,:conv,350,350 FROM lab.prueba WHERE empresa_id=:emp AND codigo='HEM01'
RETURNING orden_prueba_id AS opr2 \gset

SELECT lab.registrar_resultado(:opr2, analito_id, 13.0, NULL, NULL, NULL, NULL, now(), :usr) AS r_mujer
FROM lab.analito WHERE empresa_id=:emp AND codigo='HGB' \gset

-- El mismo valor en el paciente hombre, en un episodio nuevo.
INSERT INTO core.episodio (empresa_id, sucursal_id, paciente_id, convenio_id, numero, creado_por_usuario_id)
VALUES (:emp,:suc,:pac,:conv, core.siguiente_correlativo(:emp,:suc,'episodio'), :usr)
RETURNING episodio_id AS epi3 \gset
INSERT INTO lab.orden (empresa_id, episodio_id, numero, creado_por_usuario_id)
VALUES (:emp,:epi3, core.siguiente_correlativo(:emp,:suc,'orden'), :usr)
RETURNING orden_id AS ord3 \gset
INSERT INTO lab.orden_prueba (empresa_id, orden_id, prueba_id, convenio_id, precio_lista, precio)
SELECT :emp,:ord3,prueba_id,:conv,350,350 FROM lab.prueba WHERE empresa_id=:emp AND codigo='HEM01'
RETURNING orden_prueba_id AS opr3 \gset
SELECT lab.registrar_resultado(:opr3, analito_id, 13.0, NULL, NULL, NULL, NULL, now(), :usr) AS r_hombre
FROM lab.analito WHERE empresa_id=:emp AND codigo='HGB' \gset

SELECT 'hombre' AS paciente, valor_numerico, rango_min, rango_max, bandera
FROM lab.resultado WHERE resultado_id = :r_hombre
UNION ALL
SELECT 'mujer', valor_numerico, rango_min, rango_max, bandera
FROM lab.resultado WHERE resultado_id = :r_mujer;
\echo '    -> mismo valor, distinto rango, distinta bandera. Con un solo rango'
\echo '       para los dos sexos, una de las dos lecturas seria falsa.'


\echo ''
\echo '=== 6 · Un valor critico no se valida sin registrar el aviso ======'
SELECT lab.registrar_resultado(:opr2, analito_id, 5.2, NULL, NULL, NULL, NULL, now(), :usr) AS r_crit
FROM lab.analito WHERE empresa_id=:emp AND codigo='PLT' \gset
SELECT bandera AS bandera_plaquetas FROM lab.resultado WHERE resultado_id = :r_crit;
\echo '    intento validar sin aviso (debe fallar):'
SELECT lab.validar_resultado(:r_crit, :usr);
\echo '    registro el aviso y vuelvo a intentar:'
INSERT INTO lab.aviso_valor_critico (empresa_id, resultado_id, avisado_a, cargo, medio,
                                     avisado_por_usuario_id)
VALUES (:emp, :r_crit, 'Dra. Fernandez', 'Medico tratante', 'telefono', :usr);
SELECT lab.validar_resultado(:r_crit, :usr);
SELECT estado, validado_en IS NOT NULL AS quedo_firmado FROM lab.resultado WHERE resultado_id = :r_crit;


\echo ''
\echo '=== 7 · Corregir crea una version; el valor viejo no cambia ======='
SELECT resultado_id AS r_hgb FROM lab.resultado
WHERE orden_prueba_id = :opr
  AND analito_id = (SELECT analito_id FROM lab.analito WHERE empresa_id=:emp AND codigo='HGB') \gset
SELECT lab.validar_resultado(:r_hgb, :usr);
SELECT lab.corregir_resultado(:r_hgb, 11.2, NULL, 'Se reproceso la muestra: interferencia por lipemia', :usr) AS nuevo \gset

SELECT resultado_id, valor_numerico, bandera, estado, vigente,
       corrige_a_resultado_id AS corrige_a, motivo_correccion
FROM lab.resultado
WHERE resultado_id IN (:r_hgb, :nuevo) ORDER BY resultado_id;
\echo '    -> hay dos filas. La original conserva su valor para siempre.'


\echo ''
\echo '=== 8 · La consulta que el modelo A no podia responder ============'
\echo '    "todas las hemoglobinas fuera de rango"'
SELECT pa.nombre_completo, r.valor_numerico AS hgb, r.rango_min, r.rango_max, r.bandera
FROM lab.resultado r
JOIN lab.analito   a  USING (analito_id)
JOIN lab.orden_prueba op ON op.orden_prueba_id = r.orden_prueba_id
JOIN lab.orden     o  ON o.orden_id    = op.orden_id
JOIN core.episodio e  ON e.episodio_id = o.episodio_id
JOIN core.paciente pa ON pa.paciente_id = e.paciente_id
WHERE a.codigo = 'HGB'
  AND r.bandera <> 'normal'
  AND r.vigente;


\echo ''
\echo '=== 9 · RLS tambien en lab e integra =============================='
\echo '    esperado: cero filas'
SELECT n.nspname, c.relname AS tabla_sin_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'empresa_id'
WHERE n.nspname IN ('core','lab','integra') AND c.relkind='r'
  AND NOT (c.relrowsecurity AND c.relforcerowsecurity);

\echo '    y una empresa distinta no ve nada de este laboratorio:'
SELECT core.crear_empresa('Otro Laboratorio','0801-0000','Unica','OTR') AS otra \gset
-- Desde que las politicas llaman a core.sesion_vigente(), el contexto necesita
-- las DOS variables. Poner solo la empresa era un atajo que el sistema real
-- nunca usa: conSesion() siempre pone las dos. Se saca el usuario ANTES de
-- SET ROLE, como postgres, porque despues RLS ya no dejaria leerlo.
-- crear_empresa() deja la empresa con roles y permisos pero SIN usuarios
-- (H-2). Desde que las politicas comprueban core.sesion_vigente(), eso ya no
-- es solo una nota: una empresa sin usuarios NO PUEDE ABRIR SESION. La
-- asercion es mas fuerte que la de antes -- no es que no vea nada, es que no
-- llega a mirar.
\echo '    esperado: ERROR 28000 -- esa empresa no tiene usuarios (H-2)'
SET lis.usuario_id = '';
SET ROLE lis_app;
SET lis.empresa_id = :'otra';
SELECT count(*) AS resultados_que_ve_la_otra_empresa FROM lab.resultado;
RESET ROLE;
RESET lis.usuario_id;
