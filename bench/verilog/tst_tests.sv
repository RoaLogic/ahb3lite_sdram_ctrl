////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.         //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.   //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'   //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.   //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'   //
//                                             `---'              //
//                                                                //
//      SDRAM Controller Testbench                                //
//      Various tests                                             //
//                                                                //
////////////////////////////////////////////////////////////////////
//                                                                //
//     Copyright (C) 2023-2024 ROA Logic BV                       //
//     www.roalogic.com                                           //
//                                                                //
//     This source file may be used and distributed without       //
//   restrictions, provided that this copyright statement is      //
//   not removed from the file and that any derivative work       //
//   contains the original copyright notice and the associated    //
//   disclaimer.                                                  //
//                                                                //
//     This soure file is free software; you can redistribute     //
//   it and/or modify it under the terms of the GNU General       //
//   Public License as published by the Free Software             //
//   Foundation, either version 3 of the License, or (at your     //
//   option) any later versions.                                  //
//   The current text of the License can be found at:             //
//   http://www.gnu.org/licenses/gpl.html                         //
//                                                                //
//     This source file is distributed in the hope that it will   //
//   be useful, but WITHOUT ANY WARRANTY; without even the        //
//   implied warranty of MERCHANTABILITY or FITTNESS FOR A        //
//   PARTICULAR PURPOSE. See the GNU General Public License for   //
//   more details.                                                //
//                                                                //
////////////////////////////////////////////////////////////////////


/* Constants
 */
localparam int AHB_ADDRESS_BOUNDARY = 1024;

`define __DEBUG

/* Error counter
 */
int total, good, bad, ugly;

initial
begin
    total=0;
    good=0;
    bad =0;
    ugly=0;
end

task clear_error_counters;
  good=0;
  bad =0;
endtask

function automatic int min(input int a, b);
  return a < b ? a : b;
endfunction : min



/* Testbuffer
 * Buffer containing data to write/read
 * Compare to contents written to/read from SDRAM memory
 */
logic [SDRAM_DQ_SIZE  -1:0] test_buffer              [2**(2+SDRAM_ROWS+SDRAM_COLS)];
logic [SDRAM_DQ_SIZE/8-1:0] test_buffer_byte_written [2**(2+SDRAM_ROWS+SDRAM_COLS)];


// Fill test_buffer
task test_buffer_clear;
  foreach (test_buffer[i])
    test_buffer[i] = {SDRAM_DQ_SIZE{1'bx}};
endtask : test_buffer_clear

task test_buffer_fill_sequential;
  foreach (test_buffer[i])
    for (int b=0; b < SDRAM_DQ_SIZE/8; b++)
       test_buffer[i][b*8 +: 8] = i*(SDRAM_DQ_SIZE/8) +b;
endtask : test_buffer_fill_sequential

task test_buffer_fill_random;
  foreach (test_buffer[i])
    test_buffer[i] = $urandom;
endtask : test_buffer_fill_random


//SDRAM tasks in tst_sdram_lowlvl



/* Useful functions
 */
function automatic int hburst2int (input [HBURST_SIZE-1:0] hburst);
  case (hburst)
    HBURST_SINGLE: hburst2int = 1;
    HBURST_INCR  : hburst2int = 128;
    HBURST_WRAP4 : hburst2int = 4;
    HBURST_INCR4 : hburst2int = 4;
    HBURST_WRAP8 : hburst2int = 8;
    HBURST_INCR8 : hburst2int = 8;
    HBURST_WRAP16: hburst2int = 16;
    HBURST_INCR16: hburst2int = 16;
  endcase
endfunction : hburst2int

function automatic [HADDR_SIZE-1:0] hsize2adrmask (input [HSIZE_SIZE-1:0] hsize);
  case (hsize)
    HSIZE_B8   : hsize2adrmask = {HADDR_SIZE{1'b1}};
    HSIZE_B16  : hsize2adrmask = {HADDR_SIZE{1'b1}} << 1;
    HSIZE_B32  : hsize2adrmask = {HADDR_SIZE{1'b1}} << 2;
    HSIZE_B64  : hsize2adrmask = {HADDR_SIZE{1'b1}} << 3;
    HSIZE_B128 : hsize2adrmask = {HADDR_SIZE{1'b1}} << 4;
    HSIZE_B256 : hsize2adrmask = {HADDR_SIZE{1'b1}} << 5;
    HSIZE_B512 : hsize2adrmask = {HADDR_SIZE{1'b1}} << 6;
    HSIZE_B1024: hsize2adrmask = {HADDR_SIZE{1'b1}} << 7;
  endcase
endfunction : hsize2adrmask

function automatic [HADDR_SIZE-1:0] hsize2bytes (input [HSIZE_SIZE-1:0] hsize);
  case (hsize)
    HSIZE_B8   : hsize2bytes = 1;
    HSIZE_B16  : hsize2bytes = 2;
    HSIZE_B32  : hsize2bytes = 4;
    HSIZE_B64  : hsize2bytes = 8;
    HSIZE_B128 : hsize2bytes = 16;
    HSIZE_B256 : hsize2bytes = 32;
    HSIZE_B512 : hsize2bytes = 64;
    HSIZE_B1024: hsize2bytes = 128;
  endcase
endfunction : hsize2bytes


function automatic [15:0][127:0][7:0]urandom16384;
  for (int beats=0; beats < 16 ; beats++)
  for (int bytes=0; bytes < 128; bytes++)
    urandom16384[beats][bytes] = $urandom();
endfunction : urandom16384


/* -- SDRAM Access routines
 */
task automatic set_testbuffer_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst,
  input [15:0][127:0][7:0] data   //max 16beats * 128 bytes
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;
  int                    byteoffset;

  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;
          test_buffer[haddr / (SDRAM_DQ_SIZE/8)][ (haddr % (SDRAM_DQ_SIZE/8)) *8 +: 8] = data[beat][b];
      end

`ifdef __DEBUG
    haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize)) & adr_mask)
                       : start_haddr + (beat << hsize);
    $display("test_buffer[%0h]:%0h", haddr, test_buffer[haddr / (SDRAM_DQ_SIZE/8)]);
`endif
  end
endtask : set_testbuffer_memory


function automatic logic [15:0][127:0][7:0] get_testbuffer_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;
  int                    byteoffset;

  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;
          get_testbuffer_memory[beat][b] = test_buffer[haddr / (SDRAM_DQ_SIZE/8)][ (haddr % (SDRAM_DQ_SIZE/8)) *8 +: 8];
      end
  end
  endfunction : get_testbuffer_memory


function automatic bit cmp_testbuffer_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst,
  input [15:0][127:0][7:0] data   //max 16beats * 128 bytes
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;
  int                    byteoffset;

  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;

          if (test_buffer[haddr / (SDRAM_DQ_SIZE/8)][ (haddr % (SDRAM_DQ_SIZE/8)) *8 +: 8] !== data[beat][b])
begin
$display("haddr=%x, test_buffer=%x, sdram=%x", haddr, test_buffer[haddr / (SDRAM_DQ_SIZE/8)][ (haddr % (SDRAM_DQ_SIZE/8)) *8 +: 8], data[beat][b]);
            return 1'b0; //return false (not equal)
end
      end
  end

  //return true (equal)
  return 1'b1;
endfunction : cmp_testbuffer_memory



task automatic set_sdram_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst,
  input [15:0][127:0][7:0] data   //max 16beats * 128 bytes
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;
  int                    byteoffset;

  //write values to sdram
  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;
          byteoffset = 1'h1 << (haddr & ((2'h2 << SDRAM_DSIZE) -1'h1));
          poke_sdram(haddr, data[beat][b] << (8 * (byteoffset -1'h1)), byteoffset);
      end

`ifdef __DEBUG
    haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize)) & adr_mask)
                       : start_haddr + (beat << hsize);
    $display("sdram[%0h]:%0h", haddr, peek_sdram(haddr));
`endif
  end
endtask : set_sdram_memory


function automatic logic [15:0][127:0][7:0] get_sdram_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;

  //read values from sdram
  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;

          get_sdram_memory[beat][b] = peek_sdram(haddr)[(haddr % (2 << SDRAM_DSIZE)) *8 +: 8];
//$display("haddr=%x, sdram_memory=%x, sdram_beat=%x", haddr, peek_sdram(haddr), get_sdram_memory[beat][b]);
      end
  end
endfunction : get_sdram_memory


function automatic bit cmp_sdram_memory (
  input [HADDR_SIZE  -1:0] start_haddr,
  input [HSIZE_SIZE  -1:0] hsize,
  input [HBURST_SIZE -1:0] hburst,
  input [15:0][127:0][7:0] data   //max 16beats * 128 bytes
);
  int                    beats = ahb_hburst2beats(hburst);
  int                    bytes = ahb_hsize2bytes(hsize);
  logic                  wrap_burst = ahb_is_wrap_burst(hburst);
  logic [HADDR_SIZE-1:0] adr_mask = (beats << hsize) -1'h1;
  logic [HADDR_SIZE-1:0] haddr;
  int                    byteoffset;

  //write values to sdram
  for (int beat=0; beat < beats; beat++)
  begin
      for (int b=0; b < bytes; b++)
      begin
          haddr = wrap_burst ? (start_haddr & ~adr_mask) | ((start_haddr + (beat << hsize) +b) & adr_mask)
                             :  start_haddr + (beat << hsize) +b;
          byteoffset = 1'h1 << (haddr & ((2'h2 << SDRAM_DSIZE) -1'h1));

          if(peek_sdram(haddr)[(haddr % (2 << SDRAM_DSIZE)) *8 +: 8] !== data[beat][b] << (8 * (byteoffset -1'h1)))
            return 1'b0; //return false (not equal)
      end
  end

  //return true (equal)
  return 1'b1;
endfunction : cmp_sdram_memory








task automatic write_sdram_seq(
  input [HSIZE_SIZE-1:0 ] size,
  input [HBURST_SIZE-1:0] burst,
  input int               runs
);
  //filling sdram with sequential numbers
  //start at address 0 and fill memory
  int                                 run = 0;
  int                                 burstsize;
  logic        [SDRAM_ADDR_SIZE -1:0] adr;
  static logic [HDATA_SIZE-1:0]       wbuf[];

  //create write buffer
  burstsize = hburst2int(burst);
  wbuf = new[burstsize];

  //start at address 0
  adr = 0;

  while (run < runs)
  begin
      //fill write buffer
      foreach (wbuf[i])
        for (int b=0; b < HDATA_SIZE/8; b++)
          wbuf[i][b*8 +: 8] = run*(burstsize * (1 << size) /*HDATA_SIZE/8*/) +i*(1 << size) +b;

      //AHB write
      ahb_if[AHB_CTRL_PORT].ahb_bfm.write(adr, wbuf, size, burst);

      //next address
      adr = adr + (burstsize << size);

      //next run                
      run++;
  end

  //idle AHB bus
  ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

  wait fork;
endtask : write_sdram_seq


task automatic read_sdram_seq(
  input [HSIZE_SIZE-1:0 ] size,
  input [HBURST_SIZE-1:0] burst,
  input int               runs
);
  //Reading sdram sequentially
  //start at address 0
  int                                 run = 0;
  int                                 burstsize;
  logic        [SDRAM_ADDR_SIZE -1:0] adr;
  static logic [HDATA_SIZE-1:0]       rbuf[];

  //create read buffer
  burstsize = hburst2int(burst);
  rbuf = new[burstsize];

  //start at address 0
  adr = 0;

  while (run < runs)
  begin
      //AHB read
      ahb_if[AHB_CTRL_PORT].ahb_bfm.read(adr, rbuf, size, burst);

      //next address
      adr = adr + (burstsize << size);

      //next run
      run++;
  end

  //idle AHB bus
  ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

  wait fork;
endtask : read_sdram_seq


/* -- Write
 * Reads content from test_buffer and writes it to the SDRAM
 */
task automatic tst_write (
    input int               port,
    input [HADDR_SIZE -1:0] start_address,
    input [HSIZE_SIZE -1:0] hsize,
    input [HBURST_SIZE-1:0] hburst
);
  static logic [HDATA_SIZE-1:0] buffer[];
  logic                  wrap_burst;
  int                    wrap_size;
  logic [HADDR_SIZE-1:0] adr_mask;
  int                    offset;
  int                    beats;

  //Is this a wrapping burst?
  wrap_burst = ~hburst[0];

  //How many beats in a transaction
  beats = hburst2int(hburst);

  //calculate address mask
  if (wrap_burst) //strictly not necessary, but speeds up sims
  begin
      wrap_size = beats << hsize;
      adr_mask  = wrap_size -1;
  end

  //create new transaction buffer
  buffer = new[beats];

  //fill transaction buffer
  foreach(buffer[i])
    for (int b=0; b < HDATA_SIZE/8; b++)
    begin
        offset = wrap_burst ? (start_address & ~adr_mask) | ((start_address + (i << hsize) +b) & adr_mask)
                            : start_address + (i << hsize) +b;
        buffer[i][b*8 +: 8] = test_buffer[offset / (SDRAM_DQ_SIZE/8)][(offset % (SDRAM_DQ_SIZE/8)) *8 +: 8];
    end

  //AHB write
  ahb_if[AHB_CTRL_PORT].ahb_bfm.write(start_address, buffer, hsize, hburst);
endtask : tst_write


/* -- Read
 * Reads content from sdram and writes it to the testbuffer
 */
task automatic tst_read (
    input int               port,
    input [HADDR_SIZE -1:0] start_address,
    input [HSIZE_SIZE -1:0] hsize,
    input [HBURST_SIZE-1:0] hburst
);
  logic [HDATA_SIZE-1:0] buffer[];
  logic                  wrap_burst;
  int                    wrap_size;
  logic [HADDR_SIZE-1:0] adr_mask;
  int                    offset;
  int                    beats;

static int transaction=0;

  //Is this a wrapping burst?
  wrap_burst = ~hburst[0];

  //How many beats in a transaction
  beats = hburst2int(hburst);

  //calculate address mask
  if (wrap_burst) //strictly not necessary, but speeds up sims
  begin
      wrap_size = beats << hsize;
      adr_mask  = wrap_size -1;
  end

  //create new transaction buffer
//  buffer = new[beats];

  fork
     //AHB read
     ahb_if[AHB_CTRL_PORT].ahb_bfm.read(start_address, buffer, hsize, hburst);

     begin
         //prepare address phase
//$display ("1: @%0t", $realtime);
         do
           @(posedge HCLK);
         while (!HREADY[AHB_CTRL_PORT]);

         //wait for address phase (1st address is presented here)
//$display ("2: @%0t", $realtime);
         do
           @(posedge HCLK);
         while (!HREADY[AHB_CTRL_PORT]);
//$display ("3: @%0t", $realtime);

         //Data phase(s)
         for (int i=0; i < beats; i++)
         begin
//$display("4: @%0t", $realtime);
             do
               @(posedge HCLK);
             while (!HREADY[AHB_CTRL_PORT]);
//$display("5: @%0t", $realtime);

             for (int b=0; b < hsize2bytes(hsize); b++)
             begin
                 offset = wrap_burst ? (start_address & ~adr_mask) | ((start_address + (i << hsize) +b) & adr_mask)
                                     : start_address + (i << hsize) +b;
                 test_buffer[offset / (SDRAM_DQ_SIZE/8)][(offset % (SDRAM_DQ_SIZE/8)) *8 +: 8] = HRDATA[AHB_CTRL_PORT][(offset % (HDATA_SIZE/8)) *8 +: 8];
             end

`ifdef __DEBUG
             $display("test_buffer[%0h]:%0h, HRDATA=%h @%0t", offset/(SDRAM_DQ_SIZE/8), test_buffer[offset / (SDRAM_DQ_SIZE/8)], HRDATA[AHB_CTRL_PORT], $realtime);
`endif
         end
     end
  join_any
endtask : tst_read


/* -- Compare
 * Compares content of the SDRAM memory with the test_buffer form start_address to end_address
 */
task tst_compare (
  input [HADDR_SIZE-1:0] start_address, end_address
);

  logic [           7:0] test_buffer_value,   sdram_value;
  logic [HADDR_SIZE-1:0] test_buffer_address;

  localparam int dsize_bits = 16 << SDRAM_DSIZE;

  for (int adr=start_address; adr < end_address; adr++)
  begin
      test_buffer_address = adr / (SDRAM_DQ_SIZE/8);

`ifdef __DEBUG
//      $display ("adr=%h, buffer_adr=%h, sdram_adr=%h", adr, test_buffer_address, adr >> SDRAM_DSIZE >> 1);
`endif

      test_buffer_value = test_buffer[test_buffer_address][(adr % (SDRAM_DQ_SIZE / 8)) *8 +: 8];
      sdram_value       = peek_sdram(adr)[(adr % (2 << SDRAM_DSIZE)) *8 +: 8];

      total++;
      if ( test_buffer_value !== sdram_value )
      begin
          $display ("ERROR, compare mismatch for HADDR=%0h. Test_buffer=%2h, SDRAM=%2h @%0t", adr, test_buffer_value, sdram_value, $realtime);
          bad++; ugly++;
      end
      else
          good++;
  end

endtask : tst_compare



/* -- Actual tests
 */

// write sequential test
task tst_write_sequential (
  input int runs,
  input bit random
);
  logic wrap_burst;
  int hsize;
  int hburst;

  int total_start;
  int ugly_start;

  $display ("\n");
  $display ("-------------------------------------------------------------");
  $display (" tst_write_sequential started (%0s) @%0t", random ? "random data" : "sequential data", $realtime);
  $display ("-------------------------------------------------------------");

  if (random) test_buffer_fill_random();
  else        test_buffer_fill_sequential();

  total_start = total;
  ugly_start  = ugly;

  hsize  = 3'b000;
  hburst = 3'b011;
  for (hsize  = 0; hsize  < $clog2(HDATA_SIZE/8); hsize++)
  for (hburst = 0; hburst < 8;                    hburst++)
  begin
      if (hburst == HBURST_INCR) hburst++;

      wrap_burst = ~hburst[0];

      sdram_clear();
      clear_error_counters();

      $display ("tst_write_sequential; hsize=%3b, hburst=%3b", hsize, hburst);

      //perform writes
      for (int adr=0; adr < runs; adr++)
      begin
          //skip transactions that cross the AHB address boundary
/*          if (!wrap_burst &&
              ((adr & (AHB_ADDRESS_BOUNDARY-1)) + (hburst2int(hburst) << hsize) > AHB_ADDRESS_BOUNDARY)
             ) continue;
*/
          //perform AHB write
          tst_write(AHB_CTRL_PORT, adr, hsize, hburst);

          //show test progress
          if (adr % 500_000 == 0) $display("  run:%0d of %0d (%0d%%)", adr, runs, 100*adr/runs);
      end

      //idle AHB bus
      ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

      //wait for the writebuffer to commit contents
      repeat (100+WRITEBUFFER_TIMEOUT) @(posedge HCLK);

      //check results
      tst_compare(0, runs);

      $display(" --Done. Good=%0d, Bad=%0d, Ugly=%0d", good, bad, ugly);
  end

  $display ("-------------------------------------------------------------");
  $display (" tst_write_sequential finished @%0t", $realtime);
  $display (" Total tests: %0d, failed tests: %0d", total-total_start, ugly-ugly_start);
  $display ("-------------------------------------------------------------");

endtask : tst_write_sequential


// random write test
task tst_write_random (
  input int runs,
  input int haddr_range
);
  logic [HADDR_SIZE -1:0] haddr;
  logic [HSIZE_SIZE -1:0] hsize;
  logic [HBURST_SIZE-1:0] hburst;

  logic                  wrap_burst;
  int                    wrap_size;
  logic [HADDR_SIZE-1:0] adr_mask;
  int                    offset;
  int                    beats;

  int run;
  int total_start;
  int ugly_start;


  $display ("\n");
  $display ("-------------------------------------------------------------");
  $display (" tst_write_random started @%0t", $realtime);
  $display ("-------------------------------------------------------------");

  //clear test_buffer
  test_buffer_clear();

  //clear SDRAM
  sdram_clear();

  //clear error counters
  clear_error_counters();
  total_start = total;
  ugly_start  = ugly;

  for (run=0; run < runs; run++)
  begin
      haddr  = $urandom_range(0, haddr_range);
      hsize  = $urandom_range(0, $clog2(HDATA_SIZE/8));
      hburst = $urandom();

      //haddr must align with hsize
      haddr &= hsize2adrmask(hsize);

      //Ignore incrementing bursts
      if (hburst == HBURST_INCR) hburst++;

      //Is this a wrapping burst?
      wrap_burst = ~hburst[0];

      //How many beats in a transaction
      beats = hburst2int(hburst);

      //calculate address mask
      if (wrap_burst) //strictly not required, but speeds up sims
      begin
          wrap_size = beats << hsize;
          adr_mask  = wrap_size -1;
      end

      //write values to testbuffer
      for (int beat=0; beat < beats; beat++)
      begin
          for (int b=0; b < hsize2bytes(hsize); b++)
          begin
              offset = wrap_burst ? (haddr & ~adr_mask) | ((haddr + (beat << hsize) +b) & adr_mask)
                                  : haddr + (beat << hsize) +b;
              test_buffer[offset / (SDRAM_DQ_SIZE/8)][ (offset % (SDRAM_DQ_SIZE/8)) *8 +: 8] = $urandom();
          end

`ifdef __DEBUG
          offset = wrap_burst ? (haddr & ~adr_mask) | ((haddr + (beat << hsize)) & adr_mask)
                              : haddr + (beat << hsize);
          $display("test_buffer[%0h]:%0h", offset, test_buffer[offset / (SDRAM_DQ_SIZE/8)]);
`endif
      end

`ifdef __DEBUG
      $display ("tst_write_random; hsize=%3b, hburst=%3b, haddr=%h", hsize, hburst, haddr);
`endif

      //write values to SDRAM (controller)
      tst_write(AHB_CTRL_PORT, haddr, hsize, hburst);

      //show test progress
      if (run % 500_000 == 0) $display("  run:%0d of %0d (%0d%%)", run, runs, 100*run/runs);
  end

  //idle AHB bus
  ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

  //wait for the writebuffer to commit contents
  repeat (100+WRITEBUFFER_TIMEOUT) @(posedge HCLK);

  //check results
  tst_compare(0, haddr_range);

  $display ("-------------------------------------------------------------");
  $display (" tst_write_random finished @%0t", $realtime);
  $display (" Total tests: %0d, failed tests: %0d", total-total_start, ugly-ugly_start);
  $display ("-------------------------------------------------------------");

endtask : tst_write_random


// read sequential test
task tst_read_sequential (
  input int runs,
  input bit random
);
  logic wrap_burst;
  int hsize;
  int hburst;

  int total_start;
  int ugly_start;

  $display ("\n");
  $display ("-------------------------------------------------------------");
  $display (" tst_read_sequential started (%0s) @%0t", random ? "random data" : "sequential data", $realtime);
  $display ("-------------------------------------------------------------");

  if (random) sdram_fill_random();
  else        sdram_fill_sequential();

  total_start = total;
  ugly_start  = ugly;

  hsize  = 3'b010;
  hburst = 3'b000;
  for (hsize  = 0; hsize  <= $clog2(HDATA_SIZE/8); hsize++)
  for (hburst = 0; hburst < 8;                    hburst++)
//  for (hburst = 3'b010; hburst < 8; hburst += 2)
  begin
      if (hburst == HBURST_INCR) hburst++;

      wrap_burst = ~hburst[0];

      test_buffer_clear();
      clear_error_counters();

      $display ("tst_read_sequential; hsize=%3b, hburst=%3b", hsize, hburst);

      //perform reads
      for (int adr=0; adr < runs; adr+= (1'h1 << hsize))
      begin
          //perform AHB read
          tst_read(AHB_CTRL_PORT, adr, hsize, hburst);

          //show test progress
          if (adr % 500_000 == 0) $display("  run:%0d of %0d (%0d%%)", adr, runs, 100*adr/runs);
      end

      //idle AHB bus
      ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

      //wait for HREADY
      do
        @(posedge HCLK);
      while (!HREADY[AHB_CTRL_PORT]);

      //check results
      tst_compare(0, runs);

      $display(" --Done. Good=%0d, Bad=%0d, Ugly=%0d", good, bad, ugly);
  end

  $display ("-------------------------------------------------------------");
  $display (" tst_read_sequential finished");
  $display (" Total tests: %0d, failed tests: %0d", total-total_start, ugly-ugly_start);
  $display ("-------------------------------------------------------------");

endtask : tst_read_sequential


// random read test
task tst_read_random (
  input int runs,
  input int haddr_range
);
  logic [HADDR_SIZE    -1:0] haddr;
  logic [HSIZE_SIZE    -1:0] hsize;
  logic [HBURST_SIZE   -1:0] hburst;

  logic [SDRAM_DQ_SIZE -1:0] data;
  logic                      wrap_burst;
  int                        wrap_size;
  logic [HADDR_SIZE    -1:0] adr_mask;
  int                        offset;
  int                        beats;

  int run;
  int ten_percent;
  int total_start;
  int ugly_start;


  $display ("\n");
  $display ("-------------------------------------------------------------");
  $display (" tst_read_random started @%0t", $realtime);
  $display ("-------------------------------------------------------------");
  ten_percent = runs /10;

  //clear test_buffer
  test_buffer_clear();

  //clear SDRAM
  sdram_clear();

  //clear error counters
  clear_error_counters();
  total_start = total;
  ugly_start  = ugly;

  for (run=0; run < runs; run++)
  begin
      haddr  = $urandom_range(0, haddr_range);
      hsize  = $urandom_range(0, $clog2(HDATA_SIZE/8));
      hburst = $urandom();

      //haddr must align with hsize
      haddr &= hsize2adrmask(hsize);

      //Ignore incrementing bursts
      if (hburst == HBURST_INCR) hburst++;

      //Is this a wrapping burst?
      wrap_burst = ~hburst[0];

      //How many beats in a transaction
      beats = hburst2int(hburst);

      //calculate address mask
      if (wrap_burst) //strictly not required, but speeds up sims
      begin
          wrap_size = beats << hsize;
          adr_mask  = wrap_size -1;
      end

      //write values to sdram
      for (int beat=0; beat < beats; beat++)
      begin
          data = $urandom();
          for (int be=0; be < hsize2bytes(hsize); be++)
          begin
              offset = wrap_burst ? (haddr & ~adr_mask) | ((haddr + (beat << hsize) +be) & adr_mask)
                                  :  haddr + (beat << hsize) +be;
              poke_sdram(offset, data, 1'h1 << (offset & ((2'h2 << SDRAM_DSIZE) -1'h1)) );
          end

`ifdef __DEBUG
          offset = wrap_burst ? (haddr & ~adr_mask) | ((haddr + (beat << hsize)) & adr_mask)
                              : haddr + (beat << hsize);
          $display("sdram[%0h]:%0h", offset, peek_sdram(offset));
`endif
      end

`ifdef __DEBUG
      $display ("tst_read_random; hsize=%3b, hburst=%3b, haddr=%h", hsize, hburst, haddr);
`endif

      //read values from SDRAM (controller)
      tst_read(AHB_CTRL_PORT, haddr, hsize, hburst);

      //show test progress
      if (run % ten_percent == 0) $display("  run:%0d of %0d (%0d%%)", run, runs, 100*run/runs);
  end

  //idle AHB bus
  ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

  //check results
  tst_compare(0, haddr_range);


  $display ("-------------------------------------------------------------");
  $display (" tst_read_random finished @%0t", $realtime);
  $display (" Total tests: %0d, failed tests: %0d", total-total_start, ugly-ugly_start);
  $display ("-------------------------------------------------------------");

endtask : tst_read_random


// random read/write test
task tst_readwrite_random (
  input int runs,
  input int haddr_range,
  input int seed = 1299897866
);
  logic [HADDR_SIZE    -1:0] haddr;
  logic [HSIZE_SIZE    -1:0] hsize;
  logic [HBURST_SIZE   -1:0] hburst;
  logic                      hwrite;

  logic [15:0][127:0][7:0]   tmp_data;
  logic [SDRAM_DQ_SIZE -1:0] data;
  logic                      wrap_burst;
  int                        wrap_size;
  logic [HADDR_SIZE    -1:0] adr_mask;
  int                        offset;
  int                        beats;

  static process pt = process::self();
  int run;
  int show_percentage;
  int total_start;
  int ugly_start;

/*
  int fd;
  string line;

  fd = $fopen("/dev/urandom", "r");
  if (!$fgets(line, fd))
    $error("Cannot read seed value from /dev/urandom");
  else
    seed = int'(line);
  $fclose(fd);
*/

  $srandom(seed); //this should be srandom()
  
  $display ("\n");
  $display ("-------------------------------------------------------------");
  $display (" tst_readwrite_random started @%0t", $realtime);
  $display (" - randstate=%s", pt.get_randstate());
  $display (" - seed    =%0d", seed);
  $display ("-------------------------------------------------------------");
  show_percentage = min(runs /10, 100000);

  //clear test_buffer
  $display("Clear testbuffer");
  test_buffer_clear();

  //clear SDRAM
  $display("Clear SDRAM");
  sdram_clear();
  
  //fill test_buffer and sdram with (the same!) random data
  $display("Randomize testbuffer and SDRAM");
  hsize  = HSIZE_B1024;
  hburst = HBURST_INCR16;
  for (haddr=0; haddr < haddr_range; haddr = haddr + (1024 * 16))
  begin
      tmp_data = urandom16384();

      set_testbuffer_memory(haddr, hsize, hburst, tmp_data);
      set_sdram_memory(haddr, hsize, hburst, tmp_data);
  end


  //clear error counters
  clear_error_counters();
  total_start = total;
  ugly_start  = ugly;

  //range from [0,haddr_range>
  haddr_range = haddr_range -1;

  //run tests
  for (run=0; run < runs; run++)
  begin
      haddr  = $urandom_range(0, haddr_range);
      hsize  = $urandom_range(0, $clog2(HDATA_SIZE/8));
      hburst = $urandom();
      hwrite = $urandom();

      //don't roll over
      while (haddr + (ahb_hburst2beats(hburst) << hsize) > haddr_range) haddr = $urandom_range(0, haddr_range);

      //haddr must align with hsize
      haddr &= hsize2adrmask(hsize);

      //Ignore incrementing bursts
      if (hburst == HBURST_INCR) hburst++;

`ifdef __DEBUG
      $display ("tst_readwrite_random; hsize=%3b, hburst=%3b, haddr=%h, hwrite=%b", hsize, hburst, haddr, hwrite);
`endif

      //Is this a wrapping burst?
      wrap_burst = ~hburst[0];

      //How many beats in a transaction
      beats = hburst2int(hburst);

      //calculate address mask
      if (wrap_burst) //strictly not required, but speeds up sims
      begin
          wrap_size = beats << hsize;
          adr_mask  = wrap_size -1;
      end

      if (hwrite)
      begin
          //new random values for write
          //write values to testbuffer
          set_testbuffer_memory(haddr, hsize, hburst, urandom16384());

          //write values to SDRAM (controller)
          tst_write(AHB_CTRL_PORT, haddr, hsize, hburst);
      end
      else
      begin
          //write new data into SDRAM internal RAM
//          set_sdram_memory(haddr, hsize, hburst, urandom16384());

          //read values from SDRAM (controller)
          tst_read(AHB_CTRL_PORT, haddr, hsize, hburst);

          tmp_data = get_sdram_memory(haddr, hsize, hburst);
          if (!cmp_testbuffer_memory(haddr, hsize, hburst, tmp_data))
begin
            $display("ERROR: Not equal haddr=%0x, hsize=%0x, hburst=%0x @%0t", haddr, hsize, hburst, $time);
ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();
#1000 $finish();
end
      end


      //show test progress
      if (run % show_percentage == 0) $display("  run:%0d of %0d (%0d%%)", run, runs, 100.0*run/runs);
  end

  //idle AHB bus
  ahb_if[AHB_CTRL_PORT].ahb_bfm.idle();

  //wait for the writebuffer to commit contents
  repeat (100+WRITEBUFFER_TIMEOUT) @(posedge HCLK);

  //check results
  tst_compare(0, haddr_range);


  $display ("-------------------------------------------------------------");
  $display (" tst_readwrite_random finished @%0t", $realtime);
  $display (" Total tests: %0d, failed tests: %0d", total-total_start, ugly-ugly_start);
  $display ("-------------------------------------------------------------");

endtask : tst_readwrite_random

