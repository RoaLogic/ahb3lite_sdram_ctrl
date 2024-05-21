////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      HAL_SDRAM.c                                               //
//		Source file or the Roa Logic SDRAM controller   	      //
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

#include "HAL_SDRAM.h"
#define NUM_DATA_READS_AUTO_REFRESH 8

/**
 * @brief This function initializes the SDRAM controller
 * @details Within this function the SDRAM controller is initialized
 * 
 * It runs through the full configuration and walks to all steps. In the beginning
 * it waits until the initDone flag of the control register is set, which takes 
 * approx 100us. This function is blocking at that moment.
 * 
 * @attention The configuration must be passed into this function, it is specific
 * for each SDRAM.
 * 
 * @param sdramBase         Pointer to the base address of the SDRAM controller
 * @param sdramDataAddress  Pointer to the base address of the SDRAM data
 * @param tREFValue         The tREF value that has to be set
 * @param timeConfig        The time configuration according to the used SDRAM
 * @param controlRegister   The control settings used for running the SDRAM
 * @param modeRegister      The mode register setting for the SDRAM
 */
void HAL_SDRAM_initialize(HAL_SDRAM_CONTROLLER* sdramBase, 
                     uint32_t* sdramDataAddress, 
                     uint16_t tREFValue, 
                     tSDRAMTimeConfig timeConfig,
                     tSDRAMControlRegister controlRegister,
                     tSDRAMModeRegister modeRegister)
{
    tSDRAMControlRegister controlInfo;
    uint32_t dummyData;
    uint32_t* msrValue = (sdramDataAddress + modeRegister.asData); // Setup the value mode register value
    uint16_t dummyWord;

    // Initializing the SDRAM
    // First write SDRAM time (over APB bus)
    sdramBase->timeConfig = timeConfig;

    // Write SDRAM T_REF
    sdramBase->timeRef = tREFValue;

    // Wait init done, check SDRAM_CTRL register bit 30
    do
    {
        controlInfo = sdramBase->control;
    } while (!controlInfo.asElements.initDone);
    
    // Send precharge command, at this point also enable the device
    controlInfo.asElements.mode = MODE_REG_PRECHARGE;
    controlInfo.asElements.initDone = 0; // Set the read flag back to 0
    controlInfo.asElements.enable = 1;
    sdramBase->control = controlInfo;

    // Read single data element from SDRAM
    dummyData = *(sdramDataAddress);

    // Set auto refresh command
    controlInfo.asElements.mode = MODE_REG_AUTO_REFRESH;
    sdramBase->control = controlInfo;

    // Perform 8 auto refreshes, done by reading 8 times from SDRAM
    for(uint8_t i = 0; i < NUM_DATA_READS_AUTO_REFRESH; i++)
    {
        dummyData = *(sdramDataAddress);
    }

    // Set controller Command mode register, we don't actually write the data in this moment.
    // With this command the controller will go into programming mode, the value itself is then written by 
    // reading with the value of the control register
    controlInfo.asElements.mode = MODE_REG_AUTO_SET;
    sdramBase->control = controlInfo;

    //Write SDRAM Mode Register (which is actually a read)
    dummyWord = *(msrValue);

    //Set Controller Normal Mode
    sdramBase->control = controlRegister;
}