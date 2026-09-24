import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { SesionService } from '../Servicios/sesion.service';
import { environment } from '../../environments/environment';

/**
 * Le pega el token a cada peticion que sale hacia NUESTRO API.
 *
 * Va en un interceptor y no adentro de ApiService a proposito: el
 * interceptor actua a nivel de HttpClient, asi que alcanza tambien al
 * cliente que vamos a generar desde el OpenAPI -- que no va a pasar por
 * ApiService. Lo que tiene que aplicarse a TODAS las peticiones no puede
 * vivir en un envoltorio que alguien puede esquivar.
 */
export const tokenInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(SesionService).token();

  // Dos condiciones, y la segunda importa tanto como la primera:
  //
  //   1. que haya token
  //   2. que la peticion vaya a NUESTRO API
  //
  // Sin la segunda, el dia que el front pida algo a un servicio de
  // terceros -- un mapa, un CDN, lo que sea -- le estariamos mandando la
  // credencial del laboratorio de regalo.
  if (!token || !req.url.startsWith(environment.apiUrl)) {
    return next(req);
  }

  // Las peticiones son inmutables: no se modifican, se clona una nueva.
  return next(
    req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }),
  );
};
