import { Controller, Get } from '@nestjs/common';
import { CatalogoService } from './catalogo.service';
import { SesionActual } from '../comun/sesion.decorador';
import type { Sesion } from '../comun/sesion';

/**
 * /catalogo/<cosa> - las listas para elegir. Una ruta por lista, todas
 * aqui: la URL dice para que sirve (llenar un campo), y estar juntas hace
 * que la lista numero treinta cueste lo mismo que la primera. Con sesion
 * vigente alcanza (el guard global ya lo exige); las filas las decide la
 * base.
 *
 * Administrar la cosa NO va aqui: eso es /<cosa>, en el modulo dueno, con
 * su permiso.
 */
@Controller('catalogo')
export class CatalogoController {
  constructor(private readonly catalogo: CatalogoService) {}

  /** GET /catalogo/roles - alcance empresa. */
  @Get('roles')
  roles(@SesionActual() sesion: Sesion) {
    return this.catalogo.roles(sesion);
  }

  /** GET /catalogo/sucursales - alcance empresa; solo las abiertas. */
  @Get('sucursales')
  sucursales(@SesionActual() sesion: Sesion) {
    return this.catalogo.sucursales(sesion);
  }

  /** GET /catalogo/permisos - alcance empresa; los asignables, por modulo, con su nivel. */
  @Get('permisos')
  permisos(@SesionActual() sesion: Sesion) {
    return this.catalogo.permisos(sesion);
  }
}
