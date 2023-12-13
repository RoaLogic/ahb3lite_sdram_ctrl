/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    Synchronizer Flipflop chain.                                 //
//    Replace with technology specific implementation, if required //
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
// FILE NAME      : synchronizer.sv
// DEPARTMENT     :
// AUTHOR         : rherveille
// AUTHOR'S EMAIL :
// ------------------------------------------------------------------
// RELEASE HISTORY
// VERSION DATE        AUTHOR      DESCRIPTION
// 1.0     2023-11-09  rherveille  initial release
// ------------------------------------------------------------------
// KEYWORDS : Clock Domain Crossing Synchronizer Flipflop
// ------------------------------------------------------------------
// PURPOSE  : Cross Clock Domain Synchronizer Flipflops
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  STAGES            2+       Number of DFF stages     2       DFFs
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

module synchronizer
#(
  parameter int STAGES = 2
)
(
  input  logic rst_ni,
  input  logic clk_i,
  input  logic d_i,
  output logic q_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  logic [STAGES -1:0] synchronizer_flipflops;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //
generate
if (STAGES == 0)
begin

  initial $display ("WARNING: Zero synchronisation stages. At least 2 recommended (%m)");
  assign q_o = d_i;

end
else if (STAGES == 1)
begin

  initial $display ("WARNING: One synchronisation stage. At least 2 recommended (%m)");

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) synchronizer_flipflops[0] <= 1'b0;
    else         synchronizer_flipflops[0] <= d_i; 

  assign q_o = synchronizer_flipflops[0];

end
else
begin

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) synchronizer_flipflops <= {STAGES{1'b0}};
    else         synchronizer_flipflops <= {d_i, synchronizer_flipflops[STAGES-1:1]}; 

  assign q_o = synchronizer_flipflops[0];

end
endgenerate

endmodule : synchronizer
