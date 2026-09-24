import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';

/**
 * El cascaron. No tiene encabezado ni menu propios a proposito: el login y
 * la activacion se pintan a pantalla completa, y lo que lleva barra es cada
 * pantalla de adentro. Cuando exista el menu de verdad va a vivir en un
 * componente de plantilla, no aqui.
 */
@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  template: '<router-outlet />',
})
export class App {}
