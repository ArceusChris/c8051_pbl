#ifndef BOARD_H
#define BOARD_H

#include "c8051f310.h"

#define SYSCLK_HZ 24500000UL
#define UART_BAUD 9600UL

/*
 * C8051F310EVM 使用指南（2026）硬件定义：
 * - 数码管段控：P1.7..P1.0 = a,b,c,d,e,f,g,dp，高电平点亮
 * - 数码管位控：P0.7=B，P0.6=A，BA=00/01/10/11 选择数码管 0/1/2/3
 * - 矩阵键盘：P2.0..P2.3=KO.0..KO.3，P2.4..P2.7=KI.0..KI.3
 * - LED 阵列：74HCT164，P3.3=DAT_IN，P3.4=CLK，Q=0 时 LED 亮
 * - 蜂鸣器：P3.1，高电平有效
 * - D9：P0.0，低电平有效
 * - A/D：P3.2
 * - UART：P0.4=TXD，P0.5=RXD
 * - KINT：P0.1，按下为低电平
 */
#define LED_SER_DATA P3_3
#define LED_SER_CLK P3_4
#define LED_ACTIVE_LOW 1

#define SEG_PORT P1
#define SEG_ACTIVE_LOW 0

#define DIGIT_A P0_6
#define DIGIT_B P0_7
#define DIGIT_SELECT_MASK 0xC0

#define BUZZER P3_1
#define BUZZER_ACTIVE_LOW 0

#define STATUS_LED P0_0
#define STATUS_LED_ACTIVE_LOW 1

#define TRIGGER_KEY P0_1
#define TRIGGER_KEY_ACTIVE_LOW 1

#define KEYPAD_PORT P2
#define KEYPAD_ROWS_MASK 0x0F
#define KEYPAD_COLS_MASK 0xF0

/* P3.2 corresponds to ADC0 positive mux channel 0x1A on C8051F31x. */
#define ADC0_CHANNEL 0x1A

#define UART_ENABLE 1

#endif
