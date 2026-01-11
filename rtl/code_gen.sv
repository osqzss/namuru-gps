//                              -*- Mode: SystemVerilog -*-
// Filename        : code_gen.sv
// Description     : Generates early, prompt and late C/A code chips.
//                   Also outputs fc_enable (full-chip enable pulse).
//
// Author          : Peter Mumford, 2005, UNSW
// SystemVerilog rewrite : Takuji Ebinuma, 2026

module code_gen (
  input  logic        clk,
  input  logic        rstn,

  input  logic        tic_enable,        // TIC
  input  logic        hc_enable,         // half-chip enable pulse from code_nco

  input  logic        prn_key_enable,    // latch prn_key and reset logic
  input  logic [9:0]  prn_key,           // selects satellite PRN code (G2 init)

  input  logic [10:0] code_slew,         // number of half-chips to delay after next dump
  input  logic        slew_enable,       // sets slew_flag

  output logic        dump_enable,       // pulse at beginning/end of prompt C/A code cycle
  output logic [10:0] code_phase,        // half-chip phase at TIC
  output logic        fc_enable,         // full-chip enable pulse
  output logic        early,
  output logic        prompt,
  output logic        late
);

  // G1/G2 registers
  logic [9:0] g1, g2;
  logic       g1_q, g2_q;

  logic       ca_code;
  logic [2:0] srq;

  // Counters and slew logic
  logic [10:0] hc_count1;
  logic [10:0] hc_count3;

  logic [10:0] slew;
  logic [11:0] hc_count2;
  logic [11:0] max_count2;

  logic        slew_flag;
  logic        slew_trigger;

  logic [2:0]  shft_reg;

  // --------------------------------------------------------------------------
  // G1 shift register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      g1_q <= 1'b0;
      g1   <= 10'b1111111111;
    end
    else if (fc_enable) begin
      g1_q <= g1[0];
      g1   <= {(g1[7] ^ g1[0]), g1[9:1]};
    end
  end

  // --------------------------------------------------------------------------
  // G2 shift register
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      g2_q <= 1'b0;
      g2   <= prn_key;
    end
    else if (fc_enable) begin
      g2_q <= g2[0];
      g2   <= {(g2[8] ^ g2[7] ^ g2[4] ^ g2[2] ^ g2[1] ^ g2[0]), g2[9:1]};
    end
  end

  assign ca_code = g1_q ^ g2_q;

  // --------------------------------------------------------------------------
  // Half-chip spaced shift register for early/prompt/late (sample at hc_enable)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      shft_reg <= 3'b000;
    end
    else if (hc_enable) begin
      shft_reg <= {shft_reg[1:0], ca_code};
    end
  end

  assign srq    = shft_reg;
  assign early  = srq[0];
  assign prompt = srq[1];
  assign late   = srq[2];

  // --------------------------------------------------------------------------
  // Counter 3: counts hc_enable, reset on dump_enable; latched to code_phase on TIC
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable || dump_enable) begin
      hc_count3 <= 11'd0;
    end
    else if (hc_enable) begin
      hc_count3 <= hc_count3 + 11'd1;
    end
  end

  // Latch code phase at TIC
  always_ff @(posedge clk) begin
    if (tic_enable) begin
      code_phase <= hc_count3;
    end
  end

  // --------------------------------------------------------------------------
  // Full-chip enable generator (fc_enable)
  // - Normally fc_enable pulses every 2 hc_enable pulses.
  // - When slewing, fc_enable is delayed by 'slew' half-chips.
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      hc_count1 <= 11'd0;
      fc_enable <= 1'b0;
      slew      <= 11'd0;
    end
    else begin
      // Default: pulse is 0 unless explicitly generated
      fc_enable <= 1'b0;

      if (slew_trigger) begin
        slew <= code_slew;
      end

      if (hc_enable) begin
        if (slew == 11'd0) begin
          if (hc_count1 == 11'd1) begin
            hc_count1 <= 11'd0;
            fc_enable <= 1'b1;   // generate pulse
          end
          else begin
            hc_count1 <= hc_count1 + 11'd1;
          end
        end
        else begin
          slew <= slew - 11'd1;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // dump_enable generator
  // - dump_enable asserted when hc_count2 == 3
  // - hc_count2 rolls over at max_count2 (normally 2045, extended by slew)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      dump_enable  <= 1'b0;
      hc_count2    <= 12'd0;
      slew_trigger <= 1'b0;
      max_count2   <= 12'd2045;
    end
    else if (hc_enable) begin
      hc_count2 <= hc_count2 + 12'd1;

      if (hc_count2 == 12'd3) begin
        dump_enable <= 1'b1;
      end
      else begin
        dump_enable <= 1'b0;
      end

      if (hc_count2 == max_count2) begin
        hc_count2 <= 12'd0;
      end
      else if (hc_count2 == 12'd1) begin
        if (slew_flag) begin
          slew_trigger <= 1'b1;
          max_count2   <= 12'd2045 + {1'b0, code_slew}; // extend cycle length
        end
        else begin
          max_count2 <= 12'd2045;
        end
      end
      else begin
        slew_trigger <= 1'b0;
      end
    end
    else begin
      dump_enable  <= 1'b0;
      slew_trigger <= 1'b0;
    end
  end

  // --------------------------------------------------------------------------
  // slew_flag: set by slew_enable, cleared by dump_enable
  // --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (prn_key_enable) begin
      slew_flag <= 1'b0;
    end
    else if (slew_enable) begin
      slew_flag <= 1'b1;
    end
    else if (dump_enable) begin
      slew_flag <= 1'b0;
    end
  end

endmodule
