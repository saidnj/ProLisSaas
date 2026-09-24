import { ConflictException } from '@nestjs/common';
import type { Tx } from '../prisma/prisma.service';

/**
 * UN EMPLEADO NO SE REPITE.
 *
 * Dentro de la empresa no puede haber dos personas con el mismo nombre
 * (nombres + apellidos, la suma), la misma identidad, el mismo telefono, el
 * mismo correo, la misma colegiacion ni el mismo usuario. Que "mismo"
 * significa lo deciden las llaves de la base (core.llave_nombre,
 * llave_documento, llave_telefono, llave_correo, en 01_tipos.sql): "Said
 * Gabriel" y "said gabriel", "+504 9933-4455" y "9933-4455" son lo mismo.
 *
 * La garantia son los indices unicos de 03_indices.sql: si dos guardan a
 * la vez, el segundo revienta con 23505 y el filtro lo vuelve un 409
 * generico. Esto de aqui se pregunta ANTES de escribir, con la misma llave,
 * para devolver todos los choques de una vez -- no uno por intento -- y
 * que la pantalla marque cada campo.
 *
 * Se dice QUE dato ya esta en uso, no DE QUIEN: el formulario no es lugar
 * para senalar la ficha de otra persona.
 */

/** Los campos que no se repiten. 'nombre' es nombres + apellidos. */
export type CampoUnico = 'nombre' | 'documento' | 'telefono' | 'correo' | 'colegiacion' | 'username';

export interface DatosAComparar {
  nombres: string;
  apellidos: string;
  documento?: string | null;
  telefono?: string | null;
  correo?: string | null;
  numeroColegiacion?: string | null;
  /** El usuario que se le va a poner (al crear, o al cambiarlo). */
  username?: string | null;
}

const ETIQUETA: Record<CampoUnico, string> = {
  nombre: 'ese nombre',
  documento: 'ese numero de identidad',
  telefono: 'ese telefono',
  correo: 'ese correo',
  colegiacion: 'ese numero de colegiacion',
  username: 'ese usuario',
};

/**
 * Lanza 409 con la lista de campos si algun dato ya es de OTRO empleado de
 * la empresa (RLS recorta la consulta a la empresa de la sesion). Al editar,
 * `propio` es el empleado que se esta guardando: sus propios datos no chocan
 * consigo mismo.
 */
export async function exigirSinDuplicados(tx: Tx, d: DatosAComparar, propio: number | null): Promise<void> {
  const yo = propio === null ? null : BigInt(propio);

  // Una consulta para los cinco de la ficha: por cada campo, si ALGUN otro
  // empleado ya lo tiene. Solo eso: ni quien ni cuantos.
  const [f] = await tx.$queryRaw<{
    nombre: boolean; documento: boolean; telefono: boolean; correo: boolean; colegiacion: boolean;
  }[]>`
    SELECT bool_or(core.llave_nombre(e.nombres, e.apellidos) = core.llave_nombre(${d.nombres}, ${d.apellidos})) AS nombre,
           bool_or(core.llave_documento(e.documento) = core.llave_documento(${d.documento ?? null})) AS documento,
           bool_or(core.llave_telefono(e.telefono) = core.llave_telefono(${d.telefono ?? null})) AS telefono,
           bool_or(core.llave_correo(e.correo) = core.llave_correo(${d.correo ?? null})) AS correo,
           bool_or(core.llave_documento(e.numero_colegiacion) = core.llave_documento(${d.numeroColegiacion ?? null})) AS colegiacion
      FROM core.empleado e
     WHERE ${yo}::bigint IS NULL OR e.empleado_id <> ${yo}::bigint`;

  const campos: CampoUnico[] = [];
  if (f?.nombre) campos.push('nombre');
  if (f?.documento) campos.push('documento');
  if (f?.telefono) campos.push('telefono');
  if (f?.correo) campos.push('correo');
  if (f?.colegiacion) campos.push('colegiacion');

  // El usuario vive en core.usuario; misma regla que uq_usuario_username.
  if (d.username) {
    const [u] = await tx.$queryRaw<{ existe: boolean }[]>`
      SELECT EXISTS (
        SELECT 1 FROM core.usuario u
         WHERE lower(u.username) = lower(${d.username.trim()})
           AND (${yo}::bigint IS NULL OR u.empleado_id <> ${yo}::bigint)) AS existe`;
    if (u?.existe) campos.push('username');
  }

  if (campos.length === 0) return;

  // Un solo mensaje con todo, y la lista aparte para que la pantalla marque
  // cada campo.
  const partes = campos.map((c) => ETIQUETA[c]);
  throw new ConflictException({
    statusCode: 409,
    message: campos.length === 1
      ? `Ya hay otro empleado con ${partes[0]}`
      : `Ya hay otro empleado con ${partes.slice(0, -1).join(', ')} y ${partes.at(-1)}`,
    campos,
  });
}
