import {
  CanActivate, ExecutionContext, ForbiddenException, Injectable, UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { CargaToken, Sesion } from '../comun/sesion';
import { ES_PUBLICO } from './publico.decorador';
import { SIN_SEDE } from './sin-sede.decorador';

/**
 * EL PUNTO DONDE EL TOKEN SE CONVIERTE EN SESION.
 *
 * Corre ANTES de cualquier controlador. Su trabajo es uno solo: sacar el
 * token de la cabecera, verificar la FIRMA, y dejar en la peticion quien
 * es el que llama.
 *
 * "Verificar la firma" es lo que hace que esto funcione. El token va en
 * texto a la vista -- cualquiera lo pega en jwt.io y lee el empresa_id --
 * pero no lo puede CAMBIAR: la firma se calcula con un secreto que solo
 * tiene el servidor. Cambiar un solo caracter del contenido invalida la
 * firma y jwtService.verify() lanza excepcion.
 *
 * Por eso el empresa_id de adentro del token es confiable, y el de un
 * ?empresaId= de la URL no lo seria nunca.
 */
@Injectable()
export class JwtGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    // Las rutas marcadas con @Publico() -- el login -- pasan sin token.
    const esPublico = this.reflector.getAllAndOverride<boolean>(ES_PUBLICO, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (esPublico) return true;

    const req = ctx.switchToHttp().getRequest();

    // "Authorization: Bearer eyJhbGciOi..."
    const [tipo, token] = (req.headers.authorization ?? '').split(' ');
    if (tipo !== 'Bearer' || !token) {
      throw new UnauthorizedException('Falta el token');
    }

    let carga: CargaToken;
    try {
      carga = await this.jwt.verifyAsync<CargaToken>(token);
    } catch {
      // Firma invalida, token vencido, o basura. El front lo traduce a
      // "se vencio la sesion" y manda al login.
      throw new UnauthorizedException('Token invalido o vencido');
    }

    // AQUI nace la sesion, y sale ENTERA del token verificado.
    const sesion: Sesion = {
      usuarioId: BigInt(carga.sub),
      empresaId: BigInt(carga.emp),
      username:  carga.usr,
      rol:       carga.rol,
      // Puede no venir: el token que da el login no la trae mientras la
      // persona no elija sede. Quien necesite sucursal tiene que exigirla,
      // no suponerla -- undefined aqui significa "todavia no esta parado en
      // ningun lado", no "en todas".
      sucursalId: carga.suc ? BigInt(carga.suc) : undefined,
    };

    // LA SEDE ES OBLIGATORIA salvo en las rutas marcadas con @SinSede() -- las
    // de auth, que son justamente por donde se consigue. Las politicas RLS de
    // las tablas operativas calculan el permiso en la sede del contexto; sin
    // sede no ven nada. Que un endpoint conteste "vacio" en vez de "elegi una
    // sede" seria mentirle al usuario. Por eso se corta aqui, con mensaje.
    const sinSede = this.reflector.getAllAndOverride<boolean>(SIN_SEDE, [
      ctx.getHandler(),
      ctx.getClass(),
    ]);
    if (!sinSede && sesion.sucursalId === undefined) {
      throw new ForbiddenException(
        'Elegi una sede primero: esta ruta necesita el token que devuelve POST /auth/sucursal',
      );
    }

    req.sesion = sesion;
    return true;
  }
}
