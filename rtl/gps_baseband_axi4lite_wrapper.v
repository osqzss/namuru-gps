// gps_baseband_axi4lite_wrapper.v
// AXI4-Lite slave wrapper for gps_baseband with dual-clock CDC.
//
// Clock domains
//   aclk         : PS AXI clock (FCLK_CLK0, 50 MHz)
//   baseband_clk : MAX2769C CLKOUT routed through a BUFG (16.368 MHz)
//
// CDC crossings (all implemented with portable custom Verilog primitives;
// no Xilinx XPM macros are used so the design is simulatable with iverilog)
//
//   #1  Write bus (addr + data)  aclk -> baseband_clk  cdc_handshake 40-bit
//   #2  Read request (addr)      aclk -> baseband_clk  cdc_handshake  8-bit
//   #3  Read data                baseband_clk -> aclk  cdc_handshake 32-bit
//   #4  accum_int level          baseband_clk -> aclk  cdc_sync_2ff   1-bit
//
// Vivado XDC constraints required at the project level
//   create_clock -period 61.108 -name baseband_clk [get_ports CLKOUT]
//   set_clock_groups -asynchronous \
//       -group [get_clocks clk_fpga_0] \
//       -group [get_clocks baseband_clk]
//   set_max_delay -datapath_only \
//       -from [get_cells */u_cdc_wr/src_latch_reg[*]]    \
//       -to   [get_cells */u_cdc_wr/dest_out_reg[*]]     61.108
//   set_max_delay -datapath_only \
//       -from [get_cells */u_cdc_rd_req/src_latch_reg[*]] \
//       -to   [get_cells */u_cdc_rd_req/dest_out_reg[*]] 61.108
//   set_max_delay -datapath_only \
//       -from [get_cells */u_cdc_rd_data/src_latch_reg[*]] \
//       -to   [get_cells */u_cdc_rd_data/dest_out_reg[*]] 20.0
//
// Note: simultaneous AXI read and write is not supported.  The PS driver
// must serialise all register accesses, which is normal for polled use.

`timescale 1ns/1ps

module gps_baseband_axi4lite_wrapper #(
    parameter integer AXI_ADDR_WIDTH = 32,
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer ADDR_LSB       = 2
) (
    // Clocks and reset
    // X_INTERFACE_INFO attributes enable Vivado IP Integrator to auto-detect
    // the AXI4-Lite slave interface and clock/reset associations.
    // These attributes are Verilog comments to non-Vivado tools (iverilog ignores them).
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 50000000" *)
    input  wire                        aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                        aresetn,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 baseband_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 16368000" *)
    input  wire                        baseband_clk,  // 16.368 MHz via BUFG

    // RF front-end inputs (from MAX2769C via PMOD JD)
    input  wire                        sign_in,
    input  wire                        mag_in,

    // Interrupt to PS (level, aclk domain)
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 accum_int INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire                        accum_int,

    // AXI4-Lite slave
    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 32, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 1" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg                         s_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg                         s_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]                  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg                         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                        s_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg                         s_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg  [1:0]                  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg                         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                        s_axi_rready
);

    // -- Reset synchroniser: aresetn -> bb_rstn (baseband domain) ------------
    // Asynchronous assert, synchronous deassert.  This is the standard safe
    // reset-synchronisation idiom for FPGA designs.
    (* ASYNC_REG = "TRUE" *) reg bb_rstn_s1, bb_rstn;
    always @(posedge baseband_clk or negedge aresetn) begin
        if (!aresetn) {bb_rstn, bb_rstn_s1} <= 2'b00;
        else          {bb_rstn, bb_rstn_s1} <= {bb_rstn_s1, 1'b1};
    end

    // -- CDC #1: Write bus  aclk -> baseband_clk -----------------------------
    // src_in[39:32] = address[7:0],  src_in[31:0] = write_data[31:0]
    reg        cdc_wr_src_send;
    wire       cdc_wr_src_rcv;
    reg [39:0] cdc_wr_src_in;
    wire [39:0] cdc_wr_dest_out;
    wire        cdc_wr_dest_req;

    cdc_handshake #(.WIDTH(40)) u_cdc_wr (
        .src_clk  (aclk),
        .src_in   (cdc_wr_src_in),
        .src_send (cdc_wr_src_send),
        .src_rcv  (cdc_wr_src_rcv),
        .dest_clk (baseband_clk),
        .dest_out (cdc_wr_dest_out),
        .dest_req (cdc_wr_dest_req)
    );

    // -- CDC #2: Read request  aclk -> baseband_clk --------------------------
    // src_in[7:0] = address[7:0]
    reg        cdc_rd_req_src_send;
    wire       cdc_rd_req_src_rcv;
    reg  [7:0] cdc_rd_req_src_in;
    wire [7:0] cdc_rd_req_dest_out;
    wire       cdc_rd_req_dest_req;

    cdc_handshake #(.WIDTH(8)) u_cdc_rd_req (
        .src_clk  (aclk),
        .src_in   (cdc_rd_req_src_in),
        .src_send (cdc_rd_req_src_send),
        .src_rcv  (cdc_rd_req_src_rcv),
        .dest_clk (baseband_clk),
        .dest_out (cdc_rd_req_dest_out),
        .dest_req (cdc_rd_req_dest_req)
    );

    // -- CDC #3: Read data  baseband_clk -> aclk -----------------------------
    // src_in[31:0] = read_data[31:0]
    reg        cdc_rd_data_src_send;
    wire       cdc_rd_data_src_rcv;
    reg [31:0] cdc_rd_data_src_in;
    wire [31:0] cdc_rd_data_dest_out;
    wire        cdc_rd_data_dest_req;

    cdc_handshake #(.WIDTH(32)) u_cdc_rd_data (
        .src_clk  (baseband_clk),
        .src_in   (cdc_rd_data_src_in),
        .src_send (cdc_rd_data_src_send),
        .src_rcv  (cdc_rd_data_src_rcv),
        .dest_clk (aclk),
        .dest_out (cdc_rd_data_dest_out),
        .dest_req (cdc_rd_data_dest_req)
    );

    // -- CDC #4: accum_int level  baseband_clk -> aclk -----------------------
    wire bb_accum_int;

    cdc_sync_2ff #(.WIDTH(1)) u_cdc_accum_int (
        .dest_clk (aclk),
        .d        (bb_accum_int),
        .q        (accum_int)
    );

    // -- Baseband-domain bus signals ------------------------------------------
    reg        bb_chip_select;
    reg        bb_wr_stb;
    reg        bb_rd_stb;
    reg  [7:0] bb_address;
    reg [31:0] bb_wdata;
    wire [31:0] bb_rdata;

    gps_baseband u_baseband (
        .clk         (baseband_clk),
        .hw_rstn     (bb_rstn),
        .sign_in     (sign_in),
        .mag_in      (mag_in),
        .chip_select (bb_chip_select),
        .write       (bb_wr_stb),
        .read        (bb_rd_stb),
        .address     (bb_address),
        .write_data  (bb_wdata),
        .read_data   (bb_rdata),
        .accum_int   (bb_accum_int)
    );

    // -- Baseband-domain state machine ----------------------------------------
    //
    // Writes are handled directly by cdc_wr_dest_req (one dest_clk pulse):
    //   pulse at T  -> bb_chip_select/bb_wr_stb driven high (registered)
    //   posedge T+1 -> gps_baseband sees chip_select=1, write=1 and commits
    //
    // Reads need an extra cycle because gps_baseband updates read_data with
    // a non-blocking assignment on the same edge that chip_select is seen:
    //   BB_IDLE      : cdc_rd_req fires -> drive chip_select/rd_stb high,
    //                  go to BB_RD_ASSERT
    //   BB_RD_ASSERT : gps_baseband processes the read at this posedge;
    //                  read_data becomes valid after this edge -> BB_RD_CAP
    //   BB_RD_CAP    : bb_rdata is now the freshly written value; latch it,
    //                  initiate the return handshake -> BB_RD_WAIT_RCV
    //   BB_RD_WAIT_RCV: hold cdc_rd_data_src_send until src_rcv -> BB_IDLE

    localparam [2:0] BB_IDLE        = 3'd0;
    localparam [2:0] BB_RD_ASSERT   = 3'd1;
    localparam [2:0] BB_RD_CAP      = 3'd2;
    localparam [2:0] BB_RD_WAIT_RCV = 3'd3;

    reg [2:0] bb_state;

    always @(posedge baseband_clk) begin
        if (!bb_rstn) begin
            bb_state             <= BB_IDLE;
            bb_chip_select       <= 1'b0;
            bb_wr_stb            <= 1'b0;
            bb_rd_stb            <= 1'b0;
            bb_address           <= 8'h00;
            bb_wdata             <= 32'h0;
            cdc_rd_data_src_send <= 1'b0;
            cdc_rd_data_src_in   <= 32'h0;
        end else begin
            // Default: deassert all bus strobes every cycle
            bb_chip_select       <= 1'b0;
            bb_wr_stb            <= 1'b0;
            bb_rd_stb            <= 1'b0;
            cdc_rd_data_src_send <= 1'b0;

            case (bb_state)
                BB_IDLE: begin
                    // Write takes priority; the AXI wrapper serialises
                    // read and write so both dest_req signals will not fire
                    // simultaneously under normal operation.
                    if (cdc_wr_dest_req) begin
                        bb_chip_select <= 1'b1;
                        bb_wr_stb      <= 1'b1;
                        bb_address     <= cdc_wr_dest_out[39:32];
                        bb_wdata       <= cdc_wr_dest_out[31:0];
                        // stay in BB_IDLE; write completes in one baseband cycle
                    end else if (cdc_rd_req_dest_req) begin
                        bb_chip_select <= 1'b1;
                        bb_rd_stb      <= 1'b1;
                        bb_address     <= cdc_rd_req_dest_out;
                        bb_state       <= BB_RD_ASSERT;
                    end
                end

                BB_RD_ASSERT: begin
                    // gps_baseband sees chip_select=1 / read=1 at this posedge
                    // and updates read_data with a non-blocking assignment;
                    // the new value is not visible until the next posedge.
                    bb_state <= BB_RD_CAP;
                end

                BB_RD_CAP: begin
                    // bb_rdata now holds the value written by gps_baseband
                    // at the BB_RD_ASSERT posedge.  Latch and send it back.
                    cdc_rd_data_src_in   <= bb_rdata;
                    cdc_rd_data_src_send <= 1'b1;
                    bb_state             <= BB_RD_WAIT_RCV;
                end

                BB_RD_WAIT_RCV: begin
                    cdc_rd_data_src_send <= 1'b1; // hold until aclk side acks
                    if (cdc_rd_data_src_rcv) begin
                        cdc_rd_data_src_send <= 1'b0;
                        bb_state             <= BB_IDLE;
                    end
                end

                default: bb_state <= BB_IDLE;
            endcase
        end
    end

    // -- aclk-domain AXI4-Lite FSMs ------------------------------------------

    wire [7:0] aw_word = s_axi_awaddr[ADDR_LSB + 7 : ADDR_LSB];
    wire [7:0] ar_word = s_axi_araddr[ADDR_LSB + 7 : ADDR_LSB];

    // Write FSM: IDLE -> SEND -> RESP
    // SEND holds cdc_wr_src_send high until cdc_wr_src_rcv confirms that
    // the baseband domain has committed the write.
    localparam [1:0] WR_IDLE = 2'd0;
    localparam [1:0] WR_SEND = 2'd1;
    localparam [1:0] WR_RESP = 2'd2;

    reg [1:0]  wr_state;
    reg [7:0]  wr_addr_lat;
    reg [31:0] wr_data_lat;

    // Read FSM: IDLE -> SEND_REQ -> WAIT_RCV -> WAIT_DATA -> RESP
    // SEND_REQ / WAIT_RCV send the address to the baseband domain.
    // WAIT_DATA waits for the read data to arrive back via CDC #3.
    localparam [2:0] RD_IDLE      = 3'd0;
    localparam [2:0] RD_SEND_REQ  = 3'd1;
    localparam [2:0] RD_WAIT_RCV  = 3'd2;
    localparam [2:0] RD_WAIT_DATA = 3'd3;
    localparam [2:0] RD_RESP      = 3'd4;

    reg [2:0]  rd_state;
    reg [7:0]  rd_addr_lat;
    reg [31:0] rd_data_lat;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready       <= 1'b0;
            s_axi_wready        <= 1'b0;
            s_axi_bresp         <= 2'b00;
            s_axi_bvalid        <= 1'b0;

            s_axi_arready       <= 1'b0;
            s_axi_rdata         <= 32'h0;
            s_axi_rresp         <= 2'b00;
            s_axi_rvalid        <= 1'b0;

            cdc_wr_src_send     <= 1'b0;
            cdc_wr_src_in       <= 40'h0;
            cdc_rd_req_src_send <= 1'b0;
            cdc_rd_req_src_in   <= 8'h00;

            wr_state            <= WR_IDLE;
            wr_addr_lat         <= 8'h00;
            wr_data_lat         <= 32'h0;

            rd_state            <= RD_IDLE;
            rd_addr_lat         <= 8'h00;
            rd_data_lat         <= 32'h0;
        end else begin
            s_axi_bresp <= 2'b00;
            s_axi_rresp <= 2'b00;

            // -- Write FSM ----------------------------------------------------
            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready   <= 1'b1;
                    s_axi_wready    <= 1'b1;
                    s_axi_bvalid    <= 1'b0;
                    cdc_wr_src_send <= 1'b0;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        wr_addr_lat   <= aw_word;
                        wr_data_lat   <= s_axi_wdata;
                        // awready and wready remain 1 for this (handshake) cycle;
                        // WR_SEND will deassert them on the next clock.
                        wr_state      <= WR_SEND;
                    end
                end

                WR_SEND: begin
                    s_axi_awready   <= 1'b0;
                    s_axi_wready    <= 1'b0;
                    s_axi_bvalid    <= 1'b0;
                    cdc_wr_src_send <= 1'b1;
                    cdc_wr_src_in   <= {wr_addr_lat, wr_data_lat};
                    if (cdc_wr_src_rcv) begin
                        cdc_wr_src_send <= 1'b0;
                        s_axi_bvalid    <= 1'b1;
                        wr_state        <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b1;
                    if (s_axi_bready)
                        wr_state <= WR_IDLE;
                end

                default: wr_state <= WR_IDLE;
            endcase

            // -- Read FSM -----------------------------------------------------
            case (rd_state)
                RD_IDLE: begin
                    s_axi_arready       <= 1'b1;
                    s_axi_rvalid        <= 1'b0;
                    cdc_rd_req_src_send <= 1'b0;
                    if (s_axi_arvalid) begin
                        rd_addr_lat   <= ar_word;
                        // arready remains 1 for this (handshake) cycle;
                        // RD_SEND_REQ will deassert it on the next clock.
                        rd_state      <= RD_SEND_REQ;
                    end
                end

                RD_SEND_REQ: begin
                    s_axi_arready       <= 1'b0;
                    cdc_rd_req_src_send <= 1'b1;
                    cdc_rd_req_src_in   <= rd_addr_lat;
                    rd_state            <= RD_WAIT_RCV;
                end

                RD_WAIT_RCV: begin
                    s_axi_arready       <= 1'b0;
                    cdc_rd_req_src_send <= 1'b1; // hold until baseband acks
                    if (cdc_rd_req_src_rcv) begin
                        cdc_rd_req_src_send <= 1'b0;
                        rd_state            <= RD_WAIT_DATA;
                    end
                end

                RD_WAIT_DATA: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b0;
                    if (cdc_rd_data_dest_req) begin
                        rd_data_lat <= cdc_rd_data_dest_out;
                        rd_state    <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rdata   <= rd_data_lat;
                    if (s_axi_rready)
                        rd_state <= RD_IDLE;
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
