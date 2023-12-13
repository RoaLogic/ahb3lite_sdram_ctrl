////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      SDRAM Controller Testbench                                //
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


module testbench_top
import ahb3lite_pkg::*;
;

  //Hardware parameters
  parameter int  HCLK_PERIOD      = 10; //10ns = 100MHz
  parameter int  PCLK_PERIOD      = 40; //40ns =  25MHz

  parameter int  INIT_DLY_CNT     = 100e-6/(PCLK_PERIOD * 1e-9);  //100us in PCLK cycles
  parameter int  WRITEBUFFER_SIZE = 8;

  parameter int  AHB_PORTS        = 1;
  parameter int  AHB_CTRL_PORT    = 0;
  parameter int  HADDR_SIZE       = 20;
  parameter int  HDATA_SIZE       = 32;

  parameter int  PADDR_SIZE       =  4;
  parameter int  PDATA_SIZE       = 32;
  
  parameter int  SDRAM_DQ_SIZE    = 32;
  parameter int  SDRAM_ADDR_SIZE  = 11;
  parameter int  SDRAM_AP         = 1;
  parameter int  SDRAM_BURST_SIZE = 8;  //1,2,4,8

  /* PCB trace
   */
  parameter real PROPAGATION_DELAY = 15.0; //15cm/ns
  parameter real TRACE_LENGTH      = 6.0;  //3cm
  parameter real TRACE_DELAY       = TRACE_LENGTH / PROPAGATION_DELAY; //15cm/ns


  /* Software parameters
   */
  //ISSI IS42S16320F-7

  //IS42VM32200-S60
  //Control
  parameter logic SDRAM_BTAC        = 0;
  parameter int   SDRAM_CL          = 2;
  parameter logic SDRAM_PP          = 0;
  parameter int   SDRAM_ROWS        = SDRAM_ADDR_SIZE;
  parameter int   SDRAM_COLS        = 8;
  parameter logic SDRAM_IAM         = 0;
  parameter int   SDRAM_DSIZE       = SDRAM_DQ_SIZE;
  parameter int   WBUF_TIMEOUT      = 0;

  //timing parameters (in ns)
  parameter real REFRESHES      = 4096;
  parameter real REFRESH_PERIOD = 64e-3; // refreshes every 64msecs
  parameter int  tDAL           = 4;     // tDAL in cycles
  parameter real tRAS           = 42.0;
  parameter real tRP            = 18.0;
  parameter real tRCD           = 18.0;
  parameter real tRC            = 60.0;
  parameter real tRFC           = 80.0;

  //-------------------------------------------------------
  //
  // Variables
  //

  logic                        PRESETn;
  logic                        PCLK;
  logic                        PSEL;
  logic                        PENABLE;
  logic [PADDR_SIZE      -1:0] PADDR;
  logic                        PWRITE;
  logic [PDATA_SIZE/8    -1:0] PSTRB;
  logic [                 2:0] PPROT;
  logic [PDATA_SIZE      -1:0] PWDATA;
  logic [PDATA_SIZE      -1:0] PRDATA;
  logic                        PREADY;
  logic                        PSLVERR;

  logic                        HRESETn;
  logic                        HCLK;
  logic                        HSEL      [AHB_PORTS];
  logic [HTRANS_SIZE     -1:0] HTRANS    [AHB_PORTS];
  logic [HSIZE_SIZE      -1:0] HSIZE     [AHB_PORTS];
  logic [HBURST_SIZE     -1:0] HBURST    [AHB_PORTS];
  logic [HPROT_SIZE      -1:0] HPROT     [AHB_PORTS];
  logic                        HWRITE    [AHB_PORTS];
  logic                        HMASTLOCK [AHB_PORTS];
  logic [HADDR_SIZE      -1:0] HADDR     [AHB_PORTS];
  logic [HDATA_SIZE      -1:0] HWDATA    [AHB_PORTS];
  logic [HDATA_SIZE      -1:0] HRDATA    [AHB_PORTS];
  logic                        HREADYOUT [AHB_PORTS];
  logic                        HREADY    [AHB_PORTS];
  logic                        HRESP     [AHB_PORTS];

  logic                        sdram_rdclk;
  logic                        sdram_clk,   sdram_clk_pcb;
  logic                        sdram_cke,   sdram_cke_pcb;
  logic                        sdram_cs_n,  sdram_cs_n_pcb;
  logic                        sdram_ras_n, sdram_ras_n_pcb;
  logic                        sdram_cas_n, sdram_cas_n_pcb;
  logic                        sdram_we_n,  sdram_we_n_pcb;
  logic [SDRAM_ADDR_SIZE -1:0] sdram_addr,  sdram_addr_pcb;
  logic [                 1:0] sdram_ba,    sdram_ba_pcb;
  wire  [SDRAM_DQ_SIZE   -1:0] sdram_dq;
  logic [SDRAM_DQ_SIZE   -1:0]              sdram_dq_pcb;
  logic [SDRAM_DQ_SIZE   -1:0] sdram_dqi,   
                               sdram_dqo;
  logic                        sdram_dqoe;
  logic [SDRAM_DQ_SIZE/8 -1:0] sdram_dm,    sdram_dm_pcb;


  localparam int SDRAM_CTRL = 0;
  localparam int SDRAM_TIME = 4;
  localparam int SDRAM_TREF = 8;
    
  //-------------------------------------------------------
  //
  // Tasks
  //

  task welcome_msg();
    $display("\n\n");
    $display ("------------------------------------------------------------");
    $display (" ,------.                    ,--.                ,--.       ");
    $display (" |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---. ");
    $display (" |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--' ");
    $display (" |  |\\  \\ ' '-' '\\ '-'  |    |  '--.' '-' ' '-' ||  |\\ `--. ");
    $display (" `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---' ");
    $display ("- SDRAM Controller Testbench ------------  `---'  ----------");
    $display ("-------------------------------------------------------------");
    $display ("\n");
  endtask


  task goodbye_msg();
    $display("\n\n");
    $display ("------------------------------------------------------------");
    $display (" ,------.                    ,--.                ,--.       ");
    $display (" |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---. ");
    $display (" |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--' ");
    $display (" |  |\\  \\ ' '-' '\\ '-'  |    |  '--.' '-' ' '-' ||  |\\ `--. ");
    $display (" `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---' ");
    $display ("- SDRAM Controller Testbench ------------  `---'  ----------");
    $display ("-------------------------------------------------------------");
    $display ("  Done");
//    $display ("  Status = %s", checker_inst.ugly ? "FAILED" : "PASSED");
    $display ("-------------------------------------------------------------");
  endtask

  
  task ahb_reset();
    HRESETn <= 1'b0;
    @(posedge HCLK);
    HRESETn <= 1'b1;
    @(posedge HCLK);
  endtask


  task apb_reset();
    PRESETn <= 1'b0;
    @(posedge PCLK);
    PRESETn <= 1'b1;
    @(posedge PCLK);
  endtask


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
    logic [ 3:0] tDAL_cnt;
    logic [ 3:0] tRAS_cnt;
    logic [ 3:0] tRP_cnt;
    logic [ 3:0] tRCD_cnt;
    logic [ 3:0] tRC_cnt;
    logic [ 3:0] tRDV_cnt;
    logic [31:0] regval;

    //get clk-period counts for each timing parameter
    tREF_cnt = refreshes / refresh_period / clk_period;
    tRAS_cnt = get_t_period(tRAS, clk_period);
    tRP_cnt  = get_t_period(tRP,  clk_period);
    tRCD_cnt = get_t_period(tRCD, clk_period);
    tRC_cnt  = get_t_period(tRFC > tRC ? tRFC : tRC,  clk_period);

    //Data valid at controller: PHY-delay (output + input) + PCB delay
    tRDV_cnt = 1+2 + get_t_period(1, clk_period);

    //register value
    regval = {5'h0, tRDV_cnt, btac, 1'b0, cl, tDAL, tRAS_cnt, tRP_cnt, tRCD_cnt, tRC_cnt};

    //write regval to timing CSR
    $display("Writing timing CSR");
    apb_bfm.write(SDRAM_TIME, regval, 4'hf);
    //write tREF
    $display("Writing tREF CSR");
    apb_bfm.write(SDRAM_TREF, tREF_cnt, 4'h3);
  endtask : set_time_csr


  task initialise_sdram_ctrl();
    logic [HDATA_SIZE-1:0] rbuf[];

    //initalise SDRAM controller
    $display ("Initialising SDRAM controller");

    $display ("  Precharge ALL"); 
    //set Precharge Command
    apb_bfm.write(SDRAM_CTRL, 32'h9000_0000, 4'hf);

    //Precharge ALL
    //read from SDRAM with A10=1
    ahb_if[AHB_CTRL_PORT].ahb_bfm.read(0,   //any address in range
                                       rbuf,
                                       HDATA_SIZE == 32 ? HSIZE_WORD : HSIZE_DWORD,
                                       HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();
//    wait fork;


    $display ("  Auto Refreshes");
    //Set Auto Refresh Command
    apb_bfm.write(SDRAM_CTRL, 32'ha000_0000, 4'hf);

    //Perform 8 auto refreshes
    //read from SDRAM 8x
    for (int n=0; n < 8; n++)
      ahb_if[AHB_CTRL_PORT].ahb_bfm.read(0, //any address in range
                                         rbuf,
                                         HDATA_SIZE == 32 ? HSIZE_WORD : HSIZE_DWORD,
                                         HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();


    $display ("  Write Mode Register");
    //Set Command Mode Register
    apb_bfm.write(SDRAM_CTRL, 32'hb000_0000, 4'hf);

    //Write Mode Register, address pins = settings
    // WriteBustMode, OpsMode, CL, Sequential, BL=4
    ahb_if[AHB_CTRL_PORT].ahb_bfm.read({1'b0, 2'b00, 3'(SDRAM_CL), 1'b0, 3'($clog2(SDRAM_BURST_SIZE))},
                                       rbuf,
                                       HDATA_SIZE == 32 ? HSIZE_WORD : HSIZE_DWORD,
                                       HBURST_SINGLE);
    ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();


    //Set Normal Mode
    apb_bfm.write(SDRAM_CTRL,
                  32'h8000_0000                    |
                  ((SDRAM_ROWS-11)          << 24) |
                  ($clog2(SDRAM_BURST_SIZE) << 22) |
                  ((SDRAM_COLS- 8)          << 20) |
                  ( SDRAM_IAM               << 19) |
                  ( SDRAM_AP                << 18) |
                  ( SDRAM_DSIZE             << 16) |
                  128,                      //writebuffer timeout
                  4'hf);


    $display("Initialisation complete");
  endtask : initialise_sdram_ctrl


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
    //filling sdram with sequential numbers
    //start at address 0 and fill memory
    int                                 run = 0;
    int                                 burstsize;
    logic        [SDRAM_ADDR_SIZE -1:0] adr;
    static logic [HDATA_SIZE-1:0]       rbuf[];

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


  //-------------------------------------------------------
  //
  // Module Body
  //

  //generate clocks
  always #(PCLK_PERIOD/2.0) PCLK = ~PCLK;
  always #(HCLK_PERIOD/2.0) HCLK = ~HCLK;

  //phase shifted readclock (1.25 clock cycles delay)
  always_comb sdram_rdclk <= #(HCLK_PERIOD/4.0) HCLK;


  //Instantiate BFMs
  apb4_master_bfm #(
    .PADDR_SIZE ( PADDR_SIZE ),
    .PDATA_SIZE ( PDATA_SIZE ))
  apb_bfm (
    .PRESETn    ( PRESETn    ),
    .PCLK       ( PCLK       ),
    .PSEL       ( PSEL       ),
    .PENABLE    ( PENABLE    ),
    .PWRITE     ( PWRITE     ),
    .PSTRB      ( PSTRB      ),
    .PADDR      ( PADDR      ),
    .PPROT      ( PPROT      ),
    .PWDATA     ( PWDATA     ),
    .PRDATA     ( PRDATA     ),
    .PREADY     ( PREADY     ),
    .PSLVERR    ( PSLVERR    ));


generate
  genvar ahbport;

  for (ahbport=0; ahbport < AHB_PORTS; ahbport++)
  begin: ahb_if
      ahb3lite_master_bfm #(
        .HADDR_SIZE ( HADDR_SIZE         ),
        .HDATA_SIZE ( HDATA_SIZE         ))
      ahb_bfm (
        .HRESETn    ( HRESETn            ),
        .HCLK       ( HCLK               ),
        .HSEL       ( HSEL     [ahbport] ),
        .HTRANS     ( HTRANS   [ahbport] ),
        .HBURST     ( HBURST   [ahbport] ),
        .HSIZE      ( HSIZE    [ahbport] ),
        .HWRITE     ( HWRITE   [ahbport] ),
        .HPROT      ( HPROT    [ahbport] ),
        .HMASTLOCK  ( HMASTLOCK[ahbport] ),
        .HADDR      ( HADDR    [ahbport] ),
        .HWDATA     ( HWDATA   [ahbport] ),
        .HRDATA     ( HRDATA   [ahbport] ),
        .HREADY     ( HREADY   [ahbport] ),
        .HRESP      ( HRESP    [ahbport] ));

       assign HREADY[ahbport] = HREADYOUT[ahbport];
  end
endgenerate


  //Instantiate SDRAM controller (DUT)
  ahb3lite_sdram_ctrl #(
    .INIT_DLY_CNT     ( INIT_DLY_CNT     ),  //in PCLK cycles
    .WRITEBUFFER_SIZE ( WRITEBUFFER_SIZE ),
  
    .AHB_PORTS        ( AHB_PORTS        ),
    .HADDR_SIZE       ( HADDR_SIZE       ),
    .HDATA_SIZE       ( HDATA_SIZE       ),

    .SDRAM_DQ_SIZE    ( SDRAM_DQ_SIZE    ),
    .SDRAM_ADDR_SIZE  ( SDRAM_ADDR_SIZE  ))
  dut (
    //APB Control/Status Interface
    .PRESETn          ( PRESETn          ),
    .PCLK             ( PCLK             ),
    .PSEL             ( PSEL             ),
    .PENABLE          ( PENABLE          ),
    .PADDR            ( PADDR            ),
    .PWRITE           ( PWRITE           ),
    .PSTRB            ( PSTRB            ),
    .PPROT            ( PPROT            ),
    .PWDATA           ( PWDATA           ),
    .PRDATA           ( PRDATA           ),
    .PREADY           ( PREADY           ),
    .PSLVERR          ( PSLVERR          ),

    //AHB Data Interface
    .HRESETn          ( HRESETn          ),
    .HCLK             ( HCLK             ),
    .HSEL             ( HSEL             ),
    .HTRANS           ( HTRANS           ),
    .HSIZE            ( HSIZE            ),
    .HBURST           ( HBURST           ),
    .HPROT            ( HPROT            ),
    .HMASTLOCK        ( HMASTLOCK        ),
    .HWRITE           ( HWRITE           ),
    .HADDR            ( HADDR            ),
    .HWDATA           ( HWDATA           ),
    .HRDATA           ( HRDATA           ),
    .HREADYOUT        ( HREADYOUT        ),
    .HREADY           ( HREADY           ),
    .HRESP            ( HRESP            ),

    //SDRAM Interface
    .sdram_rdclk_i    ( sdram_rdclk      ),
    .sdram_clk_o      ( sdram_clk        ),
    .sdram_cke_o      ( sdram_cke        ),
    .sdram_cs_no      ( sdram_cs_n       ),
    .sdram_ras_no     ( sdram_ras_n      ),
    .sdram_cas_no     ( sdram_cas_n      ),
    .sdram_we_no      ( sdram_we_n       ),
    .sdram_ba_o       ( sdram_ba         ),
    .sdram_addr_o     ( sdram_addr       ),
    .sdram_dq_i       ( sdram_dqi        ),
    .sdram_dq_o       ( sdram_dqo        ),
    .sdram_dqoe_o     ( sdram_dqoe       ),
    .sdram_dm_o       ( sdram_dm         ));


  //PCB traces (transport delay)
  always_comb
  begin
      sdram_clk_pcb   <= #(TRACE_DELAY) sdram_clk;
      sdram_cke_pcb   <= #(TRACE_DELAY) sdram_cke;
      sdram_cs_n_pcb  <= #(TRACE_DELAY) sdram_cs_n;
      sdram_ras_n_pcb <= #(TRACE_DELAY) sdram_ras_n;
      sdram_cas_n_pcb <= #(TRACE_DELAY) sdram_cas_n;
      sdram_we_n_pcb  <= #(TRACE_DELAY) sdram_we_n;
      sdram_ba_pcb    <= #(TRACE_DELAY) sdram_ba;
      sdram_addr_pcb  <= #(TRACE_DELAY) sdram_addr;
      sdram_dq_pcb    <= #(TRACE_DELAY) sdram_dqoe ? sdram_dqo : {$bits(sdram_dq){1'bz}};
      sdram_dm_pcb    <= #(TRACE_DELAY) sdram_dm;
  end

  assign sdram_dq = sdram_dq_pcb;
  always_comb sdram_dqi <= #(TRACE_DELAY) sdram_dq;

  //Instantiate SDRAM memory model
  IS42VM32200M
  sdram_memory (
    .clk  ( sdram_clk_pcb   ),
    .cke  ( sdram_cke_pcb   ),
    .csb  ( sdram_cs_n_pcb  ),
    .rasb ( sdram_ras_n_pcb ),
    .casb ( sdram_cas_n_pcb ),
    .web  ( sdram_we_n_pcb  ),
    .ba   ( sdram_ba_pcb    ),
    .addr ( sdram_addr_pcb  ),
    .dq   ( sdram_dq        ),
    .dqm  ( sdram_dm_pcb    ));

 
  //Initial settings and tests

  initial
  begin
      HCLK = 1'b0;
      repeat (5) @(posedge HCLK);
      ahb_reset();
  end

  initial
  begin
      PCLK = 1'b0;
      repeat (5) @(posedge PCLK);
      apb_reset();
  end
 
  initial
  begin
      //wait for PCLK reset
      @(posedge PRESETn);

      welcome_msg();
      set_time_csr(HCLK_PERIOD, REFRESHES, REFRESH_PERIOD, SDRAM_BTAC, SDRAM_CL, tRP, tRCD, tRC);
      wait_for_init_done();
      initialise_sdram_ctrl();

//      write_sdram_seq(HSIZE_B8 , HBURST_SINGLE, 70);
      write_sdram_seq(HSIZE_B32, HBURST_SINGLE, 30);
//      write_sdram_seq(HSIZE_B16, HBURST_INCR4, 30);


      repeat (100) @(posedge HCLK);

      read_sdram_seq(HSIZE_B8, HBURST_SINGLE, 5);

      goodbye_msg();

      //wait a bit and finish
      repeat (1600) @(posedge PCLK);
      $finish();
  end

endmodule

