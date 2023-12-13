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
//  WRITEBUFFER_SIZE  1+       Writebuffer size         8
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
  parameter int HADDR_SIZE       = 32,
  parameter int HDATA_SIZE       = 32,
  parameter int WRITEBUFFER_SIZE = 8,

  parameter int BA_SIZE          = 2,
  parameter int MAX_RSIZE        = 13,
  parameter int MAX_CSIZE        = 11,

  parameter int DSIZE            = WRITEBUFFER_SIZE * HDATA_SIZE
)
(
  input csr_t                     csr_i,

  //AHB Port
  input  logic                    HRESETn,
                                  HCLK,
                                  HSEL,
  input  logic [HTRANS_SIZE -1:0] HTRANS,
  input  logic [HSIZE_SIZE  -1:0] HSIZE,
  input  logic [HBURST_SIZE -1:0] HBURST,
  input  logic [HPROT_SIZE  -1:0] HPROT,
  input  logic                    HWRITE,
  input  logic                    HMASTLOCK,
  input  logic [HADDR_SIZE  -1:0] HADDR,
  input  logic [HDATA_SIZE  -1:0] HWDATA,
  output logic [HDATA_SIZE  -1:0] HRDATA,
  output logic                    HREADYOUT,
  input  logic                    HREADY,
  output logic                    HRESP,

  //To SDRAM
  output logic                    wbr_o,

  output logic                    rdreq_o,
  input  logic                    rdrdy_i,
  output logic [HADDR_SIZE  -1:0] rdadr_o,
  output logic [BA_SIZE     -1:0] rdba_o,
  output logic [MAX_RSIZE   -1:0] rdrow_o,
  output logic [MAX_CSIZE   -1:0] rdcol_o,
  output logic [             2:0] rdsize_o,
  input  logic [HDATA_SIZE  -1:0] rdq_i,
  input  logic                    rdqvalid_i,

  output logic                    wrreq_o,
  input  logic                    wrrdy_i,
  output logic [HADDR_SIZE  -1:0] wradr_o,
  output logic [BA_SIZE     -1:0] wrba_o,
  output logic [MAX_RSIZE   -1:0] wrrow_o,
  output logic [MAX_CSIZE   -1:0] wrcol_o,
  output logic [             2:0] wrsize_o,
  output logic [DSIZE/8     -1:0] wrbe_o,
  output logic [DSIZE       -1:0] wrd_o
);

`ifdef ALTERA_RESERVED_QIS
  import sdram_ctrl_pkg::*;
  import ahb3lite_pkg::*;
`endif

  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam HDATA_BYTES     = HDATA_SIZE/8;
  localparam BUFFER_BYTES    = DSIZE/8;
  localparam BUFFER_ADR_SIZE = $clog2(BUFFER_BYTES);
  localparam BUFFER_TAG_SIZE = HADDR_SIZE - BUFFER_ADR_SIZE;


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


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //AHB domain
  logic                       ahb_read,
                              ahb_write;

  logic                       write,
                              read;
  logic [HDATA_BYTES    -1:0] be;
  logic [BUFFER_TAG_SIZE-1:0] tag,
                              write_tag;
  logic [BUFFER_ADR_SIZE-1:0] idx;

  logic                       writebuffer_flush;
  logic [               15:0] writebuffer_timer;
  logic                       writebuffer_timer_expired;
  logic [DSIZE          -1:0] writebuffer      [2];
  logic [BUFFER_BYTES   -1:0] writebuffer_be   [2];
  logic [BUFFER_TAG_SIZE-1:0] writebuffer_tag  [2];
  logic                       writebuffer_dirty[2];

  logic                       pingpong,
                              pingpong_toggle,
                              nxt_pingpong;

  //FSM encoding
  enum {rd_idle, rd_read} rd_nxt_state, rd_state;
  enum {wr_idle, wr_wait} wr_nxt_state, wr_state;

  logic hreadyout_rd, hreadyout_rd_reg;
  logic hreadyout_wr, hreadyout_wr_reg;


  //To SDRAM
  logic                    wbr;      //write-before-read

  logic                    rdreq;
  logic [HADDR_SIZE  -1:0] rdadr;
  logic [             2:0] rdsize;

  logic                    wrreq;
  logic [HADDR_SIZE  -1:0] wradr;
  logic [             2:0] wrsize;
  logic [DSIZE/8     -1:0] wrbe;
  logic [DSIZE       -1:0] wrd;


  //////////////////////////////////////////////////////////////////
  //
  // Tasks
  //
  task flush;
      input wrrdy;

      if (!writebuffer_dirty[~pingpong] || wrrdy) //other buffer clean?
      begin
          //flush
          go_flush();
      end
      else //other buffer not clean; wait for it to be processed
      begin
          //previous flush not serviced yet, insert wait states
          hreadyout_wr = 1'b0;

          //wait for previous request to be serviced
          wr_nxt_state = wr_wait;
      end
  endtask : flush


  task go_flush;
    //flush
    wr_nxt_state    = wr_idle;
    hreadyout_wr    = 1'b1;
    pingpong_toggle = 1'b1;

    wrreq     = 1'b1;
    wradr     = {writebuffer_tag[pingpong], {BUFFER_ADR_SIZE{1'b0}}};
    wrsize    = $clog2(BUFFER_BYTES) -1'h1;
    wrbe      = writebuffer_be[pingpong];
    wrd       = writebuffer[pingpong];
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
    if (HREADY) write <= ahb_write;
    else        write <= 1'b0;


  //decode Byte-Enables
  always @(posedge HCLK)
    if (HREADY) be <= gen_be(HSIZE,HADDR);


  //next pingpong
  assign nxt_pingpong = pingpong ^ pingpong_toggle;


  //TAG
  assign tag = HADDR[HADDR_SIZE -1 -: BUFFER_TAG_SIZE];

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn) write_tag <= {BUFFER_TAG_SIZE{1'b0}};
    else if ( HREADY ) write_tag <= tag;

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn)
    begin
        writebuffer_tag[0] <= {$bits(writebuffer_tag[0]){1'b0}};
        writebuffer_tag[1] <= {$bits(writebuffer_tag[1]){1'b0}};
    end
    else if ( HREADY ) writebuffer_tag[nxt_pingpong] <= write_tag;


  //IDX
  always @(posedge HCLK)
    idx <= HADDR[BUFFER_ADR_SIZE -1:0] & ~{$clog2(HDATA_SIZE/8){1'b1}}; //do not double count address + byte-enables


  //Writebuffer
  always @(posedge HCLK)
    if (write)
      for (int i=0; i < HDATA_BYTES; i++)
        if (be[i]) writebuffer[nxt_pingpong][(idx + i)*8 +: 8] <= HWDATA[i*8 +: 8];


  //Byte enables
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        writebuffer_be[0] <= {$bits(writebuffer_be[0]){1'b0}};
        writebuffer_be[1] <= {$bits(writebuffer_be[1]){1'b0}};
    end
    else
    case ({write, pingpong_toggle})
      2'b00: ; //do nothing
      2'b01: writebuffer_be[pingpong]                     <= {BUFFER_BYTES{1'b0}};
      2'b10: writebuffer_be[pingpong][idx +: HDATA_BYTES] <= writebuffer_be[pingpong][idx +: HDATA_BYTES] | be;
      2'b11: begin
                 writebuffer_be[nxt_pingpong]                     <= {BUFFER_BYTES{1'b0}};
                 writebuffer_be[nxt_pingpong][idx +: HDATA_BYTES] <= be;
             end
    endcase


  //Dirty
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        writebuffer_dirty[0] <= 1'b0;
        writebuffer_dirty[1] <= 1'b0;
    end
    else
    begin
        if ( write             ) writebuffer_dirty[ nxt_pingpong] <= 1'b1;
        if ( wrreq_o && wrrdy_i) writebuffer_dirty[~pingpong    ] <= 1'b0;
    end


  //Timer
  always @(posedge HCLK, negedge HRESETn)
    if      ( !HRESETn                    ) writebuffer_timer <= {$bits(writebuffer_timer){1'b0}};
    else if ( !writebuffer_dirty[pingpong]) writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;
    else if (  write                      ) writebuffer_timer <= 1'h1 << csr_i.ctrl.writebuffer_timeout;
    else if (~|writebuffer_timer          ) writebuffer_timer <= writebuffer_timer -1'h1;

  always @(posedge HCLK, negedge HRESETn)
    if      (!HRESETn                        ) writebuffer_timer_expired <= 1'b0;
    else if (~|csr_i.ctrl.writebuffer_timeout) writebuffer_timer_expired <= 1'b0; //a CSR value of zero disables the timer
    else if (~|writebuffer_timer             ) writebuffer_timer_expired <= 1'b1;
    else if (  pingpong_toggle               ) writebuffer_timer_expired <= 1'b0;

    
  //Flush
  assign writebuffer_flush = (ahb_read  & writebuffer_dirty[       0] & (tag       == writebuffer_tag[       0])) |
                             (ahb_read  & writebuffer_dirty[       1] & (tag       == writebuffer_tag[       1])) |
                             (ahb_write & writebuffer_dirty[pingpong] & (write_tag != writebuffer_tag[pingpong]));


  //Read FSM
  always_comb
  begin
      rd_nxt_state = rd_state;
      hreadyout_rd = hreadyout_rd_reg;

      wbr    = wbr_o & ~rdrdy_i;
      rdreq  = rdreq_o;
      rdadr  = rdadr_o;
      rdsize = rdsize_o;

      case (rd_state)
        //wait for action
        rd_idle: if (HREADY)
                   if (ahb_read)
                   begin
                       rd_nxt_state = rd_read;
                       hreadyout_rd = 1'b0;  //insert wait states
                       wbr    = writebuffer_flush;

                       rdreq  = 1'b1;
                       rdadr  = HADDR;
                       rdsize = HSIZE; //handle HBURST and HSIZE, chop requests into max BUFFERSIZE transactions
                                             //all controllers say 'read always burst size'
                   end

        //wait for SDRAM to fill buffer
        rd_read: if (rdrdy_i)
                 begin
                     //wait for SDRAM to fill buffer
		     //output data to HRDATA
		     //end when all data transfered (counter?)
		     rd_nxt_state = rd_idle;
                     hreadyout_rd = 1'b1;
                     rdreq  = 1'b0;
                 end
        endcase
    end


  //Write FSM
  always_comb
  begin
      wr_nxt_state   = wr_state;
      hreadyout_wr   = hreadyout_wr_reg;

      wrreq    = wrreq_o & ~wrrdy_i;
      wradr    = wradr_o;
      wrsize   = wrsize_o;
      wrbe     = wrbe_o;
      wrd      = wrd_o;

      pingpong_toggle = 1'b0;

      case (wr_state)
        //wait for action
        wr_idle: if (HREADY)
                 begin
                     if ( (ahb_read || ahb_write) && writebuffer_flush) flush(wrrdy_i);
                 end
                 else if (writebuffer_timer_expired) flush(wrrdy_i); //timer expired

        //wait for pending wrreq to complete
        wr_wait: if (wrrdy_i) go_flush();
      endcase
    end


  //FSM registers
  always @(posedge HCLK, negedge HRESETn)
    if (!HRESETn)
    begin
        wr_state         <= wr_idle;
        rd_state         <= rd_idle;
	hreadyout_wr_reg <= 1'b1;
	hreadyout_rd_reg <= 1'b1;
        HREADYOUT        <= 1'b1;

        pingpong         <= 1'b0;

        wbr_o      <= 1'b0;

        wrreq_o    <= 1'b0;
        wradr_o    <= {$bits(wradr_o ){1'bx}};
        wrsize_o   <= {$bits(wrsize_o){1'bx}};
        wrbe_o     <= {$bits(wrbe_o  ){1'bx}};
        wrd_o      <= {$bits(wrd_o   ){1'bx}};

        rdreq_o    <= 1'b0;
        rdadr_o    <= {$bits(rdadr_o ){1'bx}};
        rdsize_o   <= {$bits(rdsize_o){1'bx}};
    end
    else
    begin
        wr_state         <= wr_nxt_state;
	rd_state         <= rd_nxt_state;
	hreadyout_wr_reg <= hreadyout_wr;
	hreadyout_rd_reg <= hreadyout_rd;
        HREADYOUT        <= hreadyout_wr & hreadyout_rd;

        pingpong         <= nxt_pingpong;

        wbr_o      <= wbr;

        wrreq_o    <= wrreq;
        wradr_o    <= wradr;
        wrsize_o   <= wrsize;
        wrbe_o     <= wrbe;
        wrd_o      <= wrd;

        rdreq_o    <= rdreq;
        rdadr_o    <= rdadr;
        rdsize_o   <= rdsize;
    end



  sdram_address_mapping #(
    .ADDR_SIZE ( HADDR_SIZE ),
    .MAX_CSIZE ( MAX_CSIZE  ),
    .MAX_RSIZE ( MAX_RSIZE  ),
    .BA_SIZE   ( BA_SIZE    ))
  map_addr_wr (
    .clk_i     ( HCLK       ),
    .csr_i     ( csr_i      ),
    .address_i ( wradr      ),
    .bank_o    ( wrba_o     ),
    .row_o     ( wrrow_o    ),
    .column_o  ( wrcol_o    )),
  map_addr_rd (
    .clk_i     ( HCLK       ),
    .csr_i     ( csr_i      ),
    .address_i ( rdadr      ),
    .bank_o    ( rdba_o     ),
    .row_o     ( rdrow_o    ),
    .column_o  ( rdcol_o    ));

endmodule : sdram_ahb_if
