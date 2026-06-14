// cdc_handshake.v
// Four-phase request/acknowledge handshake for transferring a multi-bit
// word between two asynchronous clock domains.
//
// Interface matches xpm_cdc_handshake (DEST_EXT_HSK=0) so the two can be
// swapped without changing the surrounding logic.
//
// Protocol:
//   1. Caller asserts src_send (level) with stable src_in data.
//      src_in is latched internally on the first src_clk after src_send rises.
//   2. An internal request level (src_req) is registered from src_send and
//      propagates to the destination domain through a 2-FF synchronizer.
//   3. On the rising edge of the synchronised request, dest_out is updated
//      from the internal latch, dest_req pulses for one dest_clk cycle, and
//      an internal acknowledge level (dest_ack) is asserted.
//   4. dest_ack propagates back to the source domain through a 2-FF
//      synchronizer.  On its rising edge, src_rcv pulses for one src_clk
//      cycle.
//   5. The caller deasserts src_send after observing src_rcv.
//      src_req (= registered src_send) then falls, which propagates back to
//      the destination, causing dest_ack to fall.  The handshake is now
//      fully reset and a new transfer may begin.
//
// Constraints:
//   The src_latch -> dest_out path is a multi-cycle CDC data path that is
//   safe because the handshake protocol guarantees data stability before
//   dest_req fires.  Add the following XDC constraint per instance:
//
//     set_max_delay -datapath_only \
//         -from [get_cells <hier>/src_latch_reg[*]] \
//         -to   [get_cells <hier>/dest_out_reg[*]] \
//         <dest_clk_period_ns>
//
//   ASYNC_REG attributes on the synchroniser flip-flops are declared below
//   and are sufficient for single-bit req/ack lines.

`timescale 1ns/1ps

module cdc_handshake #(
    parameter integer WIDTH = 32
) (
    // Source clock domain
    input  wire             src_clk,
    input  wire [WIDTH-1:0] src_in,   // data to transfer; must be stable while src_send is high
    input  wire             src_send, // level: assert and hold until src_rcv is observed
    output reg              src_rcv,  // one src_clk pulse when the transfer is complete

    // Destination clock domain
    input  wire             dest_clk,
    output reg  [WIDTH-1:0] dest_out, // captured data; valid when dest_req fires
    output reg              dest_req  // one dest_clk pulse when dest_out is valid
);

    // -- Source domain --------------------------------------------------------
    //
    // src_req is a registered copy of src_send.  Using a register (rather than
    // the raw combinational signal) eliminates glitches on the CDC req line.
    // src_latch captures src_in on the first cycle that src_send is asserted.

    reg [WIDTH-1:0] src_latch;
    reg             src_req;

    // Two-FF synchroniser for dest_ack -> src domain
    (* ASYNC_REG = "TRUE" *) reg src_ack_ff1, src_ack_ff2;
    reg src_ack_prev;

    always @(posedge src_clk) begin
        // Synchronise dest_ack into the source domain
        src_ack_ff1  <= dest_ack;
        src_ack_ff2  <= src_ack_ff1;
        src_ack_prev <= src_ack_ff2;

        src_rcv <= 1'b0; // default: no pulse

        // Capture data on the rising edge of src_send (first cycle only)
        if (src_send && !src_req)
            src_latch <= src_in;

        // src_req tracks src_send with one cycle of delay.
        // Its falling edge after src_send is deasserted resets the handshake.
        src_req <= src_send;

        // Generate src_rcv on the rising edge of the synchronised acknowledge
        if (src_ack_ff2 && !src_ack_prev)
            src_rcv <= 1'b1;
    end

    // -- Destination domain ---------------------------------------------------

    reg dest_ack; // acknowledge level returned to the source domain

    // Two-FF synchroniser for src_req -> dest domain
    (* ASYNC_REG = "TRUE" *) reg dest_req_ff1, dest_req_ff2;
    reg dest_req_prev;

    always @(posedge dest_clk) begin
        // Synchronise src_req into the destination domain
        dest_req_ff1  <= src_req;
        dest_req_ff2  <= dest_req_ff1;
        dest_req_prev <= dest_req_ff2;

        dest_req <= 1'b0; // default: no pulse

        if (dest_req_ff2 && !dest_req_prev) begin
            // Rising edge: data is stable - capture it, pulse dest_req, assert ack
            dest_out <= src_latch;
            dest_req <= 1'b1;
            dest_ack <= 1'b1;
        end else if (!dest_req_ff2 && dest_req_prev) begin
            // Falling edge: src has deasserted its request - release acknowledge
            dest_ack <= 1'b0;
        end
    end

    // -- Initialisation (simulation and Xilinx FPGA power-on) ----------------
    initial begin
        src_latch     = {WIDTH{1'b0}};
        src_req       = 1'b0;
        src_rcv       = 1'b0;
        src_ack_ff1   = 1'b0;
        src_ack_ff2   = 1'b0;
        src_ack_prev  = 1'b0;
        dest_ack      = 1'b0;
        dest_req_ff1  = 1'b0;
        dest_req_ff2  = 1'b0;
        dest_req_prev = 1'b0;
        dest_req      = 1'b0;
        dest_out      = {WIDTH{1'b0}};
    end

endmodule
