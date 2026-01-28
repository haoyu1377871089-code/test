// AXI4 Arbiter with Full Burst Support
// Arbitrates between IFU (Master 0) and LSU (Master 1)
// 
// Features:
//   - Full AXI4 protocol support including burst transactions
//   - Priority: IFU > LSU (instruction fetch has higher priority)
//   - Transaction-level arbitration (waits for complete transaction)

module AXI4_Arbiter (
    input clk,
    input rst,
    
    // ============================================================
    // Master 0: IFU Interface (AXI4 with burst)
    // ============================================================
    // Write Address Channel
    input [31:0]  m0_awaddr,
    input         m0_awvalid,
    output reg    m0_awready,
    input [3:0]   m0_awid,
    input [7:0]   m0_awlen,
    input [2:0]   m0_awsize,
    input [1:0]   m0_awburst,
    
    // Write Data Channel
    input [31:0]  m0_wdata,
    input [3:0]   m0_wstrb,
    input         m0_wlast,
    input         m0_wvalid,
    output reg    m0_wready,
    
    // Write Response Channel
    output reg [3:0]  m0_bid,
    output reg [1:0]  m0_bresp,
    output reg        m0_bvalid,
    input             m0_bready,
    
    // Read Address Channel
    input [31:0]  m0_araddr,
    input         m0_arvalid,
    output reg    m0_arready,
    input [3:0]   m0_arid,
    input [7:0]   m0_arlen,
    input [2:0]   m0_arsize,
    input [1:0]   m0_arburst,
    
    // Read Data Channel
    output reg [3:0]  m0_rid,
    output reg [31:0] m0_rdata,
    output reg [1:0]  m0_rresp,
    output reg        m0_rlast,
    output reg        m0_rvalid,
    input             m0_rready,
    
    // ============================================================
    // Master 1: LSU Interface (AXI4 with burst)
    // ============================================================
    // Write Address Channel
    input [31:0]  m1_awaddr,
    input         m1_awvalid,
    output reg    m1_awready,
    input [3:0]   m1_awid,
    input [7:0]   m1_awlen,
    input [2:0]   m1_awsize,
    input [1:0]   m1_awburst,
    
    // Write Data Channel
    input [31:0]  m1_wdata,
    input [3:0]   m1_wstrb,
    input         m1_wlast,
    input         m1_wvalid,
    output reg    m1_wready,
    
    // Write Response Channel
    output reg [3:0]  m1_bid,
    output reg [1:0]  m1_bresp,
    output reg        m1_bvalid,
    input             m1_bready,
    
    // Read Address Channel
    input [31:0]  m1_araddr,
    input         m1_arvalid,
    output reg    m1_arready,
    input [3:0]   m1_arid,
    input [7:0]   m1_arlen,
    input [2:0]   m1_arsize,
    input [1:0]   m1_arburst,
    
    // Read Data Channel
    output reg [3:0]  m1_rid,
    output reg [31:0] m1_rdata,
    output reg [1:0]  m1_rresp,
    output reg        m1_rlast,
    output reg        m1_rvalid,
    input             m1_rready,
    
    // ============================================================
    // Slave Interface: Output to downstream (AXI4)
    // ============================================================
    // Write Address Channel
    output reg [31:0] s_awaddr,
    output reg        s_awvalid,
    input             s_awready,
    output reg [3:0]  s_awid,
    output reg [7:0]  s_awlen,
    output reg [2:0]  s_awsize,
    output reg [1:0]  s_awburst,
    
    // Write Data Channel
    output reg [31:0] s_wdata,
    output reg [3:0]  s_wstrb,
    output reg        s_wlast,
    output reg        s_wvalid,
    input             s_wready,
    
    // Write Response Channel
    input [3:0]       s_bid,
    input [1:0]       s_bresp,
    input             s_bvalid,
    output reg        s_bready,
    
    // Read Address Channel
    output reg [31:0] s_araddr,
    output reg        s_arvalid,
    input             s_arready,
    output reg [3:0]  s_arid,
    output reg [7:0]  s_arlen,
    output reg [2:0]  s_arsize,
    output reg [1:0]  s_arburst,
    
    // Read Data Channel
    input [3:0]       s_rid,
    input [31:0]      s_rdata,
    input [1:0]       s_rresp,
    input             s_rlast,
    input             s_rvalid,
    output reg        s_rready
);

// ============================================================
// Arbiter State Machine
// ============================================================
localparam ARB_IDLE = 2'b00;
localparam ARB_IFU  = 2'b01;  // IFU has bus
localparam ARB_LSU  = 2'b10;  // LSU has bus

reg [1:0] arb_state, arb_state_next;
reg [1:0] granted_master;  // Current master with bus access

// Request signals
wire ifu_req = m0_arvalid || m0_awvalid;  // IFU request (read or write)
wire lsu_req = m1_arvalid || m1_awvalid;  // LSU request (read or write)

// Transaction type tracking
reg is_read_txn;   // Current transaction is read (vs write)
reg [7:0] burst_cnt;  // Remaining beats in burst

// ============================================================
// Arbitration Logic (combinational)
// ============================================================
always @(*) begin
    arb_state_next = arb_state;
    granted_master = 2'b00;
    
    case (arb_state)
        ARB_IDLE: begin
            // Idle: select based on priority (IFU > LSU)
            if (ifu_req && lsu_req) begin
                // Both requesting, IFU wins
                arb_state_next = ARB_IFU;
                granted_master = 2'b00;
            end else if (ifu_req) begin
                arb_state_next = ARB_IFU;
                granted_master = 2'b00;
            end else if (lsu_req) begin
                arb_state_next = ARB_LSU;
                granted_master = 2'b01;
            end else begin
                arb_state_next = ARB_IDLE;
                granted_master = 2'b00;
            end
        end
        
        ARB_IFU: begin
            // IFU has the bus
            granted_master = 2'b00;
            // Check if transaction is complete
            // Read: wait for rlast && rvalid && rready
            // Write: wait for bvalid && bready
            if ((m0_rvalid && m0_rready && m0_rlast) ||    // Read burst complete
                (m0_bvalid && m0_bready)) begin            // Write complete
                arb_state_next = ARB_IDLE;
            end else begin
                arb_state_next = ARB_IFU;
            end
        end
        
        ARB_LSU: begin
            // LSU has the bus
            granted_master = 2'b01;
            // Check if transaction is complete
            if ((m1_rvalid && m1_rready && m1_rlast) ||    // Read burst complete
                (m1_bvalid && m1_bready)) begin            // Write complete
                arb_state_next = ARB_IDLE;
            end else begin
                arb_state_next = ARB_LSU;
            end
        end
        
        default: begin
            arb_state_next = ARB_IDLE;
            granted_master = 2'b00;
        end
    endcase
end

// ============================================================
// State Register
// ============================================================
always @(posedge clk or posedge rst) begin
    if (rst) begin
        arb_state <= ARB_IDLE;
    end else begin
        arb_state <= arb_state_next;
    end
end

// ============================================================
// Signal Multiplexing (combinational)
// ============================================================
always @(*) begin
    // Default: all ready/valid signals low
    m0_awready = 1'b0;
    m0_wready = 1'b0;
    m0_bvalid = 1'b0;
    m0_bid = 4'b0;
    m0_bresp = 2'b0;
    m0_arready = 1'b0;
    m0_rvalid = 1'b0;
    m0_rid = 4'b0;
    m0_rdata = 32'b0;
    m0_rresp = 2'b0;
    m0_rlast = 1'b0;
    
    m1_awready = 1'b0;
    m1_wready = 1'b0;
    m1_bvalid = 1'b0;
    m1_bid = 4'b0;
    m1_bresp = 2'b0;
    m1_arready = 1'b0;
    m1_rvalid = 1'b0;
    m1_rid = 4'b0;
    m1_rdata = 32'b0;
    m1_rresp = 2'b0;
    m1_rlast = 1'b0;
    
    // Default slave outputs
    s_awaddr = 32'h0;
    s_awvalid = 1'b0;
    s_awid = 4'b0;
    s_awlen = 8'b0;
    s_awsize = 3'b010;
    s_awburst = 2'b01;
    s_wdata = 32'h0;
    s_wstrb = 4'h0;
    s_wlast = 1'b0;
    s_wvalid = 1'b0;
    s_bready = 1'b0;
    s_araddr = 32'h0;
    s_arvalid = 1'b0;
    s_arid = 4'b0;
    s_arlen = 8'b0;
    s_arsize = 3'b010;
    s_arburst = 2'b01;
    s_rready = 1'b0;
    
    // 使用寄存器状态来控制多路复用
    // 在 ARB_IDLE 状态下，根据请求信号决定是否开始转发（零周期延迟仲裁）
    case (arb_state)
        ARB_IDLE: begin
            // 在 IDLE 状态，如果有请求则立即开始转发（优先级：IFU > LSU）
            if (ifu_req) begin
                // 转发 IFU 信号
                s_awaddr = m0_awaddr;
                s_awvalid = m0_awvalid;
                s_awid = m0_awid;
                s_awlen = m0_awlen;
                s_awsize = m0_awsize;
                s_awburst = m0_awburst;
                s_wdata = m0_wdata;
                s_wstrb = m0_wstrb;
                s_wlast = m0_wlast;
                s_wvalid = m0_wvalid;
                s_bready = m0_bready;
                s_araddr = m0_araddr;
                s_arvalid = m0_arvalid;
                s_arid = m0_arid;
                s_arlen = m0_arlen;
                s_arsize = m0_arsize;
                s_arburst = m0_arburst;
                s_rready = m0_rready;
                m0_awready = s_awready;
                m0_wready = s_wready;
                m0_bvalid = s_bvalid;
                m0_bid = s_bid;
                m0_bresp = s_bresp;
                m0_arready = s_arready;
                m0_rvalid = s_rvalid;
                m0_rid = s_rid;
                m0_rdata = s_rdata;
                m0_rresp = s_rresp;
                m0_rlast = s_rlast;
            end else if (lsu_req) begin
                // 转发 LSU 信号
                s_awaddr = m1_awaddr;
                s_awvalid = m1_awvalid;
                s_awid = m1_awid;
                s_awlen = m1_awlen;
                s_awsize = m1_awsize;
                s_awburst = m1_awburst;
                s_wdata = m1_wdata;
                s_wstrb = m1_wstrb;
                s_wlast = m1_wlast;
                s_wvalid = m1_wvalid;
                s_bready = m1_bready;
                s_araddr = m1_araddr;
                s_arvalid = m1_arvalid;
                s_arid = m1_arid;
                s_arlen = m1_arlen;
                s_arsize = m1_arsize;
                s_arburst = m1_arburst;
                s_rready = m1_rready;
                m1_awready = s_awready;
                m1_wready = s_wready;
                m1_bvalid = s_bvalid;
                m1_bid = s_bid;
                m1_bresp = s_bresp;
                m1_arready = s_arready;
                m1_rvalid = s_rvalid;
                m1_rid = s_rid;
                m1_rdata = s_rdata;
                m1_rresp = s_rresp;
                m1_rlast = s_rlast;
            end
            // 如果没有请求，保持默认值（不转发）
        end
        
        ARB_IFU: begin  // IFU (M0) granted
            // Forward M0 -> Slave
            s_awaddr = m0_awaddr;
            s_awvalid = m0_awvalid;
            s_awid = m0_awid;
            s_awlen = m0_awlen;
            s_awsize = m0_awsize;
            s_awburst = m0_awburst;
            
            s_wdata = m0_wdata;
            s_wstrb = m0_wstrb;
            s_wlast = m0_wlast;
            s_wvalid = m0_wvalid;
            
            s_bready = m0_bready;
            
            s_araddr = m0_araddr;
            s_arvalid = m0_arvalid;
            s_arid = m0_arid;
            s_arlen = m0_arlen;
            s_arsize = m0_arsize;
            s_arburst = m0_arburst;
            
            s_rready = m0_rready;
            
            // Forward Slave -> M0
            m0_awready = s_awready;
            m0_wready = s_wready;
            m0_bvalid = s_bvalid;
            m0_bid = s_bid;
            m0_bresp = s_bresp;
            m0_arready = s_arready;
            m0_rvalid = s_rvalid;
            m0_rid = s_rid;
            m0_rdata = s_rdata;
            m0_rresp = s_rresp;
            m0_rlast = s_rlast;
        end
        
        ARB_LSU: begin  // LSU (M1) granted
            // Forward M1 -> Slave
            s_awaddr = m1_awaddr;
            s_awvalid = m1_awvalid;
            s_awid = m1_awid;
            s_awlen = m1_awlen;
            s_awsize = m1_awsize;
            s_awburst = m1_awburst;
            
            s_wdata = m1_wdata;
            s_wstrb = m1_wstrb;
            s_wlast = m1_wlast;
            s_wvalid = m1_wvalid;
            
            s_bready = m1_bready;
            
            s_araddr = m1_araddr;
            s_arvalid = m1_arvalid;
            s_arid = m1_arid;
            s_arlen = m1_arlen;
            s_arsize = m1_arsize;
            s_arburst = m1_arburst;
            
            s_rready = m1_rready;
            
            // Forward Slave -> M1
            m1_awready = s_awready;
            m1_wready = s_wready;
            m1_bvalid = s_bvalid;
            m1_bid = s_bid;
            m1_bresp = s_bresp;
            m1_arready = s_arready;
            m1_rvalid = s_rvalid;
            m1_rid = s_rid;
            m1_rdata = s_rdata;
            m1_rresp = s_rresp;
            m1_rlast = s_rlast;
        end
        
        default: begin
            // Keep defaults (all blocked)
        end
    endcase
end

// Debug: Arbiter state
`ifdef SIMULATION
    reg [63:0] arb_dbg_cycle;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arb_dbg_cycle <= 0;
        end else begin
            arb_dbg_cycle <= arb_dbg_cycle + 1;
            if ((arb_dbg_cycle < 5000 && s_rvalid)) begin
                $display("[ARB@%0d] st=%d arv=%b arr=%b rr=%b rv=%b addr=%h",
                         arb_dbg_cycle, arb_state, s_arvalid, s_arready, s_rready, s_rvalid, s_araddr);
            end
        end
    end
`endif

endmodule
