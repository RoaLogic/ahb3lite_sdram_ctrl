/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    SystemVerilog package                                        //
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
 
/************************************************
 * SDRAM Controller Package
 */
package sdram_ctrl_pkg;

  /* SDRAM Commands
   */
  typedef enum logic [4:0] {
    //CKE CSn RASn CASn WEn
    CMD_DESL = 5'b11xxx,         //Device deselect
    CMD_NOP  = 5'b10111,         //No operation
    CMD_BST  = 5'b10110,         //Burst stop
    CMD_RD   = 5'b10101,         //Read
    CMD_WR   = 5'b10100,         //Write
    CMD_ACT  = 5'b10011,         //Bank active
    CMD_PRE  = 5'b10010,         //Precharge
    CMD_REF  = 5'b10001,         //Auto refresh
    CMD_SELF = 5'b00001,         //Self-refresh
    CMD_MRS  = 5'b10000          //Mode Register Set
  } sdram_cmds_t;


  /* CSR Definitions
   */
  typedef struct packed {
    logic       ena;       //Enable SDRAM controller
    logic       init_done; //Initial/Startup delay done (read only)
    logic [1:0] mode;      //00:normal mode
                           //01:precharge command
                           //10:auto-refresh mode
                           //11:set mode register
    logic       pp;        //0:allow normal and privileged access to CSRs
                           //1:allow privileged access only. Normal access=error
    logic       reserved26;
    logic [1:0] rows;      //00:11 rows
                           //01:12 rows
                           //10:13 rows
                           //11:14 rows (just for completeness)
    logic [1:0] burst_size;//00: 1
                           //01: 2
                           //10: 4
                           //11: 8
    logic [1:0] cols;      //00: 8 cols
                           //01: 9 cols
                           //10:10 cols
                           //11:11 cols
    logic       iam;       //0:linear bank addressing
                           //1:interleaved bank addressing
    logic       ap;        //auto-precharge on read/write
    logic [1:0] dqsize;    //00: 16bits on DQ[ 15:0]
                           //01: 32bits on DQ[ 31:0]
                           //10: 64bits on DQ[ 63:0]
                           //11:128bits on DQ[127:0]
    logic [15:4] reserved15_4;
    logic [ 3:0] writebuffer_timeout; //in 2^writebuffer count
                                      //a value of zero disables the write buffer timer
  } csr_ctrl_t;
 
  typedef struct packed {
    logic [ 4:0] reserved31_27;
    logic [ 2:0] tRDV;     //Read Command to data valid delay
                           //This is the total delay from the command-out until the 
                           //data is received. This includes PHY and PCB delays, but not CL
    logic        btac;     //Bus Turnaround Cycle. Add an additional cycle between RD-to-WR commands
    logic        reserved22;
    logic [ 1:0] cl;       //cas latency; 00:reserved, 01:CL1, 10:CL2, 11:CL3
    logic [ 3:0] tDAL;     //Input data to REFR/ACT (during auto precharge)
    logic [ 3:0] tRAS;     //Command Period; ACT-to-PRE
    logic [ 3:0] tRP;      //Precharge period; PRE-to-ACT
    logic [ 3:0] tRCD;     //Active-to-Read/Write period
    logic [ 3:0] tRC;      //Active-to-Active period =max(tRC,tRCF)
  } csr_timing_t;

  typedef struct packed {
    csr_ctrl_t   ctrl;
    csr_timing_t timing;
    logic [15:0] tREF;  //AHB clock cycles until next refres
  } csr_t;



  /* Internal
   */
  localparam BANK_STATUS_IDLE       = 1'b0;
  localparam BANK_STATUS_ACTIVE     = 1'b1;
  localparam BANK_STATUS_ALL_IDLE   = 4'h0;
  localparam BANK_STATUS_ALL_ACTIVE = 4'hf;

endpackage



