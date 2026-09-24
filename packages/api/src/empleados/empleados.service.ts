import {
  BadRequestException, Injectable, NotFoundException,
} from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../prisma/prisma.service';
import type { Tx } from '../prisma/prisma.service';
import type { Sesion } from '../comun/sesion';
import { generarCodigo } from '../comun/codigo';
import { exigirPermiso } from '../comun/permiso';
import { aplicarCuenta, exigirPoderTocar, exigirPoderTocarFicha, fijarSedes } from './cuenta';
import { CrearEmpleadoDto } from './dto/crear-empleado.dto';
import { ActualizarEmpleadoDto } from './dto/actualizar-empleado.dto';
import { exigirSinDuplicados } from './duplicados';
import type { EmpleadoDeLista, EmpleadoGuardado } from './tipos';

/** El mismo jsonb para listar, obtener, crear y editar: una sola forma. */
const FORMA_EMPLEADO = `
  jsonb_build_object(
    'empleadoId',        e.empleado_id,
    'nombres',           e.nombres,
    'apellidos',         e.apellidos,
    'documento',         e.documento,
    'telefono',          e.telefono,
    'correo',            e.correo,
    'cargo',             e.cargo,
    'numeroColegiacion', e.numero_colegiacion,
    'activo',            e.activo,
    'creadoEn',          e.creado_en,
    'username',          u.username,
    'usuarioId',         u.usuario_id,
    'rolId',             u.rol_id,
    'rol',               r.nombre,
    'rolEsSistema',      r.es_sistema,
    'rolEsAdmin',        CASE WHEN u.rol_id IS NULL THEN NULL ELSE core.rol_es_admin(u.rol_id) END,
    'estado',            u.estado,

    -- Las sedes donde puede pararse. null cuando no tiene cuenta -- que no
    -- es lo mismo que [], "tiene cuenta y no le dieron ninguna sede".
    'sucursales',        CASE WHEN u.usuario_id IS NULL THEN NULL ELSE (
                           SELECT coalesce(jsonb_agg(a.sucursal_id ORDER BY a.sucursal_id),
                                           '[]'::jsonb)
                           FROM core.acceso_sucursal a
                           WHERE a.usuario_id = u.usuario_id
                             AND a.empresa_id = u.empresa_id
                             AND a.activo
                         ) END
  )`;

/** El FROM que acompana a FORMA_EMPLEADO. */
const DESDE_EMPLEADO = `
  FROM core.empleado e
  LEFT JOIN core.usuario u
         ON u.empleado_id = e.empleado_id
        AND u.empresa_id  = e.empresa_id
  LEFT JOIN core.rol r
         ON r.rol_id     = u.rol_id
        AND r.empresa_id = u.empresa_id`;

@Injectable()
export class EmpleadosService {
  constructor(private readonly prisma: PrismaService) {}

  // ===================================================================
  //  LISTAR
  // ===================================================================
  async listar(sesion: Sesion): Promise<EmpleadoDeLista[]> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', 'No tenes permiso para administrar empleados');

      // Mira bien lo que NO lleva: ningun "WHERE empresa_id". No hace falta
      // -- la politica rls_empleado_ver se lo agrega Postgres a esta
      // consulta y a cualquier otra, la escriba quien la escriba.
      //
      // El LEFT JOIN a core.usuario si lleva las DOS columnas (empleado_id
      // Y empresa_id), que es la regla de la casa para toda llave foranea
      // compuesta. Aqui RLS ya recorta las dos tablas a la misma empresa,
      // asi que es redundante -- pero el dia que esta consulta se copie
      // dentro de una funcion SECURITY DEFINER, donde RLS no aplica, esa
      // linea es lo unico que impide cruzar empresas.
      //
      // Y sale como jsonb porque adentro de un jsonb los bigint salen como
      // numeros de JSON: no hay que convertir BigInt a Number campo por
      // campo ni explota JSON.stringify.
      const [fila] = await tx.$queryRawUnsafe<{ lista: EmpleadoDeLista[] }[]>(`
        SELECT coalesce(
                 jsonb_agg(x ORDER BY x->>'apellidos', x->>'nombres'),
                 '[]'::jsonb
               ) AS lista
        FROM (SELECT ${FORMA_EMPLEADO} AS x ${DESDE_EMPLEADO}) q`);

      return fila?.lista ?? [];
    });
  }

  // ===================================================================
  //  UNO SOLO
  // ===================================================================
  async obtener(sesion: Sesion, id: number): Promise<EmpleadoDeLista> {
    return this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', 'No tenes permiso para administrar empleados');

      const [fila] = await tx.$queryRawUnsafe<{ empleado: EmpleadoDeLista | null }[]>(
        `SELECT ${FORMA_EMPLEADO} AS empleado ${DESDE_EMPLEADO} WHERE e.empleado_id = $1`,
        BigInt(id),
      );

      // Si es de otra empresa, RLS no lo oculta a medias: no existe. Por eso
      // "no encontrado" y no "no tenes permiso" -- un 403 aqui le diria a
      // quien pregunta que ese id SI existe en algun lado, que es justo lo
      // que no queremos contarle.
      if (!fila?.empleado) throw new NotFoundException('No existe ese empleado');

      return fila.empleado;
    });
  }

  // ===================================================================
  //  CREAR - la persona, su cuenta, sus sedes y su codigo. UNA transaccion.
  //
  //  Empleado y usuario son uno (1 a 1): todo empleado nace con cuenta.
  //  Cuatro escrituras encadenadas que no sirven de a una:
  //
  //    INSERT core.empleado          -> sale el empleado_id
  //    core.crear_usuario(...)       -> usa ese id, sale el usuario_id
  //    fijarSedes(...)               -> usa ese id, deja las sedes
  //    core.generar_activacion(...)  -> usa ese id, sale el codigo
  //
  //  Si una falla, lo anterior no sirve: un usuario sin sedes no puede
  //  entrar a ningun lado, y uno sin codigo no puede estrenar clave. Por
  //  eso van en UNA transaccion: o pasan todas o no pasa ninguna.
  //
  //  Funciona encadenado porque dentro de una transaccion cada consulta ve
  //  lo que escribieron las anteriores: crear_usuario() encuentra el
  //  empleado que acabamos de insertar aunque todavia no haya COMMIT.
  //
  //  Si nace INACTIVO (alguien que empieza el mes que viene) no hay codigo:
  //  la base le crea la cuenta suspendida (core.crear_usuario mira
  //  empleado.activo) y no se le puede generar codigo hasta activarlo.
  //  Cuando lo activen desde Editar, el trigger la pasa a
  //  pendiente_activacion y el codigo se genera desde la ficha.
  // ===================================================================
  async crear(sesion: Sesion, dto: CrearEmpleadoDto): Promise<EmpleadoGuardado> {
    const activo = dto.activo ?? true;

    // EL HASH VA AFUERA DE LA TRANSACCION. argon2 tarda ~100 ms a proposito
    // y no toca la base: adentro seria tener una conexion del pool
    // secuestrada y una transaccion abierta sin hacer nada.
    const codigo = activo ? generarCodigo() : null;
    const codigoHash = codigo
      ? await argon2.hash(codigo.paraHash, { type: argon2.argon2id })
      : null;

    const r = await this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', 'No tenes permiso para administrar empleados');

      // 0 - Que no sea otra vez alguien que ya esta (duplicados.ts). Se
      //     pregunta antes de escribir para poder decir quien lo tiene; los
      //     indices unicos de la base son la garantia si dos guardan a la vez.
      await exigirSinDuplicados(tx, { ...dto, username: dto.cuenta.username }, null);

      // 1 - El empleado.
      //
      // empresa_id sale de core.empresa_actual(), NUNCA del cuerpo de la
      // peticion. Y no hay comprobacion de permiso escrita aqui porque
      // rls_empleado_crear ya exige empresa, sesion vigente y puede_crear():
      // si la empresa quedo en solo_lectura, este INSERT revienta solo.
      const [emp] = await tx.$queryRaw<{ empleado_id: bigint }[]>`
        INSERT INTO core.empleado
          (empresa_id, nombres, apellidos, documento, telefono, correo,
           cargo, numero_colegiacion, activo)
        VALUES
          ((SELECT core.empresa_actual()),
           ${dto.nombres.trim()},
           ${dto.apellidos.trim()},
           ${dto.documento?.trim() || null},
           ${dto.telefono?.trim() || null},
           ${dto.correo?.trim() || null},
           ${dto.cargo?.trim() || null},
           ${dto.numeroColegiacion?.trim() || null},
           ${activo})
        RETURNING empleado_id`;

      // 2 - La cuenta. Nace sin clave (password_hash '', que no es el hash
      //     de nada) y en pendiente_activacion -- o suspendida, si el
      //     empleado nace inactivo. Lo que la base rechaza (username
      //     repetido, rol del propietario, rol de administrador sin ser el
      //     propietario) llega como 409 o 403 y tumba la transaccion entera.
      const [u] = await tx.$queryRaw<{ crear_usuario: bigint }[]>`
        SELECT core.crear_usuario(
          ${emp.empleado_id},
          ${BigInt(dto.cuenta.rolId)},
          ${dto.cuenta.username.trim().toLowerCase()})`;
      const usuarioId = u.crear_usuario;

      // 3 - Las sedes donde va a poder pararse: el mismo codigo que al
      //     editar (empleados/cuenta.ts). Comprueba que alguna exista y este
      //     abierta, y que el rol le sirva en alguna de ellas.
      await fijarSedes(tx, Number(usuarioId), BigInt(dto.cuenta.rolId), dto.cuenta.sucursales);

      // 4 - El codigo de un solo uso, solo si nace activo. La base guarda
      //     el HASH; el codigo en claro solo existe en esta respuesta, una
      //     vez.
      let venceEn: Date | null = null;
      if (codigoHash) {
        const [act] = await tx.$queryRaw<{ vence_en: Date }[]>`
          SELECT * FROM core.generar_activacion(
            ${usuarioId}, ${codigoHash}, ${dto.cuenta.horas ?? 24})`;
        venceEn = act.vence_en;
      }

      // 5 - Se relee con la MISMA forma que usa la lista, para que el front
      //     reciba un objeto identico venga de donde venga.
      const [fila] = await tx.$queryRawUnsafe<{ empleado: EmpleadoDeLista }[]>(
        `SELECT ${FORMA_EMPLEADO} AS empleado ${DESDE_EMPLEADO} WHERE e.empleado_id = $1`,
        emp.empleado_id,
      );

      return { empleado: fila.empleado, venceEn };
    });

    return {
      ...r.empleado,

      // EL CODIGO EN CLARO, Y ES LA UNICA VEZ QUE EXISTE.
      //
      // En la base solo queda su hash argon2: no hay pantalla de "ver el
      // codigo otra vez" ni la va a haber. Si se pierde, se genera otro
      // desde la ficha (POST /empleados/:id/codigo). null si nacio inactivo.
      activacion: codigo
        ? {
            codigo: codigo.legible,
            venceEn: r.venceEn,
            aviso: 'Este codigo no se vuelve a mostrar. Entregaselo a la persona.',
          }
        : null,
    };
  }

  // ===================================================================
  //  EDITAR - la misma transaccion que crear, sobre lo que ya existe
  //
  //  La ficha y la cuenta (username, sedes, rol) llegan juntas y se
  //  aplican juntas: si algo de la cuenta se rechaza (username repetido,
  //  rol que no puede dar), la ficha tampoco cambia. Lo que vino igual que
  //  como estaba no se escribe (empleados/cuenta.ts).
  //
  //  Si el empleado todavia NO tiene cuenta -- los de antes de que fuera
  //  obligatoria -- este guardar se la crea, exactamente como al crear:
  //  crear_usuario, sedes y, si queda activo, el codigo. La cuenta viene
  //  con lo que la pantalla tiene: si no vino (esta bloqueada para quien
  //  edita), no se toca.
  // ===================================================================
  async actualizar(sesion: Sesion, id: number, dto: ActualizarEmpleadoDto): Promise<EmpleadoGuardado> {
    const activo = dto.activo ?? true;

    // Si le va a CREAR la cuenta y queda activo, hace falta un codigo, y su
    // hash se calcula AFUERA de la transaccion (argon2 tarda ~100 ms a
    // proposito; adentro seria una conexion del pool secuestrada sin hacer
    // nada). Por eso se pregunta antes si ya tiene cuenta. Adentro se
    // vuelve a preguntar: si entre una cosa y otra alguien se la creo, se
    // aplica como cambio y el codigo se descarta.
    const vaACrear = !!dto.cuenta && activo && !(await this.tieneCuenta(sesion, id));
    const codigo = vaACrear ? generarCodigo() : null;
    const codigoHash = codigo
      ? await argon2.hash(codigo.paraHash, { type: argon2.argon2id })
      : null;

    const r = await this.prisma.conSesion(sesion, async (tx) => {
      await exigirPermiso(tx, 'usuario.administrar', 'No tenes permiso para administrar empleados');

      // La ficha sigue a la cuenta: la del propietario la edita solo el
      // propietario, la de un administrador solo el propietario. Se pregunta
      // antes para contestar 403 con el motivo (y 404 si no existe); la pared
      // es rls_empleado_editar.
      await exigirPoderTocarFicha(tx, id);

      // Que lo que se guarda no sea ya de OTRO empleado (duplicados.ts);
      // lo suyo propio no choca consigo mismo.
      await exigirSinDuplicados(tx, { ...dto, username: dto.cuenta?.username }, id);

      // Sin WHERE empresa_id: rls_empleado_editar pone el USING (que filas
      // puede tocar) y el WITH CHECK (como puede quedar la fila: de la
      // empresa, con la sesion viva, y core.puede_tocar_ficha). Si la
      // empresa esta en solo_lectura, puede_modificar() lo rechaza solo.
      // Si 'activo' cambia, el trigger tg_empleado_activo suspende o
      // reactiva la cuenta aqui mismo.
      const filas = await tx.$queryRaw<{ empleado_id: bigint }[]>`
        UPDATE core.empleado SET
          nombres            = ${dto.nombres.trim()},
          apellidos          = ${dto.apellidos.trim()},
          documento          = ${dto.documento?.trim() || null},
          telefono           = ${dto.telefono?.trim() || null},
          correo             = ${dto.correo?.trim() || null},
          cargo              = ${dto.cargo?.trim() || null},
          numero_colegiacion = ${dto.numeroColegiacion?.trim() || null},
          activo             = ${activo}
        WHERE empleado_id = ${BigInt(id)}
        RETURNING empleado_id`;

      // Cero filas puede ser "no existe" o "es de otra empresa": para quien
      // pregunta son lo mismo, y tiene que seguir siendolo.
      if (filas.length === 0) throw new NotFoundException('No existe ese empleado');

      let venceEn: Date | null = null;

      if (dto.cuenta) {
        const [u] = await tx.$queryRaw<{ usuario_id: bigint }[]>`
          SELECT usuario_id FROM core.usuario WHERE empleado_id = ${BigInt(id)}`;

        if (u) {
          await aplicarCuenta(tx, Number(u.usuario_id), dto.cuenta);
        } else {
          // Sin cuenta: se le crea con lo que vino. Para nacer hacen falta
          // las tres cosas; al editar el DTO las deja opcionales porque
          // sobre una cuenta que ya existe lo que no viene no se toca.
          const c = dto.cuenta;
          if (!c.username || c.rolId === undefined || !c.sucursales) {
            throw new BadRequestException('Para crear la cuenta hacen falta usuario, rol y sedes');
          }
          const [nuevo] = await tx.$queryRaw<{ crear_usuario: bigint }[]>`
            SELECT core.crear_usuario(${BigInt(id)}, ${BigInt(c.rolId)},
                                      ${c.username.trim().toLowerCase()})`;
          await fijarSedes(tx, Number(nuevo.crear_usuario), BigInt(c.rolId), c.sucursales);

          // El codigo solo si queda activo: inactivo, la cuenta nace
          // suspendida (crear_usuario mira empleado.activo, que ya se
          // escribio arriba) y no se le puede dar codigo.
          if (codigoHash) {
            const [act] = await tx.$queryRaw<{ vence_en: Date }[]>`
              SELECT * FROM core.generar_activacion(${nuevo.crear_usuario}, ${codigoHash}, 24)`;
            venceEn = act.vence_en;
          }
        }
      }

      const [fila] = await tx.$queryRawUnsafe<{ empleado: EmpleadoDeLista }[]>(
        `SELECT ${FORMA_EMPLEADO} AS empleado ${DESDE_EMPLEADO} WHERE e.empleado_id = $1`,
        BigInt(id),
      );

      return { empleado: fila.empleado, venceEn };
    });

    return {
      ...r.empleado,
      // Solo cuando este guardar le creo la cuenta y quedo activo. En claro
      // y una unica vez, igual que al crear.
      activacion: codigo && r.venceEn
        ? {
            codigo: codigo.legible,
            venceEn: r.venceEn,
            aviso: 'Este codigo no se vuelve a mostrar. Entregaselo a la persona.',
          }
        : null,
    };
  }

  /** Si ya tiene cuenta. Una lectura corta, fuera de la transaccion del guardar. */
  private tieneCuenta(sesion: Sesion, id: number): Promise<boolean> {
    return this.prisma.conSesion(sesion, async (tx) => {
      const [f] = await tx.$queryRaw<{ n: bigint }[]>`
        SELECT count(*) AS n FROM core.usuario WHERE empleado_id = ${BigInt(id)}`;
      return Number(f.n) > 0;
    });
  }

  // ===================================================================
  //  LA CUENTA, LO QUE NO ES "EDITAR UN CAMPO"
  //
  //  Un codigo nuevo y desbloquear van por el empleado (empleado y usuario
  //  son uno): la pantalla no conoce otro id. La regla vive en la base
  //  (generar_activacion, desbloquear_usuario); aqui, el 404 si no se ve,
  //  el 400 si el estado no lo permite y el 403 con motivo antes de llamar.
  // ===================================================================

  /**
   * UN CODIGO NUEVO. Sirve para dos situaciones que la pantalla distingue
   * pero la base no:
   *
   *   pendiente_activacion  no le llego, se le vencio, lo perdio. El
   *                         anterior se anula solo. No cambia nada mas.
   *   activo / bloqueado    "olvide mi clave": la clave se BORRA, la cuenta
   *                         queda en pendiente_activacion y la persona
   *                         queda fuera EN EL ACTO -- su sesion abierta
   *                         muere en la siguiente peticion, porque
   *                         sesion_vigente() no deja pasar a nadie que no
   *                         este activo. Estrena clave con el codigo.
   *
   * Lo que NO se toca: una cuenta suspendida (la base tambien lo rechaza).
   * Suspender es una decision de un administrador, o el empleado esta
   * inactivo; no se deshace generando un codigo.
   *
   * Quien se bloqueo y SI recuerda su clave no pasa por aqui: se
   * desbloquea (abajo) y entra con la de siempre.
   */
  async codigoNuevo(sesion: Sesion, empleadoId: number) {
    const codigo = generarCodigo();
    // SOBRE codigo.paraHash, no sobre codigo.legible: activar() normaliza
    // antes de verificar, asi que el hash tiene que ir sobre la forma
    // canonica. Hasheando la legible ningun codigo cuadraria nunca.
    const codigoHash = await argon2.hash(codigo.paraHash, { type: argon2.argon2id });

    const r = await this.prisma.conSesion(sesion, async (tx) => {
      const cuenta = await this.cuentaDe(tx, empleadoId);
      if (cuenta.estado === 'suspendido') {
        throw new BadRequestException('La cuenta esta suspendida: primero hay que reactivarla');
      }

      await exigirPoderTocar(tx, cuenta.usuarioId);

      const [act] = await tx.$queryRaw<{ activacion_id: bigint; vence_en: Date }[]>`
        SELECT * FROM core.generar_activacion(${BigInt(cuenta.usuarioId)}, ${codigoHash}, 24)`;
      return { act, estado: cuenta.estado };
    });

    return {
      empleadoId,
      codigo: codigo.legible,
      venceEn: r.act.vence_en,
      aviso:
        r.estado === 'pendiente_activacion'
          ? 'El codigo anterior ya no sirve. Este tampoco se vuelve a mostrar.'
          : 'La persona quedo fuera hasta que active con este codigo. No se vuelve a mostrar.',
    };
  }

  /**
   * De bloqueado a activo, con el contador en cero y SIN codigo nuevo: la
   * clave sigue siendo la suya. Si se equivoco cinco veces no tiene por que
   * inventarse otra clave; eso termina en un papel pegado al monitor.
   */
  async desbloquear(sesion: Sesion, empleadoId: number) {
    return this.prisma.conSesion(sesion, async (tx) => {
      const cuenta = await this.cuentaDe(tx, empleadoId);
      if (cuenta.estado !== 'bloqueado') {
        throw new BadRequestException('La cuenta no esta bloqueada');
      }

      await exigirPoderTocar(tx, cuenta.usuarioId);

      await tx.$queryRaw`SELECT core.desbloquear_usuario(${BigInt(cuenta.usuarioId)}, NULL)::text AS ok`;

      return { empleadoId, estado: 'activo' as const };
    });
  }

  /** La cuenta de un empleado, o 404 si no se ve (RLS) o no tiene. */
  private async cuentaDe(tx: Tx, empleadoId: number): Promise<{ usuarioId: number; estado: string }> {
    const f = await tx.$queryRaw<{ usuario_id: bigint; estado: string }[]>`
      SELECT usuario_id, estado::text AS estado
        FROM core.usuario WHERE empleado_id = ${BigInt(empleadoId)}`;
    if (f.length === 0) throw new NotFoundException('Ese empleado no existe o no tiene cuenta');
    return { usuarioId: Number(f[0].usuario_id), estado: f[0].estado };
  }

  // ===================================================================
  //  Lo comun
  //
  //  EL PERMISO, DOS VECES Y A PROPOSITO.
  //
  //  Aqui se pregunta para poder contestar un 403 con un mensaje que se
  //  entienda. Despues, core.exigir_permiso() lo vuelve a exigir dentro de
  //  la misma transaccion: esa es la ultima linea de defensa, la que atrapa
  //  el endpoint que alguien escriba manana sin acordarse de esta
  //  comprobacion. Su propio comentario en 04_funciones.sql lo dice.
  //
  //  usuario_puede() es LA comprobacion, y mira la sede del token: el rol
  //  tiene el permiso Y el modulo esta encendido donde esta parado quien
  //  pregunta. Es la misma que aplica el front con los permisos por sede
  //  de la sesion, asi que los dos lados dicen lo mismo siempre.
  // ===================================================================
}
