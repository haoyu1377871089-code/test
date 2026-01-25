`include "axi4_lite_interface.vh"

module IFU_AXI (
    input clk,
    input rst,
    
    // 原始接口（保持兼容）
    input req,
    input [31:0] addr,
    output reg rvalid_out,
    output reg [31:0] rdata_out,
    
    // AXI4-Lite Master接口
    // Write Address Channel (AW) - IFU只读，这些信号置为0
    output reg [31:0] awaddr,
    output reg        awvalid,
    input             awready,
    
    // Write Data Channel (W) - IFU只读，这些信号置为0
    output reg [31:0] wdata,
    output reg [3:0]  wstrb,
    output reg        wvalid,
    input             wready,
    
    // Write Response Channel (B) - IFU只读，这些信号置为0
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

// 通过 DPI-C 从外部物理内存读取指令（AM/NPC 提供）
// 综合时注释掉 DPI-C 函数
// import "DPI-C" function int unsigned pmem_read(input int unsigned raddr);

// ========== 性能计数器 (仅仿真) ==========
`ifdef SIMULATION
    reg [63:0] perf_ifu_fetch_cnt;       // 成功取指次数
    reg [63:0] perf_ifu_req_cycles;      // 发起请求的周期数
    reg [63:0] perf_ifu_wait_cycles;     // 等待响应的周期数  
    reg [63:0] perf_ifu_stall_arb_cycles; // 等待仲裁的周期数 (arvalid && !arready)
`endif

reg [31:0] addr_stage1;
reg        req_stage1;

always @(posedge clk or posedge rst) begin
  if (rst) begin
    addr_stage1 <= 32'h0;
    req_stage1  <= 1'b0;
    rvalid_out  <= 1'b0;
    rdata_out   <= 32'h0;
    
    // 写通道信号全部置为0（IFU只读）
    awaddr <= 32'h0;
    awvalid <= 1'b0;
    wdata <= 32'h0;
    wstrb <= 4'h0;
    wvalid <= 1'b0;
    bready <= 1'b0;
    
    // 读通道信号初始化
    araddr <= 32'h0;
    arvalid <= 1'b0;
    rready <= 1'b0;
`ifdef SIMULATION
    // 初始化性能计数器
    perf_ifu_fetch_cnt <= 64'h0;
    perf_ifu_req_cycles <= 64'h0;
    perf_ifu_wait_cycles <= 64'h0;
    perf_ifu_stall_arb_cycles <= 64'h0;
`endif
  end else begin
    // 写通道信号始终为0（IFU只读）
    awaddr <= 32'h0;
    awvalid <= 1'b0;
    wdata <= 32'h0;
    wstrb <= 4'h0;
    wvalid <= 1'b0;
    bready <= 1'b0;
    
    // 1级流水线：把请求与地址打一拍
    addr_stage1 <= addr;
    req_stage1  <= req;

    // 下一拍输出有效与数据，实现1周期读延迟
    // rvalid_out <= req_stage1;
    // if (req_stage1) begin
    //   rdata_out <= 32'h0; // pmem_read(...);
    // end
    
    // AXI4-Lite握手信号（简化处理，立即响应）
    if (req) begin
      araddr <= addr;
      arvalid <= 1'b1;
      rready <= 1'b1;
      rvalid_out <= 1'b0; // 等待AXI响应
    end else if (arvalid && arready) begin
      arvalid <= 1'b0;
    end 
    
    if (rvalid && rready) begin
      rready <= 1'b0;
      rdata_out <= rdata; // 从AXI读取数据
      rvalid_out <= 1'b1; // 输出有效
`ifdef SIMULATION
      perf_ifu_fetch_cnt <= perf_ifu_fetch_cnt + 1; // 成功取指
`endif
    end else begin
      rvalid_out <= 1'b0;
    end

`ifdef SIMULATION
    // 性能计数：统计各种状态周期
    if (req) perf_ifu_req_cycles <= perf_ifu_req_cycles + 1;
    if (arvalid && !arready) perf_ifu_stall_arb_cycles <= perf_ifu_stall_arb_cycles + 1;
    if (arvalid || rready) perf_ifu_wait_cycles <= perf_ifu_wait_cycles + 1;
`endif
  end
end

// 断言：确保写通道信号始终为0
always @(posedge clk) begin
    if (!rst) begin
        // assert(awvalid == 1'b0) else $error("IFU awvalid should always be 0");
        // assert(wvalid == 1'b0) else $error("IFU wvalid should always be 0");
        // assert(bready == 1'b0) else $error("IFU bready should always be 0");
    end
end

endmodule