/**
 * Un paciente de la empresa. Espejo de pacientes/tipos.ts del API: mismos
 * nombres, mismos campos.
 *
 * La edad NO se guarda: se guarda la fecha de nacimiento. Si al registrar
 * solo se supo la edad, la base calculo la fecha (hoy menos la edad) y la
 * marco ESTIMADA; la edad que se muestra sale siempre de la fecha.
 */
export type TipoDocumento =
  | 'identidad' | 'pasaporte' | 'carnet_residencia' | 'partida_nacimiento' | 'ninguno';

export type Sexo = 'femenino' | 'masculino';

export interface Paciente {
  pacienteId: number;
  /** Lo pone el sistema: EXP-000001, EXP-000002... por empresa. */
  expediente: string;
  nombreCompleto: string;
  tipoDocumento: TipoDocumento;
  /** Solo con tipoDocumento distinto de 'ninguno'. */
  documento: string | null;
  /** AAAA-MM-DD, sin hora. */
  fechaNacimiento: string;
  /** Calculada a partir de la edad, no dicha por la persona. Se corrige poniendo la fecha real. */
  fechaEstimada: boolean;
  sexo: Sexo;
  telefono: string | null;
  creadoEn: string;
}

/** La ficha: lo de la lista mas lo que no hace falta para buscar. */
export interface PacienteCompleto extends Paciente {
  correo: string | null;
  direccion: string | null;
  /** Si este expediente se fusiono en otro, el id del que quedo. Todavia sin pantalla. */
  fusionadoEn: number | null;
}

/**
 * Lo que se manda al registrar y al guardar: la ficha entera. La fecha O la
 * edad, nunca las dos (la base lo rechaza); con edad, la fecha queda
 * estimada.
 */
export interface PacienteEntrada {
  nombreCompleto: string;
  tipoDocumento: TipoDocumento;
  documento: string | null;
  fechaNacimiento: string | null;
  edadAnios: number | null;
  edadMeses: number | null;
  sexo: Sexo;
  telefono: string | null;
  correo: string | null;
  direccion: string | null;
}

/** Para los <select>: el valor que entiende la base y como se le dice a una persona. */
export const TIPOS_DOCUMENTO: ReadonlyArray<{ id: TipoDocumento; texto: string }> = [
  { id: 'ninguno',            texto: 'Sin documento' },
  { id: 'identidad',          texto: 'Identidad' },
  { id: 'pasaporte',          texto: 'Pasaporte' },
  { id: 'carnet_residencia',  texto: 'Carnet de residencia' },
  { id: 'partida_nacimiento', texto: 'Partida de nacimiento' },
];

export const SEXOS: ReadonlyArray<{ id: Sexo; texto: string }> = [
  { id: 'femenino',  texto: 'Femenino' },
  { id: 'masculino', texto: 'Masculino' },
];

export function textoTipoDocumento(t: TipoDocumento): string {
  return TIPOS_DOCUMENTO.find((x) => x.id === t)?.texto ?? t;
}

export function textoSexo(s: Sexo): string {
  return SEXOS.find((x) => x.id === s)?.texto ?? s;
}
