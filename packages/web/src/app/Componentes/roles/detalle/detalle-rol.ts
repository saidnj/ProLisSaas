import { Component, computed, inject, signal } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { RolesService } from '../../../Servicios/roles.service';
import { CatalogoService } from '../../../Servicios/catalogo.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import { porQueNoSeEdita } from '../reglas';
import type { RolCompleto } from '../../../Interfaces/rol.interface';
import type { ModuloDePermisos, PermisoDeCatalogo } from '../../../Interfaces/catalogo.interface';

/** Como se muestra el estado de cada cuenta que tiene el rol. */
const ESTADOS: Record<string, { texto: string; clase: 'si' | 'no' | 'gris' | 'info' }> = {
  pendiente_activacion: { texto: 'Pendiente', clase: 'info' },
  activo:               { texto: 'Activa',    clase: 'si' },
  bloqueado:            { texto: 'Bloqueada', clase: 'no' },
  suspendido:           { texto: 'Suspendida', clase: 'gris' },
};

/**
 * LA FICHA DE UN ROL: que puede hacer (los permisos, por modulo, con la
 * descripcion del catalogo) y quien lo tiene puesto. Si no se puede editar
 * -- fijo, el propio, de administrador sin ser el propietario -- lo dice
 * aqui en vez de ofrecer un boton que va a fallar.
 */
@Component({
  selector: 'app-detalle-rol',
  imports: [RouterLink, Encabezado],
  templateUrl: './detalle-rol.html',
  styleUrl: './detalle-rol.scss',
})
export class DetalleRol {
  private readonly servicio = inject(RolesService);
  private readonly catalogo = inject(CatalogoService);
  private readonly ruta = inject(ActivatedRoute);
  protected readonly sesion = inject(SesionService);

  protected readonly rol = signal<RolCompleto | null>(null);
  protected readonly modulos = signal<ModuloDePermisos[]>([]);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly porQueNo = computed(() => {
    const r = this.rol();
    return r ? porQueNoSeEdita(r, this.sesion.puede('usuario.nombrar_admin')) : null;
  });

  /**
   * Los permisos del rol, agrupados por modulo, con palabras (la
   * descripcion del catalogo; el id que usa la base no se muestra). Solo
   * los modulos donde tiene alguno. Lo que no este en el catalogo (un
   * modulo que ya no esta contratado) se cuenta aparte.
   */
  protected readonly porModulo = computed(() => {
    const r = this.rol();
    if (!r) return [];
    const tiene = new Set(r.permisos);
    return this.modulos()
      .map((m) => ({ ...m, permisos: m.permisos.filter((p) => tiene.has(p.id)) }))
      .filter((m) => m.permisos.length > 0);
  });

  protected readonly fueraDelCatalogo = computed(() => {
    const r = this.rol();
    if (!r || this.modulos().length === 0) return 0;
    const enCatalogo = new Set(this.modulos().flatMap((m) => m.permisos.map((p) => p.id)));
    return r.permisos.filter((id) => !enCatalogo.has(id)).length;
  });

  constructor() {
    const id = Number(this.ruta.snapshot.paramMap.get('id'));

    this.catalogo.permisos().subscribe({
      next: (m) => this.modulos.set(m),
      error: () => this.modulos.set([]),
    });

    this.servicio.obtener(id).subscribe({
      next: (r) => {
        this.rol.set(r);
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se encontro ese rol'));
        this.cargando.set(false);
      },
    });
  }

  protected estado(clave: string) {
    return ESTADOS[clave] ?? { texto: clave, clase: 'gris' as const };
  }

  protected esAdmin(p: PermisoDeCatalogo): boolean {
    return p.nivel !== 'normal';
  }
}
