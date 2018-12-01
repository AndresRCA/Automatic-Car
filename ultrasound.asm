list P = 16F877A
include <P16F877A.inc>

org 0h
		bsf STATUS, 5
		bcf TRISB, 1 ; RB1 es el Trig del sensor de ultrasonido
		bcf TRISB, 2 ; un led cualquiera que me indica si estoy en proximidad
		;************* Configuracion TMR0 ******************************
		bcf OPTION_REG, 2 ; prescaler 16 para tener mejor precision de distancias cortas
		;***************************************************************
		bcf STATUS, 5
		bcf PORTB, 2
		bcf PORTB, 1
		
Main	bsf PORTB, 1
		call delay10us
		bcf PORTB, 1
		call startCounting ; el tmr0 va a empezar a contar desde 0
NotYet	btfsc PORTB, 0 ; espero a que el pin de eco se baje, que es cuando recibe la respuesta
		goto NotYet
		call TMR0_OFF
		movlw d'34' ; distancia cm = (X/Prescaler)*(1/2*29,1) => 10 cm = (X/16)*(1/2*29,1) => X = 33
		subwf TMR0, 0
		btfsc STATUS, 0 ; si TMR0 = 33 -> 33 - 34 = -1 -> C = 0, si esta en proximidad
		goto NotClose
		bsf PORTB, 2 ; se prende el led que me dice que estoy en proximidad
		goto Main
		
NotClose
		bcf PORTB, 2
		goto Main
	
delay10us
		nop ; aqui hay 6 nops, el call y return cuentan como 4 micro segundos
		nop
		nop
		nop
		nop
		nop
		return

TMR0_ON
		bsf STATUS, 5
		bcf OPTION_REG, 3 ; en esencia apago el TMR0
		bcf STATUS, 5
		return
		
TMR0_OFF
		bsf STATUS, 5
		bsf OPTION_REG, 3 ; en esencia prendo el TMR0
		bcf STATUS, 5
		return
		
startCounting
		clrf TMR0
		call TMR0_ON
		return
		
end