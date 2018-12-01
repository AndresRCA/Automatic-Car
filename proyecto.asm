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
;* -RB0/INT: echo pin, este pin se pone en 0 cuando se recibe el eco del sensor        					  	  *
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
;* - RB0 external interrupt                                                     						 	  *
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
PORTB_AUX EQU 23h
aux EQU 27h ; variable auxiliar para realizar operaciones matematicas
cociente EQU 28h ; variable auxiliar para obtener el cociente en una division

;************* Variables modo COMP *****************************
timer EQU 24h
isReverse EQU 25h ; booleano que indica si el carro va en reverso, bit 0 = 1 significa true
ADRESH_AUX EQU 26h ; valor necesario para tomar decisiones en la busqueda de un oponente, si la siguiente conversion es menor a la anterior (ADRESH_AUX), se gira al lado contrario (esto puede cambiar)
;***************************************************************

;****************************************************************************************************************

org 0h
		goto CommonConfig
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
CommonConfig
;************************************** Configuracion Comun *****************************************************
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
		;******************************************    
		
		bcf STATUS, 5
		bcf PORTB, 1 ; lo pongo en 0 por si estaba en 1 antes (para el sensor)
		bsf T2CON, 1 ; configuro el prescaler 16 de TMR2, 00 = 1, 01 = 4, 1X = 16
		bsf T2CON, 2 ; prendo el TMR2
		bsf CCP1CON, 3 ; configuro el modulo CCP1 como PWM (11xx de bits 3-0)
		bsf CCP1CON, 2
		bsf CCP2CON, 3 ; configuro el modulo CCP2 como PWM (11xx de bits 3-0)
		bsf CCP2CON, 2
		;***************************************************************	
;****************************************************************************************************************

;****************************** Inicializacion de variables comunes **********************************************
		clrf speed
		clrf turn_speed
		clrf cociente
;****************************************************************************************************************

;****************************** Decision de modo ****************************************************************
		btfss PORTD, 0 ; asumiendo que RD0 es el que me dice en que modo esta
		goto TrackMode ; se que TrackMode esta justo abajo, pero dejo este goto para que sea mas legible el codigo
		goto CompMode
;****************************************************************************************************************

TrackMode
;**************************************** Main Tracking Mode ****************************************************
		call medSpeed
TMain 	goto TMain	
;****************************************************************************************************************

;************************************** Funciones INT Track Mode ************************************************
TrackInt		
		btfss PORTB, 6 ; reviso si el sensor de la derecha detecto la linea negra, si la toco entonces el carro tiene que girar a la derecha
		goto ChckRB4
		; movf speed, 0
		; call divideBy2
		; movwf turn_speed
		call turnRight
Keep1	btfsc PORTB, 6
		goto Keep1 ; Keep turning 1
		; tal vez haya que poner un ligero retardo antes de que termine de girar? nah, probablemente no
		call stopTurning ; si RB6 = 0 entonces ya no tiene que girar a la izquierda
		bcf INTCON, 0 ; bajo la bandera
		return
ChckRB4 btfss PORTB, 4
		goto FlsAlrm ; falsa alarma, aparentemente ni el sensor de la izquierda ni el de la derecha se activaron, o se activo por cuestiones de imperfecciones de la linea
		; movf speed, 0
		; call divideBy2
		; movwf turn_speed
		call turnLeft
Keep2	btfsc PORTB, 6
		goto Keep2 ; Keep turning 2
		; tal vez haya que poner un ligero retardo antes de que termine de girar? nah, probablemente no
		call stopTurning ; si RB6 = 0 entonces ya no tiene que girar a la izquierda
FlsAlrm	bcf INTCON, 0 ; bajo la bandera
		return
;****************************************************************************************************************

;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************

CompMode
;************************************** Configuracion Comp ******************************************************
		bsf STATUS, 5
		;************* Configuracion TMR1 ******************************
		; configuro aqui el prescaler de T1CON (bits 5-4 => 11 = 1:8, 10 = 1:4, 01 = 1:2, 00 = 1:1)
		bsf T1CON, 5
		bsf T1CON, 4
		bsf T1CON, 3 ; habilito el oscilador
		clrf TMR1H
		clrf TMR1L
		; ** recuerda prender el TMR1 en algun lado "bsf T1CON, 0" **
		;***************************************************************
		
		;************* Configuracion INT **********
		bsf INTCON, 6
		bsf INTCON, 6 ; int perifericos
		bsf PIE1, 0 ; habilito la interrupcion del overflow del TMR1
		bsf INTCON, 4 ; RB0 external interrupt
		bcf OPTION_REG, 6 ; RB0 interrumpe en flanco de bajada
		;******************************************
        
		bcf STATUS, 5
		bsf ADCON0, 0 ; enciendo el modulo conversor
;****************************************************************************************************************

;****************************** Inicializacion de variables *****************************************************
		clrf isReverse
		clrf timer
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
NotOn	call steppingLine ; aqui verifico los bits de RB para tomar las medidas correspondientes
		bsf T1CON, 0 ; prendo el TMR1
		call medSeg
		clrf timer ; limpio el timer para indicar el comienzo de la salida de la linea negra
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

seekingSpeed ; velocidad baja para la busqueda de un oponente
		movlw d'64'
		movwf speed
		movwf CCPR1L
		movwf CCPR2L
		return

medSpeed ; media velocidad en los motores delanteros y traseros	
		movlw d'128'
		movwf speed
		btfsc isReverse, 0
		comf speed, 0 ; si el carro va en reverso, se saca el valor complemento para que el duty cycle sea al reves, en este caso seria lo mismo...
		movwf CCPR1L
		movwf CCPR2L
		return
		
fullSpeed ; maxima velocidad en los motores delanteros y traseros
		movlw d'255'
		movwf speed
		btfsc isReverse, 0
		comf speed, 0 ; si el carro va en reverso, se saca el valor complemento para que el duty cycle sea al reves
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
		movf turn_speed, 0
		movwf CCPR2L
		return

turnLeft ; disminuir la velocidad de las ruedas en la izquierda
		movf turn_speed, 0
		movwf CCPR1L
		return
		
stopTurning ; ambos lados tienen la misma velocidad
		movf speed, 0
		movwf turn_speed ; turn_speed = speed
		movwf CCPR1L
		movwf CCPR2L
		return

fullyDeactivateTMR1 ; nombre bastante explicatorio, esto se llama cuando ocurren tanto cosas inesperadas como momentos de seguridad al salirse de la linea negra
		bcf T1CON, 0
		clrf TMR1H
		clrf TMR1L
		clrf time
		bcf isReverse, 0
		return
		
steppingLine ; funcion que se llama cuando el carro toca la linea en modo competitivo
		btfss PORTB, 7
		goto ChckRB5 ; chequeo la parte trasera
		bsf isReverse, 0 ; lo pongo en reversa
		call fullSpeed
		return
Keep3	btfsc PORTB, 7
		goto Keep3
		return
ChckRB5	btfss PORTB, 5
		nop ; <-- Aqui se activo algun sensor de los lados
		call fullSpeed ; ira al frente a toda velocidad
Keep4	btfsc PORTB, 5
		goto Keep4
		return
;****************************************************************************************************************

end
