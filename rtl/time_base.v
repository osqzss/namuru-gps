//                              -*- Mode: Verilog -*-
// Filename        : time_base.v
// Description     : Generates the TIC (tic_enable), preTIC (pre_tic_enable)
//                    ACCUM_INT (accum_enable) and accum_sample_enable.

//                  The accumulator sample rate is set at 40/7 MHz in this design.
//                  The accum_sample_enable pulse is derived from the sample clock
//                  driver for the 2015, but is on a different enable phase.

// Author          : Peter Mumford  UNSW 2005
// Modified by     : Takuji Ebinuma, 2026
/*
	Copyright (C) 2007  Peter Mumford
   Copyright (C) 2026  Takuji Ebinuma

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*/

`timescale 1ns/1ps

module time_base (clk, rstn, tic_divide, accum_divide, pre_tic_enable, tic_enable, accum_enable, tic_count, accum_count);
   
   input clk, rstn;
   input [23:0] tic_divide;
   input [23:0] accum_divide;
   output pre_tic_enable;
   output tic_enable; // to code_gen's
   output accum_enable; // accumulation interrupt
   output [23:0] tic_count; // the value of the TIC counter
   output [23:0] accum_count; // the value of the accum counter
   
   reg [23:0] tic_q;
   reg [23:0] accum_q;
   reg tic_shift; // used to delay TIC 1 clock cycles
   	
  //-------------------------------------------------------
  // generate the tic_enable
  // 
  // tic period = (tic_divide + 1) * clk_en period
  // If clock enabled by accum_sample_enable (= 16.368MHz):
  // tic period = (tic_divide + 1) / 16.368MHz
  // For default tic period (0.1s) tic_divide = 0x18F9BF
  //-------------------------------------------------------  
   /* 
   lpm_counter te(
		  .clock(clk),
		  .sclr(!rstn),
		  //.clk_en(accum_sample_enable),
		  .sload(pre_tic_enable),
		  .data(tic_divide),
		  .q(tic_q)
		  );
   defparam 	 te.lpm_direction="DOWN";
   defparam 	 te.lpm_width=24;
   */
   always @(posedge clk) begin
      if (!rstn) begin
         tic_q <= 24'b0;
      end
      else if (pre_tic_enable) begin
         tic_q <= tic_divide;
      end
      else begin
         tic_q <= tic_q - 24'b1;
      end
   end

  // The preTIC comes first latching the code_nco,
  // followed by the TIC latching everything else.
  // This is due to the delay between the code_nco phase
  // and the prompt code.
   assign 	 pre_tic_enable = (tic_q == 0)? 1'b1:1'b0;

   assign    tic_count = tic_q;
   
   always @ (posedge clk)
   begin
   if (!rstn) // set up shift register
	    begin
	    tic_shift <= 0;
	    end
	 else // run
	    begin
	    tic_shift <= pre_tic_enable;
	    end
   end // always @ (posedge clk)
   
   assign tic_enable = tic_shift;
	
  //---------------------------------------------------------
  // generate the accum_enable
  // 
  // The Accumulator interrupt signal and flag needs to have 
  // between 0.5 ms and about 1 ms period.
  // This is to ensure that accumulation data can be read
  // before it is written over by new data.
  // The accumulators are asynchronous to each other and have
  // a dump period of nominally 1ms.
  //
  // ACCUM_INT period = (accum_divide + 1) / 16.368MHz
  // For 0.9 ms accumulator interrupt
  // accum_divide = 16.368e6 * 0.0009 - 1 = 0x398A     
  //----------------------------------------------------------
   /*
   lpm_counter ae(
		  .clock(clk),
		  .sclr(!rstn),
		  //.clk_en(accum_sample_enable),
		  .sload(accum_enable),
		  .data(accum_divide),
		  .q(accum_q)
		  );
   defparam 	 ae.lpm_direction="DOWN";
   defparam 	 ae.lpm_width=24;
   */
   always @(posedge clk) begin
      if (!rstn) begin
         accum_q <= 24'b0;
      end
      else if (accum_enable) begin
         accum_q <= accum_divide;
      end
      else begin
         accum_q <= accum_q - 24'b1;
      end
   end

   assign 	 accum_enable = (accum_q == 0)? 1'b1:1'b0;
  
   assign    accum_count = accum_q;

endmodule // time_base
