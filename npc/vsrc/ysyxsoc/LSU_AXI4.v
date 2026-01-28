// LSU AXI4 Master Module
// Handles load/store operations with full AXI4 protocol
// Supports both single-beat and burst transactions for DCache refill

module LSU_AXI4 (
    input clk,
    input rst,
    
    // Original interface (for compatibility)
    input req,              // Memory request
    input wen,              // Write enable: 1=write, 0=read
    input [31:0] addr,      // 32-bit address
    input [31:0] wdata,     // Write data
    input [3:0] wmask,      // Byte write mask
    input [7:0] burst_len,  // Burst length (0=1 beat, N-1=N beats) - NEW for DCache
    output reg rvalid_out,  // Read data valid (per beat for burst)
    output reg [31:0] rdata_out, // Read data
    output reg rlast_out,   // Last beat of burst - NEW for DCache
    
    // AXI4 Master Interface - Write Address Channel
    output reg [31:0]   m_axi_awaddr,
    output reg          m_axi_awvalid,
    input               m_axi_awready,
    output     [3:0]    m_axi_awid,
    output reg [7:0]    m_axi_awlen,
    output     [2:0]    m_axi_awsize,
    output     [1:0]    m_axi_awburst,
    
    // AXI4 Master Interface - Write Data Channel
    output reg [31:0]   m_axi_wdata,
    output reg [3:0]    m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input               m_axi_wready,
    
    // AXI4 Master Interface - Write Response Channel
    input      [3:0]    m_axi_bid,
    input      [1:0]    m_axi_bresp,
    input               m_axi_bvalid,
    output reg          m_axi_bready,
    
    // AXI4 Master Interface - Read Address Channel
    output reg [31:0]   m_axi_araddr,
    output reg          m_axi_arvalid,
    input               m_axi_arready,
    output     [3:0]    m_axi_arid,
    output reg [7:0]    m_axi_arlen,
    output     [2:0]    m_axi_arsize,
    output     [1:0]    m_axi_arburst,
    
    // AXI4 Master Interface - Read Data Channel
    input      [3:0]    m_axi_rid,
    input      [31:0]   m_axi_rdata,
    input      [1:0]    m_axi_rresp,
    input               m_axi_rlast,
    input               m_axi_rvalid,
    output reg          m_axi_rready
);

// ============================================================
// Fixed AXI4 Signals
// ============================================================
assign m_axi_awid    = 4'b0001;    // LSU uses ID 1 (IFU uses ID 0)
assign m_axi_awsize  = 3'b010;     // 4 bytes
assign m_axi_awburst = 2'b01;      // INCR

assign m_axi_arid    = 4'b0001;    // LSU uses ID 1
assign m_axi_arsize  = 3'b010;     // 4 bytes
assign m_axi_arburst = 2'b01;      // INCR

// ============================================================
// Performance Counters (simulation only)
// ============================================================
`ifdef SIMULATION
    reg [63:0] perf_lsu_load_cnt;
    reg [63:0] perf_lsu_store_cnt;
    reg [63:0] perf_lsu_load_cycles;
    reg [63:0] perf_lsu_store_cycles;
    reg [63:0] perf_lsu_stall_arb_cycles;
    reg [63:0] perf_lsu_burst_cnt;        // NEW: burst transaction count
    reg [31:0] lsu_cycle_counter;
    reg        lsu_in_flight;
    reg        lsu_is_load;
`endif

// ============================================================
// State Machine
// ============================================================
localparam S_IDLE     = 3'd0;
localparam S_WRITE_AW = 3'd1;  // Write address phase
localparam S_WRITE_W  = 3'd2;  // Write data phase
localparam S_WRITE_B  = 3'd3;  // Write response phase
localparam S_READ_AR  = 3'd4;  // Read address phase
localparam S_READ_R   = 3'd5;  // Read data phase (handles burst)

reg [2:0] state;
reg [31:0] saved_addr;  // Save address for alignment
reg [7:0] saved_burst_len;  // Save burst length
reg is_burst;           // Flag for burst transaction

// ============================================================
// Main State Machine
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        rvalid_out <= 1'b0;
        rdata_out <= 32'h0;
        rlast_out <= 1'b0;
        saved_addr <= 32'h0;
        saved_burst_len <= 8'h0;
        is_burst <= 1'b0;
        
        // AXI4 signals
        m_axi_awaddr <= 32'h0;
        m_axi_awvalid <= 1'b0;
        m_axi_awlen <= 8'h0;
        m_axi_wdata <= 32'h0;
        m_axi_wstrb <= 4'h0;
        m_axi_wlast <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
        m_axi_araddr <= 32'h0;
        m_axi_arvalid <= 1'b0;
        m_axi_arlen <= 8'h0;
        m_axi_rready <= 1'b0;
        
`ifdef SIMULATION
        perf_lsu_load_cnt <= 64'h0;
        perf_lsu_store_cnt <= 64'h0;
        perf_lsu_load_cycles <= 64'h0;
        perf_lsu_store_cycles <= 64'h0;
        perf_lsu_stall_arb_cycles <= 64'h0;
        perf_lsu_burst_cnt <= 64'h0;
        lsu_cycle_counter <= 32'h0;
        lsu_in_flight <= 1'b0;
        lsu_is_load <= 1'b0;
`endif
    end else begin
        // Default: clear single-cycle pulses
        rvalid_out <= 1'b0;
        rlast_out <= 1'b0;
        
        case (state)
            S_IDLE: begin
                if (req) begin
                    saved_addr <= addr;
                    saved_burst_len <= burst_len;
                    is_burst <= (burst_len != 8'h0);
                    
                    if (wen) begin
                        // Write request (always single-beat for write-through)
                        m_axi_awaddr <= addr;
                        m_axi_awvalid <= 1'b1;
                        m_axi_awlen <= 8'h0;  // Write is always single beat
                        m_axi_wdata <= wdata;
                        m_axi_wstrb <= wmask;
                        m_axi_wlast <= 1'b1;  // Single beat, so always last
                        m_axi_wvalid <= 1'b1;
                        state <= S_WRITE_AW;
`ifdef SIMULATION
                        perf_lsu_store_cnt <= perf_lsu_store_cnt + 1;
                        lsu_in_flight <= 1'b1;
                        lsu_is_load <= 1'b0;
                        lsu_cycle_counter <= 32'h1;
`endif
                    end else begin
                        // Read request (can be single or burst)
                        m_axi_araddr <= addr;
                        m_axi_arvalid <= 1'b1;
                        m_axi_arlen <= burst_len;  // Use provided burst length
                        m_axi_rready <= 1'b1;
                        state <= S_READ_AR;
`ifdef SIMULATION
                        perf_lsu_load_cnt <= perf_lsu_load_cnt + 1;
                        if (burst_len != 8'h0) perf_lsu_burst_cnt <= perf_lsu_burst_cnt + 1;
                        lsu_in_flight <= 1'b1;
                        lsu_is_load <= 1'b1;
                        lsu_cycle_counter <= 32'h1;
`endif
                    end
                end
            end
            
            // ============================================================
            // Write Transaction States
            // ============================================================
            S_WRITE_AW: begin
`ifdef SIMULATION
                lsu_cycle_counter <= lsu_cycle_counter + 1;
                if (!m_axi_awready) perf_lsu_stall_arb_cycles <= perf_lsu_stall_arb_cycles + 1;
`endif
                // Handle AW and W handshakes (can happen in any order or same cycle)
                if (m_axi_awready && m_axi_awvalid) begin
                    m_axi_awvalid <= 1'b0;
                end
                if (m_axi_wready && m_axi_wvalid) begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                end
                
                // When both are done, wait for response
                if (!m_axi_awvalid && !m_axi_wvalid) begin
                    m_axi_bready <= 1'b1;
                    state <= S_WRITE_B;
                end else if (m_axi_awready || m_axi_wready) begin
                    // At least one handshake done, continue
                    state <= S_WRITE_W;
                end
            end
            
            S_WRITE_W: begin
`ifdef SIMULATION
                lsu_cycle_counter <= lsu_cycle_counter + 1;
`endif
                // Continue handling handshakes
                if (m_axi_awready && m_axi_awvalid) begin
                    m_axi_awvalid <= 1'b0;
                end
                if (m_axi_wready && m_axi_wvalid) begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast <= 1'b0;
                end
                
                // Both done, wait for response
                if (!m_axi_awvalid && !m_axi_wvalid) begin
                    m_axi_bready <= 1'b1;
                    state <= S_WRITE_B;
                end
            end
            
            S_WRITE_B: begin
`ifdef SIMULATION
                lsu_cycle_counter <= lsu_cycle_counter + 1;
`endif
                if (m_axi_bvalid) begin
                    m_axi_bready <= 1'b0;
                    rvalid_out <= 1'b1;  // Write complete signal
                    rlast_out <= 1'b1;   // Write is always single beat
                    state <= S_IDLE;
`ifdef SIMULATION
                    perf_lsu_store_cycles <= perf_lsu_store_cycles + {32'b0, lsu_cycle_counter};
                    lsu_in_flight <= 1'b0;
`endif
                end
            end
            
            // ============================================================
            // Read Transaction States (with burst support)
            // ============================================================
            S_READ_AR: begin
`ifdef SIMULATION
                lsu_cycle_counter <= lsu_cycle_counter + 1;
                if (!m_axi_arready) perf_lsu_stall_arb_cycles <= perf_lsu_stall_arb_cycles + 1;
`endif
                if (m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    state <= S_READ_R;
                end
            end
            
            S_READ_R: begin
`ifdef SIMULATION
                lsu_cycle_counter <= lsu_cycle_counter + 1;
`endif
                if (m_axi_rvalid) begin
                    // For burst: forward each beat to upstream
                    // For single beat: apply address alignment
                    if (is_burst) begin
                        // Burst mode: pass data directly
                        rdata_out <= m_axi_rdata;
                    end else begin
                        // Single beat mode: align data based on address
                        case (saved_addr[1:0])
                            2'b00: rdata_out <= m_axi_rdata;
                            2'b01: rdata_out <= {8'b0, m_axi_rdata[31:8]};
                            2'b10: rdata_out <= {16'b0, m_axi_rdata[31:16]};
                            2'b11: rdata_out <= {24'b0, m_axi_rdata[31:24]};
                        endcase
                    end
                    rvalid_out <= 1'b1;
                    rlast_out <= m_axi_rlast;  // Forward rlast from AXI
                    
                    if (m_axi_rlast) begin
                        // Last beat of burst (or single beat)
                        m_axi_rready <= 1'b0;
                        state <= S_IDLE;
`ifdef SIMULATION
                        perf_lsu_load_cycles <= perf_lsu_load_cycles + {32'b0, lsu_cycle_counter};
                        lsu_in_flight <= 1'b0;
`endif
                    end
                    // If not last beat, stay in S_READ_R to receive more data
                end
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
