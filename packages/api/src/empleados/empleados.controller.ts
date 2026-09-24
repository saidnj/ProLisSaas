import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post } from '@nestjs/common';
import { EmpleadosService } from './empleados.service';
import { CrearEmpleadoDto } from './dto/crear-empleado.dto';
import { ActualizarEmpleadoDto } from './dto/actualizar-empleado.dto';
import { SesionActual } from '../comun/sesion.decorador';
// 'import type' por isolatedModules + emitDecoratorMetadata: un tipo que
// aparece en una firma decorada se importa como tipo, si no TypeScript
// intenta emitir metadata de runtime para una interfaz que no existe ahi.
import type { Sesion } from '../comun/sesion';

/**
 * EMPLEADOS ES TAMBIEN USUARIOS. Empleado y cuenta son uno (1 a 1), asi que
 * todo lo de la cuenta entra por aqui: nace con el empleado, se edita con
 * el, y las acciones que no son "editar un campo" (codigo nuevo,
 * desbloquear) van por su id de empleado. No hay un modulo usuarios/.
 *
 * Sin @Publico(): el guard global ya las cerro. Y la sesion no llega del
 * cuerpo ni de la URL -- sale del token firmado, via @SesionActual(). El
 * permiso usuario.administrar lo comprueba la BASE adentro de cada funcion
 * (crear_usuario, generar_activacion, desbloquear_usuario...), no solo
 * aqui: si se comprobara solo aqui, bastaria una ruta nueva que alguien
 * olvide proteger.
 */
@Controller('empleados')
export class EmpleadosController {
  constructor(private readonly empleados: EmpleadosService) {}

  /** GET /empleados - la lista de la empresa de quien pregunta. */
  @Get()
  listar(@SesionActual() sesion: Sesion) {
    return this.empleados.listar(sesion);
  }

  /**
   * POST /empleados - la persona, su cuenta, sus sedes y su codigo de
   * activacion, en una sola transaccion.
   *
   * Devuelve 201 (el 'created' de siempre) y el codigo EN CLARO una unica
   * vez: de la base solo sale el hash. Si nace inactivo no hay codigo.
   */
  @Post()
  crear(@SesionActual() sesion: Sesion, @Body() dto: CrearEmpleadoDto) {
    return this.empleados.crear(sesion, dto);
  }

  /** GET /empleados/:id - la ficha de uno. */
  @Get(':id')
  obtener(@SesionActual() sesion: Sesion, @Param('id', ParseIntPipe) id: number) {
    return this.empleados.obtener(sesion, id);
  }

  /**
   * PATCH /empleados/:id - guardar: la ficha y la cuenta, en una sola
   * transaccion. Si todavia no tiene cuenta, se la crea (y devuelve el
   * codigo, como al crear).
   */
  @Patch(':id')
  actualizar(
    @SesionActual() sesion: Sesion,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ActualizarEmpleadoDto,
  ) {
    return this.empleados.actualizar(sesion, id, dto);
  }

  /**
   * POST /empleados/:id/codigo - un codigo nuevo: reemplazo si la cuenta
   * sigue pendiente, restablecer la clave si ya tenia (queda fuera hasta
   * activar). Una cuenta suspendida no recibe codigo.
   */
  @Post(':id/codigo')
  codigoNuevo(@SesionActual() sesion: Sesion, @Param('id', ParseIntPipe) id: number) {
    return this.empleados.codigoNuevo(sesion, id);
  }

  /** POST /empleados/:id/desbloquear - de bloqueado a activo, sin codigo: la clave sigue siendo la suya. */
  @Post(':id/desbloquear')
  desbloquear(@SesionActual() sesion: Sesion, @Param('id', ParseIntPipe) id: number) {
    return this.empleados.desbloquear(sesion, id);
  }
}
