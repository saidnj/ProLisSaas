import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

@Module({
  imports: [
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        // EL SECRETO. Con esto se firma y se verifica. Quien lo tenga puede
        // fabricar un token con el empresa_id que quiera y leer cualquier
        // laboratorio. Va en el .env, nunca en el codigo, y en produccion
        // tiene que ser largo y aleatorio.
        secret: config.getOrThrow<string>('JWT_SECRETO'),

        // El tipo de expiresIn es StringValue ("8h", "30m"), no string suelto:
        // asi el compilador rechaza "ocho horas" o un typo como "8hh".
        signOptions: {
          expiresIn: (config.get<string>('JWT_VENCE_EN') ?? '8h') as `${number}h`,
        },
      }),
    }),
  ],
  controllers: [AuthController],
  providers: [AuthService],
  exports: [JwtModule],
})
export class AuthModule {}
