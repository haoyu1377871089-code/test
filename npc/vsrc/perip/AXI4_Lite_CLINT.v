`include "axi4_lite_interface.vh"

module AXI4_Lite_CLINT (
    input clk,
    input rst,
    
    // AXI4-Lite Slave接口
    `AXI4_LITE_SLAVE_PORTS,
    
    // 配置参数：设备寄存器基地址
    input [31:0] base_addr,
    
    // 调试输出
    output reg [63:0] debug_mtime,
    output reg        debug_read
);

// CLINT寄存器偏移定义（相对于基地址）
localparam MTIME_ADDR     = 32'h0000;  // mtime寄存器（64位，低32位）
localparam MTIMEH_ADDR    = 32'h0004;  // mtime寄存器（64位，高32位）
localparam MSIP_ADDR      = 32'h0008;  // 软件中断寄存器（未使用，但预留）

// AXI4-Lite状态机状态定义
localparam AXI4_IDLE  = 2'b00;
localparam AXI4_ADDR  = 2'b01;
localparam AXI4_DATA  = 2'b10;
localparam AXI4_RESP  = 2'b11;

// 内部寄存器
reg [1:0]  state;
reg [31:0] addr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg        is_write;

// CLINT内部寄存器
reg [63:0] mtime;        // 64位mtime寄存器
reg [31:0] msip;         // 软件中断寄存器（未使用）

// 地址匹配信号
wire addr_in_range = (arvalid || awvalid) && (araddr[31:12] == base_addr[31:12]);
wire [11:0] reg_offset = arvalid ? araddr[11:0] : awaddr[11:0];

// mtime递增逻辑（每周期加1）
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mtime <= 64'h0;
    end else begin
        mtime <= mtime + 64'h1;  // 每周期递增1
    end
end

// 初始化
initial begin
    state = AXI4_IDLE;
    addr_reg = 32'h0;
    wdata_reg = 32'h0;
    wstrb_reg = 4'h0;
    is_write = 1'b0;
    
    // AXI4-Lite信号初始化
    awready = 1'b0;
    wready = 1'b0;
    bresp = `AXI4_RESP_OKAY;
    bvalid = 1'b0;
    arready = 1'b0;
    rdata = 32'h0;
    rresp = `AXI4_RESP_OKAY;
    rvalid = 1'b0;
    
    // CLINT寄存器初始化
    msip = 32'h0;
    
    // 调试信号初始化
    debug_mtime = 64'h0;
    debug_read = 1'b0;
end

// AXI4-Lite状态机
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= AXI4_IDLE;
        addr_reg <= 32'h0;
        wdata_reg <= 32'h0;
        wstrb_reg <= 4'h0;
        is_write <= 1'b0;
        
        // AXI4-Lite信号复位
        awready <= 1'b0;
        wready <= 1'b0;
        bresp <= `AXI4_RESP_OKAY;
        bvalid <= 1'b0;
        arready <= 1'b0;
        rdata <= 32'h0;
        rresp <= `AXI4_RESP_OKAY;
        rvalid <= 1'b0;
        
        // CLINT寄存器复位
        msip <= 32'h0;
        
        // 调试信号复位
        debug_mtime <= 64'h0;
        debug_read <= 1'b0;
    end else begin
        case (state)
            AXI4_IDLE: begin
                // 空闲状态，等待地址通道
                awready <= 1'b0;
                arready <= 1'b0;
                bvalid <= 1'b0;
                rvalid <= 1'b0;
                debug_read <= 1'b0;
                
                if (awvalid && !awready && addr_in_range) begin
                    // 写地址通道
                    state <= AXI4_ADDR;
                    addr_reg <= awaddr;
                    is_write <= 1'b1;
                    awready <= 1'b1;
                end else if (arvalid && !arready && addr_in_range) begin
                    // 读地址通道
                    state <= AXI4_ADDR;
                    addr_reg <= araddr;
                    is_write <= 1'b0;
                    arready <= 1'b1;
                end
            end
            
            AXI4_ADDR: begin
                // 地址通道已接收，准备数据通道
                awready <= 1'b0;
                arready <= 1'b0;
                
                if (is_write) begin
                    // 写操作：等待写数据
                    if (wvalid && !wready) begin
                        state <= AXI4_DATA;
                        wdata_reg <= wdata;
                        wstrb_reg <= wstrb;
                        wready <= 1'b1;
                    end
                end else begin
                    // 读操作：立即执行读操作
                    state <= AXI4_DATA;
                    // 执行读操作
                    debug_read <= 1'b1;
                    debug_mtime <= mtime;
                    
                    case ({20'h0, reg_offset})
                        MTIME_ADDR:  rdata <= mtime[31:0];      // 低32位
                        MTIMEH_ADDR: rdata <= mtime[63:32];     // 高32位
                        MSIP_ADDR:   rdata <= msip;             // 软件中断
                        default:     rdata <= 32'h0;
                    endcase
                    rresp <= `AXI4_RESP_OKAY;
                    rvalid <= 1'b1;
                end
            end
            
            AXI4_DATA: begin
                // 数据通道处理
                wready <= 1'b0;
                
                if (is_write) begin
                    // 写操作：执行写操作并发送响应
                    if (!bvalid) begin
                        // 执行写操作
                        case ({20'h0, reg_offset})
                            MTIME_ADDR: begin
                                if (wstrb[0]) mtime[7:0]   <= wdata_reg[7:0];
                                if (wstrb[1]) mtime[15:8]  <= wdata_reg[15:8];
                                if (wstrb[2]) mtime[23:16] <= wdata_reg[23:16];
                                if (wstrb[3]) mtime[31:24] <= wdata_reg[31:24];
                            end
                            MTIMEH_ADDR: begin
                                if (wstrb[0]) mtime[39:32] <= wdata_reg[7:0];
                                if (wstrb[1]) mtime[47:40] <= wdata_reg[15:8];
                                if (wstrb[2]) mtime[55:48] <= wdata_reg[23:16];
                                if (wstrb[3]) mtime[63:56] <= wdata_reg[31:24];
                            end
                            MSIP_ADDR: begin
                                if (wstrb[0]) msip[7:0] <= wdata_reg[7:0];
                            end
                        endcase
                        bresp <= `AXI4_RESP_OKAY;
                        bvalid <= 1'b1;
                        state <= AXI4_RESP;
                    end
                end else begin
                    // 读操作：等待读响应被接收
                    if (rvalid && rready) begin
                        rvalid <= 1'b0;
                        debug_read <= 1'b0;
                        state <= AXI4_IDLE;
                    end
                end
            end
            
            AXI4_RESP: begin
                // 响应通道处理
                if (is_write) begin
                    // 写操作：等待写响应被接收
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        state <= AXI4_IDLE;
                    end
                end
            end
            
            default: begin
                state <= AXI4_IDLE;
            end
        endcase
    end
end

endmodule