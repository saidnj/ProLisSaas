import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { PacientesService } from '../../../Servicios/pacientes.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import { edadDe, edadTexto, fechaLocal } from '../edad';
import { textoSexo, textoTipoDocumento } from '../../../Interfaces/paciente.interface';
import type { PacienteCompleto } from '../../../Interfaces/paciente.interface';

/**
 * LA FICHA DE UN PACIENTE: el expediente y sus datos, tal como estan. La
 * edad sale de la fecha (no se guarda); si la fecha es estimada, se dice.
 *
 * "Crear boleta" esta apagado: las boletas (ordenes) todavia no existen.
 * El boton esta para que se vea donde va a estar.
 */
@Component({
  selector: 'app-detalle-paciente',
  imports: [RouterLink, DatePipe, Encabezado],
  templateUrl: './detalle-paciente.html',
  styleUrl: './detalle-paciente.scss',
})
export class DetallePaciente {
  private readonly servicio = inject(PacientesService);
  private readonly ruta = inject(ActivatedRoute);
  protected readonly sesion = inject(SesionService);

  protected readonly paciente = signal<PacienteCompleto | null>(null);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly puedeEditar = computed(() => this.sesion.puede('paciente.editar'));

  protected readonly edad = computed(() => {
    const p = this.paciente();
    return p ? edadTexto(edadDe(p.fechaNacimiento)) : '';
  });

  /** La fecha como Date local, para el DatePipe (un string 'AAAA-MM-DD' lo tomaria como UTC). */
  protected readonly fechaNacimiento = computed(() => fechaLocal(this.paciente()?.fechaNacimiento));

  protected readonly documento = computed(() => {
    const p = this.paciente();
    return p?.documento ? `${textoTipoDocumento(p.tipoDocumento)} ${p.documento}` : '';
  });

  protected readonly sexo = computed(() => {
    const p = this.paciente();
    return p ? textoSexo(p.sexo) : '';
  });

  constructor() {
    const id = Number(this.ruta.snapshot.paramMap.get('id'));

    this.servicio.obtener(id).subscribe({
      next: (p) => {
        this.paciente.set(p);
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se encontro ese paciente'));
        this.cargando.set(false);
      },
    });
  }
}
