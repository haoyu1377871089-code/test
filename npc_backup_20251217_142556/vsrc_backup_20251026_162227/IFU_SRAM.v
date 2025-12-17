module IFU_SRAM (
    input clk,
    input rst,
    input req,
    input [31:0] addr,
    output reg rvalid,
    output reg [31:0] rdata
);

// 通过 DPI-C 从外部物理内存读取指令（AM/NPC 提供）
import "DPI-C" function int unsigned pmem_read(input int unsigned raddr);

reg [31:0] addr_stage1;
reg        req_stage1;

always @(posedge clk or posedge rst) begin
  if (rst) begin
    addr_stage1 <= 32'h0;
    req_stage1  <= 1'b0;
    rvalid      <= 1'b0;
    rdata       <= 32'h0;
  end else begin
    // 1级流水线：把请求与地址打一拍
    addr_stage1 <= addr;
    req_stage1  <= req;

    // 下一拍输出有效与数据，实现1周期读延迟
    rvalid <= req_stage1;
    if (req_stage1) begin
      rdata <= pmem_read(addr_stage1);
    end
  end
end

endmodule