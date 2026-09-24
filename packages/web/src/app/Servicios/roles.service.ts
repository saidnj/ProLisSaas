import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import type { Rol, RolCambios, RolCompleto, RolEntrada } from '../Interfaces/rol.interface';

/**
 * Roles, contra el API (roles/). Los permisos para marcar salen de
 * CatalogoService.permisos(): son un catalogo, no de este modulo.
 *
 * Nada de aqui manda el empresaId: el back lo saca del token firmado. El
 * token lo pega el tokenInterceptor.
 */
@Injectable({ providedIn: 'root' })
export class RolesService {
  private readonly api = inject(ApiService);

  /** Todos los de la empresa, activos e inactivos. */
  listar(): Observable<Rol[]> {
    return this.api.get<Rol[]>('roles');
  }

  obtener(id: number): Observable<RolCompleto> {
    return this.api.get<RolCompleto>('roles/' + id);
  }

  /** El rol y sus permisos, en una sola transaccion del back: o queda todo o nada. */
  crear(datos: RolEntrada): Observable<RolCompleto> {
    return this.api.post<RolCompleto>('roles', datos);
  }

  /**
   * Guardar tal como esta en pantalla: nombre, descripcion, permisos y
   * estado. UNA peticion y UNA transaccion; lo que vino igual no se
   * escribe ni deja evento, asi que no hay que comparar antes.
   */
  actualizar(id: number, datos: RolCambios): Observable<RolCompleto> {
    return this.api.patch<RolCompleto>('roles/' + id, datos);
  }
}
