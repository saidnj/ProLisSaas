import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

/** @Global: se importa una vez y lo inyecta cualquier modulo sin re-importarlo. */
@Global()
@Module({ providers: [PrismaService], exports: [PrismaService] })
export class PrismaModule {}
