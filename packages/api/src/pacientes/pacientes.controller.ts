import { Controller, Get } from '@nestjs/common';
import { PacientesService } from './pacientes.service';
import { SesionActual } from '../comun/sesion.decorador';
// 'import type' y no 'import' a secas: con isolatedModules y
// emitDecoratorMetadata, TypeScript exige que los tipos que aparecen en una
// firma decorada se importen como tipos. Si no, intenta emitir metadata de
// runtime para una interfaz que en runtime no existe.
import type { Sesion } from '../comun/sesion';

/**
 * Sin @Publico(): el guard global exige token.
 *
 * Y fijate que el controlador no sabe nada de empresas. Recibe la sesion y
 * la pasa. Toda la decision de que datos salen la toma Postgres.
 */
@Controller('pacientes')
export class PacientesController {
  constructor(private readonly pacientes: PacientesService) {}

  @Get()
  listar(@SesionActual() sesion: Sesion) {
    return this.pacientes.listar(sesion);
  }
}
