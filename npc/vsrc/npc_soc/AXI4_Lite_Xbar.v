`include "axi4_lite_interface.vh"

module AXI4_Lite_Xbar (
    input clk,
    input rst,
    
    // 主设备接口（来自仲裁器）
    input [31:0]  m_awaddr,
    input         m_awvalid,
    output        m_awready,
    
    input [31:0]  m_wdata,
    input [3:0]   m_wstrb,
    input         m_wvalid,
    output        m_wready,
    
    output [1:0]  m_bresp,
    output        m_bvalid,
    input         m_bready,
    
    input [31:0]  m_araddr,
    input         m_arvalid,
    output        m_arready,
    
    output [31:0] m_rdata,
    output [1:0]  m_rresp,
    output        m_rvalid,
    input         m_rready,
    
    // SRAM从设备接口
    output [31:0] sram_awaddr,
    output        sram_awvalid,
    input         sram_awready,
    
    output [31:0] sram_wdata,
    output [3:0]  sram_wstrb,
    output        sram_wvalid,
    input         sram_wready,
    
    input [1:0]   sram_bresp,
    input         sram_bvalid,
    output        sram_bready,
    
    output [31:0] sram_araddr,
    output        sram_arvalid,
    input         sram_arready,
    
    input [31:0]  sram_rdata,
    input [1:0]   sram_rresp,
    input         sram_rvalid,
    output        sram_rready,
    
    // UART从设备接口
    output [31:0] uart_awaddr,
    output        uart_awvalid,
    input         uart_awready,
    
    output [31:0] uart_wdata,
    output [3:0]  uart_wstrb,
    output        uart_wvalid,
    input         uart_wready,
    
    input [1:0]   uart_bresp,
    input         uart_bvalid,
    output        uart_bready,
    
    output [31:0] uart_araddr,
    output        uart_arvalid,
    input         uart_arready,
    
    input [31:0]  uart_rdata,
    input [1:0]   uart_rresp,
    input         uart_rvalid,
    output        uart_rready,
    
    // CLINT从设备接口
    output [31:0] clint_awaddr,
    output        clint_awvalid,
    input         clint_awready,
    
    output [31:0] clint_wdata,
    output [3:0]  clint_wstrb,
    output        clint_wvalid,
    input         clint_wready,
    
    input [1:0]   clint_bresp,
    input         clint_bvalid,
    output        clint_bready,
    
    output [31:0] clint_araddr,
    output        clint_arvalid,
    input         clint_arready,
    
    input [31:0]  clint_rdata,
    input [1:0]   clint_rresp,
    input         clint_rvalid,
    output        clint_rready
);

// 地址映射定义
localparam SRAM_BASE_ADDR  = 32'h80000000;  // SRAM基地址
localparam SRAM_SIZE       = 32'h00100000;  // 1MB SRAM
localparam UART_BASE_ADDR  = 32'ha0000000;  // UART设备基地址
localparam UART_SIZE       = 32'h00100000;  // 1MB 设备空间
localparam CLINT_BASE_ADDR = 32'ha0000000;  // CLINT设备基地址（与UART共享地址空间）
localparam CLINT_SIZE      = 32'h00001000;  // 4KB CLINT空间
localparam UART_OFFSET     = 32'h000003f8;  // UART在设备空间中的偏移
localparam CLINT_OFFSET    = 32'h00000048;  // CLINT在设备空间中的偏移（RTC地址）

// 地址解码逻辑
wire sram_selected = (m_awvalid && (m_awaddr >= SRAM_BASE_ADDR) && (m_awaddr < (SRAM_BASE_ADDR + SRAM_SIZE))) ||
                      (m_arvalid && (m_araddr >= SRAM_BASE_ADDR) && (m_araddr < (SRAM_BASE_ADDR + SRAM_SIZE)));

// 设备地址空间解码（0xa0000000 - 0xa0100000）
wire device_space_selected = (m_awvalid && (m_awaddr >= UART_BASE_ADDR) && (m_awaddr < (UART_BASE_ADDR + UART_SIZE))) ||
                             (m_arvalid && (m_araddr >= UART_BASE_ADDR) && (m_araddr < (UART_BASE_ADDR + UART_SIZE)));

// 在设备地址空间中进一步解码
wire [31:0] device_offset = m_awvalid ? (m_awaddr - UART_BASE_ADDR) : (m_araddr - UART_BASE_ADDR);
wire uart_selected = device_space_selected && (device_offset == UART_OFFSET);
wire clint_selected = device_space_selected && (device_offset == CLINT_OFFSET || device_offset == CLINT_OFFSET + 4);

// 主设备到从设备的信号路由
assign sram_awaddr = m_awaddr;
assign sram_awvalid = m_awvalid && sram_selected;
assign sram_wdata = m_wdata;
assign sram_wstrb = m_wstrb;
assign sram_wvalid = m_wvalid && sram_selected;
assign sram_bready = m_bready;
assign sram_araddr = m_araddr;
assign sram_arvalid = m_arvalid && sram_selected;
assign sram_rready = m_rready;

assign uart_awaddr = m_awaddr;
assign uart_awvalid = m_awvalid && uart_selected;
assign uart_wdata = m_wdata;
assign uart_wstrb = m_wstrb;
assign uart_wvalid = m_wvalid && uart_selected;
assign uart_bready = m_bready;
assign uart_araddr = m_araddr;
assign uart_arvalid = m_arvalid && uart_selected;
assign uart_rready = m_rready;

assign clint_awaddr = m_awaddr;
assign clint_awvalid = m_awvalid && clint_selected;
assign clint_wdata = m_wdata;
assign clint_wstrb = m_wstrb;
assign clint_wvalid = m_wvalid && clint_selected;
assign clint_bready = m_bready;
assign clint_araddr = m_araddr;
assign clint_arvalid = m_arvalid && clint_selected;
assign clint_rready = m_rready;

// 从设备到主设备的响应复用
reg [2:0] selected_slave;  // 000: none, 001: SRAM, 010: UART, 100: CLINT
reg [2:0] selected_slave_r; // 用于读响应的寄存器

always @(*) begin
    if (sram_selected) begin
        selected_slave = 3'b001;
    end else if (uart_selected) begin
        selected_slave = 3'b010;
    end else if (clint_selected) begin
        selected_slave = 3'b100;
    end else begin
        selected_slave = 3'b000;
    end
end

// 在读地址阶段寄存器选择的从设备
always @(posedge clk or posedge rst) begin
    if (rst) begin
        selected_slave_r <= 3'b000;
    end else if (m_arvalid && m_arready) begin
        selected_slave_r <= selected_slave;
    end
end

// 主设备响应信号生成
assign m_awready = sram_selected ? sram_awready : 
                   uart_selected ? uart_awready : 
                   clint_selected ? clint_awready : 1'b0;

assign m_wready = sram_selected ? sram_wready : 
                  uart_selected ? uart_wready : 
                  clint_selected ? clint_wready : 1'b0;

assign m_bresp = sram_selected ? sram_bresp : 
                 uart_selected ? uart_bresp : 
                 clint_selected ? clint_bresp : `AXI4_RESP_OKAY;

assign m_bvalid = sram_selected ? sram_bvalid : 
                  uart_selected ? uart_bvalid : 
                  clint_selected ? clint_bvalid : 1'b0;

assign m_arready = sram_selected ? sram_arready : 
                   uart_selected ? uart_arready : 
                   clint_selected ? clint_arready : 1'b0;

// 读数据响应复用
assign m_rdata = (selected_slave_r == 3'b001) ? sram_rdata :
                 (selected_slave_r == 3'b010) ? uart_rdata :
                 (selected_slave_r == 3'b100) ? clint_rdata : 32'h0;

assign m_rresp = (selected_slave_r == 3'b001) ? sram_rresp :
                 (selected_slave_r == 3'b010) ? uart_rresp :
                 (selected_slave_r == 3'b100) ? clint_rresp : `AXI4_RESP_OKAY;

assign m_rvalid = (selected_slave_r == 3'b001) ? sram_rvalid :
                  (selected_slave_r == 3'b010) ? uart_rvalid :
                  (selected_slave_r == 3'b100) ? clint_rvalid : 1'b0;

endmodule