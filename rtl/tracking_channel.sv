//                              -*- Mode: SystemVerilog -*-
// Filename        : tracking_channel.sv
// Description     : Wire the correlator block together.
//                   - 2 carrier_mixers
//                   - 1 carrier_nco
//                   - 1 code_nco
//                   - 1 code_gen
//                   - 1 epoch_counter
//                   - 6 accumulators
//
// Author          : Peter Mumford, UNSW 2005
// SystemVerilog rewrite : Takuji Ebinuma, 2026

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

module tracking_channel (
  input  logic        clk,
  input  logic        rstn,

  input  logic        if_sign,
  input  logic        if_mag,

  input  logic        pre_tic_enable,
  input  logic        tic_enable,

  input  logic [28:0] carr_nco_fc,
  input  logic [27:0] code_nco_fc,

  input  logic [9:0]  prn_key,
  input  logic        prn_key_enable,

  input  logic [10:0] code_slew,
  input  logic        slew_enable,
  input  logic        epoch_enable,

  input  logic [10:0] epoch_load,

  output logic        dump,

  output logic signed [15:0] i_early,
  output logic signed [15:0] q_early,
  output logic signed [15:0] i_prompt,
  output logic signed [15:0] q_prompt,
  output logic signed [15:0] i_late,
  output logic signed [15:0] q_late,

  output logic [31:0] carrier_val,
  output logic [20:0] code_val,

  output logic [10:0] epoch,
  output logic [10:0] epoch_check,

  output logic        test_point_01,
  output logic        test_point_02,
  output logic        test_point_03
);

  // Internal signals
  logic        carrier_i_mag,  carrier_q_mag;
  logic        carrier_i_sign, carrier_q_sign;

  logic        hc_enable, fc_enable;
  logic        dump_enable;

  logic        early_code, prompt_code, late_code;

  logic        mix_i_sign, mix_q_sign;
  logic [2:0]  mix_i_mag,  mix_q_mag;

  assign dump = dump_enable;

  // --------------------------------------------------------------------------
  // Carrier mixers
  // --------------------------------------------------------------------------
  carrier_mixer i_cos (
    .if_sign      (if_sign),
    .if_mag       (if_mag),
    .carrier_sign (carrier_i_sign),
    .carrier_mag  (carrier_i_mag),
    .mix_sign     (mix_i_sign),
    .mix_mag      (mix_i_mag)
  );

  carrier_mixer q_sin (
    .if_sign      (if_sign),
    .if_mag       (if_mag),
    .carrier_sign (carrier_q_sign),
    .carrier_mag  (carrier_q_mag),
    .mix_sign     (mix_q_sign),
    .mix_mag      (mix_q_mag)
  );

  // --------------------------------------------------------------------------
  // Carrier NCO
  // --------------------------------------------------------------------------
  carrier_nco carrnco (
    .clk         (clk),
    .rstn        (rstn),
    .tic_enable  (tic_enable),
    .f_control   (carr_nco_fc),
    .carrier_val (carrier_val),
    .i_sign      (carrier_i_sign),
    .i_mag       (carrier_i_mag),
    .q_sign      (carrier_q_sign),
    .q_mag       (carrier_q_mag)
  );

  // --------------------------------------------------------------------------
  // Code NCO
  // --------------------------------------------------------------------------
  code_nco codenco (
    .clk           (clk),
    .rstn          (rstn),
    .tic_enable    (pre_tic_enable),
    .f_control     (code_nco_fc),
    .hc_enable     (hc_enable),
    .code_nco_phase(code_val[9:0])
  );

  // --------------------------------------------------------------------------
  // Code generator
  // --------------------------------------------------------------------------
  code_gen codegen (
    .clk            (clk),
    .rstn           (rstn),
    .tic_enable     (tic_enable),
    .hc_enable      (hc_enable),
    .prn_key_enable (prn_key_enable),
    .prn_key        (prn_key),
    .code_slew      (code_slew),
    .slew_enable    (slew_enable),
    .dump_enable    (dump_enable),
    .code_phase     (code_val[20:10]),
    .fc_enable      (fc_enable),
    .early          (early_code),
    .prompt         (prompt_code),
    .late           (late_code)
  );

  // --------------------------------------------------------------------------
  // Epoch counter
  // --------------------------------------------------------------------------
  epoch_counter epc (
    .clk          (clk),
    .rstn         (rstn),
    .tic_enable   (tic_enable),
    .dump_enable  (dump_enable),
    .epoch_enable (epoch_enable),
    .epoch_load   (epoch_load),
    .epoch        (epoch),
    .epoch_check  (epoch_check)
  );

  // --------------------------------------------------------------------------
  // Accumulators
  // --------------------------------------------------------------------------
  // In-phase early
  accumulator ie (
    .clk             (clk),
    .rstn            (rstn),
    .code            (early_code),
    .carrier_mix_sign(mix_i_sign),
    .carrier_mix_mag (mix_i_mag),
    .dump_enable     (dump_enable),
    .accumulation    (i_early)
  );

  // In-phase prompt
  accumulator ip (
    .clk             (clk),
    .rstn            (rstn),
    .code            (prompt_code),
    .carrier_mix_sign(mix_i_sign),
    .carrier_mix_mag (mix_i_mag),
    .dump_enable     (dump_enable),
    .accumulation    (i_prompt)
  );

  // In-phase late
  accumulator il (
    .clk             (clk),
    .rstn            (rstn),
    .code            (late_code),
    .carrier_mix_sign(mix_i_sign),
    .carrier_mix_mag (mix_i_mag),
    .dump_enable     (dump_enable),
    .accumulation    (i_late)
  );

  // Quadrature-phase early
  accumulator qe (
    .clk             (clk),
    .rstn            (rstn),
    .code            (early_code),
    .carrier_mix_sign(mix_q_sign),
    .carrier_mix_mag (mix_q_mag),
    .dump_enable     (dump_enable),
    .accumulation    (q_early)
  );

  // Quadrature-phase prompt
  accumulator qp (
    .clk             (clk),
    .rstn            (rstn),
    .code            (prompt_code),
    .carrier_mix_sign(mix_q_sign),
    .carrier_mix_mag (mix_q_mag),
    .dump_enable     (dump_enable),
    .accumulation    (q_prompt)
  );

  // Quadrature-phase late
  accumulator ql (
    .clk             (clk),
    .rstn            (rstn),
    .code            (late_code),
    .carrier_mix_sign(mix_q_sign),
    .carrier_mix_mag (mix_q_mag),
    .dump_enable     (dump_enable),
    .accumulation    (q_late)
  );

  // --------------------------------------------------------------------------
  // Test points
  // --------------------------------------------------------------------------
  assign test_point_01 = hc_enable;
  assign test_point_02 = fc_enable;
  assign test_point_03 = prompt_code;

endmodule
