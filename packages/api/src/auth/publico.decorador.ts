import { SetMetadata } from '@nestjs/common';

export const ES_PUBLICO = 'esPublico';

/**
 * Marca una ruta como abierta, sin token.
 *
 * El guard esta puesto de forma GLOBAL: todo pide token salvo lo que lleve
 * este decorador. Al reves -- proteger ruta por ruta -- el dia que alguien
 * olvide ponerlo queda un endpoint abierto y nadie se entera. Asi, olvidarse
 * significa quedar cerrado de mas, que se nota en el acto.
 */
export const Publico = () => SetMetadata(ES_PUBLICO, true);
