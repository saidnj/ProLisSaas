import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client';
import type { Sesion } from '../comun/sesion';

/** El cliente de adentro de una transaccion. */
export type Tx = Omit<
  PrismaClient,
  '$connect' | '$disconnect' | '$on' | '$transaction' | '$use' | '$extends'
>;

/**
 * La unica puerta a la base.
 *
 * Nada consulta directo: todo pasa por conSesion() o por sinSesion(), y las
 * dos hacen lo mismo primero -- ponerse el rol lis_app, local a la
 * transaccion -- porque la aplicacion se conecta como lis_api, que con
 * NOINHERIT no tiene NINGUN privilegio hasta pedirlo.
 *
 * Eso es a proposito: una consulta que se escape de la transaccion no devuelve
 * cero filas en silencio, revienta con "permission denied for schema core".
 * Ruidoso en vez de mentiroso.
 */
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  constructor() {
    // Prisma 7 con el generador "prisma-client" exige un adaptador de driver:
    // por debajo corre node-postgres (pg). Es mejor para nosotros -- el pool
    // queda bajo nuestro control en vez de escondido en el motor.
    //
    // EL POOL, EXPLICITO. pg trae 10 conexiones por defecto y cada peticion
    // retiene una durante toda su transaccion (milisegundos, pero una). Si
    // llegan mas peticiones a la vez que conexiones, las demas esperan hasta
    // maxWait y salen con P2028, que el filtro convierte en 503 "ocupado".
    // Cuando eso aparezca en los logs es la senal de subir DB_POOL_MAX o de
    // poner PgBouncer delante (el diseno ya es compatible: todo va con
    // SET LOCAL / set_config local). Nunca mas que max_connections de
    // Postgres menos lo que usen las otras apps y el operador.
    super({
      adapter: new PrismaPg({
        connectionString: process.env.DATABASE_URL,
        max: Number(process.env.DB_POOL_MAX ?? 10),
        // Una conexion ociosa se devuelve al servidor a los 30 s: en horas
        // valle el pool se achica solo.
        idleTimeoutMillis: 30_000,
      }),
    });
  }

  async onModuleInit()    { await this.$connect(); }
  async onModuleDestroy() { await this.$disconnect(); }

  /**
   * Una transaccion CON contexto de empresa: RLS activo.
   *
   * Esto es el 99% del sistema. Adentro del callback, las consultas se
   * escriben SIN "where empresaId" -- la politica de Postgres lo agrega.
   *
   * REGLA: adentro del callback, SIEMPRE `tx`, NUNCA `this`. Una consulta
   * hecha con `this` sale por otra conexion del pool, sin rol y sin contexto,
   * y falla con "permission denied".
   */
  async conSesion<T>(sesion: Sesion, trabajo: (tx: Tx) => Promise<T>): Promise<T> {
    return this.$transaction(
      async (tx) => {
        // ROL Y CONTEXTO EN UNA SOLA SENTENCIA. set_config('role', ...) es
        // exactamente SET ROLE (misma comprobacion de membresia, mismo
        // efecto) y con el tercer parametro TRUE es local a la transaccion,
        // igual que SET LOCAL. Ir junto con los lis.* ahorra una ida a la
        // base por peticion; con la base en otro servidor, una ida son
        // milisegundos, y son de todas las peticiones.
        //
        // TRUE = "local a la transaccion". Con FALSE quedaria pegado a la
        // CONEXION, y la siguiente peticion que la reuse -- que puede ser de
        // otra empresa -- lo heredaria. Ese es el unico fallo de RLS que no
        // es "no ves nada" sino "ves lo de otro".
        //
        // Los valores van como PARAMETRO, no interpolados: SET no acepta
        // parametros y obligaria a pegar el valor dentro del SQL -- una
        // inyeccion esperando pasar. set_config si los acepta.
        // La sucursal va con cadena vacia cuando todavia no eligio sede. Es la
        // misma convencion que ya usa core.empresa_actual(): nullif(x,'') la
        // convierte en NULL en vez de reventar al castear a bigint.
        //
        // Esto SI es una pared: core.usuario_puede() -- la unica comprobacion
        // de permiso, la que usan las politicas RLS de las tablas operativas,
        // las funciones y el API -- lee la sede de aqui. Sin sede devuelve
        // false, y las tablas operativas contestan cero filas.
        await tx.$executeRaw`
          SELECT set_config('role',            'lis_app', true),
                 set_config('lis.empresa_id',  ${sesion.empresaId.toString()}, true),
                 set_config('lis.usuario_id',  ${sesion.usuarioId.toString()}, true),
                 set_config('lis.sucursal_id', ${sesion.sucursalId?.toString() ?? ''}, true)`;

        return trabajo(tx as Tx);
      },
      { timeout: 15_000, maxWait: 5_000 },
    );
  }

  /**
   * Una transaccion CON rol pero SIN contexto de empresa.
   *
   * Para los dos momentos en que todavia no hay nadie identificado: entrar y
   * activar. Lo unico que se puede hacer aqui es llamar a las funciones
   * SECURITY DEFINER -- buscar_credencial, buscar_activacion, activar_usuario
   * --, que se saltan RLS a proposito.
   *
   * Cualquier otra consulta aqui adentro devuelve cero filas o revienta.
   */
  async sinSesion<T>(trabajo: (tx: Tx) => Promise<T>): Promise<T> {
    return this.$transaction(
      async (tx) => {
        await tx.$executeRaw`SELECT set_config('role', 'lis_app', true)`;
        return trabajo(tx as Tx);
      },
      { timeout: 10_000, maxWait: 5_000 },
    );
  }
}
