import { BadRequestException } from '@nestjs/common';
import type { Tx } from '../prisma/prisma.service';

/**
 * UN ROL NO ES DE UNA SEDE, PERO PUEDE NO SERVIR EN ELLA.
 *
 * El rol es una bolsa de permisos de la empresa (core.rol_permiso). Cada
 * permiso pertenece a un modulo (plataforma.permiso.modulo_id), y la sede
 * es la que tiene modulos encendidos o apagados (plataforma.modulo_sucursal).
 * Asi que "Bioquimico en una sede sin laboratorio" no es un rol que no
 * exista: es un rol del que ahi solo quedan vivos los permisos del nucleo.
 *
 * Eso se PERMITE -- un jefe de sede cubriendo una sede sin laboratorio es
 * legitimo -- y el front lo avisa. Lo que NO se permite es el caso cero:
 * que en NINGUNA de las sedes elegidas le quede un solo permiso util. Esa
 * cuenta no podria hacer nada en ningun lado, y quien la creo no lo sabria
 * hasta que la persona llame preguntando por que todo le sale prohibido.
 *
 * El front ya lo impide con la lista de roles evaluada por sede; esto es
 * la ultima linea, la que atrapa al que llama al API sin pasar por el
 * front. La misma regla se aplica al crear (rol nuevo, sedes nuevas) y al
 * cambiar sedes (rol que ya tiene, sedes nuevas); por eso vive aqui y no
 * en uno de los dos servicios.
 */
export async function exigirRolConUso(
  tx: Tx,
  rolId: bigint,
  sucursales: number[],
): Promise<void> {
  // El arreglo va tal cual: Prisma lo manda como parametro bigint[].
  const lista = sucursales.map((id) => BigInt(id));

  // Dos EXISTS y un nombre en una sola ida. rol_permiso y modulo_sucursal
  // estan recortadas por RLS a la empresa de la sesion, asi que un rol o
  // una sede de otra empresa simplemente no aparecen: 'nombre' sale null y
  // se contesta "no existe", que es lo unico que ese cliente tiene derecho
  // a saber.
  const [r] = await tx.$queryRaw<{ nombre: string | null; sirve: boolean }[]>`
    SELECT
      (SELECT r.nombre FROM core.rol r WHERE r.rol_id = ${rolId}) AS nombre,
      EXISTS (
        SELECT 1
          FROM core.rol_permiso rp
          JOIN plataforma.permiso p
            ON p.permiso_id = rp.permiso_id
          JOIN plataforma.modulo_sucursal ms
            ON ms.modulo_id  = p.modulo_id
           AND ms.empresa_id = rp.empresa_id
           AND ms.activo
         WHERE rp.rol_id = ${rolId}
           AND ms.sucursal_id = ANY (${lista}::bigint[])
      ) AS sirve`;

  if (!r?.nombre) {
    throw new BadRequestException('Ese rol no existe en tu empresa');
  }
  if (!r.sirve) {
    throw new BadRequestException(
      `El rol "${r.nombre}" no tiene ningun permiso utilizable en las sedes elegidas: ` +
        'ninguna tiene encendidos los modulos que ese rol necesita',
    );
  }
}
