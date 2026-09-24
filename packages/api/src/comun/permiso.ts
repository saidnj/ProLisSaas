import { ForbiddenException } from '@nestjs/common';
import type { Tx } from '../prisma/prisma.service';

/**
 * "Tiene el permiso, en la sede donde esta parado?" -- dentro de la
 * transaccion de quien llama. La misma pregunta que hace la base adentro de
 * cada funcion (core.usuario_puede), hecha antes para contestar un 403 con
 * un mensaje que se entienda en vez de un error de Postgres.
 *
 * Vive en comun/ porque lo usan dos modulos (empleados y roles). No es la
 * seguridad: es la cortesia. La pared son las funciones SECURITY DEFINER y
 * las politicas RLS, que lo vuelven a comprobar aunque este archivo no
 * exista.
 */
export async function exigirPermiso(tx: Tx, permiso: string, mensaje: string): Promise<void> {
  const [f] = await tx.$queryRaw<{ puede: boolean }[]>`
    SELECT core.usuario_puede(${permiso}) AS puede`;

  if (!f?.puede) throw new ForbiddenException(mensaje);

  // EL ::text NO SOBRA, y si alguien lo quita esto vuelve a romperse.
  //
  // core.exigir_permiso() devuelve void. Prisma intenta deserializar cada
  // columna que vuelve y no sabe que hacer con el tipo void:
  //
  //   Failed to deserialize column of type 'void'
  //
  // El cast la convierte en una cadena vacia, que si sabe leer. La funcion
  // corre igual y su RAISE sigue subiendo -- lo unico que cambia es el
  // envoltorio de lo que devuelve, que de todos modos no se mira.
  await tx.$queryRaw`SELECT core.exigir_permiso(${permiso})::text AS ok`;
}
