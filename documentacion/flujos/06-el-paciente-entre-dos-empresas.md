# El paciente entre dos empresas

Qué pasa cuando el hospital y el laboratorio atienden al mismo señor, siendo dos
empresas distintas que no comparten ni una fila.

> **Este es el modelo decidido.** Manda sobre lo que digan los demás documentos
> mientras no se actualicen: la identidad compartida de `core/05-la-identidad.md`
> y la forma actual de `audit.derivacion` quedaron atrás. La sección 9 lista qué
> falta reconciliar, y ese trabajo está anotado en `hallazgos.md`.
>
> Todavía **no hay tablas ni diagramas**, a propósito. La forma exacta se define
> aparte; aquí está el comportamiento que esa forma tiene que sostener.

---

## 1. Quién es quién

| | Qué es | De quién son sus datos |
|---|---|---|
| **El hospital** | Empresa cliente, con su propio sistema | Suyos |
| **El laboratorio** | Empresa cliente, con su propio sistema | Suyos |
| **La sede del laboratorio dentro del hospital** | Sucursal del **laboratorio** | Del laboratorio |
| **La otra sede del laboratorio** | Sucursal del laboratorio, afuera | Del laboratorio |

**El sello decide la pertenencia.** El examen sale firmado por el bioquímico y
sellado por el laboratorio; entonces el resultado es del laboratorio, él responde
por él y él lo conserva. Que la sede esté dentro del hospital no cambia de quién
es el dato — cambia dónde está la puerta.

Y como las dos sedes son de la misma empresa, **entre ellas comparten todo**. El
paciente que se atiende en la sede de adentro y después en la de afuera es el
mismo expediente. Eso no es un problema que haya que resolver: es una sola
empresa.

---

## 2. La pieza que hace que esto funcione: la referencia guardada

Ninguna de las dos empresas escribe en la fila de la otra. Lo que hacen es
**anotar, cada una en su propia ficha del paciente, cómo lo llama la otra.**

```
Ficha del hospital                    Ficha del laboratorio
───────────────────                   ─────────────────────
expediente   H-000123                 expediente   L-000456
nombre       Said Hoch                nombre       Said Hoch
documento    0801-2004-00844          documento    0801-2004-00844
                                      
referencia externa:                   referencia externa:
  Laboratorio Ochoa → L-000456          Hospital San José → H-000123
  confirmado por Rosa, 10/09/2026       confirmado por Rosa, 10/09/2026
```

No es una llave foránea. No hay integridad referencial entre empresas. Es **un
dato externo anotado sobre el propio paciente**, igual que se anota el número de
póliza de un seguro.

> **REGLA** — `F6-1` · La referencia externa la escribe cada empresa en su propia
> ficha y nadie más la toca. Si está mal, la arregla quien la escribió, y esa
> corrección no afecta a la otra empresa ni a ninguna tercera.

> **REGLA** — `F6-2` · Una referencia externa **nace de una confirmación humana
> con el paciente presente**, o de un cotejo de dos factores que el sistema pudo
> resolver sin dudar. Nunca de una elección hecha desde una lista.

### Los tres niveles de identidad

Se usan en orden. Solo el tercero pide trabajo, y ese trabajo ya se hacía.

| | Cuándo | Quién decide | Cuesta |
|---|---|---|---|
| **1 · Referencia guardada** | Ya se confirmó antes | Nadie, es automático | nada |
| **2 · Cotejo de dos factores** | Primera vez, con documento | El que tiene los datos, contra los suyos | nada |
| **3 · Confirmación humana** | Sin documento, o el cotejo dudó | Recepción, con el paciente enfrente | lo que ya costaba |

> **REGLA** — `F6-3` · Si el cotejo no está seguro, **no devuelve nada y lo dice**.
> «No encontré resultados» y «no puedo confirmar que estos resultados sean de este
> paciente» son respuestas distintas y las dos tienen que existir. La primera deja
> tranquilo al médico; la segunda le dice que le pregunte al paciente.

---

## 3. Llegó primero al hospital

El caso más común. El paciente nunca pasó por el laboratorio.

**1 · Admisión en el hospital.** Recepción lo registra con sus datos. Nace su
expediente `H-000123`.

**2 · Consulta.** El médico abre la ficha. El sistema del hospital busca si tiene
referencia al laboratorio: **no la tiene**. Pregunta igual, con documento y año de
nacimiento. El laboratorio coteja contra lo suyo y contesta: *no lo conozco*.

El médico ve «sin historial de laboratorio», que es cierto.

**3 · El médico pide un hemograma.** Sale una solicitud hacia el laboratorio con:

- Los datos del paciente, y **el expediente del hospital** (`H-000123`)
- Las pruebas pedidas
- El convenio con el que se cobra
- El médico solicitante
- **El contexto clínico que cambia la interpretación**: embarazo, tratamiento,
  ayuno, diagnóstico presuntivo
- La urgencia

**4 · La solicitud aparece en la sede de adentro.** No hay que aceptarla. **El
enlace ya es la aceptación** —lo creó el operador cuando las dos empresas
acordaron trabajar juntas— y una boleta que llega es trabajo, no una propuesta.
Queda en la lista de pendientes de esa ventanilla, no de otra: el enlace es entre
**esas dos sedes**, no entre las dos empresas.

**5 · El paciente camina hasta la ventanilla.** Y acá pasa lo único que cuesta
algo, una sola vez en la vida de ese paciente:

La recepcionista lo tiene enfrente, le pide su identidad, y confirma que es él.
Como no existía en el laboratorio, lo registra: nace `L-000456`.

**6 · Nace el par de referencias.** En la misma operación:

- El laboratorio anota en su ficha: *el Hospital San José lo llama `H-000123`*
- La respuesta al hospital lleva `L-000456`, y el hospital lo anota en la suya

Desde este momento, **estos dos nunca más se tienen que buscar.**

**7 · Toma de muestra, proceso, validación.** El bioquímico valida y firma. El
informe sale **con el sello del laboratorio**, porque es el laboratorio el que
responde.

**8 · Vuelve el resultado.** Atado a la orden, no al paciente — el hospital lo
archiva bajo el paciente que la pidió, sin cotejar nada. Vuelven dos cosas:

- **Los valores**, para que el médico los vea dentro de su propia historia clínica
- **El informe firmado y sellado**, que es el documento con valor legal

> **REGLA** — `F6-4` · El resultado vuelve atado a **la orden**, nunca al paciente.
> Quien la pidió sabe de quién era; no hace falta volver a identificar a nadie.

---

## 4. Llegó directo al laboratorio

No hay hospital en esta historia. Es el flujo más corto y no tiene nada especial.

**1 ·** Recepción del laboratorio lo registra: `L-000789`.
**2 ·** Se le indica qué exámenes quiere o trae una orden en papel de un médico
de afuera.
**3 ·** Paga en el mostrador, con el convenio `Particular`.
**4 ·** Muestra, proceso, validación, firma y sello.
**5 ·** Se lleva su informe.

**No se guarda ninguna referencia externa**, porque no hay otra empresa
involucrada. El laboratorio es dueño de todo, de punta a punta.

Y si mañana ese mismo señor vuelve a la sede de afuera, es el mismo `L-000789`:
una sola empresa, un solo expediente.

---

## 5. Llegó primero al laboratorio y después al hospital

**Este es el caso que motivó todo el diseño**, y el único donde la identidad hay
que resolverla de verdad.

Said se hizo un hemograma por su cuenta en marzo. En septiembre llega al hospital
con otra cosa, y el médico necesita ver ese resultado.

**1 · Admisión en el hospital.** Nace `H-000999`. El hospital no sabe nada del
laboratorio.

**2 · El médico pide el historial.** El hospital **no tiene referencia guardada**
—nunca pasaron juntos— así que pregunta:

> *Soy el Hospital San José. Mi paciente `H-000999`: documento 0801-2004-00844,
> nacido en 2004, Said Hoch. ¿Lo conocés?*

**3 · El cotejo lo hace el laboratorio, contra lo suyo.** Documento y año de
nacimiento coinciden con `L-000789`. Dos factores: no hay ambigüedad.

El hospital **nunca vio el registro de pacientes del laboratorio**. No eligió de
una lista. No adivinó. Preguntó y le contestaron.

**4 · El laboratorio devuelve tres cosas:**

- El historial que corresponde compartir (sección 6)
- **Su expediente `L-000789`**, para que el hospital lo anote
- El aviso de si hay algo que no pudo confirmar

**5 · Nace el par de referencias, sin que nadie haga nada extra.** El hospital
anota `L-000789`; el laboratorio anota `H-000999`.

**6 · De aquí en adelante todo es automático.** La próxima consulta del historial
y la próxima orden van por el nivel 1.

> **ABIERTO** — Anotar la referencia significa que el laboratorio ahora sabe que
> ese paciente también se atiende en el hospital. Es información sobre la persona,
> no sobre su salud, y es la misma que obtendría con la primera orden. Queda
> escrito para que sea una decisión y no un descuido. *(H-75)*

### Si el cotejo no alcanza

Sin documento, o con datos que no cuadran, el laboratorio contesta **«no puedo
confirmar»** y no devuelve nada. No se crea referencia.

El médico ve ese aviso y sabe que tiene que preguntarle al paciente. Cuando el
paciente vaya a la ventanilla con una orden, la recepcionista confirma con él
delante y ahí nace el par. Nunca antes.

---

## 6. Qué se comparte, exactamente

No todo lo que el laboratorio tiene sobre un paciente es del hospital.

| | ¿Se comparte? | Por qué |
|---|---|---|
| Lo que **este hospital** ordenó | **Sí** | Ya es suyo: él lo pidió y él lo paga |
| Lo que el paciente se hizo **por su cuenta** | **Sí** | Es el requisito clínico: el médico tiene que poder diagnosticar bien |
| Lo que el laboratorio hizo **para otra clínica** | **No** | El resultado es del laboratorio, pero **el hecho de que exista una orden es de quien la pidió**. Mostrarlo le dice al hospital dónde más se atiende el paciente, y eso no es del laboratorio darlo |

> **REGLA** — `F6-5` · El laboratorio comparte lo que este hospital ordenó y lo que
> el paciente se hizo directamente. Lo que ordenó un tercero, no — salvo que el
> paciente lo pida.

> **REGLA** — `F6-6` · **Toda consulta de historial queda registrada**: quién
> preguntó, por qué paciente y cuándo. No se bloquea al médico, pero queda rastro.
> Es lo que un hospital hace con su propia historia clínica por dentro.

---

## 7. El día normal, que es el que importa

Con las dos referencias ya anotadas, así se ve una atención cualquiera:

```
  El médico abre la ficha del paciente
      └─ el historial del laboratorio ya está ahí          (nivel 1, instantáneo)

  Pide un hemograma
      └─ la orden aparece en la ventanilla                 (sin aceptar nada)

  El paciente camina veinte metros
      └─ le sacan sangre                                   (ya está identificado)

  El bioquímico valida y firma
      └─ el resultado aparece en la pantalla del médico    (atado a la orden)
```

**Nadie aceptó nada. Nadie buscó a nadie. Nadie eligió de una lista.**

La única fricción de todo el modelo ocurrió una vez, en la primera visita de ese
paciente, en un mostrador donde de todos modos había que atenderlo.

---

## 8. Qué puede fallar

**El hospital fusiona dos fichas suyas** que resultaron ser la misma persona, y
cada una tenía una referencia distinta al laboratorio. Eso significa que **el
laboratorio también tiene dos**. Hay que avisarle, o el laboratorio va a seguir
partiendo el historial en dos. No es difícil, pero si no se escribe aparece solo.
*(H-74)*

**Una referencia se confirmó mal.** Alguien confirmó al paciente equivocado en la
ventanilla. El daño existe, pero es local: la empresa que la escribió la borra, y
nadie más se enteró. Compará con una identidad compartida, donde el mismo error
lo heredan las dos y hay que negociarlo.

**El laboratorio corrige un resultado ya enviado.** Tiene que salir un mensaje de
corrección, no una edición silenciosa. Si el hospital ya imprimió el anterior,
alguien tiene que saber que cambió.

**El paciente sin documento.** Cae siempre en el nivel 3. Es el único caso donde
la fricción se repite, y es correcto que se repita: no hay nada que cotejar.

**Se rompe la relación entre las dos empresas.** El laboratorio se muda, o el
contrato se termina. Cada uno ya tiene todo lo suyo; las referencias quedan como
texto muerto y se borran. **No hay nada que repartir** — que es exactamente lo que
un modelo de datos compartidos no puede prometer.

---

## 9. Lo que falta reconciliar

Este documento ya es la referencia. Lo de abajo es lo que quedó desactualizado y
hay que poner al día — está anotado como `H-73` para que no se pierda.

Nada de esto se toca todavía: **la forma exacta se define aparte.**

| Qué | Estado |
|---|---|
| `plataforma.persona` y `plataforma.conflicto_identidad` | **Sobran.** El cotejo pasa a ser local y por consulta |
| `plataforma.vincular_persona()` y las cinco funciones de identidad | Sobran con ellas. Son 511 líneas entre `07_identidad.sql` y sus pruebas |
| `core.paciente.persona_id` | Se reemplaza por la referencia externa, que es texto y no llave |
| `audit.derivacion` | **Se reemplaza por `core.mensaje`**: una fila de cada lado, con su propio `empresa_id` y la RLS de todas. Deja de necesitar `persona_id`, su `datos_compartidos` pasa a ser el contenido, y los estados dejan de negociar. La forma está en `01-la-empresa.md` 2.8 |
| `rls_derivacion` | Desaparece la única política del sistema que compara contra dos empresas |
| `core.empresa_asociada` | **Se retira, y no se reemplaza por nada a nivel de empresa.** Entra `plataforma.enlace`: una fila por ruta **entre dos sedes**, creada por el operador. Unir empresas era demasiado grueso — si el laboratorio tiene dos sedes y solo una está adentro del hospital, un vínculo empresa a empresa le manda trabajo a la otra. Tampoco colapsa dentro de `core.convenio` como se pensaba aquí: el convenio modela quién te manda pacientes y paga, y el hospital no tiene convenio hacia su proveedor. Decidido en `H-78`; el hueco que lo obliga está en `H-76` |
| `core/05-la-identidad.md` | Cambia de tema: de «la identidad compartida» a «cómo cada empresa reconoce a su propio paciente» |
| `E-1` | Pasa a ser verdad **sin excepciones**: toda fila pertenece a exactamente una empresa |

Ese último renglón es el que mide si el modelo es bueno. Hoy `E-1` tiene una
excepción declarada y dos sin declarar. Con esto, ninguna.
