//                              -*- Mode: SystemVerilog -*-
// Filename        : carrier_nco.sv
// Description     : Generates the 8-stage carrier local oscillator.
//
// Author          : Peter Mumford, UNSW, 2005
// SystemVerilog rewrite : Takuji Ebinuma, 2026

/*
  Numerically Controlled Oscillator (NCO) which replicates the carrier frequency.
  This pseudo-sinusoid waveform consists of 8 stages or phases.

  The NCO frequency is:
      f = fControl * Clk / 2^N
  where:
      f        = required carrier wave frequency
      Clk      = system clock
      N        = 30 (bit width of the phase accumulator)
      fControl = 29-bit (unsigned) control word in this implementation

  I & Q pseudo-waveforms (8 phases):
      Phase: 0  1  2  3  4  5  6  7
         I: +1 +2 +2 +1 -1 -2 -2 -1 (sin)
         Q: +2 +1 -1 -2 -2 -1 +1 +2 (cos)

  carrier_val latches on tic_enable:
      [9:0]   = carrier phase (10 MSBs of accumulator)
      [31:10] = cycle count between last two tic_enables
*/

/*
  Copyright (C) 2007  Peter Mumford

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

module carrier_nco (
  input  logic        clk,
  input  logic        rstn,
  input  logic        tic_enable,
  input  logic [28:0] f_control,

  output logic [31:0] carrier_val,
  output logic        i_sign,
  output logic        i_mag,   // in-phase carrier wave (sign/magnitude)
  output logic        q_sign,
  output logic        q_mag    // quadrature carrier wave (sign/magnitude)
);

  logic [29:0] accum_reg;
  logic [21:0] cycle_count_reg;

  logic [3:0]  phase_key;
  logic [30:0] accum_sum;
  logic        accum_carry;
  logic [31:0] combined_carr_value;

  // 30-bit phase accumulator
  always_ff @(posedge clk) begin
    if (!rstn) accum_reg <= '0;
    else       accum_reg <= accum_sum[29:0];
  end

  // Extend and add (match original bit growth)
  assign accum_sum   = {1'b0, accum_reg} + {2'b0, f_control}; // 31-bit sum
  assign accum_carry = accum_sum[30];
  assign phase_key   = accum_sum[29:26];

  // Combine cycle count and phase for carrier_val
  assign combined_carr_value[9:0]   = accum_reg[29:20];
  assign combined_carr_value[31:10] = cycle_count_reg;

  // Cycle counter and value latching
  always_ff @(posedge clk) begin
    if (!rstn) begin
      cycle_count_reg <= '0;
      carrier_val     <= '0;
    end
    else if (tic_enable) begin
      carrier_val     <= combined_carr_value; // latch carrier value
      cycle_count_reg <= '0;                  // reset cycle counter
    end
    else if (accum_carry) begin
      cycle_count_reg <= cycle_count_reg + 22'd1;
    end
  end

  // Lookup table for 8-phase pseudo-sinewave generation
  // Use always_comb to describe pure combinational logic.
  always_comb begin
    // Default assignments (avoid inferred latches)
    i_sign = 1'b0;
    i_mag  = 1'b0;
    q_sign = 1'b0;
    q_mag  = 1'b0;

    case (phase_key)
      // 0 degrees (phase 0): keys 15,0
      4'd15, 4'd0: begin
        i_sign = 1'b1; i_mag = 1'b0;
        q_sign = 1'b1; q_mag = 1'b1;
      end

      // 45 degrees (phase 1): keys 1,2
      4'd1, 4'd2: begin
        i_sign = 1'b1; i_mag = 1'b1;
        q_sign = 1'b1; q_mag = 1'b0;
      end

      // 90 degrees (phase 2): keys 3,4
      4'd3, 4'd4: begin
        i_sign = 1'b1; i_mag = 1'b1;
        q_sign = 1'b0; q_mag = 1'b0;
      end

      // 135 degrees (phase 3): keys 5,6
      4'd5, 4'd6: begin
        i_sign = 1'b1; i_mag = 1'b0;
        q_sign = 1'b0; q_mag = 1'b1;
      end

      // 180 degrees (phase 4): keys 7,8
      4'd7, 4'd8: begin
        i_sign = 1'b0; i_mag = 1'b0;
        q_sign = 1'b0; q_mag = 1'b1;
      end

      // 225 degrees (phase 5): keys 9,10
      4'd9, 4'd10: begin
        i_sign = 1'b0; i_mag = 1'b1;
        q_sign = 1'b0; q_mag = 1'b0;
      end

      // 270 degrees (phase 6): keys 11,12
      4'd11, 4'd12: begin
        i_sign = 1'b0; i_mag = 1'b1;
        q_sign = 1'b1; q_mag = 1'b0;
      end

      // 315 degrees (phase 7): keys 13,14
      4'd13, 4'd14: begin
        i_sign = 1'b0; i_mag = 1'b0;
        q_sign = 1'b1; q_mag = 1'b1;
      end

      default: begin
        // Keep defaults
      end
    endcase
  end

endmodule
