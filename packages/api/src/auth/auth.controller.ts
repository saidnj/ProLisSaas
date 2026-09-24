import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { ActivarDto } from './dto/activar.dto';
import { SucursalDto } from './dto/sucursal.dto';
import { Publico } from './publico.decorador';
import { SinSede } from './sin-sede.decorador';
import { SesionActual } from '../comun/sesion.decorador';
// 'import type' y no 'import' a secas: con isolatedModules y
// emitDecoratorMetadata, TypeScript exige que los tipos que aparecen en una
// firma decorada se importen como tipos. Si no, intenta emitir metadata de
// runtime para una interfaz que en runtime no existe.
import type { Sesion } from '../comun/sesion';

// Toda esta seccion se atiende sin sede: es por donde se consigue una.
@SinSede()
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  /** Una de las DOS rutas abiertas. Sin @Publico() el guard global la cierra. */
  @Publico()
  @Post('login')
  @HttpCode(200)          // un login no "crea" nada; 201 confundiria
  entrar(@Body() dto: LoginDto) {
    return this.auth.entrar(dto);
  }

  /**
   * La otra. Tiene que ser abierta por definicion: quien activa todavia no
   * tiene con que identificarse -- lo que trae es el codigo, y ese es su
   * credencial de un solo uso.
   */
  @Publico()
  @Post('activar')
  @HttpCode(200)
  activar(@Body() dto: ActivarDto) {
    return this.auth.activar(dto);
  }

  /**
   * Pararse en una sede. Esta NO es publica y esa es toda la idea: llega con
   * el token del login -- el que todavia no lleva sucursal -- y devuelve uno
   * nuevo que si la lleva, firmada.
   *
   * Podria haberse resuelto mandando la sucursal en una cabecera en cada
   * peticion y listo. No: lo que el navegador manda, el navegador lo cambia.
   * Como los permisos efectivos dependen de la sede, una sucursal editable en
   * F12 es un permiso editable en F12.
   */
  @Post('sucursal')
  @HttpCode(200)
  elegirSucursal(@SesionActual() sesion: Sesion, @Body() dto: SucursalDto) {
    return this.auth.elegirSucursal(sesion, dto.sucursalId);
  }

  /**
   * Para ver el token desarmado: devuelve exactamente lo que el guard sacó de
   * la firma. Util para entender el mecanismo, y se borra antes de produccion.
   */
  @Get('yo')
  yo(@SesionActual() sesion: Sesion) {
    return {
      usuarioId:  Number(sesion.usuarioId),
      empresaId:  Number(sesion.empresaId),
      sucursalId: sesion.sucursalId ? Number(sesion.sucursalId) : null,
      username:   sesion.username,
      rol:        sesion.rol,
      nota: 'Todo esto salio del token verificado, no del cuerpo de la peticion.',
    };
  }
}
