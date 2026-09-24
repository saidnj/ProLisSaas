import { Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { RolesService } from '../../../Servicios/roles.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import { porQueNoSeEdita } from '../reglas';
import type { Rol } from '../../../Interfaces/rol.interface';

/**
 * LA LISTA DE ROLES. Un rol es una bolsa de permisos con nombre, de la
 * empresa. Aqui salen todos, activos e inactivos; para elegir uno en un
 * formulario esta el catalogo (solo activos).
 *
 * Los que "vienen con la casa" (Propietario, Administrador) se ven pero no
 * se editan; los de administrador los edita solo el propietario; y nadie
 * edita el que tiene puesto. Esos botones no se dibujan, y la ficha dice
 * por que.
 */
@Component({
  selector: 'app-lista-roles',
  imports: [RouterLink, Encabezado],
  templateUrl: './lista-roles.html',
  styleUrl: './lista-roles.scss',
})
export class ListaRoles {
  private readonly servicio = inject(RolesService);
  protected readonly sesion = inject(SesionService);

  protected readonly roles = signal<Rol[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly busqueda = signal('');
  protected readonly verInactivos = signal(false);

  protected readonly filtrados = computed(() => {
    const texto = this.busqueda().trim().toLowerCase();
    return this.roles().filter((r) => {
      if (!this.verInactivos() && !r.activo) return false;
      if (!texto) return true;
      return [r.nombre, r.descripcion].some((c) => c?.toLowerCase().includes(texto));
    });
  });

  protected readonly inactivos = computed(() => this.roles().filter((r) => !r.activo).length);

  private readonly puedeNombrarAdmin = computed(() => this.sesion.puede('usuario.nombrar_admin'));

  constructor() {
    this.cargar();
  }

  protected cargar(): void {
    this.cargando.set(true);
    this.error.set(null);

    this.servicio.listar().subscribe({
      next: (lista) => {
        this.roles.set(lista);
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se pudo traer la lista de roles'));
        this.cargando.set(false);
      },
    });
  }

  /** El boton de editar solo cuando el back lo va a aceptar. */
  protected puedeEditar(r: Rol): boolean {
    return porQueNoSeEdita(r, this.puedeNombrarAdmin()) === null;
  }
}
