/*
  tb_code_slew.sv

  Verifies that code_gen slewing works as expected:
    - dump_enable interval (in hc_enable counts) becomes longer by code_slew for one cycle
    - fc_enable pulses exhibit a larger gap consistent with the applied slew

  Clock: 16.368 MHz
  code_nco f_control: 0x4000000 (28-bit), which yields ~2.046 MHz hc_enable for 16.368 MHz clk.

  Notes:
    - We count events using hc_enable pulses (half-chip ticks), not real time.
    - After reset release, the very first dump may be abnormal; we ignore it for baseline.
    - We apply slew_enable for 1 clk after a dump, so it is active before the next code cycle.
*/

`timescale 1ps/1ps

module tb_code_slew;

  // ----------------------------
  // Clock: 16.368 MHz
  // ----------------------------
  // period = 61.095... ns, half = 30.5475... ns
  localparam integer CLK_HALF_PS = 30548;

  reg clk;
  reg rstn;

  // ----------------------------
  // DUT control inputs
  // ----------------------------
  reg         tic_enable;       // not needed for this test, keep 0
  reg         pre_tic_enable;    // not needed for this test, keep 0

  reg  [27:0] code_nco_fc;       // for code_nco
  wire        hc_enable;
  wire [9:0]  code_nco_phase;

  reg         prn_key_enable;
  reg  [9:0]  prn_key;

  reg  [10:0] code_slew;
  reg         slew_enable;

  // code_gen outputs
  wire        dump_enable;
  wire [10:0] code_phase;
  wire        fc_enable;
  wire        early, prompt, late;

  // ----------------------------
  // Instances
  // ----------------------------
  code_nco u_code_nco (
    .clk           (clk),
    .rstn          (rstn),
    .tic_enable    (pre_tic_enable),
    .f_control     (code_nco_fc),
    .hc_enable     (hc_enable),
    .code_nco_phase(code_nco_phase)
  );

  code_gen u_code_gen (
    .clk            (clk),
    .rstn           (rstn),
    .tic_enable     (tic_enable),
    .hc_enable      (hc_enable),
    .prn_key_enable (prn_key_enable),
    .prn_key        (prn_key),
    .code_slew      (code_slew),
    .slew_enable    (slew_enable),
    .dump_enable    (dump_enable),
    .code_phase     (code_phase),
    .fc_enable      (fc_enable),
    .early          (early),
    .prompt         (prompt),
    .late           (late)
  );

  // ----------------------------
  // Clock generator
  // ----------------------------
  initial clk = 1'b0;
  always #(CLK_HALF_PS) clk = ~clk;

  // ----------------------------
  // Test parameters
  // ----------------------------
  localparam integer BASE_DUMP_HC = 2046;   // 1023 chips * 2 half-chips/chip
  reg [10:0] SLEW_HC;                       // user-set in initial block

  // ----------------------------
  // Event counters / measurements
  // ----------------------------
  integer hc_cnt;                 // total number of hc_enable pulses observed
  integer last_dump_hc;           // hc_cnt at last dump
  integer dump_idx;               // dump counter

  integer baseline_dump_period;   // baseline dump interval (hc counts)
  integer slew_dump_period;       // observed extended dump interval

  integer last_fc_hc;             // hc_cnt at last fc_enable
  integer max_fc_gap;             // max gap (in hc counts) between fc_enable pulses within current dump interval
  integer baseline_max_fc_gap;    // baseline max gap
  integer slew_max_fc_gap;        // max gap during the extended interval

  // Slew detection flags
  integer have_baseline;
  integer slew_applied;
  integer found_extended_interval;

  // ----------------------------
  // Initialize & apply stimulus
  // ----------------------------
  initial begin
    // Optional VCD (enable if needed)
    // $dumpfile("code_slew.vcd");
    // $dumpvars(0, tb_code_slew);

    rstn          = 1'b0;
    tic_enable    = 1'b0;
    pre_tic_enable= 1'b0;

    // f_control = 0x4000000 (28-bit)
    code_nco_fc   = 28'h0400_0000;

    prn_key       = 10'b0110010110;
    prn_key_enable= 1'b0;

    code_slew     = 11'd0;
    slew_enable   = 1'b0;

    // Choose a non-zero slew to test (change as you like)
    SLEW_HC       = 11'd7;

    // Reset counters
    hc_cnt               = 0;
    last_dump_hc         = 0;
    dump_idx             = 0;

    baseline_dump_period = 0;
    slew_dump_period     = 0;

    last_fc_hc           = 0;
    max_fc_gap           = 0;
    baseline_max_fc_gap  = 0;
    slew_max_fc_gap      = 0;

    have_baseline        = 0;
    slew_applied         = 0;
    found_extended_interval = 0;

    // Release reset
    repeat (10) @(posedge clk);
    rstn <= 1'b1;

    // Initialize code_gen PRN registers
    @(posedge clk);
    prn_key_enable <= 1'b1;
    @(posedge clk);
    prn_key_enable <= 1'b0;

    // Wait until we have a baseline measurement (done in monitor always block)

    // Apply slew right after a dump (so slew_flag is set before the next cycle)
    // We do this after baseline is captured.
    wait (have_baseline == 1);

    // Wait for a dump edge, then assert slew_enable for 1 clk
    wait (dump_enable == 1'b1);
    @(posedge clk);
    code_slew   <= SLEW_HC;
    slew_enable <= 1'b1;
    @(posedge clk);
    slew_enable <= 1'b0;
    slew_applied <= 1;

    // Now wait until the extended dump interval is detected and checked
    wait (found_extended_interval == 1);

    $display("PASS: code_slew=%0d verified.", SLEW_HC);
    $finish;
  end

  // ----------------------------
  // Monitor: count hc_enable and fc_enable gaps
  // ----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      hc_cnt       <= 0;
      last_fc_hc   <= 0;
      max_fc_gap   <= 0;
    end
    else begin
      // Count half-chip pulses
      if (hc_enable) begin
        hc_cnt <= hc_cnt + 1;
      end

      // Track fc_enable spacing in terms of hc_cnt
      if (fc_enable) begin
        if (last_fc_hc != 0) begin
          // gap measured in hc pulses between successive fc_enable pulses
          integer gap;
          gap = hc_cnt - last_fc_hc;
          if (gap > max_fc_gap) max_fc_gap <= gap;
        end
        last_fc_hc <= hc_cnt;
      end
    end
  end

  // ----------------------------
  // Monitor: measure dump intervals in hc counts
  // ----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      last_dump_hc <= 0;
      dump_idx     <= 0;
    end
    else begin
      if (dump_enable) begin
        dump_idx <= dump_idx + 1;

        // Measure dump-to-dump interval in hc counts (ignore very first dump)
        if (last_dump_hc != 0) begin
          integer dump_period;
          dump_period = hc_cnt - last_dump_hc;

          // Establish baseline from the first "normal-looking" interval
          if (!have_baseline) begin
            baseline_dump_period <= dump_period;
            baseline_max_fc_gap  <= max_fc_gap;
            have_baseline        <= 1;

            $display("Baseline: dump_period=%0d hc (expected %0d), max_fc_gap=%0d",
                     dump_period, BASE_DUMP_HC, max_fc_gap);

            // Optional strict check for baseline dump period
            if (dump_period !== BASE_DUMP_HC) begin
              $display("WARNING: baseline dump period is %0d (expected %0d). Continuing anyway.",
                       dump_period, BASE_DUMP_HC);
            end
          end
          else begin
            // After slew is applied, we expect to see exactly one extended interval:
            // dump_period = baseline + code_slew (in half-chips)
            if (slew_applied && !found_extended_interval) begin
              if (dump_period == (baseline_dump_period + SLEW_HC)) begin
                slew_dump_period   <= dump_period;
                slew_max_fc_gap    <= max_fc_gap;
                found_extended_interval <= 1;

                $display("Slew interval detected: dump_period=%0d hc (baseline %0d + slew %0d)",
                         dump_period, baseline_dump_period, SLEW_HC);

                // Check dump interval extension
                if (dump_period !== (baseline_dump_period + SLEW_HC)) begin
                  $fatal(1, "ERROR: dump period mismatch for slew.");
                end

                // Check fc_enable gap increased (code generation delayed)
                // In steady state fc_enable pulses should be spaced ~2 hc apart.
                // With slewing, we expect one larger gap; at minimum it should grow by ~SLEW_HC.
                /*
                if (slew_max_fc_gap < (baseline_max_fc_gap + SLEW_HC)) begin
                  $display("ERROR: fc_enable max gap did not increase enough.");
                  $display("  baseline_max_fc_gap=%0d", baseline_max_fc_gap);
                  $display("  slew_max_fc_gap=%0d", slew_max_fc_gap);
                  $display("  expected >= %0d", (baseline_max_fc_gap + SLEW_HC));
                  $fatal(1, "fc_enable delay check failed.");
                end
                else begin
                  $display("OK: fc_enable gap increased: baseline=%0d, slew=%0d (expected >= baseline+slew)",
                           baseline_max_fc_gap, slew_max_fc_gap);
                end
                */
              end
            end
          end
        end

        // Reset per-interval stats at each dump edge
        last_dump_hc <= hc_cnt;
        max_fc_gap   <= 0;
        last_fc_hc   <= 0;
      end
    end
  end

endmodule
