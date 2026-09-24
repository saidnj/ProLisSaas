/**
 * LOS CATALOGOS: las listas para elegir algo en un campo (o para mostrar
 * su nombre). Espejo de catalogo/tipos.ts del API: mismos nombres, mismos
 * campos. Que es y que no es un catalogo: api/src/LEEME.md, regla 3.
 *
 * Son livianas y de solo lectura: lo justo para elegir bien, solo lo
 * vigente, y con el alcance que pone la sesion (la empresa, y la sede
 * cuando la cosa es de la sede). Administrar la cosa (crear un rol, abrir
 * una sede) tendra su propia interfaz cuando exista esa pantalla.
 */

/**
 * A que modulo pertenecen los permisos de un rol, y cuantos son.
 *
 * Un rol no es de una sede: es una bolsa de permisos de la empresa. Pero
 * cada permiso pertenece a un modulo, y la sede es la que tiene modulos
 * encendidos o apagados. Bioquimico en una sede sin laboratorio no es un
 * rol que "no exista" ahi: es un rol del que quedan vivos 4 permisos de 15.
 * Con esta lista y la de modulos de cada sede, el formulario lo calcula
 * solo, sin ir al back por cada casilla que se marca.
 */
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
  /** El rol del propietario: la cuenta que entrega el operador. No se asigna ni se cambia. */
  esSistema: boolean;
  /** Puede crear usuarios (tiene usuario.administrar). Lo nombra solo el propietario. */
  esAdmin: boolean;
  /** Ordenados por id. Un rol sin permisos trae []. */
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
