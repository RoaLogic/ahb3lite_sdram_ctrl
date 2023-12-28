////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      SDRAM Controller Testbench                                //
//      Various tests                                             //
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


  // -- SDRAM Access routines
  //
  task automatic write_sdram_seq(
    input [HSIZE_SIZE-1:0 ] size,
    input [HBURST_SIZE-1:0] burst,
    input int               runs
  );
    //filling sdram with sequential numbers
    //start at address 0 and fill memory
    int                                 run = 0;
    int                                 burstsize;
    logic        [SDRAM_ADDR_SIZE -1:0] adr;
    static logic [HDATA_SIZE-1:0]       wbuf[];

    //create write buffer
    case (burst)
      HBURST_SINGLE: burstsize = 1;
      HBURST_INCR  : burstsize = 128;
      HBURST_WRAP4 : burstsize = 4;
      HBURST_INCR4 : burstsize = 4;
      HBURST_WRAP8 : burstsize = 8;
      HBURST_INCR8 : burstsize = 8;
      HBURST_WRAP16: burstsize = 16;
      HBURST_INCR16: burstsize = 16;
    endcase
    wbuf = new[burstsize];


    //start at address 0
    adr = 0;

    while (run < runs)
    begin
        //fill write buffer
        foreach (wbuf[i])
          for (int b=0; b < HDATA_SIZE/8; b++)
            wbuf[i][b*8 +: 8] = run*(burstsize * (1 << size) /*HDATA_SIZE/8*/) +i*(1 << size) +b;

        //AHB write
        ahb_if[AHB_CTRL_PORT].ahb_bfm.write(adr, wbuf, size, burst);

        //next address
        adr = adr + (burstsize << size);

        //next run                
        run++;
    end

    //idle AHB bus
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

    wait fork;
  endtask : write_sdram_seq


  task automatic read_sdram_seq(
    input [HSIZE_SIZE-1:0 ] size,
    input [HBURST_SIZE-1:0] burst,
    input int               runs
  );
    //Reading sdram sequentially
    //start at address 0
    int                                 run = 0;
    int                                 burstsize;
    logic        [SDRAM_ADDR_SIZE -1:0] adr;
    static logic [HDATA_SIZE-1:0]       rbuf[];

    //create read buffer
    case (burst)
      HBURST_SINGLE: burstsize = 1;
      HBURST_INCR  : burstsize = 128;
      HBURST_WRAP4 : burstsize = 4;
      HBURST_INCR4 : burstsize = 4;
      HBURST_WRAP8 : burstsize = 8;
      HBURST_INCR8 : burstsize = 8;
      HBURST_WRAP16: burstsize = 16;
      HBURST_INCR16: burstsize = 16;
    endcase
    rbuf = new[burstsize];


    //start at address 0
    adr = 0;

    while (run < runs)
    begin
        //AHB read
        ahb_if[AHB_CTRL_PORT].ahb_bfm.read(adr, rbuf, size, burst);

        //next address
        adr = adr + (burstsize << size);

        //next run                
        run++;
    end

    //idle AHB bus
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

    wait fork;
  endtask : read_sdram_seq
