import { randomBytes } from 'node:crypto';

/**
 * Alfabeto de 32 caracteres SIN  I  L  O  U.
 *
 *   I y L se confunden con 1
 *   O     se confunde con 0
 *   U     se confunde con V escrito a mano
 *
 * Alguien va a dictar este codigo en voz alta o a copiarlo de un papel, y
 * "cero o letra o" es el error clasico. Es el alfabeto de Crockford, hecho
 * justo para esto.
 */
const ALFABETO = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/**
 * UN CODIGO TIENE DOS FORMAS Y NO SON INTERCAMBIABLES.
 *
 *   legible   'K7M2-9QXF'  con guion. Es lo que se le entrega a la persona,
 *                          lo que se dicta por telefono, lo que se muestra
 *                          en pantalla.
 *
 *   paraHash  'K7M29QXF'   sin guion ni mayusculas sueltas. Es la forma
 *                          canonica, y es la UNICA sobre la que se calcula
 *                          el hash.
 *
 * Por que estan separadas: quien escribe el codigo al activar puede poner el
 * guion o no, en mayuscula o en minuscula, con un espacio en medio. Por eso
 * activar() llama a normalizarCodigo() antes de verificar. Si el hash se
 * hubiera calculado sobre la forma legible, la comparacion nunca cuadraria y
 * ningun codigo se podria activar jamas -- que es exactamente el error que
 * tenia este archivo.
 *
 * Devolver las dos juntas es lo que hace que no se pueda volver a equivocar:
 * ya no hay un "string codigo" suelto del que haya que acordarse cual era.
 */
export interface CodigoActivacion {
  legible: string;
  paraHash: string;
}

/**
 * Un codigo de activacion: ocho caracteres en dos grupos.
 *
 *     K7M2-9QXF
 *
 * 32^8 = 40 bits de entropia. Con cinco intentos y 24 horas de vida,
 * adivinarlo no es una via.
 *
 * 32 divide exacto a 256, asi que `byte % 32` reparte parejo: no hay
 * caracteres mas probables que otros.
 */
export function generarCodigo(): CodigoActivacion {
  const bytes = randomBytes(8);
  let s = '';
  for (let i = 0; i < 8; i++) {
    s += ALFABETO[bytes[i] % ALFABETO.length];
    if (i === 3) s += '-';
  }
  return { legible: s, paraHash: normalizarCodigo(s) };
}

/** Quita guiones y espacios y sube a mayusculas, para comparar sin sorpresas. */
export function normalizarCodigo(codigo: string): string {
  return codigo.replace(/[\s-]/g, '').toUpperCase();
}
