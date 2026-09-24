import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { PacientesModule } from './pacientes/pacientes.module';
import { EmpleadosModule } from './empleados/empleados.module';
import { CatalogoModule } from './catalogo/catalogo.module';
import { RolesModule } from './roles/roles.module';
import { JwtGuard } from './auth/jwt.guard';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    PacientesModule,
    EmpleadosModule,
    CatalogoModule,
    RolesModule,
  ],
  providers: [
    // EL GUARD ES GLOBAL, y esa es la decision de seguridad del archivo.
    //
    // Todo pide token salvo lo marcado con @Publico(). Al reves -- poner
    // @UseGuards() ruta por ruta -- el dia que alguien olvide ponerlo queda un
    // endpoint abierto y nadie se entera hasta que sea tarde. Asi, olvidarse
    // significa quedar cerrado de mas: se nota en el acto.
    { provide: APP_GUARD, useClass: JwtGuard },
  ],
})
export class AppModule {}
