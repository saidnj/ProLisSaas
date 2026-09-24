import { Component, computed, inject, signal } from '@angular/core';
import { Router, RouterLink, RouterLinkActive } from '@angular/router';
import { AuthService } from '../../Servicios/auth.service';
import { SesionService } from '../../Servicios/sesion.service';
import { MENU, OpcionMenu } from './menu';

/**
 * EL ENCABEZADO DEL SISTEMA.
 *
 * Se pone en cualquier pantalla con una linea:
 *
 *     imports: [Encabezado]          <- en el @Component de esa pantalla
 *     <app-encabezado />             <- al principio de su .html
 *
 * No hay que registrarlo en ningun modulo: en Angular 21 los componentes
 * son "standalone" y se importan uno a uno, donde se usan. Se ve de un
 * vistazo quien usa que, y lo que una pantalla no importa no se le carga.
 *
 * El menu NO se escribe aqui: vive en menu.ts, y este componente solo lo
 * filtra con los permisos y los modulos de la sede donde esta parado.
 */
@Component({
  selector: 'app-encabezado',
  imports: [RouterLink, RouterLinkActive],
  templateUrl: './encabezado.html',
  styleUrl: './encabezado.scss',
})
export class Encabezado {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly sesion = inject(SesionService);

  /** Solo para pantallas angostas: en escritorio el menu abre al pasar el mouse. */
  protected readonly menuAbierto = signal(false);

  /**
   * El menu recortado a lo que esta persona puede hacer AQUI.
   *
   * Es un computed sobre las signals de la sesion: cuando cambia de sede,
   * el menu se repinta solo. No hay que acordarse de recalcularlo.
   */
  protected readonly menu = computed(() => this.filtrar(MENU));

  protected readonly iniciales = computed(() => {
    const nombre = this.sesion.persona()?.nombre ?? this.sesion.usuario()?.username ?? '';
    const partes = nombre.trim().split(/[\s.]+/).filter(Boolean);
    return ((partes[0]?.[0] ?? '') + (partes[1]?.[0] ?? '')).toUpperCase() || '?';
  });

  private filtrar(opciones: OpcionMenu[]): OpcionMenu[] {
    return opciones
      .map((o) => (o.hijos ? { ...o, hijos: this.filtrar(o.hijos) } : o))
      .filter((o) => {
        // El modulo manda sobre todo: si la sede no lo tiene contratado, la
        // rama entera desaparece aunque el rol traiga los permisos.
        if (o.modulo && !this.sesion.tieneModulo(o.modulo)) return false;

        // Un padre sin hijos visibles no se muestra: seria un menu que se
        // abre vacio.
        if (o.hijos) return o.hijos.length > 0;

        return this.permitido(o.permiso);
      });
  }

  private permitido(permiso?: string | string[]): boolean {
    if (!permiso) return true;
    const lista = Array.isArray(permiso) ? permiso : [permiso];
    return lista.some((p) => this.sesion.puede(p));
  }

  protected cerrarMenu(): void {
    this.menuAbierto.set(false);
  }

  protected cambiarSucursal(): void {
    this.cerrarMenu();
    void this.router.navigate(['/elegir-sucursal']);
  }

  protected salir(): void {
    this.cerrarMenu();
    this.auth.salir();
  }
}
