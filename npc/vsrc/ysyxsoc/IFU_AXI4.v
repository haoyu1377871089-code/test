// AXI4 Master with Burst-to-Single Conversion for ICache
// This module handles AXI4 transactions for cache line refill
//
// NOTE: Flash XIP in ysyxSoC doesn't support AXI4 burst, so this module
// converts burst requests from ICache into multiple single-beat requests.
//
// Interface:
//   - ICache side: Simple request/response with burst length
//   - Memory side: AXI4 protocol (single-beat only)

module IFU_AXI4 (
    input clk,
    input rst,
    
    // ICache interface (upstream)
    input               icache_req,      // Read request
    input      [31:0]   icache_addr,     // Read address (line-aligned)
    input      [7:0]    icache_len,      // Burst length (0=1 beat, N-1=N beats)
    input               icache_flush,    // Flush: discard pending transaction
    output reg          icache_rvalid,   // Data valid
    output reg [31:0]   icache_rdata,    // Read data
    output reg          icache_rlast,    // Last beat of burst
    
    // AXI4 Master interface - Write channels (unused, IFU is read-only)
    output     [31:0]   m_axi_awaddr,
    output              m_axi_awvalid,
    input               m_axi_awready,
    output     [3:0]    m_axi_awid,
    output     [7:0]    m_axi_awlen,
    output     [2:0]    m_axi_awsize,
    output     [1:0]    m_axi_awburst,
    output              m_axi_awlock,
    output     [3:0]    m_axi_awcache,
    output     [2:0]    m_axi_awprot,
    
    output     [31:0]   m_axi_wdata,
    output     [3:0]    m_axi_wstrb,
    output              m_axi_wlast,
    output              m_axi_wvalid,
    input               m_axi_wready,
    
    input      [3:0]    m_axi_bid,
    input      [1:0]    m_axi_bresp,
    input               m_axi_bvalid,
    output              m_axi_bready,
    
    // AXI4 Master interface - Read Address Channel (AR)
    output reg [31:0]   m_axi_araddr,
    output reg          m_axi_arvalid,
    input               m_axi_arready,
    output     [3:0]    m_axi_arid,
    output     [7:0]    m_axi_arlen,     // Always 0 (single beat)
    output     [2:0]    m_axi_arsize,    // Transfer size (2 = 4 bytes)
    output     [1:0]    m_axi_arburst,   // Burst type (1 = INCR)
    output              m_axi_arlock,
    output     [3:0]    m_axi_arcache,
    output     [2:0]    m_axi_arprot,
    
    // AXI4 Master interface - Read Data Channel (R)
    input      [31:0]   m_axi_rdata,
    input      [1:0]    m_axi_rresp,
    input               m_axi_rvalid,
    output reg          m_axi_rready,
    input               m_axi_rlast,
    input      [3:0]    m_axi_rid
);

// ============================================================
// Write Channel Tie-offs (IFU is read-only)
// ============================================================
assign m_axi_awaddr  = 32'h0;
assign m_axi_awvalid = 1'b0;
assign m_axi_awid    = 4'b0;
assign m_axi_awlen   = 8'b0;
assign m_axi_awsize  = 3'b010;  // 4 bytes
assign m_axi_awburst = 2'b01;   // INCR
assign m_axi_awlock  = 1'b0;
assign m_axi_awcache = 4'b0;
assign m_axi_awprot  = 3'b0;

assign m_axi_wdata   = 32'h0;
assign m_axi_wstrb   = 4'h0;
assign m_axi_wlast   = 1'b0;
assign m_axi_wvalid  = 1'b0;

assign m_axi_bready  = 1'b0;

// ============================================================
// Read Channel Fixed Signals
// ============================================================
assign m_axi_arid    = 4'b0;           // Transaction ID
assign m_axi_arlen   = 8'h0;           // ALWAYS single beat (Flash doesn't support burst)
assign m_axi_arsize  = 3'b010;         // 4 bytes per transfer
assign m_axi_arburst = 2'b01;          // INCR burst type (doesn't matter for single beat)
assign m_axi_arlock  = 1'b0;           // Normal access
assign m_axi_arcache = 4'b0011;        // Normal Non-cacheable Bufferable
assign m_axi_arprot  = 3'b000;         // Unprivileged, secure, data

// ============================================================
// State Machine
// ============================================================
localparam S_IDLE = 2'd0;   // Waiting for request
localparam S_AR   = 2'd1;   // Waiting for AR handshake
localparam S_R    = 2'd2;   // Receiving R data

reg [1:0] state;
reg [7:0] beat_count;       // Current beat number (0-based)
reg [7:0] total_beats;      // Total beats expected
reg [31:0] base_addr;       // Base address for current burst
reg       discard_mode;     // Discard received data after flush

// ============================================================
// Performance Counters (simulation only)
// ============================================================
`ifdef SIMULATION
    reg [63:0] perf_ifu_fetch_cnt;       // Successful fetch count
    reg [63:0] perf_ifu_req_cycles;      // Request cycles
    reg [63:0] perf_ifu_wait_cycles;     // Wait cycles
    reg [63:0] perf_ifu_stall_arb_cycles; // Arbitration stall cycles
`endif

// ============================================================
// Main State Machine
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        m_axi_araddr <= 32'h0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready <= 1'b0;
        icache_rvalid <= 1'b0;
        icache_rdata <= 32'h0;
        icache_rlast <= 1'b0;
        beat_count <= 8'd0;
        total_beats <= 8'd0;
        base_addr <= 32'h0;
        discard_mode <= 1'b0;
`ifdef SIMULATION
        perf_ifu_fetch_cnt <= 64'h0;
        perf_ifu_req_cycles <= 64'h0;
        perf_ifu_wait_cycles <= 64'h0;
        perf_ifu_stall_arb_cycles <= 64'h0;
`endif
    end else begin
        // Default: clear single-cycle pulses
        icache_rvalid <= 1'b0;
        icache_rlast <= 1'b0;
        
        // Flush handling: enter discard mode, don't abort AXI transaction
        // (AXI protocol requires completing transactions once started)
        if (icache_flush && state != S_IDLE) begin
            discard_mode <= 1'b1;
        end
        
        case (state)
            S_IDLE: begin
                discard_mode <= 1'b0;  // Clear discard mode when idle
                if (icache_req && !icache_flush) begin
                    // Start first AR transaction
                    base_addr <= icache_addr;
                    m_axi_araddr <= icache_addr;
                    m_axi_arvalid <= 1'b1;
                    beat_count <= 8'd0;
                    total_beats <= icache_len + 1;
                    state <= S_AR;
`ifdef SIMULATION
                    perf_ifu_req_cycles <= perf_ifu_req_cycles + 1;
`endif
                end
            end
            
            S_AR: begin
                if (m_axi_arready) begin
                    // AR handshake complete
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready <= 1'b1;
                    state <= S_R;
                end
`ifdef SIMULATION
                if (!m_axi_arready) begin
                    perf_ifu_stall_arb_cycles <= perf_ifu_stall_arb_cycles + 1;
                end
                perf_ifu_wait_cycles <= perf_ifu_wait_cycles + 1;
`endif
            end
            
            S_R: begin
                if (m_axi_rvalid) begin
                    // Received data for current beat
                    m_axi_rready <= 1'b0;
                    
                    // Forward data to ICache (unless in discard mode)
                    if (!discard_mode) begin
                        icache_rvalid <= 1'b1;
                        icache_rdata <= m_axi_rdata;
                    end
                    
                    // Check if this is the last beat
                    if (beat_count + 1 >= total_beats) begin
                        // Burst complete
                        if (!discard_mode) begin
                            icache_rlast <= 1'b1;
                        end
                        state <= S_IDLE;
                        discard_mode <= 1'b0;
`ifdef SIMULATION
                        if (!discard_mode) begin
                            perf_ifu_fetch_cnt <= perf_ifu_fetch_cnt + 1;
                        end
`endif
                    end else begin
                        // More beats to fetch - start next AR transaction
                        beat_count <= beat_count + 1;
                        m_axi_araddr <= base_addr + {{22{1'b0}}, (beat_count[7:0] + 8'd1), 2'b0};  // Next word address
                        m_axi_arvalid <= 1'b1;
                        state <= S_AR;
                    end
                end
`ifdef SIMULATION
                perf_ifu_wait_cycles <= perf_ifu_wait_cycles + 1;
`endif
            end
            
            default: begin
                state <= S_IDLE;
                discard_mode <= 1'b0;
            end
        endcase
    end
end

endmodule
