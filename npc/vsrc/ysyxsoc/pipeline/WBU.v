// WBU: Write Back Unit (写回单元)
// 
// 职责:
// - 寄存器写回
// - CSR 写回
// - 异常处理 (ecall/mret)
// - 指令退休计数

module WBU (
    input         clk,
    input         rst,
    
    // 上游接口 (from LSU)
    input         in_valid,
    output        in_ready,
    input  [31:0] in_pc,
    input  [31:0] in_inst,
    input  [31:0] in_result,
    input  [4:0]  in_rd,
    input         in_reg_wen,
    input         in_is_csr,
    input  [31:0] in_csr_wdata,
    input         in_csr_wen,
    input  [11:0] in_csr_addr,
    input         in_ebreak,
    input         in_ecall,
    input         in_mret,
    
    // 寄存器文件写回接口
    output        rf_wen,
    output [4:0]  rf_waddr,
    output [31:0] rf_wdata,
    
    // CSR 寄存器写回
    output reg [31:0] csr_mtvec,
    output reg [31:0] csr_mepc,
    output reg [31:0] csr_mcause,
    output reg [31:0] csr_mstatus,
    
    // 异常处理
    output        exception_valid,
    output [31:0] exception_target,  // mtvec 或 mepc
    
    // ebreak 信号
    output        ebreak_flag,
    output [31:0] exit_code,
    
    // 指令完成信号 (用于控制)
    output reg    inst_commit,
    output [31:0] commit_pc
    
    // 性能计数器 (仅仿真)
`ifdef SIMULATION
    ,
    output reg [63:0] perf_minstret,
    output reg [63:0] perf_mcycle
`endif
);

    // ========== 状态机 ==========
    localparam S_IDLE = 1'b0;
    localparam S_COMMIT = 1'b1;
    
    reg state;
    reg [31:0] pc_reg;
    reg [31:0] inst_reg;
    reg [31:0] result_reg;
    reg [4:0]  rd_reg;
    reg        reg_wen_reg;
    reg        is_csr_reg;
    reg [31:0] csr_wdata_reg;
    reg        csr_wen_reg;
    reg [11:0] csr_addr_reg;
    reg        is_ebreak_reg;
    reg        is_ecall_reg;
    reg        is_mret_reg;
    
    // ========== 握手逻辑 ==========
    assign in_ready = (state == S_IDLE);
    
    // ========== 寄存器文件写回 ==========
    assign rf_wen   = reg_wen_reg && (state == S_COMMIT);
    assign rf_waddr = rd_reg;
    assign rf_wdata = result_reg;
    
    // ========== 异常处理 ==========
    assign exception_valid  = (is_ecall_reg || is_mret_reg) && (state == S_COMMIT);
    assign exception_target = is_mret_reg ? csr_mepc : csr_mtvec;
    
    // ========== ebreak ==========
    assign ebreak_flag = is_ebreak_reg && (state == S_COMMIT);
    assign exit_code   = 32'h0;  // 正常退出
    
    // ========== commit PC ==========
    assign commit_pc = pc_reg;
    
    // ========== 主状态机 ==========
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            inst_commit <= 1'b0;
            pc_reg <= 32'h0;
            inst_reg <= 32'h0;
            result_reg <= 32'h0;
            rd_reg <= 5'h0;
            reg_wen_reg <= 1'b0;
            is_csr_reg <= 1'b0;
            csr_wdata_reg <= 32'h0;
            csr_wen_reg <= 1'b0;
            csr_addr_reg <= 12'h0;
            is_ebreak_reg <= 1'b0;
            is_ecall_reg <= 1'b0;
            is_mret_reg <= 1'b0;
            
            // CSR 初始化
            csr_mtvec <= 32'h80000000;
            csr_mepc <= 32'h0;
            csr_mcause <= 32'h0;
            csr_mstatus <= 32'h0;
            
`ifdef SIMULATION
            perf_minstret <= 64'h0;
            perf_mcycle <= 64'h0;
`endif
        end else begin
`ifdef SIMULATION
            perf_mcycle <= perf_mcycle + 1;
`endif
            
            case (state)
                S_IDLE: begin
                    inst_commit <= 1'b0;
                    if (in_valid) begin
                        // 锁存输入
                        pc_reg <= in_pc;
                        inst_reg <= in_inst;
                        result_reg <= in_result;
                        rd_reg <= in_rd;
                        reg_wen_reg <= in_reg_wen;
                        is_csr_reg <= in_is_csr;
                        csr_wdata_reg <= in_csr_wdata;
                        csr_wen_reg <= in_csr_wen;
                        csr_addr_reg <= in_csr_addr;
                        is_ebreak_reg <= in_ebreak;
                        is_ecall_reg <= in_ecall;
                        is_mret_reg <= in_mret;
                        state <= S_COMMIT;
                    end
                end
                
                S_COMMIT: begin
                    // 执行写回
                    // 寄存器写回通过 rf_wen 组合逻辑完成
                    
                    // CSR 写回
                    if (csr_wen_reg) begin
                        case (csr_addr_reg)
                            12'h305: csr_mtvec <= csr_wdata_reg;
                            12'h341: csr_mepc <= csr_wdata_reg;
                            12'h342: csr_mcause <= csr_wdata_reg;
                            12'h300: csr_mstatus <= csr_wdata_reg;
                            default: ;
                        endcase
                    end
                    
                    // ecall 处理: 保存上下文
                    if (is_ecall_reg) begin
                        csr_mepc <= pc_reg;
                        csr_mcause <= 32'd11;  // Environment call from M-mode
                    end
                    
`ifdef SIMULATION
                    // 性能计数
                    perf_minstret <= perf_minstret + 1;
`endif
                    
                    inst_commit <= 1'b1;
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
