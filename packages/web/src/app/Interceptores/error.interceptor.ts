import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { SesionService } from '../Servicios/sesion.service';

/**
 * Lo que hay que hacer con un error pase donde pase, para no repetirlo en
 * cada pantalla.
 *
 *   401  el token vencio o no sirve  -> cerrar sesion y mandar al login
 *   403  el token sirve pero no alcanza el permiso -> NO se cierra nada,
 *        la pantalla decide que decir
 *
 * Confundir los dos es el error clasico: con un 403 tratado como 401, a un
 * usuario que toca un boton que no le corresponde lo expulsas del sistema.
 */
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const sesion = inject(SesionService);
  const router = inject(Router);

  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      // La excepcion: el propio login. Una clave equivocada tambien
      // contesta 401, y sin esta linea entrarias en un bucle -- te manda
      // al login, que falla, que te manda al login.
      // El login Y la activacion: los dos contestan 401 con credencial mala.
      const esPuertaDeEntrada =
        req.url.includes('/auth/login') || req.url.includes('/auth/activar');

      if (error.status === 401 && !esPuertaDeEntrada) {
        sesion.cerrar();
        router.navigate(['/login']);
      }

      // Se vuelve a lanzar SIEMPRE. El interceptor decide el efecto
      // global; quien llamo sigue necesitando enterarse para mostrar su
      // propio mensaje.
      return throwError(() => error);
    }),
  );
};
