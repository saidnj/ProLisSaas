import { Component, DestroyRef, computed, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { RouterLink } from '@angular/router';
import { Subject, catchError, debounceTime, filter, map, of, switchMap } from 'rxjs';
import { Encabezado } from '../../encabezado/encabezado';
import { PacientesService } from '../../../Servicios/pacientes.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import { edadCorta, edadDe } from '../edad';
import { textoTipoDocumento } from '../../../Interfaces/paciente.interface';
import type { Paciente } from '../../../Interfaces/paciente.interface';

/** Cuanto se espera despues de la ultima tecla antes de preguntar al API. */
const ESPERA_MS = 400;

/**
 * LA LISTA DE PACIENTES. Al entrar salen los ultimos 50 registrados; el
 * buscador pregunta al API (no filtra en memoria: la empresa puede tener
 * miles), por nombre, expediente o documento, y el API los devuelve por
 * parecido y ordenados por coincidencia.
 *
 * EL BUSCADOR NO PREGUNTA EN CADA TECLA. Cada tecla entra a un Subject;
 * debounceTime espera a que la persona deje de escribir ESPERA_MS (si
 * vuelve a teclear, el reloj arranca de nuevo) y recien ahi sale UNA
 * peticion. switchMap tira la anterior si todavia no volvio: la lista nunca
 * muestra la respuesta de un texto viejo.
 *
 * El circulo que gira mientras se escribe es retroalimentacion, no una
 * barra de progreso real: se enciende con la primera tecla y se apaga
 * cuando la peticion que si se hizo responde (o cuando no hacia falta
 * hacerla porque el texto quedo igual).
 */
@Component({
  selector: 'app-lista-pacientes',
  imports: [RouterLink, Encabezado],
  templateUrl: './lista-pacientes.html',
  styleUrl: './lista-pacientes.scss',
})
export class ListaPacientes {
  private readonly servicio = inject(PacientesService);
  private readonly destruir = inject(DestroyRef);
  protected readonly sesion = inject(SesionService);

  protected readonly pacientes = signal<Paciente[]>([]);
  /** La primera carga: se muestra "Cargando..." en vez de la tabla. */
  protected readonly cargando = signal(true);
  /** Se esta escribiendo o esperando la respuesta: el circulo gira. */
  protected readonly buscando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly busqueda = signal('');
  /** El texto de la ultima respuesta que se mostro ('' = los ultimos registrados). */
  protected readonly buscado = signal('');

  protected readonly puedeCrear = computed(() => this.sesion.puede('paciente.crear'));
  protected readonly puedeEditar = computed(() => this.sesion.puede('paciente.editar'));

  private readonly teclas$ = new Subject<string>();
  private ultimoPedido = '';

  constructor() {
    this.teclas$
      .pipe(
        debounceTime(ESPERA_MS),
        map((t) => t.trim()),
        // El mismo texto de la ultima peticion (escribio una letra y la
        // borro): no se vuelve a preguntar, y el circulo se apaga aqui,
        // porque no va a haber respuesta que lo apague.
        filter((t) => {
          if (t === this.ultimoPedido) { this.buscando.set(false); return false; }
          return true;
        }),
        switchMap((t) => {
          this.ultimoPedido = t;
          return this.servicio.buscar(t).pipe(
            map((lista) => ({ t, lista, error: null as string | null })),
            catchError((e) => of({ t, lista: [] as Paciente[], error: mensajeDeError(e, 'No se pudo buscar') })),
          );
        }),
        takeUntilDestroyed(this.destruir),
      )
      .subscribe(({ t, lista, error }) => {
        this.pacientes.set(lista);
        this.buscado.set(t);
        this.error.set(error);
        this.buscando.set(false);
        this.cargando.set(false);
      });

    this.cargarRecientes();
  }

  /** Cada tecla: el circulo arranca ya; la peticion, cuando deje de escribir. */
  protected alEscribir(texto: string): void {
    this.busqueda.set(texto);
    this.buscando.set(true);
    this.teclas$.next(texto);
  }

  protected limpiar(): void {
    this.busqueda.set('');
    this.buscando.set(true);
    this.teclas$.next('');
  }

  /** Los ultimos registrados, sin pasar por la espera del buscador. */
  protected cargarRecientes(): void {
    this.cargando.set(true);
    this.error.set(null);
    this.ultimoPedido = '';
    this.servicio.buscar().subscribe({
      next: (lista) => {
        this.pacientes.set(lista);
        this.buscado.set('');
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se pudo traer la lista de pacientes'));
        this.cargando.set(false);
      },
    });
  }

  protected edad(p: Paciente): string {
    return edadCorta(edadDe(p.fechaNacimiento));
  }

  protected tipoDocumento(p: Paciente): string {
    return textoTipoDocumento(p.tipoDocumento);
  }
}
