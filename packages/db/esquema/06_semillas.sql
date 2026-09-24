-- =====================================================================
-- ProLisSaas - 06 - Semillas
--
-- El catalogo del producto: igual para todos los clientes y escrito por el
-- operador. Los modulos, los permisos y el catalogo de hematologia del Hemax 53.
--
-- Generado desde los archivos por modulo. Se reparte por TIPO de objeto
-- para poder leer el modelo entero de un tiron.
-- =====================================================================


-- ---------------------------------------------------------- 06_semillas.sql

-- =====================================================================
-- ProLisSaas - 06 - Semillas
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
-- Permisos - acciones del dominio, no rutas
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
  ('usuario.nombrar_admin','core', 'Nombrar administradores y tocar sus cuentas. Solo el propietario'),
  ('sucursal.administrar','core', 'Crear y configurar sucursales'),
  ('informe.emitir',      'core', 'Emitir la version de un informe'),
  ('informe.corregir',    'core', 'Emitir una version correctiva'),
  ('informe.entregar',    'core', 'Registrar la entrega de un informe'),
  -- derivacion.responder se retiro: con el modelo de mensajes nada se acepta.
  -- La aceptacion se mudo una sola vez a la relacion (plataforma.enlace).
  ('derivacion.solicitar','core', 'Mandar datos de un paciente a otra empresa'),
  ('auditoria.ver',       'core', 'Consultar el rastro de auditoria')
ON CONFLICT (permiso_id) DO NOTHING;


-- ---------------------------------------------------------- 15_lab_semillas.sql

-- =====================================================================
-- ProLisSaas - 15 - Semillas del laboratorio
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
--   - el metodo y el reactivo del equipo,
--   - la poblacion que atiende el laboratorio,
--   - y la altitud: en Tegucigalpa, a unos 1000 m, la hemoglobina y el
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

-- El NIVEL de cada permiso (plataforma.nivel_permiso). Todo nace 'normal';
-- aqui van, explicitos, los que no lo son. Un permiso de nivel 'admin' hace
-- que el rol que lo tenga sea de administrador (solo el propietario lo
-- asigna y solo el toca ese rol y sus cuentas); uno de nivel 'propietario'
-- no se asigna nunca. Es la lista que hay que revisar cuando llega un
-- modulo nuevo: si trae un permiso que da forma a quien puede que, va aqui.
UPDATE plataforma.permiso SET nivel = 'propietario' WHERE permiso_id = 'usuario.nombrar_admin';
UPDATE plataforma.permiso SET nivel = 'admin'
 WHERE permiso_id IN ('usuario.administrar', 'sucursal.administrar');


-- ---------------------------------------------------------- 17_comercial.sql

-- ---------------------------------------------------------------------
-- Los motivos que ya conocemos
--
-- Los que CONCEDEN acceso nacen definidos y en completo: que un cliente activo
-- pueda trabajar no es una politica por decidir, es lo normal.
--
-- Los que RESTRINGEN quedan en false, y hasta que alguien decida sus valores
-- aplican solo_lectura y avisan. La excepcion es riesgo_seguridad, que si trae
-- politica: es el unico donde esperar es peor que equivocarse.
-- ---------------------------------------------------------------------
INSERT INTO comercial.motivo
  (motivo_id, tipo_evento, nombre, descripcion,
   nivel_inmediato, dias_plazo, nivel_al_vencer, estado_al_vencer,
   requiere_nota, politica_definida)
VALUES
  -- Entrada
  ('prueba_gratuita',   'alta', 'Periodo de prueba',
   'Evaluacion sin contrato firmado',                'completo', NULL, NULL, NULL, false, true),
  ('contrato_firmado',  'alta', 'Contrato firmado',
   'Entra directamente como cliente',                'completo', NULL, NULL, NULL, false, true),
  ('migracion',         'alta', 'Migracion desde otro sistema',
   'Viene de otro sistema y trae datos',             'completo', NULL, NULL, NULL, true,  true),

  -- Activacion
  ('pago_recibido',     'activacion', 'Pago recibido',
   'Se cobro la primera factura',                    'completo', NULL, NULL, NULL, false, true),
  ('contrato_activado', 'activacion', 'Contrato activado',
   'Termino la prueba y firmo',                      'completo', NULL, NULL, NULL, false, true),

  -- Suspension
  ('falta_pago',        'suspension', 'Falta de pago',
   'Retraso en facturas',                            'solo_lectura', NULL, NULL, NULL, false, false),
  ('solicitud_cliente', 'suspension', 'A peticion del cliente',
   'Pausa temporal: remodelacion, vacaciones',       'solo_lectura', NULL, NULL, NULL, true,  false),
  ('fin_de_prueba',     'suspension', 'Fin del periodo de prueba',
   'Termino la prueba sin convertir',                'solo_lectura', NULL, NULL, NULL, false, false),
  ('incumplimiento',    'suspension', 'Incumplimiento del contrato',
   'Uso indebido o violacion de los terminos',       'solo_lectura', NULL, NULL, NULL, true,  false),
  ('riesgo_seguridad',  'suspension', 'Riesgo de seguridad',
   'Cuenta comprometida o actividad anomala',        'bloqueado', 0, 'bloqueado', 'suspendida', true, true),

  -- Reactivacion
  ('pago_regularizado', 'reactivacion', 'Pago regularizado',
   'Se pusieron al dia',                             'completo', NULL, NULL, NULL, false, true),
  ('acuerdo_alcanzado', 'reactivacion', 'Acuerdo alcanzado',
   'Se resolvio lo que motivo la suspension',        'completo', NULL, NULL, NULL, true,  true),

  -- Cancelacion
  ('cancelacion_con_antelacion', 'cancelacion', 'Cancelacion con antelacion',
   'El cliente aviso con el plazo acordado',         'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('cancelacion_voluntaria',     'cancelacion', 'Cancelacion voluntaria',
   'El cliente se va sin haber avisado',             'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('falta_pago_prolongada',      'cancelacion', 'Falta de pago prolongada',
   'Escalo desde una suspension por mora',           'solo_cierre', NULL, 'bloqueado',    'cerrada', true,  false),
  ('incumplimiento_grave',       'cancelacion', 'Incumplimiento grave',
   'Motivo de terminacion inmediata',                'bloqueado',   NULL, 'bloqueado',    'cerrada', true,  false),
  ('cierre_del_negocio',         'cancelacion', 'El laboratorio cerro',
   'El cliente dejo de operar',                      'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),
  ('migracion_a_otro',           'cancelacion', 'Se fue a otro sistema',
   'Cambio de proveedor',                            'solo_cierre', NULL, 'solo_lectura', 'cerrada', false, false),

  -- Cierre
  ('plazo_vencido',     'cierre', 'Vencio el plazo de cierre',
   'La tarea diaria lo aplico',                      'bloqueado', NULL, NULL, NULL, false, true),
  ('cierre_solicitado', 'cierre', 'Cierre solicitado por el cliente',
   'Pidio cortar el acceso antes de que venza',      'bloqueado', NULL, NULL, NULL, true,  true)
ON CONFLICT (motivo_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Los parches que este esquema ya contiene. Una base cargada desde estos
-- archivos no tiene que correr ninguno: quedan anotados como aplicados.
-- Cada parche nuevo agrega su nombre aqui Y se anota solo al correr.
-- ---------------------------------------------------------------------
INSERT INTO plataforma.migracion (nombre) VALUES
  ('2026-09-21_acceso_sucursal'),
  ('2026-09-21_activacion'),
  ('2026-09-22_desbloqueo'),
  ('2026-09-22_propietario'),
  ('2026-09-22_rls_permisos'),
  ('2026-09-23_cuenta'),
  ('2026-09-23_cuenta_siempre'),
  ('2026-09-23_empleado_unico'),
  ('2026-09-23_permiso_unico'),
  ('2026-09-24_roles'),
  ('2026-09-24_ficha'),
  ('2026-09-25_cerrar'),
  ('2026-09-25_pacientes')
ON CONFLICT DO NOTHING;
