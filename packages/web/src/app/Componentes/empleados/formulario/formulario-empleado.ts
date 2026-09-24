import { Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { NgTemplateOutlet } from '@angular/common';
import { AbstractControl, FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { NgOptionTemplateDirective, NgSelectComponent } from '@ng-select/ng-select';
import { Encabezado } from '../../encabezado/encabezado';
import { CodigoActivacion } from '../codigo/codigo-activacion';
import { EmpleadosService } from '../../../Servicios/empleados.service';
import { CatalogoService } from '../../../Servicios/catalogo.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { camposEnUso, mensajeDeError, type CampoEnUso } from '../../../Servicios/errores';
import type { CambiosCuenta, EmpleadoEntrada } from '../../../Interfaces/empleado.interface';
import type { RolDeCatalogo, SucursalDeCatalogo } from '../../../Interfaces/catalogo.interface';

/**
 * Un rol visto desde las sedes marcadas: que le sirve ahi y que no.
 *
 * Es lo que se le da a ng-select en vez del RolDeCatalogo pelado. La propiedad
 * 'disabled' no es un capricho de nombre: ng-select la lee del item y pinta
 * la opcion gris sin que haya que decirle nada mas.
 */
interface RolEvaluado extends RolDeCatalogo {
  /** Cuantos permisos tiene el rol en total. */
  total: number;
  /** Por cada sede marcada donde el rol pierde algo: que modulos faltan y cuantos permisos se van. */
  parcial: { sede: SucursalDeCatalogo; faltan: string[]; pierde: number }[];
  /** En NINGUNA sede marcada le queda un permiso util. */
  sinUso: boolean;
  /**
   * Por que NO se puede asignar, si no se puede: es el rol del propietario,
   * o es un rol de administrador y quien esta sentado no es el propietario.
   * null = se puede.
   */
  vetado: string | null;
  /** Lo que ng-select lee para pintar la opcion gris: cualquiera de las dos. */
  disabled: boolean;
}

/**
 * CREAR Y EDITAR, EN UNA SOLA PANTALLA.
 *
 * Son el mismo formulario con los mismos campos y las mismas reglas: tenerlos
 * separados significa que el dia que se agregue un campo hay que acordarse de
 * dos sitios, y uno de los dos se olvida.
 *
 * El modulo de empleados ES el de usuarios (1 a 1): todo empleado tiene
 * cuenta, y se pide siempre -- usuario, sedes y rol -- junto con la ficha.
 * Todo va en UNA peticion y UNA transaccion en el back, al crear y al
 * editar: o queda todo o no queda nada.
 *
 *   crear   la persona, su cuenta y sus sedes. Si nace ACTIVO, sale el
 *           codigo de activacion con el que estrena su clave; si nace
 *           inactivo (empieza el mes que viene), la cuenta nace suspendida
 *           y sin codigo -- se le genera desde la ficha cuando lo activen.
 *
 *   editar  la misma pantalla, con la cuenta que ya tiene: el USERNAME,
 *           las SEDES -- lo que mas cambia en el dia a dia -- y el ROL,
 *           con dos limites que pone la base (core.cambiar_rol): el rol
 *           del propietario no se cambia ni se asigna, y a un
 *           administrador (cualquier rol que pueda crear usuarios) solo lo
 *           nombra o retira el propietario. Aqui eso se ve como opciones
 *           grises con su motivo. Si el empleado todavia no tiene cuenta
 *           (los de antes de que fuera obligatoria), la seccion sale vacia
 *           y guardar se la crea, con codigo si queda activo.
 *
 * La casilla "Activo" es del EMPLEADO y manda tambien sobre la cuenta:
 * inactivo = suspendida, no entra (lo hace la base: core.crear_usuario al
 * nacer, trigger tg_empleado_activo despues). No es "con cuenta o sin
 * cuenta": eso no existe.
 *
 * Y en los dos casos se cruza el rol con las sedes marcadas: un rol no es
 * de una sede, pero sus permisos son de modulos y la sede puede tener un
 * modulo apagado. Lo parcial se avisa ("en Valle pierde 11 de 15"); el caso
 * en que NO le queda un permiso en ninguna sede se bloquea, aqui y en el
 * back (comun/rol-en-sedes.ts).
 */
@Component({
  selector: 'app-formulario-empleado',
  // NgOptionTemplateDirective es lo que hace que ng-select USE la plantilla
  // marcada con ng-option-tmp. Sin importarla no hay error: la plantilla se
  // ignora en silencio y las opciones salen con el nombre pelado.
  imports: [
    ReactiveFormsModule, RouterLink, NgTemplateOutlet,
    NgSelectComponent, NgOptionTemplateDirective, Encabezado, CodigoActivacion,
  ],
  templateUrl: './formulario-empleado.html',
  styleUrl: './formulario-empleado.scss',
})
export class FormularioEmpleado {
  
  private readonly fb = inject(FormBuilder);
  private readonly servicio = inject(EmpleadosService);
  private readonly catalogo = inject(CatalogoService);
  private readonly sesion = inject(SesionService);
  private readonly router = inject(Router);
  private readonly ruta = inject(ActivatedRoute);

  private readonly param = this.ruta.snapshot.paramMap.get('id');
  protected readonly id = this.param ? Number(this.param) : null;
  protected readonly editando = this.id !== null;

  protected readonly cargando = signal(this.editando);
  protected readonly guardando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly roles = signal<RolDeCatalogo[]>([]);
  protected readonly sedes = signal<SucursalDeCatalogo[]>([]);

  /** La cuenta del empleado que se esta editando. null si todavia no tiene. */
  protected readonly usuarioId = signal<number | null>(null);
  protected readonly username = signal<string | null>(null);
  /** El rol que ya tiene (al editar no se cambia, pero si se cruza con las sedes). */
  private readonly rolIdActual = signal<number | null>(null);

  /**
   * Las sedes marcadas. Un Set y no un FormArray: lo unico que hace falta es
   * "esta o no esta", y un Set lo dice sin indices que mantener sincronizados
   * con el orden de la lista.
   */
  protected readonly elegidas = signal<ReadonlySet<number>>(new Set());
  private sedesOriginales: ReadonlySet<number> = new Set();

  /**
   * Ya intento guardar una vez. Los "hace falta X" de la cuenta se muestran
   * a partir de ahi, no desde que marca "darle acceso": recibir tres
   * mensajes en rojo antes de haber escrito nada no es ayuda, es ruido.
   * (El aviso del rol por sede no espera: es consecuencia de lo que acaba
   * de marcar, y tiene que verlo en el momento.)
   */
  protected readonly intentado = signal(false);

  /**
   * Lo que ya es de OTRO empleado, campo por campo. Viene del 409 del back
   * (que pregunta antes de escribir con las mismas llaves que los indices
   * unicos de la base): el nombre entero, la identidad, el telefono, el
   * correo, la colegiacion y el usuario no se repiten dentro de la empresa.
   * Se dice que el dato esta en uso, no de quien. Cada aviso se va solo
   * cuando se toca su campo.
   */
  protected readonly enUso = signal<ReadonlySet<CampoEnUso>>(new Set());

  protected readonly codigoNuevo = signal<{
    codigo: string; venceEn: string; empleadoId: number; nombre: string;
  } | null>(null);

  protected readonly titulo = computed(() =>
    this.editando ? 'Editar empleado' : 'Nuevo empleado',
  );

  protected readonly formulario = this.fb.nonNullable.group({
    nombres:   ['', [Validators.required, Validators.maxLength(80)]],
    apellidos: ['', [Validators.required, Validators.maxLength(80)]],
    documento: [''],
    telefono:  [''],
    correo:    ['', [Validators.email]],
    cargo:     [''],
    numeroColegiacion: [''],
    activo:    [true],

    // La cuenta. Los motivos solo al editar.
    username:    [''],
    rolId:       [null as number | null],
    motivo:      [''],
    motivoRol:   [''],
  });

  /**
   * LOS VALORES DEL FORMULARIO, COMO SEÑALES.
   *
   * Un computed solo se recalcula cuando cambia una señal que leyo. El
   * formulario reactivo NO es una señal: leer control.value adentro de un
   * computed lo deja congelado con el primer valor que vio, para siempre.
   * toSignal() convierte el valueChanges de cada control en una señal, y a
   * partir de ahi los computed de abajo se mueven solos con el formulario.
   */
  private readonly usernameEscrito = toSignal(this.formulario.controls.username.valueChanges, {
    initialValue: this.formulario.controls.username.value,
  });
  private readonly rolIdElegido = toSignal(this.formulario.controls.rolId.valueChanges, {
    initialValue: this.formulario.controls.rolId.value,
  });
  protected readonly activoMarcado = toSignal(this.formulario.controls.activo.valueChanges, {
    initialValue: this.formulario.controls.activo.value,
  });

  /**
   * Al editar, si todavia no tiene cuenta: la seccion sale vacia y
   * guardar se la crea. Sin este caso la cuenta siempre esta.
   */
  protected readonly sinCuenta = computed(() => this.editando && this.usuarioId() === null);

  /** Primero las sedes: el rol se elige con ellas a la vista. */
  protected readonly haySedes = computed(() => this.elegidas().size > 0);

  /** Quien esta sentado es el propietario (o tiene su permiso extra). */
  private readonly puedeNombrarAdmin = computed(() => this.sesion.puede('usuario.nombrar_admin'));

  /**
   * Cada rol, cruzado con las sedes marcadas. Se recalcula solo cada vez
   * que se marca o desmarca una casilla, y es lo que ng-select muestra.
   */
  protected readonly rolesEvaluados = computed<RolEvaluado[]>(() => {
    const marcadas = this.sedes().filter((s) => this.elegidas().has(s.sucursalId));

    return this.roles().map((rol) => {
      const total = rol.modulos.reduce((n, m) => n + m.permisos, 0);

      const porSede = marcadas.map((sede) => {
        const faltan = rol.modulos.filter((m) => !sede.modulos.includes(m.id));
        return {
          sede,
          faltan: faltan.map((m) => m.nombre),
          pierde: faltan.reduce((n, m) => n + m.permisos, 0),
        };
      });

      // Le sirve en una sede si ahi le queda AL MENOS un permiso. Un rol
      // sin permisos (total 0) no sirve en ninguna, y eso es correcto.
      const sirveEnAlguna = porSede.some((x) => x.pierde < total);
      const sinUso = marcadas.length > 0 && !sirveEnAlguna;

      // Lo que la base va a rechazar de todos modos (core.cambiar_rol y
      // core.crear_usuario). Se dice aqui, antes, con el motivo.
      const vetado = rol.esSistema
        ? 'Es el rol del propietario: no se asigna, se traspasa'
        : rol.esAdmin && !this.puedeNombrarAdmin()
          ? 'Solo el propietario nombra administradores'
          : null;

      return {
        ...rol,
        total,
        parcial: porSede.filter((x) => x.pierde > 0),
        sinUso,
        vetado,
        disabled: sinUso || vetado !== null,
      };
    });
  });

  /** El rol que esta en el desplegable (al editar arranca con el que ya tiene). */
  protected readonly rolElegido = computed(() => {
    const id = this.rolIdElegido();
    return id === null ? null : (this.rolesEvaluados().find((r) => r.rolId === id) ?? null);
  });

  /** El que ya tiene, evaluado. Solo al editar. */
  private readonly rolActual = computed(() => {
    const id = this.rolIdActual();
    return id === null ? null : (this.rolesEvaluados().find((r) => r.rolId === id) ?? null);
  });

  /** Al editar: se esta pidiendo un rol distinto del que tiene. */
  protected readonly rolCambia = computed(
    () => this.editando && this.rolIdActual() !== null && this.rolIdElegido() !== this.rolIdActual(),
  );

  /**
   * Al editar, si quien esta sentado puede tocar la CUENTA de esta persona
   * (sus sedes, su rol). Es la misma pregunta que core.puede_tocar_cuenta():
   * una cuenta corriente la toca cualquiera que administre; la de un
   * administrador o la del propietario, solo el propietario.
   */
  protected readonly puedeTocarCuenta = computed(() => {
    const r = this.rolActual();
    if (!this.editando) return false;
    if (this.usuarioId() === null || !r) return true;   // sin cuenta se crea; sin roles cargados, que lo diga el back
    return (!r.esSistema && !r.esAdmin) || this.puedeNombrarAdmin();
  });

  /**
   * LA FICHA SIGUE A LA CUENTA. Si quien esta sentado no puede tocar la
   * cuenta de esta persona (la del propietario, la de un administrador),
   * tampoco edita su ficha: el correo y el telefono son el camino por donde
   * llega el codigo que restablece una clave. Aqui va el motivo, o null si
   * se puede. La base lo rechaza igual (rls_empleado_editar,
   * core.puede_tocar_ficha).
   */
  protected readonly porQueNoFicha = computed(() => {
    const r = this.rolActual();
    if (!this.editando || this.usuarioId() === null || !r || this.puedeTocarCuenta()) return null;
    return r.esSistema
      ? 'Los datos del propietario solo los edita el propietario.'
      : 'Solo el propietario edita los datos y la cuenta de un administrador.';
  });

  /**
   * Y si ademas se le puede cambiar el ROL. Depende del que tiene, no del
   * nuevo: el del propietario no se cambia ni por el propietario mismo.
   */
  protected readonly puedeCambiarRol = computed(
    () => this.puedeTocarCuenta() && !(this.rolActual()?.esSistema ?? false),
  );

  /** Y si no se puede, por que. Para decirlo junto a lo que quedo bloqueado. */
  protected readonly porQueNoCambia = computed(() => {
    const r = this.rolActual();
    if (!r || this.puedeCambiarRol()) return null;
    return r.esSistema
      ? 'Este rol no puede ser revocado, si desea revocarlo ponerse en contacto con soporte.'
      : 'Solo el propietario cambia el rol y las sedes de un administrador.';
  });

  /** El rol no puede hacer nada en ninguna de las sedes marcadas. Bloquea guardar. */
  protected readonly rolSinUso = computed(() => this.rolElegido()?.sinUso ?? false);

  /**
   * Se esta ASIGNANDO (al crear, o al editar con rol distinto) un rol que la
   * base va a rechazar. Con el rol que ya tiene no aplica: que un
   * administrador edite la ficha de otro administrador es legitimo, lo que
   * no puede es cambiarle el rol.
   */
  protected readonly rolVetado = computed(() => {
    const r = this.rolElegido();
    if (!r?.vetado) return null;
    return !this.editando || this.rolCambia() ? r.vetado : null;
  });

  /** Se desmarco alguna que estaba: ahi tiene sentido preguntar por que. */
  protected readonly hayRetiros = computed(() =>
    [...this.sedesOriginales].some((s) => !this.elegidas().has(s)),
  );

  protected readonly faltaUsuario = computed(
    () => this.usernameEscrito().trim().length < 3,
  );

  /** Al editar: el username escrito no es el que tiene. */
  protected readonly usernameCambia = computed(
    () => this.editando && this.usuarioId() !== null &&
          this.usernameEscrito().trim().toLowerCase() !== (this.username() ?? ''),
  );

  protected readonly faltaRol = computed(() => !Number(this.rolIdElegido()));

  protected readonly faltanSedes = computed(() => this.elegidas().size === 0);

  constructor() {
    // Cada aviso de "en uso" se borra al tocar su campo: es sobre lo que se
    // escribio, no una marca que se queda.
    const c = this.formulario.controls;
    const campoDe: [AbstractControl, CampoEnUso][] = [
      [c.nombres, 'nombre'], [c.apellidos, 'nombre'], [c.documento, 'documento'],
      [c.telefono, 'telefono'], [c.correo, 'correo'], [c.numeroColegiacion, 'colegiacion'],
      [c.username, 'username'],
    ];
    for (const [control, campo] of campoDe) {
      control.valueChanges.subscribe(() => {
        if (this.enUso().has(campo)) {
          const resto = new Set(this.enUso());
          resto.delete(campo);
          this.enUso.set(resto);
        }
      });
    }

    // Las sedes hacen falta en los dos casos: al crear para elegirlas, al
    // editar para poder cambiarlas.
    this.catalogo.sucursales().subscribe({
      next: (s) => this.sedes.set(s),
      error: () => this.sedes.set([]),
    });

    if (this.id !== null) {
      this.servicio.obtener(this.id).subscribe({
        next: (e) => {
          this.formulario.patchValue({
            nombres: e.nombres,
            apellidos: e.apellidos,
            // Los nulos de la base se vuelven '' en el formulario: un input
            // con null adentro se queda pegado y Angular se queja.
            documento: e.documento ?? '',
            telefono: e.telefono ?? '',
            correo: e.correo ?? '',
            cargo: e.cargo ?? '',
            numeroColegiacion: e.numeroColegiacion ?? '',
            activo: e.activo,
          });
          this.usuarioId.set(e.usuarioId);
          this.username.set(e.username);
          this.rolIdActual.set(e.rolId);
          this.formulario.patchValue({ rolId: e.rolId, username: e.username ?? '' });
          this.sedesOriginales = new Set(e.sucursales ?? []);
          this.elegidas.set(new Set(this.sedesOriginales));
          this.cargando.set(false);

          // Los roles hacen falta tambien al editar: para cambiarlo, y para
          // saber que le queda del suyo en cada sede que se le marque.
          this.cargarRoles();
        },
        error: (e) => {
          this.error.set(mensajeDeError(e, 'No se encontro ese empleado'));
          this.cargando.set(false);
        },
      });
    } else {
      this.cargarRoles();
    }
  }

  private cargarRoles(): void {
    this.catalogo.roles().subscribe({
      next: (r) => this.roles.set(r),
      error: () => this.roles.set([]),
    });
  }

  protected alternarSede(id: number): void {
    const s = new Set(this.elegidas());
    if (s.has(id)) s.delete(id); else s.add(id);
    this.elegidas.set(s);
  }

  protected malo(campo: string): boolean {
    const c = this.formulario.get(campo);
    return !!c && c.invalid && (c.touched || c.dirty);
  }

  protected terminar(): void {
    const c = this.codigoNuevo();
    void this.router.navigate(['/empleados', c ? c.empleadoId : '']);
  }

  protected guardar(): void {
    if (this.guardando()) return;

    // Todo lo que falta se dice de una vez -- la ficha y la cuenta -- y no
    // en dos rondas: primero "falta el nombre" y, ya con nombre, "falta el
    // usuario".
    const faltaFicha = this.formulario.invalid;
    const faltaCuenta =
      this.faltaUsuario() || this.faltaRol() || this.faltanSedes() ||
      this.rolSinUso() || this.rolVetado() !== null;
    if (faltaFicha || faltaCuenta) {
      this.intentado.set(true);
      this.formulario.markAllAsTouched();
      return;
    }

    this.guardando.set(true);
    this.error.set(null);

    const v = this.formulario.getRawValue();

    // Al reves que al cargar: '' vuelve a ser null. Un texto vacio en la base
    // es un dato que dice "esto esta en blanco"; null dice "no se sabe". No
    // son lo mismo, y mezclarlos ensucia las consultas para siempre.
    const datos: EmpleadoEntrada = {
      nombres: v.nombres.trim(),
      apellidos: v.apellidos.trim(),
      documento: v.documento.trim() || null,
      telefono: v.telefono.trim() || null,
      correo: v.correo.trim() || null,
      cargo: v.cargo.trim() || null,
      numeroColegiacion: v.numeroColegiacion.trim() || null,
      activo: v.activo,
    };

    if (this.id !== null) {
      this.guardarEdicion(this.id, datos, {
        username: v.username.trim().toLowerCase(),
        rolId: Number(v.rolId),
        motivoRol: v.motivoRol.trim(),
        motivoSedes: v.motivo.trim(),
      });
      return;
    }

    this.servicio
      .crear({
        ...datos,
        cuenta: {
          username: v.username.trim().toLowerCase(),
          rolId: Number(v.rolId),
          sucursales: [...this.elegidas()],
        },
      })
      .subscribe({
        next: (e) => {
          this.guardando.set(false);

          // Si vino codigo, NO se navega: hay que mostrarlo primero, porque
          // de la base solo sale el hash y no hay segunda oportunidad.
          // Si nacio inactivo no hay codigo (la cuenta nace suspendida) y
          // se va derecho a la ficha.
          if (e.activacion) {
            this.codigoNuevo.set({
              codigo: e.activacion.codigo,
              venceEn: e.activacion.venceEn,
              empleadoId: e.empleadoId,
              nombre: e.nombres + ' ' + e.apellidos,
            });
            return;
          }

          void this.router.navigate(['/empleados', e.empleadoId]);
        },
        error: (e) => {
          this.guardando.set(false);
          this.enUso.set(camposEnUso(e));
          this.error.set(mensajeDeError(e, 'No se pudo crear el empleado'));
        },
      });
  }

  /**
   * Editar es UNA peticion: la ficha y la cuenta tal como esta en
   * pantalla, igual que crear. El back lo corre en una transaccion -- o
   * cambia todo o no cambia nada -- y no escribe lo que vino igual, asi
   * que aqui no se comparan valores. Lo unico que se mira es si hubo
   * cambio para mandar el motivo, porque un motivo sin cambio no significa
   * nada. Si el empleado no tenia cuenta, el back se la crea con esto
   * mismo y devuelve el codigo: se muestra antes de ir a la ficha.
   *
   * Lo que esta BLOQUEADO en pantalla no se manda, ni igual: el rol del
   * propietario. Tocar eso es de quien puede, venga cambiado o no, y el
   * back lo rechaza. (La cuenta de un administrador, cuando quien edita no
   * es el propietario, ya no llega hasta aqui: la ficha entera sigue a la
   * cuenta y el formulario no se dibuja.)
   *
   * Cada cosa de la cuenta sigue dejando su propio evento en la bitacora
   * (rol, username, sedes), asi que en la auditoria se distinguen igual.
   */
  private guardarEdicion(
    id: number,
    datos: EmpleadoEntrada,
    cuenta: { username: string; rolId: number; motivoRol: string; motivoSedes: string },
  ): void {
    const cambios: CambiosCuenta | undefined =
      !this.puedeTocarCuenta()
        ? undefined
        : {
            username: cuenta.username,
            sucursales: [...this.elegidas()],
            ...(this.puedeCambiarRol() ? { rolId: cuenta.rolId } : {}),
            ...(this.rolCambia() && cuenta.motivoRol ? { motivoRol: cuenta.motivoRol } : {}),
            ...(this.hayRetiros() && cuenta.motivoSedes ? { motivoSedes: cuenta.motivoSedes } : {}),
          };

    this.servicio.actualizar(id, datos, cambios).subscribe({
      next: (e) => {
        this.guardando.set(false);
        if (e.activacion) {
          this.codigoNuevo.set({
            codigo: e.activacion.codigo,
            venceEn: e.activacion.venceEn,
            empleadoId: id,
            nombre: e.nombres + ' ' + e.apellidos,
          });
          return;
        }
        void this.router.navigate(['/empleados', id]);
      },
      error: (e) => {
        this.guardando.set(false);
        this.enUso.set(camposEnUso(e));
        this.error.set(mensajeDeError(e, 'No se pudo guardar'));
      },
    });
  }
}
