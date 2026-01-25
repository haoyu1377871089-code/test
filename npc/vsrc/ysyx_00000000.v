`include "axi4_lite_interface.vh"

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

    // LSU Signals
    wire lsu_req;
    wire lsu_wen;
    wire [31:0] lsu_addr;
    wire [31:0] lsu_wdata;
    wire [3:0]  lsu_wmask;
    wire lsu_rvalid;
    wire [31:0] lsu_rdata;

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
    wire        icache_mem_rvalid;
    wire [31:0] icache_mem_rdata;

    // AXI4-Lite Signals (IFU)
    wire [31:0] ifu_awaddr;
    wire        ifu_awvalid;
    wire        ifu_awready;
    wire [31:0] ifu_wdata;
    wire [3:0]  ifu_wstrb;
    wire        ifu_wvalid;
    wire        ifu_wready;
    wire [1:0]  ifu_bresp;
    wire        ifu_bvalid;
    wire        ifu_bready;
    wire [31:0] ifu_araddr;
    wire        ifu_arvalid;
    wire        ifu_arready;
    wire [31:0] ifu_rdata_axi;
    wire [1:0]  ifu_rresp;
    wire        ifu_rvalid_axi;
    wire        ifu_rready;

    // AXI4-Lite Signals (LSU)
    wire [31:0] lsu_awaddr;
    wire        lsu_awvalid;
    wire        lsu_awready;
    wire [31:0] lsu_wdata_axi;
    wire [3:0]  lsu_wstrb;
    wire        lsu_wvalid;
    wire        lsu_wready;
    wire [1:0]  lsu_bresp;
    wire        lsu_bvalid;
    wire        lsu_bready;
    wire [31:0] lsu_araddr;
    wire        lsu_arvalid;
    wire        lsu_arready;
    wire [31:0] lsu_rdata_axi;
    wire [1:0]  lsu_rresp;
    wire        lsu_rvalid_axi;
    wire        lsu_rready;

    // AXI4-Lite Signals (Arbiter Output)
    wire [31:0] arb_awaddr;
    wire        arb_awvalid;
    wire        arb_awready;
    wire [31:0] arb_wdata;
    wire [3:0]  arb_wstrb;
    wire        arb_wvalid;
    wire        arb_wready;
    wire [1:0]  arb_bresp;
    wire        arb_bvalid;
    wire        arb_bready;
    wire [31:0] arb_araddr;
    wire        arb_arvalid;
    wire        arb_arready;
    wire [31:0] arb_rdata;
    wire [1:0]  arb_rresp;
    wire        arb_rvalid;
    wire        arb_rready;

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
        // .regs (exu_regs)
    );

    // I-Cache (temporarily bypassed for debugging)
`ifdef ENABLE_ICACHE
    ICache u_icache (
        .clk         (clk),
        .rst         (rst),
        // Upstream interface (to CPU)
        .cpu_req     (ifu_req),
        .cpu_addr    (ifu_addr),
        .cpu_rvalid  (icache_rvalid),
        .cpu_rdata   (icache_rdata),
        // Downstream interface (to IFU_AXI)
        .mem_req     (icache_mem_req),
        .mem_addr    (icache_mem_addr),
        .mem_rvalid  (icache_mem_rvalid),
        .mem_rdata   (icache_mem_rdata)
    );

    // Connect ICache outputs to IFU signals (for control logic)
    assign ifu_rvalid = icache_rvalid;
    assign ifu_rdata = icache_rdata;

    // IFU_AXI (now driven by ICache for memory access)
    IFU_AXI u_ifu (
        .clk         (clk),
        .rst         (rst),
        .req         (icache_mem_req),
        .addr        (icache_mem_addr),
        .rvalid_out  (icache_mem_rvalid),
        .rdata_out   (icache_mem_rdata),
`else
    // Bypass I-Cache: connect directly to IFU_AXI
    assign icache_rvalid = 1'b0;  // Unused
    assign icache_rdata = 32'h0;  // Unused
    assign icache_mem_req = 1'b0;  // Unused
    assign icache_mem_addr = 32'h0;  // Unused

    // IFU_AXI (directly connected to control logic)
    IFU_AXI u_ifu (
        .clk         (clk),
        .rst         (rst),
        .req         (ifu_req),
        .addr        (ifu_addr),
        .rvalid_out  (ifu_rvalid),
        .rdata_out   (ifu_rdata),
`endif
        .awaddr      (ifu_awaddr),
        .awvalid     (ifu_awvalid),
        .awready     (ifu_awready),
        .wdata       (ifu_wdata),
        .wstrb       (ifu_wstrb),
        .wvalid      (ifu_wvalid),
        .wready      (ifu_wready),
        .bresp       (ifu_bresp),
        .bvalid      (ifu_bvalid),
        .bready      (ifu_bready),
        .araddr      (ifu_araddr),
        .arvalid     (ifu_arvalid),
        .arready     (ifu_arready),
        .rdata       (ifu_rdata_axi),
        .rresp       (ifu_rresp),
        .rvalid      (ifu_rvalid_axi),
        .rready      (ifu_rready)
    );

    // LSU_AXI
    LSU_AXI u_lsu (
        .clk         (clk),
        .rst         (rst),
        .req         (lsu_req),
        .wen         (lsu_wen),
        .addr        (lsu_addr),
        .wdata       (lsu_wdata),
        .wmask       (lsu_wmask),
        .rvalid_out  (lsu_rvalid),
        .rdata_out   (lsu_rdata),
        .awaddr      (lsu_awaddr),
        .awvalid     (lsu_awvalid),
        .awready     (lsu_awready),
        .wdata_axi   (lsu_wdata_axi),
        .wstrb       (lsu_wstrb),
        .wvalid      (lsu_wvalid),
        .wready      (lsu_wready),
        .bresp       (lsu_bresp),
        .bvalid      (lsu_bvalid),
        .bready      (lsu_bready),
        .araddr      (lsu_araddr),
        .arvalid     (lsu_arvalid),
        .arready     (lsu_arready),
        .rdata       (lsu_rdata_axi),
        .rresp       (lsu_rresp),
        .rvalid      (lsu_rvalid_axi),
        .rready      (lsu_rready)
    );

    // AXI4_Lite_Arbiter
    AXI4_Lite_Arbiter u_arbiter (
        .clk(clk),
        .rst(rst),
        // Master 0: IFU
        .m0_awaddr   (ifu_awaddr),
        .m0_awvalid  (ifu_awvalid),
        .m0_awready  (ifu_awready),
        .m0_wdata    (ifu_wdata),
        .m0_wstrb    (ifu_wstrb),
        .m0_wvalid   (ifu_wvalid),
        .m0_wready   (ifu_wready),
        .m0_bresp    (ifu_bresp),
        .m0_bvalid   (ifu_bvalid),
        .m0_bready   (ifu_bready),
        .m0_araddr   (ifu_araddr),
        .m0_arvalid  (ifu_arvalid),
        .m0_arready  (ifu_arready),
        .m0_rdata    (ifu_rdata_axi),
        .m0_rresp    (ifu_rresp),
        .m0_rvalid   (ifu_rvalid_axi),
        .m0_rready   (ifu_rready),
        // Master 1: LSU
        .m1_awaddr   (lsu_awaddr),
        .m1_awvalid  (lsu_awvalid),
        .m1_awready  (lsu_awready),
        .m1_wdata    (lsu_wdata_axi),
        .m1_wstrb    (lsu_wstrb),
        .m1_wvalid   (lsu_wvalid),
        .m1_wready   (lsu_wready),
        .m1_bresp    (lsu_bresp),
        .m1_bvalid   (lsu_bvalid),
        .m1_bready   (lsu_bready),
        .m1_araddr   (lsu_araddr),
        .m1_arvalid  (lsu_arvalid),
        .m1_arready  (lsu_arready),
        .m1_rdata    (lsu_rdata_axi),
        .m1_rresp    (lsu_rresp),
        .m1_rvalid   (lsu_rvalid_axi),
        .m1_rready   (lsu_rready),
        // Slave: Connected to Bridge
        .s_awaddr    (arb_awaddr),
        .s_awvalid   (arb_awvalid),
        .s_awready   (arb_awready),
        .s_wdata     (arb_wdata),
        .s_wstrb     (arb_wstrb),
        .s_wvalid    (arb_wvalid),
        .s_wready    (arb_wready),
        .s_bresp     (arb_bresp),
        .s_bvalid    (arb_bvalid),
        .s_bready    (arb_bready),
        .s_araddr    (arb_araddr),
        .s_arvalid   (arb_arvalid),
        .s_arready   (arb_arready),
        .s_rdata     (arb_rdata),
        .s_rresp     (arb_rresp),
        .s_rvalid    (arb_rvalid),
        .s_rready    (arb_rready)
    );

    // AXI4_Lite_to_AXI4_Bridge
    AXI4_Lite_to_AXI4_Bridge u_bridge (
        .clk           (clk),
        .rst           (rst),
        // Slave (from Arbiter)
        .s_awaddr      (arb_awaddr),
        .s_awvalid     (arb_awvalid),
        .s_awready     (arb_awready),
        .s_wdata       (arb_wdata),
        .s_wstrb       (arb_wstrb),
        .s_wvalid      (arb_wvalid),
        .s_wready      (arb_wready),
        .s_bresp       (arb_bresp),
        .s_bvalid      (arb_bvalid),
        .s_bready      (arb_bready),
        .s_araddr      (arb_araddr),
        .s_arvalid     (arb_arvalid),
        .s_arready     (arb_arready),
        .s_rdata       (arb_rdata),
        .s_rresp       (arb_rresp),
        .s_rvalid      (arb_rvalid),
        .s_rready      (arb_rready),
        // Master (to ysyxSoC)
        .m_axi_awid    (io_master_awid),
        .m_axi_awaddr  (io_master_awaddr),
        .m_axi_awlen   (io_master_awlen),
        .m_axi_awsize  (io_master_awsize),
        .m_axi_awburst (io_master_awburst),
        .m_axi_awlock  (io_master_awlock),
        .m_axi_awcache (io_master_awcache),
        .m_axi_awprot  (io_master_awprot),
        .m_axi_awvalid (io_master_awvalid),
        .m_axi_awready (io_master_awready),
        .m_axi_wdata   (io_master_wdata),
        .m_axi_wstrb   (io_master_wstrb),
        .m_axi_wlast   (io_master_wlast),
        .m_axi_wvalid  (io_master_wvalid),
        .m_axi_wready  (io_master_wready),
        .m_axi_bid     (io_master_bid),
        .m_axi_bresp   (io_master_bresp),
        .m_axi_bvalid  (io_master_bvalid),
        .m_axi_bready  (io_master_bready),
        .m_axi_arid    (io_master_arid),
        .m_axi_araddr  (io_master_araddr),
        .m_axi_arlen   (io_master_arlen),
        .m_axi_arsize  (io_master_arsize),
        .m_axi_arburst (io_master_arburst),
        .m_axi_arlock  (io_master_arlock),
        .m_axi_arcache (io_master_arcache),
        .m_axi_arprot  (io_master_arprot),
        .m_axi_arvalid (io_master_arvalid),
        .m_axi_arready (io_master_arready),
        .m_axi_rid     (io_master_rid),
        .m_axi_rdata   (io_master_rdata),
        .m_axi_rresp   (io_master_rresp),
        .m_axi_rlast   (io_master_rlast),
        .m_axi_rvalid  (io_master_rvalid),
        .m_axi_rready  (io_master_rready)
    );

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
                // ========== 性能计数器统计输出 ==========
                $display("");
                $display("========== NPC Performance Counter Report ==========");
                $display("");
                
                // EXU 统计
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
                
                // EXU 状态周期分布
                $display("[EXU State Cycle Distribution]");
                $display("  IDLE Cycles:       %0d (%0d%%)", EXU.perf_exu_idle_cycles,
                    (EXU.perf_exu_idle_cycles * 100) / EXU.perf_mcycle);
                $display("  EXEC Cycles:       %0d (%0d%%)", EXU.perf_exu_exec_cycles,
                    (EXU.perf_exu_exec_cycles * 100) / EXU.perf_mcycle);
                $display("  WAIT_LSU Cycles:   %0d (%0d%%)", EXU.perf_exu_wait_lsu_cycles,
                    (EXU.perf_exu_wait_lsu_cycles * 100) / EXU.perf_mcycle);
                $display("");
                
                // 指令类型统计
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
                
                // 指令分类汇总
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
                // I-Cache 统计
                $display("[I-Cache Statistics]");
                $display("  Hit Count:         %0d", u_icache.perf_icache_hit_cnt);
                $display("  Miss Count:        %0d", u_icache.perf_icache_miss_cnt);
                if ((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) > 0) begin
                    $display("  Hit Rate:          %0d.%02d%%",
                        (u_icache.perf_icache_hit_cnt * 100) / (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt),
                        (u_icache.perf_icache_hit_cnt * 10000 / (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt)) % 100);
                end
                $display("  Refill Cycles:     %0d", u_icache.perf_icache_refill_cycles);
                if (u_icache.perf_icache_miss_cnt > 0) begin
                    $display("  Avg Refill Latency:%0d.%02d cycles",
                        u_icache.perf_icache_refill_cycles / u_icache.perf_icache_miss_cnt,
                        (u_icache.perf_icache_refill_cycles * 100 / u_icache.perf_icache_miss_cnt) % 100);
                end
                $display("");
`endif
                
                // IFU 统计
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
                
                // LSU 统计
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
                
                // 一致性检查
                $display("[Consistency Check]");
`ifdef ENABLE_ICACHE
                // I-Cache: Hit + Miss 应该接近 Retired Instrs (允许差1，ebreak时有预取)
                $display("  ICache Accesses ~= Retired: %s (diff=%0d)", 
                    (((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) == EXU.perf_minstret) || 
                     ((u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) == EXU.perf_minstret + 1)) ? "PASS" : "FAIL",
                    (u_icache.perf_icache_hit_cnt + u_icache.perf_icache_miss_cnt) - EXU.perf_minstret);
                // IFU Mem Fetch = I-Cache Miss (1 word per miss)
                $display("  Mem Fetches = Miss: %s",
                    (u_ifu.perf_ifu_fetch_cnt == u_icache.perf_icache_miss_cnt) ? "PASS" : "FAIL");
`else
                // No I-Cache: IFU Fetch 允许比 Retired 多1（ebreak时有预取）
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
`endif
`ifdef SIMULATION
                npc_trap(exit_value);
`endif
            end
        end
    end

endmodule
