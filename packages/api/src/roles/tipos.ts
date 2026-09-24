/**
 * LO QUE DEVUELVE roles/. El front lo espeja en Interfaces/rol.interface.ts:
 * mismos nombres, mismos campos.
 *
 * Un rol es de la EMPRESA (no de una sede): una bolsa de permisos con
 * nombre. Los permisos son de modulos, y un modulo puede estar apagado en
 * una sede: eso lo resuelve el formulario de empleados con el catalogo,
 * no esta pantalla.
 */

export interface RolDeLista {
  rolId: number;
  nombre: string;
  /** Obligatoria al crear y al guardar. null solo en roles de antes de esa regla. */
  descripcion: string | null;
  /** El rol del propietario. Uno por empresa: no se asigna, no se edita. */
  esSistema: boolean;
  /**
   * Lo entrego el operador al abrir la empresa (Propietario y
   * Administrador) y lo mantiene el operador: desde el LIS se ve, no se
   * edita ni se desactiva.
   */
  esFijo: boolean;
  /**
   * Tiene algun permiso de nivel 'admin' (usuario.administrar,
   * sucursal.administrar). Un rol asi lo edita solo el propietario, y solo
   * el propietario lo asigna: es la regla que cierra el agujero de "un rol
   * que edita roles se edita a si mismo".
   */
  esAdmin: boolean;
  /** Desactivado = ya no se asigna a nadie. Quien lo tenia, lo sigue teniendo. */
  activo: boolean;
  /** Quien pregunta lo tiene puesto: ese no lo edita, aunque pueda editar los demas. */
  esElMio: boolean;
  cuantosPermisos: number;
  /** Cuantas cuentas lo tienen. Con alguna, no se puede desactivar. */
  cuantosEmpleados: number;
}

/** Una persona que tiene el rol: lo justo para saber a quien afecta. */
export interface EmpleadoDeRol {
  empleadoId: number;
  nombres: string;
  apellidos: string;
  cargo: string | null;
  activo: boolean;
  /** El estado de su cuenta: pendiente_activacion, activo, suspendido o bloqueado. */
  estado: string;
}

/** La ficha: la lista mas sus permisos y quienes lo tienen. */
export interface RolCompleto extends RolDeLista {
  /** Los ids de sus permisos ('paciente.ver', ...). Para marcar las casillas. */
  permisos: string[];
  empleados: EmpleadoDeRol[];
}
