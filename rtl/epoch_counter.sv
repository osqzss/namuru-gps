//                              -*- Mode: SystemVerilog -*-
// Filename        : epoch_counter.sv
// Description     : Count the C/A code cycles.
//
// Author          : Peter Mumford, UNSW, 2005
// SystemVerilog rewrite : Takuji Ebinuma, 2026

/*
  C/A code cycles are counted by two counters:
    - 1 ms epoch counter (cycle counter): counts dump_enable pulses from 0 to 19
    - 20 ms epoch counter (bit counter): increments on every 20th dump (cycle rollover),
      counts from 0 to 49 to track message frame boundary

  Widths:
    - cycle_count: 5 bits
    - bit_count:   6 bits

  epoch is latched on tic_enable.
  epoch_check provides instantaneous values (updated every clock).
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

module epoch_counter (
  input  logic        clk,
  input  logic        rstn,
  input  logic        tic_enable,
  input  logic        dump_enable,
  input  logic        epoch_enable,
  input  logic [10:0] epoch_load,
  output logic [10:0] epoch,
  output logic [10:0] epoch_check
);

  logic [4:0] cycle_count;
  logic [5:0] bit_count;
  logic       cycle_count_overflow;

  // 1 ms epoch (C/A code cycle) counter: 0..19
  always_ff @(posedge clk) begin
    if (!rstn) begin
      cycle_count <= 5'd0;
    end
    else if (epoch_enable) begin
      cycle_count <= epoch_load[4:0];
    end
    else if (dump_enable) begin
      if (cycle_count_overflow)
        cycle_count <= 5'd0;
      else
        cycle_count <= cycle_count + 5'd1;
    end
  end

  // Detect rollover at 19
  assign cycle_count_overflow = (cycle_count == 5'd19);

  // 20 ms epoch (bit flip) counter: 0..49, increments on cycle rollover
  always_ff @(posedge clk) begin
    if (!rstn) begin
      bit_count <= 6'd0;
    end
    else if (epoch_enable) begin
      bit_count <= epoch_load[10:5];
    end
    else if (cycle_count_overflow && dump_enable) begin
      if (bit_count == 6'd49)
        bit_count <= 6'd0;
      else
        bit_count <= bit_count + 6'd1;
    end
  end

  // Latch epoch on TIC
  always_ff @(posedge clk) begin
    if (tic_enable) begin
      epoch[4:0]  <= cycle_count;
      epoch[10:5] <= bit_count;
    end
  end

  // Instantaneous epoch values (updated every clock)
  always_ff @(posedge clk) begin
    epoch_check[4:0]  <= cycle_count;
    epoch_check[10:5] <= bit_count;
  end

endmodule
