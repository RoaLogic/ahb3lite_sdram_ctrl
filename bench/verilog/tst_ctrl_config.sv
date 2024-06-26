////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      SDRAM Controller Testbench                                //
//      Controller Configuation routines                          //
//                                                                //
////////////////////////////////////////////////////////////////////
//                                                                //
//     Copyright (C) 2023-2024 ROA Logic BV                       //
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


  // -- SDRAM Controller Configuration routines
  //
  task wait_for_init_done();
    //wait until initial SDRAM delay (100us or 200us) is done
    logic [31:0] rdq;
    logic        init_done;

    $display("Wait for SDRAM initial delay");
    do
    begin
        apb_bfm.read(SDRAM_CTRL, rdq);
        init_done = rdq[30];
    end
    while (!init_done);
  endtask : wait_for_init_done


  function [3:0] get_t_period(input real t, input real clk_period);
    real cnt;

    //get cnt and round to highest value
    cnt = $ceil(t/clk_period);

    //rtoi truncates, but 'cnt' should not have any fraction anyways
    return $rtoi(cnt);
  endfunction : get_t_period


  /*
   * Set Time CSR
   */
  task set_time_csr(
    input real  clk_period,
    input int   refreshes,
    input real  refresh_period,
    input       btac,
    input [1:0] cl,
    input real  tRP,
    input real  tRCD,
    input real  tRC
  );
    //Write timing parameters into timing CSR
    logic [15:0] tREF_cnt;
    logic [ 2:0] tRDV_cnt;
    logic [ 2:0] tRRD_cnt;
    logic [ 2:0] tWR_cnt;
    logic [ 2:0] tRP_cnt;
    logic [ 2:0] tRCD_cnt;
    logic [ 3:0] tRAS_cnt;
    logic [ 3:0] tRC_cnt;
    logic [ 3:0] tRFC_cnt;
    logic [31:0] regval;

    //get clk-period counts for each timing parameter
    tREF_cnt = refreshes / refresh_period / clk_period;
    tRRD_cnt = get_t_period(tRRD, clk_period);
    tWR_cnt  = get_t_period(tWR,  clk_period);
    tRAS_cnt = get_t_period(tRAS, clk_period);
    tRP_cnt  = get_t_period(tRP,  clk_period);
    tRCD_cnt = get_t_period(tRCD, clk_period);
    tRC_cnt  = get_t_period(tRC,  clk_period);
    tRFC_cnt = get_t_period(tRFC, clk_period);

    //Data valid at controller: PHY-delay (output + input) + PCB delay
    tRDV_cnt = 0 + 2 + get_t_period(1, clk_period);

    //register value
    regval = {2'h0, tRDV_cnt, btac, 1'b0, cl, tRRD_cnt, tWR_cnt, tRP_cnt, tRCD_cnt, tRAS_cnt, tRC_cnt, tRFC_cnt};

    //write regval to timing CSR
    $display("Writing timing CSR (0x%8h)", regval);
    $display("  - tRFC=%0d (0x%0h)", tRFC_cnt, tRFC_cnt);
    $display("  - tRC =%0d (0x%0h)", tRC_cnt,  tRC_cnt);
    $display("  - tRAS=%0d (0x%0h)", tRAS_cnt, tRAS_cnt);
    $display("  - tRCD=%0d (0x%0h)", tRCD_cnt, tRCD_cnt);
    $display("  - tRP =%0d (0x%0h)", tRP_cnt,  tRP_cnt);
    $display("  - tWR =%0d (0x%0h)", tWR_cnt,  tWR_cnt);
    $display("  - tRRD=%0d (0x%0h)", tRRD_cnt, tRRD_cnt);
    $display("  - cl  =%0d (%2b)", cl, cl);
    $display("  - btac=%0d      ", btac);
    $display("  - tRDV=%0d (0x%0h)", tRDV_cnt, tRDV_cnt);

    apb_bfm.write(SDRAM_TIME, regval, 4'hf);
    //write tREF
    $display("Writing tREF CSR");
    apb_bfm.write(SDRAM_TREF, tREF_cnt, 4'h3);
  endtask : set_time_csr


  /*
   * Initialise SDRAM Controller
   */
  task initialise_sdram_ctrl();
    logic [HDATA_SIZE-1:0] rbuf[];
    logic [          31:0] regval;

    //initalise SDRAM controller
    $display ("Initialising SDRAM controller");

    $display ("  Precharge ALL"); 
    //set Controller Precharge Command
    @(posedge PCLK);
    apb_bfm.write(SDRAM_CTRL, 32'h9000_0000, 4'hf);

    //Precharge ALL; read from SDRAM
    ahb_if[AHB_CTRL_PORT].ahb_bfm.read(0,   //any address in range
                                       rbuf,
                                       HDATA_SIZE == 32 ? HSIZE_WORD : HSIZE_DWORD,
                                       HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();


    $display ("  Auto Refreshes");
    //Set Controller Auto Refresh Command
    @(posedge PCLK);
    apb_bfm.write(SDRAM_CTRL, 32'ha000_0000, 4'hf);

    //Perform 8 auto refreshes; read from SDRAM 8x
    for (int n=0; n < 8; n++)
      ahb_if[AHB_CTRL_PORT].ahb_bfm.read(0, //any address in range
                                         rbuf,
                                         HDATA_SIZE == 32 ? HSIZE_WORD : HSIZE_DWORD,
                                         HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();


    $display ("  Write Mode Register");
    //Set Controller Command Mode Register
    @(posedge PCLK);
    apb_bfm.write(SDRAM_CTRL, 32'hb000_0000, 4'hf);

    //Write SDRAM Mode Register, address pins = settings
    // WriteBurstMode, OpsMode, CL, Sequential, BL=4
    ahb_if[AHB_CTRL_PORT].ahb_bfm.read({1'b0, 2'b00, 3'(SDRAM_CL), 1'b0, 3'($clog2(SDRAM_BURST_SIZE))},
                                       rbuf,
                                       HSIZE_BYTE, //prevent HADDR from being misaligned with HSIZE
                                       HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();


    //Set Controller Normal Mode and write control values
    regval = 32'h8000_0000                      |
             ($clog2(SDRAM_BURST_SIZE/4) << 24) |
             ((SDRAM_ROWS-11)            << 22) |
             ((SDRAM_COLS-8)             << 20) |
             ( SDRAM_IAM                 << 19) |
             ( SDRAM_AP                  << 18) |
             ( SDRAM_DSIZE               << 16) |
             ($clog2(WRITEBUFFER_TIMEOUT)     ) ;      //writebuffer timeout = 2^n

    $display("Writing Control CSR (0x%8h)", regval);
    $display("  - burst_size=%0d (0x%0h)", $clog2(SDRAM_BURST_SIZE/2) , $clog2(SDRAM_BURST_SIZE/2));
    $display("  - rows      =%0d (0x%0h)", SDRAM_ROWS , SDRAM_ROWS-11);
    $display("  - columns   =%0d (0x%0h)", SDRAM_COLS , SDRAM_COLS- 8);
    $display("  - iam       =%0d (0x%0h)", SDRAM_IAM  , SDRAM_IAM);
    $display("  - ap        =%0d (0x%0h)", SDRAM_AP   , SDRAM_AP);
    $display("  - dsize     =%0d (0x%0h)", 16 << SDRAM_DSIZE, SDRAM_DSIZE);
    $display("  - timeout   =%0d (0x%0h)", WRITEBUFFER_TIMEOUT, $clog2(WRITEBUFFER_TIMEOUT));

    @(posedge PCLK);
    apb_bfm.write(SDRAM_CTRL, regval, 4'hf);

    $display("Initialisation complete");
  endtask : initialise_sdram_ctrl
