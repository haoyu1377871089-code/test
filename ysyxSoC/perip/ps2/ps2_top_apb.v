module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

  // APB 接口始终就绪，无错误
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;

  // PS/2 时钟同步（3级同步器检测下降沿）
  reg [2:0] ps2_clk_sync;
  always @(posedge clock) begin
    if (reset)
      ps2_clk_sync <= 3'b111;
    else
      ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
  end
  wire ps2_clk_negedge = ps2_clk_sync[2] & ~ps2_clk_sync[1];

  // PS/2 数据同步
  reg [1:0] ps2_data_sync;
  always @(posedge clock) begin
    if (reset)
      ps2_data_sync <= 2'b11;
    else
      ps2_data_sync <= {ps2_data_sync[0], ps2_data};
  end
  wire ps2_data_in = ps2_data_sync[1];

  // 超时计数器 - 如果太长时间没有时钟边沿，重置接收状态
  // 假设系统时钟 25MHz，PS/2 时钟约 10-16kHz
  // 超时设为 ~2ms (50000 cycles @ 25MHz)
  reg [15:0] timeout_cnt;
  wire timeout = (timeout_cnt == 16'hFFFF);
  
  always @(posedge clock) begin
    if (reset)
      timeout_cnt <= 16'b0;
    else if (ps2_clk_negedge)
      timeout_cnt <= 16'b0;  // 有时钟边沿，重置计数器
    else if (!timeout)
      timeout_cnt <= timeout_cnt + 1'b1;
  end

  // PS/2 接收状态机
  // PS/2 帧格式: [START=0] [D0] [D1] [D2] [D3] [D4] [D5] [D6] [D7] [PARITY] [STOP=1]
  // 数据在 PS2_CLK 下降沿采样，LSB 先发送
  reg [7:0] data_reg;      // 数据移位寄存器
  reg [3:0] bit_count;     // 位计数器 (0-10)
  reg [7:0] rx_scancode;   // 接收到的扫描码
  reg       rx_valid;      // 扫描码接收完成脉冲
  reg       parity_bit;    // 奇偶校验位

  always @(posedge clock) begin
    if (reset) begin
      data_reg <= 8'b0;
      bit_count <= 4'b0;
      rx_scancode <= 8'b0;
      rx_valid <= 1'b0;
      parity_bit <= 1'b0;
    end else begin
      rx_valid <= 1'b0;  // 默认清除

      // 超时重置 - 接收不完整的帧时重新开始
      if (timeout && bit_count != 0) begin
        bit_count <= 4'b0;
        data_reg <= 8'b0;
      end
      // PS/2 时钟下降沿采样数据
      else if (ps2_clk_negedge) begin
        case (bit_count)
          4'd0: begin
            // Start bit - 应该是 0
            if (ps2_data_in == 1'b0) begin
              bit_count <= 4'd1;
            end
            // 如果不是 0，忽略这个边沿
          end
          4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: begin
            // Data bits D0-D7 (LSB first)
            // D0 在 bit_count=1 时采样，放入 data_reg[0]
            data_reg <= {ps2_data_in, data_reg[7:1]};
            bit_count <= bit_count + 1'b1;
          end
          4'd9: begin
            // Parity bit
            parity_bit <= ps2_data_in;
            bit_count <= 4'd10;
          end
          4'd10: begin
            // Stop bit - 应该是 1
            // 验证帧：stop=1 且奇校验正确
            if (ps2_data_in == 1'b1 && (^{data_reg, parity_bit}) == 1'b1) begin
              rx_scancode <= data_reg;
              rx_valid <= 1'b1;
            end
            bit_count <= 4'b0;
            data_reg <= 8'b0;
          end
          default: begin
            bit_count <= 4'b0;
          end
        endcase
      end
    end
  end

  // FIFO 缓冲区 (16 字节)
  reg [7:0] fifo [0:15];
  reg [3:0] fifo_wptr;
  reg [3:0] fifo_rptr;
  wire fifo_empty = (fifo_wptr == fifo_rptr);
  wire fifo_full = ((fifo_wptr + 1'b1) == fifo_rptr);

  // APB 读取操作检测
  wire apb_read_active = in_psel && in_penable && !in_pwrite && (in_paddr[2:0] == 3'b000);
  reg apb_read_done;
  
  always @(posedge clock) begin
    if (reset) begin
      fifo_wptr <= 4'b0;
      fifo_rptr <= 4'b0;
      apb_read_done <= 1'b0;
    end else begin
      // 写入 FIFO
      if (rx_valid && !fifo_full) begin
        fifo[fifo_wptr] <= rx_scancode;
        fifo_wptr <= fifo_wptr + 1'b1;
      end
      
      // 读取 FIFO
      if (apb_read_active) begin
        if (!apb_read_done && !fifo_empty) begin
          fifo_rptr <= fifo_rptr + 1'b1;
          apb_read_done <= 1'b1;
        end
      end else begin
        apb_read_done <= 1'b0;
      end
    end
  end

  // APB 读取逻辑
  reg [31:0] rdata;
  always @(*) begin
    case (in_paddr[2:0])
      3'b000: rdata = fifo_empty ? 32'b0 : {24'b0, fifo[fifo_rptr]};
      3'b100: rdata = {30'b0, fifo_full, fifo_empty};
      default: rdata = 32'b0;
    endcase
  end
  assign in_prdata = rdata;

endmodule
