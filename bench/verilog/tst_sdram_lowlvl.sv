////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      SDRAM Controller Testbench                                //
//      Low Level routines to peek/poke SDRAM memory contents     //
//                                                                //
////////////////////////////////////////////////////////////////////
//                                                                //
//     Copyright (C) 2023 ROA Logic BV                            //
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


  task sdram_clear;
    foreach (sdram_memory.Bank0[i])
    begin
        sdram_memory.Bank0[i]={SDRAM_DQ_SIZE{1'bx}};
        sdram_memory.Bank1[i]={SDRAM_DQ_SIZE{1'bx}};
        sdram_memory.Bank2[i]={SDRAM_DQ_SIZE{1'bx}};
        sdram_memory.Bank3[i]={SDRAM_DQ_SIZE{1'bx}};
    end
  endtask : sdram_clear


  task map_haddr_to_sdram_address;
    input  [HADDR_SIZE              -1:0] haddr;
    output [                         1:0] bank;
    output [SDRAM_COLS + SDRAM_ROWS -1:0] sdram_address;

    logic [HADDR_SIZE -1:0] adr;
    logic [SDRAM_ROWS -1:0] row;
    logic [SDRAM_COLS -1:0] column;

    //adjust for DSIZE
    adr = haddr >> SDRAM_DSIZE >> 1;

    //extract column
    column = adr[0 +: SDRAM_COLS];

    //extract row
    adr = adr >> SDRAM_COLS;
    row = SDRAM_IAM ? adr[2 +: SDRAM_ADDR_SIZE] : adr[0 +: SDRAM_ADDR_SIZE];

    //extract bank
    bank = SDRAM_IAM ? adr[1:0] : adr[SDRAM_ROWS +: 2];

    //sdram address
    sdram_address = {row, column};
  endtask : map_haddr_to_sdram_address


  function automatic [SDRAM_DQ_SIZE-1:0] peek_sdram;
    //peek inside SDRAM and return value at address 'adr'
    input [HADDR_SIZE-1:0] haddr;

    logic [1:0] bank;
    logic [SDRAM_COLS + SDRAM_ROWS -1:0] sdram_address;

    //map address
    map_haddr_to_sdram_address(haddr, bank, sdram_address);

    //get memory contents
    case (bank)
      2'b00: peek_sdram = sdram_memory.Bank0[sdram_address];
      2'b01: peek_sdram = sdram_memory.Bank1[sdram_address];
      2'b10: peek_sdram = sdram_memory.Bank2[sdram_address];
      2'b11: peek_sdram = sdram_memory.Bank3[sdram_address];
    endcase
  endfunction : peek_sdram
