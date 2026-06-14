//                              -*- Mode: Verilog -*-
// Filename        : code_nco.v
// Description     : Generate the half-chip enable signal

// Author          : Peter Mumford, UNSW, 2005
// Modified by     : Takuji Ebinuma, 2026

/*
                 The Code_NCO creates the half-chip enable signal.
                 This drives the C/A code generator at the required frequency
                 (nominally 1.023MHz). The frequency must be adjusted by the
                 application code to align the incomming signal with the
                 generated C/A code replica and to account for clock error
                 (TCXO frequency error) and doppler.

                 The code_NCO provides the fine code phase (10 bit) value on
                 the TIC signal. 
					  
                 Note 1) 
					  The full-chip enable (fc_enable) is generated in the code_gen
                 module and is not aligned with the hc_enable.
                 The C/A code chip boundaries align to the fc_enable
                 not the hc_enable. This implies that the fine code phase obtained
                 from the code_nco that generates the hc_enable will be early by
                 one clock cycle. To account for this, the pre_tic_enable is used to
                 latch the code NCO phase. 

                 The NCO frequency is:

                    f = fControl * clk/2^N
                 
					  where:
                 
					     f = the required frequency
                    N = 28 (bit width of the phase accumulator)
                    clk = the system clock (= 16.368[MHz])
                    fControl = the 27-bit (unsigned) control word
 
                 To generate the C/A code at f, the NCO must be set to run
                 at 2f, therefore:
					  
                    code_frequency = 0.5 * fControl * clk/2^N

                 For a system clock running @ clk = 16.368[MHz]:
					  
                    fControl = code_frequency * 2^28 / (16.368/2)[Mhz]

                 For code_frequency = 1.023[MHz]
                 
					     fControl = 0x2000000
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

module code_nco (clk, rstn, tic_enable, f_control, hc_enable, code_nco_phase);
   
   input clk, rstn, tic_enable;
	input [26:0] f_control; // 27-bit control word
   output reg hc_enable;
   output reg [9:0] code_nco_phase;

	reg [27:0] accum_reg; // 28-bit accumulation register
   wire [28:0] accum_sum; // 28-bit accumulation register + carry
	wire accum_carry;
   reg [1:0] accum_carry_reg;

   // 28 bit phase accumulator
   always @ (posedge clk) begin
		if (!rstn) begin
			accum_reg <= 0;
		end
		else begin
			accum_reg <= accum_sum[27:0];
		end
	end

   assign accum_sum = accum_reg + f_control;
   assign accum_carry = accum_sum[28];
	
   // latch the top 10 bits on the tic_enable
   always @ (posedge clk) begin
		if (!rstn) code_nco_phase <= 0;
		else if (tic_enable) code_nco_phase <= accum_reg[27:18]; // 10-bit code phase
	end
	
	// detect edge of accumu_carry
	always @ (posedge clk) begin
		if (!rstn) accum_carry_reg <= 2'b00;
		else accum_carry_reg <= {accum_carry_reg[0],accum_carry};
	end
	
   // generate the half-chip enable
   always @ (posedge clk) begin
		if (!rstn) hc_enable <= 0;
		else if (accum_carry_reg==2'b01) begin
			hc_enable <= 1;
		end
		else hc_enable <= 0;
	end

endmodule // code_nco

 
   
 