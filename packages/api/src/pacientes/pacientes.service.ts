import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import type { Sesion } from '../comun/sesion';

@Injectable()
export class PacientesService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Mira bien lo que NO hay aqui: ningun "where: { empresa_id: ... }".
   *
   * La sesion no se usa para filtrar -- se usa para PONER EL CONTEXTO, y
   * el filtro lo agrega Postgres con la politica rls_paciente. Si manana
   * alguien escribe una consulta nueva y se olvida del filtro, sigue sin
   * poder ver los pacientes de otra empresa.
   */
  listar(sesion: Sesion) {
    return this.prisma.conSesion(sesion, async (tx) => {
      const filas = await tx.paciente.findMany({
        select: { paciente_id: true, expediente: true, nombres: true,
                  apellidos: true, telefono: true },
        orderBy: { apellidos: 'asc' },
        take: 50,
      });
      // BigInt no se puede convertir a JSON: hay que bajarlo a number.
      return filas.map((p) => ({ ...p, paciente_id: Number(p.paciente_id) }));
    });
  }
}
