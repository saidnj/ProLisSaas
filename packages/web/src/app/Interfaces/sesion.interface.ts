// =====================================================================
//  EL CONTRATO CON EL BACK
//
//  Es el espejo exacto de packages/api/src/auth/respuesta-sesion.ts. Si
//  uno cambia, el otro tambien -- hasta que el cliente se genere desde el
//  OpenAPI del API y este archivo se borre solo.
// =====================================================================

export interface SucursalDeSesion {
  sucursalId: number;
  codigo: string;
  nombre: string;

  /** Los modulos encendidos EN ESTA SEDE. Para esconder secciones enteras. */
  modulos: string[];

  /**
   * Los permisos que de verdad sirven parado AQUI: el rol intersecado con
   * los modulos que la empresa paga en esta sede.
   *
   * Por eso van adentro de la sucursal y no en una lista suelta al lado. El
   * mismo rol rinde distinto en cada sede, y una lista plana diria que no.
   */
  permisos: string[];
}

export interface DatosSesion {
  usuario: {
    usuarioId: number;
    username: string;
    estado: string;
    /** El acceso ANTERIOR a este. Sirve para "tu ultimo ingreso fue...". */
    ultimoAccesoEn: string | null;
  };
  persona: {
    empleadoId: number | null;
    nombre: string | null;
    cargo: string | null;
    correo: string | null;
    /** Numero de colegiacion del bioquimico. Va impreso en el informe. */
    colegiacion: string | null;
    activo: boolean | null;
  };
  empresa: {
    empresaId: number;
    /** El nombre legal, el del RTN. */
    nombre: string;
    /** El de rotulo. Es el que va en el encabezado (E-21). */
    comercial: string | null;
    nivelAcceso: string;
    fechaCierre: string | null;
  };
  rol: {
    rolId: number;
    nombre: string;
    esSistema: boolean;
  };
  sucursales: SucursalDeSesion[];
}

export interface RespuestaSesion extends DatosSesion {
  token: string;
  /** true cuando hay mas de una sede y falta elegir. El token aun no la lleva. */
  requiereSucursal: boolean;
  /** La sede ya elegida, cuando habia una sola y se eligio sola. */
  sucursalId: number | null;
}

export interface RespuestaSucursal {
  /** Token NUEVO, ahora con la sucursal firmada adentro. Reemplaza al anterior. */
  token: string;
  sucursalId: number;
}

export interface Credenciales {
  username: string;
  password: string;
}

export interface DatosActivacion {
  username: string;
  codigo: string;
  claveNueva: string;
}
