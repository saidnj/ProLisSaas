/**
 * Un rol de la empresa: una bolsa de permisos con nombre. Espejo de
 * roles/tipos.ts del API: mismos nombres, mismos campos.
 *
 * Para ELEGIR un rol (el formulario de empleados) esta RolDeCatalogo en
 * catalogo.interface.ts; esto es lo que muestra la pantalla de administrar.
 */
export interface Rol {
  rolId: number;
  nombre: string;
  /** Obligatoria al crear y al guardar. null solo en roles de antes de esa regla. */
  descripcion: string | null;
  /** El rol del propietario. Uno por empresa: no se asigna, no se edita. */
  esSistema: boolean;
  /**
   * Lo entrego el operador al abrir la empresa (Propietario y
   * Administrador) y lo mantiene el operador: se ve, no se edita ni se
   * desactiva desde aqui.
   */
  esFijo: boolean;
  /**
   * Tiene algun permiso de nivel 'admin'. Un rol asi lo edita y lo asigna
   * solo el propietario: es lo que cierra el agujero de "un rol que edita
   * roles se edita a si mismo".
   */
  esAdmin: boolean;
  /** Apagado: ya no se asigna a nadie. Quien lo tenia lo sigue teniendo. */
  activo: boolean;
  /** Quien esta sentado lo tiene puesto: ese no lo edita, aunque edite los demas. */
  esElMio: boolean;
  cuantosPermisos: number;
  /** Cuantas cuentas lo tienen. Con alguna no se puede desactivar. */
  cuantosEmpleados: number;
}

/** Una persona que tiene el rol. */
export interface EmpleadoDeRol {
  empleadoId: number;
  nombres: string;
  apellidos: string;
  cargo: string | null;
  activo: boolean;
  /** El estado de su cuenta: pendiente_activacion, activo, suspendido o bloqueado. */
  estado: string;
}

/** La ficha: lo de la lista mas los permisos y quienes lo tienen. */
export interface RolCompleto extends Rol {
  /** Los ids de sus permisos ('paciente.ver', ...). */
  permisos: string[];
  empleados: EmpleadoDeRol[];
}

/** Lo que se manda al crear: el nombre, la descripcion y los permisos, de una vez. */
export interface RolEntrada {
  nombre: string;
  descripcion: string;
  permisos: string[];
}

/** Al guardar, ademas, el estado (y por que se apaga). */
export interface RolCambios extends RolEntrada {
  activo?: boolean;
  motivo?: string;
}
