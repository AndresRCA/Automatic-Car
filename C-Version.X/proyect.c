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

typedef unsigned char byte;
volatile bit isReverse = FALSE;
volatile byte time = 0;
volatile byte speed = 0;
volatile byte turn_speed = 0;

/* Configuration functions */
void PWM_INIT(void);
void INT_INIT(void);
void TMR1_INIT(void);

/* Main functions */
void setSpeed(byte); // accepts FULL_SPEED, MED_SPEED and SEEKING_SPEED
void turnRight(void);
void turnLeft(void);
void stopTurning(void);
void medSeg(void);

/* functions used only in interruptions */
void steppingLine(void);

void main(void) {
    PORTB;
    RBIF = 0; // just in case it's 1
    PWM_INIT();
    INT_INIT();
    if(MODE) {
        TMR1_INIT();
    }
    TRIG = 0; // in case it's on
    
    if(MODE) {
        /* Comp mode */
        while(1) {
        
        }
    }
    else {
        /* Tracking mode */
        setSpeed(MED_SPEED);
        while(1) {

        }
    }
    return;
}

void PWM_INIT(void) {
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

void INT_INIT(void) {
    GIE = 1;
    RBIE = 1;
    if(MODE) {
        PEIE = 1;
        TMR1IE = 1;
    }
    return;
}

void TMR1_INIT(void) {
    T1CKPS0 = 1; // TMR1 prescaler = 1:8
    T1CKPS1 = 1;
    TMR1 = 0;
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
    return;
}

void turnLeft(void) {
    CCPR1L = turn_speed;
    return;
}

void stopTurning(void) {
    CCPR1L = speed;
    CCPR2L = speed;
    return;
}

void medSeg(void) {
    TMR1 = 56331; // after setting TMR1, I wait for an interruption
    return;
}

void fullyDeactivateTMR1(void) {
    TMR1ON = 0;
    TMR1 = 0;
    time = 0;
    return;
}

/* This function is subject of discussion */
void steppingLine(void) {
    switch(1) {
        case FRONT_SENSOR & LEFT_SENSOR:
            isReverse = TRUE;
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnRight();
            __delay_ms(500);
            stopTurning();
            while(FRONT_SENSOR);
            return;
        
        case FRONT_SENSOR & RIGHT_SENSOR:
            isReverse = TRUE;
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnLeft();
            __delay_ms(500);
            stopTurning();
            while(FRONT_SENSOR);
            return;

        case BACK_SENSOR & LEFT_SENSOR:
            setSpeed(FULL_SPEED);
            //turn_speed = ??
            turnRight();
            __delay_ms(500);
            stopTurning();
            while(BACK_SENSOR);
            return;

        case BACK_SENSOR & RIGHT_SENSOR:
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

        case default:
            //I guess I'll just die
            return;
    }
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