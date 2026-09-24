import { Component, input, output, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';

/**
 * EL CODIGO, UNA SOLA VEZ.
 *
 * La misma pantalla para las dos veces que nace un codigo: al crear la
 * cuenta y al generarle uno nuevo a quien todavia no la estreno. Vive
 * aparte para que las dos digan exactamente lo mismo -- de la base solo
 * sale el hash, no hay segunda oportunidad, y el texto que lo explica no
 * puede irse separando en dos sitios.
 *
 * No navega sola: avisa con (listo) y quien la usa decide a donde ir.
 */
@Component({
  selector: 'app-codigo-activacion',
  imports: [RouterLink, DatePipe],
  templateUrl: './codigo-activacion.html',
  styleUrl: './codigo-activacion.scss',
})
export class CodigoActivacion {
  readonly codigo = input.required<string>();
  readonly nombre = input.required<string>();
  /** Cuando vence. Lo manda el back; si no llega, se dice "24 horas". */
  readonly venceEn = input<string | null>(null);
  /**
   * 'nuevo'        recien creada la cuenta
   * 'reemplazo'    el anterior se anulo (seguia pendiente)
   * 'restablecer'  tenia clave y la olvido: se le borro y queda fuera hasta activar
   */
  readonly motivo = input<'nuevo' | 'reemplazo' | 'restablecer'>('nuevo');
  readonly listo = output<void>();

  protected readonly copiado = signal(false);

  protected async copiar(): Promise<void> {
    try {
      await navigator.clipboard.writeText(this.codigo());
      this.copiado.set(true);
      setTimeout(() => this.copiado.set(false), 2000);
    } catch {
      // Sin permiso de portapapeles (o sin HTTPS): el codigo esta a la vista
      // y se puede seleccionar a mano. No es motivo para avisar nada.
    }
  }
}
