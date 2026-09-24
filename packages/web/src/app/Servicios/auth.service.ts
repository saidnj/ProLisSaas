import { Injectable, inject } from '@angular/core';
import { Router } from '@angular/router';
import { Observable, tap } from 'rxjs';
import { ApiService } from './api.service';
import { SesionService } from './sesion.service';
import type {
  Credenciales, DatosActivacion, RespuestaSesion, RespuestaSucursal,
} from '../Interfaces/sesion.interface';

/**
 * Las tres puertas de entrada, y lo que hay que hacer con lo que devuelven.
 *
 * Las pantallas llaman aqui y no a ApiService directo: asi el efecto de
 * entrar -- guardar la sesion -- ocurre en UN lugar. Si cada pantalla
 * guardara por su cuenta, el dia que se agregue un campo hay que acordarse
 * de tres sitios.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly api = inject(ApiService);
  private readonly sesion = inject(SesionService);
  private readonly router = inject(Router);

  entrar(cred: Credenciales): Observable<RespuestaSesion> {
    return this.api
      .post<RespuestaSesion>('auth/login', cred)
      .pipe(tap((r) => this.sesion.abrir(r)));
  }

  activar(datos: DatosActivacion): Observable<RespuestaSesion> {
    // Activar ENTRA. Ya demostro que tiene el codigo y acaba de definir su
    // clave; mandarla a escribirlo todo otra vez no agrega seguridad.
    return this.api
      .post<RespuestaSesion>('auth/activar', datos)
      .pipe(tap((r) => this.sesion.abrir(r)));
  }

  /**
   * Pararse en una sede. Devuelve un token NUEVO, ahora con la sucursal
   * firmada adentro -- por eso hay que reemplazar el viejo y no solo anotar
   * el id de la sucursal en el front.
   */
  elegirSucursal(sucursalId: number): Observable<RespuestaSucursal> {
    return this.api
      .post<RespuestaSucursal>('auth/sucursal', { sucursalId })
      .pipe(tap((r) => this.sesion.pararseEn(r.sucursalId, r.token)));
  }

  /**
   * Salir es borrar del lado del navegador y nada mas. El token sigue siendo
   * valido en el servidor hasta que venza: un JWT no se puede revocar
   * (H-103). Por eso vence en 8 horas y no en un mes.
   */
  salir(): void {
    this.sesion.cerrar();
    void this.router.navigate(['/login']);
  }
}
