import { Component, inject } from '@angular/core';
import { DatePipe } from '@angular/common';
import { SesionService } from '../../Servicios/sesion.service';
import { Encabezado } from '../encabezado/encabezado';

/**
 * Pantalla de relleno, y a proposito.
 *
 * Por ahora su unico trabajo es mostrar TODO lo que el back mando al
 * entrar, para poder verlo con los ojos: si aqui falta un dato, falta en la
 * sesion, y se arregla del lado del servidor y no parchando la pantalla.
 *
 * Fijate en lo unico que hace falta para tener el encabezado: importarlo
 * aqui abajo y poner <app-encabezado /> arriba del .html. Ni modulo, ni
 * registro en ningun lado, ni codigo repetido -- y "Cambiar de sede" y
 * "Salir" se fueron con el, porque son del encabezado y no de esta
 * pantalla.
 */
@Component({
  selector: 'app-inicio',
  imports: [DatePipe, Encabezado],
  templateUrl: './inicio.html',
  styleUrl: './inicio.scss',
})
export class Inicio {
  protected readonly sesion = inject(SesionService);
}
