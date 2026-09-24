import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Sesion } from '../comun/sesion';
import type { ModuloDePermisos, RolDeCatalogo, SucursalDeCatalogo } from './tipos';

/**
 * LOS CATALOGOS: las listas para elegir algo (o para mostrar su nombre).
 * Un metodo por lista, todos con el mismo contrato (src/LEEME.md, regla 3):
 *
 *   - solo lectura: nunca escribe, nunca decide una regla
 *   - lo minimo para elegir bien: id, nombre, y algo mas solo si sin eso
 *     se elige mal
 *   - solo lo vigente: WHERE activo, siempre
 *   - el alcance lo pone la SESION, nunca el front: la empresa via RLS
 *     (como todo), y la sede del token (core.sucursal_actual()) cuando la
 *     cosa es de la sede. Cada metodo dice su alcance: empresa | sede
 *   - permiso: sesion vigente; las filas las decide la base
 *
 * Es una capa de LECTURA que mira tablas de varios modulos, y esta bien
 * que asi sea: no escribe en ninguna. Escribir y administrar es del modulo
 * dueno de cada tabla (empleados/, y manana sucursales/, roles/...).
 */
@Injectable()
export class CatalogoService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * ROLES. Alcance: empresa (un rol es de la empresa, no de una sede).
   * Solo los activos: un rol desactivado ya no se asigna (la ficha de
   * quien lo tenia lo sigue mostrando por su nombre, que viene con ella).
   * Trae de que modulos son sus permisos: cruzado con los modulos de cada
   * sede, el front sabe que le queda al rol en cada una.
   */
  async roles(sesion: Sesion): Promise<RolDeCatalogo[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      const [fila] = await tx.$queryRaw<{ lista: RolDeCatalogo[] }[]>`
        SELECT coalesce(jsonb_agg(x ORDER BY x->>'nombre'), '[]'::jsonb) AS lista
        FROM (
          SELECT jsonb_build_object(
                   'rolId',       r.rol_id,
                   'nombre',      r.nombre,
                   'descripcion', r.descripcion,
                   'esSistema',   r.es_sistema,
                   'esAdmin',     core.rol_es_admin(r.rol_id),
                   'modulos', (
                     SELECT coalesce(jsonb_agg(jsonb_build_object(
                              'id',       m.modulo_id,
                              'nombre',   mo.nombre,
                              'permisos', m.n) ORDER BY m.modulo_id), '[]'::jsonb)
                       FROM (
                         SELECT p.modulo_id, count(*) AS n
                           FROM core.rol_permiso rp
                           JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
                          WHERE rp.rol_id = r.rol_id AND rp.empresa_id = r.empresa_id
                          GROUP BY p.modulo_id
                       ) m
                       JOIN plataforma.modulo mo ON mo.modulo_id = m.modulo_id
                   )
                 ) AS x
          FROM core.rol r
          WHERE r.activo
        ) q`;

      return fila?.lista ?? [];
    });
  }

  /**
   * SUCURSALES. Alcance: empresa (se elige entre TODAS las abiertas: el
   * formulario de empleados asigna varias). Solo las abiertas: elegir una
   * sede cerrada es elegir nada.
   */
  async sucursales(sesion: Sesion): Promise<SucursalDeCatalogo[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      const [fila] = await tx.$queryRaw<{ lista: SucursalDeCatalogo[] }[]>`
        SELECT coalesce(jsonb_agg(x ORDER BY x->>'codigo'), '[]'::jsonb) AS lista
        FROM (
          SELECT jsonb_build_object(
                   'sucursalId', s.sucursal_id,
                   'codigo',     s.codigo,
                   'nombre',     s.nombre,
                   'modulos', (
                     SELECT coalesce(jsonb_agg(ms.modulo_id ORDER BY ms.modulo_id), '[]'::jsonb)
                       FROM plataforma.modulo_sucursal ms
                      WHERE ms.sucursal_id = s.sucursal_id
                        AND ms.empresa_id  = s.empresa_id
                        AND ms.activo
                   )
                 ) AS x
          FROM core.sucursal s
          WHERE s.activo
        ) q`;

      return fila?.lista ?? [];
    });
  }

  /**
   * PERMISOS. Alcance: empresa. Los que se le pueden poner a un rol: los de
   * los modulos que la empresa tiene contratados en alguna sede
   * (core.permisos_disponibles, recortada por RLS a la empresa del token),
   * agrupados por modulo para pintar las casillas. El NIVEL va porque sin
   * el se elige mal: uno de nivel 'propietario' no se asigna nunca, uno de
   * nivel 'admin' lo asigna solo el propietario, y marcar uno de esos
   * vuelve al rol "de administrador". Esa regla la aplica la base
   * (core.asignar_permisos_a_rol); aqui solo viaja el dato.
   */
  async permisos(sesion: Sesion): Promise<ModuloDePermisos[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      const [fila] = await tx.$queryRaw<{ lista: ModuloDePermisos[] }[]>`
        SELECT coalesce(jsonb_agg(x ORDER BY x->>'id'), '[]'::jsonb) AS lista
        FROM (
          SELECT jsonb_build_object(
                   'id',     m.modulo_id,
                   'nombre', m.nombre,
                   'permisos', (
                     SELECT jsonb_agg(jsonb_build_object(
                              'id',          d.permiso_id,
                              'descripcion', d.descripcion,
                              'nivel',       d.nivel) ORDER BY d.permiso_id)
                       FROM core.permisos_disponibles() d
                      WHERE d.modulo_id = m.modulo_id
                   )
                 ) AS x
          FROM plataforma.modulo m
          WHERE EXISTS (SELECT 1 FROM core.permisos_disponibles() d WHERE d.modulo_id = m.modulo_id)
        ) q`;

      return fila?.lista ?? [];
    });
  }
}
