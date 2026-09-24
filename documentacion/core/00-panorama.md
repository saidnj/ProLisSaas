# Panorama de core

Los nueve territorios del núcleo, en el orden en que se recorren cuando un paciente
entra por la puerta.

## Los territorios y qué contiene cada uno

| Territorio | Tablas | Pregunta que contesta |
|---|---|---|
| La empresa | `empresa` | ¿De quién es esto y hasta dónde llega su mundo? |
| La sucursal | `sucursal`, `modulo_sucursal`, `correlativo` | ¿Dónde se atiende y con qué módulos encendidos? |
| La gente que trabaja | `empleado`, `usuario`, `rol`, `rol_permiso`, `acceso_sucursal` | ¿Quién puede entrar y qué puede hacer? |
| El paciente | `paciente` | ¿A quién se atiende? |
| La identidad compartida | `plataforma.persona`, `plataforma.conflicto_identidad` | ¿Es el mismo señor que atiende la clínica de al lado? |
| Por dónde entra | `convenio`, `medico`, `empresa_asociada`, `audit.derivacion` | ¿Quién lo mandó y con qué acuerdo? |
| La visita | `episodio` | ¿Qué pasó ese día? |
| El documento | `informe`, `informe_version`, `entrega` | ¿Qué se entregó, a quién y cuándo? |
| El rastro | `audit.evento` | ¿Quién hizo qué? |

## Cómo se encadenan

```
empresa ──> sucursal ──> correlativo
   │            └──> modulo_sucursal
   ├──> empleado ──> usuario ──> rol ──> rol_permiso
   │                    └──> acceso_sucursal
   ├──> paciente ─ ─ ─> persona          (vínculo de identidad, no de datos)
   ├──> medico
   ├──> convenio ─ ─ ─> empresa (otra)   (el puente hacia el futuro)
   └──> empresa_asociada ──> derivacion
                                │
        paciente + sucursal + convenio + medico + derivacion
                                │
                                v
                            EPISODIO
                                │
                                ├──> informe ──> informe_version ──> entrega
                                └──> (rama de laboratorio)
```

## La regla que ordena todo

> **REGLA** — El núcleo no conoce a las ramas. Ninguna tabla de `core` tiene una
> llave foránea hacia `lab` o `integra`. Es la rama la que apunta al núcleo. Si
> algo de aquí tuviera que cambiar cuando llegue imagenología, no es del núcleo.

## Orden de lectura sugerido

Los territorios se pueden leer sueltos, pero el orden de arriba es el que hace que
cada uno se apoye en el anterior. Los flujos conjuntos se leen después, cuando ya
existe el vocabulario.

## Qué falta en este panorama

> **ABIERTO** — Un diagrama de los estados que cambian a lo largo de una visita,
> cruzando episodio, orden, muestra y resultado en una sola línea de tiempo.
