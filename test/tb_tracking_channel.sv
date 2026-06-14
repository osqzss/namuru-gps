`timescale 1ps/1ps

module tb_tracking_channel;

  // -----------------------------
  // Clock: 16.368 MHz
  // -----------------------------
  localparam integer CLK_HALF_PS = 30548;
  localparam real    CLK_HZ      = 16_368_000.0;

  // -----------------------------
  // User settings (EDIT)
  // -----------------------------
  localparam integer NUM_DUMPS_TO_LOG = 90;
  localparam integer MIN_PROMPT_POW   = 1000;

  // PRN key (10-bit initial state used by code_gen, not PRN number)
  localparam [9:0] PRN_KEY_INIT  = 10'h3EC; // PRN 1

  // Code slew in HALF-CHIPS
  localparam integer CODE_DELAY   = 200; // <-- set to match the IF generator (chips)
  localparam integer CODE_SLEW_HC = CODE_DELAY * 2;

  // IF Doppler in Hz
  localparam real IF_DOPPLER_HZ = -2500.0; // <-- set to match the IF generator (Hz)

  // NCO control words fixed for 16.368MHz clock
  // IF center = 4.092MHz => f_control = 0x800_0000 (28-bit)
  localparam [27:0] CARR_NCO_FC = 28'h800_0000;

  // Code = 1.023MHz => f_control = 0x200_0000 (27-bit)
  localparam [26:0] CODE_NCO_FC = 27'h200_0000;

  // --------------------------------------------------------------------------
  // Carrier NCO mapping:
  //   carrier_freq [Hz] = f_control * CLK_HZ / 2^29
  // Therefore, for a desired frequency offset df [Hz]:
  //   delta_f_control = round( df * 2^29 / CLK_HZ )
  // --------------------------------------------------------------------------
  localparam real TWO_POW_29 = 536_870_912.0; // 2^29

  // -----------------------------
  // Signals
  // -----------------------------
  reg clk;
  reg rstn;

  reg pre_tic_enable, tic_enable;

  reg if_sign, if_mag;

  reg [27:0] carr_nco_fc;
  reg [26:0] code_nco_fc;

  reg [9:0]  prn_key;
  reg        prn_key_enable;

  reg [10:0] code_slew;
  reg        slew_enable;

  reg        epoch_enable;
  reg [10:0] epoch_load;

  wire       dump;

  wire signed [15:0] i_early, q_early, i_prompt, q_prompt, i_late, q_late;
  wire [31:0] carrier_val;
  wire [20:0] code_val;
  wire [10:0] epoch, epoch_check;

  integer if_fd;
  integer out_fd;
  integer scan_ret;
  integer in_s, in_m;

  integer dump_count;
  integer ie_pow, ip_pow, il_pow;

  // -----------------------------
  // Start reading gps_if.txt from the FIRST dump boundary
  // -----------------------------
  reg seen_first_dump;
  reg start_read_pending;
  reg read_enable;

  // -----------------------------
  // NEW: Doppler -> carrier NCO offset calculation
  // -----------------------------
  real doppler_fc_real;
  integer doppler_fc_offs;        // signed offset in f_control units
  integer carr_fc_word_signed;    // signed intermediate to check range
  real eff_if_hz;

  // -----------------------------
  // DUT
  // -----------------------------
  tracking_channel dut (
    .clk           (clk),
    .rstn          (rstn),

    .if_sign       (if_sign),
    .if_mag        (if_mag),

    .pre_tic_enable(pre_tic_enable),
    .tic_enable    (tic_enable),

    .carr_nco_fc   (carr_nco_fc),
    .code_nco_fc   (code_nco_fc),

    .prn_key       (prn_key),
    .prn_key_enable(prn_key_enable),

    .code_slew     (code_slew),
    .slew_enable   (slew_enable),

    .epoch_enable  (epoch_enable),
    .epoch_load    (epoch_load),

    .dump          (dump),

    .i_early       (i_early),
    .q_early       (q_early),
    .i_prompt      (i_prompt),
    .q_prompt      (q_prompt),
    .i_late        (i_late),
    .q_late        (q_late),

    .carrier_val   (carrier_val),
    .code_val      (code_val),

    .epoch         (epoch),
    .epoch_check   (epoch_check)
  );

  // -----------------------------
  // Clock generator
  // -----------------------------
  initial clk = 1'b0;
  always #(CLK_HALF_PS) clk = ~clk;

  // -----------------------------
  // Simple TIC generator (10 ms)
  // 16.368MHz * 10ms = 163680 cycles
  // pre_tic_enable one cycle before tic_enable
  // -----------------------------
  integer tic_cnt;
  localparam integer TIC_PERIOD_CYCLES = 163680;

  always @(posedge clk) begin
    if (!rstn) begin
      tic_cnt        <= 0;
      pre_tic_enable <= 1'b0;
      tic_enable     <= 1'b0;
    end else begin
      pre_tic_enable <= 1'b0;
      tic_enable     <= 1'b0;

      if (tic_cnt == (TIC_PERIOD_CYCLES-2)) begin
        pre_tic_enable <= 1'b1;
        tic_cnt <= tic_cnt + 1;
      end else if (tic_cnt == (TIC_PERIOD_CYCLES-1)) begin
        tic_enable <= 1'b1;
        tic_cnt <= 0;
      end else begin
        tic_cnt <= tic_cnt + 1;
      end
    end
  end

  // -----------------------------
  // Detect first dump and enable IF reading starting from that dump
  // -----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      seen_first_dump    <= 1'b0;
      start_read_pending <= 1'b0;
      read_enable        <= 1'b0;
    end else begin
      if (!seen_first_dump && dump) begin
        seen_first_dump    <= 1'b1;
        start_read_pending <= 1'b1;
      end else begin
        start_read_pending <= 1'b0;
      end

      if (start_read_pending) begin
        read_enable <= 1'b1;
      end
    end
  end

  // -----------------------------
  // Read IF samples from file (one sample per clk) AFTER first dump only
  // File format: "if_sign if_mag" each line, values 0/1
  // -----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      if_sign <= 1'b0;
      if_mag  <= 1'b0;
    end else if (!read_enable) begin
      if_sign <= 1'b0;
      if_mag  <= 1'b0;
    end else begin
      if (!$feof(if_fd)) begin
        scan_ret = $fscanf(if_fd, "%d %d\n", in_s, in_m);
        if (scan_ret == 2) begin
          if_sign <= in_s[0];
          if_mag  <= in_m[0];
        end else begin
          if_sign <= 1'b0;
          if_mag  <= 1'b0;
        end
      end else begin
        if_sign <= 1'b0;
        if_mag  <= 1'b0;
      end
    end
  end

  // -----------------------------
  // Power helper (I^2 + Q^2)
  // -----------------------------
  function integer sq16;
    input signed [15:0] v;
    integer vv;
    begin
      vv = v;
      sq16 = vv*vv;
    end
  endfunction

  // -----------------------------
  // Log dump results
  // -----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      dump_count <= 0;
    end else if (dump && read_enable) begin
      ie_pow = sq16(i_early)  + sq16(q_early);
      ip_pow = sq16(i_prompt) + sq16(q_prompt);
      il_pow = sq16(i_late)   + sq16(q_late);

      $fdisplay(out_fd,
        //"%0d IE %0d %0d  IP %0d %0d  IL %0d %0d  PowE %0d PowP %0d PowL %0d",
        "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
        dump_count,
        i_early, q_early,
        i_prompt, q_prompt,
        i_late, q_late,
        ie_pow, ip_pow, il_pow
      );

      if ((ip_pow < ie_pow) || (ip_pow < il_pow) || (ip_pow < MIN_PROMPT_POW)) begin
        $display("WARNING @ t=%0t: weak/incorrect correlation? dump=%0d PowE=%0d PowP=%0d PowL=%0d",
                 $time, dump_count, ie_pow, ip_pow, il_pow);
      end

      dump_count <= dump_count + 1;

      if (dump_count == (NUM_DUMPS_TO_LOG-1)) begin
        $display("INFO: collected %0d dumps after first dump/start-of-file. Stopping.", NUM_DUMPS_TO_LOG);
        $fclose(out_fd);
        $fclose(if_fd);
        $finish;
      end
    end
  end

  // -----------------------------
  // Main
  // -----------------------------
  initial begin
    // VCD is optional. For 10ms @ 16.368MHz, VCD can become huge and slow vvp.
    // $dumpfile("tb_tracking_channel_if.vcd");
    // $dumpvars(0, tb_tracking_channel_if);

    if_fd = $fopen("../sim/gps_if.txt", "r");
    if (if_fd == 0) $fatal(1, "ERROR: cannot open gps_if.txt");

    out_fd = $fopen("corr_dump.txt", "w");
    if (out_fd == 0) $fatal(1, "ERROR: cannot open corr_dump.txt");

    rstn           = 1'b0;
    if_sign        = 1'b0;
    if_mag         = 1'b0;

    prn_key        = PRN_KEY_INIT;
    prn_key_enable = 1'b0;

    code_slew      = CODE_SLEW_HC[10:0];
    slew_enable    = 1'b0;

    epoch_enable   = 1'b0;
    epoch_load     = 11'd0;

    // ------------------------------------------------------------
    // NEW: compute carrier NCO offset word from IF_DOPPLER_HZ
    // delta_f_control = round(df * 2^30 / CLK_HZ)
    // ------------------------------------------------------------
    doppler_fc_real = IF_DOPPLER_HZ * TWO_POW_29 / CLK_HZ;

    // Round-to-nearest integer (symmetric for +/-)
    if (doppler_fc_real >= 0.0)
      doppler_fc_offs = $rtoi(doppler_fc_real + 0.5);
    else
      doppler_fc_offs = $rtoi(doppler_fc_real - 0.5);

    carr_fc_word_signed = $signed({1'b0, CARR_NCO_FC}) + doppler_fc_offs;

    // Range check for 28-bit unsigned control word
    if (carr_fc_word_signed < 0 || carr_fc_word_signed > ((1<<28)-1)) begin
      $fatal(1,
        "ERROR: carr_nco_fc out of range after doppler. base=0x%0x offs=%0d => word=%0d",
        CARR_NCO_FC, doppler_fc_offs, carr_fc_word_signed
      );
    end

    carr_nco_fc = carr_fc_word_signed[27:0];
    code_nco_fc = CODE_NCO_FC; // Ignore code Doppler

    // Effective IF frequency for confirmation
    eff_if_hz = (carr_nco_fc * CLK_HZ) / TWO_POW_29;

    dump_count = 0;

    $display("INFO: PRN_KEY_INIT=0x%0x  CODE_SLEW_HC=%0d", PRN_KEY_INIT, CODE_SLEW_HC);
    $display("INFO: IF_DOPPLER_HZ=%f Hz -> delta_f_control=%0d", IF_DOPPLER_HZ, doppler_fc_offs);
    $display("INFO: carr_nco_fc=0x%08x (base 0x%08x + offs %0d), effective IF=%f Hz",
             carr_nco_fc, CARR_NCO_FC, doppler_fc_offs, eff_if_hz);
    $display("INFO: code_nco_fc=0x%07x", code_nco_fc);
    $display("INFO: IF reading will start at the first dump boundary.");

    // Release reset
    repeat (50) @(posedge clk);
    rstn = 1'b1;

    // Latch PRN key
    @(posedge clk);
    prn_key_enable = 1'b1;
    @(posedge clk);
    prn_key_enable = 1'b0;

    // Apply code slew once (if non-zero)
    if (CODE_SLEW_HC != 0) begin
      @(posedge clk);
      slew_enable = 1'b1;
      @(posedge clk);
      slew_enable = 1'b0;
    end

    // Run; finishing is handled by dump logger
  end

endmodule
