import { Component, inject, signal } from '@angular/core';
import {
  AbstractControl, FormBuilder, ReactiveFormsModule, ValidationErrors, Validators,
} from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { AuthService } from '../../Servicios/auth.service';
import { mensajeDeError } from '../../Servicios/errores';

/** Las dos claves tienen que coincidir. Se valida en el grupo, no en el campo. */
function clavesIguales(grupo: AbstractControl): ValidationErrors | null {
  const a = grupo.get('claveNueva')?.value;
  const b = grupo.get('claveRepetida')?.value;
  return a && b && a !== b ? { noCoinciden: true } : null;
}

/**
 * ESTRENAR LA CLAVE.
 *
 * El administrador crea el usuario y la base genera un codigo de un solo
 * uso (K7M2-9QXF). El administrador se lo entrega a la persona por donde
 * sea -- en mano, por telefono -- y la persona lo cambia aqui por la clave
 * que ella elija.
 *
 * Asi el administrador NUNCA sabe la clave de nadie. Es la diferencia entre
 * "te pongo una generica y cambiala despues" -- que casi nadie cambia -- y
 * una clave que solo conoce su dueno desde el primer dia.
 */
@Component({
  selector: 'app-activar',
  imports: [ReactiveFormsModule, RouterLink],
  templateUrl: './activar.html',
  styleUrl: './activar.scss',
})
export class Activar {
  private readonly fb = inject(FormBuilder);
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  protected readonly cargando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly verClave = signal(false);

  protected readonly formulario = this.fb.nonNullable.group(
    {
      username: ['', [Validators.required, Validators.minLength(3)]],
      codigo: ['', [Validators.required, Validators.minLength(8)]],
      claveNueva: ['', [Validators.required, Validators.minLength(10)]],
      claveRepetida: ['', [Validators.required]],
    },
    { validators: clavesIguales },
  );

  protected get noCoinciden(): boolean {
    return this.formulario.hasError('noCoinciden') &&
           !!this.formulario.get('claveRepetida')?.touched;
  }

  protected activar(): void {
    if (this.formulario.invalid || this.cargando()) {
      this.formulario.markAllAsTouched();
      return;
    }

    this.cargando.set(true);
    this.error.set(null);

    const { username, codigo, claveNueva } = this.formulario.getRawValue();

    this.auth.activar({ username, codigo, claveNueva }).subscribe({
      next: (r) => {
        this.cargando.set(false);
        void this.router.navigate([r.requiereSucursal ? '/elegir-sucursal' : '/inicio']);
      },
      error: (e) => {
        this.cargando.set(false);
        this.error.set(mensajeDeError(e, 'No se pudo activar la cuenta'));
      },
    });
  }
}
