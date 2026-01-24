// 执行单元 (Execution Unit)
// 当前为单体设计，后续可分解为：
// - IDU: 指令译码单元 (Instruction Decode Unit)
// - ALU: 算术逻辑单元 (Arithmetic Logic Unit) 
// - LSU: 访存单元 (Load Store Unit)
// - CSR: 控制状态寄存器单元 (Control Status Register Unit)
// - BRU: 分支单元 (Branch Unit)
module EXU (
    input clk,
    input rst,
    input [31:0] op,      
    input op_en,          // 只会置于1一周期
    input [31:0] pc,      // 当前指令的PC
    
    output reg ex_end,    // 在处理结束时使得ex_end=!ex_end
    output reg [31:0] next_pc, // 下一条指令的PC
    output reg branch_taken,   // 分支是否taken
    output reg ebreak_flag,     // ebreak 指令执行标志
    output reg [31:0] exit_code, // 添加退出码输出
    
    // LSU SRAM接口
    output reg lsu_req,        // LSU访存请求
    output reg lsu_wen,        // LSU写使能
    output reg [31:0] lsu_addr, // LSU地址
    output reg [31:0] lsu_wdata, // LSU写数据
    output reg [3:0] lsu_wmask,  // LSU写掩码
    input lsu_rvalid,          // LSU读数据有效
    input [31:0] lsu_rdata,    // LSU读数据
    
    // 寄存器接口用于DiffTest
    output [31:0] regs [0:31]
);
    
    // 定义寄存器和信号
    reg [31:0] wdata;
    reg [4:0] waddr;  
    reg wen;//write_en
    reg [4:0] raddr1;
    reg [4:0] raddr2;
    wire [31:0] rdata1;
    wire [31:0] rdata2;
    
    // ========== CSR寄存器模块 ==========
    // CSR寄存器定义
    reg [31:0] mtvec;   // 机器模式异常向量基址
    reg [31:0] mepc;    // 机器模式异常程序计数器
    reg [31:0] mcause;  // 机器模式异常原因
    reg [31:0] mstatus; // 机器模式状态寄存器
    
    // CSR相关信号
    reg csr_wen;        // CSR写使能
    reg [31:0] csr_wdata; // CSR写数据
    reg [31:0] csr_rdata; // CSR读数据
    wire [11:0] csr_addr = op[31:20]; // CSR地址
    
    // ========== 性能计数器 (仅仿真) ==========
`ifdef SIMULATION
    reg [63:0] perf_mcycle;      // 总周期数
    reg [63:0] perf_minstret;    // 退休指令数
    // 指令类型计数器
    reg [63:0] perf_alu_r_cnt;   // R型ALU指令
    reg [63:0] perf_alu_i_cnt;   // I型ALU指令
    reg [63:0] perf_load_cnt;    // Load指令
    reg [63:0] perf_store_cnt;   // Store指令
    reg [63:0] perf_branch_cnt;  // 分支指令
    reg [63:0] perf_branch_taken_cnt; // 分支taken次数
    reg [63:0] perf_jal_cnt;     // JAL指令
    reg [63:0] perf_jalr_cnt;    // JALR指令
    reg [63:0] perf_lui_cnt;     // LUI指令
    reg [63:0] perf_auipc_cnt;   // AUIPC指令
    reg [63:0] perf_csr_cnt;     // CSR指令
    reg [63:0] perf_system_cnt;  // SYSTEM指令 (ecall/ebreak/mret)
    reg [63:0] perf_fence_cnt;   // FENCE指令
    // EXU状态统计
    reg [63:0] perf_exu_idle_cycles;   // EXU空闲周期
    reg [63:0] perf_exu_exec_cycles;   // EXU执行周期
    reg [63:0] perf_exu_wait_lsu_cycles; // EXU等待LSU周期
`endif
    
    // ========== 指令译码模块 (IDU) ==========
    // 操作码和功能码提取
    wire [6:0] opcode = op[6:0];
    wire [2:0] funct3 = op[14:12];
    wire [6:0] funct7 = op[31:25];
    wire [4:0] rd = op[11:7];     // 目标寄存器
    wire [4:0] rs1 = op[19:15];   // 源寄存器1
    wire [4:0] rs2 = op[24:20];   // 源寄存器2
    
    // 各类型立即数解码
    wire [11:0] imm_i = op[31:20];                      // I型立即数
    wire [11:0] imm_s = {op[31:25], op[11:7]};          // S型立即数
    wire [12:0] imm_b = {op[31], op[7], op[30:25], op[11:8], 1'b0}; // B型立即数
    wire [31:0] imm_u = {op[31:12], 12'b0};             // U型立即数
    wire [20:0] imm_j = {op[31], op[19:12], op[20], op[30:21], 1'b0}; // J型立即数
    
    // 扩展后的立即数
    wire [31:0] imm_i_sext = {{20{imm_i[11]}}, imm_i};
    wire [31:0] imm_s_sext = {{20{imm_s[11]}}, imm_s};
    wire [31:0] imm_b_sext = {{19{imm_b[12]}}, imm_b};
    wire [31:0] imm_j_sext = {{11{imm_j[20]}}, imm_j};
      
    // 存储指令地址偏移（用于字节/半字写入时选择正确的字节位置）
    wire [31:0] store_addr_full = rdata1 + imm_s_sext;
    wire [1:0] store_addr_offset = store_addr_full[1:0];
      
    // ========== 分支单元 (BRU) ==========
    
    // 指令状态
    reg [2:0] state;
    parameter IDLE = 3'b000;
    parameter DECODE = 3'b001;
    parameter EXECUTE = 3'b010;
    parameter MEMORY = 3'b011;
    parameter WAIT_LSU = 3'b100;
    parameter WRITEBACK = 3'b101;

    // 组合分支条件（避免在时序块里先非阻塞赋值再使用造成时序问题）
    wire branch_cond = (funct3 == 3'b000) ? (rdata1 == rdata2) :
                       (funct3 == 3'b001) ? (rdata1 != rdata2) :
                       (funct3 == 3'b100) ? ($signed(rdata1) < $signed(rdata2)) :
                       (funct3 == 3'b101) ? ($signed(rdata1) >= $signed(rdata2)) :
                       (funct3 == 3'b110) ? (rdata1 < rdata2) :
                       (funct3 == 3'b111) ? (rdata1 >= rdata2) :
                       1'b0;
    
    // ========== 寄存器文件 ==========
    
    // 修改寄存器状态检查方法
    // 由于无法直接访问i0.regs，我们使用32个单独的wire来获取寄存器值
    wire [31:0] reg_values [0:31];
    
    // ========== 访存单元 (LSU) ==========
    // 内存访问临时存储
    reg [31:0] mem_result;
    
    // ========== CSR读逻辑 ==========
    // CSR读逻辑（组合逻辑）
    always @(*) begin
        case (csr_addr)
            12'h305: csr_rdata = mtvec;   // mtvec
            12'h341: csr_rdata = mepc;    // mepc  
            12'h342: csr_rdata = mcause;  // mcause
            12'h300: csr_rdata = mstatus; // mstatus
            12'hF11: csr_rdata = 32'h79737978; // mvendorid - "ysyx" ASCII
            12'hF12: csr_rdata = 32'h00000000; // marchid - 学号数字部分 (0)
            default: csr_rdata = 32'h0;
        endcase
    end
    
    // 修改后的寄存器文件实例化，添加寄存器值输出
    RegisterFile #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) i0 (
        .clk(clk),
        .rst(rst),
        .wdata(wdata),
        .waddr(waddr),
        .wen(wen),
        .raddr1(raddr1),
        .rdata1(rdata1),
        .raddr2(raddr2),
        .rdata2(rdata2),
        .reg_values(reg_values)  // 添加这一行用于获取所有寄存器值
    );
    
    // ========== 算术逻辑单元 (ALU) + 控制状态寄存器单元 (CSR) ==========
    
    // ========== 主控制单元 ==========
    // 指令执行状态机
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            ex_end <= 0;
            wen <= 0;
            branch_taken <= 0;
            next_pc <= 0;
            lsu_req <= 0;
            lsu_wen <= 0;
            ebreak_flag <= 0;
            
            // 初始化CSR寄存器
            mtvec <= 32'h80000000;  // 异常向量基址
            mepc <= 32'h0;          // 异常程序计数器
            mcause <= 32'h0;        // 异常原因
            mstatus <= 32'h0;       // 状态寄存器
            csr_wen <= 0;
`ifdef SIMULATION
            // 初始化性能计数器
            perf_mcycle <= 64'h0;
            perf_minstret <= 64'h0;
            perf_alu_r_cnt <= 64'h0;
            perf_alu_i_cnt <= 64'h0;
            perf_load_cnt <= 64'h0;
            perf_store_cnt <= 64'h0;
            perf_branch_cnt <= 64'h0;
            perf_branch_taken_cnt <= 64'h0;
            perf_jal_cnt <= 64'h0;
            perf_jalr_cnt <= 64'h0;
            perf_lui_cnt <= 64'h0;
            perf_auipc_cnt <= 64'h0;
            perf_csr_cnt <= 64'h0;
            perf_system_cnt <= 64'h0;
            perf_fence_cnt <= 64'h0;
            perf_exu_idle_cycles <= 64'h0;
            perf_exu_exec_cycles <= 64'h0;
            perf_exu_wait_lsu_cycles <= 64'h0;
`endif
        end else begin
`ifdef SIMULATION
            // 周期计数器每周期递增
            perf_mcycle <= perf_mcycle + 1;
            // 状态周期统计
            case (state)
                IDLE: perf_exu_idle_cycles <= perf_exu_idle_cycles + 1;
                DECODE, EXECUTE, WRITEBACK: perf_exu_exec_cycles <= perf_exu_exec_cycles + 1;
                WAIT_LSU: perf_exu_wait_lsu_cycles <= perf_exu_wait_lsu_cycles + 1;
                default: ;
            endcase
`endif
            case (state)
                IDLE: begin
                    if (op_en) begin
                        state <= DECODE;
                        wen <= 0;
                        branch_taken <= 0;
                        
                        lsu_req <= 0;
                        lsu_wen <= 0;
                        ebreak_flag <= 0;  // 清除 ebreak 标志
                        csr_wen <= 0;      // 清除CSR写使能
                    end
                end
                
                DECODE: begin
                    raddr1 <= rs1[4:0]; 
                    raddr2 <= rs2[4:0];
                    state <= EXECUTE;
                end
                
                EXECUTE: begin
                    case (opcode)
                        // R型指令 - 寄存器-寄存器运算
                        7'b0110011: begin
                            waddr <= rd[4:0];
                            wen <= 1;
                            next_pc <= pc + 4; // 默认PC+4
                            
                            case ({funct7, funct3})
                                // ADD
                                10'b0000000_000: wdata <= rdata1 + rdata2;
                                // SUB
                                10'b0100000_000: wdata <= rdata1 - rdata2;
                                // SLL
                                10'b0000000_001: wdata <= rdata1 << rdata2[4:0];
                                // SLT
                                10'b0000000_010: wdata <= ($signed(rdata1) < $signed(rdata2)) ? 32'b1 : 32'b0;
                                // SLTU
                                10'b0000000_011: wdata <= (rdata1 < rdata2) ? 32'b1 : 32'b0;
                                // XOR
                                10'b0000000_100: wdata <= rdata1 ^ rdata2;
                                // SRL
                                10'b0000000_101: wdata <= rdata1 >> rdata2[4:0];
                                // SRA
                                10'b0100000_101: wdata <= $signed(rdata1) >>> rdata2[4:0];
                                // OR
                                10'b0000000_110: wdata <= rdata1 | rdata2;
                                // AND
                                10'b0000000_111: wdata <= rdata1 & rdata2;
                                default: wen <= 0;
                            endcase
                            state <= WRITEBACK;
                        end
                        
                        // I型指令 - 立即数运算
                        7'b0010011: begin
                            waddr <= rd[4:0];
                            wen <= 1;
                            next_pc <= pc + 4; // 默认PC+4
                            case (funct3)
                                // ADDI
                                3'b000: wdata <= rdata1 + imm_i_sext;
                                // SLTI
                                3'b010: wdata <= ($signed(rdata1) < $signed(imm_i_sext)) ? 32'b1 : 32'b0;
                                // SLTIU
                                3'b011: wdata <= (rdata1 < imm_i_sext) ? 32'b1 : 32'b0;
                                // XORI
                                3'b100: wdata <= rdata1 ^ imm_i_sext;
                                // ORI
                                3'b110: wdata <= rdata1 | imm_i_sext;
                                // ANDI
                                3'b111: wdata <= rdata1 & imm_i_sext;
                                // SLLI
                                3'b001: wdata <= rdata1 << imm_i[4:0];
                                // SRLI/SRAI
                                3'b101: begin
                                    if (imm_i[11:5] == 7'b0000000)
                                        wdata <= rdata1 >> imm_i[4:0]; // SRLI
                                    else if (imm_i[11:5] == 7'b0100000)
                                        wdata <= $signed(rdata1) >>> imm_i[4:0]; // SRAI
                                    else
                                        wen <= 0;
                                end
                                default: wen <= 0;
                            endcase
                            state <= WRITEBACK;
                        end
                        
                        // 加载指令
                        7'b0000011: begin
                            lsu_addr <= rdata1 + imm_i_sext;
                            lsu_req <= 1;
                            lsu_wen <= 0; // 读操作
                            waddr <= rd[4:0];
                            wen <= 1;
                            next_pc <= pc + 4; // 默认PC+4
                            case (funct3)
                                // LB, LH, LW, LBU, LHU
                                3'b000: lsu_wmask <= 4'b0001; // LB
                                3'b001: lsu_wmask <= 4'b0011; // LH
                                3'b010: lsu_wmask <= 4'b1111; // LW
                                3'b100: lsu_wmask <= 4'b0001; // LBU
                                3'b101: lsu_wmask <= 4'b0011; // LHU
                                default: begin
                                    lsu_req <= 0;
                                    wen <= 0;
                                end
                            endcase
                            state <= WAIT_LSU;
                        end
                        
                        // 存储指令
                        7'b0100011: begin
                            lsu_addr <= rdata1 + imm_s_sext;
                            lsu_req <= 1;
                            lsu_wen <= 1; // 写操作
                            next_pc <= pc + 4; // 默认PC+4
                            case (funct3)
                                // SB: 写入从 lsu_addr 起始的1字节
                                // 根据地址低2位偏移 wmask 和 wdata
                                3'b000: begin
                                    case (store_addr_offset)
                                        2'b00: begin lsu_wmask <= 4'b0001; lsu_wdata <= rdata2; end
                                        2'b01: begin lsu_wmask <= 4'b0010; lsu_wdata <= rdata2 << 8; end
                                        2'b10: begin lsu_wmask <= 4'b0100; lsu_wdata <= rdata2 << 16; end
                                        2'b11: begin lsu_wmask <= 4'b1000; lsu_wdata <= rdata2 << 24; end
                                    endcase
                                end
                                // SH: 写入从 lsu_addr 起始的2字节
                                // 根据地址低2位偏移 wmask 和 wdata
                                3'b001: begin
                                    case (store_addr_offset)
                                        2'b00: begin lsu_wmask <= 4'b0011; lsu_wdata <= rdata2; end
                                        2'b10: begin lsu_wmask <= 4'b1100; lsu_wdata <= rdata2 << 16; end
                                        default: begin lsu_wmask <= 4'b0011; lsu_wdata <= rdata2; end // 非对齐按对齐处理
                                    endcase
                                end
                                // SW: 写入从 lsu_addr 起始的4字节
                                3'b010: begin lsu_wmask <= 4'b1111; lsu_wdata <= rdata2; end
                                default: lsu_req <= 0;
                            endcase
                            state <= WRITEBACK; // 写操作不需要等待
                        end
                        
                        // 分支指令
                        7'b1100011: begin
                            // 使用组合信号 branch_cond 计算分支结果，避免 non-blocking 更新顺序问题
                            branch_taken <= branch_cond;
                            // imm_b_sext 已按 B 型立即数符号扩展
                            next_pc <= branch_cond ? (pc + imm_b_sext) : (pc + 4);

                            state <= WRITEBACK;
                        end
                        
                        // JAL
                        7'b1101111: begin
                            waddr <= rd[4:0];
                            wdata <= pc + 4;
                            wen <= 1;
                            next_pc <= pc + imm_j_sext;
                            branch_taken <= 1;
                            state <= WRITEBACK;
                        end
                        
                        // JALR
                        7'b1100111: begin
                            if (funct3 == 3'b000) begin
                                waddr <= rd[4:0];
                                wdata <= pc + 4;
                                wen <= 1;
                                next_pc <= (rdata1 + imm_i_sext) & 32'hFFFFFFFE;
                                branch_taken <= 1;
                            end
                            state <= WRITEBACK;
                        end
                        
                        // LUI
                        7'b0110111: begin
                            waddr <= rd[4:0];
                            wdata <= imm_u;
                            wen <= 1;
                            state <= WRITEBACK;
                            next_pc <= pc + 4; // 默认PC+4
                        end
                        
                        // AUIPC
                        7'b0010111: begin
                            waddr <= rd[4:0];
                            wdata <= pc + imm_u;
                            wen <= 1;
                            state <= WRITEBACK;
                            next_pc <= pc + 4; // 默认PC+4
                        end
                        
                        // MISC-MEM 指令 (FENCE, FENCE.I)
                        // 在简单实现中，这些指令只需要作为 NOP 处理
                        // 因为我们是单核顺序执行，没有乱序执行或缓存
                        7'b0001111: begin
                            wen <= 0;  // 不写寄存器
                            next_pc <= pc + 4;
                            state <= WRITEBACK;
                        end
                        
                        // SYSTEM 指令 (包含 ebreak, ecall, mret, CSR指令)
                        7'b1110011: begin
                            case (funct3)
                                3'b000: begin // 特权指令
                                    case (imm_i)
                                        12'h001: begin // ebreak
                                            ebreak_flag <= 1;
                                            exit_code <= reg_values[10];
                                            next_pc <= pc + 4;
                                        end
                                        12'h000: begin // ecall
                                            // 保存异常上下文
                                            mepc <= pc;
                                            mcause <= 32'd11; // Environment call from M-mode
                                            // 跳转到异常处理程序
                                            next_pc <= mtvec;
                                        end
                                        12'h302: begin // mret
                                            // 从异常返回
                                            next_pc <= mepc;
                                        end
                                        default: next_pc <= pc + 4;
                                    endcase
                                end
                                3'b001: begin // csrrw - CSR Read and Write
                                    waddr <= rd[4:0];
                                    wdata <= csr_rdata; // 读取CSR值到rd
                                    wen <= (rd != 5'b0); // 只有rd不为0时才写入
                                    csr_wdata <= rdata1; // rs1的值写入CSR
                                    csr_wen <= 1;
                                    next_pc <= pc + 4;
                                end
                                3'b010: begin // csrrs - CSR Read and Set
                                    waddr <= rd[4:0];
                                    wdata <= csr_rdata; // 读取CSR值到rd
                                    wen <= (rd != 5'b0); // 只有rd不为0时才写入
                                    csr_wdata <= csr_rdata | rdata1; // 设置位
                                    csr_wen <= (rs1 != 5'b0); // 只有rs1不为0时才写入CSR
                                    next_pc <= pc + 4;
                                end
                                3'b011: begin // csrrc - CSR Read and Clear
                                    waddr <= rd[4:0];
                                    wdata <= csr_rdata; // 读取CSR值到rd
                                    wen <= (rd != 5'b0); // 只有rd不为0时才写入
                                    csr_wdata <= csr_rdata & (~rdata1); // 清除位
                                    csr_wen <= (rs1 != 5'b0); // 只有rs1不为0时才写入CSR
                                    next_pc <= pc + 4;
                                end
                                default: next_pc <= pc + 4;
                            endcase
                            state <= WRITEBACK;
                        end
                        
                        default: begin
                            wen <= 0;
                            state <= WRITEBACK;
                        end
                    endcase
                    
                end
                
                WAIT_LSU: begin
                    // 清除LSU请求信号
                    lsu_req <= 0;
                    
                    // 等待LSU读数据有效
                    if (lsu_rvalid) begin
                        if (opcode == 7'b0000011) begin // 加载指令
                            case (funct3)
                                // LB: 从 lsu_addr 起始位置取1字节并符号扩展
                                3'b000: begin
                                    wdata <= {{24{lsu_rdata[7]}}, lsu_rdata[7:0]};
                                end
                                // LH: 从 lsu_addr 起始位置取2字节并符号扩展（允许非对齐）
                                3'b001: begin
                                    wdata <= {{16{lsu_rdata[15]}}, lsu_rdata[15:0]};
                                end
                                // LW: 从 lsu_addr 起始位置取4字节（允许非对齐）
                                3'b010: begin
                                    wdata <= lsu_rdata;
                                end
                                // LBU: 从 lsu_addr 起始位置取1字节零扩展
                                3'b100: begin
                                    wdata <= {24'b0, lsu_rdata[7:0]};
                                end
                                // LHU: 从 lsu_addr 起始位置取2字节零扩展（允许非对齐）
                                3'b101: begin
                                    wdata <= {16'b0, lsu_rdata[15:0]};
                                end
                                default: wen <= 0;
                            endcase
                        end
                        state <= WRITEBACK;
                    end
                    // 如果lsu_rvalid为0，继续等待
                end
                
                WRITEBACK: begin
                    // $display("next_pc=0x%x",next_pc);
                    
                    // 清除LSU信号
                    lsu_req <= 0;
                    lsu_wen <= 0;
                    
`ifdef SIMULATION
                    // 性能计数器：统计指令类型
                    perf_minstret <= perf_minstret + 1;
                    case (opcode)
                        7'b0110011: perf_alu_r_cnt <= perf_alu_r_cnt + 1;  // R型ALU
                        7'b0010011: perf_alu_i_cnt <= perf_alu_i_cnt + 1;  // I型ALU
                        7'b0000011: perf_load_cnt <= perf_load_cnt + 1;    // Load
                        7'b0100011: perf_store_cnt <= perf_store_cnt + 1;  // Store
                        7'b1100011: begin  // Branch
                            perf_branch_cnt <= perf_branch_cnt + 1;
                            if (branch_taken) perf_branch_taken_cnt <= perf_branch_taken_cnt + 1;
                        end
                        7'b1101111: perf_jal_cnt <= perf_jal_cnt + 1;      // JAL
                        7'b1100111: perf_jalr_cnt <= perf_jalr_cnt + 1;    // JALR
                        7'b0110111: perf_lui_cnt <= perf_lui_cnt + 1;      // LUI
                        7'b0010111: perf_auipc_cnt <= perf_auipc_cnt + 1;  // AUIPC
                        7'b0001111: perf_fence_cnt <= perf_fence_cnt + 1;  // FENCE
                        7'b1110011: begin  // SYSTEM
                            if (funct3 == 3'b000)
                                perf_system_cnt <= perf_system_cnt + 1;  // ecall/ebreak/mret
                            else
                                perf_csr_cnt <= perf_csr_cnt + 1;  // CSR指令
                        end
                        default: ;
                    endcase
`endif
                    
                    // CSR写入逻辑
                    if (csr_wen) begin
                        case (csr_addr)
                            12'h305: mtvec <= csr_wdata;   // mtvec
                            12'h341: mepc <= csr_wdata;    // mepc
                            12'h342: mcause <= csr_wdata;  // mcause
                            12'h300: mstatus <= csr_wdata; // mstatus
                            default: ; // 其他CSR地址不处理
                        endcase
                        csr_wen <= 0;
                    end
                    
                    state <= IDLE;
                    ex_end <= ~ex_end;  // 指令执行完成，切换ex_end信号
                    wen <= 0;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // 替换有问题的generate块
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : REG_OUTPUT
            assign regs[i] = (i == 0) ? 32'b0 : reg_values[i]; // x0永远为0
        end
    endgenerate
    
endmodule