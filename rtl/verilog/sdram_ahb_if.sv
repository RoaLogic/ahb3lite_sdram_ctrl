/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    AHB3-Lite Multi-port SDRAM Controller                        //
//    AHB Data Interface                                           //
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
// FILE NAME      : sdram_ahb_if.sv
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
// PURPOSE  : SDRAM Controller AHB Interface
// ------------------------------------------------------------------
// PARAMETERS
//  PARAM NAME        RANGE    DESCRIPTION              DEFAULT UNITS
//  HADDR_SIZE        1+       AHB address width        32      bits  
//  HDATA_SIZE        1+       AHB data width           32      bits
// ------------------------------------------------------------------
// REUSE ISSUES 
//   Reset Strategy      : external asynchronous active low; HRESETn
//   Clock Domains       : HCLK, rising edge
//   Critical Timing     : 
//   Test Features       : na
//   Asynchronous I/F    : no
//   Scan Methodology    : na
//   Instantiations      : na
//   Synthesizable (y/n) : Yes
//   Other               :                                         
// -FHDR-------------------------------------------------------------

// Ping-Pong Write Buffer
// N-word (8) write buffer
// Merges writes into the same address-range
// Flush when (1) write to different address range (write buffer miss), (2) read from same address
// Ping-pong when write to different address range
// pingpong timeout


//TODO: Break read-request into multiple accesses if AHB-addresses don't align with SDRAM

module sdram_ahb_if
`ifndef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
  import ahb3lite_pkg::*;
`endif
#(
  parameter int HADDR_SIZE        = 32,
  parameter int HDATA_SIZE        = 32,

  parameter int SDRAM_DQ_SIZE     = 16,
  parameter int SDRAM_BA_SIZE     = 2,
  parameter int MAX_RSIZE         = 13,
  parameter int MAX_CSIZE         = 11,

  parameter int WRITEBUFFER_SIZE  = 8 * SDRAM_DQ_SIZE,
  parameter     TECHNOLOGY        = "GENERIC"
)
(
  input csr_t                            csr_i,

  //AHB Port
  input  logic                           HRESETn,
                                         HCLK,
                                         HSEL,
  input  logic [HTRANS_SIZE        -1:0] HTRANS,
  input  logic [HSIZE_SIZE         -1:0] HSIZE,
  input  logic [HBURST_SIZE        -1:0] HBURST,
  input  logic [HPROT_SIZE         -1:0] HPROT,
  input  logic                           HWRITE,
  input  logic                           HMASTLOCK,
  input  logic [HADDR_SIZE         -1:0] HADDR,
  input  logic [HDATA_SIZE         -1:0] HWDATA,
  output logic [HDATA_SIZE         -1:0] HRDATA,
  output logic                           HREADYOUT,
  input  logic                           HREADY,
  output logic                           HRESP,

  //To SDRAM
  output logic                           wbr_o,

  output logic                           rdreq_o,
  input  logic                           rdrdy_i,
  output logic [HADDR_SIZE         -1:0] rdadr_o,
  output logic [SDRAM_BA_SIZE      -1:0] rdba_o,
  output logic [MAX_RSIZE          -1:0] rdrow_o,
  output logic [MAX_CSIZE          -1:0] rdcol_o,
  output logic [                    7:0] rdsize_o,
  input  logic [SDRAM_DQ_SIZE      -1:0] rdq_i,
  input  logic                           rdqvalid_i,

  output logic                           wrreq_o,
  input  logic                           wrrdy_i,
  output logic [HADDR_SIZE         -1:0] wradr_o,
  output logic [SDRAM_BA_SIZE      -1:0] wrba_o,
  output logic [MAX_RSIZE          -1:0] wrrow_o,
  output logic [MAX_CSIZE          -1:0] wrcol_o,
  output logic [                    2:0] wrsize_o,
  output logic [WRITEBUFFER_SIZE/8 -1:0] wrbe_o,
  output logic [WRITEBUFFER_SIZE   -1:0] wrd_o
);

`ifdef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
  import ahb3lite_pkg::*;
`endif

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  function int max(input int a, input int b);
    max = a > b ? a : b;
  endfunction : max

  function automatic int min(input int a, input int b);
    min = a < b ? a : b;
  endfunction : min


  localparam HDATA_BYTES       = HDATA_SIZE/8;
  localparam WRBUFFER_BYTES    = WRITEBUFFER_SIZE/8;
  localparam WRBUFFER_ADR_BITS = $clog2(WRBUFFER_BYTES);
  localparam WRBUFFER_IDX_BITS = $clog2(WRBUFFER_BYTES / HDATA_BYTES);
  localparam WRBUFFER_TAG_SIZE = HADDR_SIZE - WRBUFFER_ADR_BITS;

  localparam HDATA_BYTES_BITS  = $clog2(HDATA_BYTES);
  localparam SDRAM_DQ_BITS     = $clog2(SDRAM_DQ_SIZE);
  localparam HBURST_MAX        = 16;

  //ReadBuffer-size = max(SDRAM_BURST_SIZE_MAX * SDRAM_DQ_SIZE, HBURST_MAX * HDATA_SIZE)
  localparam RDBUFFER_SIZE     = max(8 * SDRAM_DQ_SIZE, HBURST_MAX * HDATA_SIZE);


  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //
  function automatic logic [6:0] address_offset;
    //returns a mask for the lesser bits of the address
    //meaning bits [  0] for 16bit data
    //             [1:0] for 32bit data
    //             [2:0] for 64bit data
    //etc

    //default value, prevent warnings
    address_offset = 0;
	 
    //What are the lesser bits in HADDR?
    case (HDATA_SIZE)
          1024: address_offset = 7'b111_1111; 
           512: address_offset = 7'b011_1111;
           256: address_offset = 7'b001_1111;
           128: address_offset = 7'b000_1111;
            64: address_offset = 7'b000_0111;
            32: address_offset = 7'b000_0011;
            16: address_offset = 7'b000_0001;
       default: address_offset = 7'b000_0000;
    endcase
  endfunction : address_offset

  
  //Generate byte-enables
  function automatic logic [HDATA_BYTES-1:0] gen_be;
    input [HSIZE_SIZE-1:0] hsize;
    input [HADDR_SIZE-1:0] haddr;

    logic [127:0] full_be;
    logic [  6:0] haddr_masked;

    //get number of active lanes for a 1024bit databus (max width) for this HSIZE
    case (hsize)
       HSIZE_B1024: full_be = {128{1'b1}};
       HSIZE_B512 : full_be = { 64{1'b1}};
       HSIZE_B256 : full_be = { 32{1'b1}};
       HSIZE_B128 : full_be = { 16{1'b1}};
       HSIZE_DWORD: full_be = {  8{1'b1}};
       HSIZE_WORD : full_be = {  4{1'b1}};
       HSIZE_HWORD: full_be = {  2{1'b1}};
       default    : full_be = {  1{1'b1}};
    endcase

    //generate masked address
    haddr_masked = haddr & address_offset();

    //create byte-enable
    gen_be = full_be[HDATA_BYTES-1:0] << haddr_masked;
  endfunction : gen_be


  //How many transactions in burst
  function automatic int hburst2cnt;
    input [HBURST_SIZE-1:0] hburst;

    case (hburst)
      HBURST_SINGLE: hburst2cnt =  1;
      HBURST_INCR  : hburst2cnt = 16;
      HBURST_WRAP4 : hburst2cnt =  4;
      HBURST_INCR4 : hburst2cnt =  4;
      HBURST_WRAP8 : hburst2cnt =  8;
      HBURST_INCR8 : hburst2cnt =  8;
      HBURST_WRAP16: hburst2cnt = 16;
      HBURST_INCR16: hburst2cnt = 16;
    endcase
  endfunction : hburst2cnt


  //How many bytes per beat
  function automatic int hsize2bytes;
    input [HBURST_SIZE-1:0] hsize;

    hsize2bytes = 1 << hsize;
  endfunction : hsize2bytes


  //calculate the offset in the sdram burst (not the AHB burst!)
  function automatic logic [2:0] sdram_xfer_burst_offset;
    input [HADDR_SIZE -1:0] haddr;
    input [            1:0] dqsize;
    input [            1:0] burst_size;

    logic [HADDR_SIZE -1:0] sdram_address;

    //get the SDRAM address
    sdram_address           = haddr >> (dqsize + 1'h1);

    //get the SDRAM burst offset
    sdram_xfer_burst_offset = sdram_address[2:0] & ~(3'b111 << burst_size);
  endfunction : sdram_xfer_burst_offset;


  //calculate total number of SDRAM transactions required for the AHB read
  function automatic logic [10:0] sdram_rd_xfer_total_cnt;
    /*The number of SDRAM transactions dependends on the number of
     *bytes to transfer (which depends on HSIZE and HBURST) and the dqsize
     */
    input [HADDR_SIZE -1:0] haddr;
    input [HBURST_SIZE-1:0] hburst;
    input [HSIZE_SIZE -1:0] hsize;
    input [            1:0] dqsize;


    //get the total number of burst transactions
    int totalbytes           = hburst2cnt(hburst) << hsize;

    //convert total number of required bytes to sdram transaction count
    sdram_rd_xfer_total_cnt  = totalbytes/2 >> dqsize;            //sdram is minimal 2bytes wide
    sdram_rd_xfer_total_cnt += haddr & ~((2'h2 << dqsize) -1'h1) !=0 ? 1'h1 : 1'h0;
  endfunction : sdram_rd_xfer_total_cnt


  //do we need to break up the sdram transfer into multiple reads?
  function automatic logic sdram_rd_xfer_break; //FIXME
    input [HADDR_SIZE -1:0] haddr;
    input [HBURST_SIZE-1:0] hburst;
    input [HSIZE_SIZE -1:0] hsize;
    input [            1:0] dqsize;
    input [            1:0] burst_size;

    logic [ 2:0] offset;
    logic [11:0] offset_plus_xfers;
    logic        wrapped;

    //first get SDRAM offset (in column)
    offset = sdram_xfer_burst_offset(haddr, dqsize, burst_size);

    //then add how many xfers in the column (starting at offset)
    offset_plus_xfers = offset + sdram_rd_xfer_total_cnt(haddr, hburst, hsize, dqsize);

    //then check if we rolled/wrapped over the SDRAM burst
    wrapped = offset_plus_xfers > (1'h1 << burst_size);

    sdram_rd_xfer_break = wrapped & |offset;
//$display("haddr=%0h, offset=%0h, offset+xfers=%0x, wrapped=%0h, break=%b", haddr, offset, offset_plus_xfers, wrapped, sdram_rd_xfer_break);
  endfunction : sdram_rd_xfer_break


  //Calculate how many SDRAM transactions required for the AHB read
  function automatic logic [10:0] sdram_rd_xfer_cnt;
    /*The number of SDRAM transactions dependends on the number of
     *bytes to transfer (which depends on HSIZE and HBURST) and the dqsize
     */
    input [HADDR_SIZE -1:0] haddr;
    input [HBURST_SIZE-1:0] hburst;
    input [HSIZE_SIZE -1:0] hsize;
    input [            1:0] dqsize;
    input [            1:0] burst_size;

    logic [            2:0] sdram_burst_offset;
    logic [            3:0] sdram_burst_until_wrap;
    logic [           10:0] sdram_burst_total;
    logic [           10:0] sdram_burst_actual;
    int                     totalbytes;

    //get the SDRAM burst offset
    sdram_burst_offset = sdram_xfer_burst_offset(haddr, dqsize, burst_size);

    //get the number of transaction until we roll over
    sdram_burst_until_wrap = (1'h1 << burst_size) - sdram_burst_offset;

    //get the total number of required sdram transactions
    sdram_burst_total = sdram_rd_xfer_total_cnt(haddr, hburst, hsize, dqsize);
//$display("total=%0d", sdram_burst_total);

    //will we roll-over (sdram burst)?
    if (sdram_rd_xfer_break(haddr, hburst, hsize, dqsize, burst_size))
      sdram_burst_actual = min(sdram_burst_until_wrap, sdram_burst_total);
    else
      sdram_burst_actual = sdram_burst_total;

    //transfer count
//    sdram_rd_xfer_cnt = max(sdram_burst_actual, 1'h1);
    sdram_rd_xfer_cnt = sdram_burst_actual;
  endfunction : sdram_rd_xfer_cnt


  //Calculate next AHB address for a broken SDRAM burst
  function automatic logic [HADDR_SIZE-1:0] sdram_rd_nxt_radr;
    input [HADDR_SIZE -1:0] haddr;
    input [HBURST_SIZE-1:0] hburst;
    input [HSIZE_SIZE -1:0] hsize;
    input [            1:0] dqsize;
    input [            1:0] burst_size;

    logic [            2:0] sdram_burst_offset;
    logic [            3:0] sdram_burst_until_wrap;

    //get the SDRAM burst offset
    sdram_burst_offset = sdram_xfer_burst_offset(haddr, dqsize, burst_size);

    //get the number of transaction until we roll over
    sdram_burst_until_wrap = (1'h1 << burst_size) - sdram_burst_offset;

    //calculate next read address
    sdram_rd_nxt_radr = (haddr & ({{HADDR_SIZE-1{1'b1}}, 1'b0} << dqsize)) + (2'h2 << dqsize) * sdram_burst_until_wrap;
  endfunction : sdram_rd_nxt_radr


/*
  //calculate next burst address
  function automatic [ADDR_SIZE-1:0] nxt_addr;
    input [ADDR_SIZE  -1:0] addr;   //current address
    input [HBURST_SIZE-1:0] hburst; //AHB HBURST
    input [HSIZE_SIZE -1:0] hsize;  //AHB HSIZE

    logic [ADDR_SIZE-1:0] mask;


    //next linear address
    nxt_addr = addr + (1 << hsize);

    //align to boundary
    nxt_addr = nxt_addr & ({ADDR_SIZE{1'b1}} << hsize);

    //wrap?
    case (hburst)
      HBURST_WRAP4 : mask = {{ADDR_SIZE-2{1'b1}}, 2'h0} << hsize;
      HBURST_WRAP8 : mask = {{ADDR_SIZE-3{1'b1}}, 3'h0} << hsize;
      HBURST_WRAP16: mask = {{ADDR_SIZE-4{1'b1}}, 4'h0} << hsize;
      default      : mask = {ADDR_SIZE{1'b0}};
    endcase

    //mix linear/wrap address
    nxt_addr = (addr & mask) | (nxt_addr & ~mask);
  endfunction: nxt_addr
*/

  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //AHB domain
  logic                         ahb_read,
                                ahb_write;

  //AHB beats (a beat is a single transaction in an AHB burst)
  logic                         beat_write,
                                beat_read;
  logic [HTRANS_SIZE      -1:0] beat_trans;
  logic [HSIZE_SIZE       -1:0] beat_size;
  logic [HBURST_SIZE      -1:0] beat_burst;
  logic [HADDR_SIZE       -1:0] beat_addr;


  //Write
  logic [HDATA_BYTES      -1:0] be;
  logic [WRBUFFER_TAG_SIZE-1:0] tag,
                                write_tag;
  logic [WRBUFFER_IDX_BITS-1:0] wr_idx;

  logic                         writebuffer_flush;
  logic [                 15:0] writebuffer_timer;
  logic                         writebuffer_timer_expired;
  logic                         writebuffer_we;
  logic                         writebuffer_re;
  logic [WRBUFFER_BYTES   -1:0] writebuffer_be   [2];
  logic [WRBUFFER_TAG_SIZE-1:0] writebuffer_tag  [2];
  logic                         writebuffer_dirty[2];

  logic                         pingpong,
                                pingpong_toggle,
                                nxt_pingpong;

  //Read
  logic                         rdfifo_rreq;
  logic                         rdfifo_empty;
  logic [SDRAM_DQ_SIZE    -1:0] rdfifo_q;
  logic [SDRAM_DQ_BITS    -1:0] rdfifo_cnt;
  logic [SDRAM_DQ_BITS    -1:0] rdfifo_cnt_ldval;
  logic [                  3:0] rd_burst_cnt;
  logic                         rd_burst_done;
  logic [HDATA_SIZE       -1:0] hrdata;
  logic [HDATA_BYTES_BITS -1:0] hrdata_idx;
  logic [HADDR_SIZE       -1:0] rdadr_nxt, rdadr_nxt_reg;
  logic [                  7:0] rdsize_rem, rdsize_rem_reg;


  //FSM encoding
  enum logic [2:0] {rd_idle = 3'b000, rd_start = 3'b001, rd_pending = 3'b101, rd_burst = 3'b011, rd_final = 3'b111} rd_nxt_state, rd_state;
  enum logic       {wr_idle = 1'b0, wr_wait=1'b1} wr_nxt_state, wr_state;

  logic hreadyout_rd, hreadyout_rd_reg;
  logic hreadyout_wr, hreadyout_wr_reg;
  logic hreadyout_hrdata;


  //To SDRAM
  logic                           wbr;      //write-before-read

  logic                           rdreq;
  logic [HADDR_SIZE         -1:0] rdadr;
  logic [                    7:0] rdsize;

  logic                           wrreq, wrreq_dly;
  logic [HADDR_SIZE         -1:0] wradr;
  logic [                    2:0] wrsize;


  //////////////////////////////////////////////////////////////////
  //
  // Tasks
  //
  task flush;
      input                         dirty;
      input                         wrrdy;
      input [WRBUFFER_TAG_SIZE-1:0] tag;
      input                         hreadyout_value;

      if (!dirty || wrrdy) //other buffer clean?
      begin
          //flush
          go_flush(tag);
      end
      else //other buffer not clean; wait for it to be processed
      begin
          //previous flush not serviced yet, insert wait states if there's
	  //a new AHB write transaction pending
          hreadyout_wr = hreadyout_value;

          //wait for previous request to be serviced
          wr_nxt_state = wr_wait;
      end
  endtask : flush


  task go_flush;
    input [WRBUFFER_TAG_SIZE-1:0] tag;

    //flush
    wr_nxt_state    = wr_idle;
    hreadyout_wr    = 1'b1;
    pingpong_toggle = 1'b1;

    wrreq     = 1'b1;
    wradr     = {tag, {WRBUFFER_ADR_BITS{1'b0}}};
    wrsize    = WRBUFFER_ADR_BITS -1'h1;
  endtask : go_flush


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  //
  // AHB Clock Domain
  //

  assign HRESP = HRESP_OKAY;
  
  assign ahb_write = HSEL &  HWRITE & (HTRANS != HTRANS_BUSY) & (HTRANS != HTRANS_IDLE);
  assign ahb_read  = HSEL & ~HWRITE & (HTRANS != HTRANS_BUSY) & (HTRANS != HTRANS_IDLE);


  //generate write enable
  always @(posedge HCLK)
    if (HREADY) beat_write <= ahb_write;

  always @(posedge HCLK)
    if (HREADY) beat_read  <= ahb_read;

  always @(posedge HCLK)
    if (HREADY) beat_trans <= HTRANS;

  always @(posedge HCLK)
    if (HREADY) beat_size  <= HSIZE;

  always @(posedge HCLK)
    if (HREADY) beat_burst <= HBURST;

  always @(posedge HCLK)
    if (HREADY) beat_addr  <= HADDR;


  assign writebuffer_we = beat_write & hreadyout_wr_reg;


  /* Write(buffer)
   */
  //decode Byte-Enables
  always @(posedge HCLK)
    if (HREADY) be <= gen_be(HSIZE,HADDR);


  //next pingpong
  assign nxt_pingpong = pingpong ^ pingpong_toggle;


  //TAG
  assign tag = HADDR[HADDR_SIZE -1 -: WRBUFFER_TAG_SIZE];

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn) write_tag <= {WRBUFFER_TAG_SIZE{1'b0}};
    else if ( HREADY ) write_tag <= tag;

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn)
    begin
        writebuffer_tag[0] <= {$bits(writebuffer_tag[0]){1'b0}};
        writebuffer_tag[1] <= {$bits(writebuffer_tag[1]){1'b0}};
    end
    else if (writebuffer_we) writebuffer_tag[pingpong] <= write_tag;


  //IDX
  always @(posedge HCLK)
    if (HREADY)
      wr_idx <= HADDR[WRBUFFER_ADR_BITS -1 -: WRBUFFER_IDX_BITS];

  //writebuffer write enable. Delayed pingpong toggle for 1 cycle memory access delay
  always @(posedge HCLK)
    writebuffer_re <= pingpong_toggle;


  //Writebuffer
  rl_ram_1r1w #(
    .WRITE_ABITS   ( WRBUFFER_IDX_BITS +1),
    .WRITE_DBITS   ( HDATA_SIZE          ),
    .READ_ABITS    ( 1                   ),
    .READ_DBITS    ( WRITEBUFFER_SIZE    ),
    .TECHNOLOGY    ( TECHNOLOGY          ),
    .RW_CONTENTION ( "DONT_CARE"         ))
  writebuffer_inst (
    .rst_ni        ( HRESETn            ),
    .clk_i         ( HCLK               ),

    //Write side
    .waddr_i       ( {pingpong, wr_idx} ),
    .din_i         ( HWDATA             ),
    .we_i          ( writebuffer_we     ),
    .be_i          ( be                 ),

    //Read side
    .raddr_i       (~pingpong           ),
    .re_i          ( writebuffer_re     ),
    .dout_o        ( wrd_o              ));


  //Byte enables
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        writebuffer_be[0] <= {$bits(writebuffer_be[0]){1'b0}};
        writebuffer_be[1] <= {$bits(writebuffer_be[1]){1'b0}};
    end
    else
    begin
        if (pingpong_toggle)
          writebuffer_be[nxt_pingpong] <= {WRBUFFER_BYTES{1'b0}};

        if (writebuffer_we)
          writebuffer_be[pingpong][wr_idx*HDATA_BYTES +: HDATA_BYTES] <= writebuffer_be[pingpong][wr_idx*HDATA_BYTES +: HDATA_BYTES] | be;
    end


  always @(posedge HCLK)
    if (writebuffer_re) wrbe_o <= writebuffer_be[~pingpong]; 


  //Dirty
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        writebuffer_dirty[0] <= 1'b0;
        writebuffer_dirty[1] <= 1'b0;
    end
    else
    begin
        if ( writebuffer_we     ) writebuffer_dirty[ pingpong] <= 1'b1;
        if ( wrreq_o && wrrdy_i ) writebuffer_dirty[~pingpong] <= 1'b0;
    end


  //Timer
  always @(posedge HCLK, negedge HRESETn)
    if      ( !HRESETn                    ) writebuffer_timer <= {$bits(writebuffer_timer){1'b0}};
    else if ( !writebuffer_dirty[pingpong]) writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;
    else if (  beat_write                 ) writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;
    else if (  writebuffer_timer_expired  ) writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;
    else if ( |writebuffer_timer          ) writebuffer_timer <= writebuffer_timer -1'h1;
    else                                    writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn                        ) writebuffer_timer_expired <= 1'b0;
    else if (~|csr_i.ctrl.writebuffer_timeout) writebuffer_timer_expired <= 1'b0; //a CSR value of zero disables the timer
    else if (~|writebuffer_timer             ) writebuffer_timer_expired <= 1'b1;
    else if (  pingpong_toggle               ) writebuffer_timer_expired <= 1'b0;

    
  //Flush
  assign writebuffer_flush = (ahb_read  & writebuffer_dirty[       0] & (tag == writebuffer_tag[       0])) |
                             (ahb_read  & writebuffer_dirty[       1] & (tag == writebuffer_tag[       1])) |
                             (ahb_write & writebuffer_dirty[pingpong] & (tag != writebuffer_tag[pingpong])) |
                             (ahb_write & writebuffer_we              & (tag != write_tag)                );


  //Write FSM
  always_comb
  begin
      wr_nxt_state   = wr_state;
      hreadyout_wr   = hreadyout_wr_reg;

      wrreq    = (wrreq_o | wrreq_dly) & ~wrrdy_i;
      wradr    = wradr_o;
      wrsize   = wrsize_o;

      pingpong_toggle = 1'b0;

      case (wr_state)
        //wait for action
        wr_idle: if (HREADY && (ahb_read || ahb_write) )
                 begin
                     if (writebuffer_flush)
                       flush(writebuffer_dirty[~pingpong],
                             wrrdy_i,
                             writebuffer_tag  [ pingpong],
                             1'b0);
                 end
                 else if (writebuffer_timer_expired) //timer expired
                   flush(writebuffer_dirty[~pingpong],
                         wrrdy_i,
                         writebuffer_tag  [ pingpong],
                         1'b1);

        //wait for pending wrreq to complete
        wr_wait: if (wrrdy_i)
                  go_flush(writebuffer_tag[pingpong]);
      endcase
    end



  /* Read
   */

  //ReadFIFO
  rl_scfifo #(
    .DEPTH             ( 8             ), //SDRAM max burst size = 8
    .DATA_SIZE         ( SDRAM_DQ_SIZE ),
    .REGISTERED_OUTPUT ( "NO"          ))
  rdfifo (
    .rst_ni  ( HRESETn      ),
    .clk_i   ( HCLK         ),
    .clr_i   ( 1'b0         ), //TODO: use clr_i to remove extra read data?

    .d_i     ( rdq_i        ),
    .wrena_i ( rdqvalid_i   ),

    .rdena_i ( rdfifo_rreq  ),
    .q_o     ( rdfifo_q     ),

    .empty_o ( rdfifo_empty ),
    .full_o  (),
    .usedw_o ());


/* Generate HRDATA
 * 1. HSIZE <= csr.ctrl.dqsize
 *    grab fifo.q_o[idx] and place them in HRDATA
 *    set rdhreadyout = 1'b1
 *    if (idx < (SDRAM_DQ_SIZE-HSIZE)) idx++
 *    else idx=0, read next fifo entry; fifo.rdena_i=1
 * 2. HSIZE >  csr.ctrl.dqsize
 *    grab fifo.q_o and place in HRDATA[idx]
 *    fifo.rdena_i=1
 *    if (idx < (HDATA_SIZE-HSIZE)) idx++
 *    else idx=0, rdhreadyout = 1'b1
 *
 * HSIZE(bytes)  dqsize(bytes) -- dqsize-2
 *  000     1      00      2       110
 *  001     2      01      4       111
 *  010     4      10      8       000
 *  011     8      11     16       001
 *  100    16
 *  101    32
 *  110    64
 *  111   128
 *
 */

/*
 * if (beat_size < (csr_i.ctrl.dqsize + 1'h1))
 *   //sdram provides more data than required in a beat
 *   if (beat_burst == HBURST_SINGLE)
 *     //sdram_dq contains all data -> hreadyout=1
 *   else
 *     //this is a burst, sdram_dq may(!) contain data for more than 1 beat
 *     //figure out where we start in sdram_dq rdfifo_cnt = beat_addr % (csr_i.ctrl.dqsize + 1'h1)
 *     //No misaligned addresses: hrdata can not straddle/cross sdram_dq boundary (good) .. hreadyout=1
 *     //rdfifo_cnt+=(1 << beat_size)
 *     //if (rdfifo_cnt - (1 << beat_size) == (csr_i.ctrl.dqsize + 1'h1)) rdfifo_rreq=1, rdfifo_cnt=0;
 *  else
 *     //sdram provides partial beat data. Need to stich multiple fifo_q bytes together to form hrdata
 *     //No misaligned addresses, always consume full sdram_dq (good)
 *     //rdfifo_cnt = 0
 *     //rdfifo_rreq=1, rdfifo_cnt+=(2'h2 << csr_i.ctrl.dqsize)
 *     //if (rdfifo_cnt == (1 << beat_size)) hreadyout=1,rdfifo_cnt=0
 */

  always_comb
    begin
        rdfifo_rreq = 1'b0;

        if (beat_size < csr_i.ctrl.dqsize +1'h1)
        begin
            //sdram provides more data than needed in a single beat

            if (beat_burst == HBURST_SINGLE && !rdfifo_empty) rdfifo_rreq = 1'b1;
            else if (/*!rd_burst_done &&*/ !rdfifo_empty)
            begin
                if (rdfifo_cnt == 0) /*(2'h2 << csr_i.ctrl.dqsize) -1'h1)*/ rdfifo_rreq = 1'b1;
            end
        end
        else
        begin
            //sdram provides partial data needed in a single beat
            //need to stich multiple fifo-data bytes together to form HRDATA
            if (!rdfifo_empty) rdfifo_rreq = 1'b1;
        end
    end


  always_comb
    if (beat_size <= csr_i.ctrl.dqsize +1'h1)
    begin
        //sdram provides more data than needed in a single beat
        hreadyout_hrdata = ~rdfifo_empty;
    end
    else
    begin
        //sdram provides partial data needed in a single beat
        //need to stich multiple fifo-data bytes together to form HRDATA
        if (/*!rd_burst_done*/ 1)
        begin
            if (rdfifo_cnt == (1'h1 << (beat_size -1'h1)))
            begin
                hreadyout_hrdata = 1'b1;
            end
            else
            begin
                hreadyout_hrdata = 1'b0;
            end
        end
        else
        begin
            hreadyout_hrdata = 1'b0;
        end
    end


  always @(posedge HCLK)
    if (HSIZE/*beat_size*/ == csr_i.ctrl.dqsize +1'h1)
    begin
        //sdram provides exactly the required amount of data for a single beat
        rdfifo_cnt = {$bits(rdfifo_cnt){1'b0}};
    end
    else if (HSIZE/*beat_size*/ < csr_i.ctrl.dqsize +1'h1)
    begin
        //sdram provides more data than needed in a single beat

        if (!rdfifo_empty)
        begin
            //burst transfer, need to use the same fifo-data for multiple beats
            if (rdfifo_cnt == 0)
            begin
                rdfifo_cnt <= (2'h2 << csr_i.ctrl.dqsize) -1'h1;
            end
            else
              rdfifo_cnt <= rdfifo_cnt - (1'h1 << beat_size);
        end
        else if (HREADY && HTRANS == HTRANS_NONSEQ)
        begin
            rdfifo_cnt <= ((2'h2 << csr_i.ctrl.dqsize) -1'h1) - (/*beat_addr*/HADDR[0 +: HDATA_BYTES_BITS] & ((2'h2 << csr_i.ctrl.dqsize) -1'h1));
        end
    end
    else
    begin
        //sdram provides partial data needed in a single beat
        //need to stich multiple fifo-data bytes together to form HRDATA
        if (!(rd_burst_done && hreadyout_hrdata) && !rdfifo_empty)
        begin
            if (rdfifo_cnt == (1'h1 << (beat_size -1'h1)))
            begin
                rdfifo_cnt <= {$bits(rdfifo_cnt){1'b0}};
            end
            else
            begin
                rdfifo_cnt <= rdfifo_cnt + (2'h2 << csr_i.ctrl.dqsize);
            end
        end
        else
        begin
            rdfifo_cnt    <= {$bits(rdfifo_cnt){1'b0}};
        end
    end


  //which byte in HRDATA
  always @(posedge HCLK)
    if (HREADY && HTRANS == HTRANS_NONSEQ/*rdfifo_empty*/)
      hrdata_idx <= /*beat_addr*/HADDR[0 +: HDATA_BYTES_BITS];
    else if (!rdfifo_empty)
    begin
    /*else*/ if (beat_size < csr_i.ctrl.dqsize +1'h1)
      hrdata_idx <= hrdata_idx + (1'h1 << beat_size);
    else
      hrdata_idx <= hrdata_idx + (2'h2 << csr_i.ctrl.dqsize);
    end

  //assign HRDATA
  always @(posedge HCLK)
    if (!rdfifo_empty)
    begin
        if (beat_size < (csr_i.ctrl.dqsize +1'h1))
          HRDATA[hrdata_idx *8 +: SDRAM_DQ_SIZE] <= rdfifo_q >> ((hrdata_idx & ((2'h2 << csr_i.ctrl.dqsize) -1'h1)) *8);
        else
          HRDATA[hrdata_idx *8 +: SDRAM_DQ_SIZE] <= rdfifo_q;
    end


  //read burst counter
  always @(posedge HCLK)
    if (HREADY && HTRANS == HTRANS_NONSEQ)
    begin
        rd_burst_cnt  <= hburst2int(HBURST) -1'h1;
        rd_burst_done <= HBURST == HBURST_SINGLE;
    end
    else if (!rd_burst_done && hreadyout_hrdata)
    begin
        rd_burst_cnt  <= rd_burst_cnt -1'h1;
        rd_burst_done <= rd_burst_cnt == 1'h1;
    end


  //Read FSM
//FIXME: Wrap burst and burst not starting at ctrl.dqsize boundary
//if (not ctrl.burst_size, HADDR/HBURST boundary)
//    perform full burst --> rdsize = sdram_read_xfercnt()
//else
//    perform 1st read up to ctrl.burst boundary --> rdsize = (2'h2 << ctrl.dqsize) - HADDR & ((2'h2 << csr_i.ctrl.dqsize) -1'h1)
//    now next transfer always starts at ctrl.dqsize boundary --> rdsize = sdram_read_xfercnt() - rdsize
/*
    HBURST  HSIZE
    -----------------------------------
    INCR4   BYTE    0     1
                    1     2
                    2     3
                    3     4
    INCR8
    INCR16
    WRAP4
    WRAP8
    WRAP16
 */
  always_comb
  begin
      rd_nxt_state  = rd_state;
      hreadyout_rd  = hreadyout_rd_reg;

      wbr       = wbr_o   & ~rdrdy_i;
      rdreq     = rdreq_o & ~rdrdy_i;
      rdadr     = rdadr_o;
      rdadr_nxt = rdadr_nxt_reg;
      rdsize    = rdsize_o;
      rdsize_rem = rdsize_rem_reg;

      case (rd_state)
        //wait for final data ready
        rd_final  : begin
                        hreadyout_rd = hreadyout_hrdata;
                        if (rd_burst_done && hreadyout_hrdata) rd_nxt_state = rd_idle;
                    end

        //handle 2nd transaction while 1st transaction still pending
        rd_pending: if (hreadyout_hrdata)
                    begin
                        rd_nxt_state = rd_final;
                        hreadyout_rd = 1'b1;
                    end
                    else
                    begin
                        hreadyout_rd = 1'b0;
                    end

        //continue (broken) burst
        rd_burst  : begin
                        hreadyout_rd = hreadyout_hrdata;

                        if (rdrdy_i)
                        begin
                            rdadr  = HADDR;
                            rdreq  = 1'b0;
                            rdsize = sdram_rd_xfer_cnt(beat_addr, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size)
                                     -rdsize -1'h1; //do the -1 here

//                            rd_nxt_state = sdram_rd_xfer_break(beat_addr, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size) ? rd_burst : rd_final;
                            rd_nxt_state = rd_final;
                        end
                    end

        //wait for scheduler to reply/accept request
        rd_start  : begin
                        if (csr_i.ctrl.mode == 2'b00) hreadyout_rd = hreadyout_hrdata;

                        if (rdrdy_i)
                        begin
                            rdadr  = HADDR;
                            rdsize = sdram_rd_xfer_cnt(beat_addr, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size) -1'h1; //do the -1 here

                            if (csr_i.ctrl.mode != 2'b00)
                            begin
                                rdreq        = 1'b0;
                                rd_nxt_state = rd_idle;
                                hreadyout_rd = 1'b1;
                            end
                            else if (ahb_read && rd_burst_done)
                            begin
                                //this is the start of a new AHB burst
                                rdreq        = 1'b1;
                                rd_nxt_state = rd_pending;
                                hreadyout_rd = 1'b0;
                                wbr          = writebuffer_flush;
                            end
                            else
                            begin
                                rdadr        = rdadr_nxt_reg;
                                rdadr_nxt    = sdram_rd_nxt_radr(rdadr_o, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size);
                                rdreq        = sdram_rd_xfer_break(beat_addr, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size);
                                rdsize       = rdsize_rem_reg -1'h1; //sdram_rd_xfer_cnt(rdadr_nxt_reg, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size)
//                                               -rdsize -1'h1; //do the -1 here
                                rd_nxt_state = sdram_rd_xfer_break(beat_addr, beat_burst, beat_size, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size) ? rd_burst : rd_final;
                            end
                        end
                    end

        //wait for action
        rd_idle   : if (HREADY && ahb_read) //start new transaction
                    begin
                        rd_nxt_state = rd_start;
                        hreadyout_rd = 1'b0; //insert wait states
                        wbr          = writebuffer_flush;

                        rdreq      = 1'b1;
                        rdadr      = HADDR;
                        rdadr_nxt  = sdram_rd_nxt_radr(HADDR, HBURST, HSIZE, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size);
                        rdsize     = sdram_rd_xfer_cnt(HADDR, HBURST, HSIZE, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size) -1'h1; //do the -1 here
                        rdsize_rem = sdram_rd_xfer_total_cnt(HADDR, HBURST, HSIZE, csr_i.ctrl.dqsize) -
                                     sdram_rd_xfer_cnt(HADDR, HBURST, HSIZE, csr_i.ctrl.dqsize, csr_i.ctrl.burst_size);
                    end
      endcase
    end


  /* FSM registers
   */
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        wr_state         <= wr_idle;
        rd_state         <= rd_idle;
	hreadyout_wr_reg <= 1'b1;
	hreadyout_rd_reg <= 1'b1;
        HREADYOUT        <= 1'b1;

        pingpong         <= 1'b0;

        wbr_o            <= 1'b0;
        wrreq_dly        <= 1'b0;
        wrreq_o          <= 1'b0;
        wradr_o          <= {$bits(wradr_o ){1'bx}};
        wrsize_o         <= {$bits(wrsize_o){1'bx}};

        rdadr_nxt_reg    <= {$bits(rdadr_nxt_reg){1'bx}};
        rdsize_rem_reg   <= {$bits(rdsize_rem_reg){1'bx}};

        rdreq_o          <= 1'b0;
        rdadr_o          <= {$bits(rdadr_o ){1'bx}};
        rdsize_o         <= {$bits(rdsize_o){1'bx}};
    end
    else
    begin
        wr_state         <= wr_nxt_state;
	rd_state         <= rd_nxt_state;
	hreadyout_wr_reg <= hreadyout_wr;
	hreadyout_rd_reg <= hreadyout_rd;
        HREADYOUT        <= hreadyout_wr & hreadyout_rd;

        pingpong         <= nxt_pingpong;

        wbr_o            <= wbr;
        wrreq_dly        <= wrreq;                          //extra delay for wrreq, because wrd_o is 1 cycle late
        wrreq_o          <= wrreq_dly & (~wrrdy_i | wrreq); //Allow continuous wrreq only when wrreq set in wr_wait state
                                                            //wrd_o is at least 1 cycle stable due to wr_wait
        wradr_o          <= wradr;
        wrsize_o         <= wrsize;

        rdadr_nxt_reg    <= rdadr_nxt;
        rdsize_rem_reg   <= rdsize_rem;

        rdreq_o          <= rdreq;
        rdadr_o          <= rdadr;
        rdsize_o         <= rdsize;
    end



  /* SDRAM Bank, Row, Column generation
   */
  sdram_address_mapping #(
    .ADDR_SIZE ( HADDR_SIZE    ),
    .MAX_CSIZE ( MAX_CSIZE     ),
    .MAX_RSIZE ( MAX_RSIZE     ),
    .BA_SIZE   ( SDRAM_BA_SIZE ))
  map_addr_wr (
    .clk_i     ( HCLK          ),
    .csr_i     ( csr_i         ),
    .address_i ( wradr         ),
    .bank_o    ( wrba_o        ),
    .row_o     ( wrrow_o       ),
    .column_o  ( wrcol_o       )),
  map_addr_rd (
    .clk_i     ( HCLK          ),
    .csr_i     ( csr_i         ),
    .address_i ( rdadr         ),
    .bank_o    ( rdba_o        ),
    .row_o     ( rdrow_o       ),
    .column_o  ( rdcol_o       ));

endmodule : sdram_ahb_if
