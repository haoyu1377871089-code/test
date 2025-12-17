`include "axi4_lite_interface.vh"

module AXI4_Lite_UART (
    input clk,
    input rst,
    
    // AXI4-Lite Slave接口
    `AXI4_LITE_SLAVE_PORTS,
    
    // 配置参数：设备寄存器基地址
    input [31:0] base_addr,
    
    // 调试输出
    output reg [7:0]  debug_char,
    output reg        debug_write
);

// UART寄存器偏移定义（相对于基地址）
localparam UART_TXD_REG = 32'h0000;  // 发送数据寄存器
localparam UART_STATUS_REG = 32'h0004; // 状态寄存器
localparam UART_CTRL_REG = 32'h0008;   // 控制寄存器

// 状态寄存器位定义
localparam UART_TX_EMPTY = 0;  // 发送缓冲区空
localparam UART_RX_VALID = 1;  // 接收数据有效

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

// UART内部寄存器
reg [7:0]  uart_txd;      // 发送数据寄存器
reg        uart_tx_empty;   // 发送缓冲区空标志
reg [7:0]  uart_rxd;      // 接收数据寄存器（未使用，但保留）
reg        uart_rx_valid; // 接收数据有效标志（未使用，但保留）
reg [31:0] uart_status;   // 状态寄存器
reg [31:0] uart_ctrl;     // 控制寄存器

// 地址匹配信号
wire addr_in_range = (arvalid || awvalid) && (araddr[31:12] == base_addr[31:12]);
wire [11:0] reg_offset = arvalid ? araddr[11:0] : awaddr[11:0];

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
    
    // UART寄存器初始化
    uart_txd = 8'h0;
    uart_tx_empty = 1'b1;
    uart_rxd = 8'h0;
    uart_rx_valid = 1'b0;
    uart_status = 32'h00000002; // 默认发送缓冲区空
    uart_ctrl = 32'h00000000;
    
    // 调试信号初始化
    debug_char = 8'h0;
    debug_write = 1'b0;
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
        
        // UART寄存器复位
        uart_txd <= 8'h0;
        uart_tx_empty <= 1'b1;
        uart_rxd <= 8'h0;
        uart_rx_valid <= 1'b0;
        uart_status <= 32'h00000002; // 默认发送缓冲区空
        uart_ctrl <= 32'h00000000;
        
        // 调试信号复位
        debug_char <= 8'h0;
        debug_write <= 1'b0;
    end else begin
        case (state)
            AXI4_IDLE: begin
                // 空闲状态，等待地址通道
                awready <= 1'b0;
                arready <= 1'b0;
                bvalid <= 1'b0;
                rvalid <= 1'b0;
                debug_write <= 1'b0;
                
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
                    case ({20'h0, reg_offset})
                        UART_TXD_REG: rdata <= {24'h0, uart_txd};
                        UART_STATUS_REG: rdata <= uart_status;
                        UART_CTRL_REG: rdata <= uart_ctrl;
                        default: rdata <= 32'h0;
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
                            UART_TXD_REG: begin
                                if (wstrb[0]) begin
                                    uart_txd <= wdata_reg[7:0];
                                    // 输出字符到控制台
                                    $write("%c", wdata_reg[7:0]);
                                    $fflush();
                                    // 更新调试信号
                                    debug_char <= wdata_reg[7:0];
                                    debug_write <= 1'b1;
                                    // 设置发送缓冲区为忙状态
                                    uart_tx_empty <= 1'b0;
                                end
                            end
                            UART_STATUS_REG: begin
                                // 状态寄存器通常是只读的，但可以写入清除某些位
                                if (wstrb[0]) uart_status[7:0] <= uart_status[7:0] & ~wdata_reg[7:0];
                                if (wstrb[1]) uart_status[15:8] <= uart_status[15:8] & ~wdata_reg[15:8];
                                if (wstrb[2]) uart_status[23:16] <= uart_status[23:16] & ~wdata_reg[23:16];
                                if (wstrb[3]) uart_status[31:24] <= uart_status[31:24] & ~wdata_reg[31:24];
                            end
                            UART_CTRL_REG: begin
                                if (wstrb[0]) uart_ctrl[7:0] <= wdata_reg[7:0];
                                if (wstrb[1]) uart_ctrl[15:8] <= wdata_reg[15:8];
                                if (wstrb[2]) uart_ctrl[23:16] <= wdata_reg[23:16];
                                if (wstrb[3]) uart_ctrl[31:24] <= wdata_reg[31:24];
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
                        debug_write <= 1'b0;
                        // 模拟发送完成，设置发送缓冲区为空
                        uart_tx_empty <= 1'b1;
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