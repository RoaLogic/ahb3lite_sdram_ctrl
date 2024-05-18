/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    Command Scheduler                                            //
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
// FILE NAME      : sdram_cmd_scheduler.sv
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
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : external asynchronous active low; sdram_rst_ni
//   Clock Domains       : sdram_clk_i, rising edge
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
// apb_csr.*             csr_o                 false path
//

module sdram_cmd_scheduler
import sdram_ctrl_pkg::*;
#(
  parameter int PORTS           = 1,
  parameter int CTRL_PORT       = 1,
  parameter int ADDR_SIZE       = 32,
  parameter int WDATA_SIZE      = 32,

  parameter int SDRAM_ADDR_SIZE = 11,
  parameter int SDRAM_BA_SIZE   = 2,
  parameter int SDRAM_DQ_SIZE   = 16,
  parameter int MAX_RSIZE       = 13,
  parameter int MAX_CSIZE       = 11
)
(
  input  logic                       rst_ni,
  input  logic                       clk_i,

  input  logic                       wbr_i      [PORTS], 
  input  logic                       rdreq_i    [PORTS],
  output logic                       rdrdy_o    [PORTS],
  input  logic [ADDR_SIZE      -1:0] rdadr_i    [PORTS],
  input  logic [SDRAM_BA_SIZE  -1:0] rdba_i     [PORTS],
  input  logic [MAX_RSIZE      -1:0] rdrow_i    [PORTS],
  input  logic [MAX_CSIZE      -1:0] rdcol_i    [PORTS],
  input  logic [                7:0] rdsize_i   [PORTS],
  output logic [SDRAM_DQ_SIZE  -1:0] rdq_o      [PORTS],
  output logic                       rdqvalid_o [PORTS],

  input  logic                       wrreq_i    [PORTS],
  output logic                       wrrdy_o    [PORTS],
  input  logic [SDRAM_BA_SIZE  -1:0] wrba_i     [PORTS],
  input  logic [MAX_RSIZE      -1:0] wrrow_i    [PORTS],
  input  logic [MAX_CSIZE      -1:0] wrcol_i    [PORTS],
  input  logic [                2:0] wrsize_i   [PORTS],
  input  logic [WDATA_SIZE/8   -1:0] wrbe_i     [PORTS],
  input  logic [WDATA_SIZE     -1:0] wrd_i      [PORTS],

  //Transfer mode/setting are in CSRs
  input  csr_t                 csr_i,

  output sdram_cmds_t                sdram_cmd_o,
  output logic [                1:0] sdram_ba_o,
  output logic [SDRAM_ADDR_SIZE-1:0] sdram_addr_o,
  input  logic [SDRAM_DQ_SIZE  -1:0] sdram_dq_i,
  output logic [SDRAM_DQ_SIZE  -1:0] sdram_dq_o,
  output logic                       sdram_dqoe_o,
  output logic [SDRAM_DQ_SIZE/8-1:0] sdram_dm_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  function automatic int max(input int a, input int b);
    max = a > b ? a : b;
  endfunction : max

  function automatic int min(input int a, input int b);
    min = a < b ? a : b;
  endfunction : min


  localparam int PORTS_BITS    = $clog2(PORTS) +1;
  localparam int BANKS         = 1 << SDRAM_BA_SIZE;

  //There are WDATA_SIZE/8 bytes
  //Minimum DQ size is 16bits (2 bytes)
  localparam int WDATA_XFER_CNT_SIZE = $clog2(WDATA_SIZE /16) +1;
  localparam int XFER_CNT_SIZE       = max(WDATA_XFER_CNT_SIZE, 8);


  //////////////////////////////////////////////////////////////////
  //
  // Type definitions
  //
  typedef enum logic {
    ST_IDLE = 1'b0,
    ST_REF  = 1'b1
  } states_t;
  
  typedef struct packed {
    logic                  valid;
    logic [PORTS_BITS-1:0] port;
    logic [           2:0] xfer_size;
  } rdcmd_t;

 
  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function [PORTS_BITS-1:0] priority_port;
    input [PORTS-1:0] ports;

    //prevent latch behaviour
    priority_port = 0;

    //port0 has highest priority
    for (int p=0; p < PORTS; p++) if (ports[p]) return p;
  endfunction //onehot2int

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  logic [BANKS          -1:0] bank_nxt_status, bank_status;
  logic [MAX_RSIZE      -1:0] bank_nxt_row   [BANKS];
  logic [MAX_RSIZE      -1:0] bank_row       [BANKS];  //active row per bank

  logic [                3:0] tRAS_cnt       [BANKS];  //Command Period, ACT-to-PRE (per bank)
  logic [BANKS          -1:0] tRAS_load;
  logic [BANKS          -1:0] tRAS_done;
  logic [                5:0] tRP_cnt        [BANKS];  //Precharge Period, PRE-to-ACT (per bank)
  logic [                5:0] tRP_load_val;
  logic [BANKS          -1:0] tRP_load;
  logic [BANKS          -1:0] tRP_done;
  logic [                2:0] tRCD_cnt       [BANKS];  //ACT-to-RD/WR (per bank);
  logic [BANKS          -1:0] tRCD_load;
  logic [BANKS          -1:0] tRCD_done;
  logic [                3:0] tRC_cnt        [BANKS];
  logic [BANKS          -1:0] tRC_load;
  logic [BANKS          -1:0] tRC_done;
  logic [                2:0] tRRD_cnt;
  logic                       tRRD_load;
  logic                       tRRD_done;
  logic [                3:0] tRFC_cnt;                //REF-to-REF/ACT-to-ACT
  logic                       tRFC_load;
  logic                       tRFC_done;
  logic [                5:0] tWR_cnt        [BANKS];  //Last data to Precharge
  logic [                5:0] tWR_load_val;
  logic [BANKS          -1:0] tWR_load;
  logic [BANKS          -1:0] tWR_done;
  logic [                3:0] CL_cnt;
  logic                       CL_load;
  logic                       CL_done;
  rdcmd_t                     rdcmd_queue [11];
  logic [                2:0] rdcmd_queue_cnt;
  logic                       rdcmd_queue_cnt_done;

  logic [               15:0] refresh_cnt;
  logic [                3:0] refreshes_pending;
  logic                       refresh_now;
  logic                       refreshing;

  logic [WDATA_SIZE     -1:0] xfer_dq_wbuf;
  logic [WDATA_SIZE/8   -1:0] xfer_dm_wbuf;
 
  logic [XFER_CNT_SIZE  -1:0] xfer_cnt,                //Total number of transfers
                              xfer_cnt_ld_val;
  logic                       xfer_cnt_ld;
  logic                       xfer_cnt_done;
  logic                       xfer_cnt_last_burst;
  logic [MAX_CSIZE      -1:0] xfer_col;
  logic                       xfering;
  logic [PORTS_BITS     -1:0] active_nxt_port, active_port;
  logic                       active_nxt_rd, active_rd,
                              active_nxt_wr, active_wr;
  logic [                2:0] burst_cnt;               //Number of transfers per WR/RD command
  logic [                2:0] burst_cnt_int_val;
  logic                       burst_cnt_load;
  logic                       burst_cnt_done;
  logic                       burst_terminate;         //read less than csr_i.ctrl.burst_size
  logic [                4:0] burst_cnt_rd2wr;         //Number of cycles when a WR can be issues afer a RD
  logic                       burst_cnt_rd2wr_done;
  logic [                5:0] burst_cnt_wr2rd;         //Number of cycles when a RD can be issues after a WR
  logic                       burst_cnt_wr2rd_done;

  //Oops incomplete transfer
  logic                       xfer_incomplete;
  logic [PORTS_BITS     -1:0] xfer_incomplete_port;
  logic [                4:0] xfer_incomplete_size;
  logic [                1:0] xfer_incomplete_ba;

  logic [PORTS          -1:0] rdreq_nowbr,
                              rdreq_nowbr_act_bank;
  logic [PORTS_BITS     -1:0] rdport;
  logic                       rd_pending;
  logic                       rdrdy          [PORTS];

  logic [PORTS          -1:0] wrreq,
                              wrreq_bank_act;
  logic [PORTS_BITS     -1:0] wrport;
  logic                       wr_pending;

  states_t                    nxt_state,         state;
  sdram_cmds_t                sdram_nxt_cmd,     sdram_cmd;
  logic [SDRAM_ADDR_SIZE-1:0] sdram_nxt_addr,    sdram_addr;
  logic [MAX_CSIZE      -1:0] sdram_nxt_col;
  logic [SDRAM_BA_SIZE  -1:0] sdram_nxt_ba,      sdram_ba,
                              sdram_nxt_rdwr_ba, sdram_rdwr_ba;
//  logic [SDRAM_DQ_SIZE  -1:0] sdram_dq;
//  logic [SDRAM_DQ_SIZE/8-1:0] sdram_dm;
  logic                       sdram_dqoe;


  genvar port, bank;


  //////////////////////////////////////////////////////////////////
  //
  // Statemachine tasks
  //
  // NOTE: Tasks must use 'input' to ensure all signals are included
  //       in the always_comb sensitivity list

  task automatic cmd_none_task;
    //In FSM: brings nxt_state decoder in start configuration
    //In tasks: resets assignments from earlier tasks (latest task has highest priority)
    nxt_state           = state;

    sdram_nxt_cmd       = CMD_NOP;
    sdram_nxt_addr      = sdram_addr;
    sdram_nxt_ba        = sdram_ba;
    sdram_nxt_rdwr_ba   = sdram_rdwr_ba;
    sdram_nxt_col       = {$bits(sdram_nxt_col){1'bx}};
    bank_nxt_status     = bank_status;

    for (int bank = 0; bank < 4; bank++)
      bank_nxt_row[bank] = bank_row[bank];

    refreshing          = 1'b0;
    active_nxt_wr       = 1'b0;
    active_nxt_rd       = 1'b0;

    tRAS_load           = {BANKS{1'b0}};
    tRP_load            = {BANKS{1'b0}};
    tRP_load_val        = { {$bits(tRP_cnt[0])-$bits(csr_i.timing.tRP){1'b0}}, csr_i.timing.tRP };
    tRCD_load           = {BANKS{1'b0}};
    tRRD_load           = 1'b0;
    tRC_load            = {BANKS{1'b0}};
    tRFC_load           = 1'b0;
    tWR_load_val        = (3'h4 << csr_i.ctrl.burst_size)
                          + csr_i.timing.tWR;
    tWR_load            = {BANKS{1'b0}};
    burst_cnt_load      = 1'b0;
    xfer_cnt_ld         = 1'b0;
    xfer_cnt_ld_val     = {$bits(xfer_cnt_ld_val){1'bx}};
  endtask


  task automatic cmd_ref_task;
    cmd_none_task();

    nxt_state     = ST_IDLE;
    sdram_nxt_cmd = CMD_REF;
    tRFC_load     = 1'b1;
    refreshing    = 1'b1;
  endtask 


  task automatic cmd_pre_all_task;
    cmd_none_task();

    sdram_nxt_cmd      = CMD_PRE;
    sdram_nxt_addr[10] = 1'b1;
    tRP_load           = {BANKS{1'b1}};
    bank_nxt_status    = BANK_STATUS_ALL_IDLE;
  endtask


  task automatic cmd_pre_task;
    input [SDRAM_BA_SIZE-1:0] ba;

    cmd_none_task();
    
    sdram_nxt_cmd       = CMD_PRE;
    sdram_nxt_addr [10] = 1'b0;
    sdram_nxt_ba        = ba;
    tRP_load       [ba] = 1'b1;
    bank_nxt_status[ba] = BANK_STATUS_IDLE;
  endtask


  task automatic cmd_act_task;
    input [SDRAM_BA_SIZE-1:0] ba;
    input [MAX_RSIZE    -1:0] row;

    cmd_none_task();

    sdram_nxt_cmd       = CMD_ACT;
    sdram_nxt_addr      = row;
    sdram_nxt_ba        = ba;
    tRAS_load      [ba] = 1'b1;
    tRCD_load      [ba] = 1'b1;
    tRC_load       [ba] = 1'b1;
    tRRD_load           = 1'b1;
    bank_nxt_status[ba] = BANK_STATUS_ACTIVE;
    bank_nxt_row   [ba] = row;
  endtask


  task automatic cmd_terminate;
    cmd_none_task();

    sdram_nxt_cmd      = CMD_BST;
  endtask


  task automatic cmd_wr_task;
    input [PORTS_BITS   -1:0] port;
    input [SDRAM_BA_SIZE-1:0] ba;
    input [MAX_CSIZE    -1:0] col;
    input                     ap;
    input [              1:0] dqsize;
    input                     last_burst;

    logic go_ap;

    cmd_none_task();

    go_ap               = ap & last_burst;

    sdram_nxt_cmd       = CMD_WR;
    sdram_nxt_addr      = col;
    sdram_nxt_addr [10] = go_ap;
    sdram_nxt_ba        = ba;
    sdram_nxt_rdwr_ba   = ba;
    sdram_nxt_col       = col;
    tRP_load       [ba] = go_ap;
//Calculate tRP
//    tRAS
//and tWR cycle(s) after last valid data
//or  interrupted by read or write (with or without auto precharge)
    tRP_load_val        = tRAS_cnt[port]
                          + (3'h4 << csr_i.ctrl.burst_size)
                          + csr_i.timing.tWR;
    tWR_load       [ba] = 1'b1; //~go_ap, but we don't issue a PRE if the bank is auto-precharged
    bank_nxt_status[ba] = go_ap ? BANK_STATUS_IDLE : bank_status[ba];

    burst_cnt_load      = 1'b1;

    xfer_cnt_ld         = 1'b1;
    xfer_cnt_ld_val     = (WDATA_SIZE/16 >> dqsize) -1'h1; //WDATA/(16 * 2^dqsize)
    active_nxt_port     = port;
    active_nxt_wr       = 1'b1;
  endtask


  task automatic cmd_rd_task;
    input [PORTS_BITS   -1:0] port;
    input [SDRAM_BA_SIZE-1:0] ba;
    input [MAX_CSIZE    -1:0] col;
    input [              7:0] rdsize;
    input                     ap;
    input [              1:0] dqsize;
    input                     last_burst;

    logic go_ap;

    cmd_none_task();

    go_ap               = ap & (~|rdsize | last_burst);

    sdram_nxt_cmd       = CMD_RD;
    sdram_nxt_addr      = col;
    sdram_nxt_addr [10] = go_ap;
    sdram_nxt_ba        = ba;
    sdram_nxt_rdwr_ba   = ba;
    sdram_nxt_col       = col;
    tRP_load       [ba] = go_ap;
//Calculate tRP
//    tRAS
//and CAS Latency -1 cycles before last burst
//or  interrupted by read or write (with or without auto precharge)
    tRP_load_val        = tRAS_cnt[port]
                          + (3'h4 << csr_i.ctrl.burst_size) - (csr_i.timing.cl -1'h1)
                          + csr_i.timing.tRP;
    bank_nxt_status[ba] = go_ap ? BANK_STATUS_IDLE : bank_status[ba];

    burst_cnt_load      = 1'b1;

    xfer_cnt_ld         = 1'b1;
    xfer_cnt_ld_val     = rdsize;
    active_nxt_port     = port;
    active_nxt_rd       = 1'b1;
  endtask



  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

 /* counters
  */
generate
  for (bank=0; bank < 4; bank++)
  begin: gen_tCnt
      //tRAS
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni)
        begin
            tRAS_cnt [bank] <= {$bits(tRAS_cnt[bank]){1'b0}};
            tRAS_done[bank] <= 1'b0;
        end
        else if (tRAS_load[bank])
        begin
            tRAS_cnt [bank] <=   csr_i.timing.tRAS;
            tRAS_done[bank] <= ~|csr_i.timing.tRAS;
        end
        else if (!tRAS_done[bank])
        begin
            tRAS_cnt [bank] <= tRAS_cnt[bank] -1'h1;
            tRAS_done[bank] <= tRAS_cnt[bank] == 1'h1;
        end


      //tRP
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni)
        begin
            tRP_cnt [bank] <= {$bits(tRP_cnt[bank]){1'b0}};
            tRP_done[bank] <= 1'b0;
        end
        else if (tRP_load[bank])
        begin
            tRP_cnt [bank] <=  tRP_load_val;
            tRP_done[bank] <= ~|tRP_load_val;
        end
        else if (!tRP_done[bank])
        begin
            tRP_cnt [bank] <= tRP_cnt[bank] -1'h1;
            tRP_done[bank] <= tRP_cnt[bank] == 1'h1;
        end


      //tRCD
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni)
        begin
            tRCD_cnt [bank] <= {$bits(tRCD_cnt[bank]){1'b0}};
            tRCD_done[bank] <= 1'b0;
        end
        else if (tRCD_load[bank])
        begin
            tRCD_cnt [bank] <=   csr_i.timing.tRCD;
            tRCD_done[bank] <= ~|csr_i.timing.tRCD;
        end
        else if (!tRCD_done[bank])
        begin
            tRCD_cnt [bank] <= tRCD_cnt[bank] -1'h1;
            tRCD_done[bank] <= tRCD_cnt[bank] == 1'h1;
        end


      //tRC
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni)
        begin
            tRC_cnt [bank] <= {$bits(tRC_cnt[bank]){1'b0}};
            tRC_done[bank] <= 1'b0;
        end
        else if (tRC_load[bank])
        begin
            tRC_cnt [bank] <=   csr_i.timing.tRC;
            tRC_done[bank] <= ~|csr_i.timing.tRC;
        end
        else if (!tRC_done[bank])
        begin
            tRC_cnt [bank] <= tRC_cnt[bank] -1'h1;
            tRC_done[bank] <= tRC_cnt[bank] == 1'h1;
        end


      //tWR
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni)
        begin
            tWR_cnt [bank] <= {$bits(tWR_cnt[bank]){1'b0}};
            tWR_done[bank] <= 1'b0;
        end
        else if (tWR_load[bank])
        begin
            tWR_cnt [bank] <=   tWR_load_val;
            tWR_done[bank] <= ~|tWR_load_val;
        end
        else if (!tWR_done[bank])
        begin
            tWR_cnt [bank] <= tWR_cnt[bank] -1'h1;
            tWR_done[bank] <= tWR_cnt[bank] == 1'h1;
        end

  end
endgenerate

  //tRRD
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        tRRD_cnt  <= {$bits(tRRD_cnt){1'b0}};
        tRRD_done <= 1'b0;
    end
    else if (tRRD_load)
    begin
        tRRD_cnt  <=   csr_i.timing.tRRD;
        tRRD_done <= ~|csr_i.timing.tRRD;
    end
    else if (!tRRD_done)
    begin
        tRRD_cnt  <= tRRD_cnt -1'h1;
        tRRD_done <= tRRD_cnt == 1'h1;
    end


  //tRCF
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        tRFC_cnt  <= {$bits(tRFC_cnt){1'b0}};
        tRFC_done <= 1'b0;
    end
    else if (tRFC_load)
    begin
        tRFC_cnt  <=   csr_i.timing.tRFC;
        tRFC_done <= ~|csr_i.timing.tRFC;
    end
    else if (!tRFC_done)
    begin
        tRFC_cnt  <= tRFC_cnt -1'h1;
        tRFC_done <= tRFC_cnt == 1'h1;
    end


  /* Refresh counter
   */
  always @(posedge clk_i, negedge rst_ni)
    if      ( !rst_ni        ) refresh_cnt <= 16'd127;
    else if ( !csr_i.ctrl.ena) refresh_cnt <= 16'd127;
    else if (~|refresh_cnt   ) refresh_cnt <= csr_i.tREF;
    else                       refresh_cnt <= refresh_cnt -1'h1;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni) refreshes_pending <= {$bits(refreshes_pending){1'b0}};
    else
    case ( {~|refresh_cnt, refreshing & |refreshes_pending} )
      2'b00: ;
      2'b01: refreshes_pending <= refreshes_pending -1'h1;
      2'b10: refreshes_pending <= refreshes_pending +1'h1;
      2'b11: ;
    endcase


  assign refresh_now = &refreshes_pending;


  /*Burst Counters
   */
  assign burst_cnt_int_val = (3'h4 << csr_i.ctrl.burst_size) -1'h1;

  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        burst_cnt      <= {$bits(burst_cnt){1'b0}};
        burst_cnt_done <= 1'b0;
    end
    else if (burst_cnt_load)
    begin
        burst_cnt      <= burst_cnt_int_val;
        burst_cnt_done <= 1'b0;//~|csr_i.ctrl.burst_size;
    end
    else if (burst_terminate)
    begin
        burst_cnt_done <= 1'b1;
    end
    else if (!burst_cnt_done)
    begin
        burst_cnt      <= burst_cnt -1'h1;
        burst_cnt_done <= burst_cnt == 1'h1;
    end


  //Write-to-Read command
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        burst_cnt_wr2rd      <= {$bits(burst_cnt_wr2rd){1'b0}};
        burst_cnt_wr2rd_done <= 1'b0;
    end
   else if (burst_cnt_load && active_nxt_wr)
    begin
        burst_cnt_wr2rd      <= burst_cnt_int_val - csr_i.timing.cl;
        burst_cnt_wr2rd_done <= 1'b0; //{1'b1,csr_i.ctrl.burst_size} < csr_i.timing.cl;
    end
    else if (burst_terminate)
    begin
        burst_cnt_wr2rd      <= csr_i.timing.cl -1'h1;
	burst_cnt_wr2rd_done <= 1'b0;
    end
    else if (!burst_cnt_wr2rd_done)
    begin
        burst_cnt_wr2rd      <=  burst_cnt_wr2rd -1'h1;
        burst_cnt_wr2rd_done <= (burst_cnt_wr2rd == 1'h1);
    end


  //Read-to-Write command
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        burst_cnt_rd2wr      <= {$bits(burst_cnt_rd2wr){1'b0}};
        burst_cnt_rd2wr_done <= 1'b0;
    end
   else if (burst_cnt_load && active_nxt_rd)
    begin
        burst_cnt_rd2wr      <= burst_cnt_int_val + csr_i.timing.tRDV + csr_i.timing.cl + csr_i.timing.btac;
        burst_cnt_rd2wr_done <= 1'b0;
    end
    else if (burst_terminate)
    begin
        burst_cnt_rd2wr      <= csr_i.timing.cl + csr_i.timing.tRDV + csr_i.timing.btac -1'h1;
	burst_cnt_rd2wr_done <= 1'b0;
    end
    else if (!burst_cnt_rd2wr_done)
    begin
        burst_cnt_rd2wr      <=  burst_cnt_rd2wr -1'h1;
        burst_cnt_rd2wr_done <= (burst_cnt_rd2wr == 1'h1);
    end


  //Read Command queue (for rdqvalid)
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
        for (int r=0; r < $size(rdcmd_queue); r++)
          rdcmd_queue[r] <= {$bits(rdcmd_t){1'b0}};
    else
    begin
        rdcmd_queue[$size(rdcmd_queue)-1] <= {$bits(rdcmd_t){1'b0}};

        for (int r=0; r < $size(rdcmd_queue) -1; r++)
          rdcmd_queue[r] <= rdcmd_queue[r+1];

        if (burst_cnt_load && active_nxt_rd)
        begin
            rdcmd_queue[csr_i.timing.tRDV + csr_i.timing.cl].valid     <= 1'b1;
            rdcmd_queue[csr_i.timing.tRDV + csr_i.timing.cl].port      <= rdport;
            rdcmd_queue[csr_i.timing.tRDV + csr_i.timing.cl].xfer_size <= xfer_cnt_ld
                                                                            ? min(xfer_cnt_ld_val, burst_cnt_int_val)
                                                                            : burst_cnt_int_val;
        end
    end

  //Read Command Queue counters (rdqvalid)
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        rdcmd_queue_cnt      <= {$bits(rdcmd_queue_cnt){1'b0}};
        rdcmd_queue_cnt_done <= 1'b1;

        for (int p=0; p < $size(rdqvalid_o); p++)
          rdqvalid_o[p] <= 1'b0;
    end
    else if (rdcmd_queue[1].valid)
    begin
        rdcmd_queue_cnt      <= rdcmd_queue[1].xfer_size +1'h1;
        rdcmd_queue_cnt_done <= 1'b0;

        for (int p=0; p < $size(rdqvalid_o); p++)
          rdqvalid_o[p] <= 1'b0;

        rdqvalid_o[rdcmd_queue[1].port] <= 1'b1;
    end
    else if (!rdcmd_queue_cnt_done)
    begin
        rdcmd_queue_cnt      <= rdcmd_queue_cnt -1'h1;
        rdcmd_queue_cnt_done <= rdcmd_queue_cnt == 1'h1;

        for (int p=0; p < $size(rdqvalid_o); p++)
          rdqvalid_o[p] <= 1'b0;

        rdqvalid_o[rdcmd_queue[1].port] <= rdcmd_queue_cnt != 1'h1;
    end


  /*Transfer Counter
   */
  always @(posedge clk_i, negedge rst_ni)
    if      (!rst_ni        ) xfering <= 1'b0;
    else if ( burst_cnt_load) xfering <= 1'b1;
    else if ( burst_cnt_done) xfering <= 1'b0;


  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        xfer_cnt            <= {$bits(xfer_cnt){1'b0}};
        xfer_cnt_done       <= 1'b1;
        xfer_cnt_last_burst <= 1'b0;
        xfer_col            <= {$bits(xfer_col){1'bx}};
    end
    else if (|xfer_cnt)
    begin
        if (xfering)
        begin
            xfer_cnt            <=  xfer_cnt -1'h1;
            xfer_cnt_done       <= (xfer_cnt == 1'h1);
            xfer_cnt_last_burst <= (xfer_cnt == (3'h4 << csr_i.ctrl.burst_size) +1'h1);
            xfer_col            <=  xfer_col +1'h1;
        end
    end
    else if (xfer_cnt_ld) //ignore xfer_cnt_ld if current transfer not done
    begin
        xfer_cnt            <=   xfer_cnt_ld_val;
        xfer_cnt_done       <= ~|xfer_cnt_ld_val;
        xfer_cnt_last_burst <=   xfer_cnt_ld_val <= (3'h4 << csr_i.ctrl.burst_size);
//        xfer_col            <=   sdram_nxt_addr[0 +: $bits(xfer_col)] +1'h1; //store (next) sdram column
        xfer_col            <=   sdram_nxt_col + 1'h1; //use dedicated sdram_nxt_col to reduce critical path
    end
    else
    begin
        xfer_cnt_done       <= 1'b1;
        xfer_cnt_last_burst <= 1'b0;
    end

    //terminate burst
    assign burst_terminate = xfer_cnt_done & ~burst_cnt_done;


    /* Handle incomplete reads
       This can happen when a readburst doesn't start at a burst boundary and the xfer-size > burst-size
     */
    always @(posedge clk_i, negedge rst_ni)
      if      (!rst_ni             ) xfer_incomplete <= 1'b0;
      else if ( xfer_cnt_ld        ) xfer_incomplete <= 1'b0;
      else if ( xfer_cnt_last_burst) xfer_incomplete <= active_rd & (xfer_cnt > burst_cnt);

    always @(posedge clk_i)
      if (xfer_cnt_last_burst)
      begin
          xfer_incomplete_port <= active_port;
          xfer_incomplete_size <= xfer_cnt - burst_cnt -1'h1;
          xfer_incomplete_ba   <= rdba_i [active_port];
      end


  /* RDRDY
   */
generate
  for (port=0; port < PORTS; port++)
  begin: gen_rdrdy
      //rdrdy generation
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni) rdrdy_o[port] <= 1'b0;
        else
        case (csr_i.ctrl.mode)
          2'b00: //normal mode
            case (rdrdy_o[port])
              1'b0: if ( rdreq_nowbr[port] && (port == rdport) && active_rd &&
                         (
                           (                 xfer_cnt_last_burst                              ) ||
                           ( xfer_cnt_ld && (xfer_cnt_ld_val <= (3'h4 << csr_i.ctrl.burst_size)) )
                         )
                       )
                      rdrdy_o[port] <= 1'b1;

              1'b1: rdrdy_o[port] <= 1'b0;
            endcase

          default: rdrdy_o[port] <= rdrdy[port];
        endcase
  end
endgenerate


  /* WRRDY, Transfer Buffers (write)
   */
generate
  for (port=0; port < PORTS; port++)
  begin: gen_wrrdy
      //wrrdy generation
      always @(posedge clk_i, negedge rst_ni)
        if (!rst_ni) wrrdy_o[port] <= 1'b0;
        else
        case (wrrdy_o[port])
          1'b0: if ((port == wrport) && active_wr && xfer_cnt_last_burst && !refresh_now)
                  wrrdy_o[port] <= 1'b1;

          1'b1: wrrdy_o[port] <= 1'b0;
        endcase
  end
endgenerate


  //Byte-enable transfer buffer
  //DQM has 2 cycle latency for READ
  //DQM has 0 cycle latency for WRITE
  always @(posedge clk_i)
    if ((active_rd || active_nxt_rd) && !burst_terminate)
    begin
        //do not mask read transfers
        xfer_dm_wbuf <= {$bits(xfer_dm_wbuf){1'b0}};
    end
    else if ( !(active_wr || active_nxt_wr) )
    begin
        //nomansland; mask transfers
        xfer_dm_wbuf <= {$bits(xfer_dm_wbuf){1'b1}};
    end
    else //write
    begin
        if (wrreq_i[wrport] && xfer_cnt_done) xfer_dm_wbuf <= ~wrbe_i[wrport];
        else                                  xfer_dm_wbuf <=  xfer_dm_wbuf >> (2'h2 << csr_i.ctrl.dqsize);
    end


  //Write transfer buffer
  always @(posedge clk_i)
    if (wrreq_i[wrport] && xfer_cnt_done) xfer_dq_wbuf <= wrd_i [wrport];
    else                                  xfer_dq_wbuf <= xfer_dq_wbuf >> (5'd16 << csr_i.ctrl.dqsize);


  /* Internal signals
   */
generate
  for (port=0; port < PORTS; port++)
  begin: gen_req
      assign rdreq_nowbr[port] = rdreq_i[port] & ~wbr_i[port] & ~rdrdy_o[port];
      assign wrreq[port]       = wrreq_i[port];

      assign rdreq_nowbr_act_bank[port] = rdreq_nowbr[port] & (
                                            (bank_status[rdba_i[port]] == BANK_STATUS_ACTIVE) &
                                            (bank_row   [rdba_i[port]] == rdrow_i[port])
                                          );
      assign wrreq_bank_act[port]       = wrreq[port] & (
                                            (bank_status[wrba_i[port]] == BANK_STATUS_ACTIVE) &
                                            (bank_row   [wrba_i[port]] == wrrow_i[port])
                                          );
  end
endgenerate

  assign rdport = priority_port(rdreq_nowbr);
  assign wrport = priority_port(wrreq);
//  assign rdport_act = priority_port(rdreq_nowbr & 



  /* Command Scheduler State Machine
   */
  always_comb
    begin
        cmd_none_task();
        active_nxt_port     = active_port & ~{$bits(active_port){xfer_cnt_done}};
//        active_nxt_rd       = active_rd & ~xfer_cnt_done;
//        active_nxt_wr       = active_wr & ~xfer_cnt_done;

        for (int port = 0; port < PORTS; port++)
        begin
            rdrdy[port] = 1'b0;
        end

        casex ( {csr_i.ctrl.mode, state} )
          { 2'b11,{$bits(state){1'bx}} }:
             //Set Mode Register Mode
             if (rdreq_i[CTRL_PORT] && !rdrdy_o[CTRL_PORT] && tRFC_done)
             begin
                 sdram_nxt_cmd      = CMD_MRS;
                 sdram_nxt_addr     = rdadr_i[CTRL_PORT][0 +: $bits(sdram_nxt_addr)];
                 sdram_nxt_addr[10] = 1'b0;
                 sdram_nxt_ba       = {SDRAM_BA_SIZE{1'b0}};
                 rdrdy[CTRL_PORT]   = 1'b1;
             end

          { 2'b10,{$bits(state){1'bx}} }:
             //Auto Refresh Mode
             if (rdreq_i[CTRL_PORT] && ~rdrdy_o[CTRL_PORT] && tRP_done[CTRL_PORT] && tRFC_done)
             begin
                 cmd_ref_task();
                 rdrdy[CTRL_PORT] = 1'b1;
             end

          { 2'b01,{$bits(state){1'bx}} }:
             //PrechargeAll Mode
             if (rdreq_i[CTRL_PORT] && !rdrdy_o[CTRL_PORT])
             begin
                 cmd_pre_all_task();
                 rdrdy[CTRL_PORT] = 1'b1;
             end

          { 2'b00,ST_IDLE }:
             begin
                 /*This is in reverse priority order!
                  */

                 //burst terminate
                 if ( burst_terminate ) cmd_terminate();


                 //any refreshes to service?
                 if (|refreshes_pending && &tRP_done && tRFC_done && &tRAS_done && xfer_cnt_done)
                 begin
                     if      ( bank_status == BANK_STATUS_ALL_IDLE) cmd_ref_task();
                     else if (&tWR_done                           ) cmd_pre_all_task();
                 end


                 //any writes with activated banks pending?
                 //any reads with activated banks pending?

                 //any writes pending?
                 if (|wrreq)
                 begin
                     //Is the bank actived with the correct row?
                     if (wrreq_bank_act[wrport])
                     begin
                         if (!active_rd)
                         begin
                             if ( tRCD_done[wrba_i[wrport]])
                             begin
                                 //Write
                                 if ((burst_cnt_done || burst_terminate) && burst_cnt_rd2wr_done)
                                   cmd_wr_task(wrport,
                                               wrba_i [wrport],
                                               xfer_cnt_done ? wrcol_i[wrport] : xfer_col,
                                               csr_i.ctrl.ap,
                                               csr_i.ctrl.dqsize,
                                               xfer_cnt_last_burst);
                             end
                             else cmd_none_task(); //clear previous commands; prevent two actions fighting
                         end
                     end
                     //Is the bank idle (precharged)?
                     else if (bank_status[wrba_i[wrport]] == BANK_STATUS_IDLE)
                     begin
                         //Activate bank, except if a PRE/ACT for a READ is in progress
                         //  in that case, wait and interleave the WRITE-ACT with the READ-NOPs
                         if ( tRP_done[wrba_i[wrport]]      &&
                              tRC_done[wrport] && tRRD_done &&
                              tRFC_done                     &&
                             !(!tRP_done[rdba_i[rdport]] || !tRCD_done[rdba_i[rdport]])
                            ) cmd_act_task(wrba_i[wrport], wrrow_i[wrport]);
                     end
                     //Precharge bank
                     else if (tRAS_done[wrba_i[wrport]] && tWR_done[wrba_i[wrport]] &&
                              (burst_terminate || burst_cnt_done || wrba_i[wrport] != sdram_rdwr_ba)
                             ) cmd_pre_task(wrba_i[wrport]);
                 end


                 //any reads pending?
                 if (|rdreq_nowbr)
                 begin
                     //Is the bank actived with the correct row?
                     if (rdreq_nowbr_act_bank[rdport])
                     begin
                         if (!active_wr)
                         begin
                             if (tRCD_done[rdba_i[rdport]] )
                             begin
                                 //Read
                                 if (burst_cnt_done && burst_cnt_wr2rd_done)
                                    cmd_rd_task(rdport,
                                                rdba_i  [rdport],
                                                xfer_cnt_done ? rdcol_i[rdport] : xfer_col,
                                                rdsize_i[rdport],
                                                csr_i.ctrl.ap,
                                                csr_i.ctrl.dqsize,
                                                xfer_cnt_last_burst);
                             end
                             else cmd_none_task(); //clear previous commands; prevent two actions fighting
                         end
                     end
                     //Is the bank idle (precharged)?
                     else if (bank_status[rdba_i[rdport]] == BANK_STATUS_IDLE)
                     begin
                         //Activate bank, can interleave with WR-NOPs
                         if (!active_nxt_wr                 &&
                              tRP_done[rdba_i[rdport]]      &&
                              tRC_done[rdport] && tRRD_done &&
                              tRFC_done) cmd_act_task(rdba_i[rdport], rdrow_i[rdport]);
                     end
                     //Precharge bank, can interleave with WR-NOPs
                     else if (!active_nxt_wr             &&
                               tRAS_done[rdba_i[rdport]] &&
                               tWR_done[rdba_i[wrport]]  &&
                               (burst_terminate || burst_cnt_done || rdba_i[rdport] != sdram_rdwr_ba)
                             ) cmd_pre_task(rdba_i[rdport]);
                 end


                 //any refreshes to service?
                 if (refresh_now && &tRP_done && tRFC_done)
                 begin
                     if (bank_status == BANK_STATUS_ALL_IDLE) cmd_ref_task();
                     else if (&tWR_done && &tRAS_done)
                     begin
                         cmd_pre_all_task();
                         nxt_state = ST_REF;
                     end
                     else cmd_none_task(); //clear previous commands, ensure we can precharge
                 end


                 //any incomplete reads?
                 if (burst_cnt_done && xfer_incomplete)
                 begin
                     cmd_rd_task(xfer_incomplete_port,
                                 xfer_incomplete_ba,
                                 xfer_col,
                                 xfer_incomplete_size,
                                 csr_i.ctrl.ap,
                                 csr_i.ctrl.dqsize,
                                 1'b1);
                 end

             end

          { 2'b00,ST_REF }: if (tRP_done[0]) cmd_ref_task();

        endcase
    end


  //FSM Registers
  always @(posedge clk_i, negedge rst_ni)
    if (!rst_ni)
    begin
        state         <= ST_IDLE;
        sdram_cmd     <= CMD_NOP;
        sdram_addr    <= {$bits(sdram_addr   ){1'bx}};
        sdram_ba      <= {$bits(sdram_ba     ){1'bx}};
        sdram_rdwr_ba <= {$bits(sdram_rdwr_ba){1'bx}};

        bank_row      <= '{'hx, 'hx, 'hx, 'hx};
        bank_status   <= BANK_STATUS_ALL_IDLE;

        active_port   <= {$bits(active_port){1'b0}};
        active_rd     <= 1'b0;
        active_wr     <= 1'b0;
    end
    else
    begin
        state         <= nxt_state;
        sdram_cmd     <= sdram_nxt_cmd;
        sdram_addr    <= sdram_nxt_addr;
        sdram_ba      <= sdram_nxt_ba;
        sdram_rdwr_ba <= sdram_nxt_rdwr_ba;

        for (int bank=0; bank < 4; bank++)
          bank_row[bank] <= bank_nxt_row[bank];

        bank_status   <= bank_nxt_status;

        active_port   <= active_nxt_port;
        active_rd     <= (active_rd & ~xfer_cnt_done) | active_nxt_rd;
        active_wr     <= (active_wr & ~xfer_cnt_done) | active_nxt_wr;
    end



  /* Assign outputs
   */
  //CMD
  assign sdram_cmd_o = sdram_cmd;
  assign sdram_addr_o = sdram_addr;
  assign sdram_ba_o = sdram_ba;

  //DQ/DM
  assign sdram_dq_o = xfer_dq_wbuf[SDRAM_DQ_SIZE  -1:0];
  assign sdram_dm_o = xfer_dm_wbuf[SDRAM_DQ_SIZE/8-1:0];


  //DQoe
  always @(posedge clk_i)
    sdram_dqoe <= (active_wr | active_nxt_wr) & (burst_cnt_load | ~burst_cnt_done);
  assign sdram_dqoe_o = sdram_dqoe;



  /* DQ_in to AHB-IF
   * All AHB-ports receive DQ
   * dqvalid_o determines which port should process DQ
   */
  always_comb
    for (int port=0; port < $size(rdq_o); port++)
      rdq_o[port] = sdram_dq_i;

endmodule : sdram_cmd_scheduler
