import { Transform, Type } from 'class-transformer';
import {
  IsEmail, IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min, MinLength,
} from 'class-validator';
import { SEXOS, TIPOS_DOCUMENTO } from '../tipos';
import type { Sexo, TipoDocumento } from '../tipos';

/**
 * Un campo opcional que la pantalla manda vacio ('') es lo mismo que no
 * mandarlo: se vuelve undefined y @IsOptional lo deja pasar. Sin esto, un
 * correo en blanco falla @IsEmail y una fecha en blanco falla @Matches.
 */
const vacioEsNada = () =>
  Transform(({ value }) => (typeof value === 'string' && value.trim() === '' ? undefined : value));

/**
 * Registrar es un insert sencillo: la ficha y nada mas (core.registrar_paciente).
 * El expediente lo pone la base. Las reglas de fondo estan en la base y aqui
 * solo se repite la forma, para contestar 400 con palabras antes de ir:
 *
 *   - nombre completo obligatorio, de 2 a 120
 *   - documento opcional; con tipo distinto de 'ninguno' hace falta el numero
 *   - la fecha de nacimiento O la edad (anios y/o meses), nunca las dos:
 *     con edad, la base calcula la fecha (hoy - edad) y la marca ESTIMADA
 *   - sexo obligatorio: femenino o masculino
 */
export class CrearPacienteDto {
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : ''))
  @IsString()
  @MinLength(2, { message: 'Hace falta el nombre completo' })
  @MaxLength(120, { message: 'El nombre lleva hasta 120 caracteres' })
  nombreCompleto = '';

  /** Por omision 'ninguno'. */
  @IsOptional()
  @IsIn(TIPOS_DOCUMENTO, { message: 'Tipo de documento invalido' })
  tipoDocumento?: TipoDocumento;

  @vacioEsNada()
  @IsOptional() @IsString() @MaxLength(40, { message: 'El documento lleva hasta 40 caracteres' })
  documento?: string;

  /** AAAA-MM-DD, tal como lo da un <input type="date">. Sin hora. */
  @vacioEsNada()
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, { message: 'La fecha de nacimiento va como AAAA-MM-DD' })
  fechaNacimiento?: string;

  /** Solo cuando no se sabe la fecha. La base acota 0..130. */
  @vacioEsNada()
  @IsOptional() @Type(() => Number)
  @IsInt({ message: 'La edad en anios va en numeros enteros' })
  @Min(0) @Max(130, { message: 'La edad en anios va de 0 a 130' })
  edadAnios?: number;

  /** Idem, 0..11: doce meses es un anio. */
  @vacioEsNada()
  @IsOptional() @Type(() => Number)
  @IsInt({ message: 'Los meses van en numeros enteros' })
  @Min(0) @Max(11, { message: 'Los meses van de 0 a 11' })
  edadMeses?: number;

  @IsIn(SEXOS, { message: 'Hace falta el sexo: femenino o masculino' })
  sexo!: Sexo;

  @vacioEsNada()
  @IsOptional() @IsString() @MaxLength(30, { message: 'El telefono lleva hasta 30 caracteres' })
  telefono?: string;

  @vacioEsNada()
  @IsOptional() @IsEmail({}, { message: 'Ese correo no tiene forma de correo' })
  correo?: string;

  @vacioEsNada()
  @IsOptional() @IsString() @MaxLength(200, { message: 'La direccion lleva hasta 200 caracteres' })
  direccion?: string;
}
