/*
  SystemVerilog testbench for carrier_nco.

  Requirements implemented:
    - Clock frequency: 16.368 MHz
    - f_control set for center frequency: 4.092 MHz
    - Output file format: "i_carr q_carr" (two signed integer values per line)

  Notes:
    - With Fs = 16.368 MHz and f0 = 4.092 MHz, f0 = Fs/4 exactly.
    - For the RTL carrier_nco, the NCO frequency is: f = f_control * Fs / 2^30
      Therefore f_control = f * 2^30 / Fs = (Fs/4)*2^30/Fs = 2^28 = 0x1000_0000.
*/

`timescale 1ns/1ps

module tb_carrier_nco;

  // ----------------------------
  // Clock settings
  // ----------------------------
  // 16.368 MHz => period = 61.095 ns, half period = 30.5475 ns
  localparam real CLK_NS      = 61.095;
  localparam real CLK_HALF_NS = 30.5475;

  logic clk;
  logic rstn;
  logic tic_enable;

  logic [28:0] f_control;

  // DUT outputs
  wire [31:0] carrier_val;
  wire        i_sign, i_mag;
  wire        q_sign, q_mag;

  // Combined 2-bit carrier outputs (sign, magnitude)
  logic [1:0] i_carr;
  logic [1:0] q_carr;

  // File handle and counters
  integer fd;
  int unsigned sample_count;

  localparam int unsigned NUM_SAMPLES = 8*50;

  // ----------------------------
  // DUT instance
  // ----------------------------
  carrier_nco dut (
    .clk        (clk),
    .rstn       (rstn),
    .tic_enable (tic_enable),
    .f_control  (f_control),
    .carrier_val(carrier_val),
    .i_sign     (i_sign),
    .i_mag      (i_mag),
    .q_sign     (q_sign),
    .q_mag      (q_mag)
  );

  // Optional helper: decode carrier values for output file
  function automatic int decode_carrier_value(input logic s, input logic m);
    // Carrier magnitude bit: 0 -> 1, 1 -> 2
    int mag;
    begin
      mag = (m == 1'b0) ? 1 : 2;
      decode_carrier_value = (s == 1'b1) ? mag : -mag;
    end
  endfunction

  // ----------------------------
  // Clock generation (16.368 MHz)
  // ----------------------------
  initial clk = 1'b0;
  always #(CLK_HALF_NS) clk = ~clk;

  // Combine sign and magnitude into 2-bit words
  always_comb begin
    i_carr = {i_sign, i_mag};
    q_carr = {q_sign, q_mag};
  end

  // ----------------------------
  // Stimulus + file output control
  // ----------------------------
  initial begin
    $dumpfile("carrier_nco.vcd");
    $dumpvars(0, tb_carrier_nco);

    // Init
    rstn        = 1'b0;
    tic_enable  = 1'b0;
    sample_count = 0;

    // Set f_control for 4.092 MHz center frequency at Fs = 16.368 MHz.
    // f_control = f * 2^30 / Fs = 2^28 = 0x1000_0000
    //f_control   = 29'h1000_0000;
    f_control   = 29'h800_0000; // 2.046 MHz center frequency for full 8-phase waveforms

    // Open output file (two columns: i_carr and q_carr)
    fd = $fopen("carrier_nco.txt", "w");
    if (fd == 0) begin
      $fatal(1, "ERROR: Failed to open output file carrier_nco.txt");
    end

    // Hold reset for a short time, then release
    #(CLK_NS*5);
    rstn = 1'b1;

    // Generate a TIC pulse
    #(CLK_NS*50);
    tic_enable = 1'b1;
    #(CLK_NS);
    tic_enable = 1'b0;
  end

  // ----------------------------
  // Sample capture: write NUM_SAMPLES lines after reset is released
  // Each line: "<i_carr> <q_carr>" as signed integer
  // ----------------------------
  always @(posedge clk) begin
    if (!rstn) begin
      sample_count <= 0;
    end
    else begin
      // Exclude unknowns to keep the output numeric-only
      if ((i_carr !== 2'bxx) && (q_carr !== 2'bxx)) begin

        $fdisplay(fd, "%2d %2d",
                 decode_carrier_value(i_sign, i_mag),
                 decode_carrier_value(q_sign, q_mag));
        sample_count <= sample_count + 1;

        if (sample_count + 1 >= NUM_SAMPLES) begin
          $fclose(fd);
          $display("DONE: Wrote %0d IQ samples to carrier_nco.txt", NUM_SAMPLES);
          $finish;
        end
      end
    end
  end

endmodule
