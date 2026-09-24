import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from './api.service';
import type {
  CambiosCuenta, CuentaNueva,
  Empleado, EmpleadoEntrada, RespuestaGuardarEmpleado,
} from '../Interfaces/empleado.interface';

/**
 * Empleados, contra el API de verdad. Los catalogos (roles, sedes) van por
 * CatalogoService: son de sus modulos, no de este.
 *
 * Ya no hay datos de muestra: todo sale de la base, recortado por RLS a la
 * empresa de quien pregunta. Ninguna de estas llamadas manda el empresaId
 * -- ni podria: el back lo saca del token firmado y no le cree al navegador.
 *
 * El token lo pega el tokenInterceptor, asi que aqui no aparece.
 */
@Injectable({ providedIn: 'root' })
export class EmpleadosService {
  private readonly api = inject(ApiService);

  listar(): Observable<Empleado[]> {
    return this.api.get<Empleado[]>('empleados');
  }

  obtener(id: number): Observable<Empleado> {
    return this.api.get<Empleado>('empleados/' + id);
  }

  /**
   * Crea la persona, su cuenta, sus sedes y -- si nace activa -- su codigo
   * de activacion, todo en una sola transaccion del lado del back. Si algo
   * falla, no queda nada a medias. La cuenta no es opcional: empleado y
   * usuario son uno.
   */
  crear(datos: EmpleadoEntrada & { cuenta: CuentaNueva }): Observable<RespuestaGuardarEmpleado> {
    return this.api.post<RespuestaGuardarEmpleado>('empleados', datos);
  }

  /**
   * Guardar: la ficha y la cuenta tal como esta en pantalla. UNA peticion y
   * UNA transaccion en el back: o cambia todo o no cambia nada. No hace
   * falta comparar antes de mandar: lo de la cuenta que vino igual no se
   * escribe ni deja evento (comun/cuenta.ts en el API). Si el empleado no
   * tenia cuenta, este guardar se la crea y devuelve el codigo, como al
   * crear. PATCH y no PUT: en este sistema nada se reemplaza entero.
   */
  actualizar(id: number, datos: EmpleadoEntrada, cuenta?: CambiosCuenta): Observable<RespuestaGuardarEmpleado> {
    return this.api.patch<RespuestaGuardarEmpleado>('empleados/' + id, cuenta ? { ...datos, cuenta } : datos);
  }

  /**
   * Un codigo nuevo. Para una cuenta pendiente es un reemplazo (el anterior
   * deja de servir); para una activa o bloqueada es RESTABLECER LA CLAVE:
   * se le borra, queda fuera en el acto y estrena otra con el codigo. Una
   * suspendida no: el back lo rechaza.
   */
  generarCodigo(empleadoId: number) {
    return this.api.post<{ empleadoId: number; codigo: string; venceEn: string; aviso: string }>(
      'empleados/' + empleadoId + '/codigo',
      {},
    );
  }

  /**
   * De bloqueado a activo, con el contador en cero y sin codigo: la clave
   * sigue siendo la suya.
   */
  desbloquear(empleadoId: number) {
    return this.api.post<{ empleadoId: number; estado: 'activo' }>(
      'empleados/' + empleadoId + '/desbloquear',
      {},
    );
  }
}
