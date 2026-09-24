import { HttpErrorResponse } from '@angular/common/http';

/**
 * Saca un mensaje legible de lo que sea que haya vuelto.
 *
 * Nest contesta de dos formas segun quien rechazo:
 *   - una excepcion nuestra  -> message es un string
 *   - el ValidationPipe      -> message es un ARREGLO de strings
 * y si el back no esta levantado no hay cuerpo ninguno (status 0).
 */
export function mensajeDeError(err: unknown, porOmision = 'Algo salio mal'): string {
  if (!(err instanceof HttpErrorResponse)) return porOmision;

  if (err.status === 0) {
    return 'No se pudo hablar con el servidor. Revisa que el API este levantado.';
  }

  const m = (err.error as { message?: string | string[] } | null)?.message;
  if (Array.isArray(m)) return m.join('. ');
  if (typeof m === 'string' && m.trim()) return m;

  return porOmision;
}

/**
 * Un dato que ya es de otro registro. Lo manda el back en un 409
 * (empleados/duplicados.ts; roles.service.ts con 'nombre').
 */
export type CampoEnUso = 'nombre' | 'documento' | 'telefono' | 'correo' | 'colegiacion' | 'username';

/**
 * Los campos en uso de un 409, para marcarlos junto al campo que
 * corresponde. Se dice QUE dato ya esta en uso, no de quien. Vacio si no es
 * un 409 de esos.
 */
export function camposEnUso(err: unknown): ReadonlySet<CampoEnUso> {
  if (!(err instanceof HttpErrorResponse) || err.status !== 409) return new Set();
  const lista = (err.error as { campos?: CampoEnUso[] } | null)?.campos;
  return new Set(Array.isArray(lista) ? lista : []);
}
