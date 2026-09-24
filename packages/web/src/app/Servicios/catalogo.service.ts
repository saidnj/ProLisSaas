import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import type { ModuloDePermisos, RolDeCatalogo, SucursalDeCatalogo } from '../Interfaces/catalogo.interface';

/**
 * LOS CATALOGOS: un metodo por lista para elegir, espejo de
 * catalogo/catalogo.controller.ts del API (/catalogo/<cosa>). Con sesion
 * vigente alcanza; el alcance (la empresa, y la sede cuando la cosa es de
 * la sede) lo pone el token, nunca un parametro de aqui. Un formulario
 * inyecta esto y ya tiene sus desplegables.
 *
 * Cuando haga falta una lista nueva (examenes, medicos...) se agrega aqui
 * un metodo y en el API su @Get en catalogo.controller.ts.
 */
@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly api = inject(ApiService);

  /** Los roles ACTIVOS de la empresa, con de que modulos son sus permisos. */
  roles(): Observable<RolDeCatalogo[]> {
    return this.api.get<RolDeCatalogo[]>('catalogo/roles');
  }

  /** Las sedes abiertas de la empresa, con sus modulos encendidos. */
  sucursales(): Observable<SucursalDeCatalogo[]> {
    return this.api.get<SucursalDeCatalogo[]>('catalogo/sucursales');
  }

  /** Los permisos que se le pueden poner a un rol, por modulo, con su nivel. */
  permisos(): Observable<ModuloDePermisos[]> {
    return this.api.get<ModuloDePermisos[]>('catalogo/permisos');
  }
}
