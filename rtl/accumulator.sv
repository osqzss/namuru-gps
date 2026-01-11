//                              -*- Mode: SystemVerilog -*-
// Filename        : accumulator.sv
// Description     : Accumulate-and-dump process
//
// Author          : Peter Mumford, UNSW, 2005
// Code updated    : Artyom Gavrilov, gnss-sdr.com, 2012
// SystemVerilog rewrite : Takuji Ebinuma, 2026

/*
  carrier_mix_sign provides the sign:
    0 for negative, 1 for positive.
  carrier_mix_mag is a 3-bit magnitude representing values {1, 2, 3, 6}.

  code is 0 or 1 representing -1 or +1 respectively.

  The multiplication of carrier_mix and code uses carrier_mix_mag as magnitude,
  with the sign determined by code and carrier_mix_sign:

    code              0 0 1 1
    carrier_mix_sign  0 1 0 1
                      -------
    result            1 0 0 1  (0 for -ve, 1 for +ve)

  Therefore:
    if (code == carrier_mix_sign) result is positive
    else                          result is negative
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

module accumulator (
  input  logic        clk,
  input  logic        rstn,
  input  logic        code,
  input  logic        carrier_mix_sign,
  input  logic [2:0]  carrier_mix_mag,
  input  logic        dump_enable,
  output logic signed [15:0] accumulation
);

  logic signed [15:0] accum_i;

  // Extend 3-bit magnitude to signed 16-bit for add/sub operations.
  logic signed [15:0] mag_ext;
  assign mag_ext = $signed({13'b0, carrier_mix_mag});

  always_ff @(posedge clk) begin
    if (!rstn) begin
      accumulation <= '0;
      accum_i      <= '0;
    end
    else if (dump_enable) begin
      // Latch the accumulated value, then start the next accumulation with current sample.
      accumulation <= accum_i;
      if (code == carrier_mix_sign)
        accum_i <= mag_ext;
      else
        accum_i <= -mag_ext;
    end
    else begin
      // Normal accumulate
      if (code == carrier_mix_sign)
        accum_i <= accum_i + mag_ext;
      else
        accum_i <= accum_i - mag_ext;
    end
  end

endmodule
