# Cómo quedarían las cinco tablas

Leído de una base con la propuesta aplicada, no escrito de memoria.
**Cambios marcados con ▲.**

---

## `plataforma.modulo` · del operador — **sin cambios**

Los módulos que ofrece el sistema.

| Columna | Tipo | Nulo | Para qué |
|---|---|---|---|
| `modulo_id` | `text` | no | La llave. `^[a-z][a-z0-9_]*$` |
| `nombre` | `text` | no | Cómo se llama en la factura y en el menú |
| `descripcion` | `text` | sí | Qué incluye |

```
modulo_pkey            PRIMARY KEY (modulo_id)
ck_modulo_id_formato   CHECK (modulo_id ~ '^[a-z][a-z0-9_]*$')
```

Le apuntan tres tablas: `plataforma.permiso`, `plataforma.modulo_sucursal` y
`core.informe`. Sin RLS: es el catálogo del producto, igual para todos.

**`lis_app` → `SELECT`.** El administrador del laboratorio no puede crear módulos.

---

## `plataforma.permiso` · del operador — **sin cambios**

Todos los permisos del sistema. Hoy 30: 16 de `core`, 14 de `lab_clinico`.

| Columna | Tipo | Nulo | Para qué |
|---|---|---|---|
| `permiso_id` | `text` | no | La llave. `recurso.accion` — es lo que valida la ruta |
| `modulo_id` | `text` | no | **A qué módulo pertenece.** Es la bisagra con la licencia |
| `descripcion` | `text` | no | Qué autoriza |

```
permiso_pkey            PRIMARY KEY (permiso_id)
ck_permiso_id_formato   CHECK (permiso_id ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$')
permiso_modulo_id_fkey  FOREIGN KEY (modulo_id) → plataforma.modulo
```

**`lis_app` → `SELECT`.** Los permisos están predefinidos; el administrador
solo los reparte, nunca los crea.

> `permiso_id` es único en **todo el sistema**, así que `orden.crear` no puede
> existir en `lab_clinico` y en `rayos_x` a la vez. La convención de nombres hay
> que fijarla ahora.

---

## `plataforma.modulo_sucursal` · del operador — ▲ **se muda y gana dos columnas**

Qué contrató cada **sede**. Era `core.modulo_sucursal`.

| Columna | Tipo | Nulo | Para qué |
|---|---|---|---|
| `sucursal_id` | `bigint` | no | Media llave primaria |
| `modulo_id` | `text` | no | La otra media. **Las dos juntas son el muchos a muchos** |
| `empresa_id` | `bigint` | no | Para RLS y para la llave compuesta hacia `core.sucursal` |
| `activo` | `boolean` | no · `true` | Si está encendido hoy |
| `activado_en` | `timestamptz` | no · `now()` | Desde cuándo |
| ▲ `desactivado_en` | `timestamptz` | sí | **Cuándo se apagó.** Cierra `H-26` |
| ▲ `asignado_por` | `text` | no | Quién del lado del operador lo asignó |

```
modulo_sucursal_pkey          PRIMARY KEY (sucursal_id, modulo_id)
▲ ck_modulo_sucursal_apagado  CHECK (activo OR desactivado_en IS NOT NULL)
fk_modulo_sucursal_sucursal   FOREIGN KEY (sucursal_id, empresa_id) → core.sucursal
modulo_sucursal_empresa_fkey  FOREIGN KEY (empresa_id) → core.empresa
modulo_sucursal_modulo_fkey   FOREIGN KEY (modulo_id)  → plataforma.modulo

▲ POLICY rls_modulo_sucursal FOR SELECT
     USING (empresa_id = core.empresa_actual())
```

**▲ `lis_app` → `SELECT` y nada más.** Antes tenía `INSERT` y `UPDATE`, y con
eso el laboratorio podía encenderse módulos que nadie le vendió.

Tres cosas a notar:

- La política es **`FOR SELECT` y sin `WITH CHECK`**: no hay escritura posible
  desde el laboratorio, así que no hay nada que comprobar al escribir.
- `asignado_por` es **texto y no llave foránea**, por la misma razón que
  `enlace.creado_por`: el operador no es usuario de ninguna empresa (`E-19`).
- La llave primaria compuesta es lo que hace el muchos a muchos: una sede con
  cuatro módulos son cuatro filas, y un módulo en dos sedes son dos filas.

---

## `core.rol` · del laboratorio — **sin cambios**

| Columna | Tipo | Nulo | Para qué |
|---|---|---|---|
| `rol_id` | `bigint` identidad | no | La llave |
| `empresa_id` | `bigint` | no | De quién es |
| `nombre` | `text` | no | Único por empresa |
| `descripcion` | `text` | sí | Para qué sirve el rol |
| `es_sistema` | `boolean` | no · `false` | Los cuatro que nacen con la empresa |

**`lis_app` → `INSERT`, `SELECT`, `UPDATE`.** El administrador sí crea roles.

---

## `core.rol_permiso` · del laboratorio — ▲ **mismas columnas, otra puerta**

| Columna | Tipo | Nulo | Para qué |
|---|---|---|---|
| `rol_id` | `bigint` | no | Qué rol |
| `permiso_id` | `text` | no | Qué permiso |
| `empresa_id` | `bigint` | no | Para RLS y la llave compuesta |

```
rol_permiso_pkey             PRIMARY KEY (rol_id, permiso_id)
fk_rol_permiso_rol           FOREIGN KEY (rol_id, empresa_id) → core.rol
rol_permiso_empresa_fkey     FOREIGN KEY (empresa_id)         → core.empresa
rol_permiso_permiso_fkey     FOREIGN KEY (permiso_id)         → plataforma.permiso
```

**▲ `lis_app` → `SELECT` y nada más.** Antes tenía `INSERT` y `UPDATE`, y con
eso cualquier usuario podía darse `usuario.administrar` a sí mismo.

Ahora se escribe **únicamente** por `core.asignar_permisos_a_rol()`, que antes
de tocar nada comprueba que quien llama administra usuarios, que el rol es de
su empresa, y que cada permiso pertenece a un módulo encendido — y deja el
cambio en `audit.evento` con el antes y el después.

---

## Los privilegios, de un vistazo

| Tabla | `lis_app` puede | Quién escribe de verdad |
|---|---|---|
| `plataforma.modulo` | `SELECT` | El operador |
| `plataforma.permiso` | `SELECT` | El operador |
| ▲ `plataforma.modulo_sucursal` | `SELECT` | El operador |
| `core.rol` | `INSERT`, `SELECT`, `UPDATE` | El administrador |
| ▲ `core.rol_permiso` | `SELECT` | `core.asignar_permisos_a_rol()` |

Las dos flechas son el cambio entero: **dos tablas pasan de escribibles a solo
lectura**, y cada una tapa uno de los dos agujeros.

---

## El resumen en una línea

```
plataforma.modulo ◄── plataforma.permiso        (catálogo del operador)
        ▲
        └──────────── plataforma.modulo_sucursal (qué compró cada sede)

plataforma.permiso ◄── core.rol_permiso          (qué dio el admin a cada rol)
```

Nada conecta `permiso` con `modulo_sucursal` por llave foránea, **y no debe**:
se cruzan en la consulta, por `modulo_id`. Si hubiera llave, el catálogo de 30
permisos tendría que multiplicarse por cada sede de cada cliente.
