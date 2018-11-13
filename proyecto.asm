list P = 16F877A
include <P16F877A.inc>
;**************************************** README **************************************************************
;* Lower side sensors:                                                                					  	  *
;* -RB7: front                                                                       					  	  *
;* -RB6: right                                                                         					  	  *
;* -RB5: back                                                                          					  	  *
;* -RB4: left                                                                        					  	  *
;*                                                                                  					  	  *
;* Mode port:                                                                      					  		  *
;* - RD0                                                                              					  	  *
;*                                                                                  					  	  *
;* Interrupciones usadas (Track Mode):                                                           			  *
;* - RB port change                                                             						 	  *
;*                                                              										  	  *
;* Interrupciones usadas (Comp Mode):                                                           			  *
;* - TMR1                                                             									 	  *
;* - RB port change                                                             						 	  *
;*                                                              										  	  *
;* Notas:                                                             									  	  *
;* - recuerda prender el TMR1 en algun lado "bsf T1CON, 0" (probablemente al final de RB<7:4> Int)		  	  *
;* - pendiente de cuando manipular el registro timer para evitar comportamientos raros (en interrupciones)	  *
;**************************************************************************************************************

;**************************************** Variables *************************************************************

W_AUX EQU 20h
speed EQU 21h ; variable que guarda la velocidad actual del carro
PORTB_AUX EQU 22h

;************* Variables modo COMP *****************************
timer EQU 23h
isReverse EQU 24h ; booleano que indica si el carro va en reverso, bit 0 = 1 significa true
ADRESH_AUX EQU 25h ; valor necesario para tomar decisiones en la busqueda de un oponente, si la siguiente conversion es menor a la anterior (ADRESH_AUX), se gira al lado contrario (esto puede cambiar)
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
NotRB	nop ; aqui iria la interrupcion de tmr1 o una verificacion de bits si existe otra interrupcion habilitada
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie

TrackM	call TrackInt
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie	
;****************************************************************************************************************
org 16h
TrackMode
;************************************** Configuracion Track *****************************************************		
		
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

;****************************** Inicializacion de variables *****************************************************
		clrf speed
		clrf isReverse
;****************************************************************************************************************

;**************************************** Main Tracking Mode ****************************************************

Main 	call medSpeed ; aqui probablemente se hacen conversiones A/D constantemente para decidir hacia donde girar y tomar decisiones respecto al resultado
		goto Main
		
;****************************************************************************************************************

;************************************** Funciones INT Track Mode ************************************************

TrackInt
		btfsc PORTB, 6 ; reviso si el sensor de la derecha detecto el suelo (cuando detecta el sensor se deberia poner en 0)
		goto ChckRB4
		call turnLeft
Keep1	btfss PORTB, 6 
		goto Keep1 ; Keep going 1
		call stopTurning ; si RB6 = 1 entonces ya no tiene que girar a la izquierda
		bcf INTCON, 0 ; bajo la bandera
		return
ChckRB4 btfsc PORTB, 4
		goto FlsAlrm ; falsa alarma, aparentemente ni el sensor de la izquierda ni el de la derecha se activaron, o se activo por cuestiones de imperfecciones de la linea
		call turnRight
Keep2	btfss PORTB, 6
		goto Keep2 ; Keep going 2
		call stopTurning ; si RB6 = 1 entonces ya no tiene que girar a la izquierda
FlsAlrm	bcf INTCON, 0 ; bajo la bandera
		return

;****************************************************************************************************************

;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************
;***********************************************************************************************************************************************************

CompMode
;************************************** Configuracion Comp ******************************************************
		
		;************* Configuracion TMR1 ******************************
		; configuro aqui el prescaler de T1CON (bits 5-4 => 11 = 1:8, 10 = 1:4, 01 = 1:2, 00 = 1:1)
		bsf T1CON, 5
		bsf T1CON, 4
		bsf T1CON, 3 ; habilito el oscilador
		clrf TMR1H
		clrf TMR1L
		; ** recuerda prender el TMR1 en algun lado "bsf T1CON, 0" **
		;***************************************************************
		
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
		bsf INTCON, 6 ; int perifericos
		bsf PIE1, 0 ; habilito la interrupcion del overflow del TMR1
		;******************************************
        
		bcf STATUS, 5
		bsf T2CON, 1 ; configuro el prescaler 16 de TMR2, 00 = 1, 01 = 4, 1X = 16
		bsf T2CON, 2 ; prendo el TMR2
		bsf CCP1CON, 3 ; configuro el modulo CCP1 como PWM (11xx de bits 3-0)
		bsf CCP1CON, 2
		bsf CCP2CON, 3 ; configuro el modulo CCP2 como PWM (11xx de bits 3-0)
		bsf CCP2CON, 2
		;***************************************************************
		bsf ADCON0, 0 ; enciendo el modulo conversor
		
;****************************************************************************************************************

;****************************** Inicializacion de variables *****************************************************
		clrf speed
		clrf isReverse
		clrf timer
		
;****************************************************************************************************************

;**************************************** Main Comp Mode ********************************************************

Main 	nop ; aqui probablemente se hacen conversiones A/D constantemente para decidir hacia donde girar y tomar decisiones respecto al resultado
		goto Main
		
;****************************************************************************************************************

;************************************** Funciones ***************************************************************

medSeg	; le doy el valor necesario a TMR1 para que interrumpa en medio segundo
		movlw b'11011100'
		movwf TMR1L
		movlw b'00001011'
		movwf TMR1H
		return

seekingSpeed ; velocidad baja para la busqueda de un oponente
		movlw d'64'
		movwf speed ; esta linea no es necesaria pero lo dejo por legibilidad
		movwf CPPR1L
		movwf CPPR2L
		return

medSpeed ; media velocidad en los motores delanteros y traseros	
		movlw d'128'
		movwf speed
		btfsc isReverse, 0
		comf speed, 0 ; si el carro va en reverso, se saca el valor complemento para que el duty cycle sea al reves, en este caso seria lo mismo...
		movwf CPPR1L
		movwf CPPR2L
		return
		
fullSpeed ; maxima velocidad en los motores delanteros y traseros
		movlw d'255'
		movwf speed
		btfsc isReverse, 0
		comf speed, 0 ; si el carro va en reverso, se saca el valor complemento para que el duty cycle sea al reves
		movwf CPPR1L
		movwf CPPR2L
		return
		
turnRight ; apagar el motor de la rueda derecha
		; RD1 = 1 o algo asi que apague ese motor
		return

turnLeft ; apagar el motor de la rueda derecha
		; RD0 = 1 o algo asi que apague ese motor
		return
		
stopTurning ; ninguna rueda esta girando
		; RD1 y RD0 = 0 o algo asi
		return
		
;****************************************************************************************************************

;************************************** Funciones INT Comp Mode *************************************************

RBChangeInt ; tomo las medidas necesarias para redirigir el auto
		movf PORTB, 0
		movwf PORTB_AUX ; necesario para salir de la interrupcion, o simplemente indico que PORTB debe ser 0 para que el carro salga de la linea
		; aqui verifico los bits de RB para hacer giros
		bsf T1CON, 0 ; prendo el TMR1
		call medSeg
		clrf timer ; limpio el timer para indicar el comienzo de la salida de la linea negra
		bcf INTCON, 0 ; apago la bandera al final cuando PORTB vuelve a su estado original (00000000) asumiendo que los sensores al detectar la linea negra se pongan en 1
		; tal vez verificar aqui si la bandera realmente se limpio?
		return

TMR1Int ; verifico cuantos segundos han pasado (todavia no se sabe cuantos segundos seran, por ahora 4s)
		bcf PIR1, 0 ; apago la bandera del TMR1 overflow
		incf time, 1
		btfsc time, 3 ; si time es 8, han pasado 4 segundos
		goto Safe ; time = 8
		call medSeg ; si no es 8 entonces espero el otro medio segundo
		return
Safe	clrf time
		; aqui el carro hace lo suyo, despues de exitosamente salirse de la linea negra hace 4 segundos
		bcf T1CON, 0 ; apago el TMR1 y lo activo al final de la interrupcion de RB<7:4> cuando esta ocurra
		return

;****************************************************************************************************************

end
