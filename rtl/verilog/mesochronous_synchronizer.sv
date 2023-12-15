/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    Mesochronous Synchronizer                                    //
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
// FILE NAME      : mesochronous_synchronizer.sv
// DEPARTMENT     :
// AUTHOR         : rherveille
// AUTHOR'S EMAIL :
// ------------------------------------------------------------------
// RELEASE HISTORY
// VERSION DATE        AUTHOR      DESCRIPTION
// 1.0     2023-11-09  rherveille  initial release
// ------------------------------------------------------------------
// KEYWORDS : Synchronizer Mesochronous
// ------------------------------------------------------------------
// PURPOSE  : Small FIFO to cross two phase shifted clock domains
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION               DEFAULT UNITS
//  DATA_SIZE         1+       Number of data bits       32
//  REGISTERED_OUTPUT [YES,NO] Add output register stage NO
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : rst_ni, asynchronous, active low
//   Clock Domains       : clk_i
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------


/* A mesochronous system is a system in which 2 clocks have the exact
 * same clock frequency, but a different phase.
 * There is 0 frequency drift between the 2 clocks. There is only a 
 * fixed phase offset.
 *
 * The synchonizer writes data into circulat buffer
 * The write pointer trails the read pointer, ensuring the max setup
 * time possible for the read side. Thus removing metastability risk
 *
 *              ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * wrclk_i    : ┘  └──┘  └──┘  └──┘  └──┘  └─
 *                    ╱    ╲╱    ╲
 * d_i        :       ╲ a  ╱╲ b  ╱
 *                     ┆
 *               ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * rdclk_i    :  ┘  └──┘  └──┘  └──┘  └──┘  └─
 * When rdclk_i is trailing wrclk_i by a small amount (phase),
 * Tclk-to-d(setup) will be violated
 *
 *
 *               ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * wrclk_i    :  ┘  └──┘  └──┘  └──┘  └──┘  └─
 *                     ╱    ╲╱    ╲
 * d_i        :        ╲ a  ╱╲ b  ╱
 *                     ┆
 *              ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * rdclk_i    : ┘  └──┘  └──┘  └──┘  └──┘  └─
 * When rdclk_i is leading wrclk_i by a small amount (phase),
 * Tclk-to-d(hold) will be violated
 *
 * To avoid both Tclk-to-d(setup) and Tclk-to-d(hold) violations
 * the data is stored for a cycle and latched on the next rising edge
 * of rclk_i.
 *
 * rclk_i trailing (setup time satisfied):
 *              ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * wrclk_i    : ┘  └──┘  └──┘  └──┘  └──┘  └──┘
 *                    ╱    ╲╱    ╲
 * d_i        :       ╲ a  ╱╲ b  ╱
 *                          ╱          ╲
 * mem[0]     :             ╲ a        ╱
 *                                ╱┆         ╲
 * mem[1]     :                   ╲ b        ╱
 *                                 ┆     ┆
 *               ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * rdclk_i    :  ┘  └──┘  └──┘  └──┘  └──┘  └─
 *                                 ╱    ╲╱    ╲
 * q_o        :                    ╲ a  ╱╲ b  ╱
 *
 * rclk_i leading (hold time satisfied):
 *               ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * wrclk_i    :  ┘  └──┘  └──┘  └──┘  └──┘  └─
 *                     ╱    ╲╱    ╲
 * d_i        :        ╲ a  ╱╲ b  ╱
 *                           ╱          ╲
 * mem[0]     :              ╲ a        ╱
 *                                 ╱     ┆    ╲
 * mem[1]     :                    ╲ b   ┆    ╱
 *                                       ┆     ┆
 *              ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐ 
 * rdclk_i    : ┘  └──┘  └──┘  └──┘  └──┘  └──┘  └─
 *                                ╱    ╲╱    ╲
 * q_o        :                   ╲ a  ╱╲ b  ╱
 *
 */
module mesochronous_synchronizer
#(
  parameter int DATA_SIZE       = 32,
  parameter int REGISTERED_OUTPUT = "NO"
)
(
  input  logic                  wrrst_ni,
  input  logic                  wrclk_i,
  input  logic [DATA_SIZE -1:0] d_i,

  input  logic                  rdrst_ni,
  input  logic                  rdclk_i,
  output logic [DATA_SIZE -1:0] q_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  
  logic [DATA_SIZE -1:0] memory [2];
  logic                  wrptr, rdptr;

  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //


  /* Write Pointer
   * wrptr has a Hamming distance of 3
   */
  always @(posedge wrclk_i, negedge wrrst_ni)
    if      (!wrrst_ni) wrptr <= 1'b0;
    else if ( wrptr   ) wrptr <= 1'b0;
    else                wrptr <= 1'b1;

  always @(posedge wrclk_i)
    memory[wrptr] <= d_i;


  /* Read Pointer
   * rdptr has a hamming distance of 3
   */
  always @(posedge rdclk_i, negedge rdrst_ni)
    if      (!rdrst_ni) rdptr <= 1'b1;
    else if ( rdptr   ) rdptr <= 1'b0;
    else                rdptr <= 1'b1;


generate
if (REGISTERED_OUTPUT != "NO")
  always @(posedge rdclk_i)
    q_o <= memory[rdptr];

else
  assign q_o = memory[rdptr];

endgenerate

endmodule : mesochronous_synchronizer
