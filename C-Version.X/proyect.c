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
#define FRONT_SENSOR RB7
#define BACK_SENSOR RB5

#define ECHO RB2 //not decided yet
#define TRIG RB1
#define PROXIMITY_DISTANCE 5 // 5 => 11 cm with TMR0 prescaler = 128

//I want this definition to work
/*typedef struct {
    unsigned isReverse		:1;
    unsigned isTurningRight	:1;
    unsigned isTurningLeft	:1;
    unsigned				:5;
} CarState;
volatile CarState car_state;
car_stateisReverse = FALSE;
car_state.isTurningLeft = FALSE;
car_state.isTurningRight = FALSE;*/
volatile bit isReverse = FALSE;
volatile bit isTurningLeft = FALSE;
volatile bit isTurningRight = FALSE;

typedef unsigned char byte;
volatile byte time = 0;
volatile byte speed = 0;
volatile byte turn_speed = 0;

/* Configuration functions */
void inline PWM_INIT(void);
void inline INT_INIT(void);
void inline TMR1_INIT(void);
void inline TMR0_INIT(void);

/* Main functions */
void setSpeed(byte); // accepts FULL_SPEED, MED_SPEED and SEEKING_SPEED
void turnRight(void);
void turnLeft(void);
void stopTurning(void);

/* Comp functions */
void medSeg(void);
bit assessProximity(byte distance);

/* functions used only in interruptions */
void inline steppingLine(void);

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
        while(1) {
        	if(TMR1ON) continue; // TMR1 is only on when escaping a black line
            if(assessProximity(PROXIMITY_DISTANCE)) {
                /* a car is near */
                stopTurning(); // this function is redundant, setSpeed() accomplishes the same goal
                setSpeed(FULL_SPEED);
            }
            else {
                /* no car detected */
                setSpeed(SEEKING_SPEED);
                if(isTurningRight) continue; //the car was already turning, no need to call turnRight(), this saves me the problem of setSpeed() and turnRight() constantly changing the value of CCPR2L back and forth
        		turnRight(); //this will only be called after assessProximity returns 0
            }
        }
    }
    else {
        /* Tracking mode */
        setSpeed(MED_SPEED);
        while(1);
    }
    return;
}

void inline PWM_INIT(void) {
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

void inline INT_INIT(void) {
    GIE = 1;
    RBIE = 1;
    if(MODE) {
        PEIE = 1;
        TMR1IE = 1;
    }
    return;
}

void inline TMR1_INIT(void) {
    T1CKPS0 = 1; // TMR1 prescaler = 1:8
    T1CKPS1 = 1;
    TMR1 = 0;
    return;
}

void inline TMR0_INIT(void) {
	PS0 = 0; //prescaler 128
	PSA = 0; //prescaler assigned to TMR0
	T0CS = 0; // TMR0 clock source = internal cycle clock
	return;
}

void setSpeed(byte spd) {
    speed = spd;
    CCPR1L = spd;
    CCPR2L = spd;
    return;
}

void turnRight(void) {
    CCPR2L = turn_speed;
    isTurningRight = TRUE;
    return;
}

void turnLeft(void) {
    CCPR1L = turn_speed;
    isTurningLeft = TRUE;
    return;
}

void stopTurning(void) {
    CCPR1L = speed;
    CCPR2L = speed;
    isTurningRight = FALSE;
    isTurningLeft = FALSE;
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

void fullyDeactivateTMR1(void) {
    TMR1ON = 0;
    TMR1 = 0;
    time = 0;
    return;
}

/* This function is subject of discussion */
void inline steppingLine(void) {
    if(FRONT_SENSOR && LEFT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
        //turn_speed = ??
        turnRight();
        __delay_ms(500);
        stopTurning();
        while(FRONT_SENSOR);
    }
    else if(FRONT_SENSOR && RIGHT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
        //turn_speed = ??
        turnLeft();
        __delay_ms(500);
        stopTurning();
        while(FRONT_SENSOR);
    }
    else if(BACK_SENSOR && LEFT_SENSOR) {
        setSpeed(FULL_SPEED);
        //turn_speed = ??
        turnRight();
        __delay_ms(500);
        stopTurning();
        while(BACK_SENSOR);
    }
    else if(BACK_SENSOR && RIGHT_SENSOR) {
        setSpeed(FULL_SPEED);
        //turn_speed = ??
        turnLeft();
        __delay_ms(500);
        stopTurning();
        while(BACK_SENSOR);
    }
    else if(FRONT_SENSOR) {
        isReverse = TRUE;
        setSpeed(FULL_SPEED);
        while(FRONT_SENSOR);
    }
    else if(BACK_SENSOR) {
        setSpeed(FULL_SPEED);
        while(BACK_SENSOR);
    }
    else { //this else is not neccesary
        //I guess I'll just die
    }
    return;
            
    /*switch(1) {
        // constant expressions are required here... too bad
        case FRONT_SENSOR && LEFT_SENSOR:
            isReverse = TRUE;
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnRight();
            __delay_ms(500);
            stopTurning();
            while(FRONT_SENSOR);
            return;
        
        case FRONT_SENSOR && RIGHT_SENSOR:
            isReverse = TRUE;
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnLeft();
            __delay_ms(500);
            stopTurning();
            while(FRONT_SENSOR);
            return;

        case BACK_SENSOR && LEFT_SENSOR:
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnRight();
            __delay_ms(500);
            stopTurning();
            while(BACK_SENSOR);
            return;

        case BACK_SENSOR && RIGHT_SENSOR:
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnLeft();
            __delay_ms(500);
            stopTurning();
            while(BACK_SENSOR);
            return;

        case FRONT_SENSOR:
            isReverse = TRUE;
            setSpeed(FULL_SPEED);
            while(FRONT_SENSOR);
            return;

        case BACK_SENSOR:
            setSpeed(FULL_SPEED);
            while(BACK_SENSOR);
            return;

        default:
            //I guess I'll just die
            return;
    }*/
}

void interrupt ISR(void){
    if(MODE) {
        /* Comp mode interruption */
        if(RBIF) {
            if(TMR1ON) {
                fullyDeactivateTMR1();
            }
            isReverse = FALSE; // just in case, can't know for sure what'll happen in a competition
            stopTurning(); // in case the car was turning before getting knocked back
            steppingLine(); // here I check RB bits to take the proper measures
            TMR1ON = 1;
            medSeg();
            time = 0;
            RBIF = 0;
            return;
        }
        
        //TMR1 interruption
        TMR1IF = 0;
        time++;
        if(time == 8) { // if timer = 8, then 4 seconds have passed
            // here the car does its thing
            fullyDeactivateTMR1();
            isReverse = FALSE; //In case the car was going in reverse
        }
        else {
            medSeg(); // I keep counting
        }
        return;
    }
    /* Tracking mode interruption */        
    if(RIGHT_SENSOR) {
        // turn_speed = ??;
        turnRight();
        while(RIGHT_SENSOR); // the car keeps turning until it's 0
    }
    else if(LEFT_SENSOR) { //else to avoid a situation where both RIGHT_SENSOR AND LEFT_SENSOR equals 1
        // turn_speed = ??;
        turnLeft();
        while(LEFT_SENSOR); // the car keeps turning until it's 0
    }
    stopTurning(); // after the previous sensor goes back to 0, the car stops turning
    PORTB; // just in case the other sensors detected a change
    RBIF = 0;
    return;
}