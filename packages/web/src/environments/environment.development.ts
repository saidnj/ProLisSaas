// =====================================================================
//  DESARROLLO
//
//  Este reemplaza a environment.ts cuando corres "ng serve" (la
//  configuracion "development" es la predeterminada de serve).
//
//  El back escucha en 3000 y el front en 4200: son origenes distintos,
//  asi que el navegador va a bloquear la peticion hasta que Nest
//  habilite CORS para http://localhost:4200.
// =====================================================================

export const environment = {
  production: false,

  apiUrl: 'http://localhost:3000',
};
