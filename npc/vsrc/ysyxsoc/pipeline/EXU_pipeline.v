// EXU_pipeline: Execution Unit for Pipeline (执行单元)
// 
// 职责:
// - ALU 运算
// - 分支条件判断
// - 地址计算 (load/store 地址, 分支/跳转目标)
// - CSR 读取
//
// 阶段 2: 组合逻辑实现，级间寄存器在顶层

module EXU_pipeline (
    input         clk,
    input         rst,
    
    // 上游接口 (from ID/EX 级间寄存器)
    input         in_valid,
    output        in_ready,
    input  [31:0] in_pc,
    input  [31:0] in_inst,
    input  [31:0] in_rs1_data,
    input  [31:0] in_rs2_data,
    input  [31:0] in_imm,
    input  [4:0]  in_rd,
    input  [4:0]  in_rs1,
    input  [4:0]  in_rs2,
    input  [6:0]  in_opcode,
    input  [2:0]  in_funct3,
    input  [6:0]  in_funct7,
    input         in_reg_wen,
    input         in_mem_ren,
    input         in_mem_wen,
    input         in_is_branch,
    input         in_is_jal,
    input         in_is_jalr,
    input         in_is_lui,
    input         in_is_auipc,
    input         in_is_system,
    input         in_is_fence,
    input         in_is_csr,
    
    // 下游接口 (to EX/MEM 级间寄存器)
    output        out_valid,
    input         out_ready,
    output [31:0] out_pc,
    output [31:0] out_inst,
    output [31:0] out_alu_result,    // ALU 计算结果
    output [31:0] out_rs2_data,      // store 数据
    output [4:0]  out_rd,
    output [2:0]  out_funct3,
    output        out_reg_wen,
    output        out_mem_ren,
    output        out_mem_wen,
    output        out_is_system,
    output        out_is_csr,
    output [31:0] out_csr_rdata,     // CSR 读取数据
    output [31:0] out_csr_wdata,     // CSR 写入数据
    output        out_csr_wen,       // CSR 写使能
    
    // 分支/跳转结果 (给控制单元)
    output        out_branch_taken,
    output [31:0] out_branch_target,
    output        out_is_jump,       // JAL 或 JALR
    output        out_is_fence_out,
    
    // ebreak 检测
    output        out_ebreak,
    output        out_ecall,
    output        out_mret,
    
    // CSR 寄存器接口 (直接连接 CSR 模块)
    input  [31:0] csr_mtvec,
    input  [31:0] csr_mepc,
    input  [31:0] csr_mcause,
    input  [31:0] csr_mstatus,
    
    // 冲刷信号
    input         flush
);

    // ========== ALU 运算 ==========
    wire [31:0] alu_a = in_rs1_data;
    wire [31:0] alu_b;
    reg  [31:0] alu_result;
    
    // ALU 操作数 B 选择
    wire use_imm = in_opcode == 7'b0010011 ||  // I-type ALU
                   in_opcode == 7'b0000011 ||  // Load
                   in_opcode == 7'b0100011 ||  // Store
                   in_opcode == 7'b1100111;    // JALR
    assign alu_b = use_imm ? in_imm : in_rs2_data;
    
    // ALU 计算
    always @(*) begin
        case (in_opcode)
            // R-type ALU
            7'b0110011: begin
                case ({in_funct7, in_funct3})
                    10'b0000000_000: alu_result = alu_a + alu_b;                        // ADD
                    10'b0100000_000: alu_result = alu_a - alu_b;                        // SUB
                    10'b0000000_001: alu_result = alu_a << alu_b[4:0];                  // SLL
                    10'b0000000_010: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;  // SLT
                    10'b0000000_011: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;      // SLTU
                    10'b0000000_100: alu_result = alu_a ^ alu_b;                        // XOR
                    10'b0000000_101: alu_result = alu_a >> alu_b[4:0];                  // SRL
                    10'b0100000_101: alu_result = $signed(alu_a) >>> alu_b[4:0];        // SRA
                    10'b0000000_110: alu_result = alu_a | alu_b;                        // OR
                    10'b0000000_111: alu_result = alu_a & alu_b;                        // AND
                    default:        alu_result = 32'h0;
                endcase
            end
            // I-type ALU
            7'b0010011: begin
                case (in_funct3)
                    3'b000: alu_result = alu_a + alu_b;                                 // ADDI
                    3'b010: alu_result = ($signed(alu_a) < $signed(alu_b)) ? 32'd1 : 32'd0;  // SLTI
                    3'b011: alu_result = (alu_a < alu_b) ? 32'd1 : 32'd0;               // SLTIU
                    3'b100: alu_result = alu_a ^ alu_b;                                 // XORI
                    3'b110: alu_result = alu_a | alu_b;                                 // ORI
                    3'b111: alu_result = alu_a & alu_b;                                 // ANDI
                    3'b001: alu_result = alu_a << in_imm[4:0];                          // SLLI
                    3'b101: begin
                        if (in_imm[11:5] == 7'b0000000)
                            alu_result = alu_a >> in_imm[4:0];                         // SRLI
                        else
                            alu_result = $signed(alu_a) >>> in_imm[4:0];               // SRAI
                    end
                    default: alu_result = 32'h0;
                endcase
            end
            // Load/Store 地址计算
            7'b0000011,
            7'b0100011: alu_result = alu_a + alu_b;
            // JALR 目标地址计算
            7'b1100111: alu_result = (alu_a + alu_b) & 32'hFFFFFFFE;
            // LUI
            7'b0110111: alu_result = in_imm;
            // AUIPC
            7'b0010111: alu_result = in_pc + in_imm;
            // JAL 返回地址
            7'b1101111: alu_result = in_pc + 32'd4;
            // CSR 指令
            7'b1110011: alu_result = in_pc + 32'd4;
            default:    alu_result = 32'h0;
        endcase
    end
    
    // ========== 分支条件判断 ==========
    reg branch_cond;
    always @(*) begin
        case (in_funct3)
            3'b000: branch_cond = (in_rs1_data == in_rs2_data);                        // BEQ
            3'b001: branch_cond = (in_rs1_data != in_rs2_data);                        // BNE
            3'b100: branch_cond = ($signed(in_rs1_data) < $signed(in_rs2_data));       // BLT
            3'b101: branch_cond = ($signed(in_rs1_data) >= $signed(in_rs2_data));      // BGE
            3'b110: branch_cond = (in_rs1_data < in_rs2_data);                         // BLTU
            3'b111: branch_cond = (in_rs1_data >= in_rs2_data);                        // BGEU
            default: branch_cond = 1'b0;
        endcase
    end
    
    // 只有输入有效时才产生分支信号
    wire branch_taken = in_valid && in_is_branch && branch_cond;
    wire [31:0] branch_target = in_is_jalr ? alu_result :       // JALR: rs1 + imm
                                in_is_jal  ? (in_pc + in_imm) : // JAL: pc + imm
                                             (in_pc + in_imm);  // Branch: pc + imm

// Debug code removed for performance
    
    // ========== CSR 读取 ==========
    wire [11:0] csr_addr = in_imm[11:0];
    reg [31:0] csr_rdata;
    always @(*) begin
        case (csr_addr)
            12'h305: csr_rdata = csr_mtvec;
            12'h341: csr_rdata = csr_mepc;
            12'h342: csr_rdata = csr_mcause;
            12'h300: csr_rdata = csr_mstatus;
            12'hF11: csr_rdata = 32'h79737978;  // mvendorid - "ysyx"
            12'hF12: csr_rdata = 32'h00000000;  // marchid
            default: csr_rdata = 32'h0;
        endcase
    end
    
    // CSR 写数据计算
    reg [31:0] csr_wdata;
    reg csr_wen;
    always @(*) begin
        csr_wen = 1'b0;
        csr_wdata = 32'h0;
        if (in_is_csr) begin
            case (in_funct3)
                3'b001: begin  // CSRRW
                    csr_wen = 1'b1;
                    csr_wdata = in_rs1_data;
                end
                3'b010: begin  // CSRRS
                    csr_wen = (in_rs1 != 5'b0);
                    csr_wdata = csr_rdata | in_rs1_data;
                end
                3'b011: begin  // CSRRC
                    csr_wen = (in_rs1 != 5'b0);
                    csr_wdata = csr_rdata & (~in_rs1_data);
                end
                default: begin
                    csr_wen = 1'b0;
                    csr_wdata = 32'h0;
                end
            endcase
        end
    end
    
    // ========== 特殊指令检测 ==========
    wire is_ebreak = in_is_system && (in_funct3 == 3'b000) && (in_imm[11:0] == 12'h001);
    wire is_ecall  = in_is_system && (in_funct3 == 3'b000) && (in_imm[11:0] == 12'h000);
    wire is_mret   = in_is_system && (in_funct3 == 3'b000) && (in_imm[11:0] == 12'h302);
    
    // ========== 组合逻辑输出 ==========
    assign out_valid = in_valid && !flush;
    assign in_ready = out_ready;
    
    assign out_pc           = in_pc;
    assign out_inst         = in_inst;
    assign out_alu_result   = alu_result;
    assign out_rs2_data     = in_rs2_data;
    assign out_rd           = in_rd;
    assign out_funct3       = in_funct3;
    assign out_reg_wen      = in_reg_wen;
    assign out_mem_ren      = in_mem_ren;
    assign out_mem_wen      = in_mem_wen;
    assign out_is_system    = in_is_system;
    assign out_is_csr       = in_is_csr;
    assign out_csr_rdata    = csr_rdata;
    assign out_csr_wdata    = csr_wdata;
    assign out_csr_wen      = csr_wen;
    assign out_branch_taken = branch_taken;
    assign out_branch_target = branch_target;
    assign out_is_jump      = in_valid && (in_is_jal || in_is_jalr);
    assign out_is_fence_out = in_is_fence;
    assign out_ebreak       = is_ebreak;
    assign out_ecall        = is_ecall;
    assign out_mret         = is_mret;

endmodule
