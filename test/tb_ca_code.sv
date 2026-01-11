`timescale 1ns/1ps

module tb_ca_code;

  // ----------------------------
  // Clock / reset
  // ----------------------------
  logic clk;
  logic rstn;

  // ----------------------------
  // Inputs to code_gen
  // ----------------------------
  logic        tic_enable;
  logic        prn_key_enable;
  logic [9:0]  prn_key;
  logic        slew_enable;
  logic [10:0] code_slew;

  // ----------------------------
  // code_nco control
  // ----------------------------
  logic [27:0] f_control;
  wire         hc_enable;
  wire [9:0]   code_val;       // not used, kept for completeness

  // ----------------------------
  // Outputs from code_gen
  // ----------------------------
  wire         dump_enable;
  wire [10:0]  code_phase;
  wire         early, prompt, late;
  wire         fc_enable;

  // ----------------------------
  // DUT instances
  // ----------------------------
  code_gen dut (
    .clk            (clk),
    .rstn           (rstn),
    .tic_enable     (tic_enable),
    .hc_enable      (hc_enable),
    .prn_key_enable (prn_key_enable),
    .prn_key        (prn_key),
    .slew_enable    (slew_enable),
    .code_slew      (code_slew),
    .dump_enable    (dump_enable),
    .code_phase     (code_phase),
    .fc_enable      (fc_enable),
    .early          (early),
    .prompt         (prompt),
    .late           (late)
  );

  code_nco codenco (
    .clk            (clk),
    .rstn           (rstn),
    .tic_enable     (tic_enable),
    .f_control      (f_control),
    .hc_enable      (hc_enable),
    .code_nco_phase (code_val)
  );

  // ----------------------------
  // Clock generator
  // ----------------------------
  localparam real CLK_FREQ_HZ = 16.368e6;
  localparam real CLK_HALF_NS = 1e9/(2.0*CLK_FREQ_HZ); // ns
  localparam real CLK_NS = 2.0*CLK_HALF_NS;

  initial clk = 1'b0;
  always  #(CLK_HALF_NS) clk = ~clk;

  // ----------------------------
  // File I/O
  // ----------------------------
  integer fd;
  int unsigned chip_count;

  // ----------------------------
  // Test sequence
  // ----------------------------
  initial begin
    // Optional VCD
    $dumpfile("ca_code.vcd");
    $dumpvars(0, tb_ca_code);

    // Initialize signals
    rstn           = 1'b0;
    tic_enable     = 1'b0;

    prn_key_enable = 1'b0;
    prn_key        = 10'd0;

    slew_enable    = 1'b0;
    code_slew      = 11'd0;

    // Set NCO frequency control word.
    // For 16.368 MHz system clock, 2.046 MHz half-chip enable (nominal).
    f_control      = 28'h4000000;

    // Release reset
    #(CLK_NS*5);
    rstn = 1'b1;

    // Program PRN key and reset code generator logic
    // NOTE: code_gen uses prn_key as the initial value of the G2 register.
    prn_key = 10'h3EC; // PRN 1
    //prn_key = 10'b01_1001_0110; // PRN 7
    prn_key_enable = 1'b1;
    #(CLK_NS);
    prn_key_enable = 1'b0;

    // Ensure no slewing for a clean 1023-chip period
    slew_enable = 1'b0;
    code_slew   = 11'd0;

    // Open output file
    fd = $fopen("ca_code.txt", "w");
    if (fd == 0) begin
      $fatal(1, "ERROR: Failed to open output file.");
    end

    // Wait for the very first dump_enable pulse.
    // We treat this as the marker for the start of a C/A code period.
    @(posedge clk);
    wait (dump_enable === 1'b1);

    // Starting from the chip belonging to this dump event:
    // capture the next 1023 chip-boundary samples of 'prompt'.
    chip_count = 0;

    while (chip_count < 1023) begin
      @(posedge clk);
      if (fc_enable) begin
        // Write prompt as 0/1, one per line.
        $fwrite(fd, "%0d\n", prompt);

        chip_count++;
      end
    end

    $fclose(fd);
    $display("DONE: Wrote %0d prompt chips to ca_code.txt", chip_count);

    #(CLK_NS*50);
    $finish;
  end

endmodule
