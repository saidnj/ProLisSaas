import { CrearPacienteDto } from './crear-paciente.dto';

/**
 * Editar es el mismo formulario que registrar: la ficha entera, tal como
 * esta en pantalla, en UNA peticion. No hace falta mandar solo lo que
 * cambio: la base no escribe lo que vino igual (editar_paciente devuelve
 * false y no deja evento).
 *
 * Una regla mas que al crear, y la pone la base (22023 -> 400): si la fecha
 * de nacimiento ya esta CONFIRMADA no se puede volver a mandar edad. Una
 * fecha estimada si se puede corregir con la fecha real, o re-estimar.
 */
export class ActualizarPacienteDto extends CrearPacienteDto {}
