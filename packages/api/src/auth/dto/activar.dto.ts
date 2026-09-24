import { IsInt, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class ActivarDto {
  @IsString()
  @MinLength(3)
  @MaxLength(40)
  username!: string;

  /** El codigo que le entrego el administrador. Se normaliza antes de comparar. */
  @IsString()
  @MinLength(8)
  @MaxLength(20)
  codigo!: string;

  /**
   * Minimo 10 caracteres y NINGUNA regla de composicion.
   *
   * Obligar mayuscula, numero y simbolo empuja a "Laboratorio1!" -- que cumple
   * todo y es de las primeras que prueba cualquier ataque -- mientras rechaza
   * "mi perro se llama tomas", que es mas dificil de adivinar y mas facil de
   * recordar. La longitud es lo que importa.
   */
  @IsString()
  @MinLength(10)
  @MaxLength(200)
  claveNueva!: string;

  /** Solo hace falta si el mismo username existe en dos empresas (H-101). */
  @IsOptional()
  @IsInt()
  empresaId?: number;
}
