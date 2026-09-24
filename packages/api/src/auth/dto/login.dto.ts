import { IsInt, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class LoginDto {
  @IsString()
  @MinLength(3)
  @MaxLength(40)
  username!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  password!: string;

  /**
   * H-101 - la ambiguedad sin resolver.
   *
   * El indice unico es (empresa_id, lower(username)): el username es unico
   * DENTRO de la empresa, no en el sistema. Dos laboratorios pueden tener
   * 'marlon.ochoa'.
   *
   * Mientras no se decida como se sabe la empresa antes de entrar
   * (subdominio, codigo, correo unico), esto es opcional: con un solo
   * laboratorio cargado no hace falta, y en cuanto haya dos que choquen
   * core.buscar_credencial() lanza error en vez de adivinar.
   *
   * OJO: esto es lo UNICO del login que viene del cliente. Despues de
   * entrar, el empresaId sale siempre del token.
   */
  @IsOptional()
  @IsInt()
  empresaId?: number;
}
