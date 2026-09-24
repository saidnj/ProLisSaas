import { Type } from 'class-transformer';
import {
  ArrayNotEmpty, IsArray, IsInt, IsOptional, IsPositive, IsString, Matches, MaxLength,
} from 'class-validator';

/**
 * La CUENTA dentro de "guardar empleado". Va tal como esta en pantalla:
 * el back no toca lo que no cambio (empleados/cuenta.ts), asi que el front no
 * tiene que comparar. Todo opcional: lo que no viene no se toca.
 *
 * 'activo' NO va aqui: es del empleado, y la base lo traslada sola a la
 * cuenta (trigger tg_empleado_activo).
 */
export class CuentaDto {
  @IsOptional()
  @IsString()
  @Matches(/^[a-z0-9._-]{3,40}$/i, {
    message: 'El nombre de usuario lleva de 3 a 40 letras, numeros, punto, guion o guion bajo, sin espacios',
  })
  username?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @IsPositive()
  rolId?: number;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  motivoRol?: string;

  @IsOptional()
  @IsArray()
  @ArrayNotEmpty({ message: 'Un usuario tiene que quedar con al menos una sucursal' })
  @Type(() => Number)
  @IsInt({ each: true })
  @IsPositive({ each: true })
  sucursales?: number[];

  @IsOptional()
  @IsString()
  @MaxLength(200)
  motivoSedes?: string;
}
