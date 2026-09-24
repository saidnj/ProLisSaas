import { Type } from 'class-transformer';
import {
  IsBoolean, IsEmail, IsOptional, IsString, MaxLength, MinLength, ValidateNested,
} from 'class-validator';
import { CuentaDto } from './cuenta.dto';

/**
 * Editar es el mismo formulario que crear: la persona y, si tiene, su
 * cuenta. Empleado y cuenta son UN modulo en pantalla, asi que se guardan
 * con UNA peticion y UNA transaccion, igual que al crear.
 *
 * Los campos van escritos otra vez en vez de heredar de CrearEmpleadoDto,
 * porque la cuenta al crear (CuentaNuevaDto: username, rol y sedes
 * obligatorios, mas el codigo) y al editar (CuentaDto: todo opcional, y
 * nunca 'crear una') no son la misma cosa. El ValidationPipe corre con
 * forbidNonWhitelisted: lo que no este aqui se rechaza con 400.
 *
 * Que un cambio de telefono y un cambio de rol vayan en la misma peticion
 * no los mezcla en la auditoria: cada cosa de la cuenta deja su propio
 * evento (usuario.rol_cambiar, usuario.username_cambiar, ...), y la ficha
 * el suyo.
 *
 * OJO con la semantica de la ficha: el front manda el objeto COMPLETO, y lo
 * que no venga queda en null. No es un parche campo por campo. La cuenta
 * es al reves: lo que no venga no se toca.
 */
export class ActualizarEmpleadoDto {
  @IsString()
  @MinLength(2, { message: 'Hace falta el nombre' })
  @MaxLength(80)
  nombres!: string;

  @IsString()
  @MinLength(2, { message: 'Hacen falta los apellidos' })
  @MaxLength(80)
  apellidos!: string;

  @IsOptional() @IsString() @MaxLength(30)
  documento?: string;

  @IsOptional() @IsString() @MaxLength(30)
  telefono?: string;

  @IsOptional() @IsEmail({}, { message: 'Ese correo no tiene forma de correo' })
  correo?: string;

  @IsOptional() @IsString() @MaxLength(80)
  cargo?: string;

  @IsOptional() @IsString() @MaxLength(40)
  numeroColegiacion?: string;

  @IsOptional() @IsBoolean()
  activo?: boolean;

  /**
   * La cuenta, tal como esta en pantalla (ver CuentaDto). Si no viene, no se
   * toca: la pantalla no la manda cuando esta bloqueada para quien edita
   * (la de un administrador, sin ser el propietario). Si el empleado
   * todavia no tiene cuenta, este guardar se la crea: entonces hacen falta
   * username, rolId y sucursales (lo comprueba el servicio).
   */
  @IsOptional()
  @ValidateNested()
  @Type(() => CuentaDto)
  cuenta?: CuentaDto;
}
