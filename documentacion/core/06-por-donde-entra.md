# Por dónde entra

Convenio y enlace. Con qué acuerdo de precio entró el paciente y por qué puente llegó.

> **ABIERTO** — El **médico solicitante** era parte de este territorio y hoy no
> existe en la base: `core.medico` se retiró porque pedía nombres y apellidos
> por separado cuando la boleta trae una sola palabra, y sin colegiación no
> tenía ninguna unicidad ni forma de fusionar duplicados. Al escribir este
> documento hay que decidir si vuelve como ficha o como un campo de texto en
> `core.episodio`. *(H-98)*

## 1. Qué es y por qué existe

> **PENDIENTE** — Definición en una frase, en palabras del laboratorio. Qué problema resuelve y qué pasaría si esta pieza no existiera.

## 2. Las tablas y sus campos

> **PENDIENTE** — Cada tabla del territorio, columna por columna: tipo, si admite nulos, valor por defecto, para qué sirve y qué resuelve. Las llaves foráneas salientes y quién apunta a estas tablas. Comprobado contra la base, no de memoria.

## 3. Quién la crea y con qué datos

> **PENDIENTE** — Quién la da de alta, en qué momento del flujo, qué campos son obligatorios y cuáles genera el sistema solo. Qué hace falta para que sea usable.

## 4. Ciclo de vida y estados

> **PENDIENTE** — Los estados por los que pasa, las transiciones permitidas, quién dispara cada cambio y qué queda registrado. Cómo se retira sin borrarla.

## 5. Flujos propios

> **PENDIENTE** — Los flujos que son solo de esta pieza, con código (`F-X-1`, `F-X-2`…). Los que tocan varios territorios se listan aquí pero se escriben en `flujos/`.

## 6. Reglas propias

> **PENDIENTE** — Los invariantes de esta pieza, numerados para poder citarlos desde otros documentos. Qué es siempre verdad.

## 7. Cómo vive con las demás

> **PENDIENTE** — Una subsección por cada pieza con la que se relaciona: qué le da, qué le exige, y qué pasa si la otra cambia o se retira.

## 8. Quién puede hacer qué

> **PENDIENTE** — Los permisos involucrados y qué rol los tiene. Qué acciones se otorgan a mano y por qué.

## 9. Qué puede salir mal

> **PENDIENTE** — Casos límite, errores conocidos y decisiones que envejecen mal. Es la sección donde se cazan los problemas.

## 10. Preguntas abiertas

> **PENDIENTE** — Lo que todavía no está decidido, con lo que hace falta para decidirlo.

## 11. Dónde vive en el código

> **PENDIENTE** — Lo que ya existe y lo que este documento pide crear.
