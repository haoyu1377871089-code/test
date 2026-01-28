// ysyx_pipeline_top: 流水线处理器顶层模块 (替代 ysyx_00000000.v)
//
// 使用方法: 在 Makefile.soc 中添加 +define+ENABLE_PIPELINE

`ifdef ENABLE_PIPELINE

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

    // Slave Interface (Unused)
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

    wire clk = clock;
    wire rst = reset;

    // Pipeline core signals
    wire        ifu_req;
    wire [31:0] ifu_addr;
    wire        ifu_flush;
    wire        ifu_rvalid;
    wire [31:0] ifu_rdata;
    
    wire        lsu_req;
    wire        lsu_wen;
    wire [31:0] lsu_addr;
    wire [31:0] lsu_wdata;
    wire [3:0]  lsu_wmask;
    wire        lsu_rvalid;
    wire [31:0] lsu_rdata;
    
    wire        ebreak_flag;
    wire [31:0] exit_code;
    
`ifdef SIMULATION
    wire [63:0] perf_minstret;
    wire [63:0] perf_mcycle;
`endif

    // I-Cache signals
    wire        icache_rvalid;
    wire [31:0] icache_rdata;
    wire        icache_mem_req;
    wire [31:0] icache_mem_addr;
    wire [7:0]  icache_mem_len;
    wire        icache_mem_rvalid;
    wire [31:0] icache_mem_rdata;
    wire        icache_mem_rlast;

    // IFU AXI4 Signals
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

    // Pipeline Core
    NPC_pipeline u_npc (
        .clk         (clk),
        .rst         (rst),
        .ifu_req     (ifu_req),
        .ifu_addr    (ifu_addr),
        .ifu_flush   (ifu_flush),
        .ifu_rvalid  (ifu_rvalid),
        .ifu_rdata   (ifu_rdata),
        .lsu_req     (lsu_req),
        .lsu_wen     (lsu_wen),
        .lsu_addr    (lsu_addr),
        .lsu_wdata   (lsu_wdata),
        .lsu_wmask   (lsu_wmask),
        .lsu_rvalid  (lsu_rvalid),
        .lsu_rdata   (lsu_rdata),
        .ebreak_flag (ebreak_flag),
        .exit_code   (exit_code)
`ifdef SIMULATION
        ,
        .perf_minstret(perf_minstret),
        .perf_mcycle (perf_mcycle)
`endif
    );

    // I-Cache
`ifdef ENABLE_ICACHE
    ICache #(
        .CACHE_SIZE    (4096),
        .LINE_SIZE     (16),
        .NUM_WAYS      (2),
        .ADDR_WIDTH    (32)
    ) u_icache (
        .clk         (clk),
        .rst         (rst),
        .cpu_req     (ifu_req),
        .cpu_addr    (ifu_addr),
        .cpu_flush   (ifu_flush),
        .cpu_rvalid  (icache_rvalid),
        .cpu_rdata   (icache_rdata),
        .mem_req     (icache_mem_req),
        .mem_addr    (icache_mem_addr),
        .mem_len     (icache_mem_len),
        .mem_rvalid  (icache_mem_rvalid),
        .mem_rdata   (icache_mem_rdata),
        .mem_rlast   (icache_mem_rlast)
    );

    assign ifu_rvalid = icache_rvalid;
    assign ifu_rdata = icache_rdata;

    IFU_AXI4 u_ifu (
        .clk             (clk),
        .rst             (rst),
        .icache_req      (icache_mem_req),
        .icache_addr     (icache_mem_addr),
        .icache_len      (icache_mem_len),
        .icache_flush    (ifu_flush),
        .icache_rvalid   (icache_mem_rvalid),
        .icache_rdata    (icache_mem_rdata),
        .icache_rlast    (icache_mem_rlast),
`else
    assign icache_rvalid = 1'b0;
    assign icache_rdata = 32'h0;
    assign icache_mem_req = 1'b0;
    assign icache_mem_addr = 32'h0;
    assign icache_mem_len = 8'h0;

    IFU_AXI4 u_ifu (
        .clk             (clk),
        .rst             (rst),
        .icache_req      (ifu_req),
        .icache_addr     (ifu_addr),
        .icache_len      (8'h0),
        .icache_flush    (ifu_flush),
        .icache_rvalid   (ifu_rvalid),
        .icache_rdata    (ifu_rdata),
        .icache_rlast    (),
`endif
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

    // LSU_AXI4 (直接连接，不使用 D-Cache)
    LSU_AXI4 u_lsu (
        .clk             (clk),
        .rst             (rst),
        .req             (lsu_req),
        .wen             (lsu_wen),
        .addr            (lsu_addr),
        .wdata           (lsu_wdata),
        .wmask           (lsu_wmask),
        .burst_len       (8'h0),
        .rvalid_out      (lsu_rvalid),
        .rdata_out       (lsu_rdata),
        .rlast_out       (),
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

    // AXI4 Arbiter
    AXI4_Arbiter u_arbiter (
        .clk(clk),
        .rst(rst),
        // Master 0: IFU
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
        // Master 1: LSU
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
        // Slave
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

    // Fixed AXI4 signals
    assign io_master_awlock  = 1'b0;
    assign io_master_awcache = 4'b0;
    assign io_master_awprot  = 3'b0;
    assign io_master_arlock  = 1'b0;
    assign io_master_arcache = 4'b0;
    assign io_master_arprot  = 3'b0;

    // ebreak handling
    always @(posedge clk) begin
        if (ebreak_flag) begin
`ifdef SIMULATION
            $display("");
            $display("========== Pipeline NPC Performance Report ==========");
            $display("  Total Cycles:   %0d", perf_mcycle);
            $display("  Retired Instrs: %0d", perf_minstret);
            if (perf_minstret > 0) begin
                $display("  CPI:            %0d.%02d", 
                    perf_mcycle / perf_minstret,
                    (perf_mcycle * 100 / perf_minstret) % 100);
            end
            $display("=====================================================");
            $display("");
            npc_trap(exit_code);
`endif
        end
    end

endmodule

`endif // ENABLE_PIPELINE
