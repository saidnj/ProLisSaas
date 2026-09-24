import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Tx } from '../prisma/prisma.service';
import type { Sesion } from '../comun/sesion';
import { exigirPermiso } from '../comun/permiso';
import { CrearPacienteDto } from './dto/crear-paciente.dto';
import { ActualizarPacienteDto } from './dto/actualizar-paciente.dto';
import type { PacienteCompleto, PacienteDeLista, TipoDocumento } from './tipos';

/**
 * El mismo jsonb para la lista y para la ficha: una sola forma. La fecha
 * sale como AAAA-MM-DD (to_char) y no como timestamp: es un date, sin hora,
 * y asi el navegador no la corre un dia por la zona horaria.
 */
const FORMA_PACIENTE = `
  jsonb_build_object(
    'pacienteId',      p.paciente_id,
    'expediente',      p.expediente,
    'nombreCompleto',  p.nombre_completo,
    'tipoDocumento',   p.tipo_documento,
    'documento',       p.documento,
    'fechaNacimiento', to_char(p.fecha_nacimiento, 'YYYY-MM-DD'),
    'fechaEstimada',   p.fecha_nacimiento_estimada,
    'sexo',            p.sexo,
    'telefono',        p.telefono,
    'creadoEn',        p.creado_en
  )`;

const FORMA_PACIENTE_COMPLETO = `
  ${FORMA_PACIENTE} || jsonb_build_object(
    'correo',      p.correo,
    'direccion',   p.direccion,
    'fusionadoEn', p.fusionado_en_paciente_id
  )`;

const SIN_VER = 'No tenes permiso para ver pacientes';
const SIN_CREAR = 'No tenes permiso para registrar pacientes';
const SIN_EDITAR = 'No tenes permiso para editar pacientes';

/**
 * PACIENTES: buscar, ver, registrar, editar. Mismo molde que empleados y
 * roles: el servicio es el unico que le habla a core.paciente, y no le habla
 * a mano -- la tabla esta cerrada para escribir desde lis_app; se escribe
 * solo por core.registrar_paciente y core.editar_paciente. Cada una
 * comprueba adentro quien es y que puede (04_funciones.sql):
 *
 *   - hace falta paciente.crear / paciente.editar (en la sede del token)
 *   - la fecha de nacimiento O la edad, nunca las dos; con edad, la base
 *     calcula la fecha (hoy - edad) y la marca estimada
 *   - una fecha confirmada no se vuelve a estimar
 *   - un documento no se repite en la empresa (por su llave: sin guiones ni
 *     espacios); la base contesta 23505 con el expediente que ya lo tiene
 *   - un expediente fusionado en otro no se edita
 *
 * Leer va con RLS (rls_paciente: paciente.ver). Aqui se pregunta antes lo
 * que da un mejor mensaje (el permiso, el documento repetido con su campo
 * marcado); lo demas lo dice la base y el filtro lo traduce.
 *
 * Fijate que no hay ningun "where empresa_id": la sesion PONE EL CONTEXTO
 * y el filtro lo agrega Postgres. Una consulta nueva que se olvide del
 * filtro sigue sin poder ver los pacientes de otra empresa.
 */
@Injectable()
export class PacientesService {
  constructor(private readonly prisma: PrismaService) {}

  // ===================================================================
  //  BUSCAR - sin texto, los ultimos 50 registrados; con texto, por
  //  parecido y ordenados por coincidencia (core.buscar_pacientes).
  // ===================================================================
  async buscar(sesion: Sesion, q: string | undefined, limite: number | undefined): Promise<PacienteDeLista[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'paciente.ver', SIN_VER);

      // WITH ORDINALITY: el orden lo decide la funcion (escalon, parecido,
      // nombre) y jsonb_agg lo respeta por ese numero, no por casualidad.
      const [fila] = await tx.$queryRawUnsafe<{ lista: PacienteDeLista[] }[]>(
        `SELECT coalesce(jsonb_agg(${FORMA_PACIENTE} ORDER BY p.ordinality), '[]'::jsonb) AS lista
           FROM core.buscar_pacientes($1, $2) WITH ORDINALITY AS p`,
        q?.trim() || null,
        limite ?? 50,
      );

      return fila?.lista ?? [];
    });
  }

  // ===================================================================
  //  UNO SOLO
  // ===================================================================
  async obtener(sesion: Sesion, id: number): Promise<PacienteCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'paciente.ver', SIN_VER);
      return this.obtenerEn(tx, id);
    });
  }

  // ===================================================================
  //  REGISTRAR - un insert sencillo: la ficha y nada mas. El expediente lo
  //  pone la base (siguiente_correlativo de la empresa).
  // ===================================================================
  async crear(sesion: Sesion, dto: CrearPacienteDto): Promise<PacienteCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'paciente.crear', SIN_CREAR);
      await this.exigirDocumentoLibre(tx, dto.tipoDocumento ?? 'ninguno', dto.documento, null);

      const [r] = await tx.$queryRaw<{ paciente_id: bigint }[]>`
        SELECT core.registrar_paciente(
          ${dto.nombreCompleto},
          ${dto.tipoDocumento ?? 'ninguno'}::plataforma.tipo_documento,
          ${dto.documento ?? null},
          ${dto.fechaNacimiento ?? null}::date,
          ${dto.edadAnios ?? null}::int,
          ${dto.edadMeses ?? null}::int,
          ${dto.sexo}::plataforma.sexo,
          ${dto.telefono ?? null},
          ${dto.correo ?? null},
          ${dto.direccion ?? null}
        ) AS paciente_id`;

      return this.obtenerEn(tx, Number(r.paciente_id));
    });
  }

  // ===================================================================
  //  GUARDAR - la ficha entera tal como viene. Lo que vino igual no se
  //  escribe ni deja evento (editar_paciente devuelve false).
  // ===================================================================
  async actualizar(sesion: Sesion, id: number, dto: ActualizarPacienteDto): Promise<PacienteCompleto> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'paciente.editar', SIN_EDITAR);

      // Si es de otra empresa, RLS no lo oculta a medias: no existe.
      const [f] = await tx.$queryRaw<{ fusionado: boolean }[]>`
        SELECT p.fusionado_en_paciente_id IS NOT NULL AS fusionado
          FROM core.paciente p WHERE p.paciente_id = ${BigInt(id)}`;
      if (!f) throw new NotFoundException('No existe ese paciente');
      if (f.fusionado) {
        throw new ConflictException('Este expediente se fusiono en otro: se edita el que quedo');
      }

      await this.exigirDocumentoLibre(tx, dto.tipoDocumento ?? 'ninguno', dto.documento, id);

      await tx.$queryRaw`
        SELECT core.editar_paciente(
          ${BigInt(id)},
          ${dto.nombreCompleto},
          ${dto.tipoDocumento ?? 'ninguno'}::plataforma.tipo_documento,
          ${dto.documento ?? null},
          ${dto.fechaNacimiento ?? null}::date,
          ${dto.edadAnios ?? null}::int,
          ${dto.edadMeses ?? null}::int,
          ${dto.sexo}::plataforma.sexo,
          ${dto.telefono ?? null},
          ${dto.correo ?? null},
          ${dto.direccion ?? null}
        ) AS cambio`;

      return this.obtenerEn(tx, id);
    });
  }

  // ===================================================================
  //  AYUDANTES
  // ===================================================================

  private async obtenerEn(tx: Tx, id: number): Promise<PacienteCompleto> {
    const [fila] = await tx.$queryRawUnsafe<{ paciente: PacienteCompleto | null }[]>(
      `SELECT ${FORMA_PACIENTE_COMPLETO} AS paciente FROM core.paciente p WHERE p.paciente_id = $1`,
      BigInt(id),
    );

    if (!fila?.paciente) throw new NotFoundException('No existe ese paciente');
    return fila.paciente;
  }

  /**
   * "0801-2004-00844" y "080120040084 4" son el mismo documento
   * (core.llave_documento, la llave del indice uq_paciente_documento). La
   * base lo rechaza igual (23505 con el expediente); aqui se pregunta antes
   * para contestar 409 con el campo marcado y el mismo mensaje. Se dice EN
   * QUE EXPEDIENTE esta, a proposito: lo que recepcion quiere es abrir ese
   * y no crear otro. Los fusionados no cuentan: su documento vive en el que
   * quedo.
   */
  private async exigirDocumentoLibre(
    tx: Tx, tipo: TipoDocumento, documento: string | undefined, propio: number | null,
  ): Promise<void> {
    if (tipo === 'ninguno' || !documento?.trim()) return;
    const yo = propio === null ? null : BigInt(propio);

    const [f] = await tx.$queryRaw<{ expediente: string }[]>`
      SELECT p.expediente FROM core.paciente p
       WHERE p.tipo_documento = ${tipo}::plataforma.tipo_documento
         AND core.llave_documento(p.documento) = core.llave_documento(${documento})
         AND p.fusionado_en_paciente_id IS NULL
         AND (${yo}::bigint IS NULL OR p.paciente_id <> ${yo}::bigint)
       LIMIT 1`;

    if (f) {
      throw new ConflictException({
        statusCode: 409,
        message: `Ese documento ya esta registrado en el expediente ${f.expediente}`,
        campos: ['documento'],
      });
    }
  }
}
