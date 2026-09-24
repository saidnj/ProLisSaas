import { Injectable, computed, signal } from '@angular/core';
import type { RespuestaSesion } from '../Interfaces/sesion.interface';

const LLAVE = 'prolissaas.sesion';

interface SesionGuardada {
  datos: RespuestaSesion;
  /** En que sede esta parado. null mientras no elija. */
  sucursalId: number | null;
}

/**
 * Guarda quien entro y donde esta parado. Es la unica fuente de la verdad
 * sobre la sesion: el interceptor del token lee de aqui, los guards
 * preguntan aqui, y las pantallas tambien.
 *
 * DECISION PENDIENTE - donde vive el token:
 *   Hoy queda en localStorage para que al recargar (F5) no te eche. Eso lo
 *   hace vulnerable a XSS: si alguien logra meter un script en la pagina,
 *   se lo lleva. La alternativa seria una cookie httpOnly, que el
 *   JavaScript no puede leer, pero obliga al back a manejarla y trae CSRF
 *   como problema nuevo. Para un sistema con datos clinicos hay que
 *   decidirlo en serio antes de salir a produccion.
 */
@Injectable({ providedIn: 'root' })
export class SesionService {
  private readonly _guardada = signal<SesionGuardada | null>(this.leerDelAlmacen());

  readonly autenticado = computed(() => this._guardada() !== null);
  readonly token       = computed(() => this._guardada()?.datos.token ?? null);
  readonly sesion      = computed(() => this._guardada()?.datos ?? null);
  readonly usuario     = computed(() => this._guardada()?.datos.usuario ?? null);
  readonly persona     = computed(() => this._guardada()?.datos.persona ?? null);
  readonly empresa     = computed(() => this._guardada()?.datos.empresa ?? null);
  readonly rol         = computed(() => this._guardada()?.datos.rol ?? null);
  readonly sucursales  = computed(() => this._guardada()?.datos.sucursales ?? []);
  readonly sucursalId  = computed(() => this._guardada()?.sucursalId ?? null);

  /** La sede donde esta parado, entera. null mientras no haya elegido. */
  readonly sucursal = computed(() => {
    const id = this.sucursalId();
    return id === null ? null : this.sucursales().find((s) => s.sucursalId === id) ?? null;
  });

  /**
   * Los permisos EFECTIVOS: los de la sede donde esta parado, no los de la
   * empresa entera.
   *
   * Sin sucursal elegida devuelve lista vacia, y eso es a proposito: falla
   * CERRADO. Mientras no se sepa donde esta parado, no puede hacer nada --
   * que es exactamente la verdad, porque el permiso depende de los modulos
   * que la empresa paga en esa sede.
   */
  readonly permisos = computed(() => this.sucursal()?.permisos ?? []);

  /** Los modulos encendidos en la sede actual. Para esconder secciones. */
  readonly modulos = computed(() => this.sucursal()?.modulos ?? []);

  /** El nombre que va en el encabezado: el de rotulo, no el legal (E-21). */
  readonly nombreEmpresa = computed(() => {
    const e = this.empresa();
    return e ? (e.comercial ?? e.nombre) : '';
  });

  /**
   * Si el usuario tiene un permiso EN LA SEDE DONDE ESTA. Esto es SOLO para
   * la pantalla -- para no mostrar un boton que el servidor va a rechazar.
   *
   * NO ES SEGURIDAD. Esta lista vive en localStorage: cualquiera abre F12 y
   * le agrega 'usuario.administrar'. La pared de verdad la hacen
   * core.usuario_puede() y las politicas RLS, del lado del servidor, y
   * esas no se pueden editar desde el navegador.
   */
  puede(permiso: string): boolean {
    return this.permisos().includes(permiso);
  }

  /** Si la sede actual tiene encendido un modulo. */
  tieneModulo(modulo: string): boolean {
    return this.modulos().includes(modulo);
  }

  /** Recien entro. Si habia una sola sede, el back ya la eligio y la manda. */
  abrir(datos: RespuestaSesion): void {
    this.escribir({ datos, sucursalId: datos.sucursalId });
  }

  /**
   * Eligio sede. Llega con un token NUEVO -- el anterior no lleva sucursal
   * -- y hay que reemplazarlo: si se queda el viejo, el back sigue sin saber
   * donde esta parado y toda operacion que exija sede va a fallar.
   */
  pararseEn(sucursalId: number, tokenNuevo: string): void {
    const actual = this._guardada();
    if (!actual) return;
    this.escribir({
      datos: { ...actual.datos, token: tokenNuevo },
      sucursalId,
    });
  }

  cerrar(): void {
    this._guardada.set(null);
    try {
      localStorage.removeItem(LLAVE);
    } catch {
      /* ignorar */
    }
  }

  private escribir(g: SesionGuardada): void {
    this._guardada.set(g);
    try {
      localStorage.setItem(LLAVE, JSON.stringify(g));
    } catch {
      // Modo privado o almacenamiento lleno: la sesion sigue viva en
      // memoria, solo que no sobrevive a un F5. No es motivo para fallar.
    }
  }

  private leerDelAlmacen(): SesionGuardada | null {
    try {
      const crudo = localStorage.getItem(LLAVE);
      if (!crudo) return null;
      const g = JSON.parse(crudo) as SesionGuardada;
      // Comprobacion minima de forma: si quedo una sesion de una version
      // vieja del front, es mejor empezar de cero que romperse al pintar.
      return g?.datos?.token ? g : null;
    } catch {
      return null;
    }
  }
}
