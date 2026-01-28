// ysyx_00000000: NPC Top Module with AXI4 Burst Support
// 
// This module integrates:
//   - EXU (Execution Unit)
//   - ICache (Instruction Cache with burst refill)
//   - DCache (Data Cache with write-through)
//   - IFU_AXI4 (AXI4 Master for instruction fetch)
//   - LSU_AXI4 (AXI4 Master for data access, with burst support)
//   - AXI4_Arbiter (Bus arbitration with burst support)
//
// The AXI4-Lite to AXI4 Bridge is no longer needed since we now use
// native AXI4 interfaces throughout.
//
// 当 ENABLE_PIPELINE 定义时，使用 pipeline/ysyx_pipeline_top.v 中的流水线版本

`ifndef ENABLE_PIPELINE

module ysyx_00000000 (
    input         clock,
    input         reset,
    input         io_interrupt,
    input         io_master_awready,
    output        io_master_awvalid,
    output [31:0] io_master_awaddr,
    output [3:0]  io_master_awid,
    output [7:0]  io_master_awlen,
    output [2:0]  io_master_awsize,
    output [1:0]  io_master_awburst,
    output        io_master_awlock,
    output [3:0]  io_master_awcache,
    output [2:0]  io_master_awprot,
    input         io_master_wready,
    output        io_master_wvalid,
    output [31:0] io_master_wdata,
    output [3:0]  io_master_wstrb,
    output        io_master_wlast,
    input         io_master_bvalid,
    output        io_master_bready,
    input  [1:0]  io_master_bresp,
    input  [3:0]  io_master_bid,
    input         io_master_arready,
    output        io_master_arvalid,
    output [31:0] io_master_araddr,
    output [3:0]  io_master_arid,
    output [7:0]  io_master_arlen,
    output [2:0]  io_master_arsize,
    output [1:0]  io_master_arburst,
    output        io_master_arlock,
    output [3:0]  io_master_arcache,
    output [2:0]  io_master_arprot,
    output        io_master_rready,
    input         io_master_rvalid,
    input  [1:0]  io_master_rresp,
    input  [31:0] io_master_rdata,
    input         io_master_rlast,
    input  [3:0]  io_master_rid,
    
    output        io_slave_awready,
    input         io_slave_awvalid,
    input  [31:0] io_slave_awaddr,
    input  [3:0]  io_slave_awid,
    input  [7:0]  io_slave_awlen,
    input  [2:0]  io_slave_awsize,
    input  [1:0]  io_slave_awburst,
    input         io_slave_awlock,
    input  [3:0]  io_slave_awcache,
    input  [2:0]  io_slave_awprot,
    output        io_slave_wready,
    input         io_slave_wvalid,
    input  [31:0] io_slave_wdata,
    input  [3:0]  io_slave_wstrb,
    input         io_slave_wlast,
    output        io_slave_bvalid,
    input         io_slave_bready,
    output [1:0]  io_slave_bresp,
    output [3:0]  io_slave_bid,
    output        io_slave_arready,
    input         io_slave_arvalid,
    input  [31:0] io_slave_araddr,
    input  [3:0]  io_slave_arid,
    input  [7:0]  io_slave_arlen,
    input  [2:0]  io_slave_arsize,
    input  [1:0]  io_slave_arburst,
    input         io_slave_arlock,
    input  [3:0]  io_slave_arcache,
    input  [2:0]  io_slave_arprot,
    input         io_slave_rready,
    output        io_slave_rvalid,
    output [1:0]  io_slave_rresp,
    output [31:0] io_slave_rdata,
    output        io_slave_rlast,
    output [3:0]  io_slave_rid
);

`ifdef SIMULATION
    import "DPI-C" function void npc_trap(input int exit_code);
`endif

    // ------------------------------------------------------
    // Slave Interface (Unused - Tied Off)
    // ------------------------------------------------------
    assign io_slave_awready = 1'b0;
    assign io_slave_wready  = 1'b0;
    assign io_slave_bvalid  = 1'b0;
    assign io_slave_bresp   = 2'b0;
    assign io_slave_bid     = 4'b0;
    assign io_slave_arready = 1'b0;
    assign io_slave_rvalid  = 1'b0;
    assign io_slave_rresp   = 2'b0;
    assign io_slave_rdata   = 32'b0;
    assign io_slave_rlast   = 1'b0;
    assign io_slave_rid     = 4'b0;

    // ------------------------------------------------------
    // Internal Signals
    // ------------------------------------------------------
    wire clk = clock;
    wire rst = reset;

    // EXU Signals
    wire ex_end;
    wire [31:0] next_pc;
    wire branch_taken;
    wire ebreak_detected;
    wire [31:0] exit_value;
    wire [31:0] exu_regs [0:31];

    // LSU Signals (from EXU)
    wire lsu_req;
    wire lsu_wen;
    wire [31:0] lsu_addr;
    wire [31:0] lsu_wdata;
    wire [3:0]  lsu_wmask;
    wire lsu_rvalid;
    wire [31:0] lsu_rdata;

    // D-Cache Signals
    wire        dcache_rvalid;
    wire [31:0] dcache_rdata;
    wire        dcache_mem_req;
    wire        dcache_mem_wen;
    wire [31:0] dcache_mem_addr;
    wire [31:0] dcache_mem_wdata;
    wire [3:0]  dcache_mem_wmask;
    wire [7:0]  dcache_mem_len;
    wire        dcache_mem_rvalid;
    wire [31:0] dcache_mem_rdata;
    wire        dcache_mem_rlast;

    // IFU Signals
    reg [31:0] pc;
    reg rdop_en_reg;
    reg ex_end_prev;
    reg end_flag_reg;
    reg rdop_en_prev;
    reg update_pc;
    reg [31:0] exit_code_reg;

    wire ifu_rvalid;
    wire [31:0] ifu_rdata;
    reg ifu_req;
    reg first_fetch_pending;
    reg op_en_ifu;
    reg [31:0] op_ifu;
    wire [31:0] ifu_addr = (update_pc) ? next_pc : pc;

    // I-Cache Signals
    wire        icache_rvalid;
    wire [31:0] icache_rdata;
    wire        icache_mem_req;
    wire [31:0] icache_mem_addr;
    wire [7:0]  icache_mem_len;     // Burst length
    wire        icache_mem_rvalid;
    wire [31:0] icache_mem_rdata;
    wire        icache_mem_rlast;   // Last beat

    // IFU AXI4 Signals (Full AXI4 with burst)
    wire [31:0] ifu_axi_awaddr;
    wire        ifu_axi_awvalid;
    wire        ifu_axi_awready;
    wire [3:0]  ifu_axi_awid;
    wire [7:0]  ifu_axi_awlen;
    wire [2:0]  ifu_axi_awsize;
    wire [1:0]  ifu_axi_awburst;
    wire [31:0] ifu_axi_wdata;
    wire [3:0]  ifu_axi_wstrb;
    wire        ifu_axi_wlast;
    wire        ifu_axi_wvalid;
    wire        ifu_axi_wready;
    wire [3:0]  ifu_axi_bid;
    wire [1:0]  ifu_axi_bresp;
    wire        ifu_axi_bvalid;
    wire        ifu_axi_bready;
    wire [31:0] ifu_axi_araddr;
    wire        ifu_axi_arvalid;
    wire        ifu_axi_arready;
    wire [3:0]  ifu_axi_arid;
    wire [7:0]  ifu_axi_arlen;
    wire [2:0]  ifu_axi_arsize;
    wire [1:0]  ifu_axi_arburst;
    wire [3:0]  ifu_axi_rid;
    wire [31:0] ifu_axi_rdata;
    wire [1:0]  ifu_axi_rresp;
    wire        ifu_axi_rlast;
    wire        ifu_axi_rvalid;
    wire        ifu_axi_rready;

    // LSU AXI4 Signals
    wire [31:0] lsu_axi_awaddr;
    wire        lsu_axi_awvalid;
    wire        lsu_axi_awready;
    wire [3:0]  lsu_axi_awid;
    wire [7:0]  lsu_axi_awlen;
    wire [2:0]  lsu_axi_awsize;
    wire [1:0]  lsu_axi_awburst;
    wire [31:0] lsu_axi_wdata;
    wire [3:0]  lsu_axi_wstrb;
    wire        lsu_axi_wlast;
    wire        lsu_axi_wvalid;
    wire        lsu_axi_wready;
    wire [3:0]  lsu_axi_bid;
    wire [1:0]  lsu_axi_bresp;
    wire        lsu_axi_bvalid;
    wire        lsu_axi_bready;
    wire [31:0] lsu_axi_araddr;
    wire        lsu_axi_arvalid;
    wire        lsu_axi_arready;
    wire [3:0]  lsu_axi_arid;
    wire [7:0]  lsu_axi_arlen;
    wire [2:0]  lsu_axi_arsize;
    wire [1:0]  lsu_axi_arburst;
    wire [3:0]  lsu_axi_rid;
    wire [31:0] lsu_axi_rdata;
    wire [1:0]  lsu_axi_rresp;
    wire        lsu_axi_rlast;
    wire        lsu_axi_rvalid;
    wire        lsu_axi_rready;

    // ------------------------------------------------------
    // Module Instantiations
    // ------------------------------------------------------

    // EXU
    EXU EXU (
        .clk         (clk),
        .rst         (rst),
        .op          (op_ifu),
        .op_en       (op_en_ifu),
        .pc          (pc),
        .ex_end      (ex_end),
        .next_pc     (next_pc),
        .branch_taken(branch_taken),
        .lsu_req     (lsu_req),
        .lsu_wen     (lsu_wen),
        .lsu_addr    (lsu_addr),
        .lsu_wdata   (lsu_wdata),
        .lsu_wmask   (lsu_wmask),
        .lsu_rvalid  (lsu_rvalid),
        .lsu_rdata   (lsu_rdata),
        .ebreak_flag (ebreak_detected),
        .exit_code   (exit_value)
    );

    // I-Cache with burst support
`ifdef ENABLE_ICACHE
    ICache #(
        .CACHE_SIZE    (4096),   // 4KB
        .LINE_SIZE     (16),     // 16 bytes per line (4 words)
        .NUM_WAYS      (2),      // 2-way set associative
        .ADDR_WIDTH    (32)
    ) u_icache (
        .clk         (clk),
        .rst         (rst),
        // Upstream interface (to CPU)
        .cpu_req     (ifu_req),
        .cpu_addr    (ifu_addr),
        .cpu_rvalid  (icache_rvalid),
        .cpu_rdata   (icache_rdata),
        // Downstream interface (to IFU_AXI4)
        .mem_req     (icache_mem_req),
        .mem_addr    (icache_mem_addr),
        .mem_len     (icache_mem_len),
        .mem_rvalid  (icache_mem_rvalid),
        .mem_rdata   (icache_mem_rdata),
        .mem_rlast   (icache_mem_rlast)
    );

    // Connect ICache outputs to IFU signals
    assign ifu_rvalid = icache_rvalid;
    assign ifu_rdata = icache_rdata;

    // IFU_AXI4 (driven by ICache for burst memory access)
    IFU_AXI4 u_ifu (
        .clk             (clk),
        .rst             (rst),
        // ICache interface
        .icache_req      (icache_mem_req),
        .icache_addr     (icache_mem_addr),
        .icache_len      (icache_mem_len),
        .icache_flush    (1'b0),          // Single-cycle: no flush
        .icache_rvalid   (icache_mem_rvalid),
        .icache_rdata    (icache_mem_rdata),
        .icache_rlast    (icache_mem_rlast),
`else
    // Bypass I-Cache: connect directly to IFU_AXI4
    assign icache_rvalid = 1'b0;
    assign icache_rdata = 32'h0;
    assign icache_mem_req = 1'b0;
    assign icache_mem_addr = 32'h0;
    assign icache_mem_len = 8'h0;

    // IFU_AXI4 (directly connected to control logic, single-beat mode)
    IFU_AXI4 u_ifu (
        .clk             (clk),
        .rst             (rst),
        // Direct interface (no ICache)
        .icache_req      (ifu_req),
        .icache_addr     (ifu_addr),
        .icache_len      (8'h0),          // Single beat
        .icache_flush    (1'b0),          // Single-cycle: no flush
        .icache_rvalid   (ifu_rvalid),
        .icache_rdata    (ifu_rdata),
        .icache_rlast    (),              // Unused in single-beat mode
`endif
        // AXI4 Master interface
        .m_axi_awaddr    (ifu_axi_awaddr),
        .m_axi_awvalid   (ifu_axi_awvalid),
        .m_axi_awready   (ifu_axi_awready),
        .m_axi_awid      (ifu_axi_awid),
        .m_axi_awlen     (ifu_axi_awlen),
        .m_axi_awsize    (ifu_axi_awsize),
        .m_axi_awburst   (ifu_axi_awburst),
        .m_axi_awlock    (),
        .m_axi_awcache   (),
        .m_axi_awprot    (),
        .m_axi_wdata     (ifu_axi_wdata),
        .m_axi_wstrb     (ifu_axi_wstrb),
        .m_axi_wlast     (ifu_axi_wlast),
        .m_axi_wvalid    (ifu_axi_wvalid),
        .m_axi_wready    (ifu_axi_wready),
        .m_axi_bid       (ifu_axi_bid),
        .m_axi_bresp     (ifu_axi_bresp),
        .m_axi_bvalid    (ifu_axi_bvalid),
        .m_axi_bready    (ifu_axi_bready),
        .m_axi_araddr    (ifu_axi_araddr),
        .m_axi_arvalid   (ifu_axi_arvalid),
        .m_axi_arready   (ifu_axi_arready),
        .m_axi_arid      (ifu_axi_arid),
        .m_axi_arlen     (ifu_axi_arlen),
        .m_axi_arsize    (ifu_axi_arsize),
        .m_axi_arburst   (ifu_axi_arburst),
        .m_axi_arlock    (),
        .m_axi_arcache   (),
        .m_axi_arprot    (),
        .m_axi_rid       (ifu_axi_rid),
        .m_axi_rdata     (ifu_axi_rdata),
        .m_axi_rresp     (ifu_axi_rresp),
        .m_axi_rlast     (ifu_axi_rlast),
        .m_axi_rvalid    (ifu_axi_rvalid),
        .m_axi_rready    (ifu_axi_rready)
    );

    // D-Cache with write-through support
`ifdef ENABLE_DCACHE
    DCache #(
        .CACHE_SIZE    (4096),   // 4KB
        .LINE_SIZE     (16),     // 16 bytes per line (4 words)
        .NUM_WAYS      (2),      // 2-way set associative
        .ADDR_WIDTH    (32)
    ) u_dcache (
        .clk         (clk),
        .rst         (rst),
        // Upstream interface (to EXU)
        .cpu_req     (lsu_req),
        .cpu_wen     (lsu_wen),
        .cpu_addr    (lsu_addr),
        .cpu_wdata   (lsu_wdata),
        .cpu_wmask   (lsu_wmask),
        .cpu_rvalid  (dcache_rvalid),
        .cpu_rdata   (dcache_rdata),
        // Downstream interface (to LSU_AXI4)
        .mem_req     (dcache_mem_req),
        .mem_wen     (dcache_mem_wen),
        .mem_addr    (dcache_mem_addr),
        .mem_wdata   (dcache_mem_wdata),
        .mem_wmask   (dcache_mem_wmask),
        .mem_len     (dcache_mem_len),
        .mem_rvalid  (dcache_mem_rvalid),
        .mem_rdata   (dcache_mem_rdata),
        .mem_rlast   (dcache_mem_rlast)
    );

    // Connect DCache outputs to LSU signals for EXU
    assign lsu_rvalid = dcache_rvalid;
    assign lsu_rdata = dcache_rdata;

    // LSU_AXI4 (driven by DCache, with burst support for refill)
    LSU_AXI4 u_lsu (
        .clk             (clk),
        .rst             (rst),
        // Interface from DCache
        .req             (dcache_mem_req),
        .wen             (dcache_mem_wen),
        .addr            (dcache_mem_addr),
        .wdata           (dcache_mem_wdata),
        .wmask           (dcache_mem_wmask),
        .burst_len       (dcache_mem_len),
        .rvalid_out      (dcache_mem_rvalid),
        .rdata_out       (dcache_mem_rdata),
        .rlast_out       (dcache_mem_rlast),
`else
    // Bypass D-Cache: connect EXU directly to LSU_AXI4
    assign dcache_rvalid = 1'b0;
    assign dcache_rdata = 32'h0;
    assign dcache_mem_req = 1'b0;
    assign dcache_mem_wen = 1'b0;
    assign dcache_mem_addr = 32'h0;
    assign dcache_mem_wdata = 32'h0;
    assign dcache_mem_wmask = 4'h0;
    assign dcache_mem_len = 8'h0;

    // LSU_AXI4 (directly connected to EXU, single-beat mode)
    LSU_AXI4 u_lsu (
        .clk             (clk),
        .rst             (rst),
        // Original interface from EXU
        .req             (lsu_req),
        .wen             (lsu_wen),
        .addr            (lsu_addr),
        .wdata           (lsu_wdata),
        .wmask           (lsu_wmask),
        .burst_len       (8'h0),           // Single beat
        .rvalid_out      (lsu_rvalid),
        .rdata_out       (lsu_rdata),
        .rlast_out       (),               // Unused in single-beat mode
`endif
        // AXI4 Master interface
        .m_axi_awaddr    (lsu_axi_awaddr),
        .m_axi_awvalid   (lsu_axi_awvalid),
        .m_axi_awready   (lsu_axi_awready),
        .m_axi_awid      (lsu_axi_awid),
        .m_axi_awlen     (lsu_axi_awlen),
        .m_axi_awsize    (lsu_axi_awsize),
        .m_axi_awburst   (lsu_axi_awburst),
        .m_axi_wdata     (lsu_axi_wdata),
        .m_axi_wstrb     (lsu_axi_wstrb),
        .m_axi_wlast     (lsu_axi_wlast),
        .m_axi_wvalid    (lsu_axi_wvalid),
        .m_axi_wready    (lsu_axi_wready),
        .m_axi_bid       (lsu_axi_bid),
        .m_axi_bresp     (lsu_axi_bresp),
        .m_axi_bvalid    (lsu_axi_bvalid),
        .m_axi_bready    (lsu_axi_bready),
        .m_axi_araddr    (lsu_axi_araddr),
        .m_axi_arvalid   (lsu_axi_arvalid),
        .m_axi_arready   (lsu_axi_arready),
        .m_axi_arid      (lsu_axi_arid),
        .m_axi_arlen     (lsu_axi_arlen),
        .m_axi_arsize    (lsu_axi_arsize),
        .m_axi_arburst   (lsu_axi_arburst),
        .m_axi_rid       (lsu_axi_rid),
        .m_axi_rdata     (lsu_axi_rdata),
        .m_axi_rresp     (lsu_axi_rresp),
        .m_axi_rlast     (lsu_axi_rlast),
        .m_axi_rvalid    (lsu_axi_rvalid),
        .m_axi_rready    (lsu_axi_rready)
    );

    // AXI4_Arbiter (with full burst support)
    AXI4_Arbiter u_arbiter (
        .clk(clk),
        .rst(rst),
        // Master 0: IFU (with burst)
        .m0_awaddr   (ifu_axi_awaddr),
        .m0_awvalid  (ifu_axi_awvalid),
        .m0_awready  (ifu_axi_awready),
        .m0_awid     (ifu_axi_awid),
        .m0_awlen    (ifu_axi_awlen),
        .m0_awsize   (ifu_axi_awsize),
        .m0_awburst  (ifu_axi_awburst),
        .m0_wdata    (ifu_axi_wdata),
        .m0_wstrb    (ifu_axi_wstrb),
        .m0_wlast    (ifu_axi_wlast),
        .m0_wvalid   (ifu_axi_wvalid),
        .m0_wready   (ifu_axi_wready),
        .m0_bid      (ifu_axi_bid),
        .m0_bresp    (ifu_axi_bresp),
        .m0_bvalid   (ifu_axi_bvalid),
        .m0_bready   (ifu_axi_bready),
        .m0_araddr   (ifu_axi_araddr),
        .m0_arvalid  (ifu_axi_arvalid),
        .m0_arready  (ifu_axi_arready),
        .m0_arid     (ifu_axi_arid),
        .m0_arlen    (ifu_axi_arlen),
        .m0_arsize   (ifu_axi_arsize),
        .m0_arburst  (ifu_axi_arburst),
        .m0_rid      (ifu_axi_rid),
        .m0_rdata    (ifu_axi_rdata),
        .m0_rresp    (ifu_axi_rresp),
        .m0_rlast    (ifu_axi_rlast),
        .m0_rvalid   (ifu_axi_rvalid),
        .m0_rready   (ifu_axi_rready),
        // Master 1: LSU (single-beat)
        .m1_awaddr   (lsu_axi_awaddr),
        .m1_awvalid  (lsu_axi_awvalid),
        .m1_awready  (lsu_axi_awready),
        .m1_awid     (lsu_axi_awid),
        .m1_awlen    (lsu_axi_awlen),
        .m1_awsize   (lsu_axi_awsize),
        .m1_awburst  (lsu_axi_awburst),
        .m1_wdata    (lsu_axi_wdata),
        .m1_wstrb    (lsu_axi_wstrb),
        .m1_wlast    (lsu_axi_wlast),
        .m1_wvalid   (lsu_axi_wvalid),
        .m1_wready   (lsu_axi_wready),
        .m1_bid      (lsu_axi_bid),
        .m1_bresp    (lsu_axi_bresp),
        .m1_bvalid   (lsu_axi_bvalid),
        .m1_bready   (lsu_axi_bready),
        .m1_araddr   (lsu_axi_araddr),
        .m1_arvalid  (lsu_axi_arvalid),
        .m1_arready  (lsu_axi_arready),
        .m1_arid     (lsu_axi_arid),
        .m1_arlen    (lsu_axi_arlen),
        .m1_arsize   (lsu_axi_arsize),
        .m1_arburst  (lsu_axi_arburst),
        .m1_rid      (lsu_axi_rid),
        .m1_rdata    (lsu_axi_rdata),
        .m1_rresp    (lsu_axi_rresp),
        .m1_rlast    (lsu_axi_rlast),
        .m1_rvalid   (lsu_axi_rvalid),
        .m1_rready   (lsu_axi_rready),
        // Slave: Direct to io_master (ysyxSoC)
        .s_awaddr    (io_master_awaddr),
        .s_awvalid   (io_master_awvalid),
        .s_awready   (io_master_awready),
        .s_awid      (io_master_awid),
        .s_awlen     (io_master_awlen),
        .s_awsize    (io_master_awsize),
        .s_awburst   (io_master_awburst),
        .s_wdata     (io_master_wdata),
        .s_wstrb     (io_master_wstrb),
        .s_wlast     (io_master_wlast),
        .s_wvalid    (io_master_wvalid),
        .s_wready    (io_master_wready),
        .s_bid       (io_master_bid),
        .s_bresp     (io_master_bresp),
        .s_bvalid    (io_master_bvalid),
        .s_bready    (io_master_bready),
        .s_araddr    (io_master_araddr),
        .s_arvalid   (io_master_arvalid),
        .s_arready   (io_master_arready),
        .s_arid      (io_master_arid),
        .s_arlen     (io_master_arlen),
        .s_arsize    (io_master_arsize),
        .s_arburst   (io_master_arburst),
        .s_rid       (io_master_rid),
        .s_rdata     (io_master_rdata),
        .s_rresp     (io_master_rresp),
        .s_rlast     (io_master_rlast),
        .s_rvalid    (io_master_rvalid),
        .s_rready    (io_master_rready)
    );

    // Additional fixed AXI4 signals
    assign io_master_awlock  = 1'b0;
    assign io_master_awcache = 4'b0;
    assign io_master_awprot  = 3'b0;
    assign io_master_arlock  = 1'b0;
    assign io_master_arcache = 4'b0;
    assign io_master_arprot  = 3'b0;

    // ------------------------------------------------------
    // Control Logic (PC, State Machine)
    // ------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'h3000_0000;  // Flash XIP Entry Point (0x30000000)
            rdop_en_reg <= 1'b0;
            ex_end_prev <= 1'b0;
            end_flag_reg <= 1'b0;
            rdop_en_prev <= 1'b0;
            update_pc <= 1'b0;
            exit_code_reg <= 32'h0;
            first_fetch_pending <= 1'b1;
            ifu_req <= 1'b0;
            op_en_ifu <= 1'b0;
            op_ifu <= 32'h0;
        end else begin
            ex_end_prev <= ex_end;
            rdop_en_prev <= rdop_en_reg;
            
            if (ex_end != ex_end_prev) begin
                rdop_en_reg <= 1'b1;
            end else begin
                rdop_en_reg <= 1'b0;
            end
            
            if (rdop_en_reg && !rdop_en_prev) begin
                update_pc <= 1'b1;
            end else if (update_pc) begin
                pc <= next_pc;
                update_pc <= 1'b0;
            end
            
            if (first_fetch_pending) begin
                ifu_req <= 1'b1;
                first_fetch_pending <= 1'b0;
            end else if (update_pc) begin
                ifu_req <= 1'b1;
            end else begin
                ifu_req <= 1'b0;
            end

            op_en_ifu <= 1'b0;
            if (ifu_rvalid) begin
                op_ifu <= ifu_rdata;
                op_en_ifu <= 1'b1;
            end

            
            end_flag_reg <= ebreak_detected;
            if (ebreak_detected) begin
                exit_code_reg <= exit_value;
`ifdef SIMULATION
                // ========== Performance Counter Report ==========
                $display("");
                $display("========== NPC Performance Counter Report ==========");
                $display("");
                
                // EXU Statistics
                $display("[EXU Statistics]");
                $display("  Total Cycles:      %0d", EXU.perf_mcycle);
                $display("  Retired Instrs:    %0d", EXU.perf_minstret);
                $display("  IPC:               %0d.%02d", 
                    (EXU.perf_minstret * 100) / EXU.perf_mcycle / 100,
                    (EXU.perf_minstret * 100) / EXU.perf_mcycle % 100);
                $display("  CPI:               %0d.%02d",
                    (EXU.perf_mcycle * 100) / EXU.perf_minstret / 100,
                    (EXU.perf_mcycle * 100) / EXU.perf_minstret % 100);
                $display("");
                
                // EXU State Cycle Distribution
                $display("[EXU State Cycle Distribution]");
                $display("  IDLE Cycles:       %0d (%0d%%)", EXU.perf_exu_idle_cycles,
                    (EXU.perf_exu_idle_cycles * 100) / EXU.perf_mcycle);
                $display("  EXEC Cycles:       %0d (%0d%%)", EXU.perf_exu_exec_cycles,
                    (EXU.perf_exu_exec_cycles * 100) / EXU.perf_mcycle);
                $display("  WAIT_LSU Cycles:   %0d (%0d%%)", EXU.perf_exu_wait_lsu_cycles,
                    (EXU.perf_exu_wait_lsu_cycles * 100) / EXU.perf_mcycle);
                $display("");
                
                // Instruction Type Statistics
                $display("[Instruction Type Statistics]");
                $display("  ALU R-type:        %0d (%0d%%)", EXU.perf_alu_r_cnt,
                    (EXU.perf_alu_r_cnt * 100) / EXU.perf_minstret);
                $display("  ALU I-type:        %0d (%0d%%)", EXU.perf_alu_i_cnt,
                    (EXU.perf_alu_i_cnt * 100) / EXU.perf_minstret);
                $display("  Load:              %0d (%0d%%)", EXU.perf_load_cnt,
                    (EXU.perf_load_cnt * 100) / EXU.perf_minstret);
                $display("  Store:             %0d (%0d%%)", EXU.perf_store_cnt,
                    (EXU.perf_store_cnt * 100) / EXU.perf_minstret);
                $display("  Branch:            %0d (%0d%%, taken: %0d)", EXU.perf_branch_cnt,
                    (EXU.perf_branch_cnt * 100) / EXU.perf_minstret, EXU.perf_branch_taken_cnt);
                $display("  JAL:               %0d (%0d%%)", EXU.perf_jal_cnt,
                    (EXU.perf_jal_cnt * 100) / EXU.perf_minstret);
                $display("  JALR:              %0d (%0d%%)", EXU.perf_jalr_cnt,
                    (EXU.perf_jalr_cnt * 100) / EXU.perf_minstret);
                $display("  LUI:               %0d (%0d%%)", EXU.perf_lui_cnt,
                    (EXU.perf_lui_cnt * 100) / EXU.perf_minstret);
                $display("  AUIPC:             %0d (%0d%%)", EXU.perf_auipc_cnt,
                    (EXU.perf_auipc_cnt * 100) / EXU.perf_minstret);
                $display("  CSR:               %0d (%0d%%)", EXU.perf_csr_cnt,
                    (EXU.perf_csr_cnt * 100) / EXU.perf_minstret);
                $display("  SYSTEM:            %0d (%0d%%)", EXU.perf_system_cnt,
                    (EXU.perf_system_cnt * 100) / EXU.perf_minstret);
                $display("  FENCE:             %0d (%0d%%)", EXU.perf_fence_cnt,
                    (EXU.perf_fence_cnt * 100) / EXU.perf_minstret);
                $display("");
                
                // Instruction Category Summary
                $display("[Instruction Category Summary]");
                $display("  Compute (ALU R+I): %0d (%0d%%)", 
                    EXU.perf_alu_r_cnt + EXU.perf_alu_i_cnt,
                    ((EXU.perf_alu_r_cnt + EXU.perf_alu_i_cnt) * 100) / EXU.perf_minstret);
                $display("  Memory (Load+Store): %0d (%0d%%)", 
                    EXU.perf_load_cnt + EXU.perf_store_cnt,
                    ((EXU.perf_load_cnt + EXU.perf_store_cnt) * 100) / EXU.perf_minstret);
                $display("  Control (Br+J+JAL+JALR): %0d (%0d%%)", 
                    EXU.perf_branch_cnt + EXU.perf_jal_cnt + EXU.perf_jalr_cnt,
                    ((EXU.perf_branch_cnt + EXU.perf_jal_cnt + EXU.perf_jalr_cnt) * 100) / EXU.perf_minstret);
                $display("");
                
`ifdef ENABLE_ICACHE
                // I-Cache Statistics
                $display("[I-Cache Statistics]");
                $display("  Hit Count:         %0d", u_icache.perf_icache_hit_cnt);
                $display("  Miss Count:        %0d", u_icache.perf_icache_miss_cnt);
                $display("  Total Accesses:    %0d", u_icache.perf_icache_access_cnt);
                if ((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) > 0) begin
                    $display("  Hit Rate:          %0d.%02d%%",
                        (u_icache.perf_icache_hit_cnt * 100) / (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt),
                        (u_icache.perf_icache_hit_cnt * 10000 / (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt)) % 100);
                end
                $display("  Total Cycles:      %0d", u_icache.perf_icache_total_cycles);
                $display("  Refill Cycles:     %0d", u_icache.perf_icache_refill_cycles);
                if (u_icache.perf_icache_miss_cnt > 0) begin
                    $display("  Avg Refill Latency:%0d.%02d cycles",
                        u_icache.perf_icache_refill_cycles / u_icache.perf_icache_miss_cnt,
                        (u_icache.perf_icache_refill_cycles * 100 / u_icache.perf_icache_miss_cnt) % 100);
                end
                // AMAT Calculation
                if (u_icache.perf_icache_access_cnt > 0) begin
                    $display("  AMAT:              %0d.%02d cycles",
                        u_icache.perf_icache_total_cycles / u_icache.perf_icache_access_cnt,
                        (u_icache.perf_icache_total_cycles * 100 / u_icache.perf_icache_access_cnt) % 100);
                end
                $display("");
`endif

`ifdef ENABLE_DCACHE
                // D-Cache Statistics
                $display("[D-Cache Statistics]");
                $display("  Read Hit Count:    %0d", u_dcache.perf_dcache_read_hit_cnt);
                $display("  Read Miss Count:   %0d", u_dcache.perf_dcache_read_miss_cnt);
                $display("  Write Hit Count:   %0d", u_dcache.perf_dcache_write_hit_cnt);
                $display("  Write Miss Count:  %0d", u_dcache.perf_dcache_write_miss_cnt);
                $display("  Total Accesses:    %0d", u_dcache.perf_dcache_access_cnt);
                if ((u_dcache.perf_dcache_read_hit_cnt + u_dcache.perf_dcache_read_miss_cnt) > 0) begin
                    $display("  Read Hit Rate:     %0d.%02d%%",
                        (u_dcache.perf_dcache_read_hit_cnt * 100) / (u_dcache.perf_dcache_read_hit_cnt + u_dcache.perf_dcache_read_miss_cnt),
                        (u_dcache.perf_dcache_read_hit_cnt * 10000 / (u_dcache.perf_dcache_read_hit_cnt + u_dcache.perf_dcache_read_miss_cnt)) % 100);
                end
                $display("  Total Cycles:      %0d", u_dcache.perf_dcache_total_cycles);
                $display("  Refill Cycles:     %0d", u_dcache.perf_dcache_refill_cycles);
                $display("  Write Cycles:      %0d", u_dcache.perf_dcache_write_cycles);
                if (u_dcache.perf_dcache_read_miss_cnt > 0) begin
                    $display("  Avg Refill Latency:%0d.%02d cycles",
                        u_dcache.perf_dcache_refill_cycles / u_dcache.perf_dcache_read_miss_cnt,
                        (u_dcache.perf_dcache_refill_cycles * 100 / u_dcache.perf_dcache_read_miss_cnt) % 100);
                end
                // AMAT Calculation
                if (u_dcache.perf_dcache_access_cnt > 0) begin
                    $display("  AMAT:              %0d.%02d cycles",
                        u_dcache.perf_dcache_total_cycles / u_dcache.perf_dcache_access_cnt,
                        (u_dcache.perf_dcache_total_cycles * 100 / u_dcache.perf_dcache_access_cnt) % 100);
                end
                $display("");
`endif
                
                // IFU Statistics
                $display("[IFU/Memory Statistics]");
                $display("  Mem Fetch Count:   %0d", u_ifu.perf_ifu_fetch_cnt);
                $display("  Request Cycles:    %0d", u_ifu.perf_ifu_req_cycles);
                $display("  Wait Cycles:       %0d", u_ifu.perf_ifu_wait_cycles);
                $display("  Arb Stall Cycles:  %0d", u_ifu.perf_ifu_stall_arb_cycles);
                if (u_ifu.perf_ifu_fetch_cnt > 0) begin
                    $display("  Avg Mem Latency:   %0d.%02d cycles",
                        u_ifu.perf_ifu_wait_cycles / u_ifu.perf_ifu_fetch_cnt,
                        (u_ifu.perf_ifu_wait_cycles * 100 / u_ifu.perf_ifu_fetch_cnt) % 100);
                end
                $display("");
                
                // LSU Statistics
                $display("[LSU Statistics]");
                $display("  Load Count:        %0d", u_lsu.perf_lsu_load_cnt);
                $display("  Store Count:       %0d", u_lsu.perf_lsu_store_cnt);
                $display("  Load Total Cycles: %0d", u_lsu.perf_lsu_load_cycles);
                $display("  Store Total Cycles:%0d", u_lsu.perf_lsu_store_cycles);
                $display("  Arb Stall Cycles:  %0d", u_lsu.perf_lsu_stall_arb_cycles);
                if (u_lsu.perf_lsu_load_cnt > 0) begin
                    $display("  Avg Load Latency:  %0d.%02d cycles",
                        u_lsu.perf_lsu_load_cycles / u_lsu.perf_lsu_load_cnt,
                        (u_lsu.perf_lsu_load_cycles * 100 / u_lsu.perf_lsu_load_cnt) % 100);
                end
                if (u_lsu.perf_lsu_store_cnt > 0) begin
                    $display("  Avg Store Latency: %0d.%02d cycles",
                        u_lsu.perf_lsu_store_cycles / u_lsu.perf_lsu_store_cnt,
                        (u_lsu.perf_lsu_store_cycles * 100 / u_lsu.perf_lsu_store_cnt) % 100);
                end
                $display("");
                
                // Consistency Check
                $display("[Consistency Check]");
`ifdef ENABLE_ICACHE
                $display("  ICache Accesses ~= Retired: %s (diff=%0d)", 
                    (((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) == EXU.perf_minstret) || 
                     ((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) == EXU.perf_minstret + 1)) ? "PASS" : "FAIL",
                    (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) - EXU.perf_minstret);
                $display("  Mem Fetches = Miss: %s",
                    (u_ifu.perf_ifu_fetch_cnt == u_icache.perf_icache_miss_cnt) ? "PASS" : "FAIL");
`else
                $display("  IFU Fetch ~= Retired Instrs: %s (diff=%0d)", 
                    ((u_ifu.perf_ifu_fetch_cnt == EXU.perf_minstret) || 
                     (u_ifu.perf_ifu_fetch_cnt == EXU.perf_minstret + 1)) ? "PASS" : "FAIL",
                    u_ifu.perf_ifu_fetch_cnt - EXU.perf_minstret);
`endif
                $display("  Sum of Instr Types = Retired: %s",
                    ((EXU.perf_alu_r_cnt + EXU.perf_alu_i_cnt + EXU.perf_load_cnt + 
                      EXU.perf_store_cnt + EXU.perf_branch_cnt + EXU.perf_jal_cnt + 
                      EXU.perf_jalr_cnt + EXU.perf_lui_cnt + EXU.perf_auipc_cnt + 
                      EXU.perf_csr_cnt + EXU.perf_system_cnt + EXU.perf_fence_cnt) == EXU.perf_minstret) 
                    ? "PASS" : "FAIL");
                $display("  EXU Load = LSU Load: %s",
                    (EXU.perf_load_cnt == u_lsu.perf_lsu_load_cnt) ? "PASS" : "FAIL");
                $display("  EXU Store = LSU Store: %s",
                    (EXU.perf_store_cnt == u_lsu.perf_lsu_store_cnt) ? "PASS" : "FAIL");
                $display("");
                $display("====================================================");
                $display("");
                
                // Export CSV Performance Data
                export_cache_stats_csv();
`endif
`ifdef SIMULATION
                npc_trap(exit_value);
`endif
            end
        end
    end

`ifdef SIMULATION
    // ========== CSV Performance Data Export ==========
    task export_cache_stats_csv;
        integer fd;
        begin
            fd = $fopen("cache_stats.csv", "w");
            if (fd != 0) begin
                $fwrite(fd, "metric,value\n");
                // EXU Basic Statistics
                $fwrite(fd, "total_cycles,%0d\n", EXU.perf_mcycle);
                $fwrite(fd, "retired_instrs,%0d\n", EXU.perf_minstret);
`ifdef ENABLE_ICACHE
                // I-Cache Statistics
                $fwrite(fd, "icache_access_cnt,%0d\n", u_icache.perf_icache_access_cnt);
                $fwrite(fd, "icache_hit_cnt,%0d\n", u_icache.perf_icache_hit_cnt);
                $fwrite(fd, "icache_miss_cnt,%0d\n", u_icache.perf_icache_miss_cnt);
                $fwrite(fd, "icache_total_cycles,%0d\n", u_icache.perf_icache_total_cycles);
                $fwrite(fd, "icache_refill_cycles,%0d\n", u_icache.perf_icache_refill_cycles);
`endif
`ifdef ENABLE_DCACHE
                // D-Cache Statistics
                $fwrite(fd, "dcache_access_cnt,%0d\n", u_dcache.perf_dcache_access_cnt);
                $fwrite(fd, "dcache_read_hit_cnt,%0d\n", u_dcache.perf_dcache_read_hit_cnt);
                $fwrite(fd, "dcache_read_miss_cnt,%0d\n", u_dcache.perf_dcache_read_miss_cnt);
                $fwrite(fd, "dcache_write_hit_cnt,%0d\n", u_dcache.perf_dcache_write_hit_cnt);
                $fwrite(fd, "dcache_write_miss_cnt,%0d\n", u_dcache.perf_dcache_write_miss_cnt);
                $fwrite(fd, "dcache_total_cycles,%0d\n", u_dcache.perf_dcache_total_cycles);
                $fwrite(fd, "dcache_refill_cycles,%0d\n", u_dcache.perf_dcache_refill_cycles);
                $fwrite(fd, "dcache_write_cycles,%0d\n", u_dcache.perf_dcache_write_cycles);
`endif
                // IFU Statistics
                $fwrite(fd, "ifu_fetch_cnt,%0d\n", u_ifu.perf_ifu_fetch_cnt);
                $fwrite(fd, "ifu_wait_cycles,%0d\n", u_ifu.perf_ifu_wait_cycles);
                // LSU Statistics
                $fwrite(fd, "lsu_load_cnt,%0d\n", u_lsu.perf_lsu_load_cnt);
                $fwrite(fd, "lsu_store_cnt,%0d\n", u_lsu.perf_lsu_store_cnt);
                $fwrite(fd, "lsu_load_cycles,%0d\n", u_lsu.perf_lsu_load_cycles);
                $fwrite(fd, "lsu_store_cycles,%0d\n", u_lsu.perf_lsu_store_cycles);
                $fclose(fd);
                $display("[INFO] Performance stats exported to cache_stats.csv");
            end
        end
    endtask
`endif

endmodule

`endif // ENABLE_PIPELINE
