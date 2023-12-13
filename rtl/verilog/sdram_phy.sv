/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multiport SDRAM Controller                         //
//    PHY layer                                                    //
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
// FILE NAME      : sdram_phy.sv
// DEPARTMENT     :
// AUTHOR         : rherveille
// AUTHOR'S EMAIL :
// ------------------------------------------------------------------
// RELEASE HISTORY
// VERSION DATE        AUTHOR      DESCRIPTION
// 1.0     2023-11-09  rherveille  initial release
// ------------------------------------------------------------------
// KEYWORDS : SDRAM PHY Physicial Layer
// ------------------------------------------------------------------
// PURPOSE  : SDRAM Controller Physicial Layer
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  STAGES            2+       Number of DFF stages     2       DFFs
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : rst_ni, asynchronous, active low
//   Clock Domains       : clk_i, rdclk_i
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------

module sdram_phy
import sdram_ctrl_pkg::*;
#(
  parameter int SDRAM_ADDR_SIZE = 13,
  parameter int SDRAM_BA_SIZE   = 2,
  parameter int SDRAM_DQ_SIZE   = 32
)
(
  input                              rst_ni,
  input                              clk_i,
  input sdram_cmds_t                 cmd_i,
  input  logic [SDRAM_BA_SIZE  -1:0] ba_i,
  input  logic [SDRAM_ADDR_SIZE-1:0] addr_i,
  input  logic [SDRAM_DQ_SIZE  -1:0] dq_i,
  input  logic                       dqoe_i,
  input  logic [SDRAM_DQ_SIZE/8-1:0] dm_i,

  output logic                       sdram_clk_o,
  output logic                       sdram_cke_o,
                                     sdram_cs_no,
                                     sdram_ras_no,
                                     sdram_cas_no,
                                     sdram_we_no,
  output logic [SDRAM_BA_SIZE  -1:0] sdram_ba_o,
  output logic [SDRAM_ADDR_SIZE-1:0] sdram_addr_o,
  output logic [SDRAM_DQ_SIZE  -1:0] sdram_dq_o,
  output logic                       sdram_dqoe_o,
  output logic [SDRAM_DQ_SIZE/8-1:0] sdram_dm_o,


  input                              sdram_rdclk_i,
  input  logic [SDRAM_DQ_SIZE  -1:0] sdram_dq_i,
  output logic [SDRAM_DQ_SIZE  -1:0] dq_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic                     rdrst_n;
  logic [SDRAM_DQ_SIZE-1:0] latch_dqi;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* SDRAM Clock
   */
  assign sdram_clk_o = clk_i;


  /* SDRAM CMD
   */
  //decode CMD
  always @(posedge clk_i)
    {sdram_cke_o,
     sdram_cs_no,
     sdram_ras_no,
     sdram_cas_no,
     sdram_we_no} <= cmd_i;


  /* SDRAM Address/BA
   */
  always @(posedge clk_i)
    begin
        sdram_ba_o    <= ba_i;
        sdram_addr_o  <= addr_i;
    end


  /* SDRAM DQ/DM (write)
   */
  always @(posedge clk_i)
    begin
        sdram_dq_o    <= dq_i;
        sdram_dqoe_o  <= dqoe_i;
        sdram_dm_o    <= dm_i;
    end


   /* SDRAM DQ (read)
    */

  //rdclk-reset
  synchronizer #(2) rdrst_n_synchronizers (rst_ni, sdram_rdclk_i, 1'b1, rdrst_n);

  //latch sdram_dq_i; close to input buffers
  always @(posedge sdram_rdclk_i)
    latch_dqi <= sdram_dq_i;

  //synchronise incoming data
  mesochronous_synchronizer #(SDRAM_DQ_SIZE)
  dqi_synchroniser (
    .wrrst_ni ( rdrst_n        ),
    .wrclk_i  ( sdram_rdclk_i  ),
    .d_i      ( latch_dqi      ),

    .rdrst_ni ( rst_ni         ),
    .rdclk_i  ( clk_i          ),
    .q_o      ( dq_o           ));

endmodule : sdram_phy
