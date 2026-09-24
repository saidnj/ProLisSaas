import { Type } from 'class-transformer';
import {
  ArrayNotEmpty, IsArray, IsBoolean, IsDefined, IsEmail, IsInt, IsOptional, IsPositive,
  IsString, Matches, MaxLength, MinLength, ValidateNested,
} from 'class-validator';

/**
 * LA CUENTA CON LA QUE NACE. No es opcional: empleado y usuario son uno
 * (1 a 1), y el modulo de empleados ES el de usuarios. El que no debe
 * entrar al sistema no se queda sin cuenta: se registra INACTIVO, y su
 * cuenta nace suspendida (core.crear_usuario lo decide con empleado.activo).
 */
export class CuentaNuevaDto {
  /** El mismo CHECK que tiene la base (ck_usuario_username). Se guarda en minusculas. */
  @IsString()
  @Matches(/^[a-z0-9._-]{3,40}$/i, {
    message: 'El nombre de usuario lleva de 3 a 40 letras, numeros, punto, guion o guion bajo, sin espacios',
  })
  username!: string;

  @Type(() => Number)
  @IsInt({ message: 'Hace falta elegir un rol' })
  @IsPositive()
  rolId!: number;

  /**
   * En que sedes va a poder pararse. AL MENOS UNA.
   *
   * No es opcional y no tiene valor por omision a proposito: un usuario sin
   * ninguna sucursal activa no puede entrar a ningun lado -- abrirSesion()
   * lo rechaza con "No tenes ninguna sucursal activa asignada". Crearlo asi
   * seria fabricar una cuenta rota que nadie sabe por que no funciona.
   */
  @IsArray()
  @ArrayNotEmpty({ message: 'Hace falta elegir al menos una sucursal' })
  @Type(() => Number)
  @IsInt({ each: true })
  @IsPositive({ each: true })
  sucursales!: number[];

  /**
   * Cuantas horas vive el codigo de activacion. La base lo acota entre 1 y
   * 168 (siete dias) y revienta con 22023 si se pasa.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  horas?: number;
}

/**
 * Crear es UNA peticion y UNA transaccion: la persona, su cuenta, sus sedes
 * y -- si nace activo -- su codigo de activacion. O queda todo o no queda
 * nada.
 */
export class CrearEmpleadoDto {
  @IsString()
  @MinLength(2, { message: 'Hace falta el nombre' })
  @MaxLength(80)
  nombres!: string;

  @IsString()
  @MinLength(2, { message: 'Hacen falta los apellidos' })
  @MaxLength(80)
  apellidos!: string;

  /** Numero de identidad. Opcional: no todos lo traen el primer dia. */
  @IsOptional() @IsString() @MaxLength(30)
  documento?: string;

  @IsOptional() @IsString() @MaxLength(30)
  telefono?: string;

  @IsOptional() @IsEmail({}, { message: 'Ese correo no tiene forma de correo' })
  correo?: string;

  @IsOptional() @IsString() @MaxLength(80)
  cargo?: string;

  /** Del bioquimico o del medico. Va impreso en el informe junto a la firma. */
  @IsOptional() @IsString() @MaxLength(40)
  numeroColegiacion?: string;

  /**
   * Si esta trabajando. Apagado, no sale en las listas y su cuenta nace
   * suspendida: no entra hasta que lo activen. Por omision, activo.
   */
  @IsOptional() @IsBoolean()
  activo?: boolean;

  @IsDefined({ message: 'Hace falta la cuenta: usuario, rol y sedes' })
  @ValidateNested()
  @Type(() => CuentaNuevaDto)
  cuenta!: CuentaNuevaDto;
}
