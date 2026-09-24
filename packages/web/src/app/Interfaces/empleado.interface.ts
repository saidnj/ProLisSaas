/**
 * La persona que trabaja en el laboratorio y su cuenta para entrar al
 * sistema, que son una sola cosa (empleado y usuario, 1 a 1). Espejo de
 * empleados/tipos.ts del API: mismos nombres, mismos campos.
 *
 * Los catalogos (roles, sedes) estan en catalogo.interface.ts.
 */
export interface Empleado {
  empleadoId: number;
  nombres: string;
  apellidos: string;
  /** Numero de identidad. Opcional: no todos lo traen el primer dia. */
  documento: string | null;
  telefono: string | null;
  correo: string | null;
  cargo: string | null;
  /** Del bioquimico o del medico. Va impreso en el informe junto a la firma. */
  numeroColegiacion: string | null;
  activo: boolean;
  creadoEn: string;
  /** Si ya tiene cuenta para entrar al sistema. Lo pone el back. */
  username: string | null;
  /** El id de esa cuenta. Hace falta para las acciones del detalle (codigo nuevo, desbloquear). */
  usuarioId: number | null;
  /** El rol de esa cuenta (id y nombre). null si no tiene cuenta. */
  rolId: number | null;
  rol: string | null;
  /**
   * Si ese rol es el del propietario o uno de administrador. Con esto el
   * detalle sabe si quien esta sentado puede tocar la cuenta (resetear,
   * desbloquear): la de un administrador solo la toca el propietario.
   */
  rolEsSistema: boolean | null;
  rolEsAdmin: boolean | null;
  /** El estado de la cuenta. null si no tiene. */
  estado: EstadoCuenta | null;
  /**
   * Las sedes donde puede pararse.
   *
   * null = no tiene cuenta. [] = tiene cuenta y no le dieron ninguna sede,
   * que no es lo mismo: con [] la persona puede activar su clave y aun asi
   * no entrar a ningun lado.
   */
  sucursales: number[] | null;
}

/**
 * Los estados de una cuenta (core.estado_usuario) y como se sale de cada uno:
 *
 *   pendiente_activacion  nunca estreno su clave -> se le genera un codigo
 *   activo                entra con su clave
 *   bloqueado             cinco intentos fallidos -> se desbloquea, sin
 *                         tocarle la clave
 *   suspendido            la cerro un administrador (todavia sin pantalla)
 */
export type EstadoCuenta = 'pendiente_activacion' | 'activo' | 'suspendido' | 'bloqueado';

/**
 * La CUENTA dentro de guardar (PATCH /empleados/:id, campo 'cuenta'). Va tal
 * como esta en pantalla; el back no toca lo que vino igual. Los motivos solo
 * tienen sentido si hubo cambio, por eso son opcionales.
 */
export interface CambiosCuenta {
  username?: string;
  rolId?: number;
  motivoRol?: string;
  sucursales?: number[];
  motivoSedes?: string;
}

/** Lo que se manda al crear o editar. Sin id, sin fechas, sin empresa. */
export interface EmpleadoEntrada {
  nombres: string;
  apellidos: string;
  documento: string | null;
  telefono: string | null;
  correo: string | null;
  cargo: string | null;
  numeroColegiacion: string | null;
  activo: boolean;
}

/** La cuenta con la que nace un empleado. No es opcional: empleado y usuario son uno. */
export interface CuentaNueva {
  username: string;
  rolId: number;
  /** Al menos una: sin sedes, la cuenta nace sin poder entrar. */
  sucursales: number[];
}

/**
 * Lo que devuelven POST /empleados y PATCH /empleados/:id.
 *
 * El codigo viene EN CLARO y es la unica vez que existe: en la base solo
 * queda su hash argon2. No hay pantalla de "verlo otra vez" ni la va a
 * haber. Si se pierde, se genera otro desde la ficha. Viene null cuando no
 * hubo cuenta nueva (editar sin crearla) o cuando nacio inactivo.
 */
export interface RespuestaGuardarEmpleado extends Empleado {
  activacion: {
    codigo: string;
    venceEn: string;
    aviso: string;
  } | null;
}
