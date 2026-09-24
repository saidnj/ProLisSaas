/**
 * LO QUE DEVUELVEN LOS CATALOGOS. El front lo espeja en
 * Interfaces/catalogo.interface.ts: mismos nombres, mismos campos.
 *
 * Un catalogo trae lo minimo para elegir bien: id, nombre, y algun campo
 * mas solo si sin el se elige mal. Nada de lo que muestra la pantalla de
 * administrar.
 */

/** A que modulo pertenecen los permisos de un rol, y cuantos son. */
export interface ModuloDeRol {
  id: string;
  nombre: string;
  permisos: number;
}

/** Un rol ACTIVO de la empresa, para elegirlo. */
export interface RolDeCatalogo {
  rolId: number;
  nombre: string;
  descripcion: string | null;
  /** El rol del propietario: no se asigna ni se cambia. Uno por empresa. */
  esSistema: boolean;
  /** Puede crear usuarios (tiene usuario.administrar). Lo nombra solo el propietario. */
  esAdmin: boolean;
  /**
   * De que modulos son sus permisos y cuantos de cada uno. Sin esto se
   * elige mal: cruzado con los modulos de cada sede, el formulario sabe
   * que "Bioquimico en Valle pierde 11 de 15" sin otra ida al back.
   */
  modulos: ModuloDeRol[];
}

/** Una sede ABIERTA de la empresa, para elegirla. */
export interface SucursalDeCatalogo {
  sucursalId: number;
  codigo: string;
  nombre: string;
  /** Los modulos ENCENDIDOS en esa sede ('core', 'lab_clinico'...). */
  modulos: string[];
}

/**
 * Quien puede ponerle este permiso a un rol. Lo decide la base
 * (plataforma.permiso.nivel, core.asignar_permisos_a_rol):
 *   normal       cualquiera que administre usuarios
 *   admin        solo el propietario; y un rol que lo tenga es "de
 *                administrador": lo edita y lo asigna solo el propietario
 *   propietario  nadie: es del rol del propietario y de nadie mas
 */
export type NivelPermiso = 'normal' | 'admin' | 'propietario';

/** Un permiso que se le puede poner a un rol, para marcarlo. */
export interface PermisoDeCatalogo {
  /** 'modulo.accion', tal como esta en plataforma.permiso. */
  id: string;
  descripcion: string;
  nivel: NivelPermiso;
}

/** Los permisos asignables, agrupados por modulo (solo los contratados). */
export interface ModuloDePermisos {
  id: string;
  nombre: string;
  permisos: PermisoDeCatalogo[];
}
