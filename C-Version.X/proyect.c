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
#define isReverse RD1
#define isEscaping RD2
#define isRotating RD3
#define isTurningRight RD4
#define isTurningLeft RD5

/* speed constants for variable speed */
#define FULL_SPEED 255
#define MED_SPEED 128
#define SEEKING_SPEED 64

/* left and right sensor remain outside the line in tracking mode */
#define LEFT_SENSOR RB4
#define RIGHT_SENSOR RB6
#define BACK_SENSOR RB5

#define ECHO RB0 //not decided yet
#define TRIG RB1
#define PROXIMITY_DISTANCE 5 // 5 => 11 cm with TMR0 prescaler = 128

#define SWEEP_TIME 10 // 5 seconds for a full sweep => 10 because tmr1 counts up to 500ms
#define ROTATING_TIME 24 // 12 seconds for a full 360 rotation, this depends on the car itself

volatile bit toggle = FALSE;

typedef unsigned char byte;
volatile byte time = 0;
volatile byte speed = 0;
volatile byte turn_speed = 0;
volatile byte ms500_to_sweep = 5; // in the beginning the car will start in the middle of the sweep
volatile byte sweeps = 0;
volatile byte ms500_to_rotate = 0;

typedef union {
    struct {
        unsigned                :4;
        unsigned left_sensor    :1; //RB4
        unsigned back_sensor    :1; //RB5
        unsigned right_sensor   :1; //RB6
        unsigned                :1;
    }; // bits
    byte portb; // bytes
} portb_state;

/* 
 * previous_states: variable that holds the previous state of the sensors.
 * I could also just do 'byte previous_states[2] = {0, 0}' and when adding a new state just do 'previous_states[1] = {PORTB}' for example,
 * and compare like so 'previous_states[1] == 0x06', the problem with this is scalability, I'd have to ground every other pin of PORTB for the comparison to work.
 */
volatile portb_state previous_states[2];

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

/* Comp functions */
inline void rotate(void);
void medSeg(void);
bit assessProximity(byte);

/* functions used only in interruptions */
inline void saveState(portb_state);
inline void steppingLine(void);
/* 
* Because it's very unlikely that the car leaves the black line while turning off LEFT_SENSOR and RIGHT_SENSOR
* at the same time, the car will inevitably start turning left or right at some point in the end, we don't want that,
* therefore I make a function that checks the previous states so I make sure the car does not turn in this scenario
*/
bit checkScenario(void);

void main(void) {
    TRISD = 0x01;
    isReverse = 0;
    isEscaping = 0;
    isRotating = 0;
    isTurningRight = 0;
    isTurningLeft = 0;
    previous_states[0].portb = 0;
    previous_states[1].portb = 0;
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
		TMR1ON = 1;
        medSeg(); // the initial 500ms when sweeping
        while(1) {
        	if(isEscaping) continue; // when escaping I don't want to do anything
            /*if(assessProximity(PROXIMITY_DISTANCE)) {                
                               
                isRotating = FALSE;
                ms500_to_rotate = 0;
                sweeps = 0;
                ms500_to_sweep = 5; //the car will make half a sweep like at the beginning
				
                // assume an RB change interruption (a sensor goes high, this is the only way the interruption occurs inside this block) occurs while inside this block, the car would go forward, therefore ignoring the previous instruction that came from steppingLine(), we don't want that
                if(isEscaping) continue; //just in case it happens after the time it takes to measure the distance, it's like a double check
                setSpeed(FULL_SPEED);
                stopTurning();
                                
                medSeg(); // this is for when the car stops chasing the car, think more about the consequences of this
                
            }*/
            else {
                /* no car detected */
                if(isRotating) continue; // when rotating don't do anything except what made isRotating = TRUE
                else {
                    setSpeed(SEEKING_SPEED);
                    turn_speed = 32; // SEEKING_SPEED/2
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
        setSpeed(FULL_SPEED);
		turn_speed = 128;
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
    isTurningRight = TRUE;
    CCPR1L = speed;
    CCPR2L = turn_speed;
    return;
}

void turnLeft(void) {
    isTurningLeft = TRUE;
    CCPR2L = speed;
    CCPR1L = turn_speed;
    return;
}

void stopTurning(void) {
    isTurningRight = FALSE;
    isTurningLeft = FALSE;
    CCPR1L = speed;
    CCPR2L = speed;
    return;
}

inline void rotate(void) {
    //left wheel going full forward + right wheel going full reverse, I guess
    return;
}

void medSeg(void) {
    TMR1 = 3036; // after setting TMR1, I wait for an interruption
    return;
}

bit assessProximity(byte distance) {
	TRIG = 1;
	__delay_us(10);
	TRIG = 0;
	while(!ECHO); // I wait for echo pin to go up
	TMR0 = 0; // I start counting, with prescaler 128, the max value it will get is 182 (4 meters)
	while(ECHO); // I wait for echo pin to go down
	return (TMR0 <= distance);
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
    return;
}

inline void saveState(portb_state state) {
    previous_states[0].portb = previous_states[1].portb;
    previous_states[1].portb = state.portb;
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

//before entering this function, it is known that all sensors are 0
bit checkScenario(void) {
    if(previous_states[0].portb == 0xA0) { // b'01010 0000', left_sensor and right_sensor = 1, everything else 0
        return (previous_states[1].left_sensor || previous_states[1].right_sensor); //note: left_sensor and right_sensor will never be 1 at the same time due to the nature of the RB change interruption, so || really is just asking if either left_sensor or right_sensor is 1
    }
    else {
        return 0;
    }
}

void interrupt ISR(void){
    if(MODE) {
        /* Comp mode interruption */
        if(RBIF) {
            isEscaping = TRUE; // the car is trying to escape, this becomes FALSE after 4 seconds have passed since the sensor were 0
            portb_state state;
            state.portb = 0; // initial clear, then I assign the bits that are 1 or 0, a simple state.portb = PORTB would work but for scalability on PORTB I'm not doing it like that, some RB pins may be used in the future
            if(LEFT_SENSOR || RIGHT_SENSOR || BACK_SENSOR) {               
                state.left_sensor = LEFT_SENSOR;
                state.right_sensor = RIGHT_SENSOR;
                state.back_sensor = BACK_SENSOR; 
                saveState(state);
                fullyDeactivateTMR1();
                stopTurning(); // in case the car was turning before getting knocked back
                steppingLine(); // here I check RB bits to take the proper measures
            }
            else { //here the car basically escaped the black line
                if(checkScenario()) { // checks for this situation: [0] left and right = 1 -> [1] left or right = 1 -> [current] left, right and back = 0
                    stopTurning();
                }
                saveState(state); // state.portb = 0
                TMR1ON = 1;
                medSeg();
                time = 0;
            }
            RBIF = 0;
            return;
        }
        
        //TMR1 interruption
        TMR1IF = 0;
        if(isEscaping) {
            /* do the escaping timer function */
            time++;
            if(time == 8) { // if timer = 8, then 4 seconds have passed
                // here the car does its thing
                time = 0;
                isReverse = FALSE; //In case the car was going in reverse
                isEscaping = FALSE; // this condition is important for the main function
            }
            medSeg(); // either I keep counting or start timing the sweeping mode
        }
        else if(isRotating){
            ms500_to_rotate++;
            if(ms500_to_rotate == ROTATING_TIME) {
                ms500_to_rotate = 0;
                isRotating = FALSE;
                stopTurning();
                ms500_to_sweep = 5; //The car will sweep like at the start
            }
            medSeg(); // either it keeps rotating or starts the sweeping
        }
        else { //else means it is sweeping
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
                }
            }
            medSeg(); // either I keep counting or I start counting the time it takes to rotate
        }
        // ideally I would put a medSeg() here and delete the ones above, but for code understanding I have to keep it like this
        return;
    }
    /* Tracking mode interruption */
    if(RIGHT_SENSOR && LEFT_SENSOR) { //it could happen...
        isTurningRight = FALSE;
        isTurningLeft = FALSE;
        stopTurning();
    }   
    // there are two scenarios here:
    else if(isTurningRight && !RIGHT_SENSOR && !LEFT_SENSOR) { // 1. the car was turning softly to the right but both sensors derailed, therefore I turn harder
        // turn harder
        turn_speed = 0;
        turnRight();
    }
    else if(isTurningLeft && !RIGHT_SENSOR && !LEFT_SENSOR) { // 2. the car was turning softly to the left but both sensors derailed, therefore I turn harder
        // turn harder
        turn_speed = 0;
        turnLeft();
    }
    else if(RIGHT_SENSOR) {
        if(!isTurningRight) turn_speed = 128; // if the car wasn't turning already, turn softly, otherwise I gotta make that sharp turn possible! (it is implied that turn_speed is 0 if isTurningRight is TRUE in this scenario)
        isTurningRight = TRUE;
        turnRight();
    }
    else if(LEFT_SENSOR) {
        if(!isTurningLeft) turn_speed = 128; // if the car wasn't turning already, turn softly, otherwise I gotta make that sharp turn possible! (it is implied that turn_speed is 0 if isTurningLeft is TRUE in this scenario)
        isTurningLeft = TRUE;
        turnLeft();
    }
    else { // RIGHT_SENSOR || LEFT_SENSOR = FALSE
        isTurningRight = FALSE;
        isTurningLeft = FALSE;
        stopTurning();
    }
    RBIF = 0;
    return;
    
}