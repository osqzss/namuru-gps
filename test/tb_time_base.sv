/*
  SystemVerilog testbench for time_base.sv

  Purpose:
    - Generate a VCD and visually verify pulse timing in GTKWave.

  Settings:
    - clk = 16.368 MHz (rounded to 1 ps resolution)
    - tic_divide   = 24'h18F9BF  (expected 0.1 s TIC period)
    - accum_divide = 24'h00398A  (expected 0.9 ms accum_enable period)
*/

`timescale 1ps/1ps

module tb_time_base_vcd;

  // 16.368 MHz clock: half period ~ 30.5475 ns -> 30548 ps (rounded)
  localparam integer CLK_HALF_PS = 30548;

  reg clk;
  reg rstn;

  reg [23:0] tic_divide;
  reg [23:0] accum_divide;

  wire        pre_tic_enable;
  wire        tic_enable;
  wire        accum_enable;
  wire [23:0] tic_count;
  wire [23:0] accum_count;

  time_base dut (
    .clk           (clk),
    .rstn          (rstn),
    .tic_divide    (tic_divide),
    .accum_divide  (accum_divide),
    .pre_tic_enable(pre_tic_enable),
    .tic_enable    (tic_enable),
    .accum_enable  (accum_enable),
    .tic_count     (tic_count),
    .accum_count   (accum_count)
  );

  // Clock generation
  initial clk = 1'b0;
  always #(CLK_HALF_PS) clk = ~clk;

  initial begin
    // NOTE: VCD dumping can generate very large files and significantly slow down vvp.
    // Disable $dumpvars or limit the dump scope/signals if simulation becomes too slow.
    $dumpfile("time_base.vcd");
    $dumpvars(0, tb_time_base_vcd);

    // Init
    rstn         = 1'b0;
    tic_divide   = 24'h18F9BF;
    accum_divide = 24'h00398A;

    // Release reset after a short time
    repeat (10) @(posedge clk);
    rstn = 1'b1;

    // Run long enough to observe:
    // - many accum_enable pulses (0.9 ms period)
    // - multiple TIC pulses (0.1 s period)
    //
    // 0.25 s is usually enough to see a few TIC events.
    #250_000_000_000; // 0.25 s in ps

    $finish;
  end

endmodule
