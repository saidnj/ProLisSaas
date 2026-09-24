# Los estilos del sistema: como se arma una pantalla

Todo lo compartido es **global** y entra por `src/styles.scss`, una sola vez.
Cada pieza vive en su parcial aqui (`_botones.scss`, `_tabla.scss`...). Una
pantalla nueva no importa nada: usa las clases y ya sale igual que las demas.
Cambiar el azul del sistema es cambiar `--acento` en `_variables.scss`.

El `.scss` de cada componente lleva **solo lo suyo**: lo que ninguna otra
pantalla va a usar (las casillas de sedes del formulario de empleados, la caja
del codigo, la lista de sedes de "elegir sucursal"). Y **no** hace `@use` de
estos parciales: un `@use` desde un componente mete una copia entera del parcial
en ese componente (asi estaba antes: cinco copias de lo mismo).

Regla para decidir donde va una regla nueva: si la va a usar mas de una
pantalla, a un parcial de aqui; si no, al componente.

## Las piezas

| parcial            | clases                                                                 |
|--------------------|------------------------------------------------------------------------|
| `_variables.scss`  | `:root` con `--tinta --suave --tenue --borde --fondo --panel --acento --acento-2 --peligro --bien --bien-2` |
| `_base.scss`       | reset, `body` (fondo, tinta, letra)                                    |
| `_botones.scss`    | `.boton` + `.primario` / `.suave` / `.fantasma` / `.chico`             |
| `_pantalla.scss`   | `.pagina` `.migas` `.cabecera` (`h1`, `.sub`, `.acciones`) `.panel` (`.barra-panel`, `.cuerpo`) `.buscador` `.cuenta` |
| `_tabla.scss`      | `.tabla-envoltura` `table.tabla` (`.principal` `.secundario` `.apagado` `.acciones-fila`) |
| `_formulario.scss` | `.campos` `label.campo` (`.pista`, `.malo`, `.mal-campo`) `.ancho-total` `label.interruptor` `.pie-formulario` |
| `_detalle.scss`    | `dl.datos` `.dato` (`dt`, `dd`, `dd.vacio`)                            |
| `_chips.scss`      | `.chip` + `.si` / `.no` / `.info` / `.gris` (dos seguidos no se pegan); `.estado` `.error-caja` `.aviso-demo` `.cargando` |
| `_tarjeta.scss`    | `.pantalla` `.tarjeta` (+ `.ancha`) y lo de adentro: `header`, `label`, `input`, `.con-boton`, `.pista`, `.error`, `button.principal`, `.pie` |
| `_ng-select.scss`  | el desplegable con buscador, con la cara del sistema                   |

Los nombres dicen **para que** es la cosa, no de que color: `.boton.primario`
y no `.btnazul`. Si el azul cambia, `.primario` sigue diciendo la verdad.

## Esqueleto 1: una LISTA

```html
<app-encabezado />
<div class="pagina">
  <div class="cabecera">
    <div>
      <h1>Empleados</h1>
      <p class="sub">Quien trabaja aqui y con que entra al sistema.</p>
    </div>
    <div class="acciones">
      <a class="boton primario" routerLink="/empleados/nuevo">Nuevo empleado</a>
    </div>
  </div>

  @if (error()) { <p class="error-caja" role="alert">{{ error() }}</p> }

  <div class="panel">
    <div class="barra-panel">
      <input class="buscador" type="search" placeholder="Buscar..." />
      <span class="cuenta">{{ filtrados().length }} de {{ todos().length }}</span>
    </div>

    @if (cargando()) {
      <p class="cargando">Cargando...</p>
    } @else if (filtrados().length === 0) {
      <div class="estado"><strong>Nada por aqui</strong><p>Proba con otra busqueda.</p></div>
    } @else {
      <div class="tabla-envoltura">
        <table class="tabla">
          <thead><tr><th>Nombre</th><th>Estado</th><th></th></tr></thead>
          <tbody>
            @for (e of filtrados(); track e.empleadoId) {
              <tr>
                <td><span class="principal">{{ e.nombres }}</span> <span class="secundario">{{ e.cargo }}</span></td>
                <td><span class="chip" [class.si]="e.activo" [class.gris]="!e.activo">{{ e.activo ? 'Activo' : 'Inactivo' }}</span></td>
                <td><div class="acciones-fila">
                  <a class="boton fantasma chico" [routerLink]="['/empleados', e.empleadoId]">Ver</a>
                  <a class="boton suave chico" [routerLink]="['/empleados', e.empleadoId, 'editar']">Editar</a>
                </div></td>
              </tr>
            }
          </tbody>
        </table>
      </div>
    }
  </div>
</div>
```

## Esqueleto 2: un FORMULARIO (crear / editar)

```html
<app-encabezado />
<div class="pagina">
  <div class="migas"><a routerLink="/empleados">Empleados</a> <span>/</span> <span>Nuevo</span></div>
  <div class="cabecera">
    <div><h1>Nuevo empleado</h1><p class="sub">Que va a pasar al guardar.</p></div>
  </div>

  @if (error()) { <p class="error-caja" role="alert">{{ error() }}</p> }

  <form class="panel" [formGroup]="formulario" (ngSubmit)="guardar()" novalidate>
    <div class="cuerpo">
      <div class="campos">
        <label class="campo">
          <span>Nombres *</span>
          <input type="text" formControlName="nombres" [class.malo]="malo('nombres')" autocomplete="off" />
          @if (malo('nombres')) { <span class="mal-campo">Hace falta el nombre</span> }
        </label>

        <label class="campo">
          <span>Numero de identidad</span>
          <span class="pista">Opcional. No todos lo traen el primer dia.</span>
          <input type="text" formControlName="documento" autocomplete="off" />
        </label>

        <label class="campo ancho-total">
          <span>Rol *</span>
          <ng-select formControlName="rolId" [items]="roles()" bindLabel="nombre" bindValue="rolId"></ng-select>
        </label>

        <div class="ancho-total">
          <label class="interruptor">
            <input type="checkbox" formControlName="activo" />
            <span>Activo <span class="pista">-- apagado, no aparece en las listas.</span></span>
          </label>
        </div>
      </div>

      <div class="pie-formulario">
        <a class="boton fantasma" routerLink="/empleados">Cancelar</a>
        <button type="submit" class="boton primario" [disabled]="guardando()">Guardar</button>
      </div>
    </div>
  </form>
</div>
```

La pista de un `label.campo` va **debajo** del input aunque en el HTML este
arriba (lo acomoda `order`): asi los campos de una misma fila quedan alineados
tengan pista o no.

## Esqueleto 3: una FICHA (detalle)

```html
<app-encabezado />
<div class="pagina">
  <div class="migas"><a routerLink="/empleados">Empleados</a> <span>/</span> <span>{{ e.nombres }}</span></div>
  <div class="cabecera">
    <div><h1>{{ e.nombres }} {{ e.apellidos }}</h1><p class="sub">{{ e.cargo }}</p></div>
    <div class="acciones">
      <a class="boton suave" [routerLink]="['/empleados', e.empleadoId, 'editar']">Editar</a>
    </div>
  </div>

  <div class="panel">
    <div class="cuerpo">
      <dl class="datos">
        <div class="dato"><dt>Telefono</dt><dd>{{ e.telefono }}</dd></div>
        <div class="dato"><dt>Correo</dt>@if (e.correo) { <dd>{{ e.correo }}</dd> } @else { <dd class="vacio">--</dd> }</div>
        <div class="dato ancho"><dt>Estado de la cuenta</dt><dd><span class="chip si">Activa</span></dd></div>
      </dl>
    </div>
  </div>
</div>
```

## Esqueleto 4: una pantalla de ENTRADA (sin encabezado)

```html
<div class="pantalla">
  <form class="tarjeta" [formGroup]="formulario" (ngSubmit)="entrar()" novalidate>
    <header><h1>ProLisSaas</h1><p>Sistema de informacion de laboratorio</p></header>
    <label><span>Usuario</span><input type="text" formControlName="username" /></label>
    <label><span>Clave</span><input type="password" formControlName="password" /></label>
    @if (error()) { <p class="error" role="alert">{{ error() }}</p> }
    <button type="submit" class="principal" [disabled]="entrando()">Entrar</button>
    <p class="pie">Primera vez? <a routerLink="/activar">Activa tu cuenta con el codigo</a></p>
  </form>
</div>
```

## Lo que NO es global

- El encabezado tiene su propia paleta (tinta clara sobre barra oscura) en su
  `:host`: redefine `--tinta`, `--acento`, `--peligro` solo para lo que esta
  adentro de la barra. Es una excepcion local, no otra paleta.
- Etiquetas a secas (`input`, `label`, `header`, `button`) solo se estilan
  **anidadas** bajo una clase (`.tarjeta input`, `label.campo input`). Sueltas
  en lo global le pegarian a todos los input del sistema, incluidos los de
  ng-select y los de cualquier libreria.
