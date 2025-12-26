`include "axi4_lite_interface.vh"

module LSU_SRAM (
    input clk,
    input rst,
    
    // 原始接口（保持兼容）
    input req,              // 访存请求
    input wen,              // 写使能，1为写，0为读
    input [31:0] addr,      // 32位地址
    input [31:0] wdata,     // 写数据
    input [3:0] wmask,      // 字节写掩码
    output reg rvalid_out,  // 读数据有效
    output reg [31:0] rdata_out, // 读数据
    
    // AXI4-Lite Master接口
    // Write Address Channel (AW)
    output reg [31:0] awaddr,
    output reg        awvalid,
    input             awready,
    
    // Write Data Channel (W)
    output reg [31:0] wdata_axi,
    output reg [3:0]  wstrb,
    output reg        wvalid,
    input             wready,
    
    // Write Response Channel (B)
    input [1:0]       bresp,
    input             bvalid,
    output reg        bready,
    
    // Read Address Channel (AR)
    output reg [31:0] araddr,
    output reg        arvalid,
    input             arready,
    
    // Read Data Channel (R)
    input [31:0]      rdata,
    input [1:0]       rresp,
    input             rvalid,
    output reg        rready
);

// 通过 DPI-C 与 C++ 侧物理内存/设备交互（MMIO/外部内存）
import "DPI-C" function int unsigned pmem_read(input int unsigned raddr);
import "DPI-C" function void pmem_write(input int unsigned waddr, input int unsigned wdata, input byte unsigned wmask);

// ========= 数据存储器（DMEM，256x32b，组合读、时序写） =========
localparam DMEM_BASE  = 32'h8000_0000;
localparam DMEM_BYTES = 32'd1024; // 256 * 4 bytes
wire [31:0] dmem_word_index = ((addr - DMEM_BASE) >> 2);
wire [7:0]  dmem_idx        = dmem_word_index[7:0];
wire        in_dmem         = (addr >= DMEM_BASE) && (addr < (DMEM_BASE + DMEM_BYTES));
wire [31:0] dmem_rdata1;
wire [31:0] dmem_rdata2;

// 流水线寄存器
reg [31:0] addr_stage1;
reg        req_stage1;
reg        wen_stage1;
reg        in_dmem_stage1;
reg [7:0]  dmem_idx_stage1;

// 写端口寄存器
reg [31:0] dmem_wdata;
reg [7:0]  dmem_waddr;
reg        dmem_wen;

// 组合函数：根据掩码将写数据与旧数据合并
function [31:0] apply_mask(
  input [31:0] old,
  input [31:0] wdata,
  input [3:0]  mask
);
  begin
    apply_mask[7:0]   = mask[0] ? wdata[7:0]   : old[7:0];
    apply_mask[15:8]  = mask[1] ? wdata[15:8]  : old[15:8];
    apply_mask[23:16] = mask[2] ? wdata[23:16] : old[23:16];
    apply_mask[31:24] = mask[3] ? wdata[31:24] : old[31:24];
  end
endfunction

// 使用寄存器堆作为 256x32b 的数据存储器
RegisterFile #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) DMEM (
  .clk(clk), .rst(rst),
  .wdata(dmem_wdata), .waddr(dmem_waddr), .wen(dmem_wen),
  .raddr1(dmem_idx), .rdata1(dmem_rdata1),
  .raddr2(dmem_idx_stage1), .rdata2(dmem_rdata2),
  .reg_values() // 未使用的输出端口
);

// 流水线逻辑：实现1周期读延迟
always @(posedge clk or posedge rst) begin
  if (rst) begin
    addr_stage1 <= 32'h0;
    req_stage1 <= 1'b0;
    wen_stage1 <= 1'b0;
    in_dmem_stage1 <= 1'b0;
    dmem_idx_stage1 <= 8'h0;
    rvalid_out <= 1'b0;
    rdata_out <= 32'h0;
    dmem_wen <= 1'b0;
    dmem_waddr <= 8'h00;
    dmem_wdata <= 32'h0;
    
    // AXI4-Lite信号初始化
    awaddr <= 32'h0;
    awvalid <= 1'b0;
    wdata_axi <= 32'h0;
    wstrb <= 4'h0;
    wvalid <= 1'b0;
    bready <= 1'b0;
    araddr <= 32'h0;
    arvalid <= 1'b0;
    rready <= 1'b0;
  end else begin
    // 第一级流水线：保存请求信息
    addr_stage1 <= addr;
    req_stage1 <= req;
    wen_stage1 <= wen;
    in_dmem_stage1 <= in_dmem;
    dmem_idx_stage1 <= dmem_idx;
    
    // 第二级流水线：处理读操作
    // 默认 rvalid_out 为 0
    rvalid_out <= 1'b0;
    
    if (req_stage1 && !wen_stage1 && in_dmem_stage1) begin
      // DMEM 读操作 (1周期延迟)
      rdata_out <= dmem_rdata2;
      rvalid_out <= 1'b1;
    end else if (rvalid && rready) begin
      // AXI 读操作完成 (异步)
      rdata_out <= rdata;
      rvalid_out <= 1'b1;
    end
    
    // 写操作：立即处理，不延迟
    if (req && wen) begin
      if (in_dmem) begin
        dmem_wen <= 1'b1;
        dmem_waddr <= dmem_idx;
        dmem_wdata <= apply_mask(dmem_rdata1, wdata, wmask);
      end else begin
        dmem_wen <= 1'b0;
        pmem_write(addr, wdata, {4'b0000, wmask});
      end
    end else begin
      dmem_wen <= 1'b0;
    end
    
    // AXI4-Lite握手信号（简化处理，立即响应）
    // 写地址通道
    if (req && wen && !in_dmem) begin
      awaddr <= addr;
      awvalid <= 1'b1;
    end else if (awvalid && awready) begin
      awvalid <= 1'b0;
    end
    
    // 写数据通道
    if (req && wen && !in_dmem) begin
      wdata_axi <= wdata;
      wstrb <= wmask;
      wvalid <= 1'b1;
      bready <= 1'b1;
    end else if (wvalid && wready) begin
      wvalid <= 1'b0;
    end else if (bvalid && bready) begin
      bready <= 1'b0;
    end
    
    // 读地址通道
    if (req && !wen && !in_dmem) begin
      araddr <= addr;
      arvalid <= 1'b1;
      rready <= 1'b1;
    end else if (arvalid && arready) begin
      arvalid <= 1'b0;
    end else if (rvalid && rready) begin
      rready <= 1'b0;
    end
  end
end

endmodule