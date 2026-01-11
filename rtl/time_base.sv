//                              -*- Mode: SystemVerilog -*-
// Filename        : time_base.sv
// Description     : Generates preTIC (pre_tic_enable), TIC (tic_enable),
//                   and ACCUM_INT (accum_enable).
//
// Author          : Peter Mumford, UNSW, 2005
// SystemVerilog rewrite : Takuji Ebinuma, 2026
//
// Notes:
// - TIC period  = (tic_divide + 1) * clk_period
// - ACCUM period = (accum_divide + 1) * clk_period
// - pre_tic_enable is asserted when the TIC counter reaches 0.
// - tic_enable is pre_tic_enable delayed by 1 clock (tic_shift).

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

module time_base (
  input  logic        clk,
  input  logic        rstn,
  input  logic [23:0] tic_divide,
  input  logic [23:0] accum_divide,
  output logic        pre_tic_enable,
  output logic        tic_enable,
  output logic        accum_enable,
  output logic [23:0] tic_count,
  output logic [23:0] accum_count
);

  logic [23:0] tic_q;
  logic [23:0] accum_q;
  logic        tic_shift;   // used to delay TIC by 1 clock cycle

  // --------------------------------------------------
  // Generate pre_tic_enable and tic_count
  // tic period = (tic_divide + 1) * Clk period
  // If clocked by MAX2769:
  // tic period = (tic_divide + 1) / 16.368 MHz
  // For default tic period (0.1s) tic_divide = 0x18F9BF
  // --------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      tic_q <= 24'd0;
    end
    else if (pre_tic_enable) begin
      // Reload divider after preTIC pulse
      tic_q <= tic_divide;
    end
    else if (tic_q == 24'd0) begin
      // Underflow protection (match original behavior)
      tic_q <= 24'hFF_FFFF;
    end
    else begin
      tic_q <= tic_q - 24'd1;
    end
  end

  // The preTIC comes first latching the code_nco,
  // followed by the TIC latching everything else.
  // This is due to the delay between the code_nco phase
  // and the prompt code.
  always_comb begin
    pre_tic_enable = (tic_q == 24'd0);
    tic_count      = tic_q;
  end

  // --------------------------------------------------
  // Delay preTIC by 1 clock to form TIC
  // --------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      tic_shift <= 1'b0;
    end
    else begin
      tic_shift <= pre_tic_enable;
    end
  end

  assign tic_enable = tic_shift;

  // --------------------------------------------------
  // Generate accum_enable and accum_count
  // 
  // The Accumulator interrupt signal and flag needs to have 
  // between 0.5 ms and about 1 ms period.
  // This is to ensure that accumulation data can be read
  // before it is written over by new data.
  // The accumulators are asynchronous to each other and have
  // a dump period of nominally 1ms.
  //
  // ACCUM_INT period = (accum_divide + 1) / 16.368 MHz
  // For 0.9 ms accumulator interrupt:
  // accum_divide = 163680000 * 0.0009 - 1
  // accum_divide = 0x398A	
  // --------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rstn) begin
      accum_q <= 24'd0;
    end
    else if (accum_enable) begin
      // Reload divider after accum_enable pulse
      accum_q <= accum_divide;
    end
    else if (accum_q == 24'd0) begin
      // Underflow protection (match original behavior)
      accum_q <= 24'hFF_FFFF;
    end
    else begin
      accum_q <= accum_q - 24'd1;
    end
  end

  // accum_enable asserted when counter reaches 0
  always_comb begin
    accum_enable = (accum_q == 24'd0);
    accum_count  = accum_q;
  end

endmodule
