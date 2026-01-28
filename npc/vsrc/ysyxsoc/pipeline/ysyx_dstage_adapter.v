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
    // 重要：D-stage MemBridge 使用请求-响应协议
    //   - io_ifu_reqValid 只在需要新响应时为高（单周期脉冲或等待接受）
    //   - 不能在整个 burst 期间持续为高，否则会与 LSU 请求冲突
    //
    // 状态机：
    //   IDLE -> REQ -> WAIT_RESP -> (REQ or IDLE)
    
    localparam IFU_IDLE      = 2'd0;
    localparam IFU_REQ       = 2'd1;
    localparam IFU_WAIT_RESP = 2'd2;
    
    reg [1:0] ifu_state;
    reg [1:0] icache_beat_cnt;
    reg [31:0] icache_saved_addr;  // 保存 burst 起始地址
    
    // 地址计算
    assign io_ifu_addr = icache_saved_addr + {icache_beat_cnt, 2'b00};
    
    // IFU 请求逻辑
    // - IFU 只在没有 LSU 读请求时可以发
    // - IFU 可以与 LSU 写并行
    wire ifu_can_req_idle = (arb_state == ARB_IDLE) && !lsu_is_read;
    wire ifu_can_req_active = (arb_state == ARB_IFU);
    wire ifu_can_req_during_write = (arb_state == ARB_LSU_WRITE);  // LSU 写时 IFU 可以继续
    wire ifu_can_req = ifu_can_req_idle || ifu_can_req_active || ifu_can_req_during_write;
    
    // 请求信号：只在 REQ 状态且仲裁允许时为高
    assign io_ifu_reqValid = (ifu_state == IFU_REQ) && ifu_can_req;
    
    // 数据返回给 I-Cache
    assign icache_mem_rdata  = io_ifu_rdata;
    assign icache_mem_rvalid = io_ifu_respValid && (ifu_state == IFU_WAIT_RESP);
    assign icache_mem_rlast  = icache_mem_rvalid && (icache_beat_cnt == 2'd3);
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ifu_state <= IFU_IDLE;
            icache_beat_cnt <= 2'd0;
            icache_saved_addr <= 32'd0;
        end else begin
            case (ifu_state)
                IFU_IDLE: begin
                    // 开始新的 IFU burst 请求
                    if (icache_mem_req) begin
                        // I-Cache 发出新的 burst 请求
                        ifu_state <= IFU_REQ;
                        icache_beat_cnt <= 2'd0;
                        icache_saved_addr <= icache_mem_addr;
                    end
                end
                
                IFU_REQ: begin
                    // 等待仲裁允许并发送请求
                    if (ifu_can_req) begin
                        // 请求已发送，进入等待响应状态
                        ifu_state <= IFU_WAIT_RESP;
                    end
                    // 否则继续在 REQ 状态等待仲裁
                end
                
                IFU_WAIT_RESP: begin
                    if (io_ifu_respValid) begin
                        // 收到一个响应
                        if (icache_beat_cnt == 2'd3) begin
                            // 最后一个 beat 完成
                            ifu_state <= IFU_IDLE;
                            icache_beat_cnt <= 2'd0;
                        end else begin
                            // 进入下一个 beat
                            icache_beat_cnt <= icache_beat_cnt + 1;
                            ifu_state <= IFU_REQ;
                        end
                    end
                end
                
                default: ifu_state <= IFU_IDLE;
            endcase
        end
    end
`else
    // 无 ICache，直接连接
    assign io_ifu_addr     = ifu_addr;
    assign io_ifu_reqValid = ifu_req;
    assign ifu_rdata       = io_ifu_rdata;
    assign ifu_rvalid      = io_ifu_respValid;
`endif

    // ========== IFU/LSU 仲裁（优化版）==========
    // D-stage MemBridge 的 IFU 和 LSU 请求冲突分析：
    //
    // IFU 只使用 AR 通道（读取指令）
    // LSU 读使用 AR 通道（与 IFU 冲突！）
    // LSU 写使用 AW/W/B 通道（不与 IFU 冲突）
    //
    // 优化策略：
    // - 只有 LSU 读操作需要阻塞 IFU
    // - LSU 写操作可以与 IFU 并行
    //
    // 状态机：
    //   - ARB_IDLE: 空闲
    //   - ARB_IFU: IFU 正在读取
    //   - ARB_LSU_READ: LSU 正在读取（阻塞 IFU）
    //   - ARB_LSU_WRITE: LSU 正在写入（不阻塞 IFU）
    
    localparam ARB_IDLE      = 2'd0;
    localparam ARB_IFU       = 2'd1;
    localparam ARB_LSU_READ  = 2'd2;
    localparam ARB_LSU_WRITE = 2'd3;
    
    reg [1:0] arb_state;
    
    // LSU 请求类型
    wire lsu_is_read  = lsu_req && !lsu_wen;
    wire lsu_is_write = lsu_req && lsu_wen;
    
    // 总线占用状态
    wire ifu_using_bus       = (arb_state == ARB_IFU);
    wire lsu_read_using_bus  = (arb_state == ARB_LSU_READ);
    wire lsu_write_using_bus = (arb_state == ARB_LSU_WRITE);
    wire lsu_using_bus       = lsu_read_using_bus || lsu_write_using_bus;
    
    // IFU 被阻塞条件：LSU 正在读取
    wire ifu_blocked = lsu_read_using_bus || lsu_is_read;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            arb_state <= ARB_IDLE;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    // LSU 读优先级最高（防止 AR 通道冲突）
                    if (lsu_is_read) begin
                        arb_state <= ARB_LSU_READ;
                    end else if (lsu_is_write) begin
                        arb_state <= ARB_LSU_WRITE;
                    end else if (ifu_state == IFU_REQ) begin
                        arb_state <= ARB_IFU;
                    end
                end
                ARB_IFU: begin
                    // IFU 正在使用 AR 通道
                    if (io_ifu_respValid) begin
                        if (icache_beat_cnt == 2'd3) begin
                            // burst 完成
                            arb_state <= ARB_IDLE;
                        end
                    end
                    // 如果有 LSU 读请求，需要在 burst 完成后处理
                end
                ARB_LSU_READ: begin
                    // LSU 正在读取（使用 AR 通道）
                    if (io_lsu_respValid) begin
                        arb_state <= ARB_IDLE;
                    end
                end
                ARB_LSU_WRITE: begin
                    // LSU 正在写入（使用 AW/W/B 通道，不阻塞 IFU）
                    if (io_lsu_respValid) begin
                        arb_state <= ARB_IDLE;
                    end
                    // 允许 IFU 在写期间继续工作
                end
                default: arb_state <= ARB_IDLE;
            endcase
        end
    end
    
    // LSU 请求逻辑
    // - LSU 读：只在 IDLE 或 LSU_READ 状态允许
    // - LSU 写：在 IDLE, LSU_WRITE, 或 IFU 状态都允许（不冲突）
    wire lsu_read_can_req  = (arb_state == ARB_IDLE) || (arb_state == ARB_LSU_READ);
    wire lsu_write_can_req = (arb_state == ARB_IDLE) || (arb_state == ARB_LSU_WRITE) || (arb_state == ARB_IFU);
    wire lsu_can_req = (lsu_is_read && lsu_read_can_req) || (lsu_is_write && lsu_write_can_req);
    
    assign io_lsu_addr     = lsu_addr;
    assign io_lsu_reqValid = lsu_req && lsu_can_req;
    assign io_lsu_size     = 2'b10;  // 默认字访问 (4 bytes)
    assign io_lsu_wen      = lsu_wen;
    assign io_lsu_wdata    = lsu_wdata;
    assign io_lsu_wmask    = lsu_wmask;
    assign lsu_rdata       = io_lsu_rdata;
    assign lsu_rvalid      = io_lsu_respValid && lsu_using_bus;

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
