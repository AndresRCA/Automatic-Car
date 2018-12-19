// CONFIG
#pragma config FOSC = XT        // Oscillator Selection bits (XT oscillator)
#pragma config WDTE = OFF       // Watchdog Timer Enable bit (WDT disabled)
#pragma config PWRTE = OFF      // Power-up Timer Enable bit (PWRT disabled)
#pragma config BOREN = ON       // Brown-out Reset Enable bit (BOR enabled)
#pragma config LVP = OFF        // Low-Voltage (Single-Supply) In-Circuit Serial Programming Enable bit (RB3 is digital I/O, HV on MCLR must be used for programming)
#pragma config CPD = OFF        // Data EEPROM Memory Code Protection bit (Data EEPROM code protection off)
#pragma config WRT = OFF        // Flash Program Memory Write Enable bits (Write protection off; all program memory may be written to by EECON control)
#pragma config CP = OFF         // Flash Program Memory Code Protection bit (Code protection off)

#include <xc.h>

#define _XTAL_FREQ 4000000
#define TRUE 1
#define FALSE 0

#define MODE RD0 // 1 = comp, 0 = tracking

/* speed constants for variable speed */
#define FULL_SPEED 255
#define MED_SPEED 128
#define SEEKING_SPEED 64

/* left and right sensor remain outside the line in tracking mode */
#define LEFT_SENSOR RB4
#define RIGHT_SENSOR RB6
#define BACK_SENSOR RB5

#define ECHO RB2 //not decided yet
#define TRIG RB1
#define PROXIMITY_DISTANCE 5 // 5 => 11 cm with TMR0 prescaler = 128

#define SWEEP_TIME 10 // 5 seconds for a full sweep => 10 because tmr1 counts up to 500ms
#define ROTATING_TIME 24 // 12 seconds for a full 360 rotation, this depends on the car itself

//I want this definition to work
/*typedef struct {
    unsigned isReverse		:1;
    unsigned isTurningRight	:1;
    unsigned isTurningLeft	:1;
    unsigned				:5;
} CarState;
volatile CarState car_state;
car_state.isReverse = FALSE;
car_state.isTurningLeft = FALSE;
car_state.isTurningRight = FALSE;*/
volatile bit isReverse = FALSE;
volatile bit isEscaping = FALSE; // if it's not escaping, it's seeking a new target
volatile bit toggle = FALSE;
volatile bit isRotating = FALSE;

typedef unsigned char byte;
volatile byte time = 0;
volatile byte speed = 0;
volatile byte turn_speed = 0;
volatile byte ms500_to_sweep = 5; // in the beginning the car will start in the middle of the sweep
volatile byte sweeps = 0;
volatile byte ms500_to_rotate = 0;

/* Configuration functions */
inline void PWM_INIT(void);
inline void INT_INIT(void);
inline void TMR1_INIT(void);
inline void TMR0_INIT(void);

/* Main functions */
void setSpeed(byte); // accepts FULL_SPEED, MED_SPEED and SEEKING_SPEED
/*void setTurnSpeed(void); //currently all it does is set it to speed/2*/
void turnRight(void);
void turnLeft(void);
void stopTurning(void);
void rotate(void);

/* Comp functions */
void medSeg(void);
bit assessProximity(byte distance);

/* functions used only in interruptions */
inline void steppingLine(void);

void main(void) {
    PORTB;
    RBIF = 0; // just in case it's 1
    PWM_INIT();
    INT_INIT();
    if(MODE) {
        TMR1_INIT();
        TMR0_INIT();
    }
    TRIG = 0; // in case it's on
    
    if(MODE) {
        /* Comp mode */
        medSeg(); // the initial 500ms when sweeping
        while(1) {
        	if(isEscaping) continue; // when escaping I don't want to do anything
            if(assessProximity(PROXIMITY_DISTANCE)) {
                /* a car is near */
                /* reset everything about sweeping (I don't care about the direction that comes from toggle) */
                sweeps = 0;
                ms500_to_sweep = 5; //the car will make half a sweep like at the beginning
				
				/* this will interrupt only when assessProximity has failed 20 times in a row (25ms * 20 = 500ms). */
                medSeg(); // this is for when the car stops chasing the car, think more about the consequences of this
                
                setSpeed(FULL_SPEED);
                stopTurning();
            }
            else {
                /* no car detected */
                if(isRotating) continue; // when rotating don't do anything except what made isRotating = TRUE
                else {
                    setSpeed(SEEKING_SPEED);
                    if(toggle) { //toggle alternates every 5 seconds, making the car move like a snake
                        turnRight();
                    }
                    else {
                        turnLeft();
                    }
                }
            }
        }
    }
    else {
        /* Tracking mode */
        setSpeed(MED_SPEED);
		turn_speed = 64; //this is just a plain declaration for the rest of the mode (MED_SPEED/2)
        stopTurning(); // assigns the speed to the proper motors
        while(1);
    }
    return;
}

inline void PWM_INIT(void) {
    CCPR1L = 0;
    CCPR2L = 0;
    PR2 = 254;
    TRISC1 = 0; //motor pins
    TRISC2 = 0;
    T2CKPS1 = 1; // TMR2 prescaler = 1:16
    TMR2ON = 1;
    CCP1M3 = 1; // b'1100'
    CCP1M2 = 1;
    CCP2M3 = 1; // b'1100'
    CCP2M2 = 1;
    return;
}

inline void INT_INIT(void) {
    GIE = 1;
    RBIE = 1;
    if(MODE) {
        PEIE = 1;
        TMR1IE = 1;
    }
    return;
}

inline void TMR1_INIT(void) {
    T1CKPS0 = 1; // TMR1 prescaler = 1:8
    T1CKPS1 = 1;
    TMR1 = 0;
    return;
}

inline void TMR0_INIT(void) {
	PS0 = 0; //prescaler 128
	PSA = 0; //prescaler assigned to TMR0
	T0CS = 0; // TMR0 clock source = internal cycle clock
	return;
}

void setSpeed(byte spd) {
    speed = spd;
    return;
}

/*void setTurnSpeed(void) {
	turn_speed = speed/2; //could change depending of tests
	return
}*/

void turnRight(void) {
    CCPR1L = speed;
    CCPR2L = turn_speed;
    return;
}

void turnLeft(void) {
    CCPR2L = speed;
    CCPR1L = turn_speed;
    return;
}

void stopTurning(void) {
    CCPR1L = speed;
    CCPR2L = speed;
    return;
}

void rotate(void) {
    //left wheel going full forward + right wheel going full reverse, I guess
    return;
}

void medSeg(void) {
    TMR1 = 56331; // after setting TMR1, I wait for an interruption
    return;
}

bit assessProximity(byte distance) {
	TRIG = 1;
	__delay_us(10);
	TRIG = 0;
	while(!ECHO); // I wait for echo pin to go up
	TMR0 = 0; // I start counting, with prescaler 128, the max value it will get is 182 (4 meters)
	while(ECHO); // I wait for echo pin to go down
	if(TMR0 <= distance){
		return 1;
	}
	else {
		return 0;
	}
}

/* cleans everything concerning TMR1 functionality outside RB change interruption */
void fullyDeactivateTMR1(void) {
    TMR1ON = 0;
    TMR1 = 0;
    time = 0;
    sweeps = 0;
    ms500_to_rotate = 0;
    ms500_to_sweep = 0;
    isRotating = FALSE;
    isEscaping = FALSE;
    return;
}

/* This function is subject of discussion */
inline void steppingLine(void) {
    if(LEFT_SENSOR && RIGHT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
        stopTurning();
    }
    else if(LEFT_SENSOR && BACK_SENSOR) {
        isReverse = FALSE;
        setSpeed(FULL_SPEED);
		turn_speed = 127; //FULL_SPEED/2
        //setTurnSpeed();
        turnRight();
    }
    else if(RIGHT_SENSOR && BACK_SENSOR) {
        isReverse = FALSE;
        setSpeed(FULL_SPEED);
		turn_speed = 127; //FULL_SPEED/2
        //setTurnSpeed();
        turnLeft();
    }
    else if(LEFT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
		turn_speed = 127; //FULL_SPEED/2
        //setTurnSpeed();
        turnRight();
    }
    else if(RIGHT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
		turn_speed = 127; //FULL_SPEED/2
        //setTurnSpeed();
        turnLeft();
    }
    else if(BACK_SENSOR) { // this could just be an else but I'm leaving it like this just in case
        isReverse = FALSE;
        setSpeed(FULL_SPEED);
        stopTurning();
    }
    return;
}

void interrupt ISR(void){
    if(MODE) {
        /* Comp mode interruption */
        if(RBIF) {
            if(LEFT_SENSOR || RIGHT_SENSOR || BACK_SENSOR) {
                fullyDeactivateTMR1();                
                stopTurning(); // in case the car was turning before getting knocked back
                steppingLine(); // here I check RB bits to take the proper measures
            }
            else { //here the car basically escaped the black line
                isEscaping = TRUE;
                TMR1ON = 1;
                medSeg();
                time = 0;
            }
            RBIF = 0;
            return;
        }
        
        //TMR1 interruption
        TMR1IF = 0;
        if(isRotating) { //the rotating takes sort of priority
            ms500_to_rotate++;
            if(ms500_to_rotate == ROTATING_TIME) {
                ms500_to_rotate = 0;
                isRotating = FALSE;
                stopTurning();
            }
            else {
                medSeg(); // keep rotating
            }
        }
        if(!isEscaping) {
            /* do the seeking movement toggle function */
            ms500_to_sweep++;
            if(ms500_to_sweep == SWEEP_TIME) {
                toggle = !toggle;
                ms500_to_sweep = 0;
                sweeps++;
                if(sweeps == 4) { //assume the car makes its sweeping motion 4 times before rotating 360 degrees
                    sweeps = 0;
                    isRotating = TRUE;
                    rotate();
					medSeg(); // start counting the time it takes to rotate
                }
            }
            else {
                medSeg(); //keep counting
            }
            return;
        }
        else {
            /* do the escaping timer function */
            time++;
            if(time == 8) { // if timer = 8, then 4 seconds have passed
                // here the car does its thing
                time = 0;
                isReverse = FALSE; //In case the car was going in reverse
                isEscaping = FALSE; // this condition is important for the main function
            }
            else {
                medSeg(); // I keep counting
            }
        }
        return;
    }
    /* Tracking mode interruption */
    if(RIGHT_SENSOR && LEFT_SENSOR) { //it could happen...
        stopTurning();
    }
    else if(RIGHT_SENSOR) {
        turnRight();
    }
    else if(LEFT_SENSOR) {
        turnLeft();
    }
    else { // RIGHT_SENSOR || LEFT_SENSOR = FALSE
        stopTurning();
    }
    RBIF = 0;
    return;
    
}