import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post } from '@nestjs/common';
import { RolesService } from './roles.service';
import { CrearRolDto } from './dto/crear-rol.dto';
import { ActualizarRolDto } from './dto/actualizar-rol.dto';
import { SesionActual } from '../comun/sesion.decorador';
import type { Sesion } from '../comun/sesion';

/**
 * ADMINISTRAR ROLES: la lista, la ficha, crear, guardar. Mismo molde que
 * /empleados. Para ELEGIR un rol en un formulario esta /catalogo/roles
 * (solo los activos, lo minimo): eso no es de aqui.
 *
 * Sin @Publico(): el guard global ya las cerro. La sesion sale del token
 * firmado, via @SesionActual(). El permiso (usuario.administrar) y las
 * reglas de quien edita que rol las comprueba la BASE adentro de cada
 * funcion; el servicio pregunta antes solo para contestar mejor.
 */
@Controller('roles')
export class RolesController {
  constructor(private readonly roles: RolesService) {}

  /** GET /roles - todos los de la empresa, activos e inactivos. */
  @Get()
  listar(@SesionActual() sesion: Sesion) {
    return this.roles.listar(sesion);
  }

  /** POST /roles - el rol y sus permisos, en una sola transaccion. 201 con la ficha. */
  @Post()
  crear(@SesionActual() sesion: Sesion, @Body() dto: CrearRolDto) {
    return this.roles.crear(sesion, dto);
  }

  /** GET /roles/:id - la ficha: permisos y quienes lo tienen. */
  @Get(':id')
  obtener(@SesionActual() sesion: Sesion, @Param('id', ParseIntPipe) id: number) {
    return this.roles.obtener(sesion, id);
  }

  /** PATCH /roles/:id - nombre, descripcion, permisos y estado, en una sola transaccion. */
  @Patch(':id')
  actualizar(
    @SesionActual() sesion: Sesion,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ActualizarRolDto,
  ) {
    return this.roles.actualizar(sesion, id, dto);
  }
}
