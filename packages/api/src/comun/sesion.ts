/**
 * Quien esta haciendo esta peticion.
 *
 * Sale SIEMPRE del token verificado, nunca del cuerpo ni de un parametro
 * de la URL. Esa es la regla que sostiene todo el aislamiento: si el API
 * aceptara un ?empresaId=2, cualquiera lo cambia en la barra del
 * navegador y lee los pacientes de otro laboratorio -- y RLS lo dejaria
 * pasar tan tranquilo, porque RLS obedece el contexto que le pongan.
 *
 * RLS protege contra el WHERE olvidado. No protege contra un API que le
 * cree al navegador.
 */
export interface Sesion {
  usuarioId: bigint;
  empresaId: bigint;
  username: string;
  rol: string;

  /**
   * En que sede esta parado. Va aparte y es OPCIONAL porque hay un momento
   * legitimo en que la sesion existe y la sucursal no: entre que se verifico
   * la clave y que la persona eligio donde entrar.
   *
   * Cuando existe viene del token FIRMADO, igual que empresaId y por la misma
   * razon. Mandarla en una cabecera o en el cuerpo seria regalarla: el usuario
   * la cambia en F12 y se para en una sede a la que no tiene acceso. Como los
   * permisos efectivos dependen de la sede -- un modulo apagado ahi recorta el
   * rol -- eso no seria un detalle de pantalla, seria un permiso de mas.
   */
  sucursalId?: bigint;
}

/** Lo que viaja DENTRO del token. Claves cortas: el token va en cada peticion. */
export interface CargaToken {
  sub: string;  // usuario_id  (nombre estandar de JWT para "el sujeto")
  emp: string;  // empresa_id
  usr: string;  // username
  rol: string;
  suc?: string; // sucursal_id -- ausente mientras no haya elegido sede
}
