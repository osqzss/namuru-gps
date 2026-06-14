//                              -*- Mode: Verilog -*-
// Filename        : carrier_nco.v
// Description     : Generates the 8 stage carrier local oscilator.

// Author          : Peter Mumford, UNSW, 2005
// Modified by     : Takuji Ebinuma, 2026

/*
                 Numerically Controlled Oscillator (NCO) which replicates the
                 carrier frequency. This pseudo-sinusoid waveform consists of
                 8 stages or phases.

                 The NCO frequency is:
                
                    f = fControl * Clk / 2^N
                 
					  where:
					     
						  f = the required carrier wave frequency
                    Clk = the system clock (= 16.368[MHz])
                    N = 29 (bit width of the phase accumulator)
                    fControl = the 28-bit (unsigned) control word 
 
                 The generated waveforms for I & Q look like:
                 Phase   :  0  1  2  3  4  5  6  7
                 ---------------------------------
                        I: +2 +1 -1 -2 -2 -1 +1 +2 ( cos)
                        Q: -1 -2 -2 -1 +1 +2 +2 +1 (-sin)

                 The nominal center frequency for NAMURU-Nano is:
                 
					     IF = 4.092[MHz]
                    Clk = 16.368[MHz]
                    fControl = 2^N * IF / Clk
                    fControl = 0x800_0000 for center frequency

                 Resolution:
                 
					  fControl increment value = 30.4877758[mHz]
                 
					  Put another way:
                 30.5mHz is the smallest change in carrier frequency possible
                 with this NCO.
 
                 The carrier phase and carrier cycle count are latched into
                 the carrier_val on the tic_enable. The carrier phase is the
                 10 msb of the accumulator register (accum_reg). The cycle count
                 is the number of full carrier wave cycles between the last 2
                 tic_enables. The two values are combined into the carrier_val.
                 Bits 9:0 are the carrier phase, bits 31:10 are the cycle count.
 */
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

module carrier_nco (clk, rstn, tic_enable, f_control, carrier_val, i_sign, i_mag, q_sign, q_mag);

   input clk, rstn, tic_enable;
   input [27:0] f_control; //  28-bit control word
   output reg [31:0] carrier_val;
   output reg i_sign, i_mag; // in-phase (cos) carrier wave, 0 -> -, 1 -> +
   output reg q_sign, q_mag; // quadrature (-sin) carrier wave, 0 -> 1, 1 -> 2

   reg [28:0] accum_reg; // 29-bit accumulation register
   wire [29:0] accum_sum; // 29-bit accumulation register + carry
   wire	accum_carry;
	
	wire [3:0] phase_key;
	
	reg [21:0] cycle_count_reg;
   wire [31:0] combined_carr_value;
   
   // 29 bit phase accumulator
   always @ (posedge clk) begin
		if (!rstn) begin
			accum_reg <= 0;
		end
		else begin
			accum_reg <= accum_sum[28:0];
		end
   end

   assign accum_sum = accum_reg + f_control;
   assign accum_carry = accum_sum[29];
	
   assign phase_key = accum_sum[28:25]; // the top 4-bit of the accumulation register
   
   assign combined_carr_value[9:0] = accum_reg[28:19]; // 10-bit carrier phase
   assign combined_carr_value[31:10] = cycle_count_reg; // 22-bit cycle counter
   
   // cycle counter and value latching
   always @ (posedge clk)
   begin
	 if (!rstn) cycle_count_reg <= 0;
	 else if (tic_enable)
      begin
	   carrier_val = combined_carr_value; // latch in carrier value, then...
      cycle_count_reg = 0; // reset counter
	   end
	 else if (accum_carry)
      cycle_count_reg <= cycle_count_reg + 1'b1;
   end

   // look up table for carrier pseudo-sinewave generation
   always @ (phase_key)
     // ?? is there a way to have or'ed values in case statements ??
     case (phase_key)
       // 5  225 degrees
       10 : begin
         i_sign <= 0;
         i_mag <= 0;
         q_sign <= 1;
         q_mag <= 1;
       end
       11 : begin
         i_sign <= 0;
         i_mag <= 0;
         q_sign <= 1;
         q_mag <= 1;
       end
       
       // 6  270 degrees
       12 : begin
	       i_sign <= 1;
	       i_mag <= 0;
	       q_sign <= 1;
	       q_mag <= 1;
       end
       13 : begin
	       i_sign <= 1;
	       i_mag <= 0;
	       q_sign <= 1;
	       q_mag <= 1;
       end
       
       // 7  315 degrees
       14 : begin
	       i_sign <= 1;
	       i_mag <= 1;
	       q_sign <= 1;
	       q_mag <= 0;
       end
       15 : begin
	       i_sign <= 1;
	       i_mag <= 1;
	       q_sign <= 1;
	       q_mag <= 0;
       end
       
       // 0  0 degrees
       0 : begin
	       i_sign <= 1;
	       i_mag <= 1;
	       q_sign <= 0;
	       q_mag <= 0;
       end
       1 : begin
	       i_sign <= 1;
	       i_mag <= 1;
	       q_sign <= 0;
	       q_mag <= 0;
       end
       
       // 1  45 degrees
       2 : begin
	       i_sign <= 1;
	       i_mag <= 0;
	       q_sign <= 0;
	       q_mag <= 1;
       end
       3 : begin
	       i_sign <= 1;
	       i_mag <= 0;
	       q_sign <= 0;
	       q_mag <= 1;
       end
       
       // 2  90 degrees
       4 : begin
	       i_sign <= 0;
	       i_mag <= 0;
	       q_sign <= 0;
	       q_mag <= 1;
       end
       5 : begin
	        i_sign <= 0;
	        i_mag <= 0;
	        q_sign <= 0;
	        q_mag <= 1;
       end
       
       // 3  135 degrees
       6 : begin
	        i_sign <= 0;
	        i_mag <= 1;
	        q_sign <= 0;
	        q_mag <= 0;
       end
       7 : begin
	        i_sign <= 0;
	        i_mag <= 1;
	        q_sign <= 0;
	        q_mag <= 0;
       end
       
       // 4  180 degrees
       8 : begin
	        i_sign <= 0;
	        i_mag <= 1;
	        q_sign <= 1;
	        q_mag <= 0;
       end
       9 : begin
	        i_sign <= 0;
	        i_mag <= 1;
	        q_sign <= 1;
	        q_mag <= 0;
       end
     endcase // case(phase_key)
endmodule // carrier_nco

	  
       
       
       
