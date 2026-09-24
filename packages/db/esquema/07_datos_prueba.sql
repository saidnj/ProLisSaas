-- =====================================================================
-- ProLisSaas · 07 · Datos de prueba
--
-- Banco de pruebas para consultar permisos, aislamiento y licencia de
-- modulos. NO es parte del esquema: se carga aparte, cuando se quiere
-- algo con que jugar.
--
-- Deja tres empresas pensadas para que cada una pruebe algo distinto:
--
--   Laboratorio Ochoa      dos sedes, cinco roles, siete usuarios.
--                          El caso completo.
--   Clinica San Jose       otra empresa, para probar el aislamiento:
--                          nada de Ochoa se ve desde aqui.
--   Bioanalisis del Valle  tiene lab_clinico APAGADO. Sirve para ver
--                          como la licencia borra permisos sin tocar
--                          un solo rol_permiso.
--
-- Se puede correr sobre una base que ya tenga a Ochoa a medias: todo
-- lleva ON CONFLICT DO NOTHING o comprueba antes de insertar.
--
--   psql -d prolissaas -f 07_datos_prueba.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0 · El catalogo del producto, por si falta
-- ---------------------------------------------------------------------

INSERT INTO plataforma.modulo (modulo_id, nombre, descripcion) VALUES
  ('core',        'Nucleo',              'Pacientes, episodios, informes y entrega. No es opcional.'),
  ('lab_clinico', 'Laboratorio clinico', 'Ordenes, muestras, resultados y validacion.')
ON CONFLICT (modulo_id) DO NOTHING;

INSERT INTO plataforma.permiso (permiso_id, modulo_id, descripcion) VALUES
  ('paciente.ver','core','Consultar pacientes'),
  ('paciente.crear','core','Registrar un paciente nuevo'),
  ('paciente.editar','core','Modificar datos de un paciente'),
  ('paciente.fusionar','core','Fusionar dos expedientes duplicados'),
  ('episodio.ver','core','Consultar episodios'),
  ('episodio.crear','core','Abrir un episodio de admision'),
  ('episodio.anular','core','Anular un episodio con motivo'),
  ('convenio.ver','core','Consultar convenios y sus tarifas'),
  ('convenio.administrar','core','Crear y modificar convenios y listas de precios'),
  ('usuario.administrar','core','Crear usuarios, roles y permisos'),
  ('sucursal.administrar','core','Crear y configurar sucursales'),
  ('informe.emitir','core','Emitir la version de un informe'),
  ('informe.corregir','core','Emitir una version correctiva'),
  ('informe.entregar','core','Registrar la entrega de un informe'),
  ('derivacion.solicitar','core','Mandar datos de un paciente a otra empresa'),
  ('auditoria.ver','core','Consultar el rastro de auditoria'),
  ('catalogo.ver','lab_clinico','Consultar pruebas, analitos y precios'),
  ('catalogo.administrar','lab_clinico','Crear pruebas y analitos, cambiar precios y rangos'),
  ('orden.ver','lab_clinico','Consultar ordenes de laboratorio'),
  ('orden.crear','lab_clinico','Crear una orden y elegir examenes'),
  ('orden.anular','lab_clinico','Anular una orden con motivo'),
  ('muestra.tomar','lab_clinico','Registrar la toma e imprimir la etiqueta'),
  ('muestra.recibir','lab_clinico','Recibir la muestra en el laboratorio'),
  ('muestra.rechazar','lab_clinico','Rechazar una muestra con motivo'),
  ('resultado.ver','lab_clinico','Consultar resultados'),
  ('resultado.capturar','lab_clinico','Digitar resultados a mano'),
  ('resultado.validar','lab_clinico','Aprobar un resultado para que salga en el informe'),
  ('resultado.corregir','lab_clinico','Emitir una correccion de un resultado ya validado'),
  ('valor_critico.registrar','lab_clinico','Registrar a quien se aviso de un valor critico'),
  ('equipo.administrar','lab_clinico','Configurar analizadores y su mapeo de codigos')
ON CONFLICT (permiso_id) DO NOTHING;


-- ---------------------------------------------------------------------
-- 1 · Las tres empresas
-- ---------------------------------------------------------------------

-- uq_empresa_rtn es un indice PARCIAL (WHERE rtn IS NOT NULL), y ON CONFLICT
-- no puede inferirlo. Se comprueba antes, que ademas se lee mejor.
INSERT INTO core.empresa (nombre, nombre_comercial, rtn, estado, nivel_acceso)
SELECT x.nombre, x.comercial, x.rtn, x.estado::core.estado_empresa, 'completo'
FROM (VALUES
  ('Laboratorio Clinico Ochoa S. de R.L.', 'Laboratorio Ochoa',     '08019016543210', 'activa'),
  ('Clinica Medica San Jose S.A.',         'Clinica San Jose',      '05019014287395', 'activa'),
  ('Laboratorio Bioanalisis del Valle',    'Bioanalisis del Valle', '08019018765432', 'prueba')
) AS x(nombre, comercial, rtn, estado)
WHERE NOT EXISTS (SELECT 1 FROM core.empresa e WHERE e.rtn = x.rtn);


-- ---------------------------------------------------------------------
-- 2 · Las sucursales · Ochoa tiene DOS
-- ---------------------------------------------------------------------

INSERT INTO core.sucursal (empresa_id, nombre, codigo, direccion, telefono)
SELECT e.empresa_id, x.nombre, x.codigo, x.direccion, x.telefono
FROM core.empresa e
JOIN (VALUES
  ('08019016543210','Casa Matriz',    'CEN','Col. Palmira, 2a calle, Edificio Ochoa, Tegucigalpa','2232-4455'),
  ('08019016543210','Sucursal Norte', 'NOR','Blvd. Suyapa, frente a UNAH, Tegucigalpa',          '2235-9900'),
  ('05019014287395','Clinica Central','SJC','Barrio Guanacaste, 3a avenida, Tegucigalpa',        '2234-1100'),
  ('08019018765432','Unica',          'VAL','Barrio El Centro, Comayagua',                       '2772-3040')
) AS x(rtn,nombre,codigo,direccion,telefono) ON x.rtn = e.rtn
WHERE NOT EXISTS (
  SELECT 1 FROM core.sucursal s WHERE s.empresa_id = e.empresa_id AND s.codigo = x.codigo);


-- ---------------------------------------------------------------------
-- 3 · Los correlativos · cinco por sede (expediente solo una vez)
-- ---------------------------------------------------------------------

INSERT INTO core.correlativo (empresa_id, sucursal_id, tipo, prefijo, ancho)
SELECT s.empresa_id, NULL, 'expediente', 'EXP-', 6
FROM core.sucursal s
WHERE s.codigo IN ('CEN','SJC','VAL')
  AND NOT EXISTS (SELECT 1 FROM core.correlativo c
                  WHERE c.empresa_id = s.empresa_id AND c.tipo = 'expediente');

INSERT INTO core.correlativo (empresa_id, sucursal_id, tipo, prefijo, ancho)
SELECT s.empresa_id, s.sucursal_id, x.tipo::core.tipo_correlativo,
       s.codigo || x.sufijo, x.ancho
FROM core.sucursal s
CROSS JOIN (VALUES
  ('episodio','-',6), ('informe','I-',6), ('orden','O-',6), ('muestra','M-',8)
) AS x(tipo,sufijo,ancho)
WHERE NOT EXISTS (SELECT 1 FROM core.correlativo c
                  WHERE c.sucursal_id = s.sucursal_id
                    AND c.tipo = x.tipo::core.tipo_correlativo);


-- ---------------------------------------------------------------------
-- 4 · Los modulos por sede
--
-- OJO con Bioanalisis: lab_clinico queda APAGADO a proposito. Es lo que
-- hace interesante la prueba -- sus roles tienen los permisos de
-- laboratorio y aun asi no pueden usarlos.
-- ---------------------------------------------------------------------

INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, activo, asignado_por)
SELECT s.sucursal_id, 'core', s.empresa_id, true, 'operador'
FROM core.sucursal s
ON CONFLICT DO NOTHING;

INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, activo, asignado_por)
SELECT s.sucursal_id, 'lab_clinico', s.empresa_id, true, 'operador'
FROM core.sucursal s WHERE s.codigo IN ('CEN','NOR','SJC')
ON CONFLICT DO NOTHING;

INSERT INTO plataforma.modulo_sucursal
  (sucursal_id, modulo_id, empresa_id, activo, asignado_por, desactivado_en)
SELECT s.sucursal_id, 'lab_clinico', s.empresa_id, false, 'operador', now()
FROM core.sucursal s WHERE s.codigo = 'VAL'
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- 5 · Los convenios · toda empresa nace con Particular (E-6)
-- ---------------------------------------------------------------------

INSERT INTO core.convenio (empresa_id, nombre, tipo, modalidad_cobro, es_predeterminado)
SELECT e.empresa_id, 'Particular', 'particular', 'particular', true
FROM core.empresa e
WHERE NOT EXISTS (SELECT 1 FROM core.convenio c
                  WHERE c.empresa_id = e.empresa_id AND c.es_predeterminado);

INSERT INTO core.convenio
  (empresa_id, nombre, tipo, modalidad_cobro, dia_corte, recibe_copia_informe, rtn, contacto, telefono)
SELECT e.empresa_id, 'Clinica Medica San Jose', 'clinica', 'credito_mensual', 25,
       true, '05019014287395', 'Lic. Carmen Fonseca', '2234-1100'
FROM core.empresa e
WHERE e.rtn = '08019016543210'
  AND NOT EXISTS (SELECT 1 FROM core.convenio c
                  WHERE c.empresa_id = e.empresa_id AND c.nombre = 'Clinica Medica San Jose');

INSERT INTO core.convenio
  (empresa_id, nombre, tipo, modalidad_cobro, copago_porcentaje)
SELECT e.empresa_id, 'Seguros Atlantida', 'aseguradora', 'copago', 20
FROM core.empresa e
WHERE e.rtn = '08019016543210'
  AND NOT EXISTS (SELECT 1 FROM core.convenio c
                  WHERE c.empresa_id = e.empresa_id AND c.nombre = 'Seguros Atlantida');


-- ---------------------------------------------------------------------
-- 6 · Los roles · cinco por empresa
--
-- El Jefe de sede es el que estamos diseniando: administra su sede sin
-- tocar la configuracion de la empresa.
-- ---------------------------------------------------------------------

-- es_sistema SOLO en el Propietario: es la cuenta que entrega el operador,
-- y lo que la distingue es que su rol no se cambia ni se asigna. Antes los
-- cinco iban en true, que era leer la columna como "vino con la empresa";
-- no es eso lo que significa (ver core.rol.es_sistema).
INSERT INTO core.rol (empresa_id, nombre, descripcion, es_sistema, es_fijo)
SELECT e.empresa_id, x.nombre, x.descripcion, x.nombre = 'Propietario',
       x.nombre IN ('Propietario', 'Administrador')
FROM core.empresa e
CROSS JOIN (VALUES
  ('Propietario',  'La cuenta que el operador entrega con la empresa. Nombra a los administradores'),
  ('Administrador','Configura la empresa entera: usuarios, roles, sucursales, convenios y precios'),
  ('Jefe de sede', 'Administra SU sede: sus episodios, sus ordenes, su equipo. No crea usuarios ni toca la configuracion de la empresa'),
  ('Recepcion',    'Admite pacientes, crea ordenes, toma muestras y entrega informes'),
  ('Analista',     'Recibe muestras y captura resultados. NO valida'),
  ('Bioquimico',   'Lo del analista, mas validar, corregir y firmar')
) AS x(nombre, descripcion)
ON CONFLICT (empresa_id, core.llave_texto(nombre)) DO NOTHING;


-- ---------------------------------------------------------------------
-- 7 · Los permisos de cada rol
--
-- Propietario y Administrador se definen por EXCLUSION: todo el catalogo
-- de los modulos contratados (F1-6). La unica diferencia entre los dos es
-- usuario.nombrar_admin, que tiene solo el propietario. Los demas por
-- lista, porque su gracia es que NO tengan todo.
-- ---------------------------------------------------------------------

INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
SELECT r.rol_id, p.permiso_id, r.empresa_id
FROM core.rol r
CROSS JOIN plataforma.permiso p
WHERE (r.nombre = 'Propietario'
       OR (r.nombre = 'Administrador' AND p.permiso_id <> 'usuario.nombrar_admin'))
  AND p.modulo_id IN (SELECT DISTINCT ms.modulo_id
                      FROM plataforma.modulo_sucursal ms
                      WHERE ms.empresa_id = r.empresa_id AND ms.activo)
ON CONFLICT DO NOTHING;

INSERT INTO core.rol_permiso (rol_id, permiso_id, empresa_id)
SELECT r.rol_id, x.permiso_id, r.empresa_id
FROM core.rol r
JOIN (VALUES
  -- Sin usuario.administrar: quien puede crear usuarios es administrador, y
  -- a los administradores los nombra el propietario. El jefe de sede manda
  -- en su sede, no en quien entra al sistema.
  ('Jefe de sede','episodio.ver'),
  ('Jefe de sede','episodio.anular'),     ('Jefe de sede','orden.ver'),
  ('Jefe de sede','orden.anular'),        ('Jefe de sede','resultado.ver'),
  ('Jefe de sede','equipo.administrar'),  ('Jefe de sede','catalogo.ver'),
  ('Jefe de sede','convenio.ver'),        ('Jefe de sede','paciente.ver'),

  ('Recepcion','paciente.ver'),    ('Recepcion','paciente.crear'),
  ('Recepcion','paciente.editar'), ('Recepcion','episodio.ver'),
  ('Recepcion','episodio.crear'),  ('Recepcion','convenio.ver'),
  ('Recepcion','catalogo.ver'),    ('Recepcion','orden.ver'),
  ('Recepcion','orden.crear'),     ('Recepcion','muestra.tomar'),
  ('Recepcion','informe.entregar'),

  ('Analista','paciente.ver'),      ('Analista','episodio.ver'),
  ('Analista','catalogo.ver'),      ('Analista','orden.ver'),
  ('Analista','muestra.recibir'),   ('Analista','muestra.rechazar'),
  ('Analista','resultado.ver'),     ('Analista','resultado.capturar'),

  ('Bioquimico','paciente.ver'),           ('Bioquimico','episodio.ver'),
  ('Bioquimico','catalogo.ver'),           ('Bioquimico','catalogo.administrar'),
  ('Bioquimico','orden.ver'),              ('Bioquimico','orden.anular'),
  ('Bioquimico','muestra.recibir'),        ('Bioquimico','muestra.rechazar'),
  ('Bioquimico','resultado.ver'),          ('Bioquimico','resultado.capturar'),
  ('Bioquimico','resultado.validar'),      ('Bioquimico','resultado.corregir'),
  ('Bioquimico','valor_critico.registrar'),('Bioquimico','informe.emitir'),
  ('Bioquimico','informe.corregir')
) AS x(rol, permiso_id) ON x.rol = r.nombre
ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- 8 · La gente
--
-- El bioquimico lleva colegiacion; sin ella validar_resultado() lo
-- rechaza aunque tenga el permiso. La recepcionista no la necesita.
-- ---------------------------------------------------------------------

INSERT INTO core.empleado
  (empresa_id, nombres, apellidos, documento, telefono, correo, cargo, numero_colegiacion)
SELECT e.empresa_id, x.nombres, x.apellidos, x.documento, x.telefono, x.correo, x.cargo, x.colegiacion
FROM core.empresa e
JOIN (VALUES
  -- Ochoa
  ('08019016543210','Marlon Alberto','Ochoa Discua','0801198504321','9988-7766','marlon.ochoa@labochoa.hn','Propietario y bioquimico responsable','CMQ-2841'),
  ('08019016543210','Gabriela',      'Sierra Paz',  '0801199107788','9911-2233','gabriela.sierra@labochoa.hn','Jefa de la sucursal Norte',        NULL),
  ('08019016543210','Ana Luisa',     'Lopez Mejia', '0801199302156','9922-3344','ana.lopez@labochoa.hn',    'Recepcionista',                      NULL),
  ('08019016543210','Carla',         'Nunez Bonilla','0801199408899','9933-4455','carla.nunez@labochoa.hn', 'Recepcionista',                      NULL),
  ('08019016543210','Beto',          'Rivas Andino','0801198811223','9944-5566','beto.rivas@labochoa.hn',   'Analista de laboratorio',            NULL),
  ('08019016543210','Sandra',        'Munguia Cruz','0801198605544','9955-6677','sandra.munguia@labochoa.hn','Bioquimica',                        'CMQ-3190'),
  ('08019016543210','Jorge Luis',    'Padilla Caceres','0801199009911','9966-7788','jorge.padilla@labochoa.hn','Analista de laboratorio',         NULL),
  -- San Jose
  ('05019014287395','Carmen',        'Fonseca Elvir','0801197803344','9977-8899','carmen.fonseca@clinicasanjose.hn','Administradora',            NULL),
  ('05019014287395','Rene',          'Bustillo Lara','0801199206677','9988-9900','rene.bustillo@clinicasanjose.hn','Bioquimico',                  'CMQ-4055'),
  -- Bioanalisis
  ('08019018765432','Wendy',         'Alvarado Pineda','1201199304455','9900-1122','wendy.alvarado@bioanalisis.hn','Propietaria',                 'CMQ-5120')
) AS x(rtn,nombres,apellidos,documento,telefono,correo,cargo,colegiacion) ON x.rtn = e.rtn
WHERE NOT EXISTS (SELECT 1 FROM core.empleado em WHERE em.documento = x.documento);


-- ---------------------------------------------------------------------
-- 9 · Los usuarios · cada uno con su rol
-- ---------------------------------------------------------------------

INSERT INTO core.usuario (empresa_id, empleado_id, rol_id, username, password_hash, estado)
SELECT em.empresa_id, em.empleado_id, r.rol_id, x.username, 'SIN_CLAVE_PENDIENTE_ACTIVACION', 'activo'
FROM core.empleado em
JOIN (VALUES
  ('0801198504321','marlon.ochoa',  'Propietario'),
  ('0801199107788','gabriela.sierra','Jefe de sede'),
  ('0801199302156','ana.lopez',     'Recepcion'),
  ('0801199408899','carla.nunez',   'Recepcion'),
  ('0801198811223','beto.rivas',    'Analista'),
  ('0801198605544','sandra.munguia','Bioquimico'),
  ('0801199009911','jorge.padilla', 'Analista'),
  ('0801197803344','carmen.fonseca','Propietario'),
  ('0801199206677','rene.bustillo', 'Bioquimico'),
  ('1201199304455','wendy.alvarado','Propietario')
) AS x(documento, username, rol) ON x.documento = em.documento
JOIN core.rol r ON r.empresa_id = em.empresa_id AND r.nombre = x.rol
WHERE NOT EXISTS (SELECT 1 FROM core.usuario u WHERE u.empleado_id = em.empleado_id);


-- ---------------------------------------------------------------------
-- 10 · Quien trabaja en que sede
--
-- Repartidos a proposito:
--   Marlon   las DOS sedes  · el dueno anda en las dos
--   Gabriela solo NOR       · la jefa de la sucursal Norte
--   Ana      solo CEN
--   Carla    solo NOR
--   Beto     solo CEN
--   Sandra   las DOS        · la bioquimica firma para las dos sedes
--   Jorge    NINGUNA        · a proposito: un usuario sin acceso a nada
-- ---------------------------------------------------------------------

INSERT INTO core.acceso_sucursal (usuario_id, sucursal_id, empresa_id)
SELECT u.usuario_id, s.sucursal_id, u.empresa_id
FROM core.usuario u
JOIN core.sucursal s ON s.empresa_id = u.empresa_id
JOIN (VALUES
  ('marlon.ochoa','CEN'), ('marlon.ochoa','NOR'),
  ('gabriela.sierra','NOR'),
  ('ana.lopez','CEN'),
  ('carla.nunez','NOR'),
  ('beto.rivas','CEN'),
  ('sandra.munguia','CEN'), ('sandra.munguia','NOR'),
  ('carmen.fonseca','SJC'), ('rene.bustillo','SJC'),
  ('wendy.alvarado','VAL')
) AS x(username, codigo) ON x.username = u.username AND x.codigo = s.codigo
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 11 - Unos pacientes en Laboratorio Ochoa, para ver la lista y la busqueda
--      ("sair" tiene que traer a Sair primero y a Said despues).
--      Como postgres, con el correlativo de expediente; sin bitacora.
-- ---------------------------------------------------------------------
INSERT INTO core.paciente (empresa_id, expediente, nombre_completo, tipo_documento, documento,
                           fecha_nacimiento, fecha_nacimiento_estimada, sexo, telefono)
SELECT e.empresa_id, core.siguiente_correlativo(e.empresa_id, NULL, 'expediente'),
       x.nombre, x.tipo::plataforma.tipo_documento, x.documento,
       x.nacio, x.estimada, x.sexo::plataforma.sexo, x.telefono
FROM core.empresa e
JOIN (VALUES
  ('Said Gabriel Hoch Urbina',   'identidad', '0801200400844', DATE '2004-11-15', false, 'masculino', '9933-0001'),
  ('Sair Alejandro Mejia Lopez', 'identidad', '0801199912345', DATE '1999-03-02', false, 'masculino', '9933-0002'),
  ('Sayra Lizeth Nunez Bonilla', 'ninguno',   NULL,            DATE '2001-07-20', true,  'femenino',  NULL),
  ('Maria Jose Lopez Andino',    'identidad', '0801198500777', DATE '1985-05-20', false, 'femenino',  '9933-0004'),
  ('Jose Maria Lopez Andino',    'pasaporte', 'P0123456',      DATE '1982-12-01', false, 'masculino', NULL),
  ('Ana Lucia Zelaya Cruz',      'ninguno',   NULL,            (current_date - interval '6 months')::date, true, 'femenino', '9933-0006'),
  ('Carlos Roberto Andino Paz',  'identidad', '0801197000123', DATE '1970-01-30', false, 'masculino', '9933-0007'),
  ('Lucia Fernanda Reyes Mejia', 'partida_nacimiento', 'PN-2023-0456', DATE '2023-09-10', false, 'femenino', NULL)
) AS x(nombre, tipo, documento, nacio, estimada, sexo, telefono) ON true
WHERE e.rtn = '08019016543210'
  AND NOT EXISTS (SELECT 1 FROM core.paciente p WHERE p.empresa_id = e.empresa_id AND p.nombre_completo = x.nombre);
