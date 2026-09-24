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
  // UNA consulta. Antes habia dos: usuario_puede() para el mensaje y despues
  // exigir_permiso() "por si acaso". La segunda nunca podia fallar si la
  // primera dio true -- preguntan lo mismo -- y era una ida a la base de mas
  // en cada peticion protegida.
  const [f] = await tx.$queryRaw<{ puede: boolean }[]>`
    SELECT core.usuario_puede(${permiso}) AS puede`;

  if (!f?.puede) throw new ForbiddenException(mensaje);
}

/*
 * NOTA sobre las funciones que devuelven void (exigir_permiso,
 * registrar_acceso...): Prisma intenta deserializar cada columna que vuelve
 * y no sabe que hacer con el tipo void:
 *
 *   Failed to deserialize column of type 'void'
 *
 * Por eso se llaman con ::text -- SELECT core.registrar_acceso($1)::text --
 * que las convierte en una cadena vacia. La funcion corre igual y su RAISE
 * sigue subiendo; solo cambia el envoltorio de lo que devuelve.
 */
