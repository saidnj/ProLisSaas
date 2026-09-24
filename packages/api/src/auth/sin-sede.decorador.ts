import { SetMetadata } from '@nestjs/common';

export const SIN_SEDE = 'sinSede';

/**
 * Marca una ruta que puede atenderse SIN sede elegida.
 *
 * Son muy pocas: las de auth. Todo lo demas exige que el token traiga la
 * sucursal, y el guard lo comprueba antes de llegar al controlador. Por que
 * tan estricto: las politicas RLS de las tablas operativas calculan el
 * permiso EN LA SEDE del contexto (core.usuario_puede) y sin sede
 * devuelven cero filas. Un endpoint que llegara ahi sin sede no fallaria --
 * contestaria una lista vacia, que es peor, porque parece que no hay datos.
 * Mejor un 403 que lo diga.
 *
 * Igual que @Publico(): la regla es global y esto es la excepcion, asi que
 * olvidarse de ponerlo cierra de mas y se nota en el acto.
 */
export const SinSede = () => SetMetadata(SIN_SEDE, true);
