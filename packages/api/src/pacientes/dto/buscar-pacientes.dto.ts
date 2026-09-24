import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

/**
 * GET /pacientes?q=sair&limite=50
 *
 * Sin q: los ultimos registrados. Con q: por parecido (core.buscar_pacientes),
 * no por texto exacto, y ordenados por coincidencia: para "sair", Sair antes
 * que Said.
 */
export class BuscarPacientesDto {
  @IsOptional() @IsString() @MaxLength(120, { message: 'El texto de busqueda lleva hasta 120 caracteres' })
  q?: string;

  /** Por omision 50; la base acota 1..200. */
  @IsOptional() @Type(() => Number)
  @IsInt({ message: 'El limite va en numeros enteros' })
  @Min(1, { message: 'El limite va de 1 a 200' }) @Max(200, { message: 'El limite va de 1 a 200' })
  limite?: number;
}
