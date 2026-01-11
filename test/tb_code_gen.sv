/*
Engineer: Artyom Gavrilov, gnss-sdr.com, 2012
Just a simple test of code generator.
SystemVerilog rewrite: Takuji Ebinuma, 2026
*/

`timescale 1ns/1ps

module tb_code_gen;

  // clock / reset / control
  logic        clk;
  logic        rstn;
  logic        tic_enable;

  logic        prn_key_enable;
  logic        slew_enable;
  logic [9:0]  prn_key;
  logic [10:0] code_slew;

  // from code_nco
  logic [27:0] f_control;
  wire         hc_enable;
  wire [9:0]   code_val;

  // DUT outputs
  wire         dump_enable;
  wire [10:0]  code_phase;
  wire         early, prompt, late;
  wire         fc_enable; // not used, kept for completeness

  // DUT
  code_gen dut (
    .clk           (clk),
    .rstn          (rstn),
    .tic_enable    (tic_enable),
    .hc_enable     (hc_enable),
    .prn_key_enable(prn_key_enable),
    .prn_key       (prn_key),
    .code_slew     (code_slew),
    .slew_enable   (slew_enable),
    .dump_enable   (dump_enable),
    .code_phase    (code_phase),
    .fc_enable     (fc_enable),
    .early         (early),
    .prompt        (prompt),
    .late          (late)
  );

  // code_nco to generate hc_enable for code_gen
  code_nco codenco (
    .clk          (clk),
    .rstn         (rstn),
    .tic_enable   (tic_enable),
    .f_control    (f_control),
    .hc_enable    (hc_enable),
    .code_nco_phase(code_val)
  );

  // clock generation
  localparam real CLK_FREQ_HZ = 16.368e6;
  localparam real CLK_HALF_NS = 1e9/(2.0*CLK_FREQ_HZ); // ns
  localparam real CLK_NS = 2.0*CLK_HALF_NS;

  initial clk = 1'b0;
  always  #(CLK_HALF_NS) clk = ~clk;

  // stimulus
  initial begin
    // VCD
    $dumpfile("code_gen.vcd");
    $dumpvars(0, tb_code_gen);   // or $dumpvars(-1, dut);

    // init
    rstn           = 1'b0;
    tic_enable     = 1'b0;

    prn_key_enable = 1'b0;
    slew_enable    = 1'b0;
    prn_key        = 10'd0;
    code_slew      = 11'd0;

    // set code_nco frequency = 2.046 MHz for 16.368 MHz system clock
    // df = 16.368 MHz / 2^29 = 0.0305 Hz
    // 2.046 MHz / df = 67,108,864 = 0x4000000
    f_control      = 28'h4000000;

    // release reset and program PRN
    #(CLK_NS*5);
    rstn           = 1'b1;

    prn_key_enable = 1'b1;
    prn_key = 10'b11_1110_1100; // PRN 1
    //prn_key = 10'b01_1001_0110; // PRN 7

    // latch prn_key then deassert
    #(CLK_NS);
    prn_key_enable = 1'b0;

    // code slew test
    #(CLK_NS);
    code_slew   = 11'd1023; // slew half code
    slew_enable = 1'b1;

    #(CLK_NS);
    slew_enable = 1'b0;

    // generate TIC pulse later
    #(CLK_NS*50000);
    tic_enable = 1'b1;

    #(CLK_NS);
    tic_enable = 1'b0;

    // assert reset again then finish
    #(CLK_NS*50);
    rstn = 1'b0;

    $finish;
  end

endmodule
