list P = 16F877A
include <P16F877A.inc>

;DIFERENCIAS CON MASTER:
;USA TMR0 (AL IGUAL QUE ULTRASOUND)
;LA FUNCTION TMR1Int (LA PARTE DE "SAFE")

;**************************************** Variables *************************************************************

W_AUX EQU 20h
speed EQU 21h ; variable que guarda la velocidad actual del carro
turn_speed EQU 22h ; variable que posee valores menores a speed, se obtiene de la division de speed
aux EQU 23h ; variable auxiliar para realizar operaciones matematicas
cociente EQU 24h ; variable auxiliar para obtener el cociente en una division

;************* Variables modo COMP *****************************
time EQU 25h
isReverse EQU 26h ; booleano que indica si el carro va en reverso, bit 0 = 1 significa true
;***************************************************************

;****************************************************************************************************************

org 0h
		goto CompMode
;********************************** Interrupcion ****************************************************************		
org 4h
		movwf W_AUX ; guardo el valor previo de W para no generar comportamientos raros
		btfss INTCON, 0 ; reviso bandera de RB<7:4>
		goto NotRB
		call RBChangeInt
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie
NotRB	call TMR1Int
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie
;****************************************************************************************************************
org 16h
CompMode
;************************************** Configuracion Comp Mode *************************************************
		movf PORTB, 0 ; leo PORTB para poder bajar la bandera de RB port change por si se encuentra en 1 
		bcf INTCON, 0 ; bajo la bandera RBIF
		
		;************* Configuracion PWM 1 y 2 *************************
		; PWMduty cycle = (CCPR1L : CCP1CON(5,4))*Tosc*(Prescaler de TMR2)
		; En nuestro caso: duty cycle de 100% es decir, CCPR1L = 255, hallo el periodo -> 1*PWMperiodo = 1020*(1/4*10^-6)*16 = 4.08*10^-3, 1020 es 11111111:00 => CCPR1L:CCP1CON(5,4) con CCPR1L = ADRESH
		clrf CCPR1L ; el duty sera de 0 al inicio
		clrf CCPR2L
		bsf STATUS, 5
		movlw d'254' ; PWMperiodo = (PR2+1)*4*Tosc*(Prescaler de TMR2) => PR2 = (4.08*10^-3)/(10^-6 * 16) = 254
		movwf PR2 ; el valor calculado de X se carga para el periodo de la onda, el valor de PR2, no se debe exceder de 255 o ser negativo en el calculo, si se excede se debe usar otro prescaler
		
		;************* Configuracion pines ********
		bcf TRISC, 2 ; configuro pin ccp1 como salida
		bcf TRISC, 1 ; configuro pin ccp2 como salida
		bcf TRISB, 1 ; RB1 es el Trig del sensor de ultrasonido
		; RB<7:4> son los sensores
		bcf TRISD, 0 ; turning left led
		bcf TRISD, 1 ; turning right led
		bcf TRISD, 2 ; TMR1 led
		bcf TRISD, 3 ; led de reversa
		;******************************************
		
		;************* Configuracion INT **********
		bsf INTCON, 7 ; global
		bsf INTCON, 3 ; RB Port Change Interrupt Enable bit RB<7:4>
		bsf INTCON, 6 ; int perifericos
		bsf PIE1, 0 ; habilito la interrupcion del overflow del TMR1
		;******************************************    
		
		;************* Configuracion TMR1 *********
		; configuro aqui el prescaler de T1CON (bits 5-4 => 11 = 1:8, 10 = 1:4, 01 = 1:2, 00 = 1:1)
		bsf T1CON, 5
		bsf T1CON, 4
		bsf T1CON, 3 ; habilito el oscilador
		clrf TMR1H
		clrf TMR1L
		; ** recuerda prender el TMR1 en algun lado "bsf T1CON, 0" **
		;******************************************		
		
		;************* Configuracion TMR0 *********
		bcf OPTION_REG, 0 ; prescaler 128 para cubrir la distancia maxima de 4 metros (TMR0 = 182) y evitar overflows
		bcf OPTION_REG, 5 ; el tmr0 es temporizador
		bcf OPTION_REG, 3 ; prescaler asignado a tmr0
		;******************************************	
		
		bcf STATUS, 5
		bsf T2CON, 1 ; configuro el prescaler 16 de TMR2, 00 = 1, 01 = 4, 1X = 16
		bsf T2CON, 2 ; prendo el TMR2
		bsf CCP1CON, 3 ; configuro el modulo CCP1 como PWM (11xx de bits 3-0)
		bsf CCP1CON, 2
		bsf CCP2CON, 3 ; configuro el modulo CCP2 como PWM (11xx de bits 3-0)
		bsf CCP2CON, 2
		;***************************************************************
		
		bcf PORTB, 1 ; lo pongo en 0 por si estaba en 1 antes (para el sensor)
		bsf ADCON0, 0 ; enciendo el modulo conversor
;****************************************************************************************************************
		bcf PORTD, 0 ; apago los leds de turning
		bcf PORTD, 1
		bcf PORTD, 2 ; apago el led del TMR1
		bcf PORTD, 3 ; apago el led de reversa
;****************************** Inicializacion de variables *****************************************************
		clrf speed
		clrf turn_speed
		clrf cociente
		clrf isReverse
		clrf time
;****************************************************************************************************************

;**************************************** Main Comp Mode ********************************************************
CMain 	nop ; aqui probablemente se hacen conversiones A/D constantemente para decidir hacia donde girar y tomar decisiones respecto al resultado
		goto CMain		
;****************************************************************************************************************

;************************************** Funciones INT Comp Mode *************************************************
RBChangeInt ; tomo las medidas necesarias para redirigir el auto
		btfss T1CON, 0 ; verifico si el timer1 esta prendido, si lo esta entonces ocurrio la interrupcion RB mientras trataba de salir de una linea momentos antes
		goto NotOn ; no esta prendido
		; si esta prendido deshabilito todo eso  
		call fullyDeactivateTMR1
NotOn	bcf PORTD, 3 ; led de reversa
		bcf isReverse, 0 ; por si acaso, no se sabe que puede ocurrir en la competencia
		call stopTurning ; podria estar dando vueltas por el modo seeking
		call steppingLine ; aqui verifico los bits de RB para tomar las medidas correspondientes
		bsf PORTD, 2 ; prendo el led de TMR1
		bsf T1CON, 0 ; prendo el TMR1
		call medSeg
		clrf time ; limpio el timer para indicar el comienzo de la salida de la linea negra
		bcf INTCON, 0 ; apago la bandera al final cuando PORTB vuelve a su estado original (00000000) asumiendo que los sensores al detectar la linea negra se pongan en 1
		return

TMR1Int ; verifico cuantos segundos han pasado (todavia no se sabe cuantos segundos seran, por ahora 4s)
		bcf PIR1, 0 ; apago la bandera del TMR1 overflow
		incf time, 1
		btfsc time, 3 ; si time es 8, han pasado 4 segundos
		goto Safe ; time = 8
		call medSeg ; si no es 8 entonces espero el otro medio segundo
		return
Safe	; aqui el carro hace lo suyo, despues de exitosamente salirse de la linea negra hace 4 segundos
		call fullyDeactivateTMR1 ; apago el TMR1 y lo activo al final de la interrupcion de RB<7:4> cuando esta ocurra
		bcf PORTD, 3 ; led de reversa
		bcf isReverse, 0
		return
;****************************************************************************************************************

;************************************** Funciones Generales *****************************************************
medSeg	; le doy el valor necesario a TMR1 para que interrumpa en medio segundo
		movlw b'11011100'
		movwf TMR1L
		movlw b'00001011'
		movwf TMR1H
		return
		
fullSpeed ; maxima velocidad en los motores delanteros y traseros
		movlw d'255'
		movwf speed
		;btfsc isReverse, 0
		;comf speed, 0 ; si el carro va en reverso, se saca el valor complemento para que el duty cycle sea al reves
		movwf CCPR1L
		movwf CCPR2L
		return
		
divideBy2 ; funcion que divide entre 2 el numero que ingresa a w previamente
		clrf cociente
		movwf aux
		movlw d'2'
Divide	subwf aux, 1
		btfss STATUS, 0 ; cuando la resta de negativo entonces la division se completo
		goto DivEnd
		incf cociente, 1 ; incremento el valor del cociente por cada resta
		goto Divide
DivEnd	movf cociente, 0 ; muevo el cociente a w
		return ; w al final da el cociente de la division		
		
turnRight ; disminuir la velocidad de las ruedas en la derecha
		bsf PORTD, 1
		movf turn_speed, 0
		movwf CCPR2L
		return

turnLeft ; disminuir la velocidad de las ruedas en la izquierda
		bsf PORTD, 0
		movf turn_speed, 0
		movwf CCPR1L
		return
		
stopTurning ; ambos lados tienen la misma velocidad
		bcf PORTD, 0
		bcf PORTD, 1
		movf speed, 0
		movwf turn_speed ; turn_speed = speed
		movwf CCPR1L
		movwf CCPR2L
		return

fullyDeactivateTMR1 ; nombre bastante explicatorio, esto se llama cuando ocurren tanto cosas inesperadas como momentos de seguridad al salirse de la linea negra
		bcf PORTD,2 
		bcf T1CON, 0
		clrf TMR1H
		clrf TMR1L
		clrf time
		return	
		
;#define LEFT_SENSOR RB4
;#define RIGHT_SENSOR RB6
;#define BACK_SENSOR RB5		
steppingLine ; funcion que se llama cuando el carro toca la linea en modo competitivo
		btfsc PORTB, 4 ; LEFT_SENSOR && RIGHT_SENSOR
		btfss PORTB, 6
		goto Nxt1 ; siguiente condicion
		; sensor izquierdo y derecho estan activados
		bsf PORTD, 3 ; led de reversa
		bsf isReverse, 0
		call fullSpeed
KP1		btfsc PORTB, 4
		goto KP1
		btfsc PORTB, 6
		goto KP1
		; aqui finalmente ni el sensor izquierda ni el derecho son 1
		return
Nxt1	btfsc PORTB, 4 ; LEFT_SENSOR && BACK_SENSOR
		btfss PORTB, 5
		goto Nxt2
		; sensor izquierdo y trasero estan activados
		call fullSpeed
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnRight
		call delay2s
		call stopTurning
KP2		btfsc PORTB, 5
		goto KP2
		return
Nxt2	btfsc PORTB, 6 ; RIGHT_SENSOR && BACK_SENSOR
		btfss PORTB, 5
		goto Nxt3
		call fullSpeed
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnLeft
		call delay2s
		call stopTurning
KP3		btfsc PORTB, 5
		goto KP3
		return
Nxt3	btfss PORTB, 4 ; LEFT_SENSOR
		goto Nxt4
		bsf PORTD, 3 ; led de reversa
		bsf isReverse, 0
		call fullSpeed
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnRight
		call delay2s
		call stopTurning
KP4		btfsc PORTB, 4
		goto KP4
		return
Nxt4	btfss PORTB, 6 ; RIGHT_SENSOR
		goto Nxt5
		bsf PORTD, 3 ; led de reversa
		bsf isReverse, 0
		call fullSpeed
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnLeft
		call delay2s
		call stopTurning
KP5		btfsc PORTB, 6
		goto KP5
		return
Nxt5	btfss PORTB, 5 ; BACK_SENSOR
		return ; guess I'll die (the port change would be the only sensor that left the black line, or something like that, think of it like a null check)
		call fullSpeed
KP5		btfsc PORTB, 5
		goto KP5
		return

; 30 ms = 1*PRE*(256 - X) => PRE = 128 => X = 21.625 = 22, valor para un retraso de 30 ms
delay2s
		movlw d'70' ; 30ms * 70 = 2.1s
		movwf aux
SrtDl	bcf INTCON, 2 ;apago la bandera del tmr0
        movlw d'22' ; aproximadamente 30 ms
        movwf TMR0
Back    btfss INTCON, 2
        goto Back
        decfsz aux, 1
		goto SrtDl
		return
;****************************************************************************************************************
end
