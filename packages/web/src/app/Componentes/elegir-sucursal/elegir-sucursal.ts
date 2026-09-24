import { Component, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../Servicios/auth.service';
import { SesionService } from '../../Servicios/sesion.service';
import { mensajeDeError } from '../../Servicios/errores';

/**
 * DONDE VAS A TRABAJAR HOY.
 *
 * No es un adorno: los permisos dependen de la sede. El rol dice lo que se
 * quiso dar; los modulos que la empresa paga en ESA sede dicen lo que de
 * verdad rinde. El mismo rol de 30 permisos rinde 30 donde lab_clinico esta
 * encendido y 16 donde esta apagado.
 *
 * Por eso elegir sede devuelve un token NUEVO con la sucursal firmada
 * adentro, y no una casilla que el front se guarda por su cuenta: lo que el
 * navegador manda, el navegador lo cambia.
 *
 * Con una sola sede esta pantalla no se muestra nunca -- el back la elige
 * solo y el login entra derecho.
 */
@Component({
  selector: 'app-elegir-sucursal',
  imports: [],
  templateUrl: './elegir-sucursal.html',
  styleUrl: './elegir-sucursal.scss',
})
export class ElegirSucursal {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly sesion = inject(SesionService);

  protected readonly eligiendo = signal<number | null>(null);
  protected readonly error = signal<string | null>(null);

  protected elegir(sucursalId: number): void {
    if (this.eligiendo() !== null) return;

    this.eligiendo.set(sucursalId);
    this.error.set(null);

    this.auth.elegirSucursal(sucursalId).subscribe({
      next: () => {
        this.eligiendo.set(null);
        void this.router.navigate(['/inicio']);
      },
      error: (e) => {
        this.eligiendo.set(null);
        this.error.set(mensajeDeError(e, 'No se pudo entrar a esa sucursal'));
      },
    });
  }

  protected salir(): void {
    this.auth.salir();
  }
}
