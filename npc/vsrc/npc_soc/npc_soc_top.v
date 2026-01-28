module top(
    input clk,
    input rst,
    input [31:0]op,
    input sdop_en,

    output [31:0]dnpc,
    output rdop_en,
    output end_flag,          // 程序结束标志
    output [31:0] exit_code,  // 添加退出码输出
    
    // 添加寄存器接口用于DiffTest
    output [31:0] x0, x1, x2, x3, x4, x5, x6, x7,
    output [31:0] x8, x9, x10, x11, x12, x13, x14, x15,
    output [31:0] x16, x17, x18, x19, x20, x21, x22, x23,
    output [31:0] x24, x25, x26, x27, x28, x29, x30, x31
);

// EXU执行单元接口信号
wire ex_end;                // EXU执行完成信号 
wire [31:0] next_pc;        // 从EXU获取的下一条指令PC
wire branch_taken;          // 分支是否taken
  
// LSU SRAM接口信号
wire lsu_req;                    // LSU访存请求
wire lsu_wen;                    // LSU写使能
wire [31:0] lsu_addr;            // LSU地址
wire [31:0] lsu_wdata;           // LSU写数据
wire [3:0] lsu_wmask;            // LSU写掩码
wire lsu_rvalid;                 // LSU读数据有效
wire [31:0] lsu_rdata;           // LSU读数据

// IFU相关信号
reg [31:0] pc;          // 程序计数器
reg rdop_en_reg;        // 读操作使能寄存器
reg ex_end_prev;        // 前一周期的ex_end信号
reg end_flag_reg;       // 结束标志寄存器
reg rdop_en_prev;       // 前一周期的rdop_en状态
reg update_pc;          // PC更新使能信号

// 添加一个中间 wire 信号
wire ebreak_detected;  // 新增的内部信号

// 添加退出码信号
wire [31:0] exit_value;
reg [31:0] exit_code_reg;

// IFU 取指相关信号
wire        ifu_rvalid;
wire [31:0] ifu_rdata;
reg         ifu_req;
reg         first_fetch_pending;
reg         op_en_ifu;
reg  [31:0] op_ifu;
wire [31:0] ifu_addr = (update_pc) ? next_pc : pc;

// EXU实例化
EXU EXU (
    .clk         (clk),
    .rst         (rst),
    .op          (op_ifu),      // 由 IFU 返回的指令
    .op_en       (op_en_ifu),   // IFU 的有效握手
    .pc          (pc),          // 当前指令的PC
    
    .ex_end      (ex_end),      // 执行完成信号
    .next_pc     (next_pc),     // 下一条指令的PC
    .branch_taken(branch_taken), // 分支是否taken
    
    // LSU SRAM接口
    .lsu_req     (lsu_req),         // LSU访存请求
    .lsu_wen     (lsu_wen),         // LSU写使能
    .lsu_addr    (lsu_addr),        // LSU地址
    .lsu_wdata   (lsu_wdata),       // LSU写数据
    .lsu_wmask   (lsu_wmask),       // LSU写掩码
    .lsu_rvalid  (lsu_rvalid),      // LSU读数据有效
    .lsu_rdata   (lsu_rdata),       // LSU读数据
    .ebreak_flag (ebreak_detected),
    .exit_code   (exit_value)       // 连接到退出码信号
    // 寄存器接口 - regs端口已在EXU中注释，此处也注释
    // .regs        (exu_regs)
);

// 添加EXU接口用于获取寄存器值 - 正确声明为数组
wire [31:0] exu_regs [0:31];  // 明确声明为32元素的数组

// 输出寄存器值
assign x0 = exu_regs[0];
assign x1 = exu_regs[1];
assign x2 = exu_regs[2];
assign x3 = exu_regs[3];
assign x4 = exu_regs[4];
assign x5 = exu_regs[5];
assign x6 = exu_regs[6];
assign x7 = exu_regs[7];
assign x8 = exu_regs[8];
assign x9 = exu_regs[9];
assign x10 = exu_regs[10];
assign x11 = exu_regs[11];
assign x12 = exu_regs[12];
assign x13 = exu_regs[13];
assign x14 = exu_regs[14];
assign x15 = exu_regs[15];
assign x16 = exu_regs[16];
assign x17 = exu_regs[17];
assign x18 = exu_regs[18];
assign x19 = exu_regs[19];
assign x20 = exu_regs[20];
assign x21 = exu_regs[21];
assign x22 = exu_regs[22];
assign x23 = exu_regs[23];
assign x24 = exu_regs[24];
assign x25 = exu_regs[25];
assign x26 = exu_regs[26];
assign x27 = exu_regs[27];
assign x28 = exu_regs[28];
assign x29 = exu_regs[29];
assign x30 = exu_regs[30];
assign x31 = exu_regs[31];

// AXI4-Lite信号定义 - IFU
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

// AXI4-Lite信号定义 - LSU
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

// Xbar主设备接口信号（连接仲裁器）
wire [31:0] xbar_awaddr;
wire        xbar_awvalid;
wire        xbar_awready;
wire [31:0] xbar_wdata;
wire [3:0]  xbar_wstrb;
wire        xbar_wvalid;
wire        xbar_wready;
wire [1:0]  xbar_bresp;
wire        xbar_bvalid;
wire        xbar_bready;
wire [31:0] xbar_araddr;
wire        xbar_arvalid;
wire        xbar_arready;
wire [31:0] xbar_rdata;
wire [1:0]  xbar_rresp;
wire        xbar_rvalid;
wire        xbar_rready;

// SRAM从设备接口信号（连接Xbar）
wire [31:0] sram_awaddr;
wire        sram_awvalid;
wire        sram_awready;
wire [31:0] sram_wdata;
wire [3:0]  sram_wstrb;
wire        sram_wvalid;
wire        sram_wready;
wire [1:0]  sram_bresp;
wire        sram_bvalid;
wire        sram_bready;
wire [31:0] sram_araddr;
wire        sram_arvalid;
wire        sram_arready;
wire [31:0] sram_rdata;
wire [1:0]  sram_rresp;
wire        sram_rvalid;
wire        sram_rready;

// UART从设备接口信号（连接Xbar）
wire [31:0] uart_awaddr;
wire        uart_awvalid;
wire        uart_awready;
wire [31:0] uart_wdata;
wire [3:0]  uart_wstrb;
wire        uart_wvalid;
wire        uart_wready;
wire [1:0]  uart_bresp;
wire        uart_bvalid;
wire        uart_bready;
wire [31:0] uart_araddr;
wire        uart_arvalid;
wire        uart_arready;
wire [31:0] uart_rdata;
wire [1:0]  uart_rresp;
wire        uart_rvalid;
wire        uart_rready;

// CLINT从设备接口信号（连接Xbar）
wire [31:0] clint_awaddr;
wire        clint_awvalid;
wire        clint_awready;
wire [31:0] clint_wdata;
wire [3:0]  clint_wstrb;
wire        clint_wvalid;
wire        clint_wready;
wire [1:0]  clint_bresp;
wire        clint_bvalid;
wire        clint_bready;
wire [31:0] clint_araddr;
wire        clint_arvalid;
wire        clint_arready;
wire [31:0] clint_rdata;
wire [1:0]  clint_rresp;
wire        clint_rvalid;
wire        clint_rready;

// IFU SRAM模块实例化：AXI4-Lite master接口
IFU_SRAM u_ifu (
    .clk         (clk),
    .rst         (rst),
    .req         (ifu_req),
    .addr        (ifu_addr),
    .rvalid_out  (ifu_rvalid),
    .rdata_out   (ifu_rdata),
    
    // AXI4-Lite Master接口
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

// LSU SRAM模块实例化：AXI4-Lite master接口
LSU_SRAM u_lsu (
    .clk         (clk),
    .rst         (rst),
    
    // 原始接口
    .req         (lsu_req),
    .wen         (lsu_wen),
    .addr        (lsu_addr),
    .wdata       (lsu_wdata),
    .wmask       (lsu_wmask),
    .rvalid_out  (lsu_rvalid),
    .rdata_out   (lsu_rdata),
    
    // AXI4-Lite Master接口
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

// AXI4-Lite仲裁器实例化
AXI4_Lite_Arbiter u_arbiter (
    .clk(clk),
    .rst(rst),
    
    // Master 0: IFU接口
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
    
    // Master 1: LSU接口
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
    
    // Slave: Xbar接口（原来是直接连接SRAM）
    .s_awaddr    (xbar_awaddr),
    .s_awvalid   (xbar_awvalid),
    .s_awready   (xbar_awready),
    .s_wdata     (xbar_wdata),
    .s_wstrb     (xbar_wstrb),
    .s_wvalid    (xbar_wvalid),
    .s_wready    (xbar_wready),
    .s_bresp     (xbar_bresp),
    .s_bvalid    (xbar_bvalid),
    .s_bready    (xbar_bready),
    .s_araddr    (xbar_araddr),
    .s_arvalid   (xbar_arvalid),
    .s_arready   (xbar_arready),
    .s_rdata     (xbar_rdata),
    .s_rresp     (xbar_rresp),
    .s_rvalid    (xbar_rvalid),
    .s_rready    (xbar_rready)
);

// AXI4-Lite Xbar实例化
AXI4_Lite_Xbar u_xbar (
    .clk(clk),
    .rst(rst),
    
    // 主设备接口（来自仲裁器）
    .m_awaddr    (xbar_awaddr),
    .m_awvalid   (xbar_awvalid),
    .m_awready   (xbar_awready),
    .m_wdata     (xbar_wdata),
    .m_wstrb     (xbar_wstrb),
    .m_wvalid    (xbar_wvalid),
    .m_wready    (xbar_wready),
    .m_bresp     (xbar_bresp),
    .m_bvalid    (xbar_bvalid),
    .m_bready    (xbar_bready),
    .m_araddr    (xbar_araddr),
    .m_arvalid   (xbar_arvalid),
    .m_arready   (xbar_arready),
    .m_rdata     (xbar_rdata),
    .m_rresp     (xbar_rresp),
    .m_rvalid    (xbar_rvalid),
    .m_rready    (xbar_rready),
    
    // SRAM从设备接口
    .sram_awaddr (sram_awaddr),
    .sram_awvalid(sram_awvalid),
    .sram_awready(sram_awready),
    .sram_wdata  (sram_wdata),
    .sram_wstrb  (sram_wstrb),
    .sram_wvalid (sram_wvalid),
    .sram_wready (sram_wready),
    .sram_bresp  (sram_bresp),
    .sram_bvalid (sram_bvalid),
    .sram_bready (sram_bready),
    .sram_araddr (sram_araddr),
    .sram_arvalid(sram_arvalid),
    .sram_arready(sram_arready),
    .sram_rdata  (sram_rdata),
    .sram_rresp  (sram_rresp),
    .sram_rvalid (sram_rvalid),
    .sram_rready (sram_rready),
    
    // UART从设备接口
    .uart_awaddr (uart_awaddr),
    .uart_awvalid(uart_awvalid),
    .uart_awready(uart_awready),
    .uart_wdata  (uart_wdata),
    .uart_wstrb  (uart_wstrb),
    .uart_wvalid (uart_wvalid),
    .uart_wready (uart_wready),
    .uart_bresp  (uart_bresp),
    .uart_bvalid (uart_bvalid),
    .uart_bready (uart_bready),
    .uart_araddr (uart_araddr),
    .uart_arvalid(uart_arvalid),
    .uart_arready(uart_arready),
    .uart_rdata  (uart_rdata),
    .uart_rresp  (uart_rresp),
    .uart_rvalid (uart_rvalid),
    .uart_rready (uart_rready),
    
    // CLINT从设备接口
    .clint_awaddr (clint_awaddr),
    .clint_awvalid(clint_awvalid),
    .clint_awready(clint_awready),
    .clint_wdata  (clint_wdata),
    .clint_wstrb  (clint_wstrb),
    .clint_wvalid (clint_wvalid),
    .clint_wready (clint_wready),
    .clint_bresp  (clint_bresp),
    .clint_bvalid (clint_bvalid),
    .clint_bready (clint_bready),
    .clint_araddr (clint_araddr),
    .clint_arvalid(clint_arvalid),
    .clint_arready(clint_arready),
    .clint_rdata  (clint_rdata),
    .clint_rresp  (clint_rresp),
    .clint_rvalid (clint_rvalid),
    .clint_rready (clint_rready)
);

// AXI4-Lite SRAM Slave实例化
AXI4_Lite_SRAM u_sram (
    .clk(clk),
    .rst(rst),
    
    // AXI4-Lite Slave接口（连接到Xbar的SRAM端口）
    .awaddr      (sram_awaddr),
    .awvalid     (sram_awvalid),
    .awready     (sram_awready),
    .wdata       (sram_wdata),
    .wstrb       (sram_wstrb),
    .wvalid      (sram_wvalid),
    .wready      (sram_wready),
    .bresp       (sram_bresp),
    .bvalid      (sram_bvalid),
    .bready      (sram_bready),
    .araddr      (sram_araddr),
    .arvalid     (sram_arvalid),
    .arready     (sram_arready),
    .rdata       (sram_rdata),
    .rresp       (sram_rresp),
    .rvalid      (sram_rvalid),
    .rready      (sram_rready),
    
    // 调试信号
    .debug_addr  (),
    .debug_read  (),
    .debug_write ()
);

// AXI4-Lite UART实例化
AXI4_Lite_UART u_uart (
    .clk(clk),
    .rst(rst),
    
    // AXI4-Lite Slave接口（连接到Xbar的UART端口）
    .awaddr      (uart_awaddr),
    .awvalid     (uart_awvalid),
    .awready     (uart_awready),
    .wdata       (uart_wdata),
    .wstrb       (uart_wstrb),
    .wvalid      (uart_wvalid),
    .wready      (uart_wready),
    .bresp       (uart_bresp),
    .bvalid      (uart_bvalid),
    .bready      (uart_bready),
    .araddr      (uart_araddr),
    .arvalid     (uart_arvalid),
    .arready     (uart_arready),
    .rdata       (uart_rdata),
    .rresp       (uart_rresp),
    .rvalid      (uart_rvalid),
    .rready      (uart_rready),
    
    // 配置参数：设备寄存器基地址（UART串口地址）
    .base_addr   (32'ha0000000),
    
    // 调试输出
    .debug_char  (),
    .debug_write ()
);

// AXI4-Lite CLINT实例化
AXI4_Lite_CLINT u_clint (
    .clk(clk),
    .rst(rst),
    
    // AXI4-Lite Slave接口（连接到Xbar的CLINT端口）
    .awaddr      (clint_awaddr),
    .awvalid     (clint_awvalid),
    .awready     (clint_awready),
    .wdata       (clint_wdata),
    .wstrb       (clint_wstrb),
    .wvalid      (clint_wvalid),
    .wready      (clint_wready),
    .bresp       (clint_bresp),
    .bvalid      (clint_bvalid),
    .bready      (clint_bready),
    .araddr      (clint_araddr),
    .arvalid     (clint_arvalid),
    .arready     (clint_arready),
    .rdata       (clint_rdata),
    .rresp       (clint_rresp),
    .rvalid      (clint_rvalid),
    .rready      (clint_rready),
    
    // 配置参数：设备寄存器基地址（CLINT地址）
    .base_addr   (32'ha0000000),
    
    // 调试输出
    .debug_mtime (),
    .debug_read  ()
);

// 初始化与复位逻辑
always @(posedge clk or posedge rst) begin
    if (rst) begin
        pc <= 32'h8000_0000;  // 复位时PC设置为0x80000000
        rdop_en_reg <= 1'b0;
        ex_end_prev <= 1'b0;
        end_flag_reg <= 1'b0;
        rdop_en_prev <= 1'b0;
        update_pc <= 1'b0;
        exit_code_reg <= 32'h0;
        // IFU 相关复位
        first_fetch_pending <= 1'b1; // 复位后需要首次取指
        ifu_req <= 1'b0;
        op_en_ifu <= 1'b0;
        op_ifu <= 32'h0;
    end else begin
        // 保存ex_end和rdop_en的前一个状态用于检测变化
        ex_end_prev <= ex_end;
        rdop_en_prev <= rdop_en_reg;
        
        // 当ex_end发生变化时，设置rdop_en为1一个周期
        if (ex_end != ex_end_prev) begin
            rdop_en_reg <= 1'b1;
        end else begin
            rdop_en_reg <= 1'b0;
        end
        
        // 检测rdop_en从1变为0的上升沿，设置update_pc为1 hy:这里做了修改
        if (rdop_en_reg && !rdop_en_prev) begin
            update_pc <= 1'b1;
        end else if (update_pc) begin
            // 在检测到下降沿后的下一个周期更新PC，使用EXU提供的next_pc
            pc <= next_pc;
            update_pc <= 1'b0;
        end
        
        // IFU 请求脉冲：
        // - 复位后的首次取指打一拍
        // - 在更新PC的那个周期为下一条指令发起取指
        if (first_fetch_pending) begin
            ifu_req <= 1'b1;
            first_fetch_pending <= 1'b0;
        end else if (update_pc) begin
            ifu_req <= 1'b1;
        end else begin
            ifu_req <= 1'b0;
        end

        // 当 IFU 返回有效时，打一拍通知 EXU 并提供指令
        op_en_ifu <= 1'b0; // 缺省无效
        if (ifu_rvalid) begin
            op_ifu <= ifu_rdata;
            op_en_ifu <= 1'b1;
        end
        
        // 添加 end_flag_reg 更新逻辑
        end_flag_reg <= ebreak_detected;
        
        // 更新退出码寄存器
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
            
            // IFU 统计
            $display("[IFU Statistics]");
            $display("  Fetch Count:       %0d", u_ifu.perf_ifu_fetch_cnt);
            $display("  Request Cycles:    %0d", u_ifu.perf_ifu_req_cycles);
            $display("  Wait Cycles:       %0d", u_ifu.perf_ifu_wait_cycles);
            $display("  Arb Stall Cycles:  %0d", u_ifu.perf_ifu_stall_arb_cycles);
            if (u_ifu.perf_ifu_fetch_cnt > 0) begin
                $display("  Avg Fetch Latency: %0d.%02d cycles",
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
            // IFU Fetch 允许比 Retired 多1（ebreak时有预取）
            $display("  IFU Fetch ~= Retired Instrs: %s (diff=%0d)", 
                ((u_ifu.perf_ifu_fetch_cnt == EXU.perf_minstret) || 
                 (u_ifu.perf_ifu_fetch_cnt == EXU.perf_minstret + 1)) ? "PASS" : "FAIL",
                u_ifu.perf_ifu_fetch_cnt - EXU.perf_minstret);
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
        end
    end
end

// 输出赋值
assign rdop_en = rdop_en_reg;
assign end_flag = end_flag_reg;
assign dnpc = next_pc;  // 使用EXU计算的下一条指令PC作为dnpc输出
assign exit_code = exit_code_reg;

endmodule