// cdc_sync_2ff.v
// Two flip-flop synchronizer for a level signal crossing between two
// asynchronous clock domains.
//
// The ASYNC_REG attribute instructs Vivado's timing engine to treat these
// flip-flops as CDC synchronization registers, preventing optimisation
// across the boundary and enabling automatic CDC analysis via report_cdc.
//
// Vivado XDC constraint (add per instance when WIDTH > 1):
//   set_max_delay -datapath_only \
//       -from [get_cells <src_ff>] \
//       -to   [get_cells <hier>/sync1_reg[*]] \
//       <dest_clk_period_ns>

`timescale 1ns/1ps

module cdc_sync_2ff #(
    parameter integer WIDTH = 1
) (
    input  wire             dest_clk,
    input  wire [WIDTH-1:0] d,
    (* ASYNC_REG = "TRUE" *) output reg  [WIDTH-1:0] q
);

    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync1;

    // Both synchronizer flip-flops carry ASYNC_REG so the placer keeps the
    // pair adjacent, maximising the metastability settling time (MTBF).
    always @(posedge dest_clk) begin
        sync1 <= d;
        q     <= sync1;
    end

    initial begin
        sync1 = {WIDTH{1'b0}};
        q     = {WIDTH{1'b0}};
    end

endmodule
