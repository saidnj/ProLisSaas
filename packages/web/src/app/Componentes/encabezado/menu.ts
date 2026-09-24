/**
 * EL MENU, EN UN SOLO LUGAR.
 *
 * Agregar una pantalla al sistema es agregar una linea aqui y una ruta en
 * app.routes.ts. Nada mas: el encabezado se arma solo a partir de esto.
 *
 * Cada opcion dice que hace falta para verla:
 *
 *   permiso   el permiso -- o cualquiera de una lista -- en la SEDE donde
 *             esta parado. Sin permiso, la opcion no se dibuja.
 *   modulo    el modulo tiene que estar encendido en esa sede. Esconde
 *             ramas enteras: donde no se contrato lab_clinico, no aparece
 *             ni "Ordenes" ni "Resultados".
 *   ruta      si falta, la opcion se dibuja apagada con un "pronto". Es a
 *             proposito: asi el menu muestra el mapa completo del sistema
 *             y se ve lo que falta, en vez de mandarte a una pagina que
 *             no existe.
 *
 * Y el recordatorio de siempre: esconder una opcion NO es seguridad. Es
 * cortesia -- no ofrecer un boton que el servidor va a rechazar. Quien
 * autoriza de verdad son core.usuario_puede() y las politicas RLS.
 */
export interface OpcionMenu {
  texto: string;
  ruta?: string;
  permiso?: string | string[];
  modulo?: string;
  hijos?: OpcionMenu[];
}

export const MENU: OpcionMenu[] = [
  {
    texto: 'Pacientes',
    modulo: 'core',
    hijos: [
      { texto: 'Ver pacientes',      ruta: '/pacientes',       permiso: 'paciente.ver' },
      { texto: 'Registrar paciente', ruta: '/pacientes/nuevo', permiso: 'paciente.crear' },
      { texto: 'Fusionar duplicados', permiso: 'paciente.fusionar' },
    ],
  },
  {
    texto: 'Ordenes',
    modulo: 'lab_clinico',
    hijos: [
      { texto: 'Ver ordenes',   permiso: 'orden.ver' },
      { texto: 'Nueva orden',   permiso: 'orden.crear' },
      { texto: 'Recibir muestra', permiso: 'muestra.recibir' },
    ],
  },
  {
    texto: 'Resultados',
    modulo: 'lab_clinico',
    hijos: [
      { texto: 'Capturar',  permiso: 'resultado.capturar' },
      { texto: 'Validar',   permiso: 'resultado.validar' },
      { texto: 'Corregir',  permiso: 'resultado.corregir' },
    ],
  },
  {
    texto: 'Informes',
    modulo: 'core',
    hijos: [
      { texto: 'Emitir',   permiso: 'informe.emitir' },
      { texto: 'Entregar', permiso: 'informe.entregar' },
    ],
  },
  {
    texto: 'Administracion',
    hijos: [
      // OJO: no existe un permiso empleado.* en el catalogo. Los empleados
      // se administran junto con los usuarios, asi que cuelgan del mismo
      // permiso. Si algun dia se separan, se separa aqui tambien.
      { texto: 'Empleados', ruta: '/empleados', permiso: 'usuario.administrar', modulo: 'core' },
      { texto: 'Roles',     ruta: '/roles',     permiso: 'usuario.administrar', modulo: 'core' },
      { texto: 'Usuarios',  permiso: 'usuario.administrar', modulo: 'core' },
      { texto: 'Sucursales',  permiso: 'sucursal.administrar', modulo: 'core' },
      { texto: 'Convenios',   permiso: 'convenio.administrar', modulo: 'core' },
      { texto: 'Catalogo',    permiso: 'catalogo.administrar',  modulo: 'lab_clinico' },
      { texto: 'Equipos',     permiso: 'equipo.administrar',    modulo: 'lab_clinico' },
      { texto: 'Auditoria',   permiso: 'auditoria.ver',         modulo: 'core' },
    ],
  },
];
