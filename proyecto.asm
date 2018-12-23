list P = 16F877A
include <P16F877A.inc>
;**************************************** README **************************************************************
;* Lower side sensors:                                                                					  	  *
;* -RB7: front                                                                       					  	  *
;* -RB6: right                                                                         					  	  *
;* -RB5: back                                                                          					  	  *
;* -RB4: left                                                                        					  	  *
;*                                                                                  					  	  *
;* Ultrasound sensor:                                                               					  	  *
;* -RB?: echo pin, este pin se pone en 0 cuando se recibe el eco del sensor        						  	  *
;* -RB1: Trig pin, este pin se usa para generar el pulso de 10 micro segundos para mandar una onda 		 	  *
;*                                                                                  					  	  *
;* Mode port:                                                                      					  		  *
;* - RD0 (1 = CompMode, 0 = TrackMode)                                              					  	  *
;*                                                                                  					  	  *
;* Interrupciones usadas (Track Mode):                                                           			  *
;* - RB port change                                                             						 	  *
;*                                                              										  	  *
;* Interrupciones usadas (Comp Mode):                                                           			  *
;* - TMR1                                                             									 	  *
;* - RB port change                                                             						 	  *
;*                                                              										  	  *
;* Notas:                                                             									  	  *
;* - pendiente de cuando manipular el registro timer para evitar comportamientos raros (en interrupciones)	  *
;* - recuerda poner algo debajo de ChckRB5 en steppingLine, que comportamiento para los sensores laterales    *
;* 	 seria bueno?                                                                                             *
;* - steppingLine es un trabajo en progreso, el comportamiento puede ser discutido                        	  *
;* - las funciones para girar todavia no estan disenadas para ser usadas en retroceso               	  	  *
;* - en TrackInt se asume que los sensores laterales estan fuera de la linea                        	  	  *
;**************************************************************************************************************

;**************************************** Variables *************************************************************

W_AUX EQU 20h
speed EQU 21h ; variable que guarda la velocidad actual del carro
turn_speed EQU 22h ; variable que posee valores menores a speed, se obtiene de la division de speed
aux EQU 23h ; variable auxiliar para realizar operaciones matematicas
cociente EQU 24h ; variable auxiliar para obtener el cociente en una division

;************* Variables modo COMP *****************************
time EQU 25h
isReverse EQU 26h ; booleano que indica si el carro va en reverso, bit 0 = 1 significa true
isEscaping EQU 27h ; booleano que indica si el carro esta escapando de la linea negra
toggle EQU 28h
isRotating EQU 29h
ms500_to_sweep EQU 2Ah
sweeps EQU 2Bh
ms500_to_rotate EQU 2Ch
;***************************************************************

;****************************************************************************************************************

org 0h
		btfss PORTD, 0 ; asumiendo que RD0 es el que me dice en que modo esta
		goto TrackMode
		goto CompMode
;********************************** Interrupcion ****************************************************************		
org 4h
		movwf W_AUX ; guardo el valor previo de W para no generar comportamientos raros
		btfss PORTD, 0
		goto TrackM ; Track Mode Interruption
		btfss INTCON, 0 ; reviso bandera de RB<7:4>
		goto NotRB
		call RBChangeInt
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie
NotRB	call TMR1Int
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie

TrackM	call TrackInt
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie	
;****************************************************************************************************************
org 16h
TrackMode
;************************************** Configuracion Track Mode ************************************************
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
		; RB<7:4> son los sensores
		;******************************************
		
		;************* Configuracion INT **********
		bsf INTCON, 7 ; global
		bsf INTCON, 3 ; RB Port Change Interrupt Enable bit RB<7:4>
		;******************************************    
		
		bcf STATUS, 5
		bsf T2CON, 1 ; configuro el prescaler 16 de TMR2, 00 = 1, 01 = 4, 1X = 16
		bsf T2CON, 2 ; prendo el TMR2
		bsf CCP1CON, 3 ; configuro el modulo CCP1 como PWM (11xx de bits 3-0)
		bsf CCP1CON, 2
		bsf CCP2CON, 3 ; configuro el modulo CCP2 como PWM (11xx de bits 3-0)
		bsf CCP2CON, 2
		;***************************************************************	
;****************************************************************************************************************

;****************************** Inicializacion de variables ******************************************************
		clrf speed
		clrf turn_speed
		clrf cociente
;****************************************************************************************************************

;**************************************** Main Tracking Mode ****************************************************
		movlw d'128' ; MED_SPEED
		call setSpeed ; speed = MED_SPEED
		movlw d'64' ; speed/2
		movwf turn_speed
		call stopTurning ; el carro va derecho al inicio
TMain 	goto TMain
;****************************************************************************************************************

;************************************** Funciones INT Track Mode ************************************************
TrackInt
		btfsc PORTB, 6 ; left && right
		btfss PORTB, 4
		goto ChckRB6
		call stopTurning
		goto TrckEnd
ChckRB6	btfss PORTB, 6 ; reviso si el sensor de la derecha detecto la linea negra, si la toco entonces el carro tiene que girar a la derecha
		goto ChckRB4
		call turnRight
		goto TrckEnd
ChckRB4 btfss PORTB, 4
		goto AllOff ; left || right = false
		call turnLeft
		goto TrckEnd
AllOff	call stopTurning		
TrckEnd	bcf INTCON, 0 ; bajo la bandera
		return
;****************************************************************************************************************

;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************

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
		
		bcf STATUS, 5
		bsf T2CON, 1 ; configuro el prescaler 16 de TMR2, 00 = 1, 01 = 4, 1X = 16
		bsf T2CON, 2 ; prendo el TMR2
		bsf CCP1CON, 3 ; configuro el modulo CCP1 como PWM (11xx de bits 3-0)
		bsf CCP1CON, 2
		bsf CCP2CON, 3 ; configuro el modulo CCP2 como PWM (11xx de bits 3-0)
		bsf CCP2CON, 2
		;***************************************************************
		
		bcf PORTB, 1 ; lo pongo en 0 por si estaba en 1 antes (para el sensor)
;****************************************************************************************************************

;****************************** Inicializacion de variables *****************************************************
		clrf speed
		clrf turn_speed
		clrf cociente
		clrf isReverse
		clrf isEscaping
		clrf time
		clrf toggle
		clrf isRotating
		movlw d'5' ; al comienzo el carro va a comenzar en el medio del barrido
		movwf ms500_to_sweep
		clrf sweeps
		clrf ms500_to_rotate
;****************************************************************************************************************

;**************************************** Main Comp Mode ********************************************************
CMain 	btfsc isEscaping, 0 ; si el carro esta escapando, no hacer nada
		goto CMain
		;************ ultra sound function *************
		; ultra sound decision making goes here
		;***********************************************
NtClose	btfsc isRotating, 0 ; si el carro esta rotando, dejar volver a medir la distancia al inicio del CMain
		goto CMain
		movlw d'64' ; SEEKING_SPEED
		call setSpeed
		movlw d'32' ; SEEKING_SPEED/2
		movwf turn_speed
		btfss toggle, 0 ; toggle alterna cada 5 segundos, haciendo que el carro se mueva como una serpiente
		goto Lft
		call turnRight
		goto CMain
Lft		call turnLeft
		goto CMain
;****************************************************************************************************************

;************************************** Funciones INT Comp Mode *************************************************
RBChangeInt ; tomo las medidas necesarias para redirigir el auto
		bsf isEscaping, 0
		btfsc PORTB, 4
		goto StpLine
		btfsc PORTB, 6
		goto StpLine
		btfsc PORTB, 5
		goto StpLine
		bsf T1CON, 0 ; todos los sensores estan en 0, por lo tanto esta escapando
		call medSeg
		clrf time ; limpio el timer para indicar el comienzo de la salida de la linea negra
		goto RBEnd
StpLine	call fullyDeactivateTMR1 ; limpio todo los procesos que involucren el tmr1 fuera de la interrupcion RB
		call stopTurning ; detengo lo que estaba haciendo antes
		call steppingLine ; aqui verifico los bits de RB para tomar las medidas correspondientes
RBEnd	bcf INTCON, 0 ; apago la bandera al final cuando PORTB vuelve a su estado original (00000000) asumiendo que los sensores al detectar la linea negra se pongan en 1
		return

TMR1Int ; verifico cuantos segundos han pasado (todavia no se sabe cuantos segundos seran, por ahora 4s)
		bcf PIR1, 0 ; apago la bandera del TMR1 overflow
		btfss isEscaping, 0
		goto IsRotng ; is rotating?
		incf time, 1 ; aqui el carro esta escapando
		btfsc time, 3 ; si time es 8, han pasado 4 segundos
		goto Safe ; time = 8
		call medSeg ; si no es 8 entonces espero el otro medio segundo
		return
Safe	; aqui el carro hace lo suyo, despues de exitosamente salirse de la linea negra hace 4 segundos
		clrf time ; limpio time
		bcf isReverse, 0 ; por si el carro iba en reversa
		bcf isEscaping, 0 ; es el final del escape
		call medSeg ; empieza el conteo del modo de barrido
		return			
isRotng	btfss isRotating, 0
		goto NtRot ; not rotating
		incf ms500_to_rotate, 1
		movlw d'24'
		subwf ms500_to_rotate, 0
		btfss STATUS, 2 ; ms500_to_rotate == 24 (12 segundos)
		goto DntStop ; dont stop rotating, keep counting
		clrf ms500_to_rotate
		bcf isRotating, 0 ; ya el carro no esta rotando
		call stopTurning
		movlw d'5' ; el carro va a entrar en medio barrido como el comienzo
		movwf ms500_to_sweep
DntStop	call medSeg ; es el inicio del barrido o seguir contando la rotacion
		return
NtRot	incf ms500_to_sweep, 1 ; si no esta rotando ni esta escapando, el carro deberia estar barriendo
		movlw d'10' ; SWEEP_TIME
		subwf ms500_to_sweep, 0
		btfss STATUS, 2 ; ms500_to_sweep == 10
		goto KpSwpng ; not yet, dont toggle, keep sweeping
		movlw d'1'
		xorwf toggle, 1 ; toggle = !toggle, 1 xor 1 = 0 ; 1 xor 0 = 1
		clrf ms500_to_sweep
		incf sweeps, 1
		btfss sweeps, 2 ; si sweeps = 4, es decir si el carro barrio 4 veces
		goto KpSwpng ; si sweeps no es 4, simplemente sigo en el medio del barrido
		clrf sweeps ; si sweeps = 4 -> sweeps = 0 y el resto de lo que sigue
		bsf isRotating, 0
		call rotate
KpSwpng	call medSeg ; o sigue barriendo o empieza el conteo del inicio de la rotacion
		return
;****************************************************************************************************************

;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************

;************************************** Funciones Generales *****************************************************
medSeg	; le doy el valor necesario a TMR1 para que interrumpa en medio segundo
		movlw b'11011100'
		movwf TMR1L
		movlw b'00001011'
		movwf TMR1H
		return
		
setSpeed ; accepts a value from w
		movwf speed
		return
		
turnRight ; disminuir la velocidad de las ruedas en la derecha
		movf speed, 0
		movwf CCPR1L
		movf turn_speed, 0
		movwf CCPR2L
		return

turnLeft ; disminuir la velocidad de las ruedas en la izquierda
		movf speed, 0
		movwf CCPR2L
		movf turn_speed, 0
		movwf CCPR1L
		return
		
stopTurning ; ambos lados tienen la misma velocidad
		movf speed, 0
		movwf CCPR1L
		movwf CCPR2L
		return

fullyDeactivateTMR1 ; nombre bastante explicatorio, esto se llama cuando ocurren tanto cosas inesperadas como momentos de seguridad al salirse de la linea negra
		bcf T1CON, 0
		clrf TMR1H
		clrf TMR1L
		clrf time
		clrf sweeps
		clrf ms500_to_rotate
		clrf ms500_to_sweep
		bcf isRotating, 0
		return		

steppingLine ; funcion que se llama cuando el carro toca la linea en modo competitivo
		btfsc PORTB, 4 ; LEFT_SENSOR && RIGHT_SENSOR
		btfss PORTB, 6
		goto Nxt1 ; siguiente condicion
		; sensor izquierdo y derecho estan activados
		bsf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		call stopTurning
		return
Nxt1	btfsc PORTB, 4 ; LEFT_SENSOR && BACK_SENSOR
		btfss PORTB, 5
		goto Nxt2
		; sensor izquierdo y trasero estan activados
		bcf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		movlw d'128' ; FULL_SPEED/2
		movwf turn_speed
		call turnRight
		return
Nxt2	btfsc PORTB, 6 ; RIGHT_SENSOR && BACK_SENSOR
		btfss PORTB, 5
		goto Nxt3
		bcf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		movlw d'128' ; FULL_SPEED/2
		movwf turn_speed
		call turnLeft
		return
Nxt3	btfss PORTB, 4 ; LEFT_SENSOR
		goto Nxt4
		bsf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		movlw d'128' ; FULL_SPEED/2
		movwf turn_speed
		call turnRight
		return
Nxt4	btfss PORTB, 6 ; RIGHT_SENSOR
		goto Nxt5
		bsf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		movlw d'128' ; FULL_SPEED/2
		movwf turn_speed
		call turnLeft
		return
Nxt5	btfss PORTB, 5 ; BACK_SENSOR
		return ; guess I'll die (the port change would be the only sensor that left the black line, or something like that, think of it like a null check)
		bcf isReverse, 0
		movlw d'255' ; FULL_SPEED
		call setSpeed ; speed = FULL_SPEED
		call stopTurning
		return
		
rotate ; funcion que hace rotar al carro
		nop
		return
;****************************************************************************************************************

end
