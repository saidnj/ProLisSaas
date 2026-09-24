// =====================================================================
//  PRODUCCION
//
//  OJO: este es el de produccion, no el de desarrollo. angular.json no
//  tiene fileReplacements en la configuracion "production", asi que este
//  archivo se usa TAL CUAL al compilar. El que lo tapa en "ng serve" es
//  environment.development.ts.
//
//  NADA DE LO QUE ESTE AQUI ES SECRETO. Todo esto viaja al navegador y
//  cualquiera lo lee abriendo las herramientas de desarrollo. Solo la
//  URL del API y banderas de funciones. Ninguna clave, ningun token con
//  poder real, y JAMAS nada del .env del back.
// =====================================================================

export const environment = {
  production: true,

  // Cambiar por el dominio real cuando exista el servidor.
  apiUrl: 'https://api.prolissaas.hn',
};
