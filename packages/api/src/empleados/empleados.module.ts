import { Module } from '@nestjs/common';
import { EmpleadosController } from './empleados.controller';
import { EmpleadosService } from './empleados.service';

@Module({ controllers: [EmpleadosController], providers: [EmpleadosService] })
export class EmpleadosModule {}
