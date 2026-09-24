import { Component, computed, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { DatePipe } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { PacientesService } from '../../../Servicios/pacientes.service';
import { camposEnUso, mensajeDeError, type CampoEnUso } from '../../../Servicios/errores';
import { aIso, edadDe, edadTexto, fechaEstimadaDe, fechaLocal, hoy } from '../edad';
import { SEXOS, TIPOS_DOCUMENTO } from '../../../Interfaces/paciente.interface';
import type { PacienteCompleto, PacienteEntrada, Sexo, TipoDocumento } from '../../../Interfaces/paciente.interface';

/**
 * REGISTRAR Y EDITAR UN PACIENTE, EN UNA SOLA PANTALLA. Mismo molde que
 * los formularios de empleados y roles: la ficha entera en UNA peticion;
 * al guardar, lo que vino igual no se escribe.
 *
 * LA FECHA DE NACIMIENTO O LA EDAD, NUNCA LAS DOS. La base no guarda la
 * edad: guarda la fecha. Lo normal es poner la fecha. Si no se sabe (un
 * adulto mayor sin documento, un bebe que traen sin partida), hay que
 * apretar un boton para pasar a "poner la edad": ahi la fecha se calcula
 * (hoy menos la edad) y queda marcada como ESTIMADA, y la pantalla lo dice
 * antes de guardar, con la fecha que va a quedar. El boton es a proposito:
 * que la edad sea un camino aparte, y no un campo mas que se llena por
 * costumbre.
 *
 * Al editar:
 *   - fecha CONFIRMADA: no hay boton. Se corrige la fecha, no se estima
 *     (la base lo rechaza aunque alguien lo mande a mano).
 *   - fecha ESTIMADA: se ve el aviso, y hay dos salidas: poner la fecha
 *     real (deja de ser estimada, para siempre) o volver a estimar con
 *     otra edad. Guardar sin tocarla la deja como esta.
 */
@Component({
  selector: 'app-formulario-paciente',
  imports: [ReactiveFormsModule, RouterLink, DatePipe, Encabezado],
  templateUrl: './formulario-paciente.html',
  styleUrl: './formulario-paciente.scss',
})
export class FormularioPaciente {
  private readonly fb = inject(FormBuilder);
  private readonly servicio = inject(PacientesService);
  private readonly router = inject(Router);
  private readonly ruta = inject(ActivatedRoute);

  private readonly param = this.ruta.snapshot.paramMap.get('id');
  protected readonly id = this.param ? Number(this.param) : null;
  protected readonly editando = this.id !== null;

  protected readonly tiposDocumento = TIPOS_DOCUMENTO;
  protected readonly sexos = SEXOS;
  /** Tope del <input type="date">: nadie nace manana. */
  protected readonly hoyIso = aIso(hoy());

  protected readonly cargando = signal(this.editando);
  protected readonly guardando = signal(false);
  protected readonly error = signal<string | null>(null);

  /** El paciente que se esta editando, tal como vino. null al crear. */
  protected readonly paciente = signal<PacienteCompleto | null>(null);

  /** true = se pone la edad y la fecha se calcula. false = se pone la fecha. */
  protected readonly modoEdad = signal(false);

  /** Ya intento guardar: los "hace falta" se muestran a partir de ahi. */
  protected readonly intentado = signal(false);

  /** El documento ya es de otro expediente (409 del back). Se va al tocar el campo. */
  protected readonly enUso = signal<ReadonlySet<CampoEnUso>>(new Set());
  /** Lo que dijo el back: trae el expediente que ya tiene ese documento. */
  protected readonly mensajeEnUso = signal('');

  protected readonly titulo = computed(() => (this.editando ? 'Editar paciente' : 'Registrar paciente'));

  protected readonly formulario = this.fb.nonNullable.group({
    nombreCompleto:  ['', [Validators.required, Validators.minLength(2), Validators.maxLength(120)]],
    tipoDocumento:   ['ninguno' as TipoDocumento],
    documento:       ['', [Validators.maxLength(40)]],
    fechaNacimiento: [''],
    edadAnios:       [null as number | null, [Validators.min(0), Validators.max(130)]],
    edadMeses:       [null as number | null, [Validators.min(0), Validators.max(11)]],
    sexo:            ['' as Sexo | '', [Validators.required]],
    telefono:        ['', [Validators.maxLength(30)]],
    correo:          ['', [Validators.email]],
    direccion:       ['', [Validators.maxLength(200)]],
  });

  // Los valores del formulario como senales, para que los computed de
  // abajo se muevan con el (ver el formulario de empleados).
  private readonly tipoElegido = toSignal(this.formulario.controls.tipoDocumento.valueChanges, {
    initialValue: this.formulario.controls.tipoDocumento.value,
  });
  private readonly documentoEscrito = toSignal(this.formulario.controls.documento.valueChanges, {
    initialValue: this.formulario.controls.documento.value,
  });
  private readonly fechaEscrita = toSignal(this.formulario.controls.fechaNacimiento.valueChanges, {
    initialValue: this.formulario.controls.fechaNacimiento.value,
  });
  private readonly aniosEscritos = toSignal(this.formulario.controls.edadAnios.valueChanges, {
    initialValue: this.formulario.controls.edadAnios.value,
  });
  private readonly mesesEscritos = toSignal(this.formulario.controls.edadMeses.valueChanges, {
    initialValue: this.formulario.controls.edadMeses.value,
  });

  /** Con tipo de documento hace falta el numero. */
  protected readonly conDocumento = computed(() => this.tipoElegido() !== 'ninguno');
  protected readonly faltaDocumento = computed(
    () => this.conDocumento() && !this.documentoEscrito().trim(),
  );

  /** La fecha escrita, si tiene forma de fecha y no es futura ni anterior a 1900. */
  private readonly fechaValida = computed(() => {
    const f = fechaLocal(this.fechaEscrita());
    return !!f && f <= hoy() && f.getFullYear() >= 1900;
  });
  /** Por que no sirve la fecha, si no sirve. null = sirve (o esta vacia). */
  protected readonly problemaFecha = computed(() => {
    const texto = this.fechaEscrita();
    if (!texto) return null;
    const f = fechaLocal(texto);
    if (!f) return 'Esa fecha no es valida';
    if (f > hoy()) return 'La fecha de nacimiento no puede ser futura';
    if (f.getFullYear() < 1900) return 'Esa fecha no es valida';
    return null;
  });
  protected readonly faltaFecha = computed(() => !this.modoEdad() && !this.fechaValida());

  /** En modo edad: al menos una de las dos, dentro de rango. */
  protected readonly faltaEdad = computed(() => {
    if (!this.modoEdad()) return false;
    const a = this.aniosEscritos();
    const m = this.mesesEscritos();
    if (a === null && m === null) return true;
    return this.formulario.controls.edadAnios.invalid || this.formulario.controls.edadMeses.invalid;
  });

  /**
   * La fecha que va a calcular la base con la edad escrita, para verla
   * ANTES de guardar. Es la misma cuenta (hoy menos anios y meses).
   */
  protected readonly fechaPrevista = computed(() => {
    if (!this.modoEdad() || this.faltaEdad()) return null;
    return fechaEstimadaDe(this.aniosEscritos() ?? 0, this.mesesEscritos() ?? 0);
  });

  /** La edad que sale de la fecha escrita, para confirmarla con la vista ("nacio en 2004: 21 años"). */
  protected readonly edadDeLaFecha = computed(() =>
    !this.modoEdad() && this.fechaValida() ? edadTexto(edadDe(this.fechaEscrita())) : '',
  );

  /** Al editar, la fecha que tiene es estimada: hay aviso y se puede re-estimar. */
  protected readonly esEstimada = computed(() => this.paciente()?.fechaEstimada === true);
  /** La edad que tiene hoy con la fecha guardada (para el aviso de estimada). */
  protected readonly edadActual = computed(() => {
    const p = this.paciente();
    return p ? edadTexto(edadDe(p.fechaNacimiento)) : '';
  });
  /** Al editar una estimada y escribir OTRA fecha: va a quedar confirmada. Se avisa. */
  protected readonly vaAConfirmar = computed(() => {
    const p = this.paciente();
    return !!p && p.fechaEstimada && !this.modoEdad() && this.fechaValida()
      && this.fechaEscrita() !== p.fechaNacimiento;
  });

  /** Se puede pasar a "poner la edad": al crear siempre; al editar, solo si la fecha es estimada. */
  protected readonly puedeEstimar = computed(() => !this.editando || this.esEstimada());

  constructor() {
    // Sin tipo de documento no hay numero: el campo se apaga y se vacia.
    this.formulario.controls.tipoDocumento.valueChanges.subscribe((t) => {
      const doc = this.formulario.controls.documento;
      if (t === 'ninguno') { doc.setValue(''); doc.disable(); } else { doc.enable(); }
    });
    this.formulario.controls.documento.disable();

    this.formulario.controls.documento.valueChanges.subscribe(() => {
      if (this.enUso().size) { this.enUso.set(new Set()); this.mensajeEnUso.set(''); }
    });
    this.formulario.controls.tipoDocumento.valueChanges.subscribe(() => {
      if (this.enUso().size) { this.enUso.set(new Set()); this.mensajeEnUso.set(''); }
    });

    if (this.id !== null) {
      this.servicio.obtener(this.id).subscribe({
        next: (p) => {
          this.paciente.set(p);
          this.formulario.patchValue({
            nombreCompleto: p.nombreCompleto,
            tipoDocumento: p.tipoDocumento,
            documento: p.documento ?? '',
            fechaNacimiento: p.fechaNacimiento,
            sexo: p.sexo,
            telefono: p.telefono ?? '',
            correo: p.correo ?? '',
            direccion: p.direccion ?? '',
          });
          this.cargando.set(false);
        },
        error: (e) => {
          this.error.set(mensajeDeError(e, 'No se encontro ese paciente'));
          this.cargando.set(false);
        },
      });
    }
  }

  /**
   * Pasar a "poner la edad". La fecha se vacia: nunca van las dos. Al
   * editar una estimada, se arranca con la edad que sale de la fecha que
   * tiene, para corregirla y no escribirla de cero.
   */
  protected ponerEdad(): void {
    const p = this.paciente();
    const e = p?.fechaEstimada ? edadDe(p.fechaNacimiento) : null;
    this.formulario.patchValue({
      fechaNacimiento: '',
      edadAnios: e ? e.anios : null,
      edadMeses: e ? e.meses : null,
    });
    this.modoEdad.set(true);
  }

  /** Volver a "poner la fecha". La edad se vacia. */
  protected ponerFecha(): void {
    const p = this.paciente();
    this.formulario.patchValue({
      fechaNacimiento: p?.fechaEstimada ? p.fechaNacimiento : '',
      edadAnios: null,
      edadMeses: null,
    });
    this.modoEdad.set(false);
  }

  protected malo(campo: string): boolean {
    const c = this.formulario.get(campo);
    return !!c && c.invalid && (c.touched || c.dirty || this.intentado());
  }

  protected guardar(): void {
    if (this.guardando()) return;

    // Todo lo que falta se dice de una vez.
    if (this.formulario.invalid || this.faltaDocumento() || this.faltaFecha() || this.faltaEdad()) {
      this.intentado.set(true);
      this.formulario.markAllAsTouched();
      return;
    }

    this.guardando.set(true);
    this.error.set(null);

    const v = this.formulario.getRawValue();
    const conEdad = this.modoEdad();
    const datos: PacienteEntrada = {
      nombreCompleto:  v.nombreCompleto.trim(),
      tipoDocumento:   v.tipoDocumento,
      documento:       v.tipoDocumento === 'ninguno' ? null : v.documento.trim() || null,
      fechaNacimiento: conEdad ? null : v.fechaNacimiento,
      edadAnios:       conEdad ? (v.edadAnios ?? 0) : null,
      edadMeses:       conEdad ? (v.edadMeses ?? 0) : null,
      sexo:            v.sexo as Sexo,
      telefono:        v.telefono.trim() || null,
      correo:          v.correo.trim() || null,
      direccion:       v.direccion.trim() || null,
    };

    const peticion = this.id === null
      ? this.servicio.crear(datos)
      : this.servicio.actualizar(this.id, datos);

    peticion.subscribe({
      next: (p) => {
        this.guardando.set(false);
        void this.router.navigate(['/pacientes', p.pacienteId]);
      },
      error: (e) => {
        this.guardando.set(false);
        const campos = camposEnUso(e);
        this.enUso.set(campos);
        const mensaje = mensajeDeError(e, this.editando ? 'No se pudo guardar' : 'No se pudo registrar el paciente');
        // Si el back marco el campo, el mensaje va junto al campo y no arriba.
        if (campos.size) { this.mensajeEnUso.set(mensaje); } else { this.error.set(mensaje); }
      },
    });
  }
}
