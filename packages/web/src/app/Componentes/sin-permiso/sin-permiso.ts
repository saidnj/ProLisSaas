import { Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { SesionService } from '../../Servicios/sesion.service';

@Component({
  selector: 'app-sin-permiso',
  imports: [RouterLink],
  templateUrl: './sin-permiso.html',
  styleUrl: './sin-permiso.scss',
})
export class SinPermiso {
  protected readonly sesion = inject(SesionService);
}
