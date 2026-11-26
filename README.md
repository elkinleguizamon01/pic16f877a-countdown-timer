<div align="center">

# ⏱️ Programmable Countdown Timer — PIC16F877A Bare-Metal Firmware

**Firmware determinístico en lenguaje ensamblador (MPASM) para control de temporización por hardware, máquina de estados finitos, antirrebote no bloqueante y multiplexado de displays de 7 segmentos.**

![MCU](https://img.shields.io/badge/MCU-PIC16F877A-00599C?style=for-the-badge&logo=microchip&logoColor=white)
![Language](https://img.shields.io/badge/Language-Assembly%20(MPASM%20v5.87)-D35400?style=for-the-badge)
![Clock](https://img.shields.io/badge/Clock-4%20MHz%20XT-2E86C1?style=for-the-badge)
![Simulation](https://img.shields.io/badge/Simulation-Proteus%208%20VSM-1E8449?style=for-the-badge)

</div>

---

## 📌 Descripción General

Este proyecto implementa el firmware completo *bare-metal* de un temporizador regresivo programable de dos dígitos (`01` a `84` segundos) sobre el microcontrolador **Microchip PIC16F877A**. 

Diseñado sin retardos bloqueantes en la base de tiempo principal, el sistema combina una **Rutina de Servicio de Interrupción (ISR)** sincronizada con el periférico **Timer1** de 16 bits y un lazo cooperativo de $10\text{ ms}$ que gestiona simultáneamente el refresco de displays multiplexados ($\approx 100\text{ Hz}$), el filtrado digital de rebotes en pulsadores mecánicos y las transiciones de una **Máquina de Estados Finitos (FSM)**.

> 💡 *Sugerencia para tu repositorio: guarda una captura o GIF de la simulación en `docs/preview.gif` para mostrar el proyecto en acción aquí.*
>
> `![Demo en Proteus](docs/preview.gif)`

---

## 🚀 Aspectos Destacados de Ingeniería

* **Base de Tiempo Exacta por Hardware:** Generación de interrupciones periódicas cada $500\text{ ms}$ mediante **Timer1** (preescalador `1:8`) con recarga precisa (`0x0BDC`), evitando derivas acumulativas propias de los retardos por software.
* **Respaldo Completo de Contexto en ISR:** Preservación y restauración segura de `W`, `STATUS` y `PCLATH` en la memoria RAM común (`0x70–0x7F`), garantizando ejecución libre de corrupción de registros entre bancos y páginas.
* **Multiplexado Libre de *Ghosting* ($\approx 100\text{ Hz}$):** Conmutación alternada de dígitos cada $5\text{ ms}$ con apagado previo de líneas comunes (`RC0`, `RC1`) antes de actualizar el bus de segmentos (`PORTB`).
* **Tabla de Búsqueda Segura (`RETLW`):** Conversión BCD a 7 segmentos con cálculo dinámico de `PCLATH` y corrección de acarreo (`STATUS, C`), inmunizando el salto calculado frente al cruce de fronteras de 256 palabras en memoria de programa.
* **Antirrebote No Bloqueante por Muestreo:** Filtrado por ventana de estabilidad de $20\text{ ms}$ (3 lecturas consecutivas cada $10\text{ ms}$) con detección de flanco positivo, asegurando una única acción por pulsación sin interrumpir el refresco visual.
* **Configuración Parametrizable (`EQU`):** Límites operativos definidos en tiempo de ensamblado (`T_MAX = 84 s`, `T_INI = 19 s`, `T_ALARMA = 3 s` para semilla `S = 64`).

---

## 🔄 Arquitectura y Máquina de Estados (FSM)

El comportamiento del sistema se gobierna mediante cuatro estados mutuamente excluyentes (`CONFIG`, `CUENTA`, `PAUSA`, `FIN`) y una bandera de fase (`F_FASE`) que alterna cada $0,5\text{ s}$:

```mermaid
stateDiagram-v2
    [*] --> CONFIG : Encendido (T_PROG = 19 s)

    CONFIG --> CONFIG : UP (+1 hasta 84) / DOWN (-1 hasta 01) / RESET (T_PROG = 19)
    CONFIG --> CUENTA : START (T_REST = T_PROG, reinicia Timer1)

    CUENTA --> PAUSA : START / PAUSA
    CUENTA --> CONFIG : RESET (conserva T_PROG)
    CUENTA --> FIN : T_REST == 0

    PAUSA --> CUENTA : START / PAUSA (reinicia fase)
    PAUSA --> CONFIG : RESET (conserva T_PROG)

    FIN --> CONFIG : Fin T_ALARMA (3 s) / START / RESET
