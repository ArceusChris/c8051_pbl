#ifndef C8051F310_H
#define C8051F310_H

#include <stdint.h>

/* Minimal SDCC register map for the C8051F31x family. */
__sfr __at(0x80) P0;
__sfr __at(0x81) SP;
__sfr __at(0x82) DPL;
__sfr __at(0x83) DPH;
__sfr __at(0x87) PCON;
__sfr __at(0x88) TCON;
__sfr __at(0x89) TMOD;
__sfr __at(0x8A) TL0;
__sfr __at(0x8B) TL1;
__sfr __at(0x8C) TH0;
__sfr __at(0x8D) TH1;
__sfr __at(0x8E) CKCON;

__sfr __at(0x90) P1;
__sfr __at(0x98) SCON0;
__sfr __at(0x99) SBUF0;

__sfr __at(0xA0) P2;
__sfr __at(0xA4) P0MDOUT;
__sfr __at(0xA5) P1MDOUT;
__sfr __at(0xA6) P2MDOUT;
__sfr __at(0xA7) P3MDOUT;
__sfr __at(0xA8) IE;

__sfr __at(0xB0) P3;
__sfr __at(0xB2) OSCICN;
__sfr __at(0xBA) AMX0N;
__sfr __at(0xBB) AMX0P;
__sfr __at(0xBC) ADC0CF;
__sfr __at(0xBD) ADC0L;
__sfr __at(0xBE) ADC0H;

__sfr __at(0xD1) REF0CN;
__sfr __at(0xD4) P0SKIP;
__sfr __at(0xD5) P1SKIP;
__sfr __at(0xD6) P2SKIP;
__sfr __at(0xD9) PCA0MD;

__sfr __at(0xE1) XBR0;
__sfr __at(0xE2) XBR1;
__sfr __at(0xE4) IT01CF;
__sfr __at(0xE8) ADC0CN;

__sfr __at(0xF1) P0MDIN;
__sfr __at(0xF2) P1MDIN;
__sfr __at(0xF3) P2MDIN;
__sfr __at(0xF4) P3MDIN;

__sbit __at(0x80) P0_0;
__sbit __at(0x81) P0_1;
__sbit __at(0x82) P0_2;
__sbit __at(0x83) P0_3;
__sbit __at(0x84) P0_4;
__sbit __at(0x85) P0_5;
__sbit __at(0x86) P0_6;
__sbit __at(0x87) P0_7;

__sbit __at(0x88) IT0;
__sbit __at(0x89) IE0;
__sbit __at(0x8A) IT1;
__sbit __at(0x8B) IE1;
__sbit __at(0x8C) TR0;
__sbit __at(0x8D) TF0;
__sbit __at(0x8E) TR1;
__sbit __at(0x8F) TF1;

__sbit __at(0x90) P1_0;
__sbit __at(0x91) P1_1;
__sbit __at(0x92) P1_2;
__sbit __at(0x93) P1_3;
__sbit __at(0x94) P1_4;
__sbit __at(0x95) P1_5;
__sbit __at(0x96) P1_6;
__sbit __at(0x97) P1_7;

__sbit __at(0x98) RI0;
__sbit __at(0x99) TI0;

__sbit __at(0xA0) P2_0;
__sbit __at(0xA1) P2_1;
__sbit __at(0xA2) P2_2;
__sbit __at(0xA3) P2_3;
__sbit __at(0xA4) P2_4;
__sbit __at(0xA5) P2_5;
__sbit __at(0xA6) P2_6;
__sbit __at(0xA7) P2_7;

__sbit __at(0xA8) EX0;
__sbit __at(0xA9) ET0;
__sbit __at(0xAA) EX1;
__sbit __at(0xAB) ET1;
__sbit __at(0xAC) ES0;
__sbit __at(0xAF) EA;

__sbit __at(0xB0) P3_0;
__sbit __at(0xB1) P3_1;
__sbit __at(0xB2) P3_2;
__sbit __at(0xB3) P3_3;
__sbit __at(0xB4) P3_4;
__sbit __at(0xB5) P3_5;
__sbit __at(0xB6) P3_6;
__sbit __at(0xB7) P3_7;

#endif
