list P = 16F877A
include <P16F877A.inc>

W_AUX EQU 20h

org 0h
		goto CommonConfig
;********************************** Interrupcion ****************************************************************		
org 4h
		movwf W_AUX ; guardo el valor previo de W para no generar comportamientos raros
		call RB0Int
		movf W_AUX, 0 ; devuelvo el valor de W
		retfie	
;****************************************************************************************************************
org 16h
CommonConfig
		bsf STATUS, 5
		bcf TRISB, 1 ; RB1 es el Trig del sensor de ultrasonido
		;************* Configuracion TMR1 ******************************
		; configuro aqui el prescaler de T1CON (bits 5-4 => 11 = 1:8, 10 = 1:4, 01 = 1:2, 00 = 1:1)
		bsf T1CON, 5 ; prescaler 1:8
		bsf T1CON, 4
		bsf T1CON, 3 ; habilito el oscilador
		clrf TMR1H
		clrf TMR1L
		;***************************************************************
		
		;************* Configuracion INT **********
		bsf INTCON, 7 ; global
		bsf INTCON, 6 ; int perifericos
		bsf PIE1, 0 ; habilito la interrupcion del overflow del TMR1
		bsf INTCON, 4 ; RB0 external interrupt
		bcf OPTION_REG, 6 ; RB0 interrumpe en flanco de bajada
		;******************************************
        
		bcf STATUS, 5
		bcf PORTB, 1
		
Main	nop
		goto Main		
	
RB0Int
		bcf INTCON, 1
		; resto de la funcion
		return