import { IsInt, IsPositive } from 'class-validator';
import { Type } from 'class-transformer';

/**
 * Lo unico que se manda para pararse en una sede. No lleva empresaId ni
 * usuarioId: esos salen del token, y por eso no se pueden falsificar.
 */
export class SucursalDto {
  @Type(() => Number)
  @IsInt({ message: 'sucursalId tiene que ser un numero entero' })
  @IsPositive({ message: 'sucursalId tiene que ser positivo' })
  sucursalId!: number;
}
