-- =====================================================================
-- ProLisSaas · 96 · Pruebas de permisos
--
-- La pregunta: "¿donde se define que puede hacer cada rol, y quien lo
-- hace cumplir?"
-- =====================================================================

\set ON_ERROR_STOP off

SELECT core.crear_empresa('Laboratorio Familiar Ochoa','0801-9999','Sede Central','LFO') AS emp \gset
SELECT sucursal_id AS suc FROM core.sucursal WHERE empresa_id = :emp \gset
SELECT lab.sembrar_hematologia(:emp, :suc);

-- Tres empleados de verdad: la bioquimica tiene colegiacion, los otros no.
INSERT INTO core.empleado (empresa_id, nombres, apellidos, cargo, numero_colegiacion)
VALUES (:emp,'Ana','Fernandez','Bioquimica','BQ-1234') RETURNING empleado_id AS e_bio \gset
INSERT INTO core.empleado (empresa_id, nombres, apellidos, cargo)
VALUES (:emp,'Rosa','Mejia','Recepcionista') RETURNING empleado_id AS e_rec \gset
INSERT INTO core.empleado (empresa_id, nombres, apellidos, cargo)
VALUES (:emp,'Luis','Cruz','Analista') RETURNING empleado_id AS e_ana \gset

INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :emp, :e_bio, rol_id, 'ana', '$argon2id$x' FROM core.rol
WHERE empresa_id = :emp AND nombre = 'Bioquimico' RETURNING usuario_id AS u_bio \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :emp, :e_rec, rol_id, 'rosa', '$argon2id$x' FROM core.rol
WHERE empresa_id = :emp AND nombre = 'Recepcion' RETURNING usuario_id AS u_rec \gset
INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash)
SELECT :emp, :e_ana, rol_id, 'luis', '$argon2id$x' FROM core.rol
WHERE empresa_id = :emp AND nombre = 'Analista' RETURNING usuario_id AS u_ana \gset


\echo ''
\echo '=== 1 · La empresa nace con roles que YA tienen permisos =========='
\echo '    antes de este archivo, los tres operativos nacian en cero'
SELECT r.nombre AS rol, count(rp.permiso_id) AS permisos
FROM core.rol r LEFT JOIN core.rol_permiso rp USING (rol_id)
WHERE r.empresa_id = :emp GROUP BY r.nombre ORDER BY 2 DESC;


\echo ''
\echo '=== 2 · Quien puede hacer que, en concreto ======================='
SELECT p.permiso_id,
       max(CASE WHEN r.nombre='Recepcion'  THEN 'si' ELSE '' END) AS recepcion,
       max(CASE WHEN r.nombre='Analista'   THEN 'si' ELSE '' END) AS analista,
       max(CASE WHEN r.nombre='Bioquimico' THEN 'si' ELSE '' END) AS bioquimico
FROM core.rol_permiso rp
JOIN core.rol r USING (rol_id)
JOIN plataforma.permiso p USING (permiso_id)
WHERE r.empresa_id = :emp AND r.nombre <> 'Administrador'
  AND p.permiso_id IN ('paciente.crear','orden.crear','muestra.tomar',
                       'muestra.rechazar','resultado.capturar','resultado.validar',
                       'informe.emitir','informe.entregar','paciente.fusionar')
GROUP BY p.permiso_id ORDER BY p.permiso_id;
\echo '    -> paciente.fusionar no lo tiene ninguno: se otorga a mano.'


\echo ''
\echo '=== 3 · La comprobacion en la base, no solo en la pantalla ======='
SELECT core.usuario_puede('resultado.validar', :u_rec) AS recepcion_valida,
       core.usuario_puede('resultado.validar', :u_ana) AS analista_valida,
       core.usuario_puede('resultado.validar', :u_bio) AS bioquimica_valida;


-- Montaje minimo para llegar a un resultado.
SELECT convenio_id AS conv FROM core.convenio WHERE empresa_id=:emp AND es_predeterminado \gset
SELECT * FROM core.registrar_paciente(
  :emp,'SAID','HOCH','identidad','1807200400844',DATE '2004-11-15','masculino',
  NULL,NULL,NULL,:u_rec) \gset
INSERT INTO core.episodio (empresa_id, sucursal_id, paciente_id, convenio_id, numero, creado_por_usuario_id)
VALUES (:emp,:suc,:paciente_id,:conv, core.siguiente_correlativo(:emp,:suc,'episodio'), :u_rec)
RETURNING episodio_id AS epi \gset
INSERT INTO lab.orden (empresa_id, episodio_id, numero, creado_por_usuario_id)
VALUES (:emp,:epi, core.siguiente_correlativo(:emp,:suc,'orden'), :u_rec)
RETURNING orden_id AS ord \gset
INSERT INTO lab.orden_prueba (empresa_id, orden_id, prueba_id, convenio_id, precio_lista, precio)
SELECT :emp,:ord,prueba_id,:conv,350,350 FROM lab.prueba WHERE empresa_id=:emp AND codigo='HEM01'
RETURNING orden_prueba_id AS opr \gset
SELECT lab.registrar_resultado(:opr, analito_id, 14.6, NULL, NULL, NULL, NULL, now(), :u_ana) AS res
FROM lab.analito WHERE empresa_id=:emp AND codigo='HGB' \gset


\echo ''
\echo '=== 4 · El analista intenta validar ============================='
\echo '    esperado: ERROR insufficient_privilege'
SET ROLE lis_app; SET lis.empresa_id = :'emp'; SET lis.usuario_id = :'u_ana';
SELECT lab.validar_resultado(:res, :u_ana);
RESET ROLE;


\echo ''
\echo '=== 5 · La bioquimica valida ===================================='
SET ROLE lis_app; SET lis.empresa_id = :'emp'; SET lis.usuario_id = :'u_bio';
SELECT lab.validar_resultado(:res, :u_bio);
SELECT estado, validado_por_usuario_id FROM lab.resultado WHERE resultado_id = :res;
RESET ROLE;


\echo ''
\echo '=== 6 · Un permiso no convierte a nadie en bioquimico ==========='
\echo '    le doy a Rosa el rol de Bioquimico, pero no tiene colegiacion'
UPDATE core.usuario SET rol_id = (SELECT rol_id FROM core.rol WHERE empresa_id=:emp AND nombre='Bioquimico')
WHERE usuario_id = :u_rec;
SELECT lab.registrar_resultado(:opr, analito_id, 293, NULL, NULL, NULL, NULL, now(), :u_ana) AS res2
FROM lab.analito WHERE empresa_id=:emp AND codigo='PLT' \gset
SET ROLE lis_app; SET lis.empresa_id = :'emp'; SET lis.usuario_id = :'u_rec';
\echo '    esperado: ERROR sobre el numero de colegiacion'
SELECT lab.validar_resultado(:res2, :u_rec);
RESET ROLE;


\echo ''
\echo '=== 7 · Un usuario suspendido no puede nada ====================='
UPDATE core.usuario SET estado='suspendido' WHERE usuario_id = :u_bio;
SELECT core.usuario_puede('resultado.validar', :u_bio) AS bioquimica_suspendida_valida;


\echo ''
\echo '=== 8 · La matriz que pinta la pantalla de configuracion ========='
SELECT rol, count(*) FILTER (WHERE concedido) AS concedidos,
       count(*) AS total_del_catalogo
FROM core.v_rol_permiso WHERE empresa_id = :emp
GROUP BY rol ORDER BY 2 DESC;
