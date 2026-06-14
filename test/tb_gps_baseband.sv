`timescale 1ps/1ps

module tb_gps_baseband;

  // ============================================================
  // Clock: 16.368 MHz
  // ============================================================
  localparam integer CLK_HALF_PS = 30548;        // ~61.096 ns period
  localparam real    CLK_HZ      = 16_368_000.0;

  // ============================================================
  // Polling: every 900 us
  // 0.0009 * 16,368,000 = 14731.2 -> use 14731 cycles
  // ============================================================
  localparam integer POLL_CYCLES      = 14731;
  localparam integer NUM_DUMPS_TO_LOG = 90;

  // ============================================================
  // User settings (EDIT to match your IF generator settings)
  // ============================================================
  localparam [9:0]   PRN_KEY_INIT  = 10'h3EC;   // example
  localparam integer CODE_DELAY    = 200;       // chips
  localparam integer CODE_SLEW_HC  = CODE_DELAY * 2;  // half-chips

  localparam real    IF_DOPPLER_HZ = -2500.0;

  // NCO nominal control words for 16.368MHz clock
  // IF center 4.092MHz -> 0x800_0000 (28-bit)
  localparam [27:0]  CARR_NCO_FC   = 28'h800_0000;

  // Code 1.023MHz -> 0x200_0000 (27-bit)
  localparam [26:0]  CODE_NCO_FC   = 27'h200_0000;

  localparam real    TWO_POW_29    = 536_870_912.0; // 2^29

  // ============================================================
  // DUT I/F
  // ============================================================
  reg  clk;
  reg  hw_rstn;

  reg  sign_in, mag_in;

  reg        chip_select, write, read;
  reg [7:0]  address;
  reg [31:0] write_data;
  wire [31:0] read_data;

  wire accum_int;

  gps_baseband dut (
    .clk         (clk),
    .hw_rstn     (hw_rstn),
    .sign_in     (sign_in),
    .mag_in      (mag_in),
    .chip_select (chip_select),
    .write       (write),
    .read        (read),
    .address     (address),
    .write_data  (write_data),
    .read_data   (read_data),
    .accum_int   (accum_int)
  );

  // ============================================================
  // Clock generator
  // ============================================================
  initial clk = 1'b0;
  always #(CLK_HALF_PS) clk = ~clk;

  // ============================================================
  // IF file I/O
  // ============================================================
  integer if_fd;
  integer out_fd;
  integer scan_ret;
  integer in_s, in_m;
  reg     read_enable;

  // ============================================================
  // Shared regs/vars (NO automatic / NO block declarations)
  // ============================================================
  integer dump_count;

  real    doppler_fc_real;
  integer doppler_fc_offs;
  integer carr_fc_word_signed;

  reg [31:0] nd;
  reg [31:0] r;

  reg signed [15:0] IE, QE, IP, QP, IL, QL;
  integer powE, powP, powL;

  // ============================================================
  // Helpers
  // ============================================================
  function integer sq16;
    input signed [15:0] v;
    integer vv;
    begin
      vv  = v;
      sq16 = vv*vv;
    end
  endfunction

  // ============================================================
  // Avalon bus helpers (Icarus-friendly)
  // ============================================================
  task av_write;
    input [7:0]  addr;
    input [31:0] data;
    begin
      @(posedge clk);
      chip_select <= 1'b1;
      write       <= 1'b1;
      read        <= 1'b0;
      address     <= addr;
      write_data  <= data;

      @(posedge clk);
      chip_select <= 1'b0;
      write       <= 1'b0;
      address     <= 8'h00;
      write_data  <= 32'h0;
    end
  endtask

  task av_read;
    input  [7:0]  addr;
    output [31:0] data;
    begin
      @(posedge clk);
      chip_select <= 1'b1;
      write       <= 1'b0;
      read        <= 1'b1;
      address     <= addr;

      @(posedge clk);
      #1; // Wait a delta so read_data is updated by nonblocking assignments before sampling.
      data = read_data; // read_data is registered in DUT

      chip_select <= 1'b0;
      read        <= 1'b0;
      address     <= 8'h00;
    end
  endtask

  // ============================================================
  // IF drive per sample
  // ============================================================
  always @(posedge clk) begin
    if (!hw_rstn) begin
      sign_in <= 1'b0;
      mag_in  <= 1'b0;
    end else if (!read_enable) begin
      sign_in <= 1'b0;
      mag_in  <= 1'b0;
    end else begin
      if (!$feof(if_fd)) begin
        scan_ret = $fscanf(if_fd, "%d %d\n", in_s, in_m);
        if (scan_ret == 2) begin
          sign_in <= in_s[0];
          mag_in  <= in_m[0];
        end else begin
          sign_in <= 1'b0;
          mag_in  <= 1'b0;
        end
      end else begin
        sign_in <= 1'b0;
        mag_in  <= 1'b0;
      end
    end
  end

  // ============================================================
  // Main
  // ============================================================
  initial begin
    // init bus
    chip_select = 0;
    write       = 0;
    read        = 0;
    address     = 0;
    write_data  = 0;

    // init IF
    sign_in     = 0;
    mag_in      = 0;
    read_enable = 0;

    // init vars
    dump_count = 0;
    nd = 0; r = 0;
    IE = 0; QE = 0; IP = 0; QP = 0; IL = 0; QL = 0;
    powE = 0; powP = 0; powL = 0;

    // open IF file
    if_fd  = $fopen("../sim/gps_if.txt", "r");
    if (if_fd == 0) begin
      $display("ERROR: cannot open ../sim/gps_if.txt");
      $finish;
    end

    out_fd = $fopen("corr_dump.txt", "w");
    if (out_fd == 0) begin
      $display("ERROR: cannot open corr_dump.txt");
      $finish;
    end
    $fwrite(out_fd, "#dump IE QE IP QP IL QL PowE PowP PowL\n");

    // reset
    hw_rstn = 0;
    repeat (50) @(posedge clk);
    hw_rstn = 1;
    repeat (10) @(posedge clk);

    // ------------------------------------------------------------
    // Program time_base (from gps_baseband address decoder)
    // 0xF1: prog_tic (tic_divide) : period = (prog_tic+1) cycles
    // 10ms -> 163680 cycles -> prog_tic=163679
    // ------------------------------------------------------------
    av_write(8'hF1, 32'd163679);
    av_write(8'hF2, 32'd1000000); // optional

    // ------------------------------------------------------------
    // Compute carrier NCO with Doppler (mapping uses 2^29)
    // ------------------------------------------------------------
    doppler_fc_real     = IF_DOPPLER_HZ * TWO_POW_29 / CLK_HZ;
    doppler_fc_offs     = $rtoi(doppler_fc_real);
    carr_fc_word_signed = $signed({1'b0, CARR_NCO_FC}) + doppler_fc_offs;

    $display("Doppler offset FC=%0d for %f Hz", doppler_fc_offs, IF_DOPPLER_HZ);
    $display("Carrier FC word  = 0x%08x", carr_fc_word_signed[27:0]);

    // ------------------------------------------------------------
    // Program CH0 (address map verified from gps_baseband.v)
    // 0x00 PRN key (write_data[9:0]) + enable pulse
    // 0x01 carrier NCO (low bits) -> ch0_carr_nco[27:0]
    // 0x02 code NCO   (low bits) -> ch0_code_nco[26:0]
    // 0x03 code slew half-chips write_data[10:0] + enable pulse
    // 0x0E epoch_load write_data[10:0] + enable pulse
    // ------------------------------------------------------------
    av_write(8'h00, {22'b0, PRN_KEY_INIT});
    av_write(8'h01, {4'b0, carr_fc_word_signed[27:0]});
    av_write(8'h02, {5'b0, CODE_NCO_FC});
    av_write(8'h03, {21'b0, CODE_SLEW_HC[10:0]});
    av_write(8'h0E, 32'd0);

    // ------------------------------------------------------------
    // Align IF file start to accumulation boundary (like tb_tracking_channel)
    // Wait first ch0_dump, then start reading IF on next clock.
    // (Allowed to use hierarchical reference to internal ch0_dump wire.)
    // ------------------------------------------------------------
    $display("Waiting first dut.ch0_dump to align IF start...");
    wait (dut.ch0_dump == 1'b1);
    @(posedge clk);
    read_enable = 1'b1;
    $display("IF reading enabled @t=%0t", $time);

    // Clear any pending new_data caused by the first (dummy) dump
    av_read(8'hE1, nd);
    // avoid double-trigger if dump stays high multiple clocks
    wait (dut.ch0_dump == 1'b0);

    // ------------------------------------------------------------
    // Polling loop:
    // every 900us read 0xE1(new_data), if bit0==1 read correlators.
    // ------------------------------------------------------------
    while (dump_count < NUM_DUMPS_TO_LOG) begin
      repeat (POLL_CYCLES) @(posedge clk);

      av_read(8'hE1, nd);   // reading clears new_data internally (with mask protection)

      if (nd[0] == 1'b1) begin
        av_read(8'h04, r); IE = $signed(r[15:0]);
        av_read(8'h05, r); QE = $signed(r[15:0]);
        av_read(8'h06, r); IP = $signed(r[15:0]);
        av_read(8'h07, r); QP = $signed(r[15:0]);
        av_read(8'h08, r); IL = $signed(r[15:0]);
        av_read(8'h09, r); QL = $signed(r[15:0]);

        powE = sq16(IE) + sq16(QE);
        powP = sq16(IP) + sq16(QP);
        powL = sq16(IL) + sq16(QL);

        $fwrite(out_fd, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
                dump_count, IE, QE, IP, QP, IL, QL, powE, powP, powL);

        $display("DUMP%0d @t=%0t: IP=%0d QP=%0d PowP=%0d (new_data=0x%08x)",
                 dump_count, $time, IP, QP, powP, nd);

        dump_count = dump_count + 1;
      end
    end

    $display("Done.");
    $fclose(if_fd);
    $fclose(out_fd);
    #1000;
    $finish;
  end

endmodule
