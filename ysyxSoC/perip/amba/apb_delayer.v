// APB延迟模块 - 用于校准访存延迟
// 通过在设备响应后延迟若干周期来模拟处理器和设备的频率差异
// 
// 设处理器频率为 f_cpu，设备频率为 f_dev（通常约100MHz）
// 频率比 r = f_cpu / f_dev
// 如果请求在设备中花费k个周期，处理器需要等待 c = k * r 个周期
//
// 为处理小数r，引入放大系数 s（取2的幂便于除法）
// 累加阶段：每周期加 r * s（截断为整数）
// 等待阶段：将累加值除以s后开始倒计时

module apb_delayer(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

  // ========== 参数配置 ==========
  // 频率比 r = CPU频率 / 设备频率
  // 假设CPU运行在500MHz，设备(SDRAM)运行在100MHz，则 r = 5
  // 可根据yosys-sta综合结果调整
  // 放大系数 s = 256 (2^8，便于移位除法)
  // r * s = 5 * 256 = 1280 (如果r=5.5，则 r*s = 1408)
  
  parameter R_TIMES_S = 1024;  // (r-1) * s = (5-1) * 256 = 1024
  parameter S_SHIFT = 8;       // log2(s) = 8，即 s = 256
  
  // ========== 状态定义 ==========
  localparam IDLE = 2'b00;        // 空闲状态
  localparam WAIT_DEV = 2'b01;    // 等待设备响应，同时累加计数器
  localparam DELAY = 2'b10;       // 延迟状态，倒计时
  
  reg [1:0] state;
  reg [31:0] counter;         // 累加/倒计时计数器
  reg [31:0] saved_prdata;    // 保存设备返回的数据
  reg        saved_pslverr;   // 保存设备返回的错误标志
  
  // ========== 透传信号（请求直接发送给设备）==========
  // 透明传输，避免引入额外延迟
  assign out_paddr   = in_paddr;
  assign out_psel    = (state == IDLE || state == WAIT_DEV) ? in_psel : 1'b0;
  assign out_penable = (state == IDLE || state == WAIT_DEV) ? in_penable : 1'b0;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  
  // ========== 上游响应信号 ==========
  // 只有在DELAY状态且计数器为0时才向上游返回ready
  assign in_pready  = (state == DELAY && counter == 0) ? 1'b1 : 1'b0;
  assign in_prdata  = saved_prdata;
  assign in_pslverr = saved_pslverr;
  
  // ========== 状态机 ==========
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      state <= IDLE;
      counter <= 32'h0;
      saved_prdata <= 32'h0;
      saved_pslverr <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          // 检测APB事务开始：psel && penable
          if (in_psel && in_penable) begin
            if (out_pready) begin
               // 设备在第一个周期就响应了
               saved_prdata <= out_prdata;
               saved_pslverr <= out_pslverr;
               // 累加 1 * (r-1) * s
               // 延迟周期 = (R_TIMES_S >> S_SHIFT) - 1
               // 注意：如果 R_TIMES_S 很小（r接近1），这里可能下溢，需额外处理
               // 但假设 r=5，则延迟为 4-1=3。总耗时 1(dev) + 3(wait) + 1(oh) = 5.
               counter <= (R_TIMES_S >> S_SHIFT) > 0 ? (R_TIMES_S >> S_SHIFT) - 1 : 0;
               state <= DELAY;
            end else begin
               state <= WAIT_DEV;
               counter <= R_TIMES_S;  // 第一个周期结束，累加 (r-1)*s
            end
          end
        end
        
        WAIT_DEV: begin
          // 等待设备响应，每周期累加 (r-1) * s
          if (out_pready) begin
            // 设备响应了
            saved_prdata <= out_prdata;
            saved_pslverr <= out_pslverr;
            // 当前周期也算，所以先累加再计算
            // 或者：counter 已经是 (k-1)*(r-1)*s。
            // 加上当前周期的 (r-1)*s -> k*(r-1)*s
            // 延迟 = (counter + R_TIMES_S) >> S_SHIFT - 1
            counter <= ((counter + R_TIMES_S) >> S_SHIFT) > 0 ? ((counter + R_TIMES_S) >> S_SHIFT) - 1 : 0;
            state <= DELAY;
          end else begin
            // 设备还未响应，继续累加
            counter <= counter + R_TIMES_S;
          end
        end
        
        DELAY: begin
          // 倒计时，每周期减1
          if (counter == 0) begin
            // 延迟结束，返回空闲状态
            state <= IDLE;
          end else begin
            counter <= counter - 1;
          end
        end
        
        default: state <= IDLE;
      endcase
    end
  end

`ifdef SIMULATION
  // ========== 仿真统计（可选）==========
  reg [63:0] perf_total_delay_cycles;  // 总延迟周期数
  reg [63:0] perf_transaction_cnt;     // APB事务数
  
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      perf_total_delay_cycles <= 64'h0;
      perf_transaction_cnt <= 64'h0;
    end else begin
      if (state == DELAY && counter > 0) begin
        perf_total_delay_cycles <= perf_total_delay_cycles + 1;
      end
      if (state == DELAY && counter == 0) begin
        perf_transaction_cnt <= perf_transaction_cnt + 1;
      end
    end
  end
`endif

endmodule
