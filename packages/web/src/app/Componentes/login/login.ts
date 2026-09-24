import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../Servicios/auth.service';
import { mensajeDeError } from '../../Servicios/errores';

@Component({
  selector: 'app-login',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './login.html',
  styleUrl: './login.scss',
})
export class Login {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly verClave = signal(false);

  /**
   * Solo usuario y clave.
   *
   * Falta decidir como se sabe la EMPRESA antes de entrar (H-101): el
   * username es unico dentro de la empresa, no en el sistema, asi que el
   * dia que dos laboratorios tengan 'marlon.ochoa' esto es ambiguo.
   *
   * Lo que NO se va a hacer es pedirle el RTN ni el codigo de sucursal en
   * esta pantalla: son datos de otro cliente y son confidenciales. La
   * salida va a ser por subdominio o por correo unico.
   */
  protected readonly formulario = this.fb.nonNullable.group({
    username: ['', [Validators.required, Validators.minLength(3)]],
    password: ['', [Validators.required]],
  });

  protected entrar(): void {
    if (this.formulario.invalid || this.cargando()) {
      this.formulario.markAllAsTouched();
      return;
    }

    this.cargando.set(true);
    this.error.set(null);

    this.auth.entrar(this.formulario.getRawValue()).subscribe({
      next: (r) => {
        this.cargando.set(false);
        // Con una sola sede el back ya la eligio: se entra derecho.
        void this.router.navigate([r.requiereSucursal ? '/elegir-sucursal' : '/inicio']);
      },
      error: (e) => {
        this.cargando.set(false);
        this.error.set(mensajeDeError(e, 'Usuario o clave incorrectos'));
      },
    });
  }
}
