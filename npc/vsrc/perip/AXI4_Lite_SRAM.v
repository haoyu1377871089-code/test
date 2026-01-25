`include "axi4_lite_interface.vh"

module AXI4_Lite_SRAM (
    input clk,
    input rst,
    
    // AXI4-Lite Slave接口
    `AXI4_LITE_SLAVE_PORTS,
    
    // 调试输出信号
    output reg [31:0] debug_addr,
    output reg        debug_read,
    output reg        debug_write
);

// 通过 DPI-C 与外部物理内存交互
// 综合时注释掉 DPI-C 函数
// import "DPI-C" function int unsigned pmem_read(input int unsigned raddr);
// import "DPI-C" function void pmem_write(input int unsigned waddr, input int unsigned wdata, input byte unsigned wmask);

// AXI4-Lite状态机状态定义
localparam AXI4_IDLE  = 2'b00;
localparam AXI4_ADDR  = 2'b01;
localparam AXI4_DATA  = 2'b10;
localparam AXI4_RESP  = 2'b11;

// 状态寄存器
reg [1:0] state;
reg [31:0] addr_reg;
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg        is_write;  // 1:写操作，0:读操作

// 初始化
initial begin
    state = AXI4_IDLE;
    addr_reg = 32'h0;
    wdata_reg = 32'h0;
    wstrb_reg = 4'h0;
    is_write = 1'b0;
    
    // 初始化AXI4-Lite信号
    awready = 1'b0;
    wready = 1'b0;
    bresp = `AXI4_RESP_OKAY;
    bvalid = 1'b0;
    arready = 1'b0;
    rdata = 32'h0;
    rresp = `AXI4_RESP_OKAY;
    rvalid = 1'b0;
    
    debug_addr = 32'h0;
    debug_read = 1'b0;
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
        
        awready <= 1'b0;
        wready <= 1'b0;
        bresp <= `AXI4_RESP_OKAY;
        bvalid <= 1'b0;
        arready <= 1'b0;
        rdata <= 32'h0;
        rresp <= `AXI4_RESP_OKAY;
        rvalid <= 1'b0;
        
        debug_addr <= 32'h0;
        debug_read <= 1'b0;
        debug_write <= 1'b0;
    end else begin
        case (state)
            AXI4_IDLE: begin
                // 空闲状态，等待地址通道
                awready <= 1'b0;
                arready <= 1'b0;
                bvalid <= 1'b0;
                rvalid <= 1'b0;
                
                if (awvalid && !awready) begin
                    // 写地址通道
                    state <= AXI4_ADDR;
                    addr_reg <= awaddr;
                    is_write <= 1'b1;
                    awready <= 1'b1;
                    debug_addr <= awaddr;
                    debug_write <= 1'b1;
                    debug_read <= 1'b0;
                end else if (arvalid && !arready) begin
                    // 读地址通道
                    state <= AXI4_ADDR;
                    addr_reg <= araddr;
                    is_write <= 1'b0;
                    arready <= 1'b1;
                    debug_addr <= araddr;
                    debug_read <= 1'b1;
                    debug_write <= 1'b0;
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
                    rdata <= 32'h0; // pmem_read(...);
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
                         ; // pmem_write(...);
                        bresp <= `AXI4_RESP_OKAY;
                        bvalid <= 1'b1;
                        state <= AXI4_RESP;
                    end
                end else begin
                    // 读操作：等待读响应被接收
                    if (rvalid && rready) begin
                        rvalid <= 1'b0;
                        state <= AXI4_IDLE;
                        debug_read <= 1'b0;
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