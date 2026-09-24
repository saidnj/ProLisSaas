import { Component, computed, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { Encabezado } from '../../encabezado/encabezado';
import { CodigoActivacion } from '../codigo/codigo-activacion';
import { EmpleadosService } from '../../../Servicios/empleados.service';
import { CatalogoService } from '../../../Servicios/catalogo.service';
import { SesionService } from '../../../Servicios/sesion.service';
import { mensajeDeError } from '../../../Servicios/errores';
import type { Empleado, EstadoCuenta } from '../../../Interfaces/empleado.interface';
import type { SucursalDeCatalogo } from '../../../Interfaces/catalogo.interface';

/** Como se muestra cada estado de cuenta: texto y color del chip. */
const ESTADOS: Record<EstadoCuenta, { texto: string; clase: 'si' | 'no' | 'gris' | 'info' }> = {
  pendiente_activacion: { texto: 'Pendiente de activacion', clase: 'info' },
  activo:               { texto: 'Activa',                  clase: 'si' },
  bloqueado:            { texto: 'Bloqueada',               clase: 'no' },
  suspendido:           { texto: 'Suspendida',              clase: 'gris' },
};

/**
 * Ver los datos, y desde aqui las acciones sobre la cuenta que no son
 * "editar un campo". Cada estado ofrece las suyas, y todas piden
 * confirmacion en linea -- nada de dialogos del navegador:
 *
 *   pendiente  generar un codigo nuevo (el anterior se anula)
 *   activa     restablecer la clave: la olvido, se le borra, queda fuera
 *              hasta que active con el codigo
 *   bloqueada  desbloquear (la recuerda: entra con la de siempre) o
 *              restablecer (no la recuerda: un solo paso)
 *
 * "Cambiar mi clave" sabiendo la actual NO va aqui: esta pantalla es del
 * administrador. Eso seria de un "mi perfil", pendiente de decidir.
 */
@Component({
  selector: 'app-detalle-empleado',
  imports: [RouterLink, DatePipe, Encabezado, CodigoActivacion],
  templateUrl: './detalle-empleado.html',
  styleUrl: './detalle-empleado.scss',
})
export class DetalleEmpleado {
  private readonly servicio = inject(EmpleadosService);
  private readonly catalogo = inject(CatalogoService);
  private readonly ruta = inject(ActivatedRoute);
  protected readonly sesion = inject(SesionService);

  protected readonly empleado = signal<Empleado | null>(null);
  protected readonly cargando = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly puedeAdministrar = computed(
    () => this.sesion.puede('usuario.administrar'),
  );

  /**
   * Si quien esta sentado puede tocar ESTA cuenta. Misma pregunta que
   * core.puede_tocar_cuenta(): una cuenta corriente la toca cualquiera que
   * administre; la de un administrador o la del propietario, solo el
   * propietario. El back lo vuelve a comprobar; aqui es para no ofrecer
   * un boton que va a fallar.
   */
  protected readonly puedeTocarCuenta = computed(() => {
    const e = this.empleado();
    if (!e || e.usuarioId === null || !this.puedeAdministrar()) return false;
    return (!e.rolEsSistema && !e.rolEsAdmin) || this.sesion.puede('usuario.nombrar_admin');
  });

  /**
   * LA FICHA SIGUE A LA CUENTA: si no puede tocar la cuenta (la del
   * propietario, la de un administrador), tampoco edita la ficha. Sin
   * cuenta (los de antes), la edita quien administre. Aqui va el motivo
   * para no ofrecer el boton; la base lo rechaza igual.
   */
  protected readonly porQueNoFicha = computed(() => {
    const e = this.empleado();
    if (!e || !this.puedeAdministrar() || e.usuarioId === null || this.puedeTocarCuenta()) return null;
    return e.rolEsSistema
      ? 'Los datos del propietario solo los edita el propietario.'
      : 'Solo el propietario edita los datos y la cuenta de un administrador.';
  });

  protected readonly estadoCuenta = computed(() => {
    const e = this.empleado()?.estado;
    return e ? ESTADOS[e] : null;
  });

  /** Que confirmacion esta abierta, si alguna. */
  protected readonly confirmando = signal<'codigo' | 'restablecer' | 'desbloqueo' | null>(null);
  protected readonly trabajando = signal(false);
  /** Error de una accion sobre la cuenta. Va junto a los botones, no tapa la ficha. */
  protected readonly errorCuenta = signal<string | null>(null);
  /** "Desbloqueada": se dice una vez y se va con la siguiente accion. */
  protected readonly nota = signal<string | null>(null);

  protected readonly codigoNuevo = signal<{
    codigo: string; venceEn: string; nombre: string; motivo: 'reemplazo' | 'restablecer';
  } | null>(null);

  protected readonly id = Number(this.ruta.snapshot.paramMap.get('id'));

  private readonly sedes = signal<SucursalDeCatalogo[]>([]);

  /**
   * Los ids de sus sedes, convertidos a codigo y nombre.
   *
   * El back manda ids porque es lo que el formulario necesita para marcar
   * casillas; aqui hacen falta los nombres. Se cruzan en el front y no se le
   * piden al back dos veces la misma cosa en dos formas distintas.
   */
  protected readonly susSedes = computed(() => {
    const ids = this.empleado()?.sucursales;
    if (!ids) return [];
    return this.sedes().filter((s) => ids.includes(s.sucursalId));
  });

  constructor() {
    this.catalogo.sucursales().subscribe({
      next: (s) => this.sedes.set(s),
      error: () => this.sedes.set([]),
    });
    this.cargar();
  }

  private cargar(): void {
    this.servicio.obtener(this.id).subscribe({
      next: (e) => {
        this.empleado.set(e);
        this.cargando.set(false);
      },
      error: (e) => {
        this.error.set(mensajeDeError(e, 'No se encontro ese empleado'));
        this.cargando.set(false);
      },
    });
  }

  protected pedirConfirmacion(que: 'codigo' | 'restablecer' | 'desbloqueo'): void {
    this.errorCuenta.set(null);
    this.nota.set(null);
    this.confirmando.set(que);
  }

  /**
   * El codigo nuevo. Termina en la misma pantalla que al crear la cuenta,
   * con el texto que corresponda: reemplazo si seguia pendiente,
   * restablecer si tenia clave y se le borro.
   */
  protected generarCodigo(): void {
    const e = this.empleado();
    if (!e || e.usuarioId === null || this.trabajando()) return;
    const motivo = e.estado === 'pendiente_activacion' ? 'reemplazo' : 'restablecer';
    this.trabajando.set(true);
    this.servicio.generarCodigo(e.empleadoId).subscribe({
      next: (r) => {
        this.trabajando.set(false);
        this.confirmando.set(null);
        this.codigoNuevo.set({
          codigo: r.codigo,
          venceEn: r.venceEn,
          nombre: e.nombres + ' ' + e.apellidos,
          motivo,
        });
      },
      error: (err) => {
        this.trabajando.set(false);
        this.confirmando.set(null);
        this.errorCuenta.set(mensajeDeError(err, 'No se pudo generar el codigo'));
      },
    });
  }

  /** De bloqueada a activa. La ficha se vuelve a leer para que el chip cambie. */
  protected desbloquear(): void {
    const e = this.empleado();
    if (!e || e.usuarioId === null || this.trabajando()) return;
    this.trabajando.set(true);
    this.servicio.desbloquear(e.empleadoId).subscribe({
      next: () => {
        this.trabajando.set(false);
        this.confirmando.set(null);
        this.nota.set('Cuenta desbloqueada. Entra con la clave de siempre.');
        this.cargar();
      },
      error: (err) => {
        this.trabajando.set(false);
        this.confirmando.set(null);
        this.errorCuenta.set(mensajeDeError(err, 'No se pudo desbloquear'));
      },
    });
  }

  /** "Listo, ya lo entregue": se vuelve a la ficha, releida (si era activa, ahora esta pendiente). */
  protected entregado(): void {
    this.codigoNuevo.set(null);
    this.cargar();
  }
}
