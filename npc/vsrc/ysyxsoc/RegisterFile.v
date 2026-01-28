module RegisterFile #(parameter ADDR_WIDTH = 5, parameter DATA_WIDTH = 32) (
  input clk,
  input rst,  // 添加复位信号
  
  // 写入端口
  input [DATA_WIDTH-1:0] wdata,
  input [ADDR_WIDTH-1:0] waddr,
  input wen,
  
  // 读取端口1
  input [ADDR_WIDTH-1:0] raddr1,
  output [DATA_WIDTH-1:0] rdata1,
  
  // 读取端口2
  input [ADDR_WIDTH-1:0] raddr2,
  output [DATA_WIDTH-1:0] rdata2,
  
  // 读取端口3 - 用于读取 a0 (x10) 作为 ebreak exit_code
  input [ADDR_WIDTH-1:0] raddr3,
  output [DATA_WIDTH-1:0] rdata3
  // 添加寄存器值输出接口用于DiffTest
  // output [DATA_WIDTH-1:0] reg_values [0:(2**ADDR_WIDTH)-1]
);
  // 寄存器文件定义
  reg [DATA_WIDTH-1:0] rf [2**ADDR_WIDTH-1:0];
  integer i;
  
  // 写入逻辑（添加复位功能）
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      // 复位时将所有寄存器清零
      for (i = 0; i < 2**ADDR_WIDTH; i = i + 1) begin
        rf[i] = {DATA_WIDTH{1'b0}};
      end
    end else if (wen) begin
      // 考虑特殊情况：R0通常为硬件零
      if (waddr != {ADDR_WIDTH{1'b0}}) begin
        rf[waddr] <= wdata;
      end
    end
  end
  
  // 读取逻辑
  // 如果读取地址是0，直接返回0（R0通常为硬件零）
  assign rdata1 = (raddr1 == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : rf[raddr1];
  assign rdata2 = (raddr2 == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : rf[raddr2];
  assign rdata3 = (raddr3 == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : rf[raddr3];
  
  // 将内部寄存器值连接到输出接口
  genvar j;
  generate
    for (j = 0; j < 2**ADDR_WIDTH; j = j + 1) begin : REG_VALUE_CONNECT
      // assign reg_values[j] = rf[j];
    end
  endgenerate
  
  // // 添加读取调试
  // always @(raddr1, raddr2) begin
  //   if (raddr1 == 5'd1 || raddr2 == 5'd1) begin
  //     $display("读取RA(x1)寄存器: 值=0x%x 在时间 %t", 
  //              (raddr1 == 5'd1) ? rdata1 : rdata2, $time);
  //   end
  // end
endmodule