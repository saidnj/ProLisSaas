import { Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { EmpleadosService } from '../../../Servicios/empleados.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import type { Empleado } from '../../../Interfaces/empleado.interface';

/**
 * LA LISTA DE EMPLEADOS.
 *
 * Empleado y cuenta son uno (1 a 1): todo empleado nace con cuenta. La
 * columna "Cuenta" solo sale vacia en los de antes de esa regla; guardar la
 * ficha se la crea.
 */
@Component({
  selector: 'app-lista-empleados',
  imports: [RouterLink, Encabezado],
  templateUrl: './lista-empleados.html',
  styleUrl: './lista-empleados.scss',
})
export class ListaEmpleados {
  private readonly servicio = inject(EmpleadosService);
  protected readonly sesion = inject(SesionService);

  protected readonly empleados = signal<Empleado[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly busqueda = signal('');
  protected readonly verInactivos = signal(false);

  /**
   * El filtro es en memoria y a proposito: un laboratorio tiene decenas de
   * empleados, no miles. El dia que sean miles, esto se cambia por un
   * parametro que viaje al API -- y solo cambia este computed.
   */
  protected readonly filtrados = computed(() => {
    const texto = this.busqueda().trim().toLowerCase();
    return this.empleados().filter((e) => {
      if (!this.verInactivos() && !e.activo) return false;
      if (!texto) return true;
      return [e.nombres, e.apellidos, e.cargo, e.correo, e.documento, e.username]
        .some((c) => c?.toLowerCase().includes(texto));
    });
  });

  protected readonly inactivos = computed(
    () => this.empleados().filter((e) => !e.activo).length,
  );

  /** Lo hereda del rol: sin esto, los botones de crear y editar no se dibujan. */
  protected readonly puedeAdministrar = computed(
    () => this.sesion.puede('usuario.administrar'),
  );

  /**
   * LA FICHA SIGUE A LA CUENTA: la del propietario la edita solo el
   * propietario, la de un administrador solo el propietario (quien tiene
   * usuario.nombrar_admin). Sin cuenta, quien administre. El boton solo
   * cuando el back lo va a aceptar; la base lo rechaza igual.
   */
  protected puedeEditar(e: Empleado): boolean {
    if (!this.puedeAdministrar()) return false;
    if (e.usuarioId === null) return true;
    return (!e.rolEsSistema && !e.rolEsAdmin) || this.sesion.puede('usuario.nombrar_admin');
  }

  constructor() {
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);

    this.servicio.listar().subscribe({
      next: (lista) => {
        this.empleados.set(lista);
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se pudo traer la lista de empleados'));
        this.cargando.set(false);
      },
    });
  }

  protected nombre(e: Empleado): string {
    return e.nombres + ' ' + e.apellidos;
  }
}
