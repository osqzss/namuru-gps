`timescale 1ps/1ps

module tb_gps_baseband_axi4lite;

  // ============================================================
  // Clocks:
  //   aclk        = 50 MHz  (AXI / PS)
  //   baseband_clk = 16.368 MHz  (GPS correlator / MAX2769C)
  // ============================================================
  localparam integer AXI_CLK_HALF_PS = 10000;   // 50 MHz
  localparam integer BB_CLK_HALF_PS  = 30548;   // 16.368 MHz
  localparam real    BB_CLK_HZ       = 16_368_000.0;

  // ============================================================
  // Polling: every 900 us at 50 MHz
  // 0.0009 * 50,000,000 = 45,000 cycles
  // ============================================================
  localparam integer POLL_CYCLES      = 45000;
  localparam integer NUM_DUMPS_TO_LOG = 90;

  // ============================================================
  // User settings (EDIT to match your IF generator settings)
  // ============================================================
  localparam [9:0]   PRN_KEY_INIT  = 10'h3EC;   // example
  localparam integer CODE_DELAY    = 200;       // chips
  localparam integer CODE_SLEW_HC  = CODE_DELAY * 2; // half-chips

  localparam real    IF_DOPPLER_HZ = -2500.0;

  // NCO nominal control words for 16.368MHz clock
  localparam [27:0]  CARR_NCO_FC   = 28'h800_0000; // 4.092 MHz
  localparam [26:0]  CODE_NCO_FC   = 27'h200_0000; // 1.023 MHz
  localparam real    TWO_POW_29    = 536_870_912.0; // 2^29
  // NCO words are based on BB_CLK_HZ, no change needed

  // ============================================================
  // AXI address helper: internal 8-bit word index -> AXI byte address
  // ============================================================
  function [31:0] AXI_ADDR;
    input [7:0] word_index;
    begin
      AXI_ADDR = {22'b0, word_index, 2'b00}; // word_index << 2
    end
  endfunction

  // ============================================================
  // Clock/Reset
  // ============================================================
  reg s_axi_aclk;
  reg s_axi_aresetn;
  reg baseband_clk;

  initial s_axi_aclk   = 1'b0;
  initial baseband_clk = 1'b0;
  always #(AXI_CLK_HALF_PS) s_axi_aclk   = ~s_axi_aclk;
  always #(BB_CLK_HALF_PS)  baseband_clk = ~baseband_clk;

  // ============================================================
  // IF inputs
  // ============================================================
  reg sign_in, mag_in;

  // ============================================================
  // AXI4-Lite signals (32-bit)
  // ============================================================
  reg  [31:0] s_axi_awaddr;
  reg         s_axi_awvalid;
  wire        s_axi_awready;

  reg  [31:0] s_axi_wdata;
  reg  [3:0]  s_axi_wstrb;
  reg         s_axi_wvalid;
  wire        s_axi_wready;

  wire [1:0]  s_axi_bresp;
  wire        s_axi_bvalid;
  reg         s_axi_bready;

  reg  [31:0] s_axi_araddr;
  reg         s_axi_arvalid;
  wire        s_axi_arready;

  wire [31:0] s_axi_rdata;
  wire [1:0]  s_axi_rresp;
  wire        s_axi_rvalid;
  reg         s_axi_rready;

  // IRQ (optional)
  wire irq;

  // ============================================================
  // DUT: AXI4-Lite wrapper
  // NOTE: Replace module name to match your wrapper file.
  // ============================================================
  gps_baseband_axi4lite_wrapper dut (
    .aclk          (s_axi_aclk),
    .aresetn       (s_axi_aresetn),
    .baseband_clk  (baseband_clk),

    .sign_in       (sign_in),
    .mag_in        (mag_in),

    .accum_int     (irq),

    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),

    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),

    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),

    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),

    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready)
  );

  // ============================================================
  // IF file I/O
  // ============================================================
  integer if_fd;
  integer out_fd;
  integer scan_ret;
  integer in_s, in_m;
  reg     read_enable;

  // ============================================================
  // Shared vars (Icarus-friendly)
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
      vv = v;
      sq16 = vv * vv;
    end
  endfunction

  // ============================================================
  // AXI4-Lite master tasks (simple, single outstanding)
  // ============================================================
  reg axi_done;
  reg [31:0] tmo_cnt;

  task axi_write32;
    input [31:0] addr;
    input [31:0] data;
    begin
      // Drive AW/W together (wrapper accepts AW+W together)
      @(posedge s_axi_aclk);
      s_axi_awaddr  <= addr;
      s_axi_awvalid <= 1'b1;
      s_axi_wdata   <= data;
      s_axi_wstrb   <= 4'hF;
      s_axi_wvalid  <= 1'b1;
      s_axi_bready  <= 1'b1;

      // Wait for AWREADY & WREADY (sample after NBA updates)
      axi_done = 1'b0;
      tmo_cnt  = 32'd0;
      while (!axi_done) begin
        @(posedge s_axi_aclk);
        #1;
        tmo_cnt = tmo_cnt + 1;

        if (s_axi_awready && s_axi_wready) begin
          // Deassert valids after handshake
          s_axi_awvalid <= 1'b0;
          s_axi_wvalid  <= 1'b0;
          axi_done      <= 1'b1;
        end

        if (tmo_cnt == 32'd20000) begin
          $display("ERROR: AW/W ready timeout @t=%0t addr=0x%08x", $time, addr);
          $finish;
        end
      end

      // Wait for BVALID (sample after NBA updates)
      axi_done = 1'b0;
      tmo_cnt  = 32'd0;
      while (!axi_done) begin
        @(posedge s_axi_aclk);
        #1;
        tmo_cnt = tmo_cnt + 1;

        if (s_axi_bvalid) begin
          axi_done <= 1'b1;
        end

        if (tmo_cnt == 32'd20000) begin
          $display("ERROR: BVALID timeout @t=%0t addr=0x%08x", $time, addr);
          $finish;
        end
      end

      // Complete response handshake
      @(posedge s_axi_aclk);
      s_axi_bready <= 1'b0;
    end
  endtask

  task axi_read32;
    input  [31:0] addr;
    output [31:0] data;
    begin
      data = 32'h0;

      // Issue AR
      @(posedge s_axi_aclk);
      s_axi_araddr  <= addr;
      s_axi_arvalid <= 1'b1;
      s_axi_rready  <= 1'b1;

      // Wait for ARREADY (sample after NBA updates)
      axi_done = 1'b0;
      tmo_cnt  = 32'd0;
      while (!axi_done) begin
        @(posedge s_axi_aclk);
        #1;
        tmo_cnt = tmo_cnt + 1;

        if (s_axi_arready) begin
          s_axi_arvalid <= 1'b0;
          axi_done      <= 1'b1;
        end

        if (tmo_cnt == 32'd20000) begin
          $display("ERROR: ARREADY timeout @t=%0t addr=0x%08x", $time, addr);
          $finish;
        end
      end

      // Wait for RVALID and sample RDATA after NBA updates
      axi_done = 1'b0;
      tmo_cnt  = 32'd0;
      while (!axi_done) begin
        @(posedge s_axi_aclk);
        #1;
        tmo_cnt = tmo_cnt + 1;

        if (s_axi_rvalid) begin
          data     = s_axi_rdata;
          axi_done = 1'b1;
        end

        if (tmo_cnt == 32'd20000) begin
          $display("ERROR: RVALID timeout @t=%0t addr=0x%08x", $time, addr);
          $finish;
        end
      end

      // Complete response handshake
      @(posedge s_axi_aclk);
      s_axi_rready <= 1'b0;
    end
  endtask

  // ============================================================
  // IF drive per sample
  // ============================================================
  // IF samples must be clocked at the baseband rate (16.368 MHz)
  always @(posedge baseband_clk) begin
    if (!s_axi_aresetn) begin
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
    // AXI init
    s_axi_awaddr  = 32'h0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata   = 32'h0;
    s_axi_wstrb   = 4'h0;
    s_axi_wvalid  = 1'b0;
    s_axi_bready  = 1'b0;

    s_axi_araddr  = 32'h0;
    s_axi_arvalid = 1'b0;
    s_axi_rready  = 1'b0;

    // IF init
    sign_in     = 1'b0;
    mag_in      = 1'b0;
    read_enable = 1'b0;

    dump_count = 0;
    nd = 0; r = 0;
    IE = 0; QE = 0; IP = 0; QP = 0; IL = 0; QL = 0;
    powE = 0; powP = 0; powL = 0;

    // Open files
    if_fd = $fopen("../sim/gps_if.txt", "r");
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

    // Reset
    s_axi_aresetn = 1'b0;
    repeat (50) @(posedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (10) @(posedge s_axi_aclk);

    $display("TB aresetn=%b", s_axi_aresetn);
    $display("DUT aresetn=%b", dut.aresetn);
    $display("DUT module=%m");

    // ------------------------------------------------------------
    // Program time_base (same as Avalon TB but via AXI)
    // 0xF1: prog_tic (tic_divide), 10ms -> 163679
    // 0xF2: prog_accum_int (optional)
    // ------------------------------------------------------------
    axi_write32(AXI_ADDR(8'hF1), 32'd163679);
    axi_write32(AXI_ADDR(8'hF2), 32'd1000000);

    // ------------------------------------------------------------
    // Compute carrier NCO with Doppler (mapping uses 2^29)
    // ------------------------------------------------------------
    doppler_fc_real     = IF_DOPPLER_HZ * TWO_POW_29 / BB_CLK_HZ;
    doppler_fc_offs     = $rtoi(doppler_fc_real);
    carr_fc_word_signed = $signed({1'b0, CARR_NCO_FC}) + doppler_fc_offs;

    $display("Doppler offset FC=%0d for %f Hz", doppler_fc_offs, IF_DOPPLER_HZ);
    $display("Carrier FC word  = 0x%08x", carr_fc_word_signed[27:0]);

    // ------------------------------------------------------------
    // Program CH0 registers (same internal map as Avalon TB)
    // 0x00 PRN key
    // 0x01 carrier NCO
    // 0x02 code NCO
    // 0x03 code slew (half-chips)
    // 0x0E epoch_load (optional)
    // ------------------------------------------------------------
    axi_write32(AXI_ADDR(8'h00), {22'b0, PRN_KEY_INIT});
    axi_write32(AXI_ADDR(8'h01), {4'b0, carr_fc_word_signed[27:0]});
    axi_write32(AXI_ADDR(8'h02), {5'b0, CODE_NCO_FC});
    axi_write32(AXI_ADDR(8'h03), {21'b0, CODE_SLEW_HC[10:0]});
    axi_write32(AXI_ADDR(8'h0E), 32'd0);

    // ------------------------------------------------------------
    // Align IF file start to accumulation boundary:
    // Only for this initial sync, we may directly watch ch0_dump.
    // The hierarchical path assumes:
    //   dut.u_gps_baseband.ch0_dump
    // If your instance name differs, adjust this path.
    // ------------------------------------------------------------
    $display("Waiting first ch0_dump to align IF start...");
    wait (dut.u_baseband.ch0_dump == 1'b1);
    @(posedge s_axi_aclk);
    read_enable = 1'b1;
    $display("IF reading enabled @t=%0t", $time);

    // Clear any pending new_data caused by the first (dummy) dump
    axi_read32(AXI_ADDR(8'hE1), nd);

    // Avoid double-trigger if dump stays high for multiple clocks
    wait (dut.u_baseband.ch0_dump == 1'b0);

    // ------------------------------------------------------------
    // Polling loop:
    // every 900us read new_data (0xE1). If bit0==1 read correlators.
    // ------------------------------------------------------------
    while (dump_count < NUM_DUMPS_TO_LOG) begin
      repeat (POLL_CYCLES) @(posedge s_axi_aclk);

      axi_read32(AXI_ADDR(8'hE1), nd);

      if (nd[0] == 1'b1) begin
        axi_read32(AXI_ADDR(8'h04), r); IE = $signed(r[15:0]);
        axi_read32(AXI_ADDR(8'h05), r); QE = $signed(r[15:0]);
        axi_read32(AXI_ADDR(8'h06), r); IP = $signed(r[15:0]);
        axi_read32(AXI_ADDR(8'h07), r); QP = $signed(r[15:0]);
        axi_read32(AXI_ADDR(8'h08), r); IL = $signed(r[15:0]);
        axi_read32(AXI_ADDR(8'h09), r); QL = $signed(r[15:0]);

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
