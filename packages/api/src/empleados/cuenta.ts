import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import type { Tx } from '../prisma/prisma.service';
import { exigirRolConUso } from './rol-en-sedes';

/**
 * LO DE LA CUENTA, COMO FUNCIONES SUELTAS CON LA TRANSACCION EN LA MANO.
 *
 * Empleado y cuenta son uno, y todo entra por empleados/. Lo que toca la
 * cuenta -- sedes, rol, username, y la pregunta de si se puede tocar --
 * vive aqui, sin inyeccion ni modulo, para correr dentro de la transaccion
 * que abrio quien llama (crear, guardar, codigo nuevo, desbloquear, en
 * empleados.service.ts). Igual que rol-en-sedes.ts. No hay rutas sueltas
 * para sedes ni rol: el unico camino es guardar el empleado. Solo lo usa
 * este modulo; por eso vive aqui y no en comun/.
 *
 * Todas son idempotentes a proposito: llamarlas con el valor que ya tiene
 * no escribe nada y no deja evento. Asi el front puede mandar la cuenta
 * tal como esta en pantalla, sin comparar valores, y la base solo toca lo
 * que de verdad cambio. (Un UPDATE "igual" en Postgres no es gratis:
 * escribe una version nueva de la fila, WAL, y aqui ademas un evento de
 * auditoria falso. Por eso cambiar_rol y cambiar_username devuelven false
 * sin tocar nada, y las sedes se comparan antes de escribir.)
 *
 * Lo que NO es idempotente es el permiso: mandar la cuenta de alguien que
 * no se puede tocar (la de un administrador sin ser propietario, el rol
 * del propietario) se rechaza aunque venga igual. Tocar esa cuenta es de
 * quien puede, cambie o no; por eso el front no manda lo que le sale
 * bloqueado en pantalla.
 */

/** Lo que puede venir de la cuenta al guardar. Todo opcional: lo que no viene no se toca. */
export interface CambiosCuenta {
  username?: string;
  rolId?: number;
  motivoRol?: string;
  sucursales?: number[];
  motivoSedes?: string;
}

/**
 * La cuenta de un administrador (o la del propietario) la toca solo quien
 * tiene usuario.nombrar_admin. core.puede_tocar_cuenta() es la misma
 * pregunta que hacen la politica de acceso_sucursal y las funciones de la
 * base: aqui se hace antes, para que el 403 diga por que y el 404 sea 404.
 */
export async function exigirPoderTocar(tx: Tx, usuarioId: number): Promise<void> {
  const [r] = await tx.$queryRaw<{ administra: boolean; existe: boolean; puede: boolean }[]>`
    SELECT core.usuario_puede('usuario.administrar')     AS administra,
           EXISTS (SELECT 1 FROM core.usuario WHERE usuario_id = ${BigInt(usuarioId)}) AS existe,
           core.puede_tocar_cuenta(${BigInt(usuarioId)}) AS puede`;
  if (!r?.administra) {
    throw new ForbiddenException('No tenes permiso para administrar cuentas');
  }
  if (!r.existe) throw new NotFoundException('No existe ese usuario');
  if (!r.puede) {
    throw new ForbiddenException('Solo el propietario toca la cuenta de un administrador');
  }
}

/**
 * LA FICHA SIGUE A LA CUENTA. Nombre, cargo, correo, telefono parecen datos
 * inocentes, pero el correo y el telefono son el camino por donde llega (o
 * va a llegar) el codigo que restablece una clave: quien puede cambiarselos
 * a alguien puede quedarse con su cuenta. Por eso la ficha se edita con la
 * misma regla que la cuenta: la del propietario, solo el propietario; la de
 * un administrador, solo el propietario; las demas, quien administre. La
 * pared es rls_empleado_editar (core.puede_tocar_ficha); aqui se pregunta
 * antes para que el 403 diga de quien es la ficha y por que no.
 */
export async function exigirPoderTocarFicha(tx: Tx, empleadoId: number): Promise<void> {
  const [r] = await tx.$queryRaw<{ existe: boolean; puede: boolean; es_sistema: boolean | null }[]>`
    SELECT EXISTS (SELECT 1 FROM core.empleado WHERE empleado_id = ${BigInt(empleadoId)}) AS existe,
           core.puede_tocar_ficha(${BigInt(empleadoId)}) AS puede,
           (SELECT r.es_sistema
              FROM core.usuario u
              JOIN core.rol r ON r.rol_id = u.rol_id AND r.empresa_id = u.empresa_id
             WHERE u.empleado_id = ${BigInt(empleadoId)}) AS es_sistema`;
  if (!r?.existe) throw new NotFoundException('No existe ese empleado');
  if (!r.puede) {
    throw new ForbiddenException(
      r.es_sistema
        ? 'Los datos del propietario solo los edita el propietario'
        : 'Solo el propietario edita los datos de un administrador',
    );
  }
}

/** El rol que tiene, o 404 si no se ve (RLS: no es de esta empresa). */
export async function rolDe(tx: Tx, usuarioId: number): Promise<bigint> {
  const fila = await tx.$queryRaw<{ rol_id: bigint }[]>`
    SELECT rol_id FROM core.usuario WHERE usuario_id = ${BigInt(usuarioId)}`;
  if (fila.length === 0) throw new NotFoundException('No existe ese usuario');
  return fila[0].rol_id;
}

/**
 * EN QUE SEDES QUEDA PARADO. Recibe el conjunto completo y lo deja igual:
 * retira las que ya no vienen, da las que faltan, y NO toca las que ya
 * estaban. Todo en la transaccion que recibe: si retirara y despues
 * fallara al dar, el usuario quedaria sin ninguna sede y sin poder entrar.
 *
 * Retirar es un UPDATE con motivo, nunca un DELETE: que en marzo Gabriela
 * pudiera entrar a la sede Norte es un hecho que paso, y borrarlo no lo
 * deshace, solo lo esconde.
 */
export async function fijarSedes(
  tx: Tx, usuarioId: number, rolId: bigint, sucursales: number[], motivoDado?: string,
) {
  const lista = '{' + sucursales.join(',') + '}';

  // Que alguna de las pedidas exista y este abierta. Se pregunta ANTES de
  // retirar nada: por un id mal escrito nadie queda encerrado afuera.
  const [validas] = await tx.$queryRaw<{ n: bigint }[]>`
    SELECT count(*) AS n FROM core.sucursal s
     WHERE s.sucursal_id = ANY(${lista}::bigint[]) AND s.activo`;
  if (Number(validas.n) === 0) {
    throw new BadRequestException('Ninguna de esas sucursales existe o esta abierta en tu empresa');
  }

  // Con las sedes nuevas, el rol le sigue sirviendo en alguna? Misma regla
  // que al crear (rol-en-sedes.ts): lo parcial se permite, el cero no.
  await exigirRolConUso(tx, rolId, sucursales);

  const motivo = motivoDado?.trim() || 'retirado desde la administracion de usuarios';

  // 1 - Retirar las activas que ya no vienen. El motivo es obligatorio por
  //     el CHECK ck_acceso_motivo, asi que si no lo mandan va uno generico.
  const retiradas = await tx.$queryRaw<{ sucursal_id: bigint }[]>`
    UPDATE core.acceso_sucursal
       SET activo = false, retirado_en = now(), retirado_motivo = ${motivo}
     WHERE usuario_id = ${BigInt(usuarioId)}
       AND activo
       AND NOT (sucursal_id = ANY(${lista}::bigint[]))
    RETURNING sucursal_id`;

  // 2 - Dar las que faltan. ON CONFLICT porque la que se retiro alguna vez
  //     ya tiene su fila: volver a darle acceso es revivir esa misma fila.
  //     El WHERE del DO UPDATE es lo que hace que una fila ya activa NO se
  //     reescriba: guardar sin cambios no toca nada.
  const dadas = await tx.$queryRaw<{ sucursal_id: bigint }[]>`
    INSERT INTO core.acceso_sucursal (usuario_id, sucursal_id, empresa_id)
    SELECT ${BigInt(usuarioId)}, s.sucursal_id, s.empresa_id
      FROM core.sucursal s
     WHERE s.sucursal_id = ANY(${lista}::bigint[])
       AND s.activo
    ON CONFLICT (usuario_id, sucursal_id) DO UPDATE
       SET activo = true, retirado_en = NULL, retirado_motivo = NULL
     WHERE NOT core.acceso_sucursal.activo
    RETURNING core.acceso_sucursal.sucursal_id`;

  const activas = await tx.$queryRaw<{ sucursal_id: bigint }[]>`
    SELECT sucursal_id FROM core.acceso_sucursal
     WHERE usuario_id = ${BigInt(usuarioId)} AND activo ORDER BY sucursal_id`;

  return {
    sucursales: activas.map((x) => Number(x.sucursal_id)),
    dadas: dadas.map((x) => Number(x.sucursal_id)),
    retiradas: retiradas.map((x) => Number(x.sucursal_id)),
  };
}

/**
 * EL ROL. La regla vive en core.cambiar_rol(), la unica forma de escribir
 * usuario.rol_id: el rol del propietario ni se cambia ni se asigna, y
 * nombrar o retirar un administrador exige usuario.nombrar_admin. Aqui se
 * agrega lo que la base no sabe: que el rol nuevo le SIRVA en las sedes
 * donde esta parado. Devuelve false si ya era ese (y no deja evento).
 */
export async function ponerRol(tx: Tx, usuarioId: number, rolId: number, motivo?: string): Promise<boolean> {
  const sedes = await tx.$queryRaw<{ sucursal_id: bigint }[]>`
    SELECT sucursal_id FROM core.acceso_sucursal
     WHERE usuario_id = ${BigInt(usuarioId)} AND activo`;
  if (sedes.length > 0) {
    await exigirRolConUso(tx, BigInt(rolId), sedes.map((s) => Number(s.sucursal_id)));
  }

  const [r] = await tx.$queryRaw<{ cambio: boolean }[]>`
    SELECT core.cambiar_rol(${BigInt(usuarioId)}, ${BigInt(rolId)},
                            ${motivo?.trim() || null}) AS cambio`;
  return r.cambio;
}

/** EL USERNAME. core.cambiar_username() lo normaliza, lo valida y devuelve false si ya era ese. */
export async function ponerUsername(tx: Tx, usuarioId: number, username: string): Promise<boolean> {
  const [r] = await tx.$queryRaw<{ cambio: boolean }[]>`
    SELECT core.cambiar_username(${BigInt(usuarioId)}, ${username}) AS cambio`;
  return r.cambio;
}

/**
 * TODO LO DE LA CUENTA, EN ORDEN: sedes, rol, username. El orden importa:
 * la base comprueba que el rol le sirva en las sedes donde QUEDA parado, y
 * si vienen las dos cosas las sedes se comprueban contra el rol NUEVO.
 * Cada paso es idempotente; lo que no viene no se toca.
 */
export async function aplicarCuenta(tx: Tx, usuarioId: number, c: CambiosCuenta) {
  await exigirPoderTocar(tx, usuarioId);

  const hecho: { sucursales?: number[]; retiradas?: number[]; rolCambio?: boolean; usernameCambio?: boolean } = {};

  if (c.sucursales) {
    const rol = c.rolId !== undefined ? BigInt(c.rolId) : await rolDe(tx, usuarioId);
    const r = await fijarSedes(tx, usuarioId, rol, c.sucursales, c.motivoSedes);
    hecho.sucursales = r.sucursales;
    hecho.retiradas = r.retiradas;
  }
  if (c.rolId !== undefined) {
    hecho.rolCambio = await ponerRol(tx, usuarioId, c.rolId, c.motivoRol);
  }
  if (c.username !== undefined) {
    hecho.usernameCambio = await ponerUsername(tx, usuarioId, c.username);
  }
  return hecho;
}
