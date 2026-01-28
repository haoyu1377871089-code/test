// LSU_pipeline: Load Store Unit for Pipeline (访存单元)
// 
// 职责:
// - 发起内存读写请求
// - 处理数据对齐
// - 等待内存响应

module LSU_pipeline (
    input         clk,
    input         rst,
    
    // 上游接口 (from EXU)
    input         in_valid,
    output        in_ready,
    input  [31:0] in_pc,
    input  [31:0] in_inst,
    input  [31:0] in_alu_result,    // 访存地址 或 ALU 结果
    input  [31:0] in_rs2_data,      // store 数据
    input  [4:0]  in_rd,
    input  [2:0]  in_funct3,
    input         in_reg_wen,
    input         in_mem_ren,       // load
    input         in_mem_wen,       // store
    input         in_is_system,
    input         in_is_csr,
    input  [31:0] in_csr_rdata,
    input  [31:0] in_csr_wdata,
    input         in_csr_wen,
    input         in_ebreak,
    input         in_ecall,
    input         in_mret,
    
    // 下游接口 (to WBU)
    output reg    out_valid,
    input         out_ready,
    output [31:0] out_pc,
    output [31:0] out_inst,
    output [31:0] out_result,       // 写回数据 (ALU结果 或 load数据 或 CSR数据)
    output [4:0]  out_rd,
    output        out_reg_wen,
    output        out_is_csr,
    output [31:0] out_csr_wdata,
    output        out_csr_wen,
    output [11:0] out_csr_addr,
    output        out_ebreak,
    output        out_ecall,
    output        out_mret,
    
    // 内存接口
    output reg    mem_req,
    output reg    mem_wen,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [3:0]  mem_wmask,
    input         mem_rvalid,
    input  [31:0] mem_rdata,
    
    // 冲刷信号
    input         flush
);

    // ========== 状态机 ==========
    localparam S_IDLE     = 2'b00;
    localparam S_MEM_REQ  = 2'b01;
    localparam S_MEM_WAIT = 2'b10;
    localparam S_DONE     = 2'b11;
    
    reg [1:0] state;
    reg [31:0] mem_result;
    
    // ========== Store 数据对齐 ==========
    // 使用锁存后的数据
    wire [1:0] addr_offset = alu_result_reg[1:0];
    reg [31:0] store_wdata;
    reg [3:0]  store_wmask;
    
    always @(*) begin
        case (funct3_reg)
            3'b000: begin  // SB
                case (addr_offset)
                    2'b00: begin store_wmask = 4'b0001; store_wdata = rs2_data_reg; end
                    2'b01: begin store_wmask = 4'b0010; store_wdata = rs2_data_reg << 8; end
                    2'b10: begin store_wmask = 4'b0100; store_wdata = rs2_data_reg << 16; end
                    2'b11: begin store_wmask = 4'b1000; store_wdata = rs2_data_reg << 24; end
                endcase
            end
            3'b001: begin  // SH
                case (addr_offset)
                    2'b00: begin store_wmask = 4'b0011; store_wdata = rs2_data_reg; end
                    2'b10: begin store_wmask = 4'b1100; store_wdata = rs2_data_reg << 16; end
                    default: begin store_wmask = 4'b0011; store_wdata = rs2_data_reg; end
                endcase
            end
            3'b010: begin  // SW
                store_wmask = 4'b1111;
                store_wdata = rs2_data_reg;
            end
            default: begin
                store_wmask = 4'b0000;
                store_wdata = 32'h0;
            end
        endcase
    end
    
    // ========== Load 数据提取 ==========
    reg [31:0] load_result;
    always @(*) begin
        case (funct3_reg)
            3'b000: load_result = {{24{mem_rdata[7]}}, mem_rdata[7:0]};   // LB
            3'b001: load_result = {{16{mem_rdata[15]}}, mem_rdata[15:0]}; // LH
            3'b010: load_result = mem_rdata;                              // LW
            3'b100: load_result = {24'b0, mem_rdata[7:0]};                // LBU
            3'b101: load_result = {16'b0, mem_rdata[15:0]};               // LHU
            default: load_result = mem_rdata;
        endcase
    end
    
    // ========== 流水段寄存器 (锁存输入) ==========
    reg [31:0] pc_reg;
    reg [31:0] inst_reg;
    reg [31:0] alu_result_reg;
    reg [31:0] rs2_data_reg;
    reg [4:0]  rd_reg;
    reg [2:0]  funct3_reg;
    reg        reg_wen_reg;
    reg        mem_ren_reg;
    reg        mem_wen_reg;
    reg        is_system_reg;
    reg        is_csr_reg;
    reg [31:0] csr_rdata_reg;
    reg [31:0] csr_wdata_reg;
    reg        csr_wen_reg;
    reg        is_ebreak_reg;
    reg        is_ecall_reg;
    reg        is_mret_reg;
    
    // 输出寄存器
    reg [31:0] result_reg;
    
    // ========== 握手和状态机 ==========
    // 当没有访存请求时，直接传递
    wire need_mem = in_mem_ren || in_mem_wen;
    
    // in_ready: 只有在空闲状态且下游准备好时才能接收
    assign in_ready = (state == S_IDLE) && (out_ready || !out_valid);
    
    // 内存接口连接
    assign mem_addr  = alu_result_reg;
    assign mem_wdata = store_wdata;
    assign mem_wmask = store_wmask;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            out_valid <= 1'b0;
            mem_req <= 1'b0;
            mem_wen <= 1'b0;
            pc_reg <= 32'h0;
            inst_reg <= 32'h0;
            alu_result_reg <= 32'h0;
            rs2_data_reg <= 32'h0;
            rd_reg <= 5'h0;
            funct3_reg <= 3'h0;
            reg_wen_reg <= 1'b0;
            mem_ren_reg <= 1'b0;
            mem_wen_reg <= 1'b0;
            is_system_reg <= 1'b0;
            is_csr_reg <= 1'b0;
            csr_rdata_reg <= 32'h0;
            csr_wdata_reg <= 32'h0;
            csr_wen_reg <= 1'b0;
            is_ebreak_reg <= 1'b0;
            is_ecall_reg <= 1'b0;
            is_mret_reg <= 1'b0;
            result_reg <= 32'h0;
            mem_result <= 32'h0;
        end else if (flush) begin
            state <= S_IDLE;
            out_valid <= 1'b0;
            mem_req <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    // 如果 out_valid 且 out_ready，说明数据已被消费，清零 out_valid
                    if (out_valid && out_ready) begin
                        out_valid <= 1'b0;
                    end
                    // 如果 out_valid 但没有新输入，保持状态等待消费
                    else if (out_valid && !in_valid) begin
                        // 保持 out_valid，等待下游消费
                    end
                    // 接收新输入
                    else if (in_valid && in_ready) begin
                        // 锁存输入
                        pc_reg <= in_pc;
                        inst_reg <= in_inst;
                        alu_result_reg <= in_alu_result;
                        rs2_data_reg <= in_rs2_data;
                        rd_reg <= in_rd;
                        funct3_reg <= in_funct3;
                        reg_wen_reg <= in_reg_wen;
                        mem_ren_reg <= in_mem_ren;
                        mem_wen_reg <= in_mem_wen;
                        is_system_reg <= in_is_system;
                        is_csr_reg <= in_is_csr;
                        csr_rdata_reg <= in_csr_rdata;
                        csr_wdata_reg <= in_csr_wdata;
                        csr_wen_reg <= in_csr_wen;
                        is_ebreak_reg <= in_ebreak;
                        is_ecall_reg <= in_ecall;
                        is_mret_reg <= in_mret;
                        
                        if (in_mem_ren || in_mem_wen) begin
                            // 需要访存
                            state <= S_MEM_REQ;
                            mem_req <= 1'b1;
                            mem_wen <= in_mem_wen;
                            out_valid <= 1'b0;
                        end else begin
                            // 不需要访存，直接传递
                            // 选择写回数据
                            if (in_is_csr)
                                result_reg <= in_csr_rdata;
                            else
                                result_reg <= in_alu_result;
                            out_valid <= 1'b1;
                        end
                    end
                end
                
                S_MEM_REQ: begin
                    // 保持请求直到被接受
                    mem_req <= 1'b0;  // 单周期请求脉冲
                    state <= S_MEM_WAIT;
                end
                
                S_MEM_WAIT: begin
                    if (mem_rvalid) begin
                        mem_result <= mem_rdata;
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    // 访存完成，输出结果
                    if (!out_valid) begin
                        // 第一次进入 S_DONE，设置输出
                        if (mem_ren_reg) begin
                            result_reg <= load_result;
                        end else begin
                            result_reg <= alu_result_reg;
                        end
                        out_valid <= 1'b1;
                    end else if (out_valid && out_ready) begin
                        // 数据被下游消费，返回 IDLE
                        state <= S_IDLE;
                        out_valid <= 1'b0;
                    end
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
    
    // ========== 输出连接 ==========
    assign out_pc        = pc_reg;
    assign out_inst      = inst_reg;
    assign out_result    = result_reg;
    assign out_rd        = rd_reg;
    assign out_reg_wen   = reg_wen_reg && (rd_reg != 5'b0);  // x0 不能写
    assign out_is_csr    = is_csr_reg;
    assign out_csr_wdata = csr_wdata_reg;
    assign out_csr_wen   = csr_wen_reg;
    assign out_csr_addr  = inst_reg[31:20];  // CSR 地址
    assign out_ebreak    = is_ebreak_reg;
    assign out_ecall     = is_ecall_reg;
    assign out_mret      = is_mret_reg;

endmodule
