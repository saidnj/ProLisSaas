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
 * dos hacen lo mismo primero -- SET LOCAL ROLE lis_app -- porque la aplicacion
 * se conecta como lis_api, que con NOINHERIT no tiene NINGUN privilegio hasta
 * pedirlo.
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
    super({
      adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }),
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
        await tx.$executeRawUnsafe('SET LOCAL ROLE lis_app');

        // El tercer parametro TRUE es "local a la transaccion" -- equivale a
        // SET LOCAL. Con FALSE quedaria pegado a la CONEXION, y la siguiente
        // peticion que la reuse -- que puede ser de otra empresa -- lo
        // heredaria. Ese es el unico fallo de RLS que no es "no ves nada"
        // sino "ves lo de otro".
        //
        // Va como PARAMETRO, no interpolado: SET no acepta parametros y
        // obligaria a pegar el valor dentro del SQL -- una inyeccion
        // esperando pasar.
        // La sucursal va con cadena vacia cuando todavia no eligio sede. Es la
        // misma convencion que ya usa core.empresa_actual(): nullif(x,'') la
        // convierte en NULL en vez de reventar al castear a bigint.
        //
        // Esto SI es una pared: core.usuario_puede() -- la unica comprobacion
        // de permiso, la que usan las politicas RLS de las tablas operativas,
        // las funciones y el API -- lee la sede de aqui. Sin sede devuelve
        // false, y las tablas operativas contestan cero filas.
        await tx.$executeRaw`
          SELECT set_config('lis.empresa_id',  ${sesion.empresaId.toString()}, true),
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
        await tx.$executeRawUnsafe('SET LOCAL ROLE lis_app');
        return trabajo(tx as Tx);
      },
      { timeout: 10_000 },
    );
  }
}
