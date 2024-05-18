/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    Top Level                                                    //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2023 ROA Logic BV                     //
//             www.roalogic.com                                    //
//                                                                 //
//     Unless specifically agreed in writing, this software is     //
//   licensed under the RoaLogic Non-Commercial License            //
//   version-1.0 (the "License"), a copy of which is included      //
//   with this file or may be found on the RoaLogic website        //
//   http://www.roalogic.com. You may not use the file except      //
//   in compliance with the License.                               //
//                                                                 //
//     THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY           //
//   EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                    //
//   See the License for permissions and limitations under the     //
//   License.                                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////

// +FHDR -  Semiconductor Reuse Standard File Header Section  -------
// FILE NAME      : ahb3lite_sdram_ctrl.sv
// DEPARTMENT     :
// AUTHOR         : rherveille
// AUTHOR'S EMAIL :
// ------------------------------------------------------------------
// RELEASE HISTORY
// VERSION DATE        AUTHOR      DESCRIPTION
// 1.0     2023-11-09  rherveille  initial release
// ------------------------------------------------------------------
// KEYWORDS : AMBA AHB AHB3-Lite SDRAM Synchronous DRAM Controller
// ------------------------------------------------------------------
// PURPOSE  : SDRAM Controller
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  INIT_DLY_CNT      1+       Powerup delay            2500    cycles
//  HADDR_SIZE        1+       Address bus size         8       bits
//  HDATA_SIZE        1+       Data bus size            32      bits
//  TIMEOUT_CNT       1+       Timeout counter          256     cycles
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : external asynchronous active low; HRESETn
//                         external asynchronous active low; PRESETn
//   Clock Domains       : HCLK, rising edge
//                         PCLK, rising edge
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------


//INIT_DLY_CNT = PCLK_Frequency * required_dely
//example INIT_DLY_CNT = 25MHz * 100us = 2500


//---- Startup ------
//Controller automatically handles initial delay
//  CTRL.ena cannot be set until inital delay is completed
//
//Program CTRL Mode=Precharge
//Write to SDRAM with A10='1' (Precharge All)
//Program CTRL Mode=AutoRefresh
//Write to SDRAM (AutoRefresh) 8x
//Program CTRL Mode=Set Mode Register
//Write to SDRAM with Address=Mode Register Setting
//Write to TIME (set timing registers)
//Write to CTRL Mode=Normal, set control bits/values


module ahb3lite_sdram_ctrl
`ifndef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;                //Quartus doesn't like this
  import ahb3lite_pkg::*;
`endif
#(
  parameter int AHB_PORTS         = 2,
  parameter int AHB_CTRL_PORT     = 0,
  parameter int HADDR_SIZE        = 32,
  parameter int HDATA_SIZE        = 32,

  parameter int SDRAM_DQ_SIZE     = 16,    //valid options: 16, 32, 64, 128
  parameter int SDRAM_ADDR_SIZE   = 13,

  parameter int INIT_DLY_CNT      = 2500,  //in PCLK cycles
  parameter int WRITEBUFFER_SIZE  = 8 * SDRAM_DQ_SIZE,    //SDRAM max burst = 8

  parameter     TECHNOLOGY        = "ALTERA"
)
(
  //APB Control/Status Interface
  input                        PRESETn,
                               PCLK,
                               PSEL,
                               PENABLE,
  input  [                3:0] PADDR,
  input                        PWRITE,
  input  [                3:0] PSTRB,
  input  [                2:0] PPROT,
  input  [               31:0] PWDATA,
  output [               31:0] PRDATA,
  output                       PREADY,
                               PSLVERR,

  //AHB Data Interface
  input                        HRESETn,
                               HCLK,
  input                        HSEL      [AHB_PORTS],
  input  [HTRANS_SIZE    -1:0] HTRANS    [AHB_PORTS],
  input  [HSIZE_SIZE     -1:0] HSIZE     [AHB_PORTS],
  input  [HBURST_SIZE    -1:0] HBURST    [AHB_PORTS],
  input  [HPROT_SIZE     -1:0] HPROT     [AHB_PORTS],
  input                        HMASTLOCK [AHB_PORTS],
  input                        HWRITE    [AHB_PORTS],
  input  [HADDR_SIZE     -1:0] HADDR     [AHB_PORTS],
  input  [HDATA_SIZE     -1:0] HWDATA    [AHB_PORTS],
  output [HDATA_SIZE     -1:0] HRDATA    [AHB_PORTS],
  output                       HREADYOUT [AHB_PORTS],
  input                        HREADY    [AHB_PORTS],
  output                       HRESP     [AHB_PORTS],


  //SDRAM Interface
  input                        sdram_rdclk_i,
  output                       sdram_clk_o,
                               sdram_cke_o,
                               sdram_cs_no,
                               sdram_ras_no,
                               sdram_cas_no,
                               sdram_we_no,
  output [                1:0] sdram_ba_o,
  output [SDRAM_ADDR_SIZE-1:0] sdram_addr_o,
  input  [SDRAM_DQ_SIZE  -1:0] sdram_dq_i,
  output [SDRAM_DQ_SIZE  -1:0] sdram_dq_o,
  output                       sdram_dqoe_o,
  output [SDRAM_DQ_SIZE/8-1:0] sdram_dm_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
`ifdef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
  import ahb3lite_pkg::*;
`endif

  localparam int SDRAM_BA_SIZE = 2;
  localparam int MAX_RSIZE     = 13;
  localparam int MAX_CSIZE     = 11;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //AHB clock domain
  csr_t ahb_csr;

  //SDRAM read clock domain
  logic                           sdram_rdclk_rst_n;
  csr_t                           sdram_rdclk_csr;

  logic                           wbr       [AHB_PORTS];

  logic                           rdreq     [AHB_PORTS];
  logic                           rdrdy     [AHB_PORTS];
  logic [HADDR_SIZE         -1:0] rdadr     [AHB_PORTS];
  logic [SDRAM_BA_SIZE      -1:0] rdba      [AHB_PORTS];
  logic [MAX_RSIZE          -1:0] rdrow     [AHB_PORTS];
  logic [MAX_CSIZE          -1:0] rdcol     [AHB_PORTS];
  logic [                    7:0] rdsize    [AHB_PORTS];
  logic [SDRAM_DQ_SIZE      -1:0] rdq       [AHB_PORTS];
  logic                           rdqvalid  [AHB_PORTS];

  logic                           wrreq     [AHB_PORTS];
  logic                           wrrdy     [AHB_PORTS];
  logic [SDRAM_BA_SIZE      -1:0] wrba      [AHB_PORTS];
  logic [MAX_RSIZE          -1:0] wrrow     [AHB_PORTS];
  logic [MAX_CSIZE          -1:0] wrcol     [AHB_PORTS];
  logic [HSIZE_SIZE         -1:0] wrsize    [AHB_PORTS];
  logic [WRITEBUFFER_SIZE/8 -1:0] wrbe      [AHB_PORTS];
  logic [WRITEBUFFER_SIZE   -1:0] wrd       [AHB_PORTS];

  sdram_cmds_t                    sdram_cmd;
  logic [SDRAM_BA_SIZE      -1:0] sdram_ba;
  logic [SDRAM_ADDR_SIZE    -1:0] sdram_addr;
  logic [SDRAM_DQ_SIZE      -1:0] sdram_d;
  logic [SDRAM_DQ_SIZE      -1:0] sdram_q;
  logic                           sdram_dqoe;
  logic [SDRAM_DQ_SIZE/8    -1:0] sdram_dm;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  
  /* Instantiate CSR module (APB Domain)
   */
  sdram_apb_if #(
    .SDRAM_DQ_SIZE      ( SDRAM_DQ_SIZE     ),
    .INIT_DLY_CNT       ( INIT_DLY_CNT      ))
  apb_if_inst (
    //APB Clock domain
    .PRESETn            ( PRESETn           ),
    .PCLK               ( PCLK              ),
    .PSEL               ( PSEL              ),
    .PENABLE            ( PENABLE           ),
    .PADDR              ( PADDR             ),
    .PWRITE             ( PWRITE            ),
    .PSTRB              ( PSTRB             ),
    .PPROT              ( PPROT             ),
    .PWDATA             ( PWDATA            ),
    .PRDATA             ( PRDATA            ),
    .PREADY             ( PREADY            ),
    .PSLVERR            ( PSLVERR           ),

    //AHB Clock domain
    .HRESETn            ( HRESETn           ),
    .HCLK               ( HCLK              ),
    .ahb_csr_o          ( ahb_csr           ));


  /* Instantiate AHB Interface module
   */
generate
  genvar ahbport;

  for (ahbport=0; ahbport < AHB_PORTS; ahbport++)
  begin: gen_ahb_if
      sdram_ahb_if #(
        .HADDR_SIZE       ( HADDR_SIZE         ),
        .HDATA_SIZE       ( HDATA_SIZE         ),
        .WRITEBUFFER_SIZE ( WRITEBUFFER_SIZE   ),
        .SDRAM_DQ_SIZE    ( SDRAM_DQ_SIZE      ),
        .SDRAM_BA_SIZE    ( SDRAM_BA_SIZE      ),
        .MAX_CSIZE        ( MAX_CSIZE          ),
        .MAX_RSIZE        ( MAX_RSIZE          ),
        .TECHNOLOGY       ( TECHNOLOGY         ))
      ahb_if (
        .csr_i            ( ahb_csr            ),
      
        //AHB Port
        .HRESETn          ( HRESETn            ),
        .HCLK             ( HCLK               ),
        .HSEL             ( HSEL     [ahbport] ),
        .HTRANS           ( HTRANS   [ahbport] ),
        .HSIZE            ( HSIZE    [ahbport] ),
        .HBURST           ( HBURST   [ahbport] ),
        .HPROT            ( HPROT    [ahbport] ),
        .HWRITE           ( HWRITE   [ahbport] ),
        .HMASTLOCK        ( HMASTLOCK[ahbport] ),
        .HADDR            ( HADDR    [ahbport] ),
        .HWDATA           ( HWDATA   [ahbport] ),
        .HRDATA           ( HRDATA   [ahbport] ),
        .HREADYOUT        ( HREADYOUT[ahbport] ),
        .HREADY           ( HREADY   [ahbport] ),
        .HRESP            ( HRESP    [ahbport] ),

        //To scheduler
        .wbr_o            ( wbr      [ahbport] ),

        .rdreq_o          ( rdreq    [ahbport] ),
        .rdrdy_i          ( rdrdy    [ahbport] ),
        .rdadr_o          ( rdadr    [ahbport] ),
        .rdba_o           ( rdba     [ahbport] ),
        .rdrow_o          ( rdrow    [ahbport] ),
        .rdcol_o          ( rdcol    [ahbport] ),
        .rdsize_o         ( rdsize   [ahbport] ),
        .rdq_i            ( rdq      [ahbport] ),
        .rdqvalid_i       ( rdqvalid [ahbport] ),

        .wrreq_o          ( wrreq    [ahbport] ),
        .wrrdy_i          ( wrrdy    [ahbport] ),
        .wradr_o          (                    ),
        .wrba_o           ( wrba     [ahbport] ),
        .wrrow_o          ( wrrow    [ahbport] ),
        .wrcol_o          ( wrcol    [ahbport] ),
        .wrsize_o         ( wrsize   [ahbport] ),
        .wrbe_o           ( wrbe     [ahbport] ),
        .wrd_o            ( wrd      [ahbport] ));
  end
endgenerate


  /* Instantiate SDRAM Controller block
   */
  sdram_cmd_scheduler #(
    .PORTS           ( AHB_PORTS        ),
    .CTRL_PORT       ( AHB_CTRL_PORT    ),
    .ADDR_SIZE       ( HADDR_SIZE       ),
    .WDATA_SIZE      ( WRITEBUFFER_SIZE ),

    .SDRAM_ADDR_SIZE ( SDRAM_ADDR_SIZE  ),
    .SDRAM_BA_SIZE   ( SDRAM_BA_SIZE    ),
    .SDRAM_DQ_SIZE   ( SDRAM_DQ_SIZE    ))
  cmd_scheduler (
    .rst_ni          ( HRESETn          ),
    .clk_i           ( HCLK             ),

    .wbr_i           ( wbr              ),
    .rdreq_i         ( rdreq            ),
    .rdrdy_o         ( rdrdy            ),
    .rdadr_i         ( rdadr            ),
    .rdba_i          ( rdba             ),
    .rdrow_i         ( rdrow            ),
    .rdcol_i         ( rdcol            ),
    .rdsize_i        ( rdsize           ),
    .rdq_o           ( rdq              ),
    .rdqvalid_o      ( rdqvalid         ),

    .wrreq_i         ( wrreq            ),
    .wrrdy_o         ( wrrdy            ),
    .wrba_i          ( wrba             ),
    .wrrow_i         ( wrrow            ),
    .wrcol_i         ( wrcol            ),
    .wrsize_i        ( wrsize           ),
    .wrbe_i          ( wrbe             ),
    .wrd_i           ( wrd              ),

    .csr_i           ( ahb_csr          ),

    .sdram_cmd_o     ( sdram_cmd        ),
    .sdram_ba_o      ( sdram_ba         ),
    .sdram_addr_o    ( sdram_addr       ),
    .sdram_dq_i      ( sdram_q          ),
    .sdram_dq_o      ( sdram_d          ),
    .sdram_dqoe_o    ( sdram_dqoe       ),
    .sdram_dm_o      ( sdram_dm         ));


  /* Instantiate SDRAM PHY
   */
  sdram_phy #(
    .SDRAM_ADDR_SIZE ( SDRAM_ADDR_SIZE ),
    .SDRAM_BA_SIZE   ( SDRAM_BA_SIZE   ),
    .SDRAM_DQ_SIZE   ( SDRAM_DQ_SIZE   ))
  phy (
    .rst_ni          ( HRESETn         ),
    .clk_i           ( HCLK            ),
    .cmd_i           ( sdram_cmd       ),
    .ba_i            ( sdram_ba        ),
    .addr_i          ( sdram_addr      ),
    .dq_i            ( sdram_d         ),
    .dq_o            ( sdram_q         ),
    .dqoe_i          ( sdram_dqoe      ),
    .dm_i            ( sdram_dm        ),

    .sdram_rdclk_i   ( sdram_rdclk_i   ),
    .sdram_clk_o     ( sdram_clk_o     ),
    .sdram_cke_o     ( sdram_cke_o     ),
    .sdram_cs_no     ( sdram_cs_no     ),
    .sdram_ras_no    ( sdram_ras_no    ),
    .sdram_cas_no    ( sdram_cas_no    ),
    .sdram_we_no     ( sdram_we_no     ),
    .sdram_ba_o      ( sdram_ba_o      ),
    .sdram_addr_o    ( sdram_addr_o    ),
    .sdram_dq_o      ( sdram_dq_o      ),
    .sdram_dq_i      ( sdram_dq_i      ),
    .sdram_dqoe_o    ( sdram_dqoe_o    ),
    .sdram_dm_o      ( sdram_dm_o      ));

endmodule : ahb3lite_sdram_ctrl
