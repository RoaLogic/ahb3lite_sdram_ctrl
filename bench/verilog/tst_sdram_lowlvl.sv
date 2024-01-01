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


//Convert bus-address to SDRAM bank, row, column
function automatic [2 + SDRAM_ROWS + SDRAM_COLS -1:0] map_haddr_to_sdram_address (
  input  [HADDR_SIZE-1:0] haddr
);

  logic [HADDR_SIZE -1:0] adr;
  logic [            1:0] bank;
  logic [SDRAM_ROWS -1:0] row;
  logic [SDRAM_COLS -1:0] column;

//$display("haddr=%h", haddr);

  //adjust for DSIZE
  adr = haddr >> SDRAM_DSIZE >> 1;
//$display("adr=%h", adr);

  //extract column
  column = adr[0 +: SDRAM_COLS];
//$display("Column=%h", column);

  //extract row
  adr = adr >> SDRAM_COLS;
  row = SDRAM_IAM ? adr[2 +: SDRAM_ADDR_SIZE] : adr[0 +: SDRAM_ADDR_SIZE];
//$display("row=%h", row);

  //extract bank
  bank = SDRAM_IAM ? adr[1:0] : adr[SDRAM_ROWS +: 2];
//$display("bank=%d", bank);

  //sdram address
  map_haddr_to_sdram_address = {bank, row, column};
endfunction : map_haddr_to_sdram_address


//Peek inside SDRAM and return value at address 'haddr'
function automatic [SDRAM_DQ_SIZE-1:0] peek_sdram (
  input  [HADDR_SIZE   -1:0] haddr
);
    logic [1:0] bank;
    logic [SDRAM_COLS + SDRAM_ROWS -1:0] sdram_address;

    //map address
    {bank, sdram_address} = map_haddr_to_sdram_address(haddr);
//    $display("haddr=%h, bank=%d, sdram_address=%h", haddr, bank, sdram_address);

    //get memory contents
    case (bank)
      2'b00: peek_sdram = sdram_memory.Bank0[sdram_address];
      2'b01: peek_sdram = sdram_memory.Bank1[sdram_address];
      2'b10: peek_sdram = sdram_memory.Bank2[sdram_address];
      2'b11: peek_sdram = sdram_memory.Bank3[sdram_address];
    endcase
endfunction : peek_sdram
