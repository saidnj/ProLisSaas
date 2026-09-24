/**
 * LA EDAD SALE DE LA FECHA. Siempre. La base no guarda la edad (se vuelve
 * vieja sola): guarda la fecha de nacimiento, y la pantalla la convierte
 * cada vez que la muestra. Con una fecha ESTIMADA (calculada a partir de la
 * edad al registrar) la edad se muestra igual, con un "~" delante.
 *
 * Todo con fechas locales sin hora: 'AAAA-MM-DD' se arma como
 * new Date(a, m - 1, d) y no con new Date('AAAA-MM-DD'), que la toma como
 * UTC y en Honduras (UTC-6) la corre al dia anterior.
 */

export interface Edad {
  anios: number;
  meses: number;
}

/** 'AAAA-MM-DD' -> fecha local a medianoche. null si no tiene esa forma. */
export function fechaLocal(iso: string | null | undefined): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso ?? '');
  if (!m) return null;
  const f = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return isNaN(f.getTime()) ? null : f;
}

/** Fecha local -> 'AAAA-MM-DD', lo que entiende un <input type="date"> y el API. */
export function aIso(f: Date): string {
  const mm = String(f.getMonth() + 1).padStart(2, '0');
  const dd = String(f.getDate()).padStart(2, '0');
  return `${f.getFullYear()}-${mm}-${dd}`;
}

/** Hoy, local, sin hora. */
export function hoy(): Date {
  const h = new Date();
  return new Date(h.getFullYear(), h.getMonth(), h.getDate());
}

/** Anios y meses CUMPLIDOS entre la fecha de nacimiento y hoy. null si la fecha no sirve. */
export function edadDe(fechaNacimiento: string | null | undefined, referencia: Date = hoy()): Edad | null {
  const n = fechaLocal(fechaNacimiento);
  if (!n || n > referencia) return null;

  let anios = referencia.getFullYear() - n.getFullYear();
  let meses = referencia.getMonth() - n.getMonth();
  if (referencia.getDate() < n.getDate()) meses -= 1;
  if (meses < 0) { anios -= 1; meses += 12; }
  return { anios, meses };
}

/**
 * La edad con palabras, corta: "25 años", "2 años 3 meses", "6 meses",
 * "menos de un mes". Hasta los dos anios se dicen los meses, que es lo que
 * importa en un bebe; de ahi en adelante solo los anios.
 */
export function edadTexto(e: Edad | null): string {
  if (!e) return '';
  const a = e.anios === 1 ? '1 año' : `${e.anios} años`;
  const m = e.meses === 1 ? '1 mes' : `${e.meses} meses`;
  if (e.anios >= 2) return a;
  if (e.anios === 0) return e.meses === 0 ? 'menos de un mes' : m;
  return e.meses === 0 ? a : `${a} ${m}`;
}

/** Lo mismo, abreviado para una celda de tabla: "25 a", "2 a 3 m", "6 m", "< 1 m". */
export function edadCorta(e: Edad | null): string {
  if (!e) return '';
  if (e.anios >= 2) return `${e.anios} a`;
  if (e.anios === 0) return e.meses === 0 ? '< 1 m' : `${e.meses} m`;
  return e.meses === 0 ? '1 a' : `1 a ${e.meses} m`;
}

/**
 * La fecha que va a calcular la base con esa edad: hoy menos los anios y
 * los meses (make_interval, restado a current_date). Se muestra en el
 * formulario ANTES de guardar, para que se vea lo que va a quedar.
 */
export function fechaEstimadaDe(anios: number, meses: number, referencia: Date = hoy()): Date {
  // Postgres resta el intervalo por meses de calendario y recorta al ultimo
  // dia si el mes destino es mas corto (31 mar - 1 mes = 28 feb). setMonth
  // en JS se pasa al mes siguiente, asi que se recorta a mano.
  const totalMeses = anios * 12 + meses;
  const dia = referencia.getDate();
  const f = new Date(referencia.getFullYear(), referencia.getMonth() - totalMeses, 1);
  const ultimo = new Date(f.getFullYear(), f.getMonth() + 1, 0).getDate();
  f.setDate(Math.min(dia, ultimo));
  return f;
}
