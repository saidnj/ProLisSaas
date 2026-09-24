import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import type { Paciente, PacienteCompleto, PacienteEntrada } from '../Interfaces/paciente.interface';

/**
 * Pacientes, contra el API (pacientes/).
 *
 * Nada de aqui manda el empresaId: el back lo saca del token firmado. El
 * token lo pega el tokenInterceptor.
 */
@Injectable({ providedIn: 'root' })
export class PacientesService {
  private readonly api = inject(ApiService);

  /**
   * Sin texto: los ultimos registrados (50). Con texto: por parecido, no
   * por texto exacto, y ordenados por coincidencia (para "sair", Sair
   * antes que Said). Sirve el nombre, el expediente o el documento.
   */
  buscar(texto?: string, limite?: number): Observable<Paciente[]> {
    const params: Record<string, string | number> = {};
    if (texto?.trim()) params['q'] = texto.trim();
    if (limite) params['limite'] = limite;
    return this.api.get<Paciente[]>('pacientes', params);
  }

  obtener(id: number): Observable<PacienteCompleto> {
    return this.api.get<PacienteCompleto>('pacientes/' + id);
  }

  /** Un insert sencillo: la ficha. Vuelve con su expediente. */
  crear(datos: PacienteEntrada): Observable<PacienteCompleto> {
    return this.api.post<PacienteCompleto>('pacientes', datos);
  }

  /**
   * Guardar tal como esta en pantalla: la ficha entera. Lo que vino igual
   * no se escribe ni deja evento, asi que no hay que comparar antes.
   */
  actualizar(id: number, datos: PacienteEntrada): Observable<PacienteCompleto> {
    return this.api.patch<PacienteCompleto>('pacientes/' + id, datos);
  }
}
