import { Body, Controller, Get, Param, ParseIntPipe, Patch, Post, Query } from '@nestjs/common';
import { PacientesService } from './pacientes.service';
import { CrearPacienteDto } from './dto/crear-paciente.dto';
import { ActualizarPacienteDto } from './dto/actualizar-paciente.dto';
import { BuscarPacientesDto } from './dto/buscar-pacientes.dto';
import { SesionActual } from '../comun/sesion.decorador';
// 'import type' y no 'import' a secas: con isolatedModules y
// emitDecoratorMetadata, TypeScript exige que los tipos que aparecen en una
// firma decorada se importen como tipos. Si no, intenta emitir metadata de
// runtime para una interfaz que en runtime no existe.
import type { Sesion } from '../comun/sesion';

/**
 * PACIENTES: buscar, la ficha, registrar, guardar. Mismo molde que
 * /empleados y /roles.
 *
 * Sin @Publico(): el guard global ya las cerro. La sesion sale del token
 * firmado, via @SesionActual(). Fijate que el controlador no sabe nada de
 * empresas: recibe la sesion y la pasa. Los permisos (paciente.ver, crear,
 * editar) y las reglas de la ficha los comprueba la BASE; el servicio
 * pregunta antes solo para contestar mejor.
 */
@Controller('pacientes')
export class PacientesController {
  constructor(private readonly pacientes: PacientesService) {}

  /** GET /pacientes?q=&limite= - sin q los ultimos 50; con q, por parecido. */
  @Get()
  buscar(@SesionActual() sesion: Sesion, @Query() filtro: BuscarPacientesDto) {
    return this.pacientes.buscar(sesion, filtro.q, filtro.limite);
  }

  /** POST /pacientes - la ficha. 201 con la ficha completa (con su expediente). */
  @Post()
  crear(@SesionActual() sesion: Sesion, @Body() dto: CrearPacienteDto) {
    return this.pacientes.crear(sesion, dto);
  }

  /** GET /pacientes/:id - la ficha. */
  @Get(':id')
  obtener(@SesionActual() sesion: Sesion, @Param('id', ParseIntPipe) id: number) {
    return this.pacientes.obtener(sesion, id);
  }

  /** PATCH /pacientes/:id - la ficha entera, tal como esta en pantalla. */
  @Patch(':id')
  actualizar(
    @SesionActual() sesion: Sesion,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: ActualizarPacienteDto,
  ) {
    return this.pacientes.actualizar(sesion, id, dto);
  }
}
