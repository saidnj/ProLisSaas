/**
 * LO QUE DEVUELVE pacientes/. El front lo espeja en
 * Interfaces/paciente.interface.ts: mismos nombres, mismos campos.
 *
 * Un paciente es de la EMPRESA: el expediente (EXP-000001) es un correlativo
 * de la empresa, no de la sede, y se ve y se atiende desde cualquier sede.
 * La edad NO se guarda: se guarda la fecha de nacimiento, y si al registrar
 * solo se supo la edad, la base calculo la fecha y la marco estimada.
 */

export const TIPOS_DOCUMENTO = [
  'identidad', 'pasaporte', 'carnet_residencia', 'partida_nacimiento', 'ninguno',
] as const;
export type TipoDocumento = (typeof TIPOS_DOCUMENTO)[number];

export const SEXOS = ['femenino', 'masculino'] as const;
export type Sexo = (typeof SEXOS)[number];

export interface PacienteDeLista {
  pacienteId: number;
  /** Lo pone el sistema: EXP-000001, EXP-000002... por empresa. */
  expediente: string;
  nombreCompleto: string;
  tipoDocumento: TipoDocumento;
  /** Solo con tipoDocumento distinto de 'ninguno'. */
  documento: string | null;
  /** AAAA-MM-DD, sin hora. */
  fechaNacimiento: string;
  /**
   * true = al registrar no se supo la fecha y se puso la edad; la fecha es
   * hoy menos esa edad. Se corrige poniendo la fecha real (y deja de ser
   * estimada). Una fecha confirmada no vuelve a estimarse.
   */
  fechaEstimada: boolean;
  sexo: Sexo;
  telefono: string | null;
  creadoEn: string;
}

/** La ficha: la lista mas lo que no hace falta para buscar. */
export interface PacienteCompleto extends PacienteDeLista {
  correo: string | null;
  direccion: string | null;
  /**
   * Si este expediente se fusiono en otro (dos fichas de la misma persona),
   * el id del que quedo. No sale en las busquedas y no se edita. Todavia
   * no hay pantalla que fusione: queda por si acaso.
   */
  fusionadoEn: number | null;
}
