//                              -*- Mode: SystemVerilog -*-
// Filename        : carrier_mixer.sv
// Description     : Mix together the incoming signal with the local carrier.
//
// Author          : Peter Mumford, UNSW, 2005
// SystemVerilog rewrite : Takuji Ebinuma, 2026

/*
  The IF raw data and carrier are two-bit quantities.
  Each has a sign bit and a magnitude bit.
  - IF_mag represents values {1, 3}
  - carrier_mag represents values {1, 2}

  mix_mag is three bits representing the values {1, 2, 3, 6}
  mix_sign is 0 for negative, 1 for positive.

  Truth table (magnitude):

    if_mag      | 0 0 1 1 |
    carrier_mag | 0 1 0 1 |
    output bits:
      mix_mag[0]| 1 0 1 0 | = ~carrier_mag
      mix_mag[1]| 0 1 1 1 | = if_mag | carrier_mag
      mix_mag[2]| 0 0 0 1 | = if_mag & carrier_mag
    ------------|---------|
      value     | 1 2 3 6 |

  Truth table (sign):
    if_sign      | 0 0 1 1 |  (0 = -ve, 1 = +ve)
    carrier_sign | 0 1 0 1 |
    mix_sign     | 1 0 0 1 |  = ~(if_sign ^ carrier_sign)
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

module carrier_mixer (
  input  logic       if_sign,
  input  logic       if_mag,
  input  logic       carrier_sign,
  input  logic       carrier_mag,
  output logic       mix_sign,
  output logic [2:0] mix_mag
);

  // Combinational mapping from the truth table
  assign mix_mag[0] = ~carrier_mag;
  assign mix_mag[1] =  if_mag | carrier_mag;
  assign mix_mag[2] =  if_mag & carrier_mag;

  // 1 = positive, 0 = negative
  assign mix_sign = ~(if_sign ^ carrier_sign);

endmodule
