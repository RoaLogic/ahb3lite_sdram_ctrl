/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    Address Mapping                                              //
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
// FILE NAME      : sdram_address_mapping.sv
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
// PURPOSE  : SDRAM Controller Row/Column/Bank decoder
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  INIT_DLY_CNT      1+       Powerup delay            2500    cycles
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : none
//   Clock Domains       : clk_i
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------

module sdram_address_mapping
`ifndef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
`endif
#(
  parameter int ADDR_SIZE = 32,
  parameter int MAX_CSIZE = 11, //max 11 column address bits
  parameter int MAX_RSIZE = 13, //max 13 row address bits
  parameter int BA_SIZE   = 2
)
(
  input  logic                  clk_i,
  input  csr_t                  csr_i,

  input  logic [ADDR_SIZE -1:0] address_i,
  output logic [BA_SIZE   -1:0] bank_o,
  output logic [MAX_RSIZE -1:0] row_o,
  output logic [MAX_CSIZE -1:0] column_o
);

`ifdef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
`endif


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [ADDR_SIZE -1:0] address_dqsize,
                         address_columns,
                         address_rows;

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  //1. handle dqsize
  assign address_dqsize = address_i >> csr_i.ctrl.dqsize;

  //2. extract column; LSBs of adr_dqsize
  always @(posedge clk_i)
    column_o <= address_dqsize[MAX_CSIZE-1:0];

  //3. extract row
  always_comb
    case (csr_i.ctrl.cols)
      2'b00: address_columns = address_dqsize >>  8;
      2'b01: address_columns = address_dqsize >>  9;
      2'b10: address_columns = address_dqsize >> 10;
      2'b11: address_columns = address_dqsize >> 11;
    endcase

  always @(posedge clk_i)
    row_o <= csr_i.ctrl.iam ? address_columns[2 +: MAX_RSIZE] : address_columns[0 +: MAX_RSIZE];

  //4. extract BA
  always_comb
    case (csr_i.ctrl.rows)
      2'b00: address_rows = address_columns >> 11;
      2'b01: address_rows = address_columns >> 12;
      2'b10: address_rows = address_columns >> 13;
      2'b11: address_rows = address_columns >> 14;
    endcase
 
  always @(posedge clk_i)
    bank_o <= csr_i.ctrl.iam ? address_columns[1:0] : address_rows[1:0];

endmodule : sdram_address_mapping
