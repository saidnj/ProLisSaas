import { Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { RolesService } from '../../../Servicios/roles.service';
import { CatalogoService } from '../../../Servicios/catalogo.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { camposEnUso, mensajeDeError, type CampoEnUso } from '../../../Servicios/errores';
import { porQueNoSeEdita } from '../reglas';
import type { RolCompleto } from '../../../Interfaces/rol.interface';
import type { ModuloDePermisos, PermisoDeCatalogo } from '../../../Interfaces/catalogo.interface';

/**
 * CREAR Y EDITAR UN ROL, EN UNA SOLA PANTALLA. Mismo molde que el
 * formulario de empleados: los mismos campos con las mismas reglas, y
 * todo -- nombre, descripcion, permisos, estado -- en UNA peticion y UNA
 * transaccion en el back. Al crear: si los permisos no pasan, el rol no
 * queda creado a medias.
 *
 * Los permisos salen del catalogo, agrupados por modulo, y cada uno trae su
 * NIVEL. Con eso se pinta lo que la base va a rechazar de todos modos
 * (core.asignar_permisos_a_rol), con su motivo:
 *
 *   propietario  no se asigna a nadie: es del rol del propietario
 *   admin        lo asigna solo el propietario; y marcar uno vuelve al rol
 *                "de administrador": desde ahi lo edita y lo asigna solo el
 *                propietario. Se avisa antes de guardar.
 *
 * Y quien puede editar que rol (core.rol_para_editar): no un rol FIJO
 * (Propietario, Administrador: los mantiene el operador), no EL PROPIO, y
 * uno de administrador solo el propietario. Si no se puede, esta pantalla
 * lo dice y no dibuja el formulario.
 *
 * Desactivar: el rol sale del catalogo y ya no se le asigna a nadie; quien
 * lo tenia lo sigue teniendo. No se puede apagar si alguien lo tiene
 * puesto: primero se les cambia el rol (la base lo rechaza con 409).
 */
@Component({
  selector: 'app-formulario-rol',
  imports: [ReactiveFormsModule, RouterLink, Encabezado],
  templateUrl: './formulario-rol.html',
  styleUrl: './formulario-rol.scss',
})
export class FormularioRol {
  private readonly fb = inject(FormBuilder);
  private readonly servicio = inject(RolesService);
  private readonly catalogo = inject(CatalogoService);
  private readonly sesion = inject(SesionService);
  private readonly router = inject(Router);
  private readonly ruta = inject(ActivatedRoute);

  private readonly param = this.ruta.snapshot.paramMap.get('id');
  protected readonly id = this.param ? Number(this.param) : null;
  protected readonly editando = this.id !== null;

  protected readonly cargando = signal(true);
  protected readonly guardando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly modulos = signal<ModuloDePermisos[]>([]);

  /** El rol que se esta editando, tal como vino. null al crear. */
  protected readonly rol = signal<RolCompleto | null>(null);

  /**
   * Los permisos marcados. Un Set y no un FormArray: lo unico que hace
   * falta es "esta o no esta".
   */
  protected readonly marcados = signal<ReadonlySet<string>>(new Set());

  /** Ya intento guardar: los "hace falta" se muestran a partir de ahi. */
  protected readonly intentado = signal(false);

  /** El nombre ya es de otro rol (409 del back). Se va al tocar el campo. */
  protected readonly enUso = signal<ReadonlySet<CampoEnUso>>(new Set());

  protected readonly titulo = computed(() => (this.editando ? 'Editar rol' : 'Nuevo rol'));

  protected readonly formulario = this.fb.nonNullable.group({
    nombre:      ['', [Validators.required, Validators.minLength(2), Validators.maxLength(60)]],
    descripcion: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(200)]],
    activo:      [true],
    motivo:      [''],
  });

  protected readonly activoMarcado = toSignal(this.formulario.controls.activo.valueChanges, {
    initialValue: this.formulario.controls.activo.value,
  });

  /** Quien esta sentado es el propietario (o tiene su permiso extra). */
  protected readonly puedeNombrarAdmin = computed(() => this.sesion.puede('usuario.nombrar_admin'));

  /** Al editar: por que no se puede, si no se puede. null = adelante. */
  protected readonly bloqueado = computed(() => {
    const r = this.rol();
    return r ? porQueNoSeEdita(r, this.puedeNombrarAdmin()) : null;
  });

  /** Todos los permisos del catalogo, planos, por id. */
  private readonly catalogoPorId = computed(() => {
    const m = new Map<string, PermisoDeCatalogo>();
    for (const mod of this.modulos()) for (const p of mod.permisos) m.set(p.id, p);
    return m;
  });

  /** Se marco alguno de nivel 'admin': el rol pasa a ser de administrador. */
  protected readonly quedaAdmin = computed(() =>
    [...this.marcados()].some((id) => this.catalogoPorId().get(id)?.nivel === 'admin'),
  );

  /**
   * Cuantos permisos tiene el rol que ya no estan en el catalogo (el modulo
   * dejo de estar contratado). No se mandan: la base los rechazaria. Al
   * guardar se quitan del rol, y se dice antes.
   */
  protected readonly fueraDelCatalogo = computed(() => {
    const r = this.rol();
    if (!r || this.modulos().length === 0) return 0;
    return r.permisos.filter((id) => !this.catalogoPorId().has(id)).length;
  });

  protected readonly faltanPermisos = computed(() => this.marcados().size === 0);

  /** Se esta apagando un rol que alguien tiene puesto: la base lo va a rechazar. */
  protected readonly apagaConGente = computed(() => {
    const r = this.rol();
    return !!r && r.activo && !this.activoMarcado() && r.cuantosEmpleados > 0;
  });

  /** Se esta apagando (estaba activo): ahi tiene sentido preguntar por que. */
  protected readonly seApaga = computed(() => {
    const r = this.rol();
    return !!r && r.activo && !this.activoMarcado();
  });

  constructor() {
    this.formulario.controls.nombre.valueChanges.subscribe(() => {
      if (this.enUso().has('nombre')) this.enUso.set(new Set());
    });

    this.catalogo.permisos().subscribe({
      next: (m) => {
        this.modulos.set(m);
        if (!this.editando) this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se pudieron traer los permisos'));
        this.cargando.set(false);
      },
    });

    if (this.id !== null) {
      this.servicio.obtener(this.id).subscribe({
        next: (r) => {
          this.rol.set(r);
          this.formulario.patchValue({
            nombre: r.nombre,
            descripcion: r.descripcion ?? '',
            activo: r.activo,
          });
          this.marcados.set(new Set(r.permisos));
          // Con gente adentro no se apaga: la casilla se ve, no se toca (y
          // la pantalla dice por que). Es la misma regla que core.desactivar_rol.
          if (r.activo && r.cuantosEmpleados > 0) this.formulario.controls.activo.disable();
          this.cargando.set(false);
        },
        error: (e) => {
          this.error.set(mensajeDeError(e, 'No se encontro ese rol'));
          this.cargando.set(false);
        },
      });
    }
  }

  /**
   * Por que NO se puede marcar este permiso, si no se puede. Lo mismo que
   * va a decir la base, dicho antes y junto a la casilla. null = se puede.
   */
  protected vetado(p: PermisoDeCatalogo): string | null {
    if (p.nivel === 'propietario') return 'Solo lo tiene el propietario';
    if (p.nivel === 'admin' && !this.puedeNombrarAdmin()) return 'Solo el propietario lo asigna';
    return null;
  }

  protected alternar(p: PermisoDeCatalogo): void {
    if (this.vetado(p)) return;
    const s = new Set(this.marcados());
    if (s.has(p.id)) s.delete(p.id); else s.add(p.id);
    this.marcados.set(s);
  }

  /** Marcar o desmarcar todo un modulo (lo que se puede marcar). */
  protected marcarModulo(m: ModuloDePermisos, marcar: boolean): void {
    const s = new Set(this.marcados());
    for (const p of m.permisos) {
      if (this.vetado(p)) continue;
      if (marcar) s.add(p.id); else s.delete(p.id);
    }
    this.marcados.set(s);
  }

  /** Cuantos del modulo estan marcados, para el "3 de 14" de la cabecera. */
  protected marcadosDe(m: ModuloDePermisos): number {
    return m.permisos.filter((p) => this.marcados().has(p.id)).length;
  }

  protected malo(campo: string): boolean {
    const c = this.formulario.get(campo);
    return !!c && c.invalid && (c.touched || c.dirty);
  }

  protected guardar(): void {
    if (this.guardando()) return;

    // Todo lo que falta se dice de una vez: el nombre, la descripcion y los permisos.
    if (this.formulario.invalid || this.faltanPermisos() || this.apagaConGente()) {
      this.intentado.set(true);
      this.formulario.markAllAsTouched();
      return;
    }

    this.guardando.set(true);
    this.error.set(null);

    const v = this.formulario.getRawValue();
    const datos = {
      nombre: v.nombre.trim(),
      descripcion: v.descripcion.trim(),
      permisos: [...this.marcados()].sort(),
    };

    const peticion = this.id === null
      ? this.servicio.crear(datos)
      : this.servicio.actualizar(this.id, {
          ...datos,
          activo: v.activo,
          ...(this.seApaga() && v.motivo.trim() ? { motivo: v.motivo.trim() } : {}),
        });

    peticion.subscribe({
      next: (r) => {
        this.guardando.set(false);
        void this.router.navigate(['/roles', r.rolId]);
      },
      error: (e) => {
        this.guardando.set(false);
        this.enUso.set(camposEnUso(e));
        this.error.set(mensajeDeError(e, this.editando ? 'No se pudo guardar' : 'No se pudo crear el rol'));
      },
    });
  }
}
