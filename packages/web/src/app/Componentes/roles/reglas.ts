import type { Rol } from '../../Interfaces/rol.interface';

/**
 * QUIEN PUEDE EDITAR QUE ROL. La misma pregunta que hace la base en
 * core.rol_para_editar(): esto es para no ofrecer un boton que el back va
 * a rechazar, y para decir POR QUE. La pared es la base.
 *
 *   fijo          lo entrego el operador (Propietario, Administrador)
 *   el mio        nadie edita el rol que tiene puesto
 *   administrador solo el propietario (quien tiene usuario.nombrar_admin)
 *
 * Devuelve el motivo, o null si se puede.
 */
export function porQueNoSeEdita(r: Rol, puedeNombrarAdmin: boolean): string | null {
  if (r.esFijo) return 'Lo entrego el operador y lo mantiene el operador: no se edita desde aqui.';
  if (r.esElMio) return 'Es el rol que tenes puesto: no se edita a uno mismo.';
  if (r.esAdmin && !puedeNombrarAdmin) return 'Es un rol de administrador: solo el propietario lo edita.';
  return null;
}
