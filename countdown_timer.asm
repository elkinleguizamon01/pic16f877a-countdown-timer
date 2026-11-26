;===============================================================================
; Temporizador Regresivo con el PIC16F877A
; Ensamblador: MPASM v5.87 (MPLAB X v5.35) | Oscilador: Cristal 4 MHz (XT)
; Semilla: 64 -> T_MAX = 84 s | T_INI = 19 s | T_ALARMA = 3 s
;===============================================================================
        LIST        P=16F877A
        #include    <p16f877a.inc>
        ERRORLEVEL  -302                ; Suprimir aviso de cambio de banco

        __CONFIG    _XT_OSC & _WDT_OFF & _PWRTE_ON & _BODEN_OFF & _LVP_OFF & _CP_OFF


SEMILLA         EQU .64                 ; Dos últimos dígitos del código menor
T_MAX           EQU .60 + (SEMILLA % .40)   ; 60 + (64 mod 40) = 84 s
T_INI           EQU .15 + (SEMILLA % .30)   ; 15 + (64 mod 30) = 19 s
T_ALARMA        EQU .3  + (SEMILLA % .4)    ; 3  + (64 mod 4)  = 3 s

; Recarga Timer1 para 0,5 s exactos con Fosc = 4 MHz y Preescalador 1:8
; Tcy = 1 us -> T_cuenta = 8 us -> N = 0,5 s / 8 us = 62500 cuentas
; Recarga = 65536 - 62500 = 3036 = 0x0BDC
T1_RECARGA      EQU .65536 - .62500
T1_RECARGA_H    EQU HIGH T1_RECARGA     ; 0x0B
T1_RECARGA_L    EQU LOW  T1_RECARGA     ; 0xDC

; Estados de la máquina de estados
EST_CONFIG      EQU .0
EST_CUENTA      EQU .1
EST_PAUSA       EQU .2
EST_FIN         EQU .3

; Bits de BANDERAS
F_MEDIO         EQU .0                  ; 1 = pasó 0,5 s (activado en ISR)
F_FASE          EQU .1                  ; 0 = fase visible/alarma ON; 1 = apagado

; Bits de botones (PORTA invertido: 1 = pulsado)
B_UP            EQU .0                  ; RA0
B_DOWN          EQU .1                  ; RA1
B_START         EQU .2                  ; RA2
B_RESET         EQU .3                  ; RA3

        CBLOCK  0x20
            ESTADO                      ; Estado actual (0..3)
            T_PROG                      ; Tiempo programado (1..84)
            T_REST                      ; Tiempo restante en cuenta/pausa
            CONT_ALARMA                 ; Segundos restantes de alarma en FIN
            BANDERAS                    ; Banderas de tiempo (F_MEDIO, F_FASE)
            VAL_MOSTRAR                 ; Valor a convertir y visualizar
            DECENAS                     ; Dígito de las decenas (0..9)
            UNIDADES                    ; Dígito de las unidades (0..9)
            INDICE                      ; Índice temporal para tabla 7 seg
            BTN_RAW                     ; Lectura cruda actual de botones
            BTN_PREV_RAW                ; Lectura cruda anterior
            BTN_CNT                     ; Contador de estabilidad (antirrebote)
            BTN_ESTABLE                 ; Estado confirmado de los botones
            BTN_EVENTO                  ; Flancos de pulsación (1 acción/pulso)
            DLY_INT                     ; Contador interno retardo 5 ms
            DLY_EXT                     ; Contador externo retardo 5 ms
        ENDC


        CBLOCK  0x70
            W_TEMP                      ; Respaldo de W
            STATUS_TEMP                 ; Respaldo de STATUS
            PCLATH_TEMP                 ; Respaldo de PCLATH
        ENDC

        ORG     0x0000
        goto    INICIO


        ORG     0x0004
ISR
        movwf   W_TEMP                  ; Guardar W sin alterar flags
        swapf   STATUS, W               ; Copiar STATUS sin alterar Z
        clrf    STATUS                  ; Seleccionar Banco 0
        movwf   STATUS_TEMP             ; Guardar STATUS
        movf    PCLATH, W               ; Guardar PCLATH
        movwf   PCLATH_TEMP
        clrf    PCLATH                  ; Asegurar Página 0

        btfss   PIR1, TMR1IF            ; ¿La interrupción fue de Timer1?
        goto    ISR_SALIR               ; Si no, salir

        bcf     PIR1, TMR1IF            ; 1. Borrar bandera primero
        movlw   T1_RECARGA_H            ; 2. Recargar Timer1 (0x0BDC)
        movwf   TMR1H
        movlw   T1_RECARGA_L
        movwf   TMR1L
        bsf     BANDERAS, F_MEDIO       ; 3. Avisar al programa principal

ISR_SALIR
        movf    PCLATH_TEMP, W          ; Restaurar PCLATH
        movwf   PCLATH
        swapf   STATUS_TEMP, W          ; Restaurar STATUS
        movwf   STATUS
        swapf   W_TEMP, F               ; Restaurar W sin alterar flags
        swapf   W_TEMP, W
        retfie


INICIO
        ; --- Configuración en Banco 1 ---
        BANKSEL ADCON1
        movlw   0x06                    ; Configurar PORTA y PORTE como digitales
        movwf   ADCON1
        movlw   0x07                    ; Desactivar comparadores analógicos
        movwf   CMCON
        movlw   b'00001111'             ; RA0..RA3 entradas (botones)
        movwf   TRISA
        clrf    TRISB                   ; RB0..RB6 salidas (segmentos a..g)
        clrf    TRISC                   ; RC0..RC1 comunes, RC2 LED, RC3 buzzer
        bsf     PIE1, TMR1IE            ; Habilitar interrupción de Timer1

        ; --- Inicialización de puertos y variables en Banco 0 ---
        BANKSEL PORTA
        clrf    PORTB                   ; Segmentos apagados
        movlw   b'00000011'             ; RC0=1, RC1=1 (displays OFF), alarma OFF
        movwf   PORTC

        movlw   EST_CONFIG              ; Estado inicial: CONFIG
        movwf   ESTADO
        movlw   T_INI                   ; Tiempo inicial programado = 19 s
        movwf   T_PROG
        movwf   T_REST
        clrf    CONT_ALARMA
        clrf    BANDERAS
        clrf    BTN_PREV_RAW
        clrf    BTN_CNT
        clrf    BTN_ESTABLE
        clrf    BTN_EVENTO

        ; --- Configurar y arrancar Timer1 (1:8, reloj interno, 0,5 s) ---
        movlw   T1_RECARGA_H
        movwf   TMR1H
        movlw   T1_RECARGA_L
        movwf   TMR1L
        bcf     PIR1, TMR1IF            ; Limpiar bandera previa
        movlw   b'00110001'             ; Preescalador 1:8, interno, TMR1ON=1
        movwf   T1CON

        bsf     INTCON, PEIE            ; Habilitar interrupciones periféricas
        bsf     INTCON, GIE             ; Habilitar interrupciones globales


LAZO_PRINCIPAL
        btfsc   BANDERAS, F_MEDIO       ; ¿Se cumplieron 0,5 s?
        call    PROCESAR_TIEMPO         ; Sí: actualizar fase, cuenta o alarma

        call    REFRESCAR_DISPLAYS      ; Refresca decenas (5 ms) + unidades (5 ms)
        call    LEER_BOTONES            ; Muestreo cada 10 ms (antirrebote 20 ms)

        movf    BTN_EVENTO, F           ; ¿Hubo alguna pulsación confirmada?
        btfss   STATUS, Z
        call    PROCESAR_BOTONES        ; Sí: ejecutar transición de la FSM

        goto    LAZO_PRINCIPAL


PROCESAR_TIEMPO
        bcf     BANDERAS, F_MEDIO       ; Limpiar bandera de 0,5 s
        movlw   (1 << F_FASE)           ; Alternar bit F_FASE (0 <-> 1)
        xorwf   BANDERAS, F

        ; Verificar si estamos en CUENTA
        movf    ESTADO, W
        xorlw   EST_CUENTA
        btfsc   STATUS, Z
        goto    TIEMPO_CUENTA

        ; Verificar si estamos en FIN
        movf    ESTADO, W
        xorlw   EST_FIN
        btfsc   STATUS, Z
        goto    TIEMPO_FIN

        ; En CONFIG o PAUSA no se modifica ningún contador (PAUSA usa F_FASE)
        return

TIEMPO_CUENTA
        btfsc   BANDERAS, F_FASE        ; Solo restar cuando F_FASE vuelve a 0
        return

        decfsz  T_REST, F               ; T_REST = T_REST - 1; ¿llegó a 0?
        return                          ; No: continuar contando

        ; T_REST llegó a 0 -> pasar a estado FIN con alarma activa
        movlw   EST_FIN
        movwf   ESTADO
        movlw   T_ALARMA                ; Cargar duración de alarma (3 s)
        movwf   CONT_ALARMA
        bsf     PORTC, 2                ; Encender LED (primeros 0,5 s ON)
        bsf     PORTC, 3                ; Encender zumbador
        return

TIEMPO_FIN
        btfss   BANDERAS, F_FASE        ; ¿F_FASE = 1 (medio segundo apagado)?
        goto    TIEMPO_FIN_SEG          ; No: F_FASE = 0 -> pasó 1 segundo completo

        ; F_FASE = 1: apagar LED y zumbador por 0,5 s
        bcf     PORTC, 2
        bcf     PORTC, 3
        return

TIEMPO_FIN_SEG
        decfsz  CONT_ALARMA, F          ; ¿Se completaron los 3 segundos?
        goto    TIEMPO_FIN_ON           ; No: encender alarma otro 0,5 s

        ; Terminó T_ALARMA -> volver a CONFIG conservando T_PROG
        goto    IR_A_CONFIG

TIEMPO_FIN_ON
        bsf     PORTC, 2                ; Encender LED
        bsf     PORTC, 3                ; Encender zumbador
        return


LEER_BOTONES
        clrf    BTN_EVENTO              ; Sin eventos por defecto
        comf    PORTA, W                ; Invertir lógica: pulsado (0) -> 1
        andlw   0x0F                    ; Aislar RA0..RA3
        movwf   BTN_RAW

        xorwf   BTN_PREV_RAW, W         ; ¿Es igual a la lectura anterior?
        btfss   STATUS, Z
        goto    BTN_CAMBIO              ; Cambió: reiniciar contador

        movf    BTN_CNT, F              ; ¿Ya estaba confirmado?
        btfsc   STATUS, Z
        return                          ; Sí (BTN_CNT=0): evitar repeticiones

        decfsz  BTN_CNT, F              ; Decrementar conteo de estabilidad
        return                          ; Aún no cumple 20 ms estables

        ; Confirmado (3 lecturas seguidas iguales): detectar flanco 0 -> 1
        comf    BTN_ESTABLE, W          ; W = ~BTN_ESTABLE
        andwf   BTN_PREV_RAW, W         ; Solo bits nuevos en 1
        movwf   BTN_EVENTO
        movf    BTN_PREV_RAW, W
        movwf   BTN_ESTABLE             ; Guardar nuevo estado estable
        return

BTN_CAMBIO
        movf    BTN_RAW, W
        movwf   BTN_PREV_RAW
        movlw   .2                      ; 2 lecturas adicionales (+ esta = 3 -> 20 ms)
        movwf   BTN_CNT
        return

PROCESAR_BOTONES
        movf    ESTADO, W
        xorlw   EST_CONFIG
        btfsc   STATUS, Z
        goto    EVT_CONFIG

        movf    ESTADO, W
        xorlw   EST_CUENTA
        btfsc   STATUS, Z
        goto    EVT_CUENTA

        movf    ESTADO, W
        xorlw   EST_PAUSA
        btfsc   STATUS, Z
        goto    EVT_PAUSA

        goto    EVT_FIN

; --- Acciones en CONFIG ---
EVT_CONFIG
        btfsc   BTN_EVENTO, B_RESET     ; RESET -> T_PROG = T_INI (19)
        goto    CFG_RESET

        btfsc   BTN_EVENTO, B_START     ; START -> T_REST = T_PROG y pasar a CUENTA
        goto    CFG_START

        btfsc   BTN_EVENTO, B_UP        ; UP -> +1 hasta T_MAX (84)
        goto    CFG_UP

        btfsc   BTN_EVENTO, B_DOWN      ; DOWN -> -1 hasta 1
        goto    CFG_DOWN
        return

CFG_RESET
        movlw   T_INI
        movwf   T_PROG
        return

CFG_START
        movf    T_PROG, W
        movwf   T_REST
        movlw   EST_CUENTA
        movwf   ESTADO
        goto    REINICIAR_T1            ; Primer segundo completo

CFG_UP
        movlw   T_MAX
        subwf   T_PROG, W               ; W = T_PROG - T_MAX; C=1 si T_PROG >= 84
        btfss   STATUS, C               ; Si C=0 (T_PROG < 84), incrementar
        incf    T_PROG, F
        return

CFG_DOWN
        movlw   .2
        subwf   T_PROG, W               ; W = T_PROG - 2; C=1 si T_PROG >= 2
        btfsc   STATUS, C               ; Si C=1 (T_PROG >= 2), decrementar
        decf    T_PROG, F
        return

; --- Acciones en CUENTA ---
EVT_CUENTA
        btfsc   BTN_EVENTO, B_RESET     ; RESET -> volver a CONFIG (conserva T_PROG)
        goto    IR_A_CONFIG

        btfsc   BTN_EVENTO, B_START     ; START/PAUSA -> pasar a PAUSA
        goto    CNT_PAUSA
        return                          ; UP y DOWN sin efecto

CNT_PAUSA
        movlw   EST_PAUSA
        movwf   ESTADO
        goto    REINICIAR_T1            ; Inicia parpadeo 1 Hz limpio

; --- Acciones en PAUSA ---
EVT_PAUSA
        btfsc   BTN_EVENTO, B_RESET     ; RESET -> volver a CONFIG (conserva T_PROG)
        goto    IR_A_CONFIG

        btfsc   BTN_EVENTO, B_START     ; START/PAUSA -> reanudar CUENTA
        goto    PAU_REANUDAR
        return                          ; UP y DOWN sin efecto

PAU_REANUDAR
        movlw   EST_CUENTA
        movwf   ESTADO
        goto    REINICIAR_T1            ; Reinicia Timer1 y fase (1 s completo)

; --- Acciones en FIN ---
EVT_FIN
        btfsc   BTN_EVENTO, B_RESET     ; RESET -> silenciar y volver a CONFIG
        goto    IR_A_CONFIG

        btfsc   BTN_EVENTO, B_START     ; START -> silenciar y volver a CONFIG
        goto    IR_A_CONFIG
        return                          ; UP y DOWN sin efecto


IR_A_CONFIG
        bcf     PORTC, 2                ; Apagar LED de alarma
        bcf     PORTC, 3                ; Apagar zumbador
        movlw   EST_CONFIG
        movwf   ESTADO
        return


REINICIAR_T1
        bcf     INTCON, GIE             ; Deshabilitar interrupciones con seguridad
        btfsc   INTCON, GIE
        goto    $-2

        bcf     T1CON, TMR1ON           ; Pausar Timer1
        movlw   T1_RECARGA_H
        movwf   TMR1H
        movlw   T1_RECARGA_L
        movwf   TMR1L
        bcf     PIR1, TMR1IF            ; Limpiar desborde pendiente
        bcf     BANDERAS, F_MEDIO
        bcf     BANDERAS, F_FASE
        bsf     T1CON, TMR1ON           ; Reanudar Timer1
        bsf     INTCON, GIE             ; Rehabilitar interrupciones
        return


REFRESCAR_DISPLAYS
        ; Determinar valor y visibilidad según el estado
        movf    ESTADO, W
        xorlw   EST_CONFIG
        btfsc   STATUS, Z
        goto    DISP_CONFIG

        movf    ESTADO, W
        xorlw   EST_CUENTA
        btfsc   STATUS, Z
        goto    DISP_CUENTA

        movf    ESTADO, W
        xorlw   EST_PAUSA
        btfsc   STATUS, Z
        goto    DISP_PAUSA

        ; Estado FIN: muestra 00 parpadeando según F_FASE
        btfsc   BANDERAS, F_FASE        ; Si F_FASE = 1, mantener apagados
        goto    DISP_APAGADO
        clrf    VAL_MOSTRAR             ; Mostrar 00
        goto    DISP_ENCENDIDO

DISP_CONFIG
        movf    T_PROG, W
        movwf   VAL_MOSTRAR
        goto    DISP_ENCENDIDO

DISP_CUENTA
        movf    T_REST, W
        movwf   VAL_MOSTRAR
        goto    DISP_ENCENDIDO

DISP_PAUSA
        btfsc   BANDERAS, F_FASE        ; Si F_FASE = 1, mantener apagados
        goto    DISP_APAGADO
        movf    T_REST, W
        movwf   VAL_MOSTRAR

DISP_ENCENDIDO
        movf    VAL_MOSTRAR, W
        call    BIN_A_BCD               ; Separar en DECENAS y UNIDADES

        ; --- Encender DECENAS (5 ms) ---
        bsf     PORTC, 0                ; Apagar ambos dígitos (evita fantasma)
        bsf     PORTC, 1
        movf    DECENAS, W
        call    TABLA_7SEG
        movwf   PORTB
        bcf     PORTC, 0                ; Activar común 1 (decenas, activo en 0)
        call    RETARDO_5MS

        ; --- Encender UNIDADES (5 ms) ---
        bsf     PORTC, 0                ; Apagar ambos dígitos (evita fantasma)
        bsf     PORTC, 1
        movf    UNIDADES, W
        call    TABLA_7SEG
        movwf   PORTB
        bcf     PORTC, 1                ; Activar común 2 (unidades, activo en 0)
        call    RETARDO_5MS
        return

DISP_APAGADO
        bsf     PORTC, 0                ; Ambos comunes en 1 (apagados)
        bsf     PORTC, 1
        clrf    PORTB
        call    RETARDO_5MS             ; Mantener ciclo exacto de 10 ms
        call    RETARDO_5MS
        return

BIN_A_BCD
        clrf    DECENAS
        movwf   UNIDADES
BCD_LAZO
        movlw   .10
        subwf   UNIDADES, W             ; W = UNIDADES - 10; C=1 si UNIDADES >= 10
        btfss   STATUS, C
        return                          ; Si C=0, UNIDADES < 10 -> terminado
        movwf   UNIDADES
        incf    DECENAS, F
        goto    BCD_LAZO

TABLA_7SEG
        movwf   INDICE
        movlw   HIGH T_SEG_INICIO
        movwf   PCLATH
        movf    INDICE, W
        addlw   LOW T_SEG_INICIO
        btfsc   STATUS, C               ; ¿Cruzó límite de 256 palabras?
        incf    PCLATH, F               ; Sí: ajustar parte alta del PC
        movwf   PCL                     ; Salto calculado
T_SEG_INICIO
        retlw   0x3F                    ; 0 -> a,b,c,d,e,f
        retlw   0x06                    ; 1 -> b,c
        retlw   0x5B                    ; 2 -> a,b,d,e,g
        retlw   0x4F                    ; 3 -> a,b,c,d,g
        retlw   0x66                    ; 4 -> b,c,f,g
        retlw   0x6D                    ; 5 -> a,c,d,f,g
        retlw   0x7D                    ; 6 -> a,c,d,e,f,g
        retlw   0x07                    ; 7 -> a,b,c
        retlw   0x7F                    ; 8 -> a,b,c,d,e,f,g
        retlw   0x6F                    ; 9 -> a,b,c,d,f,g

RETARDO_5MS
        movlw   .10
        movwf   DLY_EXT
DLY_L1
        movlw   .165
        movwf   DLY_INT
DLY_L2
        decfsz  DLY_INT, F
        goto    DLY_L2                  ; 165 * 3 - 1 = 494 us
        decfsz  DLY_EXT, F
        goto    DLY_L1                  ; 10 * ~499 us ≈ 5,00 ms
        return

        END
