/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    APB Control and Status Registers Interface                   //
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
// FILE NAME      : sdram_apb_if.sv
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
// PURPOSE  : SDRAM Controller CSR register
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  INIT_DLY_CNT      1+       Powerup delay            2500    cycles
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : external asynchronous active low; PRESETn
//                         generated asyncronous active low; sdram_rdclk_rst_no
//   Clock Domains       : PCLK, rising edge
//                         sdram_rdclk_i, rising edge
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------


// CSR are accessed through the APB interface
// When a CSR is written, the value of all CSRs is copied into the SDRAM clock
// domain using a single, synchronised write-signal
//
// SDRAM Domain Reset:
// The async.reset for the SDRAM Clock Domain is generated from PRESETn
//
// PPROT Note:
// When PP=1 (Privilege Protection) a normal CSR read/write results in PSLVERR
// being asserted
//
// CDC Note:
// APB clock domain  ->  SDRAM clock domain    Note:
// apb_write_reg         sdram_write_syncreg   use syncregs
// csr.*                 *_csr_o               false path
//

module sdram_apb_if
import sdram_ctrl_pkg::*;
#(
  parameter int SDRAM_DQ_SIZE    = 32,
  parameter int INIT_DLY_CNT     = 2500,
  parameter int FIXED_ROWS       = 0,
  parameter int FIXED_COLUMNS    = 0,
  parameter int FIXED_BURST_SIZE = 0,
  parameter     FIXED_AP         = "CSR", //valid options: ALWAYS, NEVER, CSR

  parameter int PADDR_SIZE       = 4,
  parameter int PDATA_SIZE       = 32
)
(
  //APB Clock domain
  //APB Control/Status Interface
  input  logic                    PRESETn,
                                  PCLK,
                                  PSEL,
                                  PENABLE,
  input  logic [PADDR_SIZE  -1:0] PADDR,
  input  logic                    PWRITE,
  input  logic [PDATA_SIZE/8-1:0] PSTRB,
  input  logic [             2:0] PPROT,
  input  logic [PDATA_SIZE  -1:0] PWDATA,
  output logic [PDATA_SIZE  -1:0] PRDATA,
  output logic                    PREADY,
                                  PSLVERR,

  //AHB Clock domain
  input  logic       HRESETn,
  input  logic       HCLK,
  output csr_t       ahb_csr_o
);

  // Address Map
  //
  //+---------+----------+
  //| Address | Register | 
  //+---------+----------+
  //| 0x0     | CTRL     |
  //| 0x1     | Timing   |
  //+---------+----------+ 




  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam int   CNT_SIZE = $clog2(INIT_DLY_CNT);

  localparam [PADDR_SIZE-1:0] CSR_CTRL = 'h0;
  localparam [PADDR_SIZE-1:0] CSR_TIME = 'h4;
  localparam [PADDR_SIZE-1:0] CSR_TREF = 'h8;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //APB domain
  logic                apb_read,
                       apb_write,
                       apb_access,
                       apb_prot_error;
  logic                apb_write_dly,
                       apb_write_toggle;

  logic [         1:0] ahb_written_sync;
  logic                ahb_written;         //feedback from AHB

  csr_t                csr;

  logic [CNT_SIZE-1:0] init_dly_cnt;
  logic                init_done;

  //AHB domain
  logic [         1:0] ahb_rstn_gen;
  logic                ahb_rstn;
  logic [         1:0] ahb_write_sync;
  logic                ahb_write;
  logic                ahb_write_toggle;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
  localparam csr_ctrl_t   CSR_CTRL_RESET_VALUE   = 32'h0;
  localparam csr_timing_t CSR_TIMING_RESET_VALUE = 32'h0;
  localparam [15:0]       CSR_TREF_RESET_VALUE   = 128;

  //
  // APB Clock Domain
  //

  //access error when PrivilegeProtect=1 and non-privileged access
  assign apb_prot_error = csr.ctrl.pp & ~PPROT[0];
  assign apb_access     = PSEL & PENABLE & ~apb_prot_error;
  assign apb_read       = apb_access & ~PWRITE;
  assign apb_write      = apb_access &  PWRITE;


  //Create apb_write_toggle, for clock-domain-crossing
  always @(posedge PCLK)
    apb_write_dly <= apb_write;

  always @(posedge PCLK, negedge PRESETn)
    if      (!PRESETn                   ) apb_write_toggle <= 1'b0;
    else if ( apb_write & ~apb_write_dly) apb_write_toggle <= ~apb_write_toggle;


  //Write Register Access
  always @(posedge PCLK, negedge PRESETn)
    if (!PRESETn)
    begin
        csr.ctrl   <= CSR_CTRL_RESET_VALUE;
        csr.timing <= CSR_TIMING_RESET_VALUE;
        csr.tREF   <= 128;
    end
    else if (apb_write)
    case (PADDR)
      CSR_CTRL:
      begin
          if (PSTRB[3]) csr.ctrl[31:24] <= PWDATA[31:24] & {init_done,7'b111_1111};
          if (PSTRB[2])
          begin
              csr.ctrl[23:16] <= PWDATA[23:16];
              case (SDRAM_DQ_SIZE)
                128     : csr.ctrl.dqsize <= PWDATA[17:16];
                 64     : csr.ctrl.dqsize <= {PWDATA[17], PWDATA[16] & ~PWDATA[17]};
                 32     : csr.ctrl.dqsize <= {1'b0, PWDATA[16]};
                 default: csr.ctrl.dqsize <= 2'b00;
              endcase
          end
          if (PSTRB[1]) csr.ctrl[15: 8] <= PWDATA[15: 8];
          if (PSTRB[0]) csr.ctrl[ 7: 0] <= PWDATA[ 7: 0];
      end

      CSR_TIME:
      begin
          if (PSTRB[3]) csr.timing[31:24] <= PWDATA[31:24];
          if (PSTRB[2]) csr.timing[23:16] <= PWDATA[23:16];
          if (PSTRB[1]) csr.timing[15: 8] <= PWDATA[15: 8];
          if (PSTRB[0]) csr.timing[ 7: 0] <= PWDATA[ 7: 0];
      end

      CSR_TREF:
      begin
          //if (PSTRB[3]) csr.tREF[31:24] <= PWDATA[31:24];
          //if (PSTRB[2]) csr.tREF[23:16] <= PWDATA[23:16];
          if (PSTRB[1]) csr.tREF[15: 8] <= PWDATA[15: 8];
          if (PSTRB[0]) csr.tREF[ 7: 0] <= PWDATA[ 7: 0];
      end

    endcase


  //Read Register Access
  always @(posedge PCLK)
    case (PADDR)
      CSR_CTRL: begin
                    PRDATA     <= csr.ctrl;
                    PRDATA[30] <= init_done;
                end
      CSR_TIME: PRDATA <= csr.timing;
      CSR_TREF: PRDATA <= {16'h0, csr.tREF};
    endcase


  //We must wait for the CSRs to cross into the AHB domain
  always @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) PREADY <= 1'b1;
    else
    case (PREADY)
      1'b1: if (PSEL && !PENABLE && PWRITE && !apb_prot_error) PREADY <= 1'b0;
      1'b0: if (ahb_written                                  ) PREADY <= 1'b1;
    endcase  


  //generate PSLVERR
  always @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) PSLVERR <= 1'b0;
    else          PSLVERR <= PSEL & apb_prot_error;



  //Powerup delay counter
  always @(posedge PCLK, negedge PRESETn)
    if (!PRESETn)
    begin
        init_dly_cnt <= INIT_DLY_CNT[0 +: $bits(init_dly_cnt)];
        init_done    <= 1'b0;
    end
    else if (!init_done)
    begin
        init_dly_cnt <= init_dly_cnt -1'h1;

	if (~|init_dly_cnt) init_done <= 1'b1;
    end


  //
  // AHB Clock Domain
  //

  //keep AHB domain registers reset until both HRESETn and PRESETn are negated
  synchronizer #(2) ahb_rstn_synchronizers (HRESETn | PRESETn, HCLK, 1'b1, ahb_rstn);


  //synchronise write signals
  synchronizer #(2) ahb_write_synchronizers (ahb_rstn, HCLK, apb_write_toggle, ahb_write_sync[0]);

  always @(posedge HCLK, negedge ahb_rstn)
    if (!ahb_rstn) ahb_write_sync[1] <= 1'b0;
    else           ahb_write_sync[1] <= ahb_write_sync[0];

  //create strobed version
  always @(posedge HCLK)
    ahb_write <= ahb_write_sync[1] ^ ahb_write_sync[0];


  //transfer CSR
  always @(posedge HCLK, negedge ahb_rstn)
    if (!ahb_rstn)
    begin
        ahb_csr_o.ctrl   <= CSR_CTRL_RESET_VALUE;
        ahb_csr_o.timing <= CSR_TIMING_RESET_VALUE;
    end
    else if (ahb_write)
    begin
        ahb_csr_o   <= csr;
    end


  // Back into the APB domain
  //
  always @(posedge HCLK)
    if      (!HRESETn  ) ahb_write_toggle <= 1'b0;
    else if ( ahb_write) ahb_write_toggle <= ~ahb_write_toggle;


  //synchronise write-toggle signal
  synchronizer #(2) ahb_written_synchronizers (PRESETn, PCLK, ahb_write_toggle, ahb_written_sync[0]);

  always @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) ahb_written_sync[1] <= 1'b0;
    else          ahb_written_sync[1] <= ahb_written_sync[0];


  //create strobed version
  always @(posedge PCLK)
    ahb_written <= ahb_written_sync[1] ^ ahb_written_sync[0];

endmodule : sdram_apb_if
