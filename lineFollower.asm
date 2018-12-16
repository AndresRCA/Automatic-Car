list P = 16F877A
include <P16F877A.inc>

W_AUX EQU 20h
speed EQU 21h ; variable que guarda la velocidad actual del carro
turn_speed EQU 22h ; variable que posee valores menores a speed, se obtiene de la division de speed
aux EQU 23h ; variable auxiliar para realizar operaciones matematicas
cociente EQU 24h ; variable auxiliar para obtener el cociente en una division

org 0h
		goto TrackMode
org 4h
		movwf W_AUX ; guardo el valor previo de W para no generar comportamientos raros
		call TrackInt
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie
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
		bcf TRISD, 0 ; turning left led
		bcf TRISD, 1 ; turning right led
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
		bcf PORTD, 0 ; apago los leds de turning
		bcf PORTD, 1
;****************************** Inicializacion de variables ******************************************************
		clrf speed
		clrf turn_speed
		clrf cociente
;****************************************************************************************************************

;**************************************** Main Tracking Mode ****************************************************
		call fullSpeed
TMain 	goto TMain	
;****************************************************************************************************************

;************************************** Funciones INT Track Mode ************************************************
TrackInt		
		btfss PORTB, 6 ; reviso si el sensor de la derecha detecto la linea negra, si la toco entonces el carro tiene que girar a la derecha
		goto ChckRB4
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnRight
Keep1	btfsc PORTB, 6
		goto Keep1 ; Keep turning 1
		; tal vez haya que poner un ligero retardo antes de que termine de girar? nah, probablemente no
		call stopTurning ; si RB6 = 0 entonces ya no tiene que girar a la izquierda
		bcf INTCON, 0 ; bajo la bandera
		return
ChckRB4 btfss PORTB, 4
		goto FlsAlrm ; falsa alarma, aparentemente ni el sensor de la izquierda ni el de la derecha se activaron, o se activo por cuestiones de imperfecciones de la linea
		movf speed, 0
		call divideBy2
		movwf turn_speed
		call turnLeft
Keep2	btfsc PORTB, 6
		goto Keep2 ; Keep turning 2
		; tal vez haya que poner un ligero retardo antes de que termine de girar? nah, probablemente no
		call stopTurning ; si RB6 = 0 entonces ya no tiene que girar a la izquierda
FlsAlrm	bcf INTCON, 0 ; bajo la bandera
		return
;****************************************************************************************************************

;************************************** Funciones Generales *****************************************************
fullSpeed ; maxima velocidad en los motores delanteros y traseros
		movlw d'255'
		movwf speed
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
;****************************************************************************************************************
end