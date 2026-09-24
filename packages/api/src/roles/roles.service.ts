import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Tx } from '../prisma/prisma.service';
import type { Sesion } from '../comun/sesion';
import { exigirPermiso } from '../comun/permiso';
import { CrearRolDto } from './dto/crear-rol.dto';
import { ActualizarRolDto } from './dto/actualizar-rol.dto';
import type { RolCompleto, RolDeLista } from './tipos';

/** El mismo jsonb para listar y para la ficha: una sola forma. */
const FORMA_ROL = `
  jsonb_build_object(
    'rolId',       r.rol_id,
    'nombre',      r.nombre,
    'descripcion', r.descripcion,
    'esSistema',   r.es_sistema,
    'esFijo',      r.es_fijo,
    'esAdmin',     core.rol_es_admin(r.rol_id),
    'activo',      r.activo,
    'esElMio',     r.rol_id = (SELECT u.rol_id FROM core.usuario u
                                WHERE u.usuario_id = core.usuario_actual()),
    'cuantosPermisos', (SELECT count(*) FROM core.rol_permiso rp
                         WHERE rp.rol_id = r.rol_id AND rp.empresa_id = r.empresa_id),
    'cuantosEmpleados', (SELECT count(*) FROM core.usuario u
                          WHERE u.rol_id = r.rol_id AND u.empresa_id = r.empresa_id)
  )`;

/** La ficha: lo de la lista mas los permisos y quienes lo tienen. */
const FORMA_ROL_COMPLETO = `
  ${FORMA_ROL} || jsonb_build_object(
    'permisos', (SELECT coalesce(jsonb_agg(rp.permiso_id ORDER BY rp.permiso_id), '[]'::jsonb)
                   FROM core.rol_permiso rp
                  WHERE rp.rol_id = r.rol_id AND rp.empresa_id = r.empresa_id),
    'empleados', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'empleadoId', e.empleado_id,
                           'nombres',    e.nombres,
                           'apellidos',  e.apellidos,
                           'cargo',      e.cargo,
                           'activo',     e.activo,
                           'estado',     u.estado
                         ) ORDER BY e.apellidos, e.nombres), '[]'::jsonb)
                    FROM core.usuario u
                    JOIN core.empleado e
                      ON e.empleado_id = u.empleado_id
                     AND e.empresa_id  = u.empresa_id
                   WHERE u.rol_id = r.rol_id AND u.empresa_id = r.empresa_id)
  )`;

const SIN_PERMISO = 'No tenes permiso para administrar roles';

/**
 * ROLES: crear, editar, ver. Mismo molde que empleados: el servicio es el
 * unico que le habla a core.rol, y no le habla a mano -- core.rol esta
 * cerrada para lis_app; se escribe solo por core.crear_rol, editar_rol,
 * desactivar_rol y reactivar_rol, y los permisos por
 * core.asignar_permisos_a_rol. Cada una comprueba adentro quien es y que
 * puede (05_privilegios.sql y 04_funciones.sql):
 *
 *   - hace falta usuario.administrar (en la sede del token)
 *   - un rol FIJO (Propietario, Administrador) no se edita ni se desactiva
 *   - nadie edita el rol que tiene puesto
 *   - un rol de ADMINISTRADOR (con algun permiso de nivel 'admin') lo edita
 *     solo el propietario -- y un permiso de nivel 'admin' lo pone solo el
 *     propietario, y uno de nivel 'propietario' nadie
 *   - solo permisos de modulos contratados
 *   - no se desactiva un rol que alguien tiene puesto (55006 -> 409)
 *
 * Aqui se pregunta antes lo que da un mensaje mejor (el permiso, el nombre
 * repetido con su campo marcado); lo demas lo dice la base y el filtro lo
 * traduce.
 */
@Injectable()
export class RolesService {
  constructor(private readonly prisma: PrismaService) {}

  // ===================================================================
  //  LISTAR - todos, activos e inactivos: la pantalla de administrar.
  //  (Para ELEGIR un rol esta /catalogo/roles, solo los activos.)
  // ===================================================================
  async listar(sesion: Sesion): Promise<RolDeLista[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', SIN_PERMISO);

      // Sin WHERE empresa_id: RLS lo pone. Primero el del propietario, despues
      // los fijos, despues por nombre: los que "vienen con la casa" arriba.
      const [fila] = await tx.$queryRawUnsafe<{ lista: RolDeLista[] }[]>(`
        SELECT coalesce(jsonb_agg(x ORDER BY (x->>'esSistema')::boolean DESC,
                                            (x->>'esFijo')::boolean DESC,
                                            x->>'nombre'), '[]'::jsonb) AS lista
        FROM (SELECT ${FORMA_ROL} AS x FROM core.rol r) q`);

      return fila?.lista ?? [];
    });
  }

  // ===================================================================
  //  UNO SOLO
  // ===================================================================
  async obtener(sesion: Sesion, id: number): Promise<RolCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', SIN_PERMISO);
      return this.obtenerEn(tx, id);
    });
  }

  // ===================================================================
  //  CREAR - el rol y sus permisos. UNA transaccion.
  //
  //    core.crear_rol(nombre, descripcion)        -> sale el rol_id
  //    core.asignar_permisos_a_rol(rol_id, [...]) -> usa ese id
  //
  //  Si los permisos no pasan (uno de nivel admin sin ser el propietario,
  //  uno de un modulo no contratado), el rol recien creado se deshace con
  //  ellos: no queda un rol vacio con nombre.
  // ===================================================================
  async crear(sesion: Sesion, dto: CrearRolDto): Promise<RolCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', SIN_PERMISO);
      await this.exigirNombreLibre(tx, dto.nombre, null);

      const [r] = await tx.$queryRaw<{ rol_id: bigint }[]>`
        SELECT core.crear_rol(${dto.nombre}, ${dto.descripcion.trim()}) AS rol_id`;

      await tx.$queryRaw`
        SELECT core.asignar_permisos_a_rol(${r.rol_id}, ${dto.permisos}::text[]) AS n`;

      return this.obtenerEn(tx, Number(r.rol_id));
    });
  }

  // ===================================================================
  //  GUARDAR - nombre, descripcion, permisos y estado, tal como vienen.
  //  UNA transaccion; lo que vino igual no se escribe ni deja evento.
  //
  //  El orden importa: primero lo que puede fallar por regla (editar,
  //  permisos) y al final el estado. Desactivar comprueba que nadie lo
  //  tenga puesto; reactivar no comprueba nada.
  // ===================================================================
  async actualizar(sesion: Sesion, id: number, dto: ActualizarRolDto): Promise<RolCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', SIN_PERMISO);

      // Si es de otra empresa, RLS no lo oculta a medias: no existe.
      const [f] = await tx.$queryRaw<{ activo: boolean }[]>`
        SELECT r.activo FROM core.rol r WHERE r.rol_id = ${BigInt(id)}`;
      if (!f) throw new NotFoundException('No existe ese rol');

      await this.exigirNombreLibre(tx, dto.nombre, id);

      await tx.$queryRaw`
        SELECT core.editar_rol(${BigInt(id)}, ${dto.nombre}, ${dto.descripcion.trim()}) AS cambio`;

      await tx.$queryRaw`
        SELECT core.asignar_permisos_a_rol(${BigInt(id)}, ${dto.permisos}::text[]) AS n`;

      if (dto.activo === false && f.activo) {
        await tx.$queryRaw`
          SELECT core.desactivar_rol(${BigInt(id)}, ${dto.motivo?.trim() || null}) AS cambio`;
      } else if (dto.activo === true && !f.activo) {
        await tx.$queryRaw`SELECT core.reactivar_rol(${BigInt(id)}) AS cambio`;
      }

      return this.obtenerEn(tx, id);
    });
  }

  // ===================================================================
  //  AYUDANTES
  // ===================================================================

  private async obtenerEn(tx: Tx, id: number): Promise<RolCompleto> {
    const [fila] = await tx.$queryRawUnsafe<{ rol: RolCompleto | null }[]>(
      `SELECT ${FORMA_ROL_COMPLETO} AS rol FROM core.rol r WHERE r.rol_id = $1`,
      BigInt(id),
    );

    if (!fila?.rol) throw new NotFoundException('No existe ese rol');
    return fila.rol;
  }

  /**
   * "Recepcion", "recepcion " y "Recepcion" con acento son el mismo nombre
   * (core.llave_texto, la llave del indice uq_rol_nombre). La base lo
   * rechaza igual (23505); aqui se pregunta antes para contestar 409 con el
   * campo marcado, como hace empleados con sus duplicados. Se dice que el
   * nombre esta en uso, no cual rol lo tiene... aunque aqui da lo mismo:
   * la lista de roles la ve quien administra.
   */
  private async exigirNombreLibre(tx: Tx, nombre: string, propio: number | null): Promise<void> {
    const yo = propio === null ? null : BigInt(propio);

    const [f] = await tx.$queryRaw<{ existe: boolean }[]>`
      SELECT EXISTS (
        SELECT 1 FROM core.rol r
         WHERE core.llave_texto(r.nombre) = core.llave_texto(${nombre})
           AND (${yo}::bigint IS NULL OR r.rol_id <> ${yo}::bigint)) AS existe`;

    if (f?.existe) {
      throw new ConflictException({
        statusCode: 409,
        message: 'Ya hay un rol con ese nombre',
        campos: ['nombre'],
      });
    }
  }
}
