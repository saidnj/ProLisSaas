import {
  ArgumentsHost, Catch, ExceptionFilter, HttpException,
  HttpStatus, Logger,
} from '@nestjs/common';
import { Response } from 'express';

/**
 * Traduce los errores que sube la BASE a respuestas HTTP.
 *
 * La base habla con SQLSTATE. Los que nos importan:
 *
 *   28000  sesion caducada          sesion_vigente() desde las politicas -> 401
 *   42501  sin permiso              exigir_permiso(), puede_crear(), y las
 *                                   politicas RLS al escribir            -> 403
 *   23505  duplicado                username repetido, convenio repetido -> 409
 *   21000  ambiguedad               username en dos empresas (H-101)     -> 409
 *   22023  dato invalido            horas fuera de rango, clave sin hash -> 400
 *   23514  CHECK                    un CHECK de tabla                    -> 400
 *   23503  llave foranea            apunta a algo que no existe          -> 400
 *   55006  en uso                   desactivar un rol que alguien tiene  -> 409
 *
 * Cualquier otra cosa es un 500 pelado: se registra entera del lado del
 * servidor y al cliente le va "Error interno". Un error de base sin filtrar
 * puede llevar nombres de tablas, columnas y hasta valores de otras filas.
 *
 * DONDE VIVE EL SQLSTATE -- confirmado con el error real, no con la doc:
 *
 *   Prisma 7 con adaptador de driver envuelve todo en un
 *   PrismaClientKnownRequestError con code 'P2010', y el error de Postgres
 *   queda en  meta.driverAdapterError.cause:
 *
 *     { originalCode: '28000', originalMessage: 'Sesion caducada: ...',
 *       kind: 'DatabaseAccessDenied' | 'UniqueConstraintViolation' | 'postgres' ... ,
 *       hint?: '...'   (solo cuando kind = 'postgres') }
 *
 *   meta.code viene undefined. La primera version de este filtro lo miraba
 *   ahi y por eso TODO salia como 500 -- incluido el 28000, con lo que un
 *   usuario suspendido a media sesion veia "Error interno" en vez de ser
 *   mandado al login. Se descubrio probando, no leyendo.
 */
@Catch()
export class ErroresBaseFilter implements ExceptionFilter {
  private readonly log = new Logger('ErroresBase');

  catch(exc: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();

    // Lo que ya es una excepcion de Nest pasa de largo.
    if (exc instanceof HttpException) {
      return res.status(exc.getStatus()).json(exc.getResponse());
    }

    const pg = this.leerErrorDePostgres(exc);
    const traducido = pg.sqlstate ? this.traducir(pg) : null;

    if (traducido) {
      // Un 4xx que nace en la base es normal -- alguien sin permiso, un
      // duplicado -- y no hace falta el objeto entero en el log: una linea.
      this.log.warn(`${pg.sqlstate} -> ${traducido.status}: ${pg.mensaje}`);
      return res.status(traducido.status).json({
        statusCode: traducido.status,
        message: traducido.mensaje,
        ...(pg.pista ? { hint: pg.pista } : {}),
      });
    }

    this.log.error(exc);
    return res.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: 500,
      message: 'Error interno',
    });
  }

  private traducir(pg: ErrorPg): { status: number; mensaje: string } | null {
    const m = pg.mensaje ?? '';

    switch (pg.sqlstate) {
      case '28000':
        return { status: 401, mensaje: m || 'Sesion caducada' };

      case '42501': {
        // Dos origenes con el mismo codigo. Si es un RAISE nuestro, el mensaje
        // ya esta escrito para una persona y se manda tal cual. Si es Postgres
        // rechazando un INSERT/UPDATE por la politica RLS, el mensaje trae el
        // nombre de la tabla en ingles (o en el idioma del servidor): se cambia
        // por uno nuestro.
        const esRls = /row-level security|seguridad de filas/i.test(m);
        return {
          status: 403,
          mensaje: esRls ? 'No tenes permiso para esa operacion en esta sede' : m,
        };
      }

      case '23505':
        return { status: 409, mensaje: this.mensajeDuplicado(pg) };

      case '21000':
        return { status: 409, mensaje: m || 'El dato es ambiguo' };

      case '55006':
        // object_in_use: "hay 3 empleados con este rol". El mensaje ya
        // viene escrito para una persona.
        return { status: 409, mensaje: m || 'Esta en uso' };

      case '22023':
      case '23514':
      case '23503':
        return { status: 400, mensaje: m || 'Dato invalido' };

      default:
        return null;
    }
  }

  /**
   * Los duplicados llegan como "duplicate key value violates unique constraint
   * uq_x": el nombre de la restriccion no le dice nada al usuario y le cuenta
   * el esquema a quien no deberia. Se traduce por restriccion; lo que no este
   * en la lista sale generico. Un RAISE nuestro con ese codigo (crear_rol:
   * "Ya hay un rol con ese nombre") no trae restriccion y ya viene escrito
   * para una persona: se manda tal cual.
   */
  private mensajeDuplicado(pg: ErrorPg): string {
    const conocidos: Record<string, string> = {
      uq_rol_nombre:        'Ya hay un rol con ese nombre',
      uq_usuario_username:  'Ese nombre de usuario ya existe en la empresa',
      uq_empleado_nombre:   'Ya hay un empleado con ese nombre',
      uq_empleado_documento:'Ya hay un empleado con ese numero de identidad',
      uq_empleado_telefono: 'Ya hay un empleado con ese telefono',
      uq_empleado_correo:   'Ya hay un empleado con ese correo',
      uq_empleado_colegiacion: 'Ya hay un empleado con ese numero de colegiacion',
      uq_convenio_nombre:   'Ya hay un convenio con ese nombre',
      uq_sucursal_codigo:   'Ya hay una sucursal con ese codigo',
      uq_sucursal_nombre:   'Ya hay una sucursal con ese nombre',
      uq_activacion_viva:   'Esa persona ya tiene un codigo de activacion vivo',
      uq_paciente_documento:'Ya hay un paciente con ese numero de identidad',
    };
    if (pg.restriccion) return conocidos[pg.restriccion] ?? 'Ya existe un registro igual';
    const m = pg.mensaje ?? '';
    const dePostgres = /duplicate key|llave duplicada/i.test(m);
    return m && !dePostgres ? m : 'Ya existe un registro igual';
  }

  /**
   * Saca SQLSTATE, mensaje, pista y restriccion de donde Prisma los ponga.
   * Primero el sitio de Prisma 7 con adaptador (el real hoy); despues los
   * sitios viejos, por si algun dia cambia el motor y no este archivo.
   */
  private leerErrorDePostgres(exc: any): ErrorPg {
    const causa = exc?.meta?.driverAdapterError?.cause;

    return {
      sqlstate:
        causa?.originalCode ??
        exc?.meta?.code ??
        exc?.code ??
        exc?.originalError?.code ??
        exc?.cause?.code,
      mensaje:
        causa?.originalMessage ?? exc?.meta?.message ?? exc?.message,
      pista:
        causa?.hint ?? exc?.meta?.hint ?? exc?.hint ?? exc?.originalError?.hint,
      // Prisma lo manda como { index: 'uq_x' } (o { fields: [...] } en otros
      // motores); tambien se acepta el string pelado por si cambia.
      restriccion:
        causa?.constraint?.index ??
        (typeof causa?.constraint === 'string' ? causa.constraint : undefined) ??
        exc?.meta?.constraint,
    };
  }
}

interface ErrorPg {
  sqlstate?: string;
  mensaje?: string;
  pista?: string;
  restriccion?: string;
}
