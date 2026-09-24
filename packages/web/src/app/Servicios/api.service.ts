import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';

/**
 * Envoltorio delgado sobre HttpClient: un solo lugar donde vive la URL
 * del API.
 *
 * NO pone el token ni maneja errores -- eso lo hacen los interceptores,
 * que alcanzan a todas las peticiones y no solo a las que pasan por aqui.
 *
 * Es temporal y esta bien que lo sea. Cuando el API publique su OpenAPI y
 * generemos el cliente tipado, los metodos de aqui se reemplazan por
 * metodos por endpoint, con tipos de verdad en vez de un string suelto:
 *
 *     api.get<Paciente[]>('pacientes')   // hoy, 'pacientes' es un string
 *     pacientesApi.listar()              // manana, el compilador lo revisa
 */
@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = environment.apiUrl;

  get<T>(endpoint: string, params?: Record<string, string | number | boolean>): Observable<T> {
    return this.http.get<T>(this.url(endpoint), { params: this.armarParams(params) });
  }

  post<T>(endpoint: string, body: unknown): Observable<T> {
    return this.http.post<T>(this.url(endpoint), body);
  }

  put<T>(endpoint: string, body: unknown): Observable<T> {
    return this.http.put<T>(this.url(endpoint), body);
  }

  /** En este sistema nada se borra: se anula. PATCH se va a usar mas que PUT. */
  patch<T>(endpoint: string, body: unknown): Observable<T> {
    return this.http.patch<T>(this.url(endpoint), body);
  }

  delete<T>(endpoint: string): Observable<T> {
    return this.http.delete<T>(this.url(endpoint));
  }

  private url(endpoint: string): string {
    // Aguanta 'pacientes' y '/pacientes' por igual.
    return `${this.baseUrl}/${endpoint.replace(/^\//, '')}`;
  }

  private armarParams(params?: Record<string, string | number | boolean>): HttpParams | undefined {
    if (!params) return undefined;
    let p = new HttpParams();
    for (const [clave, valor] of Object.entries(params)) {
      if (valor !== undefined && valor !== null) p = p.set(clave, String(valor));
    }
    return p;
  }
}
