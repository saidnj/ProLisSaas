-- =====================================================================
-- ProLisSaas · 06 · Semillas
--
-- El catalogo del producto (igual para todos los clientes) y la funcion
-- que deja una empresa nueva lista para operar.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Modulos
-- ---------------------------------------------------------------------

INSERT INTO plataforma.modulo (modulo_id, nombre, descripcion) VALUES
  ('core',         'Nucleo',              'Admision, pacientes, usuarios, convenios, informes'),
  ('lab_clinico',  'Laboratorio clinico', 'Ordenes, muestras, resultados y validacion')
ON CONFLICT (modulo_id) DO NOTHING;

-- Cuando llegue, sera una fila mas y nada del nucleo cambia:
--   ('imagenologia', 'Imagenologia', 'Estudios de imagen e informes radiologicos'),
--   ('facturacion',  'Facturacion',  'Cobro, credito por convenio y cierre de caja')


-- ---------------------------------------------------------------------
-- Permisos · acciones del dominio, no rutas
-- ---------------------------------------------------------------------

INSERT INTO plataforma.permiso (permiso_id, modulo_id, descripcion) VALUES
  ('paciente.ver',        'core', 'Consultar pacientes'),
  ('paciente.crear',      'core', 'Registrar un paciente nuevo'),
  ('paciente.editar',     'core', 'Modificar datos de un paciente'),
  ('paciente.fusionar',   'core', 'Fusionar dos expedientes duplicados'),
  ('episodio.ver',        'core', 'Consultar episodios'),
  ('episodio.crear',      'core', 'Abrir un episodio de admision'),
  ('episodio.anular',     'core', 'Anular un episodio con motivo'),
  ('convenio.ver',        'core', 'Consultar convenios y sus tarifas'),
  ('convenio.administrar','core', 'Crear y modificar convenios y listas de precios'),
  ('usuario.administrar', 'core', 'Crear usuarios, roles y permisos'),
  ('sucursal.administrar','core', 'Crear y configurar sucursales'),
  ('informe.emitir',      'core', 'Emitir la version de un informe'),
  ('informe.corregir',    'core', 'Emitir una version correctiva'),
  ('informe.entregar',    'core', 'Registrar la entrega de un informe'),
  -- derivacion.responder se retiro: con el modelo de mensajes nada se acepta.
  -- La aceptacion se mudo una sola vez a la relacion (plataforma.enlace).
  ('derivacion.solicitar','core', 'Mandar datos de un paciente a otra empresa'),
  ('auditoria.ver',       'core', 'Consultar el rastro de auditoria')
ON CONFLICT (permiso_id) DO NOTHING;

-- Los de la rama de laboratorio se agregan con el modulo:
--   orden.crear, muestra.tomar, muestra.rechazar, resultado.capturar,
--   resultado.validar, resultado.corregir, catalogo.administrar


-- ---------------------------------------------------------------------
-- El alta de una empresa NO esta aqui
--
-- Estuvo, y era codigo muerto que parecia vivo: 16_roles.sql define la misma
-- funcion con la misma firma, corre despues, y la pisaba en silencio. Quien
-- leyera este archivo para entender el alta leia una version que nunca se
-- ejecutaba -- la de aqui creaba los roles operativos VACIOS. (H-84)
--
-- La unica definicion viva esta en 16_roles.sql.
-- ---------------------------------------------------------------------
