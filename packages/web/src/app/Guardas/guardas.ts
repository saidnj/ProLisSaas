import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { SesionService } from '../Servicios/sesion.service';

/**
 * LOS TRES FILTROS DEL ROUTER, Y QUE PROTEGE CADA UNO.
 *
 * AVISO QUE VALE PARA LOS TRES: esto NO es seguridad, es comodidad.
 * Deciden que PANTALLA se pinta, leyendo una sesion que vive en
 * localStorage -- o sea, algo que el usuario puede editar con F12. Quien
 * quiera saltarselos lo hace en diez segundos.
 *
 * Lo que de verdad protege los DATOS esta del otro lado:
 *   - las politicas RLS, que recortan por empresa en cada consulta
 *   - core.usuario_puede(), que exige el permiso Y la sede del token
 *   - el guard del back, que saca empresa y sucursal del token FIRMADO
 *
 * Estos guards existen para que nadie vea un boton que el servidor le va a
 * rechazar. Nada mas, y esta bien que sea nada mas.
 */

/** Hay sesion. Si no, al login. */
export const sesionGuard: CanActivateFn = () => {
  const sesion = inject(SesionService);
  const router = inject(Router);
  return sesion.autenticado() ? true : router.createUrlTree(['/login']);
};

/**
 * Ya eligio sede.
 *
 * Va DESPUES de sesionGuard y separado de el a proposito: son dos preguntas
 * distintas -- "quien sos" y "donde estas parado" -- y confundirlas manda al
 * login a alguien que ya entro bien y solo le falta elegir sucursal.
 */
export const sucursalGuard: CanActivateFn = () => {
  const sesion = inject(SesionService);
  const router = inject(Router);
  if (!sesion.autenticado()) return router.createUrlTree(['/login']);
  return sesion.sucursalId() !== null ? true : router.createUrlTree(['/elegir-sucursal']);
};

/**
 * Tiene el permiso EN LA SEDE DONDE ESTA PARADO.
 *
 * Se declara en la ruta:
 *     { path: 'usuarios', data: { permiso: 'usuario.administrar' }, ... }
 *     { path: 'ordenes',  data: { permiso: ['orden.crear','orden.ver'] }, ... }
 *
 * Con arreglo alcanza con tener UNO de los de la lista.
 */
export const permisoGuard: CanActivateFn = (ruta) => {
  const sesion = inject(SesionService);
  const router = inject(Router);

  if (!sesion.autenticado()) return router.createUrlTree(['/login']);
  if (sesion.sucursalId() === null) return router.createUrlTree(['/elegir-sucursal']);

  const pedido = ruta.data['permiso'] as string | string[] | undefined;

  // Una ruta que usa este guard y no dice que permiso pide es un error de
  // programacion, no un permiso libre. Se bloquea: falla CERRADO. Al reves
  // -- dejar pasar cuando falta el dato -- es como se abren los agujeros
  // que nadie nota hasta que alguien entra por ahi.
  if (!pedido) {
    console.error('[permisoGuard] la ruta no declara data.permiso:', ruta.routeConfig?.path);
    return router.createUrlTree(['/sin-permiso']);
  }

  const lista = Array.isArray(pedido) ? pedido : [pedido];
  const tiene = lista.some((p) => sesion.puede(p));

  return tiene ? true : router.createUrlTree(['/sin-permiso']);
};
