import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';

import { routes } from './app.routes';
import { tokenInterceptor } from './Interceptores/token.interceptor';
import { errorInterceptor } from './Interceptores/error.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),

    // Sin esta linea, inyectar HttpClient tira NullInjectorError.
    //
    // EL ORDEN DEL ARREGLO IMPORTA. Los interceptores forman una cadena:
    // a la IDA se recorre de izquierda a derecha, y a la VUELTA -- cuando
    // la respuesta o el error regresan -- al reves.
    //
    //   pide    ->  token  ->  error  ->  [red]
    //   responde <- token  <-  error  <-  [red]
    //
    // Por eso token va primero (pega la cabecera antes de salir) y error
    // despues (es el primero que ve lo que vuelve).
    provideHttpClient(withInterceptors([tokenInterceptor, errorInterceptor])),
  ],
};
