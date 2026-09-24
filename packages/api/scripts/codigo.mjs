// =====================================================================
//  ProLisSaas - generar un codigo de activacion desde la consola
//
//      npm run codigo -- marlon.ochoa
//      npm run codigo -- carla.nunez --admin marlon.ochoa --horas 48
//
//  Deja al usuario EXACTAMENTE como recien creado: estado
//  'pendiente_activacion', sin clave, con un codigo vivo de 24 horas. Es
//  lo mismo que hace POST /usuarios/:id/resetear-clave, pero sin necesitar
//  que el API este levantado ni un token.
//
//  POR QUE NO ES UN .sql
//  ---------------------
//  core.generar_activacion() recibe el HASH argon2 del codigo, no el
//  codigo. psql no sabe calcular argon2, y esta bien que sea asi: si la
//  base pudiera generar el codigo, el codigo en claro quedaria escrito en
//  el registro de consultas. El unico lugar donde existe en claro es esta
//  pantalla, una vez.
//
//  QUE PUEDE Y QUE NO
//  ------------------
//  Se conecta con el MISMO DATABASE_URL que la aplicacion y baja a
//  lis_app: no es superusuario y no se salta RLS. Todas las reglas siguen
//  en pie -- hace falta un admin activo de la misma empresa, y la base lo
//  comprueba adentro de la funcion. Esto no es una puerta trasera: es la
//  misma puerta, sin el HTTP en medio.
// =====================================================================

import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import argon2 from 'argon2';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');

// ---------------------------------------------------------------------
//  El alfabeto de los codigos. Esta DUPLICADO de src/comun/codigo.ts a
//  proposito -- este archivo corre con node pelado, sin compilar -- asi
//  que abajo se comprueba contra el original. Si alguien cambia uno y no
//  el otro, el script se planta en vez de generar codigos que la API
//  despues no va a reconocer.
// ---------------------------------------------------------------------
const ALFABETO = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

function comprobarAlfabeto() {
  try {
    const fuente = readFileSync(join(RAIZ, 'src/comun/codigo.ts'), 'utf8');
    const m = fuente.match(/const ALFABETO = '([^']+)'/);
    if (m && m[1] !== ALFABETO) {
      console.error('\n  El alfabeto de scripts/codigo.mjs no coincide con src/comun/codigo.ts.');
      console.error('  aqui:  ' + ALFABETO);
      console.error('  alla:  ' + m[1]);
      console.error('  Igualalos antes de seguir, o los codigos no se van a poder activar.\n');
      process.exit(1);
    }
  } catch {
    // Si no se puede leer el fuente (corriendo desde otro lado), se sigue.
  }
}

function generarCodigo() {
  const bytes = randomBytes(8);
  let s = '';
  for (let i = 0; i < 8; i++) {
    s += ALFABETO[bytes[i] % ALFABETO.length];
    if (i === 3) s += '-';
  }
  return s;
}

/** Igual que normalizarCodigo() de src/comun/codigo.ts. */
function normalizar(codigo) {
  return codigo.replace(/[\s-]/g, '').toUpperCase();
}

// ---------------------------------------------------------------------
//  .env a mano: un parser de tres lineas evita depender de dotenv.
// ---------------------------------------------------------------------
function leerEnv() {
  const texto = readFileSync(join(RAIZ, '.env'), 'utf8');
  const env = {};
  for (const linea of texto.split(/\r?\n/)) {
    const m = linea.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$/i);
    if (m) env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

// ---------------------------------------------------------------------
//  Argumentos
// ---------------------------------------------------------------------
const args = process.argv.slice(2);

// Se separan las banderas con valor de los sueltos, asi el orden no importa:
// "carla --admin marlon" y "--admin marlon carla" dicen lo mismo.
const banderas = {};
const sueltos = [];
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) banderas[args[i].slice(2)] = args[++i];
  else sueltos.push(args[i]);
}

const objetivo = sueltos[0];
const admin = banderas.admin ?? objetivo;
const horas = banderas.horas ? Number(banderas.horas) : 24;

if (!Number.isInteger(horas) || horas < 1 || horas > 168) {
  console.error('\n  --horas tiene que ser un entero entre 1 y 168 (7 dias).\n');
  process.exit(1);
}

if (!objetivo) {
  console.error('\n  Uso:  npm run codigo -- <username> [--admin <username>] [--horas 24]\n');
  console.error('  Sin --admin, el usuario se genera el codigo a si mismo: sirve para el');
  console.error('  primer administrador, que no tiene a nadie mas que se lo genere.\n');
  process.exit(1);
}

comprobarAlfabeto();

const env = leerEnv();
if (!env.DATABASE_URL) {
  console.error('\n  No encontre DATABASE_URL en packages/api/.env\n');
  process.exit(1);
}

// ---------------------------------------------------------------------
//  Manos a la obra
// ---------------------------------------------------------------------
const codigo = generarCodigo();

// SE HASHEA LA FORMA NORMALIZADA, sin el guion.
//
// El guion es para el ojo: quien escribe el codigo puede ponerlo o no, y por
// eso AuthService.activar() llama a normalizarCodigo() antes de verificar.
// Si el hash se calculara sobre 'K7M2-9QXF' y la verificacion se hiciera
// contra 'K7M29QXF', no cuadrarian nunca y ningun codigo se podria activar.
const codigoHash = await argon2.hash(normalizar(codigo), { type: argon2.argon2id });

const cliente = new pg.Client({ connectionString: env.DATABASE_URL });
await cliente.connect();

try {
  await cliente.query('BEGIN');

  // Igual que PrismaService: la aplicacion se conecta como lis_api, que con
  // NOINHERIT no tiene ningun privilegio hasta pedir el rol.
  await cliente.query('SET LOCAL ROLE lis_app');

  // buscar_credencial es SECURITY DEFINER: es lo unico legible sin contexto.
  const { rows: [obj] } = await cliente.query(
    'SELECT * FROM core.buscar_credencial($1, NULL)', [objetivo]);
  if (!obj) throw new Error(`No existe el usuario "${objetivo}"`);

  let quien = obj;
  if (admin !== objetivo) {
    const { rows: [a] } = await cliente.query(
      'SELECT * FROM core.buscar_credencial($1, NULL)', [admin]);
    if (!a) throw new Error(`No existe el admin "${admin}"`);
    quien = a;
  }

  if (quien.estado_usuario !== 'activo') {
    throw new Error(
      `El admin "${quien.username}" esta en estado "${quien.estado_usuario}" y no puede ` +
      'generar codigos. Hace falta un usuario activo con el permiso usuario.administrar.');
  }
  if (quien.empresa_id !== obj.empresa_id) {
    throw new Error('El admin y el usuario objetivo no son de la misma empresa.');
  }

  console.log(`\n  antes:  ${obj.username}  ->  ${obj.estado_usuario}  (rol ${obj.rol}, empresa ${obj.empresa})`);
  console.log(`  quien lo genera:  ${quien.username}\n`);

  // Contexto de sesion, local a la transaccion. Con FALSE quedaria pegado a
  // la conexion; aqui da igual porque el proceso muere, pero la costumbre se
  // mantiene igual en todos lados.
  await cliente.query(
    "SELECT set_config('lis.empresa_id', $1, true), set_config('lis.usuario_id', $2, true)",
    [String(quien.empresa_id), String(quien.usuario_id)]);

  // Y LA SEDE. core.usuario_puede() -- la unica comprobacion de permiso --
  // exige que el modulo este encendido en la sede del contexto; sin sede
  // contesta false y generar_activacion() diria "no tiene permiso". Se
  // toma una sede donde el admin tenga acceso; si no tiene ninguna (el
  // primer administrador, recien creado), la primera abierta de la empresa.
  // RLS ya recorta core.sucursal a la empresa de la sesion.
  const { rows: [sede] } = await cliente.query(
    `SELECT s.sucursal_id
       FROM core.sucursal s
       LEFT JOIN core.acceso_sucursal a
              ON a.sucursal_id = s.sucursal_id AND a.usuario_id = $1 AND a.activo
      WHERE s.activo
      ORDER BY (a.usuario_id IS NULL), s.sucursal_id
      LIMIT 1`,
    [quien.usuario_id]);
  if (!sede) throw new Error('La empresa no tiene ninguna sede abierta.');
  await cliente.query("SELECT set_config('lis.sucursal_id', $1, true)", [String(sede.sucursal_id)]);

  // La base comprueba adentro: sesion puesta, permiso usuario.administrar,
  // y que el objetivo sea de la misma empresa. Y de paso deja al usuario en
  // pendiente_activacion con la clave en blanco.
  const { rows: [act] } = await cliente.query(
    'SELECT * FROM core.generar_activacion($1, $2, $3)',
    [obj.usuario_id, codigoHash, horas]);

  await cliente.query('COMMIT');

  // La comprobacion va DESPUES del COMMIT y por buscar_credencial, no con un
  // SELECT a core.usuario: cuando el objetivo es el mismo admin (el primer
  // administrador generandose su propio codigo), generar_activacion() lo
  // acaba de dejar en pendiente_activacion, y desde ese momento RLS -- via
  // sesion_vigente() -- ya no lo deja leer nada dentro de esa sesion.
  // buscar_credencial es SECURITY DEFINER y no depende del contexto.
  //
  // El SET LOCAL ROLE de arriba murio con el COMMIT: la conexion volvio a
  // ser lis_api, que no puede ni ver el esquema. Se vuelve a pedir el rol.
  await cliente.query('SET ROLE lis_app');
  const { rows: [despues] } = await cliente.query(
    'SELECT estado_usuario AS estado, password_hash = \'\' AS sin_clave ' +
    'FROM core.buscar_credencial($1, $2)',
    [obj.username, obj.empresa_id]);

  console.log('  ' + '='.repeat(52));
  console.log(`   codigo de activacion:   ${codigo}`);
  console.log(`   vence:                  ${new Date(act.vence_en).toLocaleString('es-HN')}`);
  console.log('  ' + '='.repeat(52));
  console.log(`\n  ahora:  ${obj.username}  ->  ${despues.estado}` +
              `  (clave ${despues.sin_clave ? 'en blanco' : 'PUESTA - algo salio mal'})`);
  console.log('\n  Este codigo no se vuelve a mostrar: de la base solo sale el hash.');
  console.log(`  Activalo en  http://localhost:4200/activar  con el usuario "${obj.username}".\n`);
} catch (e) {
  await cliente.query('ROLLBACK');
  const pista = {
    '42501': 'Le falta el permiso usuario.administrar, o el objetivo es de otra empresa.',
    '28000': 'No hay sesion valida: revisa que el admin exista y este activo.',
    '42P01': 'Falta una tabla. Recarga el esquema (01 a 08) y volve a intentar.',
  }[e.code];
  console.error(`\n  FALLO: ${e.message}`);
  if (pista) console.error(`  ${pista}`);
  console.error('');
  process.exitCode = 1;
} finally {
  await cliente.end();
}
