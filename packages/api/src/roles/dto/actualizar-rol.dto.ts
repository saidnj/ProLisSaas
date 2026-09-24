import { IsBoolean, IsOptional, IsString, MaxLength } from 'class-validator';
import { CrearRolDto } from './crear-rol.dto';

/**
 * Editar es el mismo formulario que crear: el nombre, la descripcion y los
 * permisos tal como estan en pantalla, en UNA peticion y UNA transaccion.
 * No hace falta mandar solo lo que cambio: la base no escribe lo que vino
 * igual (editar_rol devuelve false, asignar_permisos_a_rol no deja evento
 * con el mismo conjunto).
 *
 * Lo unico de mas es el estado: apagar un rol lo saca de las listas para
 * elegir y ya no se le asigna a nadie. No se puede apagar si alguien lo
 * tiene puesto (la base contesta 409: "cambiales el rol primero"). Quien
 * lo tenia puesto no pierde nada: desactivar no es quitar.
 */
export class ActualizarRolDto extends CrearRolDto {
  @IsOptional() @IsBoolean()
  activo?: boolean;

  /** Por que se desactiva. Va a la bitacora. */
  @IsOptional() @IsString() @MaxLength(200)
  motivo?: string;
}
