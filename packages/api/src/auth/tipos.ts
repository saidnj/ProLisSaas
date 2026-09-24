/**
 * LO QUE EL BACK MANDA AL ENTRAR.
 *
 * Es el contrato con el front y tiene que traer TODO lo que la pantalla
 * necesita para pintarse, porque despues de esto el front no vuelve a
 * preguntar quien es hasta el siguiente login.
 *
 * Los nombres vienen en camelCase desde el SQL (jsonb_build_object los arma
 * asi): snake_case en la base, camelCase en la API, sin una capa de traduccion
 * en medio que se olvide de un campo.
 */

export interface SucursalDeSesion {
  sucursalId: number;
  codigo: string;
  nombre: string;

  /** Los modulos ENCENDIDOS en esta sede. Sirve para esconder secciones enteras. */
  modulos: string[];

  /**
   * Los permisos que de verdad sirven AQUI: el rol intersecado con los modulos
   * que la empresa paga en ESTA sede.
   *
   * Por eso van por sucursal y no en una lista suelta. El mismo rol de 30
   * permisos rinde 30 donde lab_clinico esta encendido y 16 donde esta
   * apagado; una lista plana diria 30 en las dos y la pantalla ofreceria un
   * boton que el servidor rechaza. Es el mismo reparto que hace
   * core.usuario_puede() en la base, que es la que manda.
   */
  permisos: string[];
}

export interface DatosSesion {
  usuario: {
    usuarioId: number;
    username: string;
    estado: string;
    /** El acceso ANTERIOR, no este. Se lee antes de pisarlo con now(). */
    ultimoAccesoEn: string | null;
  };
  persona: {
    empleadoId: number | null;
    nombre: string | null;
    cargo: string | null;
    correo: string | null;
    /** El numero de colegiacion del bioquimico. Va impreso en el informe. */
    colegiacion: string | null;
    activo: boolean | null;
  };
  empresa: {
    empresaId: number;
    /** El nombre legal, el del RTN. */
    nombre: string;
    /** El nombre de rotulo. Es el que va en el encabezado de la pantalla (E-21). */
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

  /**
   * true cuando hay mas de una sede y la persona todavia no eligio. El token
   * que viene arriba NO lleva sucursal: sirve para identificarse y para llamar
   * a POST /auth/sucursal, y nada mas.
   */
  requiereSucursal: boolean;

  /** La sede ya elegida, cuando habia una sola y se eligio sola. */
  sucursalId: number | null;
}
