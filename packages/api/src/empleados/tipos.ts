/**
 * LO QUE DEVUELVE empleados/. El front lo espeja en
 * Interfaces/empleado.interface.ts: mismos nombres, mismos campos.
 */

export interface EmpleadoDeLista {
  empleadoId: number;
  nombres: string;
  apellidos: string;
  documento: string | null;
  telefono: string | null;
  correo: string | null;
  cargo: string | null;
  numeroColegiacion: string | null;
  activo: boolean;
  creadoEn: string;
  /** El username de su cuenta, o null si no tiene. */
  username: string | null;
  /** El id de su cuenta, o null si todavia no tiene (los de antes de que fuera obligatoria). */
  usuarioId: number | null;
  /** El rol de esa cuenta, o null si no tiene. Para mostrarlo y para saber que le sirve en cada sede. */
  rolId: number | null;
  rol: string | null;
  /** Si ese rol es el del propietario / uno de administrador: decide quien puede tocar la cuenta. */
  rolEsSistema: boolean | null;
  rolEsAdmin: boolean | null;
  /** pendiente_activacion, activo, suspendido o bloqueado. null sin cuenta. */
  estado: string | null;
  /** Las sedes donde puede pararse. null cuando no tiene cuenta. */
  sucursales: number[] | null;
}

/**
 * Lo que devuelven crear y guardar: la ficha, y el codigo de activacion EN
 * CLARO si este guardar creo la cuenta y quedo activa. Es la unica vez que
 * el codigo existe fuera de un hash. null si no hubo cuenta nueva o nacio
 * inactiva (suspendida, sin codigo).
 */
export interface EmpleadoGuardado extends EmpleadoDeLista {
  activacion: {
    codigo: string;
    venceEn: Date | null;
    aviso: string;
  } | null;
}
