// NPC_pipeline: 五级流水线处理器顶层
//
// 阶段 2 实现: 流水线执行版本
// - IF: 取指
// - ID: 译码 + 读寄存器
// - EX: 执行 + 分支计算
// - MEM: 访存
// - WB: 写回
//
// 注意: 此版本暂不处理数据冒险，需要配合无依赖的测试程序

module NPC_pipeline (
    input         clk,
    input         rst,
    
    // IFU 接口 (连接到 I-Cache 或 IFU_AXI4)
    output reg    ifu_req,
    output [31:0] ifu_addr,
    output        ifu_flush,    // Flush signal for ICache
    input         ifu_rvalid,
    input  [31:0] ifu_rdata,
    
    // LSU 接口 (连接到 D-Cache 或 LSU_AXI4)
    output        lsu_req,
    output        lsu_wen,
    output [31:0] lsu_addr,
    output [31:0] lsu_wdata,
    output [3:0]  lsu_wmask,
    input         lsu_rvalid,
    input  [31:0] lsu_rdata,
    
    // ebreak 信号
    output        ebreak_flag,
    output [31:0] exit_code
    
    // 性能计数器 (仿真)
`ifdef SIMULATION
    ,
    output [63:0] perf_minstret,
    output [63:0] perf_mcycle
`endif
);

    // ========== 流水线控制信号 ==========
    
    // 全局暂停信号
    wire stall_if;      // IF 阶段暂停
    wire stall_id;      // ID 阶段暂停
    wire stall_ex;      // EX 阶段暂停
    wire stall_mem;     // MEM 阶段暂停
    
    // 冲刷信号
    wire flush_if;      // 冲刷 IF 阶段
    wire flush_id;      // 冲刷 ID 阶段
    wire flush_ex;      // 冲刷 EX 阶段
    
    // ========== IF 阶段 ==========
    
    // PC 寄存器
    reg [31:0] pc;
    wire [31:0] next_pc;
    
    // IF 阶段状态
    reg if_waiting;     // 正在等待取指完成
    reg if_valid;       // IF 阶段有有效数据
    
    // IF/ID 级间寄存器
    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;
    
    // ========== ID 阶段信号 ==========
    wire        idu_out_valid;
    wire        idu_out_ready;
    wire [31:0] idu_out_pc;
    wire [31:0] idu_out_inst;
    wire [31:0] idu_out_rs1_data;
    wire [31:0] idu_out_rs2_data;
    wire [31:0] idu_out_imm;
    wire [4:0]  idu_out_rd;
    wire [4:0]  idu_out_rs1;
    wire [4:0]  idu_out_rs2;
    wire [6:0]  idu_out_opcode;
    wire [2:0]  idu_out_funct3;
    wire [6:0]  idu_out_funct7;
    wire        idu_out_reg_wen;
    wire        idu_out_mem_ren;
    wire        idu_out_mem_wen;
    wire        idu_out_is_branch;
    wire        idu_out_is_jal;
    wire        idu_out_is_jalr;
    wire        idu_out_is_lui;
    wire        idu_out_is_auipc;
    wire        idu_out_is_system;
    wire        idu_out_is_fence;
    wire        idu_out_is_csr;
    
    // ID/EX 级间寄存器
    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_inst;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rd;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [6:0]  id_ex_opcode;
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_funct7;
    reg        id_ex_reg_wen;
    reg        id_ex_mem_ren;
    reg        id_ex_mem_wen;
    reg        id_ex_is_branch;
    reg        id_ex_is_jal;
    reg        id_ex_is_jalr;
    reg        id_ex_is_lui;
    reg        id_ex_is_auipc;
    reg        id_ex_is_system;
    reg        id_ex_is_fence;
    reg        id_ex_is_csr;
    
    // ========== EX 阶段信号 ==========
    wire        exu_out_valid;
    wire        exu_out_ready;
    wire [31:0] exu_out_pc;
    wire [31:0] exu_out_inst;
    wire [31:0] exu_out_alu_result;
    wire [31:0] exu_out_rs2_data;
    wire [4:0]  exu_out_rd;
    wire [2:0]  exu_out_funct3;
    wire        exu_out_reg_wen;
    wire        exu_out_mem_ren;
    wire        exu_out_mem_wen;
    wire        exu_out_is_system;
    wire        exu_out_is_csr;
    wire [31:0] exu_out_csr_rdata;
    wire [31:0] exu_out_csr_wdata;
    wire        exu_out_csr_wen;
    wire        exu_branch_taken;
    wire [31:0] exu_branch_target;
    wire        exu_is_jump;
    wire        exu_is_fence;
    wire        exu_ebreak;
    wire        exu_ecall;
    wire        exu_mret;
    
    // EX/MEM 级间寄存器
    reg        ex_mem_valid;
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_inst;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_rs2_data;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_wen;
    reg        ex_mem_mem_ren;
    reg        ex_mem_mem_wen;
    reg        ex_mem_is_system;
    reg        ex_mem_is_csr;
    reg [31:0] ex_mem_csr_rdata;
    reg [31:0] ex_mem_csr_wdata;
    reg        ex_mem_csr_wen;
    reg        ex_mem_ebreak;
    reg        ex_mem_ecall;
    reg        ex_mem_mret;
    
    // ========== MEM 阶段信号 ==========
    wire        lsu_out_valid;
    wire        lsu_out_ready;
    wire [31:0] lsu_out_pc;
    wire [31:0] lsu_out_inst;
    wire [31:0] lsu_out_result;
    wire [4:0]  lsu_out_rd;
    wire        lsu_out_reg_wen;
    wire        lsu_out_is_csr;
    wire [31:0] lsu_out_csr_wdata;
    wire        lsu_out_csr_wen;
    wire [11:0] lsu_out_csr_addr;
    wire        lsu_out_ebreak;
    wire        lsu_out_ecall;
    wire        lsu_out_mret;
    
    // MEM/WB 级间寄存器
    reg        mem_wb_valid;
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_inst;
    reg [31:0] mem_wb_result;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_wen;
    reg        mem_wb_is_csr;
    reg [31:0] mem_wb_csr_wdata;
    reg        mem_wb_csr_wen;
    reg [11:0] mem_wb_csr_addr;
    reg        mem_wb_ebreak;
    reg        mem_wb_ecall;
    reg        mem_wb_mret;
    
    // ========== WB 阶段信号 ==========
    wire        wbu_rf_wen;
    wire [4:0]  wbu_rf_waddr;
    wire [31:0] wbu_rf_wdata;
    wire [31:0] wbu_csr_mtvec;
    wire [31:0] wbu_csr_mepc;
    wire [31:0] wbu_csr_mcause;
    wire [31:0] wbu_csr_mstatus;
    wire        wbu_exception_valid;
    wire [31:0] wbu_exception_target;
    wire        wbu_ebreak_flag;
    wire [31:0] wbu_exit_code;
    wire        wbu_inst_commit;
    wire [31:0] wbu_commit_pc;
    
    // ========== 冒险检测和暂停逻辑 ==========
    
    // 结构冒险: MEM 阶段访存时需要暂停
    wire mem_busy = ex_mem_valid && (ex_mem_mem_ren || ex_mem_mem_wen) && !lsu_out_valid;
    
    // ========== RAW 数据冒险检测 ==========
    // 检测 ID 阶段源寄存器与后续阶段目标寄存器的冲突
    
    // ID 阶段的源寄存器（来自 IDU 输出）
    wire [4:0] id_rs1 = idu_out_rs1;
    wire [4:0] id_rs2 = idu_out_rs2;
    wire id_uses_rs1 = idu_out_valid && (id_rs1 != 5'b0);  // x0 不需要检测
    wire id_uses_rs2 = idu_out_valid && (id_rs2 != 5'b0);
    
    // EX 阶段的目标寄存器
    wire [4:0] ex_rd = id_ex_rd;
    wire ex_writes_reg = id_ex_valid && id_ex_reg_wen && (ex_rd != 5'b0);
    
    // MEM 阶段的目标寄存器
    wire [4:0] mem_rd = ex_mem_rd;
    wire mem_writes_reg = ex_mem_valid && ex_mem_reg_wen && (mem_rd != 5'b0);
    
    // WB 阶段的目标寄存器
    // 使用 WBU 的写入信号，因为 WBU 接收数据后需额外周期才写入寄存器堆
    wire wb_writes_reg = wbu_rf_wen && (wbu_rf_waddr != 5'b0);
    // MEM/WB 寄存器中待写入的数据也需要检测
    wire pending_wb_writes = mem_wb_valid && mem_wb_reg_wen && (mem_wb_rd != 5'b0);
    
    // RAW 冒险检测
    wire raw_ex_rs1 = id_uses_rs1 && ex_writes_reg && (id_rs1 == ex_rd);
    wire raw_ex_rs2 = id_uses_rs2 && ex_writes_reg && (id_rs2 == ex_rd);
    wire raw_mem_rs1 = id_uses_rs1 && mem_writes_reg && (id_rs1 == mem_rd);
    wire raw_mem_rs2 = id_uses_rs2 && mem_writes_reg && (id_rs2 == mem_rd);
    // WB 阶段的 RAW 冒险：检测当前周期写入和待写入的数据
    wire raw_wb_rs1 = id_uses_rs1 && ((wb_writes_reg && (id_rs1 == wbu_rf_waddr)) || 
                                      (pending_wb_writes && (id_rs1 == mem_wb_rd)));
    wire raw_wb_rs2 = id_uses_rs2 && ((wb_writes_reg && (id_rs2 == wbu_rf_waddr)) || 
                                      (pending_wb_writes && (id_rs2 == mem_wb_rd)));
    
    wire raw_hazard = raw_ex_rs1 || raw_ex_rs2 || raw_mem_rs1 || raw_mem_rs2 || raw_wb_rs1 || raw_wb_rs2;
    
    // 暂停信号
    // stall_if: IF 阶段只在 MEM busy 或下游阻塞时暂停
    // 注意: if_waiting 不应该阻塞 IF 自己，它只是等待取指完成的状态
    assign stall_if  = mem_busy || stall_id || raw_hazard;
    assign stall_id  = mem_busy || raw_hazard;  // RAW 冒险时阻塞 ID
    assign stall_ex  = mem_busy;
    assign stall_mem = 1'b0;  // MEM 阶段不暂停
    
    // 控制冒险冲刷: 分支/跳转/异常时冲刷流水线
    wire branch_flush = exu_branch_taken || exu_is_jump;
    wire exception_flush = wbu_exception_valid;
    
    assign flush_if  = branch_flush || exception_flush;
    assign flush_id  = branch_flush || exception_flush;
    assign flush_ex  = exception_flush;
    
    // ========== IF 阶段逻辑 ==========
    
    // IFU 地址和 flush 信号
    assign ifu_addr = pc;
    assign ifu_flush = flush_if;
    
    // 下一 PC 计算
    assign next_pc = wbu_exception_valid ? wbu_exception_target :
                     (exu_branch_taken || exu_is_jump) ? exu_branch_target :
                     pc + 32'd4;
    
    // IF/ID 被消费的条件：ID 阶段输出有效且 ID 阶段不阻塞（包括 RAW hazard）
    wire if_id_consumed = if_id_valid && idu_out_valid && !stall_id && !flush_id;
    
    // IF 阶段状态机
    // if_discard: 当 flush 发生时，如果 ICache 正在处理请求，需要等待它返回并丢弃数据
    reg if_discard;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 32'h3000_0000;
            ifu_req <= 1'b0;
            if_waiting <= 1'b0;
            if_discard <= 1'b0;
            if_id_pc <= 32'h0;
            if_id_inst <= 32'h0;
            if_id_valid <= 1'b0;
        end else begin
            // 默认清除请求
            ifu_req <= 1'b0;
            
            // 冲刷处理
            if (flush_if) begin
                if_id_valid <= 1'b0;
                pc <= next_pc;
                // 直接丢弃正在进行的取指，不等待 ICache 返回
                // 这可能会导致 ICache 的一次 refill 被浪费，但不会影响正确性
                if_waiting <= 1'b0;
                if_discard <= 1'b0;
            end else begin
                // 正常处理
                
                // 处理需要丢弃的旧数据
                if (if_discard && ifu_rvalid) begin
                    if_discard <= 1'b0;
                    if_waiting <= 1'b0;
                    // 丢弃数据，不写入 if_id
                end
                // IF/ID 被消费时清除 valid
                else if (if_id_consumed) begin
                    if_id_valid <= 1'b0;
                end
                
                // 取指完成时写入 IF/ID（正常情况，非 discard）
                if (if_waiting && !if_discard && ifu_rvalid) begin
                    if_id_pc <= pc;
                    if_id_inst <= ifu_rdata;
                    if_id_valid <= 1'b1;
                    if_waiting <= 1'b0;
                    pc <= pc + 32'd4;
                end
                
                // 取指请求逻辑（脉冲请求，只维持一个周期）
                // 只有当不在等待且不需要丢弃数据时才能发起新请求
                if (!stall_if && !if_waiting && !if_discard) begin
                    // 需要发起新请求的条件：IF/ID 为空 或 IF/ID 正在被消费
                    if (!if_id_valid || if_id_consumed) begin
                        ifu_req <= 1'b1;
                        if_waiting <= 1'b1;
                    end
                end
            end
        end
    end
    
    // ========== ID 阶段逻辑 ==========
    
    // IDU 输入控制
    wire idu_in_valid = if_id_valid && !flush_id;
    wire idu_in_ready;
    
    // ID/EX 级间寄存器更新
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_valid <= 1'b0;
            id_ex_pc <= 32'h0;
            id_ex_inst <= 32'h0;
            id_ex_rs1_data <= 32'h0;
            id_ex_rs2_data <= 32'h0;
            id_ex_imm <= 32'h0;
            id_ex_rd <= 5'h0;
            id_ex_rs1 <= 5'h0;
            id_ex_rs2 <= 5'h0;
            id_ex_opcode <= 7'h0;
            id_ex_funct3 <= 3'h0;
            id_ex_funct7 <= 7'h0;
            id_ex_reg_wen <= 1'b0;
            id_ex_mem_ren <= 1'b0;
            id_ex_mem_wen <= 1'b0;
            id_ex_is_branch <= 1'b0;
            id_ex_is_jal <= 1'b0;
            id_ex_is_jalr <= 1'b0;
            id_ex_is_lui <= 1'b0;
            id_ex_is_auipc <= 1'b0;
            id_ex_is_system <= 1'b0;
            id_ex_is_fence <= 1'b0;
            id_ex_is_csr <= 1'b0;
        end else if (!stall_id) begin  // 使用 stall_id 而不是 stall_ex，因为 stall_id 包含 RAW hazard
            // 指令从 EX 阶段移出时清零 id_ex_valid
            if (exu_out_valid && !flush_ex) begin
                id_ex_valid <= 1'b0;
                // 如果同时有新指令进入，则立即设置
                if (idu_out_valid && !flush_id) begin
                    id_ex_valid <= 1'b1;
                    id_ex_pc <= idu_out_pc;
                    id_ex_inst <= idu_out_inst;
                    id_ex_rs1_data <= idu_out_rs1_data;
                    id_ex_rs2_data <= idu_out_rs2_data;
                    id_ex_imm <= idu_out_imm;
                    id_ex_rd <= idu_out_rd;
                    id_ex_rs1 <= idu_out_rs1;
                    id_ex_rs2 <= idu_out_rs2;
                    id_ex_opcode <= idu_out_opcode;
                    id_ex_funct3 <= idu_out_funct3;
                    id_ex_funct7 <= idu_out_funct7;
                    id_ex_reg_wen <= idu_out_reg_wen;
                    id_ex_mem_ren <= idu_out_mem_ren;
                    id_ex_mem_wen <= idu_out_mem_wen;
                    id_ex_is_branch <= idu_out_is_branch;
                    id_ex_is_jal <= idu_out_is_jal;
                    id_ex_is_jalr <= idu_out_is_jalr;
                    id_ex_is_lui <= idu_out_is_lui;
                    id_ex_is_auipc <= idu_out_is_auipc;
                    id_ex_is_system <= idu_out_is_system;
                    id_ex_is_fence <= idu_out_is_fence;
                    id_ex_is_csr <= idu_out_is_csr;
                end
            end else if (idu_out_valid && !flush_id) begin
                // 新指令进入 EX 阶段（没有指令移出）
                id_ex_valid <= 1'b1;
                id_ex_pc <= idu_out_pc;
                id_ex_inst <= idu_out_inst;
                id_ex_rs1_data <= idu_out_rs1_data;
                id_ex_rs2_data <= idu_out_rs2_data;
                id_ex_imm <= idu_out_imm;
                id_ex_rd <= idu_out_rd;
                id_ex_rs1 <= idu_out_rs1;
                id_ex_rs2 <= idu_out_rs2;
                id_ex_opcode <= idu_out_opcode;
                id_ex_funct3 <= idu_out_funct3;
                id_ex_funct7 <= idu_out_funct7;
                id_ex_reg_wen <= idu_out_reg_wen;
                id_ex_mem_ren <= idu_out_mem_ren;
                id_ex_mem_wen <= idu_out_mem_wen;
                id_ex_is_branch <= idu_out_is_branch;
                id_ex_is_jal <= idu_out_is_jal;
                id_ex_is_jalr <= idu_out_is_jalr;
                id_ex_is_lui <= idu_out_is_lui;
                id_ex_is_auipc <= idu_out_is_auipc;
                id_ex_is_system <= idu_out_is_system;
                id_ex_is_fence <= idu_out_is_fence;
                id_ex_is_csr <= idu_out_is_csr;
            end
            // 如果既没有指令移出，也没有新指令进入，id_ex_valid 保持原值
        end
    end
    
    // ========== EX 阶段逻辑 ==========
    
    // EXU 输入控制
    wire exu_in_valid = id_ex_valid && !flush_ex;
    
    // EX/MEM 级间寄存器更新
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_valid <= 1'b0;
            ex_mem_pc <= 32'h0;
            ex_mem_inst <= 32'h0;
            ex_mem_alu_result <= 32'h0;
            ex_mem_rs2_data <= 32'h0;
            ex_mem_rd <= 5'h0;
            ex_mem_funct3 <= 3'h0;
            ex_mem_reg_wen <= 1'b0;
            ex_mem_mem_ren <= 1'b0;
            ex_mem_mem_wen <= 1'b0;
            ex_mem_is_system <= 1'b0;
            ex_mem_is_csr <= 1'b0;
            ex_mem_csr_rdata <= 32'h0;
            ex_mem_csr_wdata <= 32'h0;
            ex_mem_csr_wen <= 1'b0;
            ex_mem_ebreak <= 1'b0;
            ex_mem_ecall <= 1'b0;
            ex_mem_mret <= 1'b0;
        end else if (flush_ex) begin
            ex_mem_valid <= 1'b0;
        end else if (!stall_mem) begin
            if (exu_out_valid) begin
                ex_mem_valid <= 1'b1;
                ex_mem_pc <= exu_out_pc;
                ex_mem_inst <= exu_out_inst;
                ex_mem_alu_result <= exu_out_alu_result;
                ex_mem_rs2_data <= exu_out_rs2_data;
                ex_mem_rd <= exu_out_rd;
                ex_mem_funct3 <= exu_out_funct3;
                ex_mem_reg_wen <= exu_out_reg_wen;
                ex_mem_mem_ren <= exu_out_mem_ren;
                ex_mem_mem_wen <= exu_out_mem_wen;
                ex_mem_is_system <= exu_out_is_system;
                ex_mem_is_csr <= exu_out_is_csr;
                ex_mem_csr_rdata <= exu_out_csr_rdata;
                ex_mem_csr_wdata <= exu_out_csr_wdata;
                ex_mem_csr_wen <= exu_out_csr_wen;
                ex_mem_ebreak <= exu_ebreak;
                ex_mem_ecall <= exu_ecall;
                ex_mem_mret <= exu_mret;
            end else begin
                ex_mem_valid <= 1'b0;
            end
        end
    end
    
    // ========== MEM 阶段逻辑 ==========
    
    // LSU 输入控制
    wire lsu_in_valid = ex_mem_valid;
    
    // MEM/WB 级间寄存器更新
    // 使用握手协议：lsu_out_valid && wbu_in_ready 表示数据被消费
    wire mem_wb_handshake = mem_wb_valid && wbu_in_ready;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_valid <= 1'b0;
            mem_wb_pc <= 32'h0;
            mem_wb_inst <= 32'h0;
            mem_wb_result <= 32'h0;
            mem_wb_rd <= 5'h0;
            mem_wb_reg_wen <= 1'b0;
            mem_wb_is_csr <= 1'b0;
            mem_wb_csr_wdata <= 32'h0;
            mem_wb_csr_wen <= 1'b0;
            mem_wb_csr_addr <= 12'h0;
            mem_wb_ebreak <= 1'b0;
            mem_wb_ecall <= 1'b0;
            mem_wb_mret <= 1'b0;
        end else begin
            // 先处理数据被消费的情况
            if (mem_wb_handshake) begin
                mem_wb_valid <= 1'b0;
            end
            
            // 然后处理新数据
            if (lsu_out_valid && (!mem_wb_valid || mem_wb_handshake)) begin
                // 只有在当前没有有效数据，或者数据刚被消费时，才更新
                mem_wb_valid <= 1'b1;
                mem_wb_pc <= lsu_out_pc;
                mem_wb_inst <= lsu_out_inst;
                mem_wb_result <= lsu_out_result;
                mem_wb_rd <= lsu_out_rd;
                mem_wb_reg_wen <= lsu_out_reg_wen;
                mem_wb_is_csr <= lsu_out_is_csr;
                mem_wb_csr_wdata <= lsu_out_csr_wdata;
                mem_wb_csr_wen <= lsu_out_csr_wen;
                mem_wb_csr_addr <= lsu_out_csr_addr;
                mem_wb_ebreak <= lsu_out_ebreak;
                mem_wb_ecall <= lsu_out_ecall;
                mem_wb_mret <= lsu_out_mret;
            end
        end
    end
    
    // ========== WB 阶段逻辑 ==========
    
    // WBU 输入控制
    wire wbu_in_valid = mem_wb_valid;
    wire wbu_in_ready;
    
    // ========== 模块实例化 ==========
    
    // IDU (组合逻辑译码)
    IDU u_idu (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (idu_in_valid),
        .in_ready    (idu_in_ready),
        .in_pc       (if_id_pc),
        .in_inst     (if_id_inst),
        .out_valid   (idu_out_valid),
        .out_ready   (1'b1),  // EX 阶段总是准备接收
        .out_pc      (idu_out_pc),
        .out_inst    (idu_out_inst),
        .out_rs1_data(idu_out_rs1_data),
        .out_rs2_data(idu_out_rs2_data),
        .out_imm     (idu_out_imm),
        .out_rd      (idu_out_rd),
        .out_rs1     (idu_out_rs1),
        .out_rs2     (idu_out_rs2),
        .out_opcode  (idu_out_opcode),
        .out_funct3  (idu_out_funct3),
        .out_funct7  (idu_out_funct7),
        .out_reg_wen (idu_out_reg_wen),
        .out_mem_ren (idu_out_mem_ren),
        .out_mem_wen (idu_out_mem_wen),
        .out_is_branch(idu_out_is_branch),
        .out_is_jal  (idu_out_is_jal),
        .out_is_jalr (idu_out_is_jalr),
        .out_is_lui  (idu_out_is_lui),
        .out_is_auipc(idu_out_is_auipc),
        .out_is_system(idu_out_is_system),
        .out_is_fence(idu_out_is_fence),
        .out_is_csr  (idu_out_is_csr),
        .rf_wen      (wbu_rf_wen),
        .rf_waddr    (wbu_rf_waddr),
        .rf_wdata    (wbu_rf_wdata),
        // 转发路径
        .ex_valid    (id_ex_valid),
        .ex_reg_wen  (id_ex_reg_wen),
        .ex_rd       (id_ex_rd),
        .ex_result   (exu_out_alu_result),
        .mem_valid   (ex_mem_valid),
        .mem_reg_wen (ex_mem_reg_wen),
        .mem_rd      (ex_mem_rd),
        .mem_result  (lsu_out_result),
        .wb_valid    (mem_wb_valid),
        .wb_reg_wen  (mem_wb_reg_wen),
        .wb_rd       (mem_wb_rd),
        .wb_result   (mem_wb_result),
        .flush       (flush_id)
    );
    
    // EXU (组合逻辑执行)
    EXU_pipeline u_exu (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (exu_in_valid),
        .in_ready    (),
        .in_pc       (id_ex_pc),
        .in_inst     (id_ex_inst),
        .in_rs1_data (id_ex_rs1_data),
        .in_rs2_data (id_ex_rs2_data),
        .in_imm      (id_ex_imm),
        .in_rd       (id_ex_rd),
        .in_rs1      (id_ex_rs1),
        .in_rs2      (id_ex_rs2),
        .in_opcode   (id_ex_opcode),
        .in_funct3   (id_ex_funct3),
        .in_funct7   (id_ex_funct7),
        .in_reg_wen  (id_ex_reg_wen),
        .in_mem_ren  (id_ex_mem_ren),
        .in_mem_wen  (id_ex_mem_wen),
        .in_is_branch(id_ex_is_branch),
        .in_is_jal   (id_ex_is_jal),
        .in_is_jalr  (id_ex_is_jalr),
        .in_is_lui   (id_ex_is_lui),
        .in_is_auipc (id_ex_is_auipc),
        .in_is_system(id_ex_is_system),
        .in_is_fence (id_ex_is_fence),
        .in_is_csr   (id_ex_is_csr),
        .out_valid   (exu_out_valid),
        .out_ready   (1'b1),  // MEM 阶段总是准备接收
        .out_pc      (exu_out_pc),
        .out_inst    (exu_out_inst),
        .out_alu_result(exu_out_alu_result),
        .out_rs2_data(exu_out_rs2_data),
        .out_rd      (exu_out_rd),
        .out_funct3  (exu_out_funct3),
        .out_reg_wen (exu_out_reg_wen),
        .out_mem_ren (exu_out_mem_ren),
        .out_mem_wen (exu_out_mem_wen),
        .out_is_system(exu_out_is_system),
        .out_is_csr  (exu_out_is_csr),
        .out_csr_rdata(exu_out_csr_rdata),
        .out_csr_wdata(exu_out_csr_wdata),
        .out_csr_wen (exu_out_csr_wen),
        .out_branch_taken(exu_branch_taken),
        .out_branch_target(exu_branch_target),
        .out_is_jump (exu_is_jump),
        .out_is_fence_out(exu_is_fence),
        .out_ebreak  (exu_ebreak),
        .out_ecall   (exu_ecall),
        .out_mret    (exu_mret),
        .csr_mtvec   (wbu_csr_mtvec),
        .csr_mepc    (wbu_csr_mepc),
        .csr_mcause  (wbu_csr_mcause),
        .csr_mstatus (wbu_csr_mstatus),
        .flush       (flush_ex)
    );
    
    // LSU
    LSU_pipeline u_lsu (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (lsu_in_valid),
        .in_ready    (),
        .in_pc       (ex_mem_pc),
        .in_inst     (ex_mem_inst),
        .in_alu_result(ex_mem_alu_result),
        .in_rs2_data (ex_mem_rs2_data),
        .in_rd       (ex_mem_rd),
        .in_funct3   (ex_mem_funct3),
        .in_reg_wen  (ex_mem_reg_wen),
        .in_mem_ren  (ex_mem_mem_ren),
        .in_mem_wen  (ex_mem_mem_wen),
        .in_is_system(ex_mem_is_system),
        .in_is_csr   (ex_mem_is_csr),
        .in_csr_rdata(ex_mem_csr_rdata),
        .in_csr_wdata(ex_mem_csr_wdata),
        .in_csr_wen  (ex_mem_csr_wen),
        .in_ebreak   (ex_mem_ebreak),
        .in_ecall    (ex_mem_ecall),
        .in_mret     (ex_mem_mret),
        .out_valid   (lsu_out_valid),
        .out_ready   (1'b1),  // WB 阶段总是准备接收
        .out_pc      (lsu_out_pc),
        .out_inst    (lsu_out_inst),
        .out_result  (lsu_out_result),
        .out_rd      (lsu_out_rd),
        .out_reg_wen (lsu_out_reg_wen),
        .out_is_csr  (lsu_out_is_csr),
        .out_csr_wdata(lsu_out_csr_wdata),
        .out_csr_wen (lsu_out_csr_wen),
        .out_csr_addr(lsu_out_csr_addr),
        .out_ebreak  (lsu_out_ebreak),
        .out_ecall   (lsu_out_ecall),
        .out_mret    (lsu_out_mret),
        .mem_req     (lsu_req),
        .mem_wen     (lsu_wen),
        .mem_addr    (lsu_addr),
        .mem_wdata   (lsu_wdata),
        .mem_wmask   (lsu_wmask),
        .mem_rvalid  (lsu_rvalid),
        .mem_rdata   (lsu_rdata),
        .flush       (1'b0)
    );
    
    // WBU
    WBU u_wbu (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (wbu_in_valid),
        .in_ready    (wbu_in_ready),
        .in_pc       (mem_wb_pc),
        .in_inst     (mem_wb_inst),
        .in_result   (mem_wb_result),
        .in_rd       (mem_wb_rd),
        .in_reg_wen  (mem_wb_reg_wen),
        .in_is_csr   (mem_wb_is_csr),
        .in_csr_wdata(mem_wb_csr_wdata),
        .in_csr_wen  (mem_wb_csr_wen),
        .in_csr_addr (mem_wb_csr_addr),
        .in_ebreak   (mem_wb_ebreak),
        .in_ecall    (mem_wb_ecall),
        .in_mret     (mem_wb_mret),
        .rf_wen      (wbu_rf_wen),
        .rf_waddr    (wbu_rf_waddr),
        .rf_wdata    (wbu_rf_wdata),
        .csr_mtvec   (wbu_csr_mtvec),
        .csr_mepc    (wbu_csr_mepc),
        .csr_mcause  (wbu_csr_mcause),
        .csr_mstatus (wbu_csr_mstatus),
        .exception_valid(wbu_exception_valid),
        .exception_target(wbu_exception_target),
        .ebreak_flag (wbu_ebreak_flag),
        .exit_code   (wbu_exit_code),
        .inst_commit (wbu_inst_commit),
        .commit_pc   (wbu_commit_pc)
`ifdef SIMULATION
        ,
        .perf_minstret(perf_minstret),
        .perf_mcycle (perf_mcycle)
`endif
    );
    
    // ========== 输出 ==========
    assign ebreak_flag = wbu_ebreak_flag;
    assign exit_code   = wbu_exit_code;

`ifdef SIMULATION
    // Debug: 简化输出
    reg [63:0] dbg_cycle;
    reg [63:0] dbg_commit_cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_cycle <= 0;
            dbg_commit_cnt <= 0;
        end else begin
            dbg_cycle <= dbg_cycle + 1;
            if (wbu_inst_commit) dbg_commit_cnt <= dbg_commit_cnt + 1;
            // 每 100K 周期打印一次
            if (dbg_cycle[16:0] == 0) begin
                $display("[PIPE@%0d] pc=%h commits=%0d",
                         dbg_cycle, pc, dbg_commit_cnt);
            end
        end
    end
`endif

endmodule
