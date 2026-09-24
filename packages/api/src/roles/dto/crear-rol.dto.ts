import { Transform } from 'class-transformer';
import {
  ArrayNotEmpty, ArrayUnique, IsArray, IsString, Matches, MaxLength, MinLength,
} from 'class-validator';

/**
 * Un rol nace con nombre y con sus permisos, de una vez: crear el rol y
 * ponerle los permisos van en UNA transaccion (core.crear_rol +
 * core.asignar_permisos_a_rol). Si una falla, no queda un rol vacio.
 *
 * Las reglas de fondo las pone la base y aqui solo se repite la forma:
 *   - el nombre lleva de 2 a 60 caracteres y no se repite en la empresa
 *     ("Recepcion" y "recepcion " son el mismo: core.llave_texto)
 *   - la descripcion es obligatoria (hasta 200)
 *   - un permiso de nivel 'propietario' no se asigna a nadie
 *   - uno de nivel 'admin' lo asigna solo el propietario
 *   - solo permisos de modulos que la empresa tiene contratados
 */
export class CrearRolDto {
  @IsString()
  @MinLength(2, { message: 'El nombre del rol lleva al menos 2 caracteres' })
  @MaxLength(60, { message: 'El nombre del rol lleva hasta 60 caracteres' })
  nombre!: string;

  /**
   * Obligatoria: es lo que lee quien va a asignar el rol ("a quien se le
   * pone"). Arranca en '' (y se recorta) para que faltar y venir en blanco
   * sean lo mismo, con un solo error en espanol: "hace falta".
   */
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : ''))
  @IsString()
  @MinLength(3, { message: 'Hace falta la descripcion del rol' })
  @MaxLength(200, { message: 'La descripcion lleva hasta 200 caracteres' })
  descripcion = '';

  /** Los ids tal como estan en plataforma.permiso: 'modulo.accion'. */
  @IsArray()
  @ArrayNotEmpty({ message: 'Un rol lleva al menos un permiso' })
  @ArrayUnique()
  @IsString({ each: true })
  @Matches(/^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/, { each: true, message: 'Hay un permiso con forma invalida' })
  permisos!: string[];
}
