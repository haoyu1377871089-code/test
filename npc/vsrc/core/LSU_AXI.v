`include "axi4_lite_interface.vh"

module LSU_AXI (
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
    // 临时计数器用于计算单次访存延迟
    reg [31:0] lsu_cycle_counter;
    reg        lsu_in_flight;           // 有访存请求在进行中
    reg        lsu_is_load;             // 当前是load操作
`endif

// ========= 数据存储器已禁用，使用外部PSRAM =========
// 原DMEM范围 0x80000000 - 0x800003FF (1KB) 现在通过AXI访问外部PSRAM
localparam DMEM_BASE  = 32'h8000_0000;
localparam DMEM_BYTES = 32'd1024; // 256 * 4 bytes
wire [31:0] dmem_word_index = ((addr - DMEM_BASE) >> 2);
wire [7:0]  dmem_idx        = dmem_word_index[7:0];
// 禁用内部DMEM，所有PSRAM地址都通过AXI访问
wire        in_dmem         = 1'b0; // (addr >= DMEM_BASE) && (addr < (DMEM_BASE + DMEM_BYTES));
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
`ifdef SIMULATION
    // 初始化性能计数器
    perf_lsu_load_cnt <= 64'h0;
    perf_lsu_store_cnt <= 64'h0;
    perf_lsu_load_cycles <= 64'h0;
    perf_lsu_store_cycles <= 64'h0;
    perf_lsu_stall_arb_cycles <= 64'h0;
    lsu_cycle_counter <= 32'h0;
    lsu_in_flight <= 1'b0;
    lsu_is_load <= 1'b0;
`endif
  end else begin
    // 第一级流水线：保存请求信息
    // 仅在发起新请求时更新地址，防止在等待总线响应期间地址变化
    if (req && !arvalid && !awvalid && !rvalid_out) begin
        addr_stage1 <= addr;
    end
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
      // AXI 读完成
      // 根据地址低2位对齐读数据 (RV32E 小端序)
      // addr_stage1 是上一拍保存的请求地址
      case (addr_stage1[1:0])
        2'b00: rdata_out <= rdata;
        2'b01: rdata_out <= {8'b0, rdata[31:8]};
        2'b10: rdata_out <= {16'b0, rdata[31:16]};
        2'b11: rdata_out <= {24'b0, rdata[31:24]};
      endcase
      rvalid_out <= 1'b1;
      rready <= 1'b0;
    end else begin
      rvalid_out <= 1'b0;
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
    
    // AXI4-Lite Control Logic
    // Check if idle (no pending transactions and no completion pulse active)
    if (!awvalid && !wvalid && !bready && !arvalid && !rready && !rvalid_out) begin
        // IDLE: Accept new request
        if (req && !in_dmem) begin
            if (wen) begin
                awaddr <= addr; awvalid <= 1'b1;
                wdata_axi <= wdata; wstrb <= wmask; wvalid <= 1'b1;
                bready <= 1'b1;
`ifdef SIMULATION
                perf_lsu_store_cnt <= perf_lsu_store_cnt + 1;
                lsu_in_flight <= 1'b1;
                lsu_is_load <= 1'b0;
                lsu_cycle_counter <= 32'h1;
`endif
            end else begin
                araddr <= addr; arvalid <= 1'b1;
                rready <= 1'b1;
`ifdef SIMULATION
                perf_lsu_load_cnt <= perf_lsu_load_cnt + 1;
                lsu_in_flight <= 1'b1;
                lsu_is_load <= 1'b1;
                lsu_cycle_counter <= 32'h1;
`endif
            end
        end
    end else begin
        // BUSY: Handle Handshakes
`ifdef SIMULATION
        // 访存进行中，计数周期
        if (lsu_in_flight) begin
            lsu_cycle_counter <= lsu_cycle_counter + 1;
        end
        // 等待仲裁统计
        if ((arvalid && !arready) || (awvalid && !awready)) begin
            perf_lsu_stall_arb_cycles <= perf_lsu_stall_arb_cycles + 1;
        end
`endif
        // Write Address
        if (awvalid && awready) awvalid <= 1'b0;
        // Write Data
        if (wvalid && wready) wvalid <= 1'b0;
        // Write Response
        if (bvalid && bready && !awvalid && !wvalid) begin
            bready <= 1'b0;
            rvalid_out <= 1'b1; // Write Done
`ifdef SIMULATION
            perf_lsu_store_cycles <= perf_lsu_store_cycles + lsu_cycle_counter;
            lsu_in_flight <= 1'b0;
`endif
        end
        
        // Read Address
        if (arvalid && arready) arvalid <= 1'b0;
        // Read Data
        if (rvalid && rready) begin
            rready <= 1'b0;
            // Align data based on the address used for the request
            case (araddr[1:0])
                2'b00: rdata_out <= rdata;
                2'b01: rdata_out <= {8'b0, rdata[31:8]};
                2'b10: rdata_out <= {16'b0, rdata[31:16]};
                2'b11: rdata_out <= {24'b0, rdata[31:24]};
            endcase
            rvalid_out <= 1'b1; // Read Done
`ifdef SIMULATION
            perf_lsu_load_cycles <= perf_lsu_load_cycles + lsu_cycle_counter;
            lsu_in_flight <= 1'b0;
`endif
        end else begin
            rvalid_out <= 1'b0;
        end
    end
  end
end

endmodule