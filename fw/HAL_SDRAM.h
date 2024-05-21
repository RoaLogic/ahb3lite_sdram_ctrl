////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      HAL_SDRAM.h                                               //
//		Header file for the Roa Logic SDRAM controller   	      //
//                                                                //
////////////////////////////////////////////////////////////////////
//                                                                //
//     Copyright (C) 2016-2024 ROA Logic BV                       //
//     www.roalogic.com                                           //
//                                                                //
//     This source file may be used and distributed without       //
//   restrictions, provided that this copyright statement is      //
//   not removed from the file and that any derivative work       //
//   contains the original copyright notice and the associated    //
//   disclaimer.                                                  //
//                                                                //
//     This soure file is free software; you can redistribute     //
//   it and/or modify it under the terms of the GNU General       //
//   Public License as published by the Free Software             //
//   Foundation, either version 3 of the License, or (at your     //
//   option) any later versions.                                  //
//   The current text of the License can be found at:             //
//   http://www.gnu.org/licenses/gpl.html                         //
//                                                                //
//     This source file is distributed in the hope that it will   //
//   be useful, but WITHOUT ANY WARRANTY; without even the        //
//   implied warranty of MERCHANTABILITY or FITTNESS FOR A        //
//   PARTICULAR PURPOSE. See the GNU General Public License for   //
//   more details.                                                //
//                                                                //
////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <math.h>

#ifndef HAL_SDRAM_H_
#define HAL_SDRAM_H_

#define CAS_LATENCY_CL1 1
#define CAS_LATENCY_CL2 2
#define CAS_LATENCY_CL3 3

#define BUS_TURNAROUND 0

#define DQ_SIZE_16  0
#define DQ_SIZE_32  1
#define DQ_SIZE_64  2
#define DQ_SIZE_128 3

#define IAM_LINEAR 0
#define IAM_INTERLEAVED 1

#define COLUMNS_8  0
#define COLUMNS_9  1
#define COLUMNS_10 2
#define COLUMNS_11 3

#define ROWS_11 0
#define ROWS_12 1
#define ROWS_13 2
#define ROWS_14 3

#define BURST_SIZE_4 0
#define BURST_SIZE_8 1

#define PP_MODE_NORMAL 0
#define PP_MODE_PRIVILEGED 1

#define MODE_REG_NORMAL 0
#define MODE_REG_PRECHARGE 1
#define MODE_REG_AUTO_REFRESH 2
#define MODE_REG_AUTO_SET 3

#define INIT_DONE 1

#define BURST_LENGTH_1 0
#define BURST_LENGTH_2 1
#define BURST_LENGTH_4 2
#define BURST_LENGTH_8 3
#define BURST_LENGTH_FULL_PAGE 7

#define BURST_TYPE_SEQUENTIAL 0
#define BURST_TYPE_INTERLEAVED 1

#define LATENCY_MODE_2 2
#define LATENCY_MODE_3 3

#define OPERATING_MODE_STANDARD 0

#define WRITE_BURST_MODE_BURST_LENGTH 0
#define WRITE_BURST_MODE_SINGLE_ACCESS 1

#define GET_HCLK_T_PERIOD(t, clkPeriod) (int)(ceil(t/clkPeriod))

typedef union 
{
    uint32_t asData;
    struct 
    {
        uint32_t wBufTimeout : 4;  // Writebuffer timeout
        uint32_t reserved1   : 12; // Reserved
        uint32_t dqSize      : 2;  // DQ size, 00: 16 bits, 01: 32 bits, 10: 64bits, 11: 128 bits
        uint32_t ap          : 1;  // Auto-precharge on read/write
        uint32_t iam         : 1;  // 0: linear bank addressing, 1: interleaved bank addressing
        uint32_t numCols     : 2;  // Number of columns 00: 8 columns, 01: 9 columns, 10: 10 columns, 11: 11 columns
        uint32_t numRows     : 2;  // Number of rows 00: 11 rows, 01: 12 rows, 10: 13 rows, 11: 14 rows
        uint32_t burstSize   : 1;  // Burst size, 0: 4, 1: 8
        uint32_t reserved2   : 2;  // Reserved
        uint32_t pp          : 1;  // 0: normal and privileged access to CSR, 1: privileged only
        uint32_t mode        : 2;  // SDRAM mode, 00: normal, 01: precharge command, 10: auto-refresh, 11: set mode 
        uint32_t initDone    : 1;  // Initial/Startup delay done (read only)
        uint32_t enable      : 1;  // SDRAM enabled
    }asElements;
}tSDRAMControlRegister;

typedef union 
{
    uint32_t asData;
    struct 
    {
        uint32_t RFC_cnt : 4; // Bit 0 to 3     REF to REF period
        uint32_t RC_cnt  : 4; // Bit 4 to 7     Active to Active perion same bank
        uint32_t RAS_cnt : 4; // Bit 8 to 11    Command period, ACT to PRE
        uint32_t RCD_cnt : 3; // Bit 12 to 14   Active to read/write period
        uint32_t RP_cnt  : 3; // Bit 15 to 17   Precharge period
        uint32_t WR_cnt  : 3; // Bit 18 to 20   Write recovery period
        uint32_t RRD_cnt : 3; // Bit 21 to 23   Active to Active period different banks
        uint32_t cl      : 2; // Bit 24 to 25   CAS latency, 00 = reserverd, 01:CL1, 10:CL2, 11:CL3
        uint32_t unused1 : 1; // Bit 26         Reserved
        uint32_t btac    : 1; // Bit 27         Bus turnaround cycle, add an additional cycle between RD to WR commands
        uint32_t RDV_cnt : 3; // Bit 28 to 30   Read command to data valid delay
        uint32_t unused2 : 1; // Bit 31         Reserved
    }asElements;
}tSDRAMTimeConfig;

typedef union 
{
    uint16_t asData;
    struct 
    {
        uint16_t burstLength    : 3; // Defines the burst length, 0b000 = 1, 0b001 = 2, 0b010 = 4, 0b011 = 8, 0b111 is full page
                                     // All other values are reserved
        uint16_t burstType      : 1; // Defines the burst type, 0 = Sequential, 1 = Interleaved
        uint16_t latency        : 3; // CAS latency, only 0b010 (2) and 0b011 (3) are supported
        uint16_t operatingMode  : 2; // Operating mode, 0b00 = standard operation, all other are reserved
        uint16_t writeBurstMode : 1; // writeBurstMode, 0 = Programmed burst length, 1 = single location access
        uint16_t reserved       : 5; // Reserved, should be set to 0
    }asElements;
}tSDRAMModeRegister;

typedef struct
{
    volatile tSDRAMControlRegister control;
    volatile tSDRAMTimeConfig timeConfig;
    volatile uint16_t timeRef;
}HAL_SDRAM_CONTROLLER;

void HAL_SDRAM_initialize(HAL_SDRAM_CONTROLLER* sdramBase, 
                     uint32_t* sdramDataAddress, 
                     uint16_t tREFValue, 
                     tSDRAMTimeConfig timeConfig,
                     tSDRAMControlRegister controlRegister,
                     tSDRAMModeRegister modeRegister);

#endif /* HAL_SDRAM_H_ */