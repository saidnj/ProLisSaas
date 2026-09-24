# Propuesta · Módulos, permisos y roles

**Para revisar antes de aplicar. No se tocó ningún archivo del esquema.**

Todo lo que sigue se probó contra una copia de la base. Al final está lo que
se ejecutó y lo que contestó.

---

## 1. Lo que quedó decidido

- La licencia de un módulo es **por sede**, no por empresa.
- `plataforma.modulo` y `plataforma.permiso` son catálogos del **operador**.
  El administrador del laboratorio no puede crear ni modificar ninguno.
- La asignación de módulos a una sede la hace **el operador**, así que la tabla
  se va a `plataforma`.
- Al administrador solo le salen los permisos de los módulos que su empresa
  tiene, **y eso se comprueba en la base**, no solo en la pantalla.
- Apagar un módulo tiene que quitar el acceso **sin borrar** lo que el
  administrador configuró.

## 2. El modelo

```
        EL OPERADOR                              EL LABORATORIO

  plataforma.modulo ◄──────────────── plataforma.modulo_sucursal
   core                                (sucursal_id, modulo_id, activo)
   lab_clinico                          qué contrató cada sede
   rayos_x                              ── la escribe el operador
        ▲                               ── el laboratorio solo la LEE
        │ modulo_id
        │
  plataforma.permiso ◄──────────────── core.rol_permiso
   orden.crear · lab_clinico             qué le dio el admin a cada rol
   radiografia.crear · rayos_x           ── la escribe una función
```

Las dos tablas de la derecha apuntan al catálogo de la izquierda. **No hay
llave foránea entre ellas: se cruzan en la consulta.**

Y de ahí sale la regla:

> **Lo que un usuario puede hacer es la intersección de dos cosas:
> lo que el administrador le dio (`rol_permiso`) y lo que el operador le
> vendió a esa sede (`modulo_sucursal`).**

`rol_permiso` guarda la **intención** y sobrevive a todo. `modulo_sucursal`
guarda la **licencia** y se enciende y se apaga. Por eso cuando el cliente deja
de pagar un módulo el acceso desaparece, y cuando vuelve a pagar el acceso
vuelve solo, sin que el administrador rearme nada.

---

## 3. Los cambios

### 3.1 · `core.modulo_sucursal` → `plataforma.modulo_sucursal`

Sigue el patrón que ya usa `plataforma.enlace`: vive en el esquema del
operador, el laboratorio la lee recortada por RLS, y **no la puede escribir**.

```sql
ALTER TABLE core.modulo_sucursal SET SCHEMA plataforma;

ALTER TABLE plataforma.modulo_sucursal
  ADD COLUMN desactivado_en timestamptz,
  ADD COLUMN asignado_por   text NOT NULL;

-- Apagar un modulo tiene que dejar constancia de cuando (cierra H-26)
ALTER TABLE plataforma.modulo_sucursal
  ADD CONSTRAINT ck_modulo_sucursal_apagado
  CHECK (activo OR desactivado_en IS NOT NULL);

REVOKE ALL    ON plataforma.modulo_sucursal FROM lis_app;
GRANT  SELECT ON plataforma.modulo_sucursal TO   lis_app;

ALTER TABLE plataforma.modulo_sucursal ENABLE ROW LEVEL SECURITY;
ALTER TABLE plataforma.modulo_sucursal FORCE  ROW LEVEL SECURITY;
CREATE POLICY rls_modulo_sucursal ON plataforma.modulo_sucursal
  FOR SELECT USING (empresa_id = core.empresa_actual());
```

`asignado_por` es texto y no llave foránea por la misma razón que
`enlace.creado_por`: **el operador no es usuario de ninguna empresa** (`E-19`).

La política es `FOR SELECT` y sin `WITH CHECK` porque desde el laboratorio no
hay escritura posible. La tabla sigue siendo muchos a muchos: la llave primaria
`(sucursal_id, modulo_id)` es lo que lo permite.

### 3.2 · La comprobación, con la licencia adentro

Dos funciones, con nombres distintos a propósito para que nadie use la
equivocada sin darse cuenta:

| Función | Qué comprueba | Para qué |
|---|---|---|
| `core.usuario_puede(permiso, usuario)` | el rol lo tiene **y** el módulo está encendido **en alguna sede** | pintar menús, y lo que no ocurre en una sede concreta |
| `core.usuario_puede_en(permiso, sucursal, usuario)` | el rol lo tiene **y** el módulo está encendido **en esa sede** | las operaciones |

```sql
CREATE OR REPLACE FUNCTION core.usuario_puede_en(
  p_permiso_id text, p_sucursal_id bigint, p_usuario_id bigint DEFAULT NULL
) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM core.usuario u
    JOIN core.rol_permiso rp ON rp.rol_id = u.rol_id AND rp.empresa_id = u.empresa_id
    JOIN plataforma.permiso p ON p.permiso_id = rp.permiso_id
    JOIN plataforma.modulo_sucursal ms
      ON ms.modulo_id   = p.modulo_id
     AND ms.empresa_id  = u.empresa_id
     AND ms.sucursal_id = p_sucursal_id
     AND ms.activo
    WHERE u.usuario_id = coalesce(p_usuario_id, core.usuario_actual())
      AND u.estado = 'activo'
      AND rp.permiso_id = p_permiso_id
  )
$$;
```

`core.usuario_puede()` queda igual pero con un `EXISTS` contra
`modulo_sucursal` sin fijar la sede.

**Las dos siguen siendo `invoker`, no `SECURITY DEFINER`**, a propósito: así RLS
las sigue recortando a la empresa de la sesión y nadie puede preguntar por un
usuario de otra empresa.

### 3.3 · El menú del administrador

```sql
CREATE OR REPLACE FUNCTION core.permisos_disponibles(p_sucursal_id bigint DEFAULT NULL)
RETURNS TABLE (permiso_id text, modulo_id text, descripcion text)
LANGUAGE sql STABLE AS $$
  SELECT DISTINCT p.permiso_id, p.modulo_id, p.descripcion
  FROM plataforma.permiso p
  JOIN plataforma.modulo_sucursal ms ON ms.modulo_id = p.modulo_id AND ms.activo
  WHERE p_sucursal_id IS NULL OR ms.sucursal_id = p_sucursal_id
  ORDER BY 2, 1
$$;
```

Sin sede devuelve la unión de lo que la empresa tenga en alguna sucursal,
porque **el rol es de la empresa y el módulo es de la sede**.

### 3.4 · La única puerta para cambiar los permisos de un rol

Esto es lo que convierte tu idea en una protección de verdad. La pantalla filtra
por comodidad; **la función es la que no se puede saltar.**

```sql
CREATE OR REPLACE FUNCTION core.asignar_permisos_a_rol(
  p_rol_id bigint, p_permisos text[], p_usuario_id bigint DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
...
  -- a · quien llama administra usuarios
  IF NOT core.usuario_puede('usuario.administrar', v_usuario_id) THEN
    RAISE EXCEPTION 'Solo quien administra usuarios puede cambiar los permisos de un rol';
  END IF;

  -- b · el rol es de su empresa
  -- c · cada permiso pertenece a un modulo que la empresa tiene encendido
  --     (si no, nombra los culpables en el error)

  -- ... reemplaza el conjunto y registra el cambio en audit.evento
$$;

REVOKE INSERT, UPDATE ON core.rol_permiso FROM lis_app;
```

Tres detalles que importan:

- **Usa `core.usuario_puede()` y no `core.exigir_permiso()`.** Dentro de un
  `SECURITY DEFINER` de postgres, `current_user` deja de ser `lis_app` y
  `exigir_permiso` se va por su escape sin comprobar nada (`H-57`).
- **El error nombra los permisos rechazados**, no dice «no se pudo».
- **Registra el cambio en `audit.evento`** con `datos_antes` y `datos_despues`.
  Cambiar lo que puede un rol es la modificación más delicada del sistema y
  hasta hoy no dejaba ningún rastro.

### 3.5 · El módulo `core` se enciende como cualquier otro

Dos líneas dentro de `core.crear_empresa()`:

```sql
INSERT INTO plataforma.modulo_sucursal (sucursal_id, modulo_id, empresa_id, asignado_por)
VALUES (v_sucursal_id, 'core',        v_empresa_id, 'alta'),
       (v_sucursal_id, 'lab_clinico', v_empresa_id, 'alta');
```

Sin esto, el día que la intersección se encienda **los 16 permisos de `core` se
caen y el sistema se cierra solo**. Cierra `H-27`.

Ojo: esa función sigue siendo provisional a propósito (`H-91`). Esto es un
parche para que el esquema quede consistente, no la definición del flujo de alta.

### 3.6 · La red de RLS tiene que cubrir `plataforma`

La consulta de verificación de `05_rls_y_funciones.sql` mira `core`, `lab` e
`integra`. Con la tabla en `plataforma`, hay que agregar ese esquema o la red
deja de atraparla.

---

## 4. Lo que se probó

Sobre una base construida desde cero con los 17 archivos, más esta propuesta.

| # | Escenario | Esperado | Resultado |
|---|---|---|---|
| 1 | Una recepcionista escribe `rol_permiso` directo | rechazo | `permission denied for table rol_permiso` |
| 2 | Una recepcionista llama la función | rechazo | `Solo quien administra usuarios puede...` |
| 3 | El admin mete un permiso de un módulo no contratado | rechazo nombrándolo | `...no tiene contratados: radiografia.crear` |
| 4 | El admin mete permisos legítimos | 3, y queda en la bitácora | `3` · evento `rol.permisos_cambiar` con antes y después |
| 5 | La recepcionista usa lo que su rol dice | `t` / `t` | `t` / `t` |
| 6 | **El operador apaga `lab_clinico`** | `f` / `f`, sin borrar nada | `f` / `f` · la fila de `rol_permiso` intacta |
| 7 | **Vuelve a pagar** | `t` / `t` sin rearmar el rol | `t` / `t` |
| 8 | El laboratorio se enciende un módulo | rechazo | `permission denied for table modulo_sucursal` |
| 9 | El laboratorio lee los suyos para el menú | `core` 16, `lab_clinico` 14 | igual |
| 10 | Los permisos de `core` ya no se caen | contratado | contratado |

Los **6 y 7** son el par que importa: apagar el módulo quita el acceso, y
encenderlo lo devuelve, **sin que el administrador toque nada**.

Y los cinco archivos de prueba del proyecto siguen dando exactamente lo de
siempre con la propuesta aplicada:

```
95_pruebas_comercial.sql       errores=9
96_pruebas_permisos.sql        errores=2
97_pruebas_identidad.sql       errores=7
98_pruebas_lab.sql             errores=1
99_pruebas_aislamiento.sql     errores=5
```

---

## 5. Lo que te queda por decidir

### a · `asignar_permisos_a_rol` reemplaza el conjunto entero

Le mandás la lista completa de permisos que el rol debe tener y lo que no venga
se quita. La alternativa es que solo agregue, con otra función para quitar.

**Reemplazar es lo que le sirve a una pantalla de casillas** —el admin marca y
desmarca, y guarda— pero significa que un `array` incompleto borra permisos.
En la prueba 4 el rol Recepción pasó de 11 permisos a 3 de una sola llamada.

### b · La convención de nombres de los permisos

`permiso_id` es único en todo el sistema, así que `orden.crear` no puede existir
en `lab_clinico` y en `rayos_x` a la vez:

```
INSERT INTO plataforma.permiso VALUES ('orden.crear','rayos_x',...);
ERROR: duplicate key value violates unique constraint "permiso_pkey"
```

El formato obligado es `recurso.accion`, así que `orden.crear` para laboratorio
y `radiografia.crear` para rayos X funciona. **Conviene fijarlo ahora**, con 30
permisos y dos módulos; con cien y cinco módulos toca renombrar los viejos.

### c · De dónde sale la sucursal en cada petición

`usuario_puede_en()` la recibe como parámetro, y hoy hay operaciones que ya la
tienen a mano (`episodio.sucursal_id`, la orden, la muestra). La alternativa es
una variable de sesión `lis.sucursal_id` que se fija al entrar a trabajar en una
sede, junto a `lis.empresa_id` y `lis.usuario_id`.

Me inclino por la variable de sesión: un usuario con acceso a dos sedes tiene
que decir en cuál está trabajando, y eso va a hacer falta igual para los
correlativos y para el informe.

---

## 6. Lo que NO cambia

- `plataforma.modulo` y `plataforma.permiso`: quedan igual, y `lis_app` sigue
  teniendo solo `SELECT` sobre las dos.
- `core.rol` y `core.rol_permiso`: mismas columnas. Lo único que cambia es
  quién puede escribir en `rol_permiso`.
- La tabla de módulos por sede ya era muchos a muchos y lo sigue siendo.
- El modelo de RBAC: usuario → un rol → muchos permisos. Intacto.

## 7. Orden de aplicación

1. Mover la tabla y sus privilegios (3.1) — **antes** que nada, porque
   `crear_empresa()` la referencia.
2. `crear_empresa()` apuntando a la tabla nueva y encendiendo `core` (3.5).
3. Las funciones (3.2, 3.3, 3.4) y el `REVOKE` sobre `rol_permiso`.
4. La red de RLS (3.6).
5. Reconstruir, correr las cinco pruebas, regenerar el espejo de SQL Server.

Los hallazgos que se cierran: **H-26** (falta `desactivado_en`), **H-27** (el
módulo `core` sin activar), **H-29** (`activo` no lo lee nadie). **H-68** deja
de tener tensión: esas fechas ahora son del operador y están en su esquema.
**H-91** sigue abierto — el flujo de alta no se define aquí.
