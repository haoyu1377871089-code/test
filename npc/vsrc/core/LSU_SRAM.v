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

// ========== 性能计数器 (仅仿真) ==========
`ifdef SIMULATION
    reg [63:0] perf_lsu_load_cnt;       // Load请求次数
    reg [63:0] perf_lsu_store_cnt;      // Store请求次数
    reg [63:0] perf_lsu_load_cycles;    // Load总周期数 (从请求到完成)
    reg [63:0] perf_lsu_store_cycles;   // Store总周期数
    reg [63:0] perf_lsu_stall_arb_cycles; // 等待仲裁周期数
`endif

// 流水线寄存器
reg [31:0] addr_stage1;
reg        req_stage1;
reg        wen_stage1;

always @(posedge clk or posedge rst) begin
  if (rst) begin
    addr_stage1 <= 32'h0;
    req_stage1 <= 1'b0;
    wen_stage1 <= 1'b0;
    rvalid_out <= 1'b0;
    rdata_out <= 32'h0;
    
    // AXI4-Lite信号初始化（本模块使用pmem，AXI信号保持为0）
    awaddr <= 32'h0;
    awvalid <= 1'b0;
    wdata_axi <= 32'h0;
    wstrb <= 4'h0;
    wvalid <= 1'b0;
    bready <= 1'b0;
    araddr <= 32'h0;
    arvalid <= 1'b0;
    rready <= 1'b0;
`ifdef SIMULATION
    // 初始化性能计数器
    perf_lsu_load_cnt <= 64'h0;
    perf_lsu_store_cnt <= 64'h0;
    perf_lsu_load_cycles <= 64'h0;
    perf_lsu_store_cycles <= 64'h0;
    perf_lsu_stall_arb_cycles <= 64'h0;
`endif
  end else begin
    // 第一级流水线：保存请求信息
    addr_stage1 <= addr;
    req_stage1 <= req;
    wen_stage1 <= wen;
    
    // 默认 rvalid_out 为 0
    rvalid_out <= 1'b0;
    
    // 读操作：1周期延迟
    if (req_stage1 && !wen_stage1) begin
      rdata_out <= pmem_read(addr_stage1);
      rvalid_out <= 1'b1;
`ifdef SIMULATION
      perf_lsu_load_cnt <= perf_lsu_load_cnt + 1;
      perf_lsu_load_cycles <= perf_lsu_load_cycles + 1; // 简单模式：1周期
`endif
    end
    
    // 写操作：立即处理
    if (req && wen) begin
      pmem_write(addr, wdata, {4'b0000, wmask});
      rvalid_out <= 1'b1; // 写完成
`ifdef SIMULATION
      perf_lsu_store_cnt <= perf_lsu_store_cnt + 1;
      perf_lsu_store_cycles <= perf_lsu_store_cycles + 1; // 简单模式：1周期
`endif
    end
    
    // AXI信号保持为0（本模块使用pmem，不走AXI）
    awaddr <= 32'h0;
    awvalid <= 1'b0;
    wdata_axi <= 32'h0;
    wstrb <= 4'h0;
    wvalid <= 1'b0;
    bready <= 1'b0;
    araddr <= 32'h0;
    arvalid <= 1'b0;
    rready <= 1'b0;
  end
end

endmodule
