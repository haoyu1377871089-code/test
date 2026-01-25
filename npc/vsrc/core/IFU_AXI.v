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

// ========== 状态机定义 ==========
localparam IFU_IDLE    = 2'd0;  // 空闲，等待请求
localparam IFU_WAIT_AR = 2'd1;  // 等待地址通道握手
localparam IFU_WAIT_R  = 2'd2;  // 等待数据响应

reg [1:0] ifu_state;

// ========== 性能计数器 (仅仿真) ==========
`ifdef SIMULATION
    reg [63:0] perf_ifu_fetch_cnt;       // 成功取指次数
    reg [63:0] perf_ifu_req_cycles;      // 发起请求的周期数
    reg [63:0] perf_ifu_wait_cycles;     // 等待响应的周期数  
    reg [63:0] perf_ifu_stall_arb_cycles; // 等待仲裁的周期数 (arvalid && !arready)
`endif

// ========== 主状态机 ==========
always @(posedge clk or posedge rst) begin
    if (rst) begin
        ifu_state <= IFU_IDLE;
        rvalid_out <= 1'b0;
        rdata_out <= 32'h0;
        
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
        
        // 默认：rvalid_out 是单周期脉冲
        rvalid_out <= 1'b0;
        
        case (ifu_state)
            IFU_IDLE: begin
                if (req) begin
                    araddr <= addr;
                    arvalid <= 1'b1;
                    rready <= 1'b1;
                    ifu_state <= IFU_WAIT_AR;
`ifdef SIMULATION
                    perf_ifu_req_cycles <= perf_ifu_req_cycles + 1;
`endif
                end
            end
            
            IFU_WAIT_AR: begin
                if (arready) begin
                    arvalid <= 1'b0;  // 地址握手完成
                    ifu_state <= IFU_WAIT_R;
                end
`ifdef SIMULATION
                if (!arready) perf_ifu_stall_arb_cycles <= perf_ifu_stall_arb_cycles + 1;
                perf_ifu_wait_cycles <= perf_ifu_wait_cycles + 1;
`endif
            end
            
            IFU_WAIT_R: begin
                if (rvalid) begin
                    rready <= 1'b0;
                    rdata_out <= rdata;
                    rvalid_out <= 1'b1;  // 输出数据有效脉冲
                    ifu_state <= IFU_IDLE;
`ifdef SIMULATION
                    perf_ifu_fetch_cnt <= perf_ifu_fetch_cnt + 1;
`endif
                end
`ifdef SIMULATION
                perf_ifu_wait_cycles <= perf_ifu_wait_cycles + 1;
`endif
            end
            
            default: begin
                ifu_state <= IFU_IDLE;
            end
        endcase
    end
end

// ========== Debug Output (simulation only) ==========
// Note: Debug output disabled for performance. Uncomment for debugging.
// `ifdef SIMULATION
// always @(posedge clk) begin
//     if (!rst) begin
//         if (req && ifu_state == IFU_IDLE)
//             $display("[IFU_AXI @%0t] REQ addr=%h", $time, addr);
//         if (rvalid && rready)
//             $display("[IFU_AXI @%0t] RESP data=%h", $time, rdata);
//     end
// end
// `endif

endmodule