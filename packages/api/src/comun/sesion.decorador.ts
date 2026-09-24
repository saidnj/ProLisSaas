import { ExecutionContext, createParamDecorator } from '@nestjs/common';
import type { Sesion } from './sesion';

/**
 * Saca la sesion que el guard dejo en la peticion.
 *
 *     listar(@SesionActual() sesion: Sesion) { ... }
 *
 * Es azucar: lo unico que hace es leer request.sesion. Pero al estar en la
 * firma del metodo, TypeScript te obliga a acordarte de que existe.
 */
export const SesionActual = createParamDecorator(
  (_dato: unknown, ctx: ExecutionContext): Sesion =>
    ctx.switchToHttp().getRequest().sesion,
);
