---
description: Revisa el diseño en busca de errores — los documentos entre sí y los documentos contra el esquema
argument-hint: [territorio | diseno | esquema | vacío para todo]
---

Revisa el diseño de ProLisSaas. Alcance pedido: **$ARGUMENTS**

Cómo interpretar ese alcance:

- Vacío → los dos revisores, sobre todo lo escrito.
- `diseno` o `esquema` → solo ese revisor, sobre todo.
- Un nombre de territorio (`empresa`, `sucursal`, `paciente`, `identidad`…) o un
  archivo → los dos revisores, limitados a ese documento y a lo que se relacione
  directamente con él.

## Cómo hacerlo

Lanza **los dos agentes en paralelo, en un solo mensaje**, salvo que el alcance
pida uno solo:

- `revisor-diseno` — contradicciones entre documentos.
- `revisor-esquema` — deriva entre documentos y esquema.

Pásale a cada uno el alcance en su prompt, y dile que devuelva su informe con el
formato que tiene definido.

## Qué haces con lo que devuelvan

No pegues los dos informes uno detrás del otro. Únelos:

1. **Quita lo repetido.** Los dos pueden ver la misma cosa desde su lado. Deja
   una sola entrada y di que la vieron los dos: eso la hace más creíble, no
   menos.
2. **Contrasta antes de creer.** Los agentes se equivocan. Antes de darle una
   entrada al usuario, abre el archivo citado y comprueba que la cita es real y
   dice lo que dicen que dice. Una entrada que no puedas confirmar se va a la
   sección de dudas, con la nota de que no la verificaste.
3. **Ordena por lo que rompe**, no por quién lo encontró: primero lo que hace
   fallar el sistema, después lo que confunde a quien programe, al final lo
   cosmético.
4. **Descarta lo que ya está en `hallazgos.md`**, salvo que la fila existente
   esté incompleta o mal clasificada — entonces dilo así.

## Cómo lo presentas

Una tabla corta, en el chat:

| # | Tipo | Dónde | Qué | Se arregla en |
|---|---|---|---|---|

Debajo, solo para las entradas que rompen algo, el detalle con la cita literal.
Las cosméticas se quedan en la tabla.

Termina con las filas listas para pegar en `hallazgos.md`, numeradas siguiendo
el último `H-n` que haya en el archivo, **y pregunta antes de escribirlas**. Los
revisores son de solo lectura a propósito; quien decide qué entra en la lista de
hallazgos es el usuario.

Si los dos informes vienen limpios, dilo en dos líneas y no rellenes.
