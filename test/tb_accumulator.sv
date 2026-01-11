/*
  Testbench for accumulator.sv (Icarus Verilog friendly, race-free)

  Requirements:
    - Clock frequency: 16.368 MHz
    - code: 0 => -1, 1 => +1
    - carrier_mix_mag takes one of {1,2,3,6} using 3-bit encodings:
        1 -> 3'b001, 2 -> 3'b010, 3 -> 3'b011, 6 -> 3'b110
    - carrier_mix_sign indicates the sign of carrier_mix_mag:
        0 => negative, 1 => positive
    - Verify that 'accumulation' latched on dump_enable matches expected value.

  Key point:
    - Inputs are driven synchronously on posedge (like real upstream FFs).
    - Scoreboard snapshots the DUT-visible inputs at each posedge using BLOCKING
      assignments (code_v/sign_v/mag_v/dump_v) to avoid 1-cycle NBA skew.
*/

`timescale 1ps/1ps

module tb_accumulator;

  // ----------------------------
  // Clock (16.368 MHz)
  // ----------------------------
  // Period = 1 / 16.368e6 = 61.095... ns, half = 30.5475... ns
  // With 1 ps resolution we round half period to 30548 ps.
  localparam integer CLK_HALF_PS = 30548;

  reg clk;
  reg rstn;

  // ----------------------------
  // DUT inputs (driven at posedge)
  // ----------------------------
  reg       code;
  reg       carrier_mix_sign;
  reg [2:0] carrier_mix_mag;
  reg       dump_enable;

  // DUT output
  wire signed [15:0] accumulation;

  // ----------------------------
  // DUT instance
  // ----------------------------
  accumulator dut (
    .clk              (clk),
    .rstn             (rstn),
    .code             (code),
    .carrier_mix_sign (carrier_mix_sign),
    .carrier_mix_mag  (carrier_mix_mag),
    .dump_enable      (dump_enable),
    .accumulation     (accumulation)
  );

  // Clock generation
  initial clk = 1'b0;
  always #(CLK_HALF_PS) clk = ~clk;

  // ----------------------------
  // Test vectors (simple arrays for Icarus compatibility)
  // ----------------------------
  localparam integer VEC_LEN        = 18;
  localparam integer EXPECTED_DUMPS = 4;

  reg       code_vec [0:VEC_LEN-1];
  reg       sign_vec [0:VEC_LEN-1];
  reg [2:0] mag_vec  [0:VEC_LEN-1];
  reg       dump_vec [0:VEC_LEN-1];

  integer vec_idx;

  // Build vectors and handle reset
  initial begin
    // Optional waveform dump (enable only if needed; VCD slows vvp a lot)
    // $dumpfile("accumulator.vcd");
    // $dumpvars(0, tb_accumulator);

    // Initialize signals
    rstn             = 1'b0;
    code             = 1'b0;
    carrier_mix_sign = 1'b0;
    carrier_mix_mag  = 3'b001; // 1
    dump_enable      = 1'b0;

    vec_idx          = 0;

    // -------- Pattern A: 5 samples, dump on 6th --------
    // Samples: +1, -2, -3, +6, +2 => sum = +4 (latched at dump #0)
    // Dump cycle current sample: -1 (internal accum resets to -1)
    code_vec[0]=1; sign_vec[0]=1; mag_vec[0]=3'b001; dump_vec[0]=0; // +1
    code_vec[1]=0; sign_vec[1]=1; mag_vec[1]=3'b010; dump_vec[1]=0; // -2
    code_vec[2]=1; sign_vec[2]=0; mag_vec[2]=3'b011; dump_vec[2]=0; // -3
    code_vec[3]=0; sign_vec[3]=0; mag_vec[3]=3'b110; dump_vec[3]=0; // +6
    code_vec[4]=1; sign_vec[4]=1; mag_vec[4]=3'b010; dump_vec[4]=0; // +2
    code_vec[5]=1; sign_vec[5]=0; mag_vec[5]=3'b001; dump_vec[5]=1; // dump, current=-1

    // -------- Pattern B: 3 samples, dump on 4th --------
    // Starting from internal=-1:
    // add +3 => 2, add -1 => 1, add +6 => 7 => latched at dump #1 should be 7
    // Dump cycle current sample: -2 (internal resets to -2)
    code_vec[6]=0; sign_vec[6]=0; mag_vec[6]=3'b011; dump_vec[6]=0; // +3
    code_vec[7]=0; sign_vec[7]=1; mag_vec[7]=3'b001; dump_vec[7]=0; // -1
    code_vec[8]=1; sign_vec[8]=1; mag_vec[8]=3'b110; dump_vec[8]=0; // +6
    code_vec[9]=0; sign_vec[9]=1; mag_vec[9]=3'b010; dump_vec[9]=1; // dump, current=-2

    // -------- Pattern C: multiple dumps --------
    // Starting from internal=-2:
    // +3 => 1, -6 => -5, +2 => -3, -3 => -6 => latched at dump #2 should be -6
    // Dump cycle current sample: +1 (internal resets to +1)
    code_vec[10]=1; sign_vec[10]=1; mag_vec[10]=3'b011; dump_vec[10]=0; // +3
    code_vec[11]=1; sign_vec[11]=0; mag_vec[11]=3'b110; dump_vec[11]=0; // -6
    code_vec[12]=0; sign_vec[12]=0; mag_vec[12]=3'b010; dump_vec[12]=0; // +2
    code_vec[13]=0; sign_vec[13]=1; mag_vec[13]=3'b011; dump_vec[13]=0; // -3
    code_vec[14]=1; sign_vec[14]=1; mag_vec[14]=3'b001; dump_vec[14]=1; // dump, current=+1

    // Starting from internal=+1:
    // +6 => 7, -2 => 5 => latched at dump #3 should be 5
    // Dump cycle current sample: +1 (internal resets to +1)
    code_vec[15]=0; sign_vec[15]=0; mag_vec[15]=3'b110; dump_vec[15]=0; // +6
    code_vec[16]=1; sign_vec[16]=0; mag_vec[16]=3'b010; dump_vec[16]=0; // -2
    code_vec[17]=1; sign_vec[17]=1; mag_vec[17]=3'b001; dump_vec[17]=1; // dump, current=+1

    // Release reset after a few clocks
    repeat (5) @(posedge clk);
    rstn = 1'b1;
  end

  // Drive inputs on posedge (matches "other modules generate on posedge" requirement)
  always @(posedge clk) begin
    if (!rstn) begin
      vec_idx          <= 0;
      code             <= 1'b0;
      carrier_mix_sign <= 1'b0;
      carrier_mix_mag  <= 3'b001;
      dump_enable      <= 1'b0;
    end
    else begin
      if (vec_idx < VEC_LEN) begin
        code             <= code_vec[vec_idx];
        carrier_mix_sign <= sign_vec[vec_idx];
        carrier_mix_mag  <= mag_vec[vec_idx];
        dump_enable      <= dump_vec[vec_idx];
        vec_idx          <= vec_idx + 1;
      end
      else begin
        dump_enable <= 1'b0;
      end
    end
  end

  // ----------------------------
  // Reference model and checker
  // ----------------------------
  integer accum_ref;
  integer expected_latched;
  integer dump_count;

  function integer sample_value;
    input reg c;
    input reg s;
    input reg [2:0] m;
    integer mag_int;
    begin
      mag_int = m; // allowed encodings yield 1,2,3,6
      if (c == s) sample_value = +mag_int;
      else        sample_value = -mag_int;
    end
  endfunction

  always @(posedge clk) begin
    // Snapshot DUT-visible inputs at THIS posedge (blocking assignment)
    reg       code_v;
    reg       sign_v;
    reg [2:0] mag_v;
    reg       dump_v;

    code_v = code;
    sign_v = carrier_mix_sign;
    mag_v  = carrier_mix_mag;
    dump_v = dump_enable;

    if (!rstn) begin
      accum_ref   <= 0;
      dump_count  <= 0;
    end
    else begin
      if (dump_v) begin
        expected_latched = accum_ref;

        // Allow DUT nonblocking assignments to settle
        #1;

        if ($signed(accumulation) !== $signed(expected_latched)) begin
          $display("ERROR @ t=%0t ps: dump #%0d", $time, dump_count);
          $display("  Expected accumulation = %0d", expected_latched);
          $display("  Got      accumulation = %0d", $signed(accumulation));
          $display("  Inputs at dump edge: code=%0d sign=%0d mag=%0d (0b%b)",
                   code_v, sign_v, mag_v, mag_v);
          $fatal(1, "Accumulator mismatch.");
        end
        else begin
          $display("OK    @ t=%0t ps: dump #%0d accumulation=%0d",
                   $time, dump_count, expected_latched);
        end

        dump_count <= dump_count + 1;

        // After dump, DUT resets internal accumulator to CURRENT sample
        accum_ref <= sample_value(code_v, sign_v, mag_v);
      end
      else begin
        // Normal accumulation
        accum_ref <= accum_ref + sample_value(code_v, sign_v, mag_v);
      end

      if (dump_count == EXPECTED_DUMPS) begin
        $display("PASS: Completed accumulator checks. dumps=%0d", dump_count);
        $finish;
      end
    end
  end

endmodule
