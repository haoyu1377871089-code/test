// ysyx_dstage_adapter: 将流水线 NPC 适配到 D-stage ysyxSoCFull 接口
//
// D-stage 使用简化的 IFU/LSU 请求-响应接口，而不是标准 AXI4 接口
// 此模块将流水线 NPC 的内部信号转换为 D-stage 期望的接口

`ifdef ENABLE_PIPELINE

module ysyx_00000000 (
    input         clock,
    input         reset,
    
    // IFU 接口 (简化的请求-响应)
    output [31:0] io_ifu_addr,
    output        io_ifu_reqValid,
    input  [31:0] io_ifu_rdata,
    input         io_ifu_respValid,
    
    // LSU 接口 (简化的请求-响应)
    output [31:0] io_lsu_addr,
    output        io_lsu_reqValid,
    input  [31:0] io_lsu_rdata,
    input         io_lsu_respValid,
    output [1:0]  io_lsu_size,
    output        io_lsu_wen,
    output [31:0] io_lsu_wdata,
    output [3:0]  io_lsu_wmask
);

`ifdef SIMULATION
    import "DPI-C" function void npc_trap(input int exit_code);
`endif

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

    // I-Cache signals (bypass when not using ICache)
`ifdef ENABLE_ICACHE
    wire        icache_rvalid;
    wire [31:0] icache_rdata;
    wire        icache_mem_req;
    wire [31:0] icache_mem_addr;
    wire [7:0]  icache_mem_len;
    wire        icache_mem_rvalid;
    wire [31:0] icache_mem_rdata;
    wire        icache_mem_rlast;

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
    assign ifu_rdata  = icache_rdata;

    // IFU 请求转换 (ICache -> D-stage 接口)
    // ICache 会发出 burst 请求 (16B = 4 words)，D-stage 接口只支持单拍
    // 需要将一个 burst 请求拆分为 4 个单拍请求
    //
    // 时序：
    //   - icache_mem_req=1 触发开始，立即输出第一个请求
    //   - 等待 respValid，收到后进入下一个 beat
    //   - 4 个 beat 完成后结束
    
    reg [1:0] icache_beat_cnt;
    reg       icache_active;      // 正在进行 burst 传输
    
    // 地址计算
    assign io_ifu_addr = icache_mem_addr + {icache_beat_cnt, 2'b00};
    
    // 请求信号：在 burst 期间持续有效
    // 立即响应 icache_mem_req，或在 active 期间持续请求
    assign io_ifu_reqValid = icache_mem_req || icache_active;
    
    // 数据返回给 I-Cache
    assign icache_mem_rdata  = io_ifu_rdata;
    assign icache_mem_rvalid = io_ifu_respValid && (icache_mem_req || icache_active);
    assign icache_mem_rlast  = io_ifu_respValid && icache_active && (icache_beat_cnt == 2'd3);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            icache_beat_cnt <= 2'd0;
            icache_active <= 1'b0;
        end else begin
            if (icache_mem_req && !icache_active) begin
                // I-Cache 发出新请求，开始 burst 传输
                icache_active <= 1'b1;
                icache_beat_cnt <= 2'd0;
            end else if (icache_active && io_ifu_respValid) begin
                // 收到一个响应
                if (icache_beat_cnt == 2'd3) begin
                    // 最后一个 beat 完成
                    icache_active <= 1'b0;
                    icache_beat_cnt <= 2'd0;
                end else begin
                    // 进入下一个 beat
                    icache_beat_cnt <= icache_beat_cnt + 1;
                end
            end
        end
    end
`else
    // 无 ICache，直接连接
    assign io_ifu_addr     = ifu_addr;
    assign io_ifu_reqValid = ifu_req;
    assign ifu_rdata       = io_ifu_rdata;
    assign ifu_rvalid      = io_ifu_respValid;
`endif

    // LSU 请求转换 (直接映射)
    assign io_lsu_addr     = lsu_addr;
    assign io_lsu_reqValid = lsu_req;
    assign io_lsu_size     = 2'b10;  // 默认字访问 (4 bytes)
    assign io_lsu_wen      = lsu_wen;
    assign io_lsu_wdata    = lsu_wdata;
    assign io_lsu_wmask    = lsu_wmask;
    assign lsu_rdata       = io_lsu_rdata;
    assign lsu_rvalid      = io_lsu_respValid;

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
