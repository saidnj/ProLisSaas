import { Routes } from '@angular/router';
import { permisoGuard, sesionGuard, sucursalGuard } from './Guardas/guardas';

/**
 * EL MAPA, Y QUIEN CUIDA CADA PUERTA.
 *
 * Tres niveles, de menos a mas exigente:
 *
 *   (nada)         login y activar. Tienen que ser abiertas: quien llega
 *                  aqui todavia no tiene con que identificarse.
 *
 *   sesionGuard    hay token. Alcanza para elegir sucursal y para las
 *                  pantallas que no dependen de una sede.
 *
 *   sucursalGuard  ademas ya eligio sede. Casi todo el sistema pide esto,
 *                  porque casi todo ocurre EN una sucursal.
 *
 *   + permisoGuard ademas tiene el permiso, con data.permiso.
 *
 * El orden del arreglo importa: sucursalGuard va ANTES que permisoGuard. Si
 * fuera al reves, alguien que entro y no eligio sede veria "no tenes
 * acceso" -- cuando lo que le falta no es el permiso, es pararse en algun
 * lado. Los permisos se calculan POR SEDE; sin sede la lista esta vacia y
 * todo daria que no.
 *
 * Y el recordatorio de siempre: esto decide que se PINTA. Quien autoriza de
 * verdad es el servidor.
 */
export const routes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'inicio' },

  {
    path: 'login',
    title: 'Entrar · ProLisSaas',
    loadComponent: () => import('./Componentes/login/login').then((m) => m.Login),
  },
  {
    path: 'activar',
    title: 'Activar cuenta · ProLisSaas',
    loadComponent: () => import('./Componentes/activar/activar').then((m) => m.Activar),
  },

  {
    path: 'elegir-sucursal',
    title: 'Elegir sede · ProLisSaas',
    canActivate: [sesionGuard],
    loadComponent: () =>
      import('./Componentes/elegir-sucursal/elegir-sucursal').then((m) => m.ElegirSucursal),
  },
  {
    path: 'sin-permiso',
    title: 'Sin acceso · ProLisSaas',
    canActivate: [sesionGuard],
    loadComponent: () =>
      import('./Componentes/sin-permiso/sin-permiso').then((m) => m.SinPermiso),
  },

  {
    path: 'inicio',
    title: 'Inicio · ProLisSaas',
    canActivate: [sucursalGuard],
    loadComponent: () => import('./Componentes/inicio/inicio').then((m) => m.Inicio),
  },

  // -------------------------------------------------------------------
  // EMPLEADOS
  //
  // OJO CON EL ORDEN: 'empleados/nuevo' va ANTES que 'empleados/:id'. El
  // router prueba de arriba abajo y se queda con la primera que calza, asi
  // que al reves la palabra "nuevo" se tomaria como un id y caeria en el
  // detalle buscando el empleado numero NaN.
  // -------------------------------------------------------------------
  {
    path: 'empleados',
    title: 'Empleados - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/empleados/lista/lista-empleados').then((m) => m.ListaEmpleados),
  },
  {
    path: 'empleados/nuevo',
    title: 'Nuevo empleado - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/empleados/formulario/formulario-empleado').then(
        (m) => m.FormularioEmpleado),
  },
  {
    path: 'empleados/:id',
    title: 'Ficha del empleado - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/empleados/detalle/detalle-empleado').then((m) => m.DetalleEmpleado),
  },
  {
    path: 'empleados/:id/editar',
    title: 'Editar empleado - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/empleados/formulario/formulario-empleado').then(
        (m) => m.FormularioEmpleado),
  },

  // -------------------------------------------------------------------
  // ROLES: mismo molde y mismo permiso que empleados (usuario.administrar:
  // "crear usuarios, roles y permisos"). Quien puede editar CUAL rol lo
  // decide la base, y la pantalla lo repite para no ofrecer el boton.
  // -------------------------------------------------------------------
  {
    path: 'roles',
    title: 'Roles - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/roles/lista/lista-roles').then((m) => m.ListaRoles),
  },
  {
    path: 'roles/nuevo',
    title: 'Nuevo rol - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/roles/formulario/formulario-rol').then((m) => m.FormularioRol),
  },
  {
    path: 'roles/:id',
    title: 'Rol - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/roles/detalle/detalle-rol').then((m) => m.DetalleRol),
  },
  {
    path: 'roles/:id/editar',
    title: 'Editar rol - ProLisSaas',
    canActivate: [sucursalGuard, permisoGuard],
    data: { permiso: 'usuario.administrar' },
    loadComponent: () =>
      import('./Componentes/roles/formulario/formulario-rol').then((m) => m.FormularioRol),
  },

  // -------------------------------------------------------------------
  // ASI SE AGREGA UNA PANTALLA CON PERMISO. Descomentar cuando exista el
  // componente:
  //
  // {
  //   path: 'usuarios',
  //   title: 'Usuarios · ProLisSaas',
  //   canActivate: [sucursalGuard, permisoGuard],
  //   data: { permiso: 'usuario.administrar' },
  //   loadComponent: () =>
  //     import('./Componentes/usuarios/usuarios').then((m) => m.Usuarios),
  // },
  //
  // Con arreglo alcanza con tener UNO de los de la lista:
  //   data: { permiso: ['orden.crear', 'orden.ver'] }
  //
  // El permiso se escribe igual que en plataforma.permiso -- 'modulo.accion'
  // -- porque es el mismo que comprueba core.usuario_puede() en la base.
  // Nunca una ruta HTTP: atar la autorizacion a la forma de la URL hace que
  // cambiar la URL cambie quien puede hacer que.
  // -------------------------------------------------------------------

  { path: '**', redirectTo: 'inicio' },
];
