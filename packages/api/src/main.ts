import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { ErroresBaseFilter } from './comun/errores.filtro';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // El front vive en 4200 y el API en 3000: son ORIGENES distintos, asi que
  // el navegador bloquea la peticion salvo que el servidor diga que si.
  // Sin credentials: el token viaja en la cabecera Authorization, no en una
  // cookie; permitir credenciales de origen cruzado no se usaba y abre mas
  // de lo necesario.
  app.enableCors({ origin: process.env.ORIGEN_FRONT ?? 'http://localhost:4200' });

  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
  );

  // Traduce el 28000 que lanzan las politicas RLS a un 401 con mensaje.
  app.useGlobalFilters(new ErroresBaseFilter());

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
