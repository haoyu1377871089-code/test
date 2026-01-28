// IDU: Instruction Decode Unit (指令译码单元)
// 
// 职责:
// - 指令字段解码 (opcode, funct3, funct7, rd, rs1, rs2)
// - 立即数生成和符号扩展
// - 控制信号生成
// - 寄存器文件读取
//
// 阶段 2: 组合逻辑实现，级间寄存器在顶层

module IDU (
    input         clk,
    input         rst,
    
    // 上游接口 (from IF/ID 级间寄存器)
    input         in_valid,
    output        in_ready,
    input  [31:0] in_pc,
    input  [31:0] in_inst,
    
    // 下游接口 (to ID/EX 级间寄存器)
    output        out_valid,
    input         out_ready,
    output [31:0] out_pc,
    output [31:0] out_inst,
    output [31:0] out_rs1_data,
    output [31:0] out_rs2_data,
    output [31:0] out_imm,
    output [4:0]  out_rd,
    output [4:0]  out_rs1,
    output [4:0]  out_rs2,
    
    // 控制信号
    output [6:0]  out_opcode,
    output [2:0]  out_funct3,
    output [6:0]  out_funct7,
    output        out_reg_wen,      // 寄存器写使能
    output        out_mem_ren,      // 内存读使能 (load)
    output        out_mem_wen,      // 内存写使能 (store)
    output        out_is_branch,    // 是否为分支指令
    output        out_is_jal,       // 是否为 JAL
    output        out_is_jalr,      // 是否为 JALR
    output        out_is_lui,       // 是否为 LUI
    output        out_is_auipc,     // 是否为 AUIPC
    output        out_is_system,    // 是否为 SYSTEM 指令
    output        out_is_fence,     // 是否为 FENCE/FENCE.I
    output        out_is_csr,       // 是否为 CSR 指令
    
    // a0 寄存器值 (用于 ebreak exit_code)
    output [31:0] out_a0_data,
    
    // 寄存器文件写回接口 (from WBU)
    input         rf_wen,
    input  [4:0]  rf_waddr,
    input  [31:0] rf_wdata,
    
    // 冲刷信号
    input         flush
);

    // ========== 指令字段解码 ==========
    wire [6:0] opcode = in_inst[6:0];
    wire [2:0] funct3 = in_inst[14:12];
    wire [6:0] funct7 = in_inst[31:25];
    wire [4:0] rd     = in_inst[11:7];
    wire [4:0] rs1    = in_inst[19:15];
    wire [4:0] rs2    = in_inst[24:20];
    
    // ========== 立即数解码 ==========
    wire [11:0] imm_i = in_inst[31:20];
    wire [11:0] imm_s = {in_inst[31:25], in_inst[11:7]};
    wire [12:0] imm_b = {in_inst[31], in_inst[7], in_inst[30:25], in_inst[11:8], 1'b0};
    wire [31:0] imm_u = {in_inst[31:12], 12'b0};
    wire [20:0] imm_j = {in_inst[31], in_inst[19:12], in_inst[20], in_inst[30:21], 1'b0};
    
    // 符号扩展
    wire [31:0] imm_i_sext = {{20{imm_i[11]}}, imm_i};
    wire [31:0] imm_s_sext = {{20{imm_s[11]}}, imm_s};
    wire [31:0] imm_b_sext = {{19{imm_b[12]}}, imm_b};
    wire [31:0] imm_j_sext = {{11{imm_j[20]}}, imm_j};
    
    // ========== 指令类型判断 ==========
    wire is_r_type   = (opcode == 7'b0110011);  // R-type ALU
    wire is_i_alu    = (opcode == 7'b0010011);  // I-type ALU
    wire is_load     = (opcode == 7'b0000011);  // Load
    wire is_store    = (opcode == 7'b0100011);  // Store
    wire is_branch   = (opcode == 7'b1100011);  // Branch
    wire is_jal      = (opcode == 7'b1101111);  // JAL
    wire is_jalr     = (opcode == 7'b1100111);  // JALR
    wire is_lui      = (opcode == 7'b0110111);  // LUI
    wire is_auipc    = (opcode == 7'b0010111);  // AUIPC
    wire is_system   = (opcode == 7'b1110011);  // SYSTEM (ECALL/EBREAK/CSR)
    wire is_fence    = (opcode == 7'b0001111);  // FENCE/FENCE.I
    
    // CSR 指令判断
    wire is_csr = is_system && (funct3 != 3'b000);  // funct3=000 是 ECALL/EBREAK
    
    // ========== 立即数选择 ==========
    reg [31:0] imm_sel;
    always @(*) begin
        case (opcode)
            7'b0010011: imm_sel = imm_i_sext;  // I-type ALU
            7'b0000011: imm_sel = imm_i_sext;  // Load
            7'b1100111: imm_sel = imm_i_sext;  // JALR
            7'b0100011: imm_sel = imm_s_sext;  // Store
            7'b1100011: imm_sel = imm_b_sext;  // Branch
            7'b0110111: imm_sel = imm_u;       // LUI
            7'b0010111: imm_sel = imm_u;       // AUIPC
            7'b1101111: imm_sel = imm_j_sext;  // JAL
            7'b1110011: imm_sel = imm_i_sext;  // CSR (immediate is CSR address)
            default:    imm_sel = 32'h0;
        endcase
    end
    
    // ========== 寄存器文件 ==========
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] a0_data;  // a0 (x10) 寄存器值，用于 ebreak exit_code
    
    RegisterFile #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) u_regfile (
        .clk    (clk),
        .rst    (rst),
        .wdata  (rf_wdata),
        .waddr  (rf_waddr),
        .wen    (rf_wen),
        .raddr1 (rs1),
        .rdata1 (rs1_data),
        .raddr2 (rs2),
        .rdata2 (rs2_data),
        .raddr3 (5'd10),   // 始终读取 x10 (a0)
        .rdata3 (a0_data)
    );
    
    // ========== 控制信号生成 ==========
    wire reg_wen = is_r_type || is_i_alu || is_load || is_jal || is_jalr || 
                   is_lui || is_auipc || is_csr;
    
    // ========== 组合逻辑输出 ==========
    // 有效性: 输入有效且没有冲刷
    assign out_valid = in_valid && !flush;
    
    // 握手: 组合逻辑总是准备好
    assign in_ready = out_ready;
    
    // 直接输出解码结果
    assign out_pc       = in_pc;
    assign out_inst     = in_inst;
    assign out_rs1_data = rs1_data;
    assign out_rs2_data = rs2_data;
    assign out_imm      = imm_sel;
    assign out_rd       = rd;
    assign out_rs1      = rs1;
    assign out_rs2      = rs2;
    assign out_opcode   = opcode;
    assign out_funct3   = funct3;
    assign out_funct7   = funct7;
    assign out_reg_wen  = reg_wen;
    assign out_mem_ren  = is_load;
    assign out_mem_wen  = is_store;
    assign out_is_branch= is_branch;
    assign out_is_jal   = is_jal;
    assign out_is_jalr  = is_jalr;
    assign out_is_lui   = is_lui;
    assign out_is_auipc = is_auipc;
    assign out_is_system= is_system;
    assign out_is_fence = is_fence;
    assign out_is_csr   = is_csr;
    assign out_a0_data  = a0_data;  // 传递 a0 寄存器值

endmodule
