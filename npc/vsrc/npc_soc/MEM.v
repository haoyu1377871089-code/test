module MEM (
    input clk,
    input rst,
    
    // 内存接口
    input mem_read,        // 内存读使能
    input mem_write,       // 内存写使能
    input [31:0] mem_addr, // 内存地址
    input [31:0] mem_wdata,// 写入内存的数据
    input [3:0] mem_mask,  // 字节使能
    output reg [31:0] mem_rdata // 从内存读取的数据
);
// 通过 DPI-C 与 C++ 侧物理内存/设备交互（MMIO/外部内存）
// 综合时注释掉 DPI-C 函数
// import "DPI-C" function int unsigned pmem_read(input int unsigned raddr);
// import "DPI-C" function void pmem_write(input int unsigned waddr, input int unsigned wdata, input byte unsigned wmask);

// ========= 数据存储器（DMEM，256x32b，组合读、时序写） =========
localparam DMEM_BASE  = 32'h8000_0000;
localparam DMEM_BYTES = 32'd1024; // 256 * 4 bytes
wire [31:0] dmem_word_index = ((mem_addr - DMEM_BASE) >> 2);
wire [7:0]  dmem_idx        = dmem_word_index[7:0];
wire        in_dmem         = (mem_addr >= DMEM_BASE) && (mem_addr < (DMEM_BASE + DMEM_BYTES));
wire [31:0] dmem_rdata1;
wire [31:0] dmem_rdata2;

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
  .raddr2(dmem_idx), .rdata2(dmem_rdata2),
  .reg_values() // 未使用的输出端口
);

// 读操作：组合逻辑，本地 DMEM 命中则返回，否则通过 DPI 访问外部内存/设备
always @(*) begin
  if (mem_read) begin
    if (in_dmem) begin
      mem_rdata = dmem_rdata1;
    end else begin
      mem_rdata = 32'h0; // pmem_read(...);
    end
  end else begin
    mem_rdata = 32'h0;
  end
end

// 写操作：在时钟上升沿，本地 DMEM 命中则写入，否则通过 DPI 写外部内存/设备
always @(posedge clk or posedge rst) begin
  if (rst) begin
    dmem_wen   <= 1'b0;
    dmem_waddr <= 8'h00;
    dmem_wdata <= 32'h0;
  end else begin
    if (mem_write) begin
      if (in_dmem) begin
        dmem_wen   <= 1'b1;
        dmem_waddr <= dmem_idx;
        dmem_wdata <= apply_mask(dmem_rdata1, mem_wdata, mem_mask);
      end else begin
        dmem_wen   <= 1'b0;
         ; // pmem_write(...);
      end
    end else begin
      dmem_wen   <= 1'b0;
    end
  end
end

endmodule