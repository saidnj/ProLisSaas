import { Injectable, UnauthorizedException, ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { PrismaService, Tx } from '../prisma/prisma.service';
import type { CargaToken, Sesion } from '../comun/sesion';
import type { DatosSesion, RespuestaSesion } from './tipos';
import { LoginDto } from './dto/login.dto';
import { ActivarDto } from './dto/activar.dto';
import { normalizarCodigo } from '../comun/codigo';

interface Credencial {
  usuario_id: bigint;  empresa_id: bigint;  username: string;
  password_hash: string;  estado_usuario: string;  intentos_fallidos: number;
  empleado_id: bigint;  nombre: string;
  rol_id: bigint;  rol: string;
  empresa: string;  estado_empresa: string;  nivel_acceso: string;
  fecha_cierre: Date | null;
}

interface Activacion {
  activacion_id: bigint;  usuario_id: bigint;  empresa_id: bigint;
  codigo_hash: string;  vence_en: Date;  intentos_fallidos: number;
}

const MAX_INTENTOS = 5;

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
  ) {}

  // ===================================================================
  //  ENTRAR
  // ===================================================================
  async entrar(dto: LoginDto): Promise<RespuestaSesion> {
    // sinSesion() porque todavia no se sabe de que empresa es. Adentro, lo
    // unico legible es esta funcion: es SECURITY DEFINER y por eso se salta
    // RLS. Una consulta normal a core.usuario aqui devolveria cero filas.
    const filas = await this.prisma.sinSesion((tx) =>
      tx.$queryRaw<Credencial[]>`
        SELECT * FROM core.buscar_credencial(
          ${dto.username}, ${dto.empresaId ? BigInt(dto.empresaId) : null}::bigint)`,
    );

    const cred = filas[0];

    // El mismo mensaje para "no existe" y para "clave mala". Distinguirlos le
    // regala a un atacante una lista de usuarios validos.
    const noEntra = new UnauthorizedException('Usuario o clave incorrectos');
    if (!cred) throw noEntra;

    // Se mira el NIVEL, no el estado. El estado es el hecho comercial -- por
    // que esta asi -- y su interpretacion vive del otro lado de la frontera
    // (E-18). El nivel es la consecuencia, y es lo unico que cruza.
    if (cred.nivel_acceso === 'bloqueado') {
      throw new ForbiddenException('El acceso de la empresa esta bloqueado');
    }
    if (cred.fecha_cierre && cred.fecha_cierre <= new Date()) {
      throw new ForbiddenException('La empresa esta cerrada');
    }

    // pendiente_activacion tiene su propio mensaje: no es un rechazo, es una
    // instruccion. La persona tiene un codigo esperandola.
    if (cred.estado_usuario === 'pendiente_activacion') {
      throw new ForbiddenException(
        'Esta cuenta todavia no tiene clave. Activala con el codigo que te dio el administrador.',
      );
    }
    if (cred.estado_usuario !== 'activo') {
      throw new ForbiddenException(`Usuario ${cred.estado_usuario}`);
    }

    // La clave se verifica AQUI, nunca en SQL: compararla en SQL la deja
    // escrita en el registro de consultas y abre la puerta a medir por tiempo.
    const buena = await argon2.verify(cred.password_hash, dto.password).catch(() => false);
    if (!buena) {
      await this.contarFallo(cred);
      throw noEntra;
    }

    return this.abrirSesion(cred);
  }

  // ===================================================================
  //  ACTIVAR - estrenar la clave con el codigo
  // ===================================================================
  async activar(dto: ActivarDto): Promise<RespuestaSesion> {
    const codigo = normalizarCodigo(dto.codigo);

    // Mismo patron que el login: sin sesion, y lo unico legible es la funcion
    // SECURITY DEFINER. lis_app no tiene ni SELECT sobre core.activacion.
    const filas = await this.prisma.sinSesion((tx) =>
      tx.$queryRaw<Activacion[]>`
        SELECT * FROM core.buscar_activacion(
          ${dto.username}, ${dto.empresaId ? BigInt(dto.empresaId) : null}::bigint)`,
    );

    const act = filas[0];

    // Un solo mensaje para "no hay codigo vivo", "ya se uso" y "vencio": no
    // hace falta decirle a un desconocido en cual de los tres esta.
    const malCodigo = new UnauthorizedException(
      'El codigo no es valido, ya se uso o vencio. Pedi otro al administrador.',
    );
    if (!act) throw malCodigo;

    const cuadra = await argon2.verify(act.codigo_hash, codigo).catch(() => false);
    if (!cuadra) {
      // Sube el contador, y al quinto la base anula el codigo sola.
      // El ::text es por lo mismo que en empleados.service.ts:
      // activacion_fallida() devuelve void y Prisma no sabe deserializar ese
      // tipo. Aqui todavia no habia reventado porque esta rama solo corre
      // cuando alguien escribe mal el codigo -- que es justo el momento en
      // que menos ganas hay de encontrarse un 500.
      await this.prisma.sinSesion((tx) =>
        tx.$queryRaw`SELECT core.activacion_fallida(${act.activacion_id}, ${MAX_INTENTOS})::text AS ok`,
      );
      throw malCodigo;
    }

    if (normalizarCodigo(dto.claveNueva) === codigo) {
      throw new ForbiddenException('La clave no puede ser el codigo de activacion');
    }

    const claveHash = await argon2.hash(dto.claveNueva, { type: argon2.argon2id });

    // Gasta el codigo y estrena la clave en una sola transaccion: o pasan las
    // tres cosas o no pasa ninguna.
    await this.prisma.sinSesion((tx) =>
      tx.$queryRaw`SELECT * FROM core.activar_usuario(${act.activacion_id}, ${claveHash})`,
    );

    // Ya con la clave puesta, se relee la credencial para armar la sesion. Y
    // se entra directo: acaba de demostrar que tiene el codigo Y de definir su
    // clave. Mandarla a escribirlo todo otra vez no agrega seguridad.
    const [cred] = await this.prisma.sinSesion((tx) =>
      tx.$queryRaw<Credencial[]>`
        SELECT * FROM core.buscar_credencial(${dto.username}, ${act.empresa_id})`,
    );
    if (!cred) throw malCodigo;

    return this.abrirSesion(cred);
  }

  // ===================================================================
  //  ELEGIR SUCURSAL - pararse en una sede
  //
  //  Esto NO es publico: llega con el token que dio el login, el que todavia
  //  no lleva sucursal. El guard ya lo verifico, asi que usuarioId y empresaId
  //  son de fiar. Lo unico que trae el cuerpo es el sucursalId, y por eso es
  //  lo unico que hay que comprobar.
  // ===================================================================
  async elegirSucursal(sesion: Sesion, sucursalId: number) {
    // Dos paredes sobre la misma pregunta. RLS ya recorta acceso_sucursal a la
    // empresa de la sesion; usuario_actual() la recorta a esta persona. Lo que
    // queda por comprobar es que la sede este en SU lista y siga activa.
    const filas = await this.prisma.conSesion(sesion, (tx) =>
      tx.$queryRaw<{ ok: boolean }[]>`
        SELECT true AS ok
          FROM core.acceso_sucursal a
          JOIN core.sucursal s ON s.sucursal_id = a.sucursal_id
                              AND s.empresa_id  = a.empresa_id
         WHERE a.usuario_id  = core.usuario_actual()
           AND a.sucursal_id = ${BigInt(sucursalId)}
           AND a.activo
           AND s.activo`,
    );

    if (filas.length === 0) {
      // Mismo mensaje para "no existe" y "no te toca": que no sirva para
      // averiguar cuantas sucursales tiene el vecino.
      throw new ForbiddenException('No tenes acceso a esa sucursal');
    }

    // Token NUEVO, ahora con la sede adentro y firmada. El viejo sigue siendo
    // valido hasta que venza -- un JWT no se puede revocar (H-103) -- pero el
    // viejo no lleva sucursal, asi que no sirve para operar en ninguna.
    const token = await this.jwt.signAsync({
      sub: sesion.usuarioId.toString(),
      emp: sesion.empresaId.toString(),
      usr: sesion.username,
      rol: sesion.rol,
      suc: String(sucursalId),
    } satisfies CargaToken);

    return { token, sucursalId };
  }

  // ===================================================================
  //  Lo comun a entrar y a activar
  // ===================================================================
  private async abrirSesion(cred: Credencial): Promise<RespuestaSesion> {
    // Sesion sin sede todavia: alcanza para que RLS recorte por empresa, que
    // es lo unico que hace falta para leer los datos de la persona.
    const sesion: Sesion = {
      usuarioId: cred.usuario_id, empresaId: cred.empresa_id,
      username: cred.username,    rol: cred.rol,
    };

    const datos = await this.prisma.conSesion(sesion, async (tx: Tx) => {
      // TODO en una sola ida a la base y en un solo jsonb. Es la consulta de
      // 95_consulta_login.sql PASO 2, con dos cambios: los permisos van por
      // sucursal de verdad (antes faltaba ms.sucursal_id y devolvia la union
      // de toda la empresa), y solo salen las sedes activas.
      //
      // Que venga como jsonb tiene un efecto util de paso: los bigint salen
      // como numeros de JSON, asi que no hay que andar convirtiendo bigint a
      // Number campo por campo ni explota JSON.stringify.
      const filas = await tx.$queryRaw<{ sesion: DatosSesion }[]>`
        SELECT jsonb_build_object(
          'usuario', jsonb_build_object(
              'usuarioId',      u.usuario_id,
              'username',       u.username,
              'estado',         u.estado,
              'ultimoAccesoEn', u.ultimo_acceso_en),

          'persona', jsonb_build_object(
              'empleadoId',  em.empleado_id,
              'nombre',      em.nombres || ' ' || em.apellidos,
              'cargo',       em.cargo,
              'correo',      em.correo,
              'colegiacion', em.numero_colegiacion,
              'activo',      em.activo),

          'empresa', jsonb_build_object(
              'empresaId',   e.empresa_id,
              'nombre',      e.nombre,
              'comercial',   e.nombre_comercial,
              'nivelAcceso', e.nivel_acceso,
              'fechaCierre', e.fecha_cierre),

          'rol', jsonb_build_object(
              'rolId',     r.rol_id,
              'nombre',    r.nombre,
              'esSistema', r.es_sistema),

          'sucursales', (
              SELECT coalesce(jsonb_agg(x ORDER BY x->>'codigo'), '[]'::jsonb)
              FROM (
                SELECT jsonb_build_object(
                         'sucursalId', s.sucursal_id,
                         'codigo',     s.codigo,
                         'nombre',     s.nombre,

                         -- lo que la empresa paga en ESTA sede
                         'modulos', (
                            SELECT coalesce(jsonb_agg(ms.modulo_id ORDER BY ms.modulo_id), '[]'::jsonb)
                            FROM plataforma.modulo_sucursal ms
                            WHERE ms.sucursal_id = s.sucursal_id
                              AND ms.empresa_id  = s.empresa_id
                              AND ms.activo),

                         -- rol x licencia DE ESTA SEDE: lo unico que de verdad
                         -- puede hacer parado aqui. Es lo mismo que contesta
                         -- core.usuario_puede() con esa sede en el contexto.
                         'permisos', (
                            SELECT coalesce(jsonb_agg(DISTINCT rp.permiso_id), '[]'::jsonb)
                            FROM core.rol_permiso rp
                            JOIN plataforma.permiso p
                              ON p.permiso_id = rp.permiso_id
                            JOIN plataforma.modulo_sucursal ms
                              ON ms.modulo_id   = p.modulo_id
                             AND ms.sucursal_id = s.sucursal_id
                             AND ms.empresa_id  = s.empresa_id
                             AND ms.activo
                            WHERE rp.rol_id     = u.rol_id
                              AND rp.empresa_id = u.empresa_id)
                       ) AS x
                FROM core.acceso_sucursal a
                JOIN core.sucursal s
                  ON s.sucursal_id = a.sucursal_id
                 AND s.empresa_id  = a.empresa_id
                WHERE a.usuario_id = u.usuario_id
                  AND a.activo      -- el acceso no fue retirado
                  AND s.activo      -- y la sede sigue abierta
              ) q)
        ) AS sesion
        FROM core.usuario  u
        -- LEFT y no INNER: un usuario sin empleado no deberia existir, pero si
        -- existe tiene que poder entrar y verse el problema en pantalla, no
        -- quedarse afuera con un error que no explica nada.
        LEFT JOIN core.empleado em ON em.empleado_id = u.empleado_id AND em.empresa_id = u.empresa_id
        JOIN core.empresa  e  ON e.empresa_id = u.empresa_id
        JOIN core.rol      r  ON r.rol_id     = u.rol_id  AND r.empresa_id = u.empresa_id
        WHERE u.usuario_id = core.usuario_actual()`;

      // El UPDATE va DESPUES de leer, a proposito: ultimoAccesoEn tiene que
      // ser el acceso ANTERIOR. Si se pisa primero, la pantalla saluda con
      // "tu ultimo ingreso fue hace 0 segundos", que no le sirve a nadie --
      // y lo que de verdad sirve, "alguien entro anoche y no fui yo", se
      // pierde.
      await tx.$executeRaw`
        UPDATE core.usuario SET ultimo_acceso_en = now(), intentos_fallidos = 0
         WHERE usuario_id = ${cred.usuario_id}`;

      return filas[0]?.sesion;
    });

    if (!datos) {
      throw new UnauthorizedException('No se pudo armar la sesion');
    }

    // Sin sede activa no hay donde pararse. Falla ruidoso y con instruccion:
    // esto no es un problema del usuario, es algo que el administrador tiene
    // que arreglar.
    if (datos.sucursales.length === 0) {
      throw new ForbiddenException(
        'No tenes ninguna sucursal activa asignada. Pedile al administrador acceso a una sede.',
      );
    }

    // Con una sola sede no hay nada que preguntar: se elige sola y el token
    // sale ya con la sucursal adentro. Preguntar "en cual de estas 1 queres
    // entrar" es una pantalla que solo estorba.
    const unica = datos.sucursales.length === 1 ? datos.sucursales[0] : null;

    // Aqui el empresa_id que salio de la BASE queda sellado. De ahora en
    // adelante viaja dentro del token, firmado, y nadie lo cambia sin romper
    // la firma. Lo mismo la sucursal cuando ya se sabe.
    const carga: CargaToken = {
      sub: cred.usuario_id.toString(),
      emp: cred.empresa_id.toString(),
      usr: cred.username,
      rol: cred.rol,
      ...(unica ? { suc: String(unica.sucursalId) } : {}),
    };

    return {
      token: await this.jwt.signAsync(carga),
      requiereSucursal: unica === null,
      sucursalId: unica?.sucursalId ?? null,
      ...datos,
    };
  }

  private async contarFallo(cred: Credencial) {
    const sesion: Sesion = {
      usuarioId: cred.usuario_id, empresaId: cred.empresa_id,
      username: cred.username,    rol: cred.rol,
    };
    // Por funcion y no por UPDATE: 'estado' ya no se escribe desde lis_app
    // (05_privilegios.sql), asi que el bloqueo al quinto intento vive en
    // core.login_fallido(), que solo puede ir en esa direccion. El ::text
    // es el mismo truco de siempre con las funciones void.
    await this.prisma.conSesion(sesion, (tx) =>
      tx.$queryRaw`SELECT core.login_fallido(${cred.usuario_id}, ${MAX_INTENTOS})::text AS ok`,
    );
  }
}
